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
  static const String _defaultModelKey = 'default_model';
  // Model name formatting
  static const String _omitProviderInModelNameKey =
      'omit_provider_in_model_name';
  // Voice input settings
  static const String _voiceLocaleKey = 'voice_locale_id';
  static const String _voiceHoldToTalkKey = 'voice_hold_to_talk';
  static const String _voiceAutoSendKey = 'voice_auto_send_final';
  // Realtime transport preference
  static const String _socketTransportModeKey = 'socket_transport_mode'; // 'auto' or 'ws'
  // Quick pill visibility selections (max 2)
  static const String _quickPillsKey = 'quick_pills'; // StringList of identifiers e.g. ['web','image','tools']

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

  /// Get default model preference
  static Future<String?> getDefaultModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultModelKey);
  }

  /// Set default model preference
  static Future<void> setDefaultModel(String? modelId) async {
    final prefs = await SharedPreferences.getInstance();
    if (modelId != null) {
      await prefs.setString(_defaultModelKey, modelId);
    } else {
      await prefs.remove(_defaultModelKey);
    }
  }

  /// Whether to omit the provider prefix when displaying model names
  static Future<bool> getOmitProviderInModelName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_omitProviderInModelNameKey) ?? true; // default: omit
  }

  static Future<void> setOmitProviderInModelName(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_omitProviderInModelNameKey, value);
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
      defaultModel: await getDefaultModel(),
      omitProviderInModelName: await getOmitProviderInModelName(),
      voiceLocaleId: await getVoiceLocaleId(),
      voiceHoldToTalk: await getVoiceHoldToTalk(),
      voiceAutoSendFinal: await getVoiceAutoSendFinal(),
      socketTransportMode: await getSocketTransportMode(),
      quickPills: await getQuickPills(),
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
      setDefaultModel(settings.defaultModel),
      setOmitProviderInModelName(settings.omitProviderInModelName),
      setVoiceLocaleId(settings.voiceLocaleId),
      setVoiceHoldToTalk(settings.voiceHoldToTalk),
      setVoiceAutoSendFinal(settings.voiceAutoSendFinal),
      setSocketTransportMode(settings.socketTransportMode),
      setQuickPills(settings.quickPills),
    ]);
  }

  // Voice input specific settings
  static Future<String?> getVoiceLocaleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_voiceLocaleKey);
  }

  static Future<void> setVoiceLocaleId(String? localeId) async {
    final prefs = await SharedPreferences.getInstance();
    if (localeId == null || localeId.isEmpty) {
      await prefs.remove(_voiceLocaleKey);
    } else {
      await prefs.setString(_voiceLocaleKey, localeId);
    }
  }

  static Future<bool> getVoiceHoldToTalk() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceHoldToTalkKey) ?? false;
  }

  static Future<void> setVoiceHoldToTalk(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceHoldToTalkKey, value);
  }

  static Future<bool> getVoiceAutoSendFinal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceAutoSendKey) ?? false;
  }

  static Future<void> setVoiceAutoSendFinal(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceAutoSendKey, value);
  }

  /// Transport mode: 'auto' (polling+websocket) or 'ws' (websocket only)
  static Future<String> getSocketTransportMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_socketTransportModeKey) ?? 'auto';
  }

  static Future<void> setSocketTransportMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode != 'auto' && mode != 'ws') mode = 'auto';
    await prefs.setString(_socketTransportModeKey, mode);
  }

  // Quick Pills (visibility)
  static Future<List<String>> getQuickPills() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_quickPillsKey);
    // Default: none selected
    if (list == null) return const [];
    // Enforce max 2; accept arbitrary tool IDs plus 'web' and 'image'
    return list.take(2).toList();
  }

  static Future<void> setQuickPills(List<String> pills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_quickPillsKey, pills.take(2).toList());
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

/// Sentinel class to detect when defaultModel parameter is not provided
class _DefaultValue {
  const _DefaultValue();
}

/// Data class for app settings
class AppSettings {
  final bool reduceMotion;
  final double animationSpeed;
  final bool hapticFeedback;
  final bool highContrast;
  final bool largeText;
  final bool darkMode;
  final String? defaultModel;
  final bool omitProviderInModelName;
  final String? voiceLocaleId;
  final bool voiceHoldToTalk;
  final bool voiceAutoSendFinal;
  final String socketTransportMode; // 'auto' or 'ws'
  final List<String> quickPills; // e.g., ['web','image']

