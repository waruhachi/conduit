import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'theme_extensions.dart';
import 'color_palettes.dart';

class AppTheme {
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

  static ThemeData light(AppColorPalette palette) {
    final lightTone = palette.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: lightTone.primary,
        secondary: lightTone.secondary,
        surface: neutral50,
        error: error,
      ).copyWith(surfaceContainerHighest: const Color(0xFFF0F1F1)),
      pageTransitionsTheme: _pageTransitionsTheme,
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
        contentTextStyle: const TextStyle(
          color: neutral50,
        ).copyWith(fontSize: AppTypography.bodyMedium),
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
          borderSide: BorderSide(color: lightTone.primary, width: 2),
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
      textTheme: ThemeData.light().textTheme,
      extensions: <ThemeExtension<dynamic>>[
        ConduitThemeExtension.lightPalette(palette),
        AppPaletteThemeExtension(palette: palette),
      ],
    );
  }

  static ThemeData dark(AppColorPalette palette) {
    final darkTone = palette.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0A0D0C),
      colorScheme: ColorScheme.dark(
        primary: darkTone.primary,
        secondary: darkTone.secondary,
        surface: const Color(0xFF0A0D0C),
        surfaceContainerHighest: neutral700,
        onSurface: neutral50,
        onSurfaceVariant: neutral300,
        outline: neutral600,
        error: error,
      ),
      pageTransitionsTheme: _pageTransitionsTheme,
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
        contentTextStyle: const TextStyle(
          color: neutral50,
        ).copyWith(fontSize: AppTypography.bodyMedium),
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
          borderSide: BorderSide(color: darkTone.primary, width: 2),
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
      textTheme: ThemeData.dark().textTheme,
      extensions: <ThemeExtension<dynamic>>[
        ConduitThemeExtension.darkPalette(palette),
        AppPaletteThemeExtension(palette: palette),
      ],
    );
  }

  static CupertinoThemeData cupertinoTheme(
    BuildContext context,
    AppColorPalette palette,
  ) {
    final brightness = Theme.of(context).brightness;
    final tone = palette.toneFor(brightness);
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: tone.primary,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? neutral900
          : neutral50,
      barBackgroundColor: brightness == Brightness.dark
          ? neutral900
          : neutral50,
    );
  }

  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      );
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
  void deactivate() {
    // Pause animations during deactivation to avoid rebuilds in wrong build scope
    _controller.stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // If a theme transition was in progress, resume it
    if (_controller.value < 1.0 && !_controller.isAnimating) {
      _controller.forward();
    }
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
