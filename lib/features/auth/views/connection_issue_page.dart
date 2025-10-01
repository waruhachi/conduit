import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/server_config.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/navigation_service.dart';
import '../../../core/widgets/error_boundary.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../providers/unified_auth_providers.dart';

class ConnectionIssuePage extends ConsumerStatefulWidget {
  const ConnectionIssuePage({super.key});

  @override
  ConsumerState<ConnectionIssuePage> createState() =>
      _ConnectionIssuePageState();
}

class _ConnectionIssuePageState extends ConsumerState<ConnectionIssuePage> {
  bool _isRetrying = false;
  bool _isLoggingOut = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final connectivityAsync = ref.watch(connectivityStatusProvider);
    final connectivity = connectivityAsync.asData?.value;
    final activeServerAsync = ref.watch(activeServerProvider);
    final activeServer = activeServerAsync.asData?.value;

    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.pagePadding,
              vertical: Spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConduitIconButton(
                    icon: Platform.isIOS
                        ? CupertinoIcons.gear_alt_fill
                        : Icons.settings_ethernet,
                    onPressed: () => context.go(Routes.serverConnection),
                    tooltip: l10n.backToServerSetup,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(context, l10n, connectivity),
                          if (activeServer != null) ...[
                            const SizedBox(height: Spacing.sm),
                            _buildServerDetails(context, activeServer),
                          ],
                          const SizedBox(height: Spacing.md),
                          Text(
                            l10n.connectionIssueSubtitle,
                            textAlign: TextAlign.center,
                            style: context.conduitTheme.bodyMedium?.copyWith(
                              color: context.conduitTheme.textSecondary,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildActions(context, l10n),
                if (_statusMessage != null) ...[
                  const SizedBox(height: Spacing.sm),
                  _buildStatusMessage(context, _statusMessage!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations l10n,
    ConnectivityStatus? connectivity,
  ) {
    final iconColor = context.conduitTheme.error;
    final statusText = _statusLabel(connectivity, l10n);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.conduitTheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            Platform.isIOS
                ? CupertinoIcons.wifi_exclamationmark
                : Icons.wifi_off_rounded,
            color: iconColor,
            size: 34,
          ),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          l10n.connectionIssueTitle,
          textAlign: TextAlign.center,
          style: context.conduitTheme.headingMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.conduitTheme.textPrimary,
          ),
        ),
        if (statusText != null) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: context.conduitTheme.bodySmall?.copyWith(
              color: context.conduitTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildServerDetails(BuildContext context, ServerConfig server) {
    final host = _resolveHost(server);

    return Column(
      children: [
        Text(
          host,
          textAlign: TextAlign.center,
          style: context.conduitTheme.bodyMedium?.copyWith(
            color: context.conduitTheme.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          server.url,
          textAlign: TextAlign.center,
          style: context.conduitTheme.bodySmall?.copyWith(
            color: context.conduitTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConduitButton(
            text: l10n.retry,
            onPressed: _isRetrying || _isLoggingOut ? null : () => _retry(l10n),
            isLoading: _isRetrying,
            icon: Platform.isIOS
                ? CupertinoIcons.refresh
                : Icons.refresh_rounded,
            isFullWidth: true,
          ),
          const SizedBox(height: Spacing.sm),
          ConduitButton(
            text: l10n.signOut,
            onPressed: _isRetrying || _isLoggingOut
                ? null
                : () => _logout(l10n),
            isLoading: _isLoggingOut,
            isSecondary: true,
            icon: Platform.isIOS
                ? CupertinoIcons.arrow_turn_up_left
                : Icons.logout,
            isFullWidth: true,
            isCompact: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.conduitTheme.bodySmall?.copyWith(
          color: context.conduitTheme.textSecondary,
        ),
      ),
    );
  }

  Future<void> _retry(AppLocalizations l10n) async {
    setState(() {
      _isRetrying = true;
      _statusMessage = null;
    });

    try {
      final service = ref.read(connectivityServiceProvider);
      final isOnline = await service.checkConnectivity();

      if (!mounted) return;

      if (isOnline) {
        await ref.read(authActionsProvider).refresh();
      } else {
        setState(() {
          _statusMessage = l10n.stillOfflineMessage;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = l10n.couldNotConnectGeneric;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  Future<void> _logout(AppLocalizations l10n) async {
    setState(() {
      _isLoggingOut = true;
      _statusMessage = null;
    });

    try {
      await ref.read(authActionsProvider).logout();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = l10n.couldNotConnectGeneric;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  String _resolveHost(ServerConfig? config) {
    final url = config?.url;
    if (url == null || url.isEmpty) {
      return 'Open WebUI';
    }

    try {
      final uri = Uri.parse(url);
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
      return url;
    } catch (_) {
      return url;
    }
  }

  String? _statusLabel(ConnectivityStatus? status, AppLocalizations l10n) {
    switch (status) {
      case ConnectivityStatus.online:
        return l10n.connectedToServer;
      case ConnectivityStatus.offline:
        return l10n.pleaseCheckConnection;
      case ConnectivityStatus.checking:
      case null:
        return null;
    }
  }
}
