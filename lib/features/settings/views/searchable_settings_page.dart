import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../../../core/widgets/error_boundary.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/themed_dialogs.dart';
import '../../../core/services/focus_management_service.dart';
import '../../../shared/widgets/improved_loading_states.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../core/models/user_settings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/utils/platform_utils.dart';

enum ThemeVariant { conduit }

// Settings search provider
final settingsSearchQueryProvider = StateProvider<String>((ref) => '');

// Setting item model
class SettingItem {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final String category;
  final List<String> searchTerms;
  final VoidCallback? onTap;
  final Widget? trailing;

  SettingItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.category,
    required this.searchTerms,
    this.onTap,
    this.trailing,
  });

  bool matchesSearch(String query) {
    final lowerQuery = query.toLowerCase();
    return title.toLowerCase().contains(lowerQuery) ||
        (subtitle?.toLowerCase().contains(lowerQuery) ?? false) ||
        category.toLowerCase().contains(lowerQuery) ||
        searchTerms.any((term) => term.toLowerCase().contains(lowerQuery));
  }
}

class SearchableSettingsPage extends ConsumerStatefulWidget {
  const SearchableSettingsPage({super.key});

  @override
  ConsumerState<SearchableSettingsPage> createState() =>
      _SearchableSettingsPageState();
}

