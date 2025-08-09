import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'animation_service.dart';

/// Service for managing app-wide settings including accessibility preferences
class SettingsService {
  static const String _reduceMotionKey = 'reduce_motion';
  static const String _animationSpeedKey = 'animation_speed';
  static const String _hapticFeedbackKey = 'haptic_feedback';
  static const String _highContrastKey = 'high_contrast';
  static const String _largeTextKey = 'large_text';
  static const String _darkModeKey = 'dark_mode';

  /// Get reduced motion preference
  static Future<bool> getReduceMotion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reduceMotionKey) ?? false;
  }

  /// Set reduced motion preference
  static Future<void> setReduceMotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceMotionKey, value);
  }

  /// Get animation speed multiplier (0.5 - 2.0)
  static Future<double> getAnimationSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_animationSpeedKey) ?? 1.0;
  }

  /// Set animation speed multiplier
  static Future<void> setAnimationSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_animationSpeedKey, value.clamp(0.5, 2.0));
  }

  /// Get haptic feedback preference
  static Future<bool> getHapticFeedback() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hapticFeedbackKey) ?? true;
  }

  /// Set haptic feedback preference
  static Future<void> setHapticFeedback(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticFeedbackKey, value);
  }

  /// Get high contrast preference
  static Future<bool> getHighContrast() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_highContrastKey) ?? false;
  }

  /// Set high contrast preference
  static Future<void> setHighContrast(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, value);
  }

  /// Get large text preference
  static Future<bool> getLargeText() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_largeTextKey) ?? false;
  }

  /// Set large text preference
  static Future<void> setLargeText(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_largeTextKey, value);
  }

  /// Get dark mode preference
  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_darkModeKey) ?? true; // Default to dark
  }

  /// Set dark mode preference
  static Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, value);
  }

  /// Load all settings
  static Future<AppSettings> loadSettings() async {
    return AppSettings(
      reduceMotion: await getReduceMotion(),
      animationSpeed: await getAnimationSpeed(),
      hapticFeedback: await getHapticFeedback(),
      highContrast: await getHighContrast(),
      largeText: await getLargeText(),
      darkMode: await getDarkMode(),
    );
  }

  /// Save all settings
  static Future<void> saveSettings(AppSettings settings) async {
    await Future.wait([
      setReduceMotion(settings.reduceMotion),
      setAnimationSpeed(settings.animationSpeed),
      setHapticFeedback(settings.hapticFeedback),
      setHighContrast(settings.highContrast),
      setLargeText(settings.largeText),
      setDarkMode(settings.darkMode),
    ]);
  }

  /// Get effective animation duration considering all settings
  static Duration getEffectiveAnimationDuration(
    BuildContext context,
    Duration defaultDuration,
    AppSettings settings,
  ) {
    // Check system reduced motion first
    if (MediaQuery.of(context).disableAnimations || settings.reduceMotion) {
      return Duration.zero;
    }

    // Apply user animation speed preference
    final adjustedMs =
        (defaultDuration.inMilliseconds / settings.animationSpeed).round();
    return Duration(milliseconds: adjustedMs.clamp(50, 1000));
  }

  /// Get text scale factor considering user preferences
  static double getEffectiveTextScaleFactor(
    BuildContext context,
    AppSettings settings,
  ) {
    final textScaler = MediaQuery.of(context).textScaler;
    double baseScale = textScaler.scale(1.0);

    // Apply large text preference
    if (settings.largeText) {
      baseScale *= 1.3;
    }

    // Ensure reasonable bounds
    return baseScale.clamp(0.8, 3.0);
  }
}

/// Data class for app settings
class AppSettings {
  final bool reduceMotion;
  final double animationSpeed;
  final bool hapticFeedback;
  final bool highContrast;
  final bool largeText;
  final bool darkMode;

  const AppSettings({
    this.reduceMotion = false,
    this.animationSpeed = 1.0,
    this.hapticFeedback = true,
    this.highContrast = false,
    this.largeText = false,
    this.darkMode = true,
  });

  AppSettings copyWith({
    bool? reduceMotion,
    double? animationSpeed,
    bool? hapticFeedback,
    bool? highContrast,
    bool? largeText,
    bool? darkMode,
  }) {
    return AppSettings(
      reduceMotion: reduceMotion ?? this.reduceMotion,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      highContrast: highContrast ?? this.highContrast,
      largeText: largeText ?? this.largeText,
      darkMode: darkMode ?? this.darkMode,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.reduceMotion == reduceMotion &&
        other.animationSpeed == animationSpeed &&
        other.hapticFeedback == hapticFeedback &&
        other.highContrast == highContrast &&
        other.largeText == largeText &&
        other.darkMode == darkMode;
  }

  @override
  int get hashCode {
    return Object.hash(
      reduceMotion,
      animationSpeed,
      hapticFeedback,
      highContrast,
      largeText,
      darkMode,
    );
  }
}

/// Provider for app settings
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
      (ref) => AppSettingsNotifier(),
    );

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.loadSettings();
    state = settings;
  }

  Future<void> setReduceMotion(bool value) async {
    state = state.copyWith(reduceMotion: value);
    await SettingsService.setReduceMotion(value);
  }

  Future<void> setAnimationSpeed(double value) async {
    state = state.copyWith(animationSpeed: value);
    await SettingsService.setAnimationSpeed(value);
  }

  Future<void> setHapticFeedback(bool value) async {
    state = state.copyWith(hapticFeedback: value);
    await SettingsService.setHapticFeedback(value);
  }

  Future<void> setHighContrast(bool value) async {
    state = state.copyWith(highContrast: value);
    await SettingsService.setHighContrast(value);
  }

  Future<void> setLargeText(bool value) async {
    state = state.copyWith(largeText: value);
    await SettingsService.setLargeText(value);
  }

  Future<void> setDarkMode(bool value) async {
    state = state.copyWith(darkMode: value);
    await SettingsService.setDarkMode(value);
  }

  Future<void> resetToDefaults() async {
    const defaultSettings = AppSettings();
    await SettingsService.saveSettings(defaultSettings);
    state = defaultSettings;
  }
}

/// Provider for checking if haptic feedback should be enabled
final hapticEnabledProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsProvider);
  return settings.hapticFeedback;
});

/// Provider for effective animation settings
final effectiveAnimationSettingsProvider = Provider<AnimationSettings>((ref) {
  final appSettings = ref.watch(appSettingsProvider);

  return AnimationSettings(
    reduceMotion: appSettings.reduceMotion,
    performance: AnimationPerformance.adaptive,
    animationSpeed: appSettings.animationSpeed,
  );
});
