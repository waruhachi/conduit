import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/server_config.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/input_validation_service.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../shared/services/brand_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../core/auth/auth_state_manager.dart';
import '../../chat/views/chat_page.dart';

class ConnectAndSignInPage extends ConsumerStatefulWidget {
  const ConnectAndSignInPage({super.key});

  @override
  ConsumerState<ConnectAndSignInPage> createState() =>
      _ConnectAndSignInPageState();
}

class _ConnectAndSignInPageState extends ConsumerState<ConnectAndSignInPage> {
  final _formKey = GlobalKey<FormState>();

  // Server controls
  final TextEditingController _urlController = TextEditingController();
  String? _connectionError;

  // Auth controls
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _loginError;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _prefillFromState();
    _loadSavedCredentials();
  }

  Future<void> _prefillFromState() async {
    final activeServer = await ref.read(activeServerProvider.future);
    if (activeServer != null) {
      _urlController.text = activeServer.url;
    }
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(optimizedStorageServiceProvider);
    final savedCredentials = await storage.getSavedCredentials();
    if (savedCredentials != null) {
      setState(() {
        _usernameController.text = savedCredentials['username'] ?? '';
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<bool> _connectToServer() async {
    if (!_formKey.currentState!.validate()) return false;

    setState(() {
      _connectionError = null;
    });

    try {
      String url = _urlController.text.trim();
      if (url.isEmpty) throw Exception('URL cannot be empty');
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'http://$url';
      }
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }

      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw Exception('Invalid URL format. Please check your input.');
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        throw Exception('Only HTTP and HTTPS protocols are supported.');
      }

      final tempConfig = ServerConfig(
        id: const Uuid().v4(),
        name: _deriveServerNameFromUrl(url),
        url: url,
        isActive: true,
      );

      final api = ApiService(serverConfig: tempConfig);
      final isHealthy = await api.checkHealth();
      if (!isHealthy) {
        throw Exception('This does not appear to be an Open-WebUI server.');
      }

      await _saveServerConfig(tempConfig);
      // Success
      return true;
    } catch (e) {
      setState(() {
        _connectionError = _formatConnectionError(e.toString());
      });
      return false;
    } finally {
      // no-op
    }
  }

  Future<void> _saveServerConfig(ServerConfig config) async {
    final storage = ref.read(optimizedStorageServiceProvider);
    await storage.saveServerConfigs([config]);
    await storage.setActiveServerId(config.id);
    ref.invalidate(serverConfigsProvider);
    ref.invalidate(activeServerProvider);
  }

  String _deriveServerNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    return 'Server';
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loginError = null;
    });

    try {
      final authManager = ref.read(authStateManagerProvider.notifier);
      final success = await authManager.login(
        _usernameController.text.trim(),
        _passwordController.text,
        rememberCredentials: true,
      );
      if (!success) {
        final authState = ref.read(authStateManagerProvider);
        throw Exception(authState.error ?? 'Login failed');
      }
    } catch (e) {
      setState(() {
        _loginError = _formatLoginError(e.toString());
      });
    } finally {
      // no-op
    }
  }

  Future<void> _connectAndSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _connectionError = null;
      _loginError = null;
    });

    try {
      final connected = await _connectToServer();
      if (!connected) return;
      // Wait for providers to reflect the new active server and API service
      await ref.read(activeServerProvider.future);
      final apiReady = await _waitForApiService();
      if (!apiReady) {
        setState(() {
          _connectionError = 'Setting up the connection... Please try again.';
        });
        return;
      }
      await _signIn();
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<bool> _waitForApiService({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final api = ref.read(apiServiceProvider);
      if (api != null) return true;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return ref.read(apiServiceProvider) != null;
  }

  String _formatConnectionError(String error) {
    if (error.contains('SocketException')) {
      return 'We couldn\'t reach the server. Check your connection and that the server is running.';
    } else if (error.contains('timeout')) {
      return 'Connection timed out. The server might be busy or blocked by a firewall.';
    } else if (error.contains('Invalid URL format')) {
      return error.replaceFirst('Exception: ', '');
    } else if (error.contains('Missing protocol')) {
      return 'Include http:// or https:// (e.g., http://192.168.1.10:3000).';
    } else if (error.contains('Only HTTP and HTTPS')) {
      return 'Use http:// or https:// only.';
    }
    return 'Couldn\'t connect. Double-check the address and try again.';
  }

  String _formatLoginError(String error) {
    if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Invalid username or password. Please try again.';
    } else if (error.contains('redirect')) {
      return 'The server is redirecting requests. Check your server\'s HTTPS configuration.';
    } else if (error.contains('SocketException')) {
      return 'Unable to connect to server. Please check your connection.';
    } else if (error.contains('timeout')) {
      return 'The request timed out. Please try again.';
    }
    return 'We couldn\'t sign you in. Check your credentials and server settings.';
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final activeServerAsync = ref.watch(activeServerProvider);
    final reviewerMode = ref.watch(reviewerModeProvider);

    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.pagePadding),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GestureDetector(
                            onLongPress: () async {
                              HapticFeedback.mediumImpact();
                              await ref
                                  .read(reviewerModeProvider.notifier)
                                  .toggle();
                              if (!mounted) return;
                              final enabled = ref.read(reviewerModeProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    enabled
                                        ? 'Reviewer Mode enabled: Demo without server'
                                        : 'Reviewer Mode disabled',
                                  ),
                                ),
                              );
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                BrandService.createBrandIcon(
                                  size: 100,
                                  useGradient: true,
                                  addShadow: true,
                                ),
                                if (reviewerMode)
                                  Positioned(
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.conduitTheme.warning
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: context.conduitTheme.warning,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        'Reviewer Mode',
                                        style: TextStyle(
                                          color: context.conduitTheme.warning,
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          )
                          .animate()
                          .scale(
                            duration: AnimationDuration.pageTransition,
                            curve: Curves.easeOutBack,
                          )
                          .then()
                          .shimmer(duration: AnimationDuration.typingIndicator),

                      const SizedBox(height: Spacing.sectionGap),

                      Text(
                        'Connect and sign in',
                        textAlign: TextAlign.center,
                        style: context.conduitTheme.headingLarge?.copyWith(
                          color: context.conduitTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ).animate().fadeIn(
                        duration: AnimationDuration.pageTransition,
                        delay: AnimationDuration.microInteraction,
                      ),

                      const SizedBox(height: Spacing.comfortable),

                      if (reviewerMode) ...[
                        ConduitButton(
                          text: 'Enter Reviewer Demo',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const ChatPage(),
                              ),
                            );
                          },
                          isSecondary: true,
                          isFullWidth: true,
                        ),
                        const SizedBox(height: Spacing.xs),
                        Text(
                          'Demo mode: explore the app without a server. Some features are simulated.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.conduitTheme.textSecondary,
                            fontSize: AppTypography.bodySmall,
                          ),
                        ),

                        const SizedBox(height: Spacing.sectionGap),
                      ],

                      // Card container for form content
                      ConduitCard(
                        isElevated: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Step 1: Server
                            _SectionHeader(
                              icon: isIOS
                                  ? CupertinoIcons.globe
                                  : Icons.language,
                              title: 'Server',
                              subtitle: null,
                            ),

                            const SizedBox(height: Spacing.sm),

                            AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AccessibleFormField(
                                    label: 'Server address',
                                    hint: 'https://server',
                                    controller: _urlController,
                                    validator: InputValidationService.combine([
                                      InputValidationService.validateRequired,
                                      (value) =>
                                          InputValidationService.validateUrl(
                                            value,
                                            required: true,
                                          ),
                                    ]),
                                    keyboardType: TextInputType.url,
                                    semanticLabel:
                                        'Enter your server URL or IP address',
                                    onSubmitted: (_) => _connectAndSignIn(),
                                    prefixIcon: Icon(
                                      isIOS
                                          ? CupertinoIcons.globe
                                          : Icons.public,
                                      color: context.conduitTheme.iconSecondary,
                                    ),
                                    autofillHints: const [AutofillHints.url],
                                  ).animate().slideX(
                                    begin: -0.08,
                                    duration: AnimationDuration.messageSlide,
                                    delay: AnimationDuration.microInteraction,
                                    curve: Curves.easeOutCubic,
                                  ),

                                  if (_connectionError != null) ...[
                                    const SizedBox(height: Spacing.sm),
                                    _InlineMessage(
                                      message: _connectionError!,
                                      isError: true,
                                    ).animate().slideX(
                                      begin: 0.08,
                                      duration: AnimationDuration.messageSlide,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ],

                                  const SizedBox(height: Spacing.sectionGap),

                                  // Step 2: Sign in
                                  _SectionHeader(
                                    icon: isIOS
                                        ? CupertinoIcons.lock
                                        : Icons.lock_outline,
                                    title: 'Sign in',
                                    subtitle: null,
                                  ),

                                  const SizedBox(height: Spacing.sm),

                                  activeServerAsync.maybeWhen(
                                    data: (server) => server != null
                                        ? Row(
                                            children: [
                                              Icon(
                                                isIOS
                                                    ? CupertinoIcons.link
                                                    : Icons.link_outlined,
                                                size: IconSize.small,
                                                color: context
                                                    .conduitTheme
                                                    .iconSecondary,
                                              ),
                                              const SizedBox(width: Spacing.xs),
                                              Expanded(
                                                child: Text(
                                                  server.url,
                                                  textAlign: TextAlign.left,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: context
                                                      .conduitTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: context
                                                            .conduitTheme
                                                            .textSecondary,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : const SizedBox.shrink(),
                                    orElse: () => const SizedBox.shrink(),
                                  ),

                                  const SizedBox(height: Spacing.sm),

                                  AccessibleFormField(
                                    label: 'Username or email',
                                    hint: null,
                                    controller: _usernameController,
                                    validator: InputValidationService.combine([
                                      InputValidationService.validateRequired,
                                      (value) =>
                                          InputValidationService.validateEmailOrUsername(
                                            value,
                                          ),
                                    ]),
                                    keyboardType: TextInputType.emailAddress,
                                    semanticLabel:
                                        'Enter your username or email',
                                    prefixIcon: Icon(
                                      isIOS
                                          ? CupertinoIcons.person
                                          : Icons.person_outline,
                                      color: context.conduitTheme.iconSecondary,
                                    ),
                                    autofillHints: const [
                                      AutofillHints.username,
                                      AutofillHints.email,
                                    ],
                                  ),

                                  const SizedBox(height: Spacing.comfortable),

                                  AccessibleFormField(
                                    label: 'Password',
                                    hint: null,
                                    controller: _passwordController,
                                    validator: InputValidationService.combine([
                                      InputValidationService.validateRequired,
                                      (value) =>
                                          InputValidationService.validateMinLength(
                                            value,
                                            1,
                                            fieldName: 'Password',
                                          ),
                                    ]),
                                    obscureText: _obscurePassword,
                                    semanticLabel: 'Enter your password',
                                    prefixIcon: Icon(
                                      isIOS
                                          ? CupertinoIcons.lock
                                          : Icons.lock_outline,
                                      color: context.conduitTheme.iconSecondary,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? (isIOS
                                                  ? CupertinoIcons.eye_slash
                                                  : Icons.visibility_off)
                                            : (isIOS
                                                  ? CupertinoIcons.eye
                                                  : Icons.visibility),
                                        color:
                                            context.conduitTheme.iconSecondary,
                                      ),
                                      onPressed: () => setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      }),
                                    ),
                                    onSubmitted: (_) => _connectAndSignIn(),
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                  ),

                                  if (_loginError != null) ...[
                                    const SizedBox(height: Spacing.sm),
                                    _InlineMessage(
                                      message: _loginError!,
                                      isError: true,
                                    ),
                                  ],

                                  const SizedBox(height: Spacing.md),

                                  ConduitButton(
                                    text: 'Continue',
                                    onPressed: _isSubmitting
                                        ? null
                                        : _connectAndSignIn,
                                    isLoading: _isSubmitting,
                                    isFullWidth: true,
                                  ).animate().scale(
                                    duration: AnimationDuration.buttonPress,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: context.conduitTheme.iconPrimary),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.conduitTheme.headingSmall?.copyWith(
                  color: context.conduitTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.conduitTheme.bodySmall?.copyWith(
                    color: context.conduitTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const _InlineMessage({required this.message, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final isIOS = Platform.isIOS;
    final color = isError
        ? context.conduitTheme.error
        : context.conduitTheme.success;
    final bg = isError
        ? context.conduitTheme.errorBackground
        : context.conduitTheme.successBackground;
    final icon = isError
        ? (isIOS
              ? CupertinoIcons.exclamationmark_circle_fill
              : Icons.error_outline)
        : (isIOS ? CupertinoIcons.check_mark_circled : Icons.check_circle);

    return Container(
      padding: const EdgeInsets.all(Spacing.cardPadding),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppBorderRadius.card),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: BorderWidth.regular,
        ),
        boxShadow: ConduitShadows.low,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: IconSize.medium),
          const SizedBox(width: Spacing.comfortable),
          Expanded(
            child: Text(
              message,
              style: context.conduitTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

// removed unused _ButtonProgress; ConduitButton provides built-in loading state
