import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:io' show Platform;
import '../theme/theme_extensions.dart';

import '../services/brand_service.dart';

/// Enhanced empty state widgets with illustrations and actions
class ConduitEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? illustration;
  final List<EmptyStateAction>? actions;
  final bool isLoading;

  const ConduitEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.illustration,
    this.actions,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final conduitTheme = context.conduitTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration or icon
            if (illustration != null)
              illustration!
            else if (icon != null)
              Container(
                width: IconSize.xxl * 2.5, // 120px equivalent
                height: IconSize.xxl * 2.5, // 120px equivalent
                decoration: BoxDecoration(
                  color: conduitTheme.cardBackground,
                  shape: BoxShape.circle,
                  border: Border.all(color: conduitTheme.cardBorder, width: 2),
                ),
                child: Icon(
                  icon!,
                  size: IconSize.xxl,
                  color: context.conduitTheme.iconSecondary,
                ),
              )
            else
              // Default to brand icon when no specific icon or illustration provided
              BrandService.createBrandEmptyStateIcon(
                size: IconSize.xxl * 2.5, // 120px equivalent
                showBackground: true,
              ),

            const SizedBox(height: Spacing.xl),

            // Title
            Text(
              title,
              style: conduitTheme.headingMedium,
              textAlign: TextAlign.center,
            ),

            // Subtitle
            if (subtitle != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                subtitle!,
                style: conduitTheme.bodyMedium?.copyWith(
                  color: context.conduitTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Actions
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: Spacing.xl),
              ...actions!.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: _buildActionButton(context, action),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildActionButton(BuildContext context, EmptyStateAction action) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: action.onPressed,
        style: action.isPrimary
            ? FilledButton.styleFrom(
                backgroundColor: context.conduitTheme.buttonPrimary,
                foregroundColor: context.conduitTheme.buttonPrimaryText,
              )
            : FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: context.conduitTheme.textSecondary,
                side: BorderSide(
                  color: context.conduitTheme.dividerColor,
                  width: 1,
                ),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (action.icon != null) ...[
              Icon(action.icon, size: IconSize.md),
              const SizedBox(width: Spacing.sm),
            ],
            Text(action.label),
          ],
        ),
      ),
    );
  }
}

/// Action for empty states
class EmptyStateAction {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isPrimary;

  const EmptyStateAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isPrimary = true,
  });
}

/// Chat-specific empty state
class ChatEmptyState extends StatelessWidget {
  final VoidCallback? onStartChat;

  const ChatEmptyState({super.key, this.onStartChat});

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: 'Start a conversation',
      subtitle:
          'Ask me anything! I\'m here to help with questions, creative tasks, analysis, and more.',
      // Remove custom illustration to use default brand icon
      icon: BrandService.primaryIcon,
      actions: onStartChat != null
          ? [
              EmptyStateAction(
                label: 'Start chatting',
                icon: BrandService.primaryIcon,
                onPressed: onStartChat!,
              ),
            ]
          : null,
    );
  }
}

/// Files empty state
class FilesEmptyState extends StatelessWidget {
  final VoidCallback? onUploadFile;

  const FilesEmptyState({super.key, this.onUploadFile});

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: 'No files yet',
      subtitle:
          'Upload documents, images, or other files to get started with your knowledge base.',
      illustration: Builder(
        builder: (context) => _buildFilesIllustration(context),
      ),
      actions: onUploadFile != null
          ? [
              EmptyStateAction(
                label: 'Upload files',
                icon: Platform.isIOS
                    ? CupertinoIcons.doc_on_doc
                    : Icons.upload_file,
                onPressed: onUploadFile!,
              ),
            ]
          : null,
    );
  }

  Widget _buildFilesIllustration(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: IconSize.xxl * 2.5, // 120px equivalent
            height: IconSize.xxl * 2.5, // 120px equivalent
            decoration: BoxDecoration(
              color: context.conduitTheme.info.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          // File stack
          ...List.generate(3, (index) {
            return Positioned(
              top: 30 + (index * 8.0),
              left: 30 + (index * 4.0),
              child:
                  Container(
                        width: TouchTarget.minimum,
                        height: 50,
                        decoration: BoxDecoration(
                          color: [
                            context.conduitTheme.info,
                            context.conduitTheme.success,
                            context.conduitTheme.warning,
                          ][index],
                          borderRadius: BorderRadius.circular(
                            AppBorderRadius.xs,
                          ),
                        ),
                        child: Icon(
                          [Icons.description, Icons.image, Icons.folder][index],
                          color: context.conduitTheme.textInverse,
                          size: IconSize.md,
                        ),
                      )
                      .animate(delay: Duration(milliseconds: index * 200))
                      .fadeIn()
                      .slideY(begin: 0.3, end: 0),
            );
          }),
        ],
      ),
    );
  }
}

