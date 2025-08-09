import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// Extended theme data for consistent styling across the app
@immutable
class ConduitThemeExtension extends ThemeExtension<ConduitThemeExtension> {
  // Chat-specific colors
  final Color chatBubbleUser;
  final Color chatBubbleAssistant;
  final Color chatBubbleUserText;
  final Color chatBubbleAssistantText;
  final Color chatBubbleUserBorder;
  final Color chatBubbleAssistantBorder;

  // Input and form colors
  final Color inputBackground;
  final Color inputBorder;
  final Color inputBorderFocused;
  final Color inputText;
  final Color inputPlaceholder;
  final Color inputError;

  // Card and surface colors
  final Color cardBackground;
  final Color cardBorder;
  final Color cardShadow;
  final Color surfaceBackground;
  final Color surfaceContainer;
  final Color surfaceContainerHighest;

  // Interactive element colors
  final Color buttonPrimary;
  final Color buttonPrimaryText;
  final Color buttonSecondary;
  final Color buttonSecondaryText;
  final Color buttonDisabled;
  final Color buttonDisabledText;

  // Status and feedback colors
  final Color success;
  final Color successBackground;
  final Color error;
  final Color errorBackground;
  final Color warning;
  final Color warningBackground;
  final Color info;
  final Color infoBackground;

  // Navigation and UI element colors
  final Color dividerColor;
  final Color navigationBackground;
  final Color navigationSelected;
  final Color navigationUnselected;
  final Color navigationSelectedBackground;

  // Loading and animation colors
  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color loadingIndicator;

  // Text colors
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;
  final Color textDisabled;

  // Icon colors
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconDisabled;
  final Color iconInverse;

  // Typography styles
  final TextStyle? headingLarge;
  final TextStyle? headingMedium;
  final TextStyle? headingSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? caption;
  final TextStyle? label;
  final TextStyle? code;

  const ConduitThemeExtension({
    // Chat-specific colors
    required this.chatBubbleUser,
    required this.chatBubbleAssistant,
    required this.chatBubbleUserText,
    required this.chatBubbleAssistantText,
    required this.chatBubbleUserBorder,
    required this.chatBubbleAssistantBorder,

    // Input and form colors
    required this.inputBackground,
    required this.inputBorder,
    required this.inputBorderFocused,
    required this.inputText,
    required this.inputPlaceholder,
    required this.inputError,

    // Card and surface colors
    required this.cardBackground,
    required this.cardBorder,
    required this.cardShadow,
    required this.surfaceBackground,
    required this.surfaceContainer,
    required this.surfaceContainerHighest,

    // Interactive element colors
    required this.buttonPrimary,
    required this.buttonPrimaryText,
    required this.buttonSecondary,
    required this.buttonSecondaryText,
    required this.buttonDisabled,
    required this.buttonDisabledText,

    // Status and feedback colors
    required this.success,
    required this.successBackground,
    required this.error,
    required this.errorBackground,
    required this.warning,
    required this.warningBackground,
    required this.info,
    required this.infoBackground,

    // Navigation and UI element colors
    required this.dividerColor,
    required this.navigationBackground,
    required this.navigationSelected,
    required this.navigationUnselected,
    required this.navigationSelectedBackground,

    // Loading and animation colors
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.loadingIndicator,

    // Text colors
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.textDisabled,

    // Icon colors
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconDisabled,
    required this.iconInverse,

    // Typography styles
    this.headingLarge,
    this.headingMedium,
    this.headingSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.caption,
    this.label,
    this.code,
  });

  @override
  ConduitThemeExtension copyWith({
    // Chat-specific colors
    Color? chatBubbleUser,
    Color? chatBubbleAssistant,
    Color? chatBubbleUserText,
    Color? chatBubbleAssistantText,
    Color? chatBubbleUserBorder,
    Color? chatBubbleAssistantBorder,

    // Input and form colors
    Color? inputBackground,
    Color? inputBorder,
    Color? inputBorderFocused,
    Color? inputText,
    Color? inputPlaceholder,
    Color? inputError,

    // Card and surface colors
    Color? cardBackground,
    Color? cardBorder,
    Color? cardShadow,
    Color? surfaceBackground,
    Color? surfaceContainer,
    Color? surfaceContainerHighest,

    // Interactive element colors
    Color? buttonPrimary,
    Color? buttonPrimaryText,
    Color? buttonSecondary,
    Color? buttonSecondaryText,
    Color? buttonDisabled,
    Color? buttonDisabledText,

    // Status and feedback colors
    Color? success,
    Color? successBackground,
    Color? error,
    Color? errorBackground,
    Color? warning,
    Color? warningBackground,
    Color? info,
    Color? infoBackground,

    // Navigation and UI element colors
    Color? dividerColor,
    Color? navigationBackground,
    Color? navigationSelected,
    Color? navigationUnselected,
    Color? navigationSelectedBackground,

    // Loading and animation colors
    Color? shimmerBase,
    Color? shimmerHighlight,
    Color? loadingIndicator,

    // Text colors
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? textDisabled,

    // Icon colors
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconDisabled,
    Color? iconInverse,

    // Typography styles
    TextStyle? headingLarge,
    TextStyle? headingMedium,
    TextStyle? headingSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? caption,
    TextStyle? label,
    TextStyle? code,
  }) {
    return ConduitThemeExtension(
      // Chat-specific colors
      chatBubbleUser: chatBubbleUser ?? this.chatBubbleUser,
      chatBubbleAssistant: chatBubbleAssistant ?? this.chatBubbleAssistant,
      chatBubbleUserText: chatBubbleUserText ?? this.chatBubbleUserText,
      chatBubbleAssistantText:
          chatBubbleAssistantText ?? this.chatBubbleAssistantText,
      chatBubbleUserBorder: chatBubbleUserBorder ?? this.chatBubbleUserBorder,
      chatBubbleAssistantBorder:
          chatBubbleAssistantBorder ?? this.chatBubbleAssistantBorder,

      // Input and form colors
      inputBackground: inputBackground ?? this.inputBackground,
      inputBorder: inputBorder ?? this.inputBorder,
      inputBorderFocused: inputBorderFocused ?? this.inputBorderFocused,
      inputText: inputText ?? this.inputText,
      inputPlaceholder: inputPlaceholder ?? this.inputPlaceholder,
      inputError: inputError ?? this.inputError,

      // Card and surface colors
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      cardShadow: cardShadow ?? this.cardShadow,
      surfaceBackground: surfaceBackground ?? this.surfaceBackground,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,

      // Interactive element colors
      buttonPrimary: buttonPrimary ?? this.buttonPrimary,
      buttonPrimaryText: buttonPrimaryText ?? this.buttonPrimaryText,
      buttonSecondary: buttonSecondary ?? this.buttonSecondary,
      buttonSecondaryText: buttonSecondaryText ?? this.buttonSecondaryText,
      buttonDisabled: buttonDisabled ?? this.buttonDisabled,
      buttonDisabledText: buttonDisabledText ?? this.buttonDisabledText,

      // Status and feedback colors
      success: success ?? this.success,
      successBackground: successBackground ?? this.successBackground,
      error: error ?? this.error,
      errorBackground: errorBackground ?? this.errorBackground,
      warning: warning ?? this.warning,
      warningBackground: warningBackground ?? this.warningBackground,
      info: info ?? this.info,
      infoBackground: infoBackground ?? this.infoBackground,

      // Navigation and UI element colors
      dividerColor: dividerColor ?? this.dividerColor,
      navigationBackground: navigationBackground ?? this.navigationBackground,
      navigationSelected: navigationSelected ?? this.navigationSelected,
      navigationUnselected: navigationUnselected ?? this.navigationUnselected,
      navigationSelectedBackground:
          navigationSelectedBackground ?? this.navigationSelectedBackground,

      // Loading and animation colors
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
      loadingIndicator: loadingIndicator ?? this.loadingIndicator,

      // Text colors
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      textDisabled: textDisabled ?? this.textDisabled,

      // Icon colors
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconDisabled: iconDisabled ?? this.iconDisabled,
      iconInverse: iconInverse ?? this.iconInverse,

      // Typography styles
      headingLarge: headingLarge ?? this.headingLarge,
      headingMedium: headingMedium ?? this.headingMedium,
      headingSmall: headingSmall ?? this.headingSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      caption: caption ?? this.caption,
      label: label ?? this.label,
      code: code ?? this.code,
    );
  }

