import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

/// Enhanced keyboard handling utilities for better UX
class KeyboardUtils {
  KeyboardUtils._();

  /// Dismiss keyboard with haptic feedback
  static void dismissKeyboard(BuildContext context) {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      FocusManager.instance.primaryFocus?.unfocus();

      // Add haptic feedback on iOS
      if (Platform.isIOS) {
        HapticFeedback.lightImpact();
      }
    }
  }

  /// Force dismiss keyboard immediately
  static void forceDismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// Check if keyboard is currently visible
  static bool isKeyboardVisible(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom > 0;
  }

  /// Get keyboard height
  static double getKeyboardHeight(BuildContext context) {
    return MediaQuery.of(context).viewInsets.bottom;
  }

  /// Move focus to next field
  static void nextFocus(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }

  /// Move focus to previous field
  static void previousFocus(BuildContext context) {
    FocusScope.of(context).previousFocus();
  }

  /// Request focus for a specific node
  static void requestFocus(BuildContext context, FocusNode focusNode) {
    FocusScope.of(context).requestFocus(focusNode);
  }

  /// Create a tap detector that dismisses keyboard when tapping outside text fields
  static Widget dismissKeyboardOnTap({
    required BuildContext context,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: () => dismissKeyboard(context),
      // Let children handle taps first (e.g., TextField gains focus)
      behavior: HitTestBehavior.deferToChild,
      child: child,
    );
  }
}

/// Widget that automatically adjusts for keyboard visibility
class KeyboardAware extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final bool maintainBottomViewPadding;
  final Duration animationDuration;
  final Curve animationCurve;

  const KeyboardAware({
    super.key,
    required this.child,
    this.padding,
    this.maintainBottomViewPadding = true,
    this.animationDuration = const Duration(milliseconds: 250),
    this.animationCurve = Curves.easeInOut,
  });

  @override
  State<KeyboardAware> createState() => _KeyboardAwareState();
}

class _KeyboardAwareState extends State<KeyboardAware>
    with WidgetsBindingObserver {
  double _keyboardHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final newKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (newKeyboardHeight != _keyboardHeight) {
      setState(() {
        _keyboardHeight = newKeyboardHeight;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: widget.animationDuration,
      curve: widget.animationCurve,
      padding: EdgeInsets.only(
        bottom: widget.maintainBottomViewPadding ? _keyboardHeight : 0,
      ).add(widget.padding ?? EdgeInsets.zero),
      child: widget.child,
    );
  }
}

/// Enhanced text field with better keyboard handling
class EnhancedTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final EdgeInsets? contentPadding;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool autofocus;
  final bool dismissKeyboardOnSubmit;

  const EnhancedTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.contentPadding,
    this.prefixIcon,
    this.suffixIcon,
    this.autofocus = false,
    this.dismissKeyboardOnSubmit = true,
  });

  @override
  State<EnhancedTextField> createState() => _EnhancedTextFieldState();
}

class _EnhancedTextFieldState extends State<EnhancedTextField> {
  late FocusNode _focusNode;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _hasFocus = _focusNode.hasFocus;
    });
  }

  void _handleSubmitted(String value) {
    widget.onSubmitted?.call(value);

    if (widget.dismissKeyboardOnSubmit) {
      KeyboardUtils.dismissKeyboard(context);
    }

    // Add haptic feedback
    if (Platform.isIOS) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        border: Border.all(
          color: _hasFocus
              ? context.conduitTheme.buttonPrimary
              : context.conduitTheme.inputBorder,
          width: _hasFocus ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(AppBorderRadius.md),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        style: TextStyle(
          color: context.conduitTheme.textPrimary,
          fontSize: AppTypography.bodyLarge,
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          labelText: widget.labelText,
          hintStyle: TextStyle(color: context.conduitTheme.inputPlaceholder),
          labelStyle: TextStyle(
            color: _hasFocus
                ? context.conduitTheme.buttonPrimary
                : context.conduitTheme.textSecondary,
          ),
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          contentPadding:
              widget.contentPadding ??
              const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
        onChanged: widget.onChanged,
        onSubmitted: _handleSubmitted,
        onTap: widget.onTap,
      ),
    );
  }
}

/// Smart keyboard handler that manages multiple text fields
class SmartKeyboardHandler extends StatefulWidget {
  final List<FocusNode> focusNodes;
  final Widget child;
  final VoidCallback? onDone;

  const SmartKeyboardHandler({
    super.key,
    required this.focusNodes,
    required this.child,
    this.onDone,
  });

  @override
  State<SmartKeyboardHandler> createState() => _SmartKeyboardHandlerState();
}

class _SmartKeyboardHandlerState extends State<SmartKeyboardHandler> {
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _setupFocusListeners();
  }

  void _setupFocusListeners() {
    for (int i = 0; i < widget.focusNodes.length; i++) {
      widget.focusNodes[i].addListener(() => _onFocusChanged(i));
    }
  }

  void _onFocusChanged(int index) {
    if (widget.focusNodes[index].hasFocus) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _moveToNext() {
    if (_currentIndex < widget.focusNodes.length - 1) {
      KeyboardUtils.requestFocus(context, widget.focusNodes[_currentIndex + 1]);
    } else {
      KeyboardUtils.dismissKeyboard(context);
      widget.onDone?.call();
    }
  }

  void _moveToPrevious() {
    if (_currentIndex > 0) {
      KeyboardUtils.requestFocus(context, widget.focusNodes[_currentIndex - 1]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.tab) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              _moveToPrevious();
            } else {
              _moveToNext();
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    for (final focusNode in widget.focusNodes) {
      focusNode.removeListener(() {});
    }
    super.dispose();
  }
}

/// Keyboard-aware scroll view that adjusts scroll position
class KeyboardAwareScrollView extends StatefulWidget {
  final ScrollController? controller;
  final Widget child;
  final EdgeInsets? padding;
  final bool reverse;
  final Duration animationDuration;

  const KeyboardAwareScrollView({
    super.key,
    this.controller,
    required this.child,
    this.padding,
    this.reverse = false,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<KeyboardAwareScrollView> createState() =>
      _KeyboardAwareScrollViewState();
}

class _KeyboardAwareScrollViewState extends State<KeyboardAwareScrollView>
    with WidgetsBindingObserver {
  late ScrollController _scrollController;
  FocusNode? _currentFocus;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _adjustScrollPosition();
  }

  void _adjustScrollPosition() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus != _currentFocus) {
      _currentFocus = focus;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          if (keyboardHeight > 0) {
            _scrollController.animateTo(
              _scrollController.offset + keyboardHeight / 2,
              duration: widget.animationDuration,
              curve: Curves.easeInOut,
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      reverse: widget.reverse,
      padding: widget.padding,
      child: widget.child,
    );
  }
}
