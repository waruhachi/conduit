import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'theme_extensions.dart';

class AppTheme {
  // Brand accents (ChatGPT aesthetic)
  static const Color brandPrimary = Color(0xFF4F46E5); // Indigo
  static const Color brandPrimaryLight = Color(0xFF818CF8);
  static const Color brandPrimaryDark = Color(0xFF4338CA);

  // Enhanced neutral palette for better contrast (WCAG AA compliant)
  static const Color neutral900 = Color(0xFF000000); // Pure black
  static const Color neutral800 = Color(
    0xFF0D0D0D,
  ); // Darker for better contrast
  static const Color neutral700 = Color(0xFF1A1A1A);
  static const Color neutral600 = Color(0xFF2D2D2D); // Improved contrast
  static const Color neutral500 = Color(0xFF404040); // Better middle gray
  static const Color neutral400 = Color(0xFF525252);
  static const Color neutral300 = Color(0xFF6B6B6B); // Improved contrast ratio
  static const Color neutral200 = Color(0xFF9E9E9E); // Better readability
  static const Color neutral100 = Color(0xFFD1D1D1); // Enhanced contrast
  static const Color neutral50 = Color(
    0xFFF8F8F8,
  ); // Softer white for reduced eye strain

  // Enhanced semantic colors for WCAG AA compliance
  static const Color error = Color(0xFFDC2626); // Improved red contrast
  static const Color errorDark = Color(0xFFB91C1C); // Darker red for dark theme
  static const Color success = Color(0xFF059669); // Better green contrast
  static const Color successDark = Color(0xFF047857); // Dark theme green
  static const Color warning = Color(0xFFD97706); // Improved orange contrast
  static const Color warningDark = Color(0xFFB45309); // Dark theme orange
  static const Color info = Color(0xFF0284C7); // Better blue contrast
  static const Color infoDark = Color(0xFF0369A1); // Dark theme blue

  // Brand aliases
  static const Color primaryColor = brandPrimary;
  static const Color secondaryColor = brandPrimaryLight;
  static const Color surfaceColor = neutral50;
  static const Color errorColor = error;
  static const Color successColor = success;

  // Base Light Theme
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: brandPrimary,
      secondary: brandPrimaryLight,
      surface: surfaceColor,
      error: errorColor,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      },
    ),
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: Elevation.none,
      backgroundColor: Colors.transparent,
      foregroundColor: neutral800,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: neutral50,
      modalBackgroundColor: neutral50,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.modal),
      ),
      showDragHandle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: Elevation.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        side: BorderSide(color: neutral200),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: neutral900.withValues(alpha: 0.92),
      contentTextStyle: GoogleFonts.inter(
        color: neutral50,
        fontSize: AppTypography.bodyMedium,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.snackbar),
      ),
      elevation: Elevation.high,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: neutral50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: errorColor, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
    ),
    textTheme: GoogleFonts.interTextTheme(),
    extensions: const [ConduitThemeExtension.auroraLight],
  );

  // Base Dark Theme
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Color(0xFF0A0D0C),
    colorScheme: const ColorScheme.dark(
      primary: brandPrimary,
      secondary: brandPrimaryDark,
      surface: Color(0xFF0A0D0C),
      surfaceContainerHighest: neutral700,
      onSurface: neutral50,
      onSurfaceVariant: neutral300,
      outline: neutral600,
      error: error,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      },
    ),
    splashFactory: NoSplash.splashFactory,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: Elevation.none,
      backgroundColor: Colors.transparent,
      foregroundColor: neutral50,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: neutral900,
      modalBackgroundColor: neutral900,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.modal),
      ),
      showDragHandle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppBorderRadius.md),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: Elevation.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.lg),
        side: BorderSide(color: neutral800),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: neutral800.withValues(alpha: 0.92),
      contentTextStyle: GoogleFonts.inter(
        color: neutral50,
        fontSize: AppTypography.bodyMedium,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.snackbar),
      ),
      elevation: Elevation.high,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: neutral700,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: neutral600, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: neutral600, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: brandPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    extensions: const [ConduitThemeExtension.dark],
  );

  // Conduit variants using brand colors
  static ThemeData conduitLightTheme = lightTheme.copyWith(
    colorScheme: lightTheme.colorScheme.copyWith(
      primary: brandPrimary,
      secondary: brandPrimaryLight,
      surface: neutral50,
    ),
    extensions: const [ConduitThemeExtension.light],
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: Elevation.none,
      backgroundColor: Colors.transparent,
      foregroundColor: neutral800,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: neutral50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: brandPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
    ),
  );

  static ThemeData conduitDarkTheme = darkTheme.copyWith(
    scaffoldBackgroundColor: const Color(0xFF0A0D0C),
    colorScheme: darkTheme.colorScheme.copyWith(
      primary: brandPrimary,
      secondary: brandPrimaryDark,
      surface: const Color(0xFF0A0D0C),
      surfaceContainerHighest: neutral700,
    ),
    extensions: const [ConduitThemeExtension.dark],
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: Elevation.none,
      backgroundColor: Colors.transparent,
      foregroundColor: neutral50,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: neutral700,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: neutral600, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: neutral600, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: brandPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
        borderSide: const BorderSide(color: error, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
    ),
  );

  // Classic Conduit variants for runtime switching
  // Removed classic Conduit variants from public API to keep Aurora only

  // Platform-specific theming helpers
  static CupertinoThemeData cupertinoTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CupertinoThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: brandPrimary,
      scaffoldBackgroundColor: isDark ? neutral900 : neutral50,
      barBackgroundColor: isDark ? neutral900 : neutral50,
    );
  }
}

/// Animated theme wrapper for smooth theme transitions
class AnimatedThemeWrapper extends StatefulWidget {
  final Widget child;
  final ThemeData theme;
  final Duration duration;

  const AnimatedThemeWrapper({
    super.key,
    required this.child,
    required this.theme,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  State<AnimatedThemeWrapper> createState() => _AnimatedThemeWrapperState();
}

class _AnimatedThemeWrapperState extends State<AnimatedThemeWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  ThemeData? _previousTheme;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _previousTheme = widget.theme;
  }

  @override
  void didUpdateWidget(AnimatedThemeWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.theme != widget.theme) {
      _previousTheme = oldWidget.theme;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Theme(
          data: ThemeData.lerp(
            _previousTheme ?? widget.theme,
            widget.theme,
            _animation.value,
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Theme transition widget for individual components
class ThemeTransition extends StatelessWidget {
  final Widget child;
  final Duration duration;

  const ThemeTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    return child.animate().fadeIn(duration: duration);
  }
}

// Typography, spacing, and design token classes are now in theme_extensions.dart for consistency
