import 'package:flutter/material.dart';
import '../../../shared/theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/improved_loading_states.dart';

import '../../../shared/utils/ui_utils.dart';
import '../../../shared/widgets/sheet_handle.dart';
import 'package:conduit/l10n/app_localizations.dart';

/// Files page for managing documents and uploads
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage>
    with TickerProviderStateMixin {
  int _selectedTab = 0;
  late AnimationController _tabAnimationController;
  late AnimationController _contentAnimationController;

  @override
  void initState() {
    super.initState();
    _tabAnimationController = AnimationController(
      duration: AnimationDuration.microInteraction,
      vsync: this,
    );
    _contentAnimationController = AnimationController(
      duration: AnimationDuration.pageTransition,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabAnimationController.dispose();
    _contentAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            // Enhanced tab selector with animations
            _buildTabSelector().animate().fadeIn(
              duration: AnimationDuration.fast,
              delay: AnimationDelay.short,
            ),

            // Animated content
            Expanded(
              child: AnimatedSwitcher(
                duration: AnimationDuration.pageTransition,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: AnimationCurves.pageTransition,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                child: _selectedTab == 0
                    ? _buildRecentFiles()
                    : _buildKnowledgeBase(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: context.conduitTheme.surfaceBackground,
      elevation: Elevation.none,
      automaticallyImplyLeading: false,
      toolbarHeight: TouchTarget.appBar,
      titleSpacing: 0.0,
      leading: IconButton(
        icon: Icon(
          UiUtils.platformIcon(
            ios: CupertinoIcons.back,
            android: Icons.arrow_back,
          ),
          color: context.conduitTheme.textPrimary,
          size: IconSize.button,
        ),
        onPressed: () => NavigationService.goBack(),
        tooltip: AppLocalizations.of(context)!.back,
      ),
      title: Text(
        AppLocalizations.of(context)!.workspace,
        style: AppTypography.headlineSmallStyle.copyWith(
          color: context.conduitTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      centerTitle: true,
      actions: [
        // Enhanced upload button with proper touch target
        Container(
          width: TouchTarget.iconButton,
          height: TouchTarget.iconButton,
          margin: const EdgeInsets.only(right: Spacing.screenPadding),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppBorderRadius.button),
              onTap: _showUploadOptions,
              child: Icon(
                UiUtils.addIcon,
                color: context.conduitTheme.iconPrimary,
                size: IconSize.button,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.pagePadding,
        vertical: Spacing.sm,
      ),
      padding: const EdgeInsets.all(Spacing.xs),
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: context.conduitTheme.cardBorder,
          width: BorderWidth.thin,
        ),
        boxShadow: ConduitShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              index: 0,
              label: AppLocalizations.of(context)!.recentFiles,
              isSelected: _selectedTab == 0,
            ),
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: _buildTabButton(
              index: 1,
              label: AppLocalizations.of(context)!.knowledgeBase,
              isSelected: _selectedTab == 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required int index,
    required String label,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTab = index);
        _tabAnimationController.forward(from: 0);
        _contentAnimationController.forward(from: 0);
      },
      child: AnimatedContainer(
        duration: AnimationDuration.microInteraction,
        curve: AnimationCurves.buttonPress,
        padding: const EdgeInsets.symmetric(
          vertical: Spacing.buttonPadding,
          horizontal: Spacing.md,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.surfaceBackground.withValues(
                  alpha: Alpha.hover,
                ),
          borderRadius: BorderRadius.circular(AppBorderRadius.button),
          boxShadow: isSelected ? ConduitShadows.button : null,
        ),
        child: Text(
          label,
          style: context.conduitTheme.label?.copyWith(
            color: isSelected
                ? context.conduitTheme.textInverse
                : context.conduitTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildRecentFiles() {
    return Container(
      key: const ValueKey('recent_files'),
      padding: const EdgeInsets.all(Spacing.pagePadding),
      child: ImprovedEmptyState(
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.doc,
          android: Icons.description_outlined,
        ),
        title: AppLocalizations.of(context)!.noFilesYet,
        subtitle: AppLocalizations.of(context)!.uploadDocsPrompt,
        onAction: _showUploadOptions,
        actionLabel: AppLocalizations.of(context)!.uploadFirstFile,
        showAnimation: true,
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.messageAppear,
      delay: AnimationDelay.short,
    );
  }

  Widget _buildKnowledgeBase() {
    return Container(
      key: const ValueKey('knowledge_base'),
      padding: const EdgeInsets.all(Spacing.pagePadding),
      child: ImprovedEmptyState(
        icon: UiUtils.platformIcon(
          ios: CupertinoIcons.book,
          android: Icons.library_books,
        ),
        title: AppLocalizations.of(context)!.knowledgeBaseEmpty,
        subtitle: AppLocalizations.of(context)!.createCollectionsPrompt,
        onAction: _showKnowledgeBaseOptions,
        actionLabel: 'Create knowledge base',
        showAnimation: true,
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.messageAppear,
      delay: AnimationDelay.short,
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildUploadModal(),
    );
  }

  Widget _buildUploadModal() {
    return Container(
      decoration: BoxDecoration(
        color: context.conduitTheme.surfaceBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppBorderRadius.modal),
          topRight: Radius.circular(AppBorderRadius.modal),
        ),
        boxShadow: ConduitShadows.modal,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar (standardized)
            const SheetHandle(),

            // Header with enhanced typography
            Padding(
              padding: const EdgeInsets.all(Spacing.modalPadding),
              child: Text(
                AppLocalizations.of(context)!.uploadFileTitle,
                style: context.conduitTheme.headingSmall?.copyWith(
                  color: context.conduitTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Enhanced upload options
            _buildUploadOption(
              icon: UiUtils.platformIcon(
                ios: CupertinoIcons.camera,
                android: Icons.camera_alt,
              ),
              title: AppLocalizations.of(context)!.takePhoto,
              subtitle: AppLocalizations.of(context)!.captureDocumentOrImage,
              onTap: () => _handleUploadOption('camera'),
            ),
            _buildUploadOption(
              icon: UiUtils.platformIcon(
                ios: CupertinoIcons.photo,
                android: Icons.photo_library,
              ),
              title: AppLocalizations.of(context)!.chooseFromGallery,
              subtitle: AppLocalizations.of(context)!.chooseFromGallery,
              onTap: () => _handleUploadOption('gallery'),
            ),
            _buildUploadOption(
              icon: UiUtils.platformIcon(
                ios: CupertinoIcons.doc,
                android: Icons.description,
              ),
              title: AppLocalizations.of(context)!.document,
              subtitle: AppLocalizations.of(context)!.documentHint,
              onTap: () => _handleUploadOption('document'),
            ),

            const SizedBox(height: Spacing.modalPadding),
          ],
        ),
      ),
    ).animate().slide(
      duration: AnimationDuration.modalPresentation,
      curve: AnimationCurves.modalPresentation,
      begin: const Offset(0, 1),
      end: Offset.zero,
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: Spacing.modalPadding,
        vertical: Spacing.xs,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppBorderRadius.card),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Spacing.listItemPadding),
            decoration: BoxDecoration(
              color: context.conduitTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppBorderRadius.card),
              border: Border.all(
                color: context.conduitTheme.cardBorder,
                width: BorderWidth.thin,
              ),
            ),
            child: Row(
              children: [
                // Enhanced icon container
                Container(
                  width: IconSize.avatar,
                  height: IconSize.avatar,
                  decoration: BoxDecoration(
                    color: context.conduitTheme.buttonPrimary.withValues(
                      alpha: Alpha.highlight,
                    ),
                    borderRadius: BorderRadius.circular(AppBorderRadius.avatar),
                  ),
                  child: Icon(
                    icon,
                    color: context.conduitTheme.buttonPrimary,
                    size: IconSize.medium,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Enhanced text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.conduitTheme.bodyLarge?.copyWith(
                          color: context.conduitTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        subtitle,
                        style: context.conduitTheme.caption?.copyWith(
                          color: context.conduitTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  UiUtils.platformIcon(
                    ios: CupertinoIcons.chevron_right,
                    android: Icons.chevron_right,
                  ),
                  color: context.conduitTheme.iconSecondary,
                  size: IconSize.small,
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
      duration: AnimationDuration.fast,
      delay: AnimationDelay.staggeredDelay,
    );
  }

  void _handleUploadOption(String type) {
    NavigationService.goBack();
    UiUtils.showMessage(
      context,
      AppLocalizations.of(context)!.fileUploadComingSoon(type),
    );
  }

  void _showKnowledgeBaseOptions() {
    UiUtils.showMessage(
      context,
      AppLocalizations.of(context)!.kbCreationComingSoon,
    );
  }
}