  @override
  ConduitThemeExtension lerp(
    ThemeExtension<ConduitThemeExtension>? other,
    double t,
  ) {
    if (other is! ConduitThemeExtension) {
      return this;
    }
    return ConduitThemeExtension(
      // Chat-specific colors
      chatBubbleUser: Color.lerp(chatBubbleUser, other.chatBubbleUser, t)!,
      chatBubbleAssistant: Color.lerp(
        chatBubbleAssistant,
        other.chatBubbleAssistant,
        t,
      )!,
      chatBubbleUserText: Color.lerp(
        chatBubbleUserText,
        other.chatBubbleUserText,
        t,
      )!,
      chatBubbleAssistantText: Color.lerp(
        chatBubbleAssistantText,
        other.chatBubbleAssistantText,
        t,
      )!,
      chatBubbleUserBorder: Color.lerp(
        chatBubbleUserBorder,
        other.chatBubbleUserBorder,
        t,
      )!,
      chatBubbleAssistantBorder: Color.lerp(
        chatBubbleAssistantBorder,
        other.chatBubbleAssistantBorder,
        t,
      )!,

      // Input and form colors
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      inputBorderFocused: Color.lerp(
        inputBorderFocused,
        other.inputBorderFocused,
        t,
      )!,
      inputText: Color.lerp(inputText, other.inputText, t)!,
      inputPlaceholder: Color.lerp(
        inputPlaceholder,
        other.inputPlaceholder,
        t,
      )!,
      inputError: Color.lerp(inputError, other.inputError, t)!,

      // Card and surface colors
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      cardShadow: Color.lerp(cardShadow, other.cardShadow, t)!,
      surfaceBackground: Color.lerp(
        surfaceBackground,
        other.surfaceBackground,
        t,
      )!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceContainerHighest: Color.lerp(
        surfaceContainerHighest,
        other.surfaceContainerHighest,
        t,
      )!,

      // Interactive element colors
      buttonPrimary: Color.lerp(buttonPrimary, other.buttonPrimary, t)!,
      buttonPrimaryText: Color.lerp(
        buttonPrimaryText,
        other.buttonPrimaryText,
        t,
      )!,
      buttonSecondary: Color.lerp(buttonSecondary, other.buttonSecondary, t)!,
      buttonSecondaryText: Color.lerp(
        buttonSecondaryText,
        other.buttonSecondaryText,
        t,
      )!,
      buttonDisabled: Color.lerp(buttonDisabled, other.buttonDisabled, t)!,
      buttonDisabledText: Color.lerp(
        buttonDisabledText,
        other.buttonDisabledText,
        t,
      )!,

      // Status and feedback colors
      success: Color.lerp(success, other.success, t)!,
      successBackground: Color.lerp(
        successBackground,
        other.successBackground,
        t,
      )!,
      error: Color.lerp(error, other.error, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      infoBackground: Color.lerp(infoBackground, other.infoBackground, t)!,

      // Navigation and UI element colors
      dividerColor: Color.lerp(dividerColor, other.dividerColor, t)!,
      navigationBackground: Color.lerp(
        navigationBackground,
        other.navigationBackground,
        t,
      )!,
      navigationSelected: Color.lerp(
        navigationSelected,
        other.navigationSelected,
        t,
      )!,
      navigationUnselected: Color.lerp(
        navigationUnselected,
        other.navigationUnselected,
        t,
      )!,
      navigationSelectedBackground: Color.lerp(
        navigationSelectedBackground,
        other.navigationSelectedBackground,
        t,
      )!,

      // Loading and animation colors
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(
        shimmerHighlight,
        other.shimmerHighlight,
        t,
      )!,
      loadingIndicator: Color.lerp(
        loadingIndicator,
        other.loadingIndicator,
        t,
      )!,

      // Text colors
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,

      // Icon colors
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconDisabled: Color.lerp(iconDisabled, other.iconDisabled, t)!,
      iconInverse: Color.lerp(iconInverse, other.iconInverse, t)!,

      // Typography styles
      headingLarge: TextStyle.lerp(headingLarge, other.headingLarge, t),
      headingMedium: TextStyle.lerp(headingMedium, other.headingMedium, t),
      headingSmall: TextStyle.lerp(headingSmall, other.headingSmall, t),
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t),
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t),
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t),
      caption: TextStyle.lerp(caption, other.caption, t),
      label: TextStyle.lerp(label, other.label, t),
      code: TextStyle.lerp(code, other.code, t),
    );
  }

  /// Dark theme extension
  static const ConduitThemeExtension dark = ConduitThemeExtension(
    // Chat-specific colors - Enhanced for production-grade look
    chatBubbleUser: AppTheme.brandPrimary,
    chatBubbleAssistant: Color(0xFF0E1010),
    chatBubbleUserText: AppTheme.neutral50,
    chatBubbleAssistantText: AppTheme.neutral50,
    chatBubbleUserBorder: AppTheme.brandPrimaryDark,
    chatBubbleAssistantBorder: Color(0xFF1A1D1C),
    // Input and form colors
    inputBackground: Color(0xFF141615),
    inputBorder: AppTheme.neutral600,
    inputBorderFocused: AppTheme.brandPrimary,
    inputText: AppTheme.neutral50,
    inputPlaceholder: AppTheme.neutral400,
    inputError: AppTheme.error,

    // Card and surface colors - Enhanced depth and hierarchy
    cardBackground: Color(0xFF0C0F0E),
    cardBorder: Color(0xFF151918),
    cardShadow: AppTheme.neutral900,
    surfaceBackground: Color(0xFF0A0D0C),
    surfaceContainer: Color(0xFF0C0F0E),
    surfaceContainerHighest: Color(0xFF121514),

    // Interactive element colors - More vibrant and accessible
    buttonPrimary: AppTheme.brandPrimary,
    buttonPrimaryText: AppTheme.neutral50,
    buttonSecondary: Color(0xFF151918),
    buttonSecondaryText: AppTheme.neutral50,
    buttonDisabled: AppTheme.neutral600,
    buttonDisabledText: AppTheme.neutral400,

    // Status and feedback colors - Enhanced visibility
    success: Color(0xFF22C55E),
    successBackground: Color(0xFF14532D),
    error: Color(0xFFEF4444),
    errorBackground: Color(0xFF7F1D1D),
    warning: Color(0xFFF59E0B),
    warningBackground: Color(0xFF7C2D12),
    info: Color(0xFF38BDF8),
    infoBackground: Color(0xFF0C4A6E),

    // Navigation and UI element colors - Enhanced contrast
    dividerColor: Color(0xFF1A1D1C),
    navigationBackground: Color(0xFF0A0D0C),
    navigationSelected: AppTheme.brandPrimary,
    navigationUnselected: AppTheme.neutral400,
    navigationSelectedBackground: AppTheme.brandPrimary,

    // Loading and animation colors - Enhanced visibility
    shimmerBase: Color(0xFF121514),
    shimmerHighlight: Color(0xFF1A1D1C),
    loadingIndicator: AppTheme.brandPrimary,
    // Text colors - Enhanced hierarchy
    textPrimary: AppTheme.neutral50,
    textSecondary: Color(0xFFBAC2C0),
    textTertiary: AppTheme.neutral400,
    textInverse: AppTheme.neutral900,
    textDisabled: AppTheme.neutral600,

    // Icon colors - Enhanced visibility
    iconPrimary: AppTheme.neutral50,
    iconSecondary: Color(0xFFA0A8A5),
    iconDisabled: AppTheme.neutral600,
    iconInverse: AppTheme.neutral900,

    // Typography styles
    headingLarge: TextStyle(
      fontSize: AppTypography.displaySmall,
      fontWeight: FontWeight.w700,
      color: AppTheme.neutral50,
      height: 1.2,
    ),
    headingMedium: TextStyle(
      fontSize: AppTypography.headlineLarge,
      fontWeight: FontWeight.w600,
      color: AppTheme.neutral50,
      height: 1.3,
    ),
    headingSmall: TextStyle(
      fontSize: AppTypography.headlineSmall,
      fontWeight: FontWeight.w600,
      color: AppTheme.neutral50,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: AppTypography.bodyLarge,
      fontWeight: FontWeight.w400,
      color: AppTheme.neutral50,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: AppTypography.bodyMedium,
      fontWeight: FontWeight.w400,
      color: AppTheme.neutral50,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w400,
      color: Color(0xFFD1D5DB), // Enhanced contrast
      height: 1.4,
    ),
    caption: TextStyle(
      fontSize: AppTypography.labelMedium,
      fontWeight: FontWeight.w500,
      color: AppTheme.neutral300,
      height: 1.3,
      letterSpacing: 0.5,
    ),
    label: TextStyle(
      fontSize: AppTypography.labelLarge,
      fontWeight: FontWeight.w500,
      color: Color(0xFFD1D5DB), // Enhanced contrast
      height: 1.3,
    ),
    code: TextStyle(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w400,
      color: Color(0xFFD1D5DB), // Enhanced contrast
      height: 1.4,
      fontFamily: AppTypography.monospaceFontFamily,
    ),
  );

  /// Light theme extension
  static const ConduitThemeExtension light = ConduitThemeExtension(
    // Chat-specific colors - Enhanced for production-grade look
    chatBubbleUser: AppTheme.brandPrimary,
    chatBubbleAssistant: Color(0xFFF7F7F7),
    chatBubbleUserText: AppTheme.neutral50,
    chatBubbleAssistantText: Color(0xFF1C1C1C),
    chatBubbleUserBorder: AppTheme.brandPrimaryDark,
    chatBubbleAssistantBorder: Color(0xFFE7E7E7),
    // Input and form colors
    inputBackground: AppTheme.neutral50,
    inputBorder: AppTheme.neutral200,
    inputBorderFocused: AppTheme.brandPrimary,
    inputText: AppTheme.neutral900,
    inputPlaceholder: AppTheme.neutral500,
    inputError: AppTheme.error,

    // Card and surface colors - Enhanced depth and hierarchy
    cardBackground: AppTheme.neutral50,
    cardBorder: Color(0xFFE7E7E7),
    cardShadow: Color(0xFFF3F4F6),
    surfaceBackground: AppTheme.neutral50,
    surfaceContainer: Color(0xFFF7F7F7),
    surfaceContainerHighest: Color(0xFFF0F1F1),
    // Interactive element colors - More vibrant and accessible
    buttonPrimary: AppTheme.brandPrimary,
    buttonPrimaryText: AppTheme.neutral50,
    buttonSecondary: Color(0xFFF0F1F1),
    buttonSecondaryText: Color(0xFF1C1C1C),
    buttonDisabled: AppTheme.neutral300,
    buttonDisabledText: AppTheme.neutral500,

    // Status and feedback colors - Enhanced visibility
    success: Color(0xFF16A34A),
    successBackground: Color(0xFFEFFBF3),
    error: Color(0xFFDC2626),
    errorBackground: Color(0xFFFDECEC),
    warning: Color(0xFFD97706),
    warningBackground: Color(0xFFFEF6E7),
    info: Color(0xFF0284C7),
    infoBackground: Color(0xFFE8F4FD),

    // Navigation and UI element colors - Enhanced contrast
    dividerColor: Color(0xFFE7E7E7),
    navigationBackground: AppTheme.neutral50,
    navigationSelected: AppTheme.brandPrimary,
    navigationUnselected: AppTheme.neutral600,
    navigationSelectedBackground: AppTheme.brandPrimary,

    // Loading and animation colors - Enhanced visibility
    shimmerBase: Color(0xFFF3F4F6),
    shimmerHighlight: AppTheme.neutral50,
    loadingIndicator: AppTheme.brandPrimary,
    // Text colors - Enhanced hierarchy
    textPrimary: Color(0xFF1C1C1C),
    textSecondary: Color(0xFF3A3F3E),
    textTertiary: AppTheme.neutral500,
    textInverse: AppTheme.neutral50,
    textDisabled: AppTheme.neutral400,

    // Icon colors - Enhanced visibility
    iconPrimary: Color(0xFF1C1C1C),
    iconSecondary: Color(0xFF666C6A),
    iconDisabled: AppTheme.neutral400,
    iconInverse: AppTheme.neutral50,

    // Typography styles
    headingLarge: TextStyle(
      fontSize: AppTypography.displaySmall,
      fontWeight: FontWeight.w700,
      color: Color(0xFF111827), // Better contrast
      height: 1.2,
    ),
    headingMedium: TextStyle(
      fontSize: AppTypography.headlineLarge,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111827), // Better contrast
      height: 1.3,
    ),
    headingSmall: TextStyle(
      fontSize: AppTypography.headlineSmall,
      fontWeight: FontWeight.w600,
      color: Color(0xFF111827), // Better contrast
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: AppTypography.bodyLarge,
      fontWeight: FontWeight.w400,
      color: Color(0xFF111827), // Better contrast
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: AppTypography.bodyMedium,
      fontWeight: FontWeight.w400,
      color: Color(0xFF374151), // Better contrast
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w400,
      color: Color(0xFF6B7280), // Better contrast
      height: 1.4,
    ),
    caption: TextStyle(
      fontSize: AppTypography.labelMedium,
      fontWeight: FontWeight.w500,
      color: AppTheme.neutral500,
      height: 1.3,
      letterSpacing: 0.5,
    ),
    label: TextStyle(
      fontSize: AppTypography.labelLarge,
      fontWeight: FontWeight.w500,
      color: Color(0xFF374151), // Better contrast
      height: 1.3,
    ),
    code: TextStyle(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w400,
      color: Color(0xFF374151), // Better contrast
      height: 1.4,
      fontFamily: AppTypography.monospaceFontFamily,
    ),
  );

  // Aurora palette: original, cool cyan-teal with midnight accents
  static const ConduitThemeExtension auroraDark = ConduitThemeExtension(
    // Chat-specific colors
    chatBubbleUser: Color(0xFF0EA5A5),
    chatBubbleAssistant: Color(0xFF111827),
    chatBubbleUserText: AppTheme.neutral50,
    chatBubbleAssistantText: AppTheme.neutral50,
    chatBubbleUserBorder: Color(0xFF0EA5A5),
    chatBubbleAssistantBorder: Color(0xFF1F2937),
    // Input and form colors
    inputBackground: AppTheme.neutral700,
    inputBorder: AppTheme.neutral600,
    inputBorderFocused: Color(0xFF06B6D4),
    inputText: AppTheme.neutral50,
    inputPlaceholder: AppTheme.neutral400,
    inputError: AppTheme.error,
    // Card and surface colors
    cardBackground: Color(0xFF0B1220),
    cardBorder: Color(0xFF1F2A37),
    cardShadow: AppTheme.neutral900,
    surfaceBackground: Color(0xFF0A0F1A),
    surfaceContainer: Color(0xFF0F172A),
    surfaceContainerHighest: Color(0xFF111827),
    // Interactive element colors
    buttonPrimary: Color(0xFF06B6D4),
    buttonPrimaryText: AppTheme.neutral50,
    buttonSecondary: Color(0xFF1E293B),
    buttonSecondaryText: AppTheme.neutral50,
    buttonDisabled: AppTheme.neutral600,
    buttonDisabledText: AppTheme.neutral400,
    // Status and feedback colors
    success: Color(0xFF22C55E),
    successBackground: Color(0xFF14532D),
    error: Color(0xFFEF4444),
    errorBackground: Color(0xFF7F1D1D),
    warning: Color(0xFFF59E0B),
    warningBackground: Color(0xFF7C2D12),
    info: Color(0xFF38BDF8),
    infoBackground: Color(0xFF0C4A6E),
    // Navigation and UI element colors
    dividerColor: Color(0xFF334155),
    navigationBackground: Color(0xFF0B1220),
    navigationSelected: Color(0xFF06B6D4),
    navigationUnselected: AppTheme.neutral400,
    navigationSelectedBackground: Color(0xFF06B6D4),
    // Loading and animation colors
    shimmerBase: Color(0xFF0F172A),
    shimmerHighlight: Color(0xFF1F2937),
    loadingIndicator: Color(0xFF06B6D4),
    // Text colors
    textPrimary: AppTheme.neutral50,
    textSecondary: Color(0xFFE5E7EB),
    textTertiary: AppTheme.neutral400,
    textInverse: AppTheme.neutral900,
    textDisabled: AppTheme.neutral600,
    // Icon colors
    iconPrimary: AppTheme.neutral50,
    iconSecondary: Color(0xFF94A3B8),
    iconDisabled: AppTheme.neutral600,
    iconInverse: AppTheme.neutral900,
    // Typography styles (reuse base sizes with aurora accent implied by colors)
    headingLarge: null,
    headingMedium: null,
    headingSmall: null,
    bodyLarge: null,
    bodyMedium: null,
    bodySmall: null,
    caption: null,
    label: null,
    code: null,
  );

  static const ConduitThemeExtension auroraLight = ConduitThemeExtension(
    // Chat-specific colors
    chatBubbleUser: Color(0xFF0EA5A5),
    chatBubbleAssistant: Color(0xFFF8FAFC),
    chatBubbleUserText: AppTheme.neutral50,
    chatBubbleAssistantText: Color(0xFF0F172A),
    chatBubbleUserBorder: Color(0xFF0EA5A5),
    chatBubbleAssistantBorder: Color(0xFFE2E8F0),
    // Input and form colors
    inputBackground: AppTheme.neutral50,
    inputBorder: Color(0xFFE2E8F0),
    inputBorderFocused: Color(0xFF06B6D4),
    inputText: Color(0xFF0F172A),
    inputPlaceholder: AppTheme.neutral500,
    inputError: AppTheme.error,
    // Card and surface colors
    cardBackground: AppTheme.neutral50,
    cardBorder: Color(0xFFE2E8F0),
    cardShadow: Color(0xFFF1F5F9),
    surfaceBackground: AppTheme.neutral50,
    surfaceContainer: Color(0xFFF8FAFC),
    surfaceContainerHighest: Color(0xFFF1F5F9),
    // Interactive element colors
    buttonPrimary: Color(0xFF06B6D4),
    buttonPrimaryText: AppTheme.neutral50,
    buttonSecondary: Color(0xFFE2E8F0),
    buttonSecondaryText: Color(0xFF0F172A),
    buttonDisabled: AppTheme.neutral300,
    buttonDisabledText: AppTheme.neutral500,
    // Status and feedback colors
    success: Color(0xFF16A34A),
    successBackground: Color(0xFFEFFBF3),
    error: Color(0xFFDC2626),
    errorBackground: Color(0xFFFDECEC),
    warning: Color(0xFFD97706),
    warningBackground: Color(0xFFFEF6E7),
    info: Color(0xFF0284C7),
    infoBackground: Color(0xFFE8F4FD),
    // Navigation and UI element colors
    dividerColor: Color(0xFFE2E8F0),
    navigationBackground: AppTheme.neutral50,
    navigationSelected: Color(0xFF06B6D4),
    navigationUnselected: AppTheme.neutral600,
    navigationSelectedBackground: Color(0xFF06B6D4),
    // Loading and animation colors
    shimmerBase: Color(0xFFF1F5F9),
    shimmerHighlight: AppTheme.neutral50,
    loadingIndicator: Color(0xFF06B6D4),
    // Text colors
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF334155),
    textTertiary: AppTheme.neutral500,
    textInverse: AppTheme.neutral50,
    textDisabled: AppTheme.neutral400,
    // Icon colors
    iconPrimary: Color(0xFF0F172A),
    iconSecondary: Color(0xFF64748B),
    iconDisabled: AppTheme.neutral400,
    iconInverse: AppTheme.neutral50,
    // Typography styles (inherit from base)
    headingLarge: null,
    headingMedium: null,
    headingSmall: null,
    bodyLarge: null,
    bodyMedium: null,
    bodySmall: null,
    caption: null,
    label: null,
    code: null,
  );

  // Serenity palette: soft sage greens with gentle neutrals
  static const ConduitThemeExtension serenityDark = ConduitThemeExtension(
    // Chat-specific colors
    chatBubbleUser: Color(0xFF4F9D88),
    chatBubbleAssistant: Color(0xFF0A100E),
    chatBubbleUserText: Color(0xFFD7E3DE),
    chatBubbleAssistantText: Color(0xFFD7E3DE),
    chatBubbleUserBorder: Color(0xFF15201B),
    chatBubbleAssistantBorder: Color(0xFF121A16),
    // Input and form colors
    inputBackground: Color(0xFF0A100E),
    inputBorder: Color(0xFF15201B),
    inputBorderFocused: Color(0xFF4F9D88),
    inputText: Color(0xFFD7E3DE),
    inputPlaceholder: Color(0xFF7C8A84),
    inputError: AppTheme.error,
    // Card and surface colors
    cardBackground: Color(0xFF0A100E),
    cardBorder: Color(0xFF121A16),
    cardShadow: AppTheme.neutral900,
    surfaceBackground: Color(0xFF080D0B),
    surfaceContainer: Color(0xFF0A100E),
    surfaceContainerHighest: Color(0xFF0D1411),
    // Interactive element colors
    buttonPrimary: Color(0xFF4F9D88),
    buttonPrimaryText: Color(0xFFD7E3DE),
    buttonSecondary: Color(0xFF101613),
    buttonSecondaryText: Color(0xFFD7E3DE),
    buttonDisabled: AppTheme.neutral600,
    buttonDisabledText: AppTheme.neutral400,
    // Status and feedback colors
    success: Color(0xFF22C55E),
    successBackground: Color(0xFF14532D),
    error: Color(0xFFEF4444),
    errorBackground: Color(0xFF7F1D1D),
    warning: Color(0xFFF59E0B),
    warningBackground: Color(0xFF7C2D12),
    info: Color(0xFF38BDF8),
    infoBackground: Color(0xFF0C4A6E),
    // Navigation and UI element colors
    dividerColor: Color(0xFF15201B),
    navigationBackground: Color(0xFF080D0B),
    navigationSelected: Color(0xFF4F9D88),
    navigationUnselected: AppTheme.neutral400,
    navigationSelectedBackground: Color(0xFF4F9D88),
    // Loading and animation colors
    shimmerBase: Color(0xFF0A100E),
    shimmerHighlight: Color(0xFF121A16),
    loadingIndicator: Color(0xFF4F9D88),
    // Text colors
    textPrimary: Color(0xFFD7E3DE),
    textSecondary: Color(0xFFA8B6AF),
    textTertiary: AppTheme.neutral400,
    textInverse: AppTheme.neutral900,
    textDisabled: AppTheme.neutral600,
    // Icon colors
    iconPrimary: Color(0xFFD7E3DE),
    iconSecondary: Color(0xFFA3B3AD),
    iconDisabled: AppTheme.neutral600,
    iconInverse: AppTheme.neutral900,
    // Typography styles (inherit from base)
    headingLarge: null,
    headingMedium: null,
    headingSmall: null,
    bodyLarge: null,
    bodyMedium: null,
    bodySmall: null,
    caption: null,
    label: null,
    code: null,
  );

  static const ConduitThemeExtension serenityLight = ConduitThemeExtension(
    // Chat-specific colors
    chatBubbleUser: Color(0xFF5FAE97),
    chatBubbleAssistant: Color(0xFFF7FAF8),
    chatBubbleUserText: AppTheme.neutral50,
    chatBubbleAssistantText: Color(0xFF0F1A14),
    chatBubbleUserBorder: Color(0xFF5FAE97),
    chatBubbleAssistantBorder: Color(0xFFD5E3DB),
    // Input and form colors
    inputBackground: Color(0xFFF7FAF8),
    inputBorder: Color(0xFFD5E3DB),
    inputBorderFocused: Color(0xFF4F9D88),
    inputText: Color(0xFF0F1A14),
    inputPlaceholder: AppTheme.neutral500,
    inputError: AppTheme.error,
    // Card and surface colors
    cardBackground: Color(0xFFFAFBF9),
    cardBorder: Color(0xFFD9E2DB),
    cardShadow: Color(0xFFEEF2EE),
    surfaceBackground: Color(0xFFF7FAF8),
    surfaceContainer: Color(0xFFEFF4F1),
    surfaceContainerHighest: Color(0xFFE6EEEA),
    // Interactive element colors
    buttonPrimary: Color(0xFF4F9D88),
    buttonPrimaryText: AppTheme.neutral50,
    buttonSecondary: Color(0xFFEEF2EE),
    buttonSecondaryText: Color(0xFF1A241E),
    buttonDisabled: AppTheme.neutral300,
    buttonDisabledText: AppTheme.neutral500,
    // Status and feedback colors
    success: Color(0xFF16A34A),
    successBackground: Color(0xFFEFFBF3),
    error: Color(0xFFDC2626),
    errorBackground: Color(0xFFFDECEC),
    warning: Color(0xFFD97706),
    warningBackground: Color(0xFFFEF6E7),
    info: Color(0xFF0284C7),
    infoBackground: Color(0xFFE8F4FD),
    // Navigation and UI element colors
    dividerColor: Color(0xFFD9E2DB),
    navigationBackground: Color(0xFFF7FAF8),
    navigationSelected: Color(0xFF4F9D88),
    navigationUnselected: AppTheme.neutral600,
    navigationSelectedBackground: Color(0xFF4F9D88),
    // Loading and animation colors
    shimmerBase: Color(0xFFEFF4F1),
    shimmerHighlight: AppTheme.neutral50,
    loadingIndicator: Color(0xFF4F9D88),
    // Text colors
    textPrimary: Color(0xFF0F1A14),
    textSecondary: Color(0xFF2D3A34),
    textTertiary: AppTheme.neutral500,
    textInverse: AppTheme.neutral50,
    textDisabled: AppTheme.neutral400,
    // Icon colors
    iconPrimary: Color(0xFF0F1A14),
    iconSecondary: Color(0xFF53665C),
    iconDisabled: AppTheme.neutral400,
    iconInverse: AppTheme.neutral50,
    // Typography styles (inherit from base)
    headingLarge: null,
    headingMedium: null,
    headingSmall: null,
    bodyLarge: null,
    bodyMedium: null,
    bodySmall: null,
    caption: null,
    label: null,
    code: null,
  );
}