/// Tools empty state
class ToolsEmptyState extends StatelessWidget {
  final VoidCallback? onExploreTools;

  const ToolsEmptyState({super.key, this.onExploreTools});

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: 'Powerful tools await',
      subtitle: 'Discover tools to enhance your productivity and creativity.',
      illustration: Builder(
        builder: (context) => _buildToolsIllustration(context),
      ),
      actions: onExploreTools != null
          ? [
              EmptyStateAction(
                label: 'Explore tools',
                icon: Platform.isIOS
                    ? CupertinoIcons.wand_stars
                    : Icons.auto_awesome,
                onPressed: onExploreTools!,
              ),
            ]
          : null,
    );
  }

  Widget _buildToolsIllustration(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: IconSize.xxl * 2.5, // 120px equivalent
            height: IconSize.xxl * 2.5, // 120px equivalent
            decoration: BoxDecoration(
              color: context.conduitTheme.buttonPrimary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
          ),
          // Tools arrangement
          ...List.generate(6, (index) {
            final angle = (index * 60) * (3.14159 / 180);
            final radius = 35.0;
            return Positioned(
              top: 60 + (radius * -cos(angle)) - 15,
              left: 60 + (radius * sin(angle)) - 15,
              child:
                  Container(
                        width: Spacing.xl - Spacing.xxs, // 30px equivalent
                        height: Spacing.xl - Spacing.xxs, // 30px equivalent
                        decoration: BoxDecoration(
                          color: context.conduitTheme.buttonPrimary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          [
                            Icons.palette,
                            Icons.calculate,
                            Icons.code,
                            Icons.translate,
                            Icons.music_note,
                            Icons.analytics,
                          ][index],
                          color: context.conduitTheme.textInverse,
                          size: IconSize.sm,
                        ),
                      )
                      .animate(delay: Duration(milliseconds: index * 100))
                      .fadeIn()
                      .scale(
                        begin: const Offset(0.5, 0.5),
                        end: const Offset(1.0, 1.0),
                      ),
            );
          }),
        ],
      ),
    );
  }
}

/// Search results empty state
class SearchEmptyState extends StatelessWidget {
  final String query;
  final VoidCallback? onClearSearch;

  const SearchEmptyState({super.key, required this.query, this.onClearSearch});

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: 'No results found',
      subtitle: 'No results for "$query". Try adjusting your search terms.',
      icon: Platform.isIOS ? CupertinoIcons.search : Icons.search_off,
      actions: onClearSearch != null
          ? [
              EmptyStateAction(
                label: 'Clear search',
                icon: Platform.isIOS ? CupertinoIcons.clear : Icons.clear,
                onPressed: onClearSearch!,
                isPrimary: false,
              ),
            ]
          : null,
    );
  }
}

/// Connection error empty state
class ConnectionEmptyState extends StatelessWidget {
  final VoidCallback? onRetry;

  const ConnectionEmptyState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: 'Connection problem',
      subtitle:
          'Unable to load content. Please check your connection and try again.',
      icon: Platform.isIOS ? CupertinoIcons.wifi_slash : Icons.wifi_off,
      actions: onRetry != null
          ? [
              EmptyStateAction(
                label: 'Try again',
                icon: Platform.isIOS ? CupertinoIcons.refresh : Icons.refresh,
                onPressed: onRetry!,
              ),
            ]
          : null,
    );
  }
}

/// Generic empty state with custom illustration
class CustomEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget illustration;
  final List<EmptyStateAction>? actions;

  const CustomEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.illustration,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return ConduitEmptyState(
      title: title,
      subtitle: subtitle,
      illustration: illustration,
      actions: actions,
    );
  }
}

// Helper function to get cosine
double cos(double radians) {
  // Simple cosine approximation for illustration positioning
  if (radians == 0) return 1.0;
  if (radians == 1.5708) return 0.0; // π/2
  if (radians == 3.14159) return -1.0; // π
  if (radians == 4.71239) return 0.0; // 3π/2

  // Taylor series approximation for other values
  double x2 = radians * radians;
  return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
}

// Helper function to get sine
double sin(double radians) {
  // Simple sine approximation for illustration positioning
  if (radians == 0) return 0.0;
  if (radians == 1.5708) return 1.0; // π/2
  if (radians == 3.14159) return 0.0; // π
  if (radians == 4.71239) return -1.0; // 3π/2

  // Taylor series approximation for other values
  double x2 = radians * radians;
  return radians - radians * x2 / 6 + radians * x2 * x2 / 120;
}