class _SearchableSettingsPageState
    extends ConsumerState<SearchableSettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  late FocusNode _searchFocusNode;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusManagementService.registerFocusNode(
      'settings_search',
      debugLabel: 'Settings Search Field',
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    FocusManagementService.disposeFocusNode('settings_search');
    super.dispose();
  }

  List<SettingItem> _buildSettingItems(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    // Single Conduit theme variant in this refactor; kept provider for future use
    final userSettingsAsync = ref.watch(userSettingsProvider);
    final userSettings = userSettingsAsync.when(
      data: (data) => data,
      loading: () => null,
      error: (_, _) => null,
    );

    return [
      // Profile & Account
      SettingItem(
        id: 'profile',
        title: 'Profile',
        subtitle: 'Manage your account details',
        icon: Platform.isIOS
            ? CupertinoIcons.person_circle
            : Icons.account_circle,
        category: 'Profile & Account',
        searchTerms: ['account', 'user', 'name', 'email', 'avatar'],
        onTap: () => _navigateToProfile(context),
      ),
      SettingItem(
        id: 'server',
        title: 'Server Connection',
        subtitle: 'Manage Open WebUI servers',
        icon: Platform.isIOS ? CupertinoIcons.cloud : Icons.cloud,
        category: 'Profile & Account',
        searchTerms: ['server', 'connection', 'api', 'host', 'url'],
        onTap: () => _navigateToServerSettings(context),
      ),
      SettingItem(
        id: 'sign-out',
        title: 'Sign Out',
        subtitle: 'Sign out of your account',
        icon: Platform.isIOS ? CupertinoIcons.square_arrow_right : Icons.logout,
        category: 'Profile & Account',
        searchTerms: ['logout', 'signout', 'exit'],
        onTap: () => _handleSignOut(context, ref),
      ),

      // Appearance
      SettingItem(
        id: 'theme',
        title: 'Theme',
        subtitle: 'Choose light or dark theme',
        icon: Platform.isIOS ? CupertinoIcons.moon_circle : Icons.dark_mode,
        category: 'Appearance',
        searchTerms: ['dark', 'light', 'mode', 'appearance', 'color'],
        trailing: _buildThemeSelector(ref, themeMode),
      ),
      // Removed variant switching; Conduit brand theme is the single source of truth
      SettingItem(
        id: 'text-size',
        title: 'Text Size',
        subtitle: 'Adjust font size for better readability',
        icon: Platform.isIOS
            ? CupertinoIcons.textformat_size
            : Icons.text_fields,
        category: 'Appearance',
        searchTerms: ['font', 'size', 'text', 'readability', 'accessibility'],
        onTap: () => _showTextSizeDialog(context),
      ),

      // Chat & AI
      SettingItem(
        id: 'stream-responses',
        title: 'Stream Responses',
        subtitle: 'See responses as they\'re generated',
        icon: Platform.isIOS ? CupertinoIcons.bolt : Icons.flash_on,
        category: 'Chat & AI',
        searchTerms: ['stream', 'real-time', 'live', 'responses'],
        trailing: PlatformUtils.createSwitch(
          value: userSettings?.streamResponses ?? true,
          onChanged: (value) => _updateSetting(ref, 'streamResponses', value),
        ),
      ),
      SettingItem(
        id: 'save-conversations',
        title: 'Save Conversations',
        subtitle: 'Keep chat history between sessions',
        icon: Platform.isIOS ? CupertinoIcons.archivebox : Icons.save,
        category: 'Chat & AI',
        searchTerms: ['save', 'history', 'conversations', 'chat', 'archive'],
        trailing: PlatformUtils.createSwitch(
          value: userSettings?.saveConversations ?? true,
          onChanged: (value) => _updateSetting(ref, 'saveConversations', value),
        ),
      ),
      SettingItem(
        id: 'web-search',
        title: 'Web Search',
        subtitle: 'Allow AI to search the web for information',
        icon: Platform.isIOS ? CupertinoIcons.globe : Icons.public,
        category: 'Chat & AI',
        searchTerms: ['web', 'search', 'internet', 'browse', 'online'],
        trailing: Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            return settings.when(
              data: (userSettings) => PlatformUtils.createSwitch(
                value: userSettings.webSearchEnabled,
                onChanged: (value) =>
                    _updateSetting(ref, 'webSearchEnabled', value),
              ),
              loading: () =>
                  const ImprovedLoadingState(message: 'Loading setting...'),
              error: (error, stackTrace) => PlatformUtils.createSwitch(
                value: false,
                onChanged: (value) =>
                    _updateSetting(ref, 'webSearchEnabled', value),
              ),
            );
          },
        ),
      ),
      SettingItem(
        id: 'model-selection',
        title: 'Default Model',
        subtitle: 'Choose your preferred AI model',
        icon: Platform.isIOS ? CupertinoIcons.cube : Icons.psychology,
        category: 'Chat & AI',
        searchTerms: ['model', 'ai', 'gpt', 'conduit', 'llm'],
        onTap: () => _showModelSelector(context),
      ),

      // Privacy & Security
      SettingItem(
        id: 'clear-history',
        title: 'Clear Chat History',
        subtitle: 'Delete all conversations',
        icon: Platform.isIOS ? CupertinoIcons.trash : Icons.delete_outline,
        category: 'Privacy & Security',
        searchTerms: ['clear', 'delete', 'history', 'privacy', 'remove'],
        onTap: () => _showClearHistoryDialog(context, ref),
      ),
      SettingItem(
        id: 'export-data',
        title: 'Export Data',
        subtitle: 'Download your conversations',
        icon: Platform.isIOS
            ? CupertinoIcons.square_arrow_down
            : Icons.download,
        category: 'Privacy & Security',
        searchTerms: ['export', 'download', 'backup', 'data'],
        onTap: () => _handleExportData(context),
      ),

      // Accessibility
      SettingItem(
        id: 'reduce-motion',
        title: 'Reduce Motion',
        subtitle: 'Minimize animations',
        icon: Platform.isIOS ? CupertinoIcons.slowmo : Icons.animation,
        category: 'Accessibility',
        searchTerms: ['motion', 'animation', 'reduce', 'accessibility'],
        trailing: Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            return settings.when(
              data: (userSettings) => PlatformUtils.createSwitch(
                value: userSettings.reduceMotion,
                onChanged: (value) =>
                    _updateSetting(ref, 'reduceMotion', value),
              ),
              loading: () =>
                  const ImprovedLoadingState(message: 'Loading setting...'),
              error: (error, stackTrace) => PlatformUtils.createSwitch(
                value: false,
                onChanged: (value) =>
                    _updateSetting(ref, 'reduceMotion', value),
              ),
            );
          },
        ),
      ),
      SettingItem(
        id: 'haptic-feedback',
        title: 'Haptic Feedback',
        subtitle: 'Vibration feedback for actions',
        icon: Platform.isIOS ? CupertinoIcons.hand_draw : Icons.vibration,
        category: 'Accessibility',
        searchTerms: ['haptic', 'vibration', 'feedback', 'touch'],
        trailing: Consumer(
          builder: (context, ref, child) {
            final settings = ref.watch(userSettingsProvider);
            return settings.when(
              data: (userSettings) => PlatformUtils.createSwitch(
                value: userSettings.hapticFeedback,
                onChanged: (value) =>
                    _updateSetting(ref, 'hapticFeedback', value),
              ),
              loading: () =>
                  const ImprovedLoadingState(message: 'Loading setting...'),
              error: (error, stackTrace) => PlatformUtils.createSwitch(
                value: true,
                onChanged: (value) =>
                    _updateSetting(ref, 'hapticFeedback', value),
              ),
            );
          },
        ),
      ),

      // About
      SettingItem(
        id: 'version',
        title: 'App Version',
        subtitle: 'Conduit v1.0.0',
        icon: Platform.isIOS ? CupertinoIcons.info_circle : Icons.info_outline,
        category: 'About',
        searchTerms: ['version', 'about', 'info', 'conduit'],
        onTap: () => _showAboutDialog(context),
      ),
      SettingItem(
        id: 'help',
        title: 'Help & Support',
        subtitle: 'Get assistance and report issues',
        icon: Platform.isIOS
            ? CupertinoIcons.question_circle
            : Icons.help_outline,
        category: 'About',
        searchTerms: ['help', 'support', 'assistance', 'contact'],
        onTap: () => _navigateToHelp(context),
      ),
    ];
  }

  List<SettingItem> _getFilteredSettings(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(settingsSearchQueryProvider);
    final allSettings = _buildSettingItems(context, ref);

    if (searchQuery.isEmpty) {
      return allSettings;
    }

    return allSettings
        .where((item) => item.matchesSearch(searchQuery))
        .toList();
  }

  Map<String, List<SettingItem>> _groupSettingsByCategory(
    List<SettingItem> settings,
  ) {
    final grouped = <String, List<SettingItem>>{};

    for (final setting in settings) {
      grouped.putIfAbsent(setting.category, () => []).add(setting);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final filteredSettings = _getFilteredSettings(context, ref);
    final groupedSettings = _groupSettingsByCategory(filteredSettings);
    final categories = groupedSettings.keys.toList()..sort();

    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: Elevation.none,
          title: _isSearching
              ? _buildSearchBar()
              : Text(
                  'Settings',
                  style: TextStyle(
                    color: context.conduitTheme.textPrimary,
                    fontSize: AppTypography.headlineMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
          leading: ConduitIconButton(
            icon: Platform.isIOS ? CupertinoIcons.back : Icons.arrow_back,
            onPressed: () {
              if (_isSearching) {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  ref.read(settingsSearchQueryProvider.notifier).state = '';
                });
              } else {
                NavigationService.goBack();
              }
            },
          ),
          actions: [
            if (!_isSearching)
              ConduitIconButton(
                icon: Platform.isIOS ? CupertinoIcons.search : Icons.search,
                onPressed: () {
                  setState(() {
                    _isSearching = true;
                  });
                  _searchFocusNode.requestFocus();
                },
              ),
            const SizedBox(width: Spacing.sm),
          ],
        ),
        body: SafeArea(
          top: false,
          child: filteredSettings.isEmpty
              ? _buildEmptySearchResults()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final items = groupedSettings[category]!;

                    return _buildCategorySection(category, items);
                  },
                ),
        ),
      ), // Added closing parenthesis for ErrorBoundary
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      style: TextStyle(
        color: context.conduitTheme.textPrimary,
        fontSize: AppTypography.bodyLarge,
      ),
      decoration: InputDecoration(
        hintText: 'Search settings...',
        hintStyle: TextStyle(
          color: context.conduitTheme.inputPlaceholder,
          fontSize: AppTypography.bodyLarge,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      onChanged: (value) {
        ref.read(settingsSearchQueryProvider.notifier).state = value;
      },
    );
  }

  Widget _buildEmptySearchResults() {
    return ImprovedEmptyState(
      title: 'No settings found',
      subtitle: 'Try a different search term',
      icon: Platform.isIOS ? CupertinoIcons.search : Icons.search_off,
      showAnimation: true,
    );
  }

  Widget _buildCategorySection(String category, List<SettingItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.md,
            Spacing.md,
            Spacing.sm,
          ),
          child: Text(
            category,
            style: TextStyle(
              color: context.conduitTheme.textSecondary,
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.conduitTheme.surfaceBackground,
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
            border: Border.all(
              color: context.conduitTheme.dividerColor,
              width: 1,
            ),
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;

              return Column(
                children: [
                  _buildSettingTile(item),
                  if (!isLast)
                    Divider(
                      height: 1,
                      color: context.conduitTheme.dividerColor,
                      indent: 56,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile(SettingItem item) {
    final searchQuery = ref.watch(settingsSearchQueryProvider);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.conduitTheme.surfaceBackground,
                  borderRadius: BorderRadius.circular(AppBorderRadius.sm),
                ),
                child: Icon(
                  item.icon,
                  color: context.conduitTheme.iconSecondary,
                  size: IconSize.md,
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightSearchText(item.title, searchQuery),
                    if (item.subtitle != null) ...[
                      const SizedBox(height: Spacing.xxs),
                      _highlightSearchText(
                        item.subtitle!,
                        searchQuery,
                        style: TextStyle(
                          color: context.conduitTheme.textSecondary,
                          fontSize: AppTypography.bodySmall,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.trailing != null) ...[
                const SizedBox(width: Spacing.sm),
                item.trailing!,
              ] else if (item.onTap != null)
                Icon(
                  Platform.isIOS
                      ? CupertinoIcons.chevron_forward
                      : Icons.chevron_right,
                  color: context.conduitTheme.iconSecondary,
                  size: IconSize.md,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightSearchText(String text, String query, {TextStyle? style}) {
    if (query.isEmpty) {
      return Text(
        text,
        style:
            style ??
            TextStyle(
              color: context.conduitTheme.textPrimary,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w500,
            ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) {
      return Text(text, style: style);
    }

    final before = text.substring(0, index);
    final match = text.substring(index, index + query.length);
    final after = text.substring(index + query.length);

    return RichText(
      text: TextSpan(
        style:
            style ??
            TextStyle(
              color: context.conduitTheme.textPrimary,
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w500,
            ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              backgroundColor: context.conduitTheme.buttonPrimary.withValues(
                alpha: 0.3,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(WidgetRef ref, ThemeMode themeMode) {
    return CupertinoSlidingSegmentedControl<ThemeMode>(
      groupValue: themeMode,
      children: const {
        ThemeMode.light: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Light',
            style: TextStyle(fontSize: AppTypography.bodySmall),
          ),
        ),
        ThemeMode.dark: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Dark',
            style: TextStyle(fontSize: AppTypography.bodySmall),
          ),
        ),
        ThemeMode.system: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Auto',
            style: TextStyle(fontSize: AppTypography.bodySmall),
          ),
        ),
      },
      onValueChanged: (value) {
        if (value != null) {
          ref.read(themeModeProvider.notifier).setTheme(value);
        }
      },
    );
  }

  // Theme variant state removed; single Conduit theme in use

  void _updateSetting(WidgetRef ref, String key, dynamic value) async {
    try {
      final currentSettings = await ref.read(userSettingsProvider.future);

      // Create updated settings based on the key
      UserSettings updatedSettings;
      switch (key) {
        case 'webSearchEnabled':
          updatedSettings = currentSettings.copyWith(
            webSearchEnabled: value as bool,
          );
          break;
        case 'reduceMotion':
          updatedSettings = currentSettings.copyWith(
            reduceMotion: value as bool,
          );
          break;
        case 'hapticFeedback':
          updatedSettings = currentSettings.copyWith(
            hapticFeedback: value as bool,
          );
          break;
        case 'streamResponses':
          updatedSettings = currentSettings.copyWith(
            streamResponses: value as bool,
          );
          break;
        case 'saveConversations':
          updatedSettings = currentSettings.copyWith(
            saveConversations: value as bool,
          );
          break;
        case 'showReadReceipts':
          updatedSettings = currentSettings.copyWith(
            showReadReceipts: value as bool,
          );
          break;
        case 'enableNotifications':
          updatedSettings = currentSettings.copyWith(
            enableNotifications: value as bool,
          );
          break;
        case 'enableSounds':
          updatedSettings = currentSettings.copyWith(
            enableSounds: value as bool,
          );
          break;
        case 'shareUsageData':
          updatedSettings = currentSettings.copyWith(
            shareUsageData: value as bool,
          );
          break;
        case 'temperature':
          updatedSettings = currentSettings.copyWith(
            temperature: value as double,
          );
          break;
        case 'maxTokens':
          updatedSettings = currentSettings.copyWith(maxTokens: value as int);
          break;
        case 'fontSize':
          updatedSettings = currentSettings.copyWith(fontSize: value as double);
          break;
        case 'theme':
          updatedSettings = currentSettings.copyWith(theme: value as String);
          break;
        case 'density':
          updatedSettings = currentSettings.copyWith(density: value as String);
          break;
        case 'language':
          updatedSettings = currentSettings.copyWith(language: value as String);
          break;
        default:
          // Handle custom settings
          final customSettings = Map<String, dynamic>.from(
            currentSettings.customSettings,
          );
          customSettings[key] = value;
          updatedSettings = currentSettings.copyWith(
            customSettings: customSettings,
          );
      }

      // Update settings on server
      final api = ref.read(apiServiceProvider);
      if (api != null) {
        await api.updateUserSettings(updatedSettings.toJson());

        // Invalidate the provider to refresh the UI
        ref.invalidate(userSettingsProvider);

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Setting updated'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update setting: $e'),
            backgroundColor: context.conduitTheme.error,
          ),
        );
      }
    }
  }

  void _navigateToProfile(BuildContext context) {
    // TODO: Navigate to profile page
  }

  void _navigateToServerSettings(BuildContext context) {
    NavigationService.navigateTo('/server-connection');
  }

  void _handleSignOut(BuildContext context, WidgetRef ref) {
    // ignore: unawaited_futures
    ThemedDialogs.confirm(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmText: 'Sign Out',
    ).then((confirmed) {
      if (confirmed) {
        // TODO: Implement proper logout functionality when auth service is available
        // ref.read(authServiceProvider.notifier).logout();
        NavigationService.navigateTo('/login', clearStack: true);
      }
    });
  }

  void _showTextSizeDialog(BuildContext context) {
    // TODO: Implement text size adjustment dialog
  }

  void _showModelSelector(BuildContext context) {
    // TODO: Implement model selection dialog
  }

  void _showClearHistoryDialog(BuildContext context, WidgetRef ref) {
    // TODO: Implement clear history dialog
  }

  void _handleExportData(BuildContext context) {
    // TODO: Implement data export
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Conduit',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2024 Conduit Team',
    );
  }

  void _navigateToHelp(BuildContext context) {
    // TODO: Navigate to help page
  }
}
