import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_boundary.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'server_connection_page.dart';

/// Entry point for the connection and sign-in flow
/// Redirects to the mobile-first two-step process
class ConnectAndSignInPage extends ConsumerWidget {
  const ConnectAndSignInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Directly navigate to the new mobile-first server connection page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ServerConnectionPage(),
        ),
      );
    });

    // Show a simple loading state while transitioning
    return ErrorBoundary(
      child: Scaffold(
        backgroundColor: context.conduitTheme.surfaceBackground,
        body: Center(
          child: ConduitLoadingIndicator(
            message: AppLocalizations.of(context)!.loadingContent,
          ),
        ),
      ),
    );
  }
}