/// Extension method to easily access Conduit theme from BuildContext
extension ConduitThemeContext on BuildContext {
  ConduitThemeExtension get conduitTheme {
    return Theme.of(this).extension<ConduitThemeExtension>() ??
        ConduitThemeExtension.dark;
  }
}

/// Consistent spacing values - Enhanced for production with better hierarchy
class Spacing {
  // Base spacing scale (8pt grid system)
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Enhanced spacing for specific components with better hierarchy
  static const double buttonPadding = 16.0;
  static const double cardPadding = 20.0;
  static const double inputPadding = 16.0;
  static const double modalPadding = 24.0;
  static const double messagePadding = 16.0;
  static const double navigationPadding = 12.0;
  static const double listItemPadding = 16.0;
  static const double sectionPadding = 24.0;
  static const double pagePadding = 20.0;
  static const double screenPadding = 16.0;

  // Spacing for different densities with improved hierarchy
  static const double compact = 8.0;
  static const double comfortable = 16.0;
  static const double spacious = 24.0;
  static const double extraSpacious = 32.0;

  // Specific component spacing with better consistency
  static const double chatBubblePadding = 16.0;
  static const double actionButtonPadding = 12.0;
  static const double floatingButtonPadding = 16.0;
  static const double bottomSheetPadding = 24.0;
  static const double dialogPadding = 20.0;
  static const double snackbarPadding = 16.0;

