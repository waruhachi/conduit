import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

/// Comprehensive focus management service for accessibility
class FocusManagementService {
  static final Map<String, FocusNode> _focusNodes = {};
  static final Map<String, FocusNode> _disposedNodes = {};
  static FocusNode? _lastFocusedNode;
  static final List<FocusNode> _focusHistory = [];

  /// Register a focus node with a unique identifier
  static FocusNode registerFocusNode(
    String identifier, {
    String? debugLabel,
    FocusOnKeyEventCallback? onKeyEvent,
    bool skipTraversal = false,
    bool canRequestFocus = true,
  }) {
    // Check if node already exists
    if (_focusNodes.containsKey(identifier)) {
      return _focusNodes[identifier]!;
    }

    // Create new focus node
    final focusNode = FocusNode(
      debugLabel: debugLabel ?? identifier,
      onKeyEvent: onKeyEvent,
      skipTraversal: skipTraversal,
      canRequestFocus: canRequestFocus,
    );

    // Add listener to track focus changes
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        _onFocusChanged(focusNode);
      }
    });

    _focusNodes[identifier] = focusNode;
    return focusNode;
  }

  /// Get a registered focus node
  static FocusNode? getFocusNode(String identifier) {
    return _focusNodes[identifier];
  }

  /// Dispose a focus node
  static void disposeFocusNode(String identifier) {
    final node = _focusNodes.remove(identifier);
    if (node != null) {
      _disposedNodes[identifier] = node;
      node.dispose();
    }
  }

  /// Dispose all focus nodes
  static void disposeAll() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusHistory.clear();
    _lastFocusedNode = null;
  }

  /// Request focus for a specific node
  static void requestFocus(String identifier) {
    final node = _focusNodes[identifier];
    if (node != null && node.canRequestFocus) {
      node.requestFocus();
      HapticFeedback.selectionClick();
    }
  }

  /// Unfocus current focus
  static void unfocus(
    BuildContext context, {
    UnfocusDisposition disposition = UnfocusDisposition.scope,
  }) {
    FocusScope.of(context).unfocus(disposition: disposition);
  }

  /// Move focus to next focusable element
  static bool nextFocus(BuildContext context) {
    return FocusScope.of(context).nextFocus();
  }

  /// Move focus to previous focusable element
  static bool previousFocus(BuildContext context) {
    return FocusScope.of(context).previousFocus();
  }

  /// Track focus changes
  static void _onFocusChanged(FocusNode node) {
    _lastFocusedNode = node;
    _focusHistory.add(node);

    // Limit history size
    if (_focusHistory.length > 10) {
      _focusHistory.removeAt(0);
    }
  }

  /// Restore last focus
  static void restoreLastFocus() {
    if (_lastFocusedNode != null && _lastFocusedNode!.canRequestFocus) {
      _lastFocusedNode!.requestFocus();
    }
  }

  /// Get focus history
  static List<FocusNode> getFocusHistory() {
    return List.unmodifiable(_focusHistory);
  }

  /// Create a focus trap for modal dialogs
  static Widget createFocusTrap({
    required Widget child,
    bool autofocus = true,
  }) {
    return FocusScope(autofocus: autofocus, child: child);
  }

  /// Create keyboard navigation handler
  static FocusOnKeyEventCallback createKeyboardNavigationHandler({
    VoidCallback? onEnter,
    VoidCallback? onEscape,
    VoidCallback? onTab,
    VoidCallback? onArrowUp,
    VoidCallback? onArrowDown,
    VoidCallback? onArrowLeft,
    VoidCallback? onArrowRight,
  }) {
    return (FocusNode node, KeyEvent event) {
      if (event is! KeyDownEvent) {
        return KeyEventResult.ignored;
      }

      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        onEnter?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.escape) {
        onEscape?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.tab) {
        onTab?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowUp) {
        onArrowUp?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowDown) {
        onArrowDown?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowLeft) {
        onArrowLeft?.call();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowRight) {
        onArrowRight?.call();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    };
  }
}

/// Focus manager widget that manages focus for its children
class FocusManager extends StatefulWidget {
  final Widget child;
  final bool autofocus;
  final bool trapFocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  const FocusManager({
    super.key,
    required this.child,
    this.autofocus = false,
    this.trapFocus = false,
    this.onKeyEvent,
  });

  @override
  State<FocusManager> createState() => _FocusManagerState();
}

class _FocusManagerState extends State<FocusManager> {
  late FocusScopeNode _focusScopeNode;

  @override
  void initState() {
    super.initState();
    _focusScopeNode = FocusScopeNode(
      debugLabel: 'FocusManager',
      onKeyEvent: widget.onKeyEvent,
    );
  }

  @override
  void dispose() {
    _focusScopeNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = FocusScope(
      node: _focusScopeNode,
      autofocus: widget.autofocus,
      child: widget.child,
    );

    if (widget.trapFocus) {
      child = FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: child,
      );
    }

    return child;
  }
}

/// Accessible form field with proper focus management
class AccessibleFormField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final String? semanticLabel;
  final String? errorSemanticLabel;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final int? maxLength;
  final bool enabled;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final FocusNode? focusNode;

  const AccessibleFormField({
    super.key,
    required this.label,
    this.hint,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.semanticLabel,
    this.errorSemanticLabel,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.suffixIcon,
    this.prefixIcon,
    this.focusNode,
  });

  @override
  State<AccessibleFormField> createState() => _AccessibleFormFieldState();
}

class _AccessibleFormFieldState extends State<AccessibleFormField> {
  late FocusNode _focusNode;
  String? _errorText;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: widget.label);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _hasFocus = _focusNode.hasFocus;
    });

    // Announce focus change for screen readers
    if (_hasFocus) {
      final announcement =
          widget.semanticLabel ??
          '${widget.label} text field. ${widget.hint ?? ''}';
      SemanticsService.announce(announcement, TextDirection.ltr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      hint: widget.hint,
      textField: true,
      enabled: widget.enabled,
      focusable: true,
      focused: _hasFocus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              widget.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _hasFocus
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: _hasFocus ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),

          // Text field
          TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            validator: (value) {
              final error = widget.validator?.call(value);
              setState(() {
                _errorText = error;
              });

              // Announce error for screen readers
              if (error != null) {
                final errorAnnouncement =
                    widget.errorSemanticLabel ?? 'Error: $error';
                SemanticsService.announce(errorAnnouncement, TextDirection.ltr);
              }

              return error;
            },
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged,
            onEditingComplete: widget.onEditingComplete,
            onFieldSubmitted: widget.onSubmitted,
            inputFormatters: widget.inputFormatters,
            maxLines: widget.maxLines,
            maxLength: widget.maxLength,
            enabled: widget.enabled,
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _errorText,
              suffixIcon: widget.suffixIcon,
              prefixIcon: widget.prefixIcon,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: theme.colorScheme.error,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
