import 'package:flutter/material.dart';
import 'package:m3e_design/m3e_design.dart';

import 'enums.dart';

/// Material 3 Expressive text field.
///
/// The container shape morphs between the resting silhouette
/// ([TextFieldM3EShape.round] / [TextFieldM3EShape.square]) and a squarer
/// focused radius, mirroring the pressed/open morph used across the M3E
/// collection (split button, toolbar, FAB).
class TextFieldM3E extends StatefulWidget {
  const TextFieldM3E({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.size = TextFieldM3ESize.md,
    this.shape = TextFieldM3EShape.round,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.leadingIcon,
    this.trailing,
    this.errorText,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Hint shown when the field is empty.
  final String? placeholder;

  final TextFieldM3ESize size;

  /// Resting outer shape (round/square). Focus morph uses tokens.
  final TextFieldM3EShape shape;

  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Optional leading icon (sized via tokens).
  final IconData? leadingIcon;

  /// Optional trailing widget (e.g. clear button, obscure toggle).
  final Widget? trailing;

  /// When non-null the container shows error styling and this supporting
  /// text is rendered below the field.
  final String? errorText;

  final String? semanticLabel;

  @override
  State<TextFieldM3E> createState() => _TextFieldM3EState();
}

class _TextFieldM3EState extends State<TextFieldM3E> {
  FocusNode? _internalNode;
  bool _focused = false;

  FocusNode get _effectiveNode =>
      widget.focusNode ?? (_internalNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _effectiveNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TextFieldM3E oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalNode)?.removeListener(
        _handleFocusChange,
      );
      _effectiveNode.addListener(_handleFocusChange);
      _focused = _effectiveNode.hasFocus;
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _internalNode)?.removeListener(_handleFocusChange);
    _internalNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final hasFocus = _effectiveNode.hasFocus;
    if (hasFocus != _focused) {
      setState(() => _focused = hasFocus);
    }
  }

  double get _restingRadius => switch (widget.shape) {
        TextFieldM3EShape.round => widget.size.outerRoundRadius,
        TextFieldM3EShape.square => widget.size.outerSquareRadius,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m3e = theme.extension<M3ETheme>() ?? M3ETheme.defaults(scheme);

    final bool hasError = widget.errorText != null;
    final double radius = _focused ? widget.size.focusedRadius : _restingRadius;

    final Color fill = !widget.enabled
        ? scheme.onSurface.withValues(alpha: TextFieldM3ETokens.disabledAlpha)
        : _focused
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerHigh;

    final Color contentColor = widget.enabled
        ? scheme.onSurface
        : scheme.onSurface
            .withValues(alpha: TextFieldM3ETokens.disabledContentAlpha);
    final Color hintColor = widget.enabled
        ? scheme.onSurfaceVariant
        : contentColor;

    final BoxBorder? border = hasError
        ? Border.all(
            color: scheme.error,
            width: TextFieldM3ETokens.focusStrokeWidth,
          )
        : _focused
            ? Border.all(
                color: scheme.primary,
                width: TextFieldM3ETokens.focusStrokeWidth,
              )
            : null;

    final textStyle =
        (theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16))
            .copyWith(color: contentColor);

    final field = AnimatedContainer(
      duration: TextFieldM3ETokens.morphDuration,
      curve: TextFieldM3ETokens.morphCurve,
      constraints: BoxConstraints(
        minHeight: widget.size.height < TextFieldM3ETokens.minTapTarget
            ? widget.size.height
            : TextFieldM3ETokens.minTapTarget,
      ),
      height: widget.size.height,
      padding:
          EdgeInsets.symmetric(horizontal: widget.size.horizontalPadding),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      child: Row(
        children: [
          if (widget.leadingIcon != null) ...[
            Icon(
              widget.leadingIcon,
              size: widget.size.iconPx,
              color: hasError ? scheme.error : hintColor,
            ),
            SizedBox(width: widget.size.gapIconToText),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _effectiveNode,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              obscureText: widget.obscureText,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: textStyle,
              cursorColor: hasError ? scheme.error : scheme.primary,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: textStyle.copyWith(color: hintColor),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            SizedBox(width: widget.size.gapIconToText),
            widget.trailing!,
          ],
        ],
      ),
    );

    Widget result = field;
    if (hasError) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          Padding(
            padding: EdgeInsets.only(
              left: widget.size.horizontalPadding,
              top: m3e.spacing.xs,
            ),
            child: Text(
              widget.errorText!,
              style: (theme.textTheme.bodySmall ??
                      const TextStyle(fontSize: 12))
                  .copyWith(color: scheme.error),
            ),
          ),
        ],
      );
    }

    if (widget.semanticLabel != null) {
      result = Semantics(label: widget.semanticLabel, child: result);
    }
    return result;
  }
}