  // Layout spacing with improved hierarchy
  static const double gridGap = 16.0;
  static const double listGap = 12.0;
  static const double sectionGap = 32.0;
  static const double contentGap = 24.0;

  // Enhanced spacing for better visual hierarchy
  static const double micro = 4.0;
  static const double small = 8.0;
  static const double medium = 16.0;
  static const double large = 24.0;
  static const double extraLarge = 32.0;
  static const double huge = 48.0;
  static const double massive = 64.0;

  // Component-specific spacing
  static const double iconSpacing = 8.0;
  static const double textSpacing = 4.0;
  static const double borderSpacing = 1.0;
  static const double shadowSpacing = 2.0;
}

/// Consistent border radius values - Enhanced for production with better hierarchy
class AppBorderRadius {
  // Base radius scale
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double round = 999.0;

  // Enhanced radius values for specific components with better hierarchy
  static const double button = 12.0;
  static const double card = 16.0;
  static const double input = 12.0;
  static const double modal = 20.0;
  static const double messageBubble = 18.0;
  static const double navigation = 12.0;
  static const double avatar = 50.0;
  static const double badge = 20.0;
  static const double chip = 16.0;
  static const double tooltip = 8.0;

  // Border radius for different sizes with improved hierarchy
  static const double small = 6.0;
  static const double medium = 12.0;
  static const double large = 18.0;
  static const double extraLarge = 24.0;
  static const double pill = 999.0;