  const AppSettings({
    this.reduceMotion = false,
    this.animationSpeed = 1.0,
    this.hapticFeedback = true,
    this.highContrast = false,
    this.largeText = false,
    this.darkMode = true,
    this.defaultModel,
    this.omitProviderInModelName = true,
    this.voiceLocaleId,
    this.voiceHoldToTalk = false,
    this.voiceAutoSendFinal = false,
    this.socketTransportMode = 'auto',
    this.quickPills = const [],
  });

  AppSettings copyWith({
    bool? reduceMotion,
    double? animationSpeed,
    bool? hapticFeedback,
    bool? highContrast,
    bool? largeText,
    bool? darkMode,
    Object? defaultModel = const _DefaultValue(),
    bool? omitProviderInModelName,
    Object? voiceLocaleId = const _DefaultValue(),
    bool? voiceHoldToTalk,
    bool? voiceAutoSendFinal,
    String? socketTransportMode,
    List<String>? quickPills,
  }) {
    return AppSettings(
      reduceMotion: reduceMotion ?? this.reduceMotion,
      animationSpeed: animationSpeed ?? this.animationSpeed,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      highContrast: highContrast ?? this.highContrast,
      largeText: largeText ?? this.largeText,
      darkMode: darkMode ?? this.darkMode,
      defaultModel: defaultModel is _DefaultValue ? this.defaultModel : defaultModel as String?,
      omitProviderInModelName: omitProviderInModelName ?? this.omitProviderInModelName,
      voiceLocaleId: voiceLocaleId is _DefaultValue ? this.voiceLocaleId : voiceLocaleId as String?,
      voiceHoldToTalk: voiceHoldToTalk ?? this.voiceHoldToTalk,
      voiceAutoSendFinal: voiceAutoSendFinal ?? this.voiceAutoSendFinal,
      socketTransportMode: socketTransportMode ?? this.socketTransportMode,
      quickPills: quickPills ?? this.quickPills,
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
        other.darkMode == darkMode &&
        other.defaultModel == defaultModel &&
        other.omitProviderInModelName == omitProviderInModelName &&
        other.voiceLocaleId == voiceLocaleId &&
        other.voiceHoldToTalk == voiceHoldToTalk &&
        other.voiceAutoSendFinal == voiceAutoSendFinal &&
        _listEquals(other.quickPills, quickPills);
        // socketTransportMode intentionally not included in == to avoid frequent rebuilds
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
      defaultModel,
      omitProviderInModelName,
      voiceLocaleId,
      voiceHoldToTalk,
      voiceAutoSendFinal,
      socketTransportMode,
      Object.hashAllUnordered(quickPills),
    );
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

  Future<void> setDefaultModel(String? modelId) async {
    state = state.copyWith(defaultModel: modelId);
    await SettingsService.setDefaultModel(modelId);
  }

  Future<void> setOmitProviderInModelName(bool value) async {
    state = state.copyWith(omitProviderInModelName: value);
    await SettingsService.setOmitProviderInModelName(value);
  }

  Future<void> setVoiceLocaleId(String? localeId) async {
    state = state.copyWith(voiceLocaleId: localeId);
    await SettingsService.setVoiceLocaleId(localeId);
  }

  Future<void> setVoiceHoldToTalk(bool value) async {
    state = state.copyWith(voiceHoldToTalk: value);
    await SettingsService.setVoiceHoldToTalk(value);
  }

  Future<void> setVoiceAutoSendFinal(bool value) async {
    state = state.copyWith(voiceAutoSendFinal: value);
    await SettingsService.setVoiceAutoSendFinal(value);
  }

  Future<void> setSocketTransportMode(String mode) async {
    state = state.copyWith(socketTransportMode: mode);
    await SettingsService.setSocketTransportMode(mode);
  }

  Future<void> setQuickPills(List<String> pills) async {
    // Enforce max 2; accept arbitrary server tool IDs plus built-ins
    final filtered = pills.take(2).toList();
    state = state.copyWith(quickPills: filtered);
    await SettingsService.setQuickPills(filtered);
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
