import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io' show Platform;
import '../theme/app_theme.dart';

/// Centralized service for consistent brand identity throughout the app
/// Uses the hub icon as the primary brand element
class BrandService {
  BrandService._();

  /// Primary brand icon - the hub icon
  static IconData get primaryIcon =>
      Platform.isIOS ? CupertinoIcons.link_circle_fill : Icons.hub;

  /// Alternative brand icons for different contexts
  static IconData get primaryIconOutlined =>
      Platform.isIOS ? CupertinoIcons.link_circle : Icons.hub_outlined;
  static IconData get connectivityIcon =>
      Platform.isIOS ? CupertinoIcons.wifi : Icons.hub;
  static IconData get networkIcon =>
      Platform.isIOS ? CupertinoIcons.globe : Icons.hub;

  /// Brand colors - these should be accessed through context.conduitTheme in UI components
  static Color get primaryBrandColor => AppTheme.brandPrimary;
  static Color get secondaryBrandColor => AppTheme.brandPrimaryLight;
  static Color get accentBrandColor => AppTheme.brandPrimaryDark;

  /// Creates a branded icon with consistent styling
  static Widget createBrandIcon({
    double size = 24,
    Color? color,
    IconData? icon,
    bool useGradient = false,
    bool addShadow = false,
  }) {
    final iconData = icon ?? primaryIcon;
    final iconColor = color ?? primaryBrandColor;

    Widget iconWidget = Icon(
      iconData,
      size: size,
      color: useGradient ? null : iconColor,
    );

    if (useGradient) {
      iconWidget = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          colors: [primaryBrandColor, secondaryBrandColor],
        ).createShader(bounds),
        child: Icon(iconData, size: size),
      );
    }

    if (addShadow) {
      iconWidget = Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: primaryBrandColor.withValues(alpha: 0.3),
              blurRadius: size * 0.3,
              offset: Offset(0, size * 0.1),
            ),
          ],
        ),
        child: iconWidget,
      );
    }

    return iconWidget;
  }

  /// Creates a branded avatar with the hub icon
  static Widget createBrandAvatar({
    double size = 40,
    Color? backgroundColor,
    Color? iconColor,
    bool useGradient = true,
    String? fallbackText,
    BuildContext? context,
  }) {
    final bgColor = backgroundColor ?? primaryBrandColor;
    final iColor =
        iconColor ?? (context?.conduitTheme.textInverse ?? AppTheme.neutral50);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: useGradient
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primaryBrandColor, secondaryBrandColor],
              )
            : null,
        color: useGradient ? null : bgColor,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: primaryBrandColor.withValues(alpha: 0.3),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: fallbackText != null && fallbackText.isNotEmpty
          ? Center(
              child: Text(
                fallbackText.toUpperCase(),
                style: TextStyle(
                  color: iColor,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Icon(primaryIcon, size: size * 0.5, color: iColor),
    );
  }

  /// Creates a branded loading indicator
  static Widget createBrandLoadingIndicator({
    double size = 24,
    double strokeWidth = 2,
    Color? color,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(color ?? primaryBrandColor),
      ),
    );
  }

  /// Creates a branded empty state icon
  static Widget createBrandEmptyStateIcon({
    double size = 80,
    Color? color,
    bool showBackground = true,
    BuildContext? context,
  }) {
    final iconColor =
        color ?? (context?.conduitTheme.iconSecondary ?? AppTheme.neutral400);

    if (!showBackground) {
      return createBrandIcon(
        size: size,
        color: iconColor,
        icon: primaryIconOutlined,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context?.conduitTheme.surfaceBackground ?? AppTheme.neutral700,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(
          color: context?.conduitTheme.dividerColor ?? AppTheme.neutral600,
          width: 2,
        ),
      ),
      child: createBrandIcon(
        size: size * 0.5,
        color: iconColor,
        icon: primaryIconOutlined,
      ),
    );
  }

  /// Creates a branded button with hub icon
  static Widget createBrandButton({
    required String text,
    required VoidCallback? onPressed,
    bool isLoading = false,
    IconData? icon,
    double? width,
    bool isSecondary = false,
    BuildContext? context,
  }) {
    return SizedBox(
      width: width,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? createBrandLoadingIndicator(size: IconSize.sm)
            : createBrandIcon(
                size: IconSize.md,
                icon: icon ?? primaryIcon,
                color: context?.conduitTheme.textInverse ?? AppTheme.neutral50,
              ),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSecondary
              ? (context?.conduitTheme.buttonSecondary ?? AppTheme.neutral700)
              : (context?.conduitTheme.buttonPrimary ?? primaryBrandColor),
          foregroundColor:
              context?.conduitTheme.buttonPrimaryText ?? AppTheme.neutral50,
          disabledBackgroundColor:
              context?.conduitTheme.buttonDisabled ?? AppTheme.neutral500,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppBorderRadius.md),
          ),
          elevation: Elevation.none,
        ),
      ),
    );
  }

  /// Brand-specific semantic labels for accessibility
  static String get brandName => 'Conduit';
  static String get brandDescription => 'Your AI Conversation Hub';
  static String get connectionLabel => 'Hub Connection';
  static String get networkLabel => 'Network Hub';

  /// Creates branded AppBar with consistent styling
  static PreferredSizeWidget createBrandAppBar({
    required String title,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = true,
    double elevation = 0,
    BuildContext? context,
  }) {
    return AppBar(
      title: Text(
        title,
        style: (context != null ? context.conduitTheme.headingSmall : null)
            ?.copyWith(
              color: (context != null
                  ? context.conduitTheme.textPrimary
                  : null),
              fontWeight: FontWeight.w600,
            ),
      ),
      centerTitle: centerTitle,
      elevation: elevation,
      backgroundColor: context?.conduitTheme.surfaceBackground,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      leading: leading,
      actions: actions,
    );
  }

  /// Creates a branded splash screen logo
  static Widget createSplashLogo({
    double size = 140,
    bool animate = true,
    BuildContext? context,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            context?.conduitTheme.buttonPrimary ?? primaryBrandColor,
            context?.conduitTheme.buttonPrimary.withValues(alpha: 0.8) ??
                secondaryBrandColor,
          ],
        ),
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: ConduitShadows.glow,
      ),
      child: Icon(
        primaryIcon,
        size: size * 0.5,
        color: context?.conduitTheme.textInverse ?? AppTheme.neutral50,
      ),
    );
  }
}