  // Specific component radius with better consistency
  static const double chatBubble = 20.0;
  static const double actionButton = 14.0;
  static const double floatingButton = 28.0;
  static const double bottomSheet = 24.0;
  static const double dialog = 16.0;
  static const double snackbar = 8.0;

  // Enhanced radius values for better visual hierarchy
  static const double micro = 2.0;
  static const double tiny = 4.0;
  static const double standard = 8.0;
  static const double comfortable = 12.0;
  static const double spacious = 16.0;
  static const double extraSpacious = 24.0;
  static const double circular = 999.0;
}

/// Consistent border width values - Enhanced for production
class BorderWidth {
  static const double thin = 0.5;
  static const double regular = 1.0;
  static const double medium = 1.5;
  static const double thick = 2.0;

  // Enhanced border widths for better visual hierarchy
  static const double micro = 0.5;
  static const double small = 1.0;
  static const double standard = 1.5;
  static const double large = 2.0;
  static const double extraLarge = 3.0;
}

/// Consistent elevation values - Enhanced for production with better hierarchy
class Elevation {
  static const double none = 0.0;
  static const double low = 2.0;
  static const double medium = 4.0;
  static const double high = 8.0;
  static const double highest = 16.0;

  // Enhanced elevation values for better visual hierarchy
  static const double micro = 1.0;
  static const double small = 2.0;
  static const double standard = 4.0;
  static const double large = 8.0;
  static const double extraLarge = 16.0;
  static const double massive = 24.0;
}

/// Helper class for consistent shadows - Enhanced for production with better hierarchy
class ConduitShadows {
  static List<BoxShadow> get low => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get medium => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get high => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.16),
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppTheme.brandPrimary.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 0),
      spreadRadius: 0,
    ),
  ];

  // Enhanced shadows for specific components with better hierarchy
  static List<BoxShadow> get card => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 3),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get button => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.1),
      blurRadius: 6,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get modal => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.2),
      blurRadius: 32,
      offset: const Offset(0, 12),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get navigation => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, -2),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get messageBubble => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get input => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.05),
      blurRadius: 4,
      offset: const Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  // Dark theme specific shadows with better contrast
  static List<BoxShadow> get darkCard => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.3),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get darkModal => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.4),
      blurRadius: 40,
      offset: const Offset(0, 16),
      spreadRadius: 0,
    ),
  ];

  // Interactive shadows with better feedback
  static List<BoxShadow> get pressed => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.15),
      blurRadius: 4,
      offset: const Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get hover => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.12),
      blurRadius: 12,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // Enhanced shadows for better visual hierarchy
  static List<BoxShadow> get micro => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get small => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get standard => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 3),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get large => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.12),
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> get extraLarge => [
    BoxShadow(
      color: AppTheme.neutral900.withValues(alpha: 0.16),
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
  ];
}

/// Typography scale following Conduit design tokens - Enhanced for production
class AppTypography {
  static const String fontFamily = 'Inter';
  static const String monospaceFontFamily = 'SF Mono';

  // Letter spacing values - Enhanced for better readability
  static const double letterSpacingTight = -0.5;
  static const double letterSpacingNormal = 0.0;
  static const double letterSpacingWide = 0.5;
  static const double letterSpacingExtraWide = 1.0;

  // Font sizes - Enhanced scale for better hierarchy
  static const double displayLarge = 48;
  static const double displayMedium = 36;
  static const double displaySmall = 32;
  static const double headlineLarge = 28;
  static const double headlineMedium = 24;
  static const double headlineSmall = 20;
  static const double bodyLarge = 18;
  static const double bodyMedium = 16;
  static const double bodySmall = 14;
  static const double labelLarge = 16;
  static const double labelMedium = 14;
  static const double labelSmall = 12;

  // Text styles following Conduit design - Enhanced for production
  static final TextStyle displayLargeStyle = GoogleFonts.inter(
    fontSize: displayLarge,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.1,
  );

  static final TextStyle displayMediumStyle = GoogleFonts.inter(
    fontSize: displayMedium,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.2,
  );

  static final TextStyle bodyLargeStyle = GoogleFonts.inter(
    fontSize: bodyLarge,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  static final TextStyle bodyMediumStyle = GoogleFonts.inter(
    fontSize: bodyMedium,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  static final TextStyle codeStyle = GoogleFonts.sourceCodePro(
    fontSize: bodySmall,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  // Additional styled text getters for convenience - Enhanced
  static TextStyle get headlineLargeStyle => GoogleFonts.inter(
    fontSize: headlineLarge,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.3,
  );

  static TextStyle get headlineMediumStyle => GoogleFonts.inter(
    fontSize: headlineMedium,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  static TextStyle get headlineSmallStyle => GoogleFonts.inter(
    fontSize: headlineSmall,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.4,
  );

  static TextStyle get bodySmallStyle => GoogleFonts.inter(
    fontSize: bodySmall,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  // Enhanced text styles for chat messages
  static TextStyle get chatMessageStyle => GoogleFonts.inter(
    fontSize: bodyMedium,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.6,
  );

  static TextStyle get chatCodeStyle => GoogleFonts.sourceCodePro(
    fontSize: bodySmall,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  // Enhanced label styles
  static TextStyle get labelStyle => GoogleFonts.inter(
    fontSize: labelMedium,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    height: 1.4,
  );

  // Enhanced caption styles
  static TextStyle get captionStyle => GoogleFonts.inter(
    fontSize: labelSmall,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.3,
  );

  // Enhanced typography for better hierarchy
  static TextStyle get micro => GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static TextStyle get tiny => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static TextStyle get small => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  static TextStyle get standard => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  static TextStyle get large => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.6,
  );

  static TextStyle get extraLarge => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  static TextStyle get huge => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  static TextStyle get massive => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.2,
  );
}

/// Consistent icon sizes - Enhanced for production with better hierarchy
class IconSize {
  static const double xs = 12.0;
  static const double sm = 16.0;
  static const double md = 20.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Enhanced icon sizes for specific components with better hierarchy
  static const double button = 20.0;
  static const double card = 24.0;
  static const double input = 20.0;
  static const double modal = 24.0;
  static const double message = 18.0;
  static const double navigation = 24.0;
  static const double avatar = 40.0;
  static const double badge = 16.0;
  static const double chip = 18.0;
  static const double tooltip = 16.0;

  // Icon sizes for different contexts with improved hierarchy
  static const double micro = 12.0;
  static const double small = 16.0;
  static const double medium = 20.0;
  static const double large = 24.0;
  static const double extraLarge = 32.0;
  static const double huge = 48.0;

  // Specific component icon sizes with better consistency
  static const double chatBubble = 18.0;
  static const double actionButton = 20.0;
  static const double floatingButton = 24.0;
  static const double bottomSheet = 24.0;
  static const double dialog = 24.0;
  static const double snackbar = 20.0;
  static const double tabBar = 24.0;
  static const double appBar = 24.0;
  static const double listItem = 20.0;
  static const double formField = 20.0;
}

/// Alpha values for opacity/transparency - Enhanced for production with better hierarchy
class Alpha {
  static const double subtle = 0.1;
  static const double light = 0.3;
  static const double medium = 0.5;
  static const double strong = 0.7;
  static const double intense = 0.9;

  // Enhanced alpha values for specific use cases with better hierarchy
  static const double disabled = 0.38;
  static const double overlay = 0.5;
  static const double backdrop = 0.6;
  static const double highlight = 0.12;
  static const double pressed = 0.2;
  static const double hover = 0.08;
  static const double focus = 0.12;
  static const double selected = 0.16;
  static const double active = 0.24;
  static const double inactive = 0.6;

  // Alpha values for different states with improved hierarchy
  static const double primary = 1.0;
  static const double secondary = 0.7;
  static const double tertiary = 0.5;
  static const double quaternary = 0.3;
  static const double disabledText = 0.38;
  static const double disabledIcon = 0.38;
  static const double disabledBackground = 0.12;

  // Specific component alpha values with better consistency
  static const double buttonPressed = 0.2;
  static const double buttonHover = 0.08;
  static const double cardHover = 0.04;
  static const double inputFocus = 0.12;
  static const double modalBackdrop = 0.6;
  static const double snackbarBackground = 0.95;
  static const double tooltipBackground = 0.9;
  static const double badgeBackground = 0.1;
  static const double chipBackground = 0.08;
  static const double avatarBorder = 0.2;

  // Enhanced alpha values for better visual hierarchy
  static const double micro = 0.05;
  static const double tiny = 0.1;
  static const double small = 0.2;
  static const double standard = 0.3;
  static const double large = 0.5;
  static const double extraLarge = 0.7;
  static const double huge = 0.9;
}

/// Touch target sizes for accessibility compliance - Enhanced for production with better hierarchy
class TouchTarget {
  static const double minimum = 44.0;
  static const double comfortable = 48.0;
  static const double large = 56.0;

  // Enhanced touch targets for specific components with better hierarchy
  static const double button = 48.0;
  static const double card = 48.0;
  static const double input = 48.0;
  static const double modal = 48.0;
  static const double message = 44.0;
  static const double navigation = 48.0;
  static const double avatar = 48.0;
  static const double badge = 32.0;
  static const double chip = 32.0;
  static const double tooltip = 32.0;

  // Touch targets for different contexts with improved hierarchy
  static const double micro = 32.0;
  static const double small = 40.0;
  static const double medium = 48.0;
  static const double standard = 56.0;
  static const double extraLarge = 64.0;
  static const double huge = 80.0;

  // Specific component touch targets with better consistency
  static const double chatBubble = 44.0;
  static const double actionButton = 48.0;
  static const double floatingButton = 56.0;
  static const double bottomSheet = 48.0;
  static const double dialog = 48.0;
  static const double snackbar = 48.0;
  static const double tabBar = 48.0;
  static const double appBar = 48.0;
  static const double listItem = 48.0;
  static const double formField = 48.0;
  static const double iconButton = 48.0;
  static const double textButton = 44.0;
  static const double toggle = 48.0;
  static const double slider = 48.0;
  static const double checkbox = 48.0;
  static const double radio = 48.0;
}

/// Animation durations for consistent motion design - Enhanced for production with better hierarchy
class AnimationDuration {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration slower = Duration(milliseconds: 800);
  static const Duration slowest = Duration(milliseconds: 1000);
  static const Duration extraSlow = Duration(milliseconds: 1200);
  static const Duration ultra = Duration(milliseconds: 1500);
  static const Duration extended = Duration(seconds: 2);
  static const Duration long = Duration(seconds: 4);

  // Enhanced durations for specific interactions with better hierarchy
  static const Duration microInteraction = Duration(milliseconds: 150);
  static const Duration buttonPress = Duration(milliseconds: 100);
  static const Duration cardHover = Duration(milliseconds: 200);
  static const Duration pageTransition = Duration(milliseconds: 400);
  static const Duration modalPresentation = Duration(milliseconds: 500);
  static const Duration typingIndicator = Duration(milliseconds: 800);
  static const Duration messageAppear = Duration(milliseconds: 350);
  static const Duration messageSlide = Duration(milliseconds: 400);

  // Enhanced durations for better visual hierarchy
  static const Duration micro = Duration(milliseconds: 50);
  static const Duration tiny = Duration(milliseconds: 100);
  static const Duration small = Duration(milliseconds: 200);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration large = Duration(milliseconds: 500);
  static const Duration extraLarge = Duration(milliseconds: 800);
  static const Duration huge = Duration(milliseconds: 1200);
}

/// Animation curves for consistent motion design - Enhanced for production with better hierarchy
class AnimationCurves {
  static const Curve easeIn = Curves.easeIn;
  static const Curve easeOut = Curves.easeOut;
  static const Curve easeInOut = Curves.easeInOut;
  static const Curve bounce = Curves.bounceOut;
  static const Curve elastic = Curves.elasticOut;
  static const Curve fastOutSlowIn = Curves.fastOutSlowIn;
  static const Curve linear = Curves.linear;

  // Enhanced curves for specific interactions with better hierarchy
  static const Curve buttonPress = Curves.easeOutCubic;
  static const Curve cardHover = Curves.easeInOutCubic;
  static const Curve messageSlide = Curves.easeOutCubic;
  static const Curve typingIndicator = Curves.easeInOut;
  static const Curve modalPresentation = Curves.easeOutBack;
  static const Curve pageTransition = Curves.easeInOutCubic;
  static const Curve microInteraction = Curves.easeOutQuart;
  static const Curve spring = Curves.elasticOut;

  // Enhanced curves for better visual hierarchy
  static const Curve micro = Curves.easeOutQuart;
  static const Curve tiny = Curves.easeOutCubic;
  static const Curve small = Curves.easeInOutCubic;
  static const Curve standard = Curves.easeInOut;
  static const Curve large = Curves.easeOutBack;
  static const Curve extraLarge = Curves.elasticOut;
  static const Curve huge = Curves.bounceOut;
}

/// Common animation values - Enhanced for production with better hierarchy
class AnimationValues {
  static const double fadeInOpacity = 0.0;
  static const double fadeOutOpacity = 1.0;
  static const Offset slideInFromTop = Offset(0, -0.05);
  static const Offset slideInFromBottom = Offset(0, 0.05);
  static const Offset slideInFromLeft = Offset(-0.05, 0);
  static const Offset slideInFromRight = Offset(0.05, 0);
  static const Offset slideCenter = Offset.zero;
  static const double scaleMin = 0.0;
  static const double scaleMax = 1.0;
  static const double shimmerBegin = -1.0;
  static const double shimmerEnd = 2.0;

  // Enhanced values for specific interactions with better hierarchy
  static const double buttonScalePressed = 0.95;
  static const double buttonScaleHover = 1.02;
  static const double cardScaleHover = 1.01;
  static const double messageSlideDistance = 0.1;
  static const double typingIndicatorScale = 0.8;
  static const double modalScale = 0.9;
  static const double pageSlideDistance = 0.15;
  static const double microInteractionScale = 0.98;

  // Enhanced values for better visual hierarchy
  static const double micro = 0.95;
  static const double tiny = 0.98;
  static const double small = 1.01;
  static const double standard = 1.02;
  static const double large = 1.05;
  static const double extraLarge = 1.1;
  static const double huge = 1.2;
}

/// Delay values for staggered animations - Enhanced for production with better hierarchy
class AnimationDelay {
  static const Duration none = Duration.zero;
  static const Duration short = Duration(milliseconds: 100);
  static const Duration medium = Duration(milliseconds: 200);
  static const Duration long = Duration(milliseconds: 400);
  static const Duration extraLong = Duration(milliseconds: 600);
  static const Duration ultra = Duration(milliseconds: 800);

  // Enhanced delays for specific interactions with better hierarchy
  static const Duration microDelay = Duration(milliseconds: 50);
  static const Duration buttonDelay = Duration(milliseconds: 75);
  static const Duration cardDelay = Duration(milliseconds: 150);
  static const Duration messageDelay = Duration(milliseconds: 100);
  static const Duration typingDelay = Duration(milliseconds: 200);
  static const Duration modalDelay = Duration(milliseconds: 300);
  static const Duration pageDelay = Duration(milliseconds: 250);
  static const Duration staggeredDelay = Duration(milliseconds: 50);

  // Enhanced delays for better visual hierarchy
  static const Duration micro = Duration(milliseconds: 25);
  static const Duration tiny = Duration(milliseconds: 50);
  static const Duration small = Duration(milliseconds: 100);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration large = Duration(milliseconds: 400);
  static const Duration extraLarge = Duration(milliseconds: 600);
  static const Duration huge = Duration(milliseconds: 800);
}
