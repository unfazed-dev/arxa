import 'package:flutter/widgets.dart';

/// Native-safe press feedback: dims [child] while pressed instead of painting
/// a Material ink splash. Ink needs a [Material] ancestor and its splash
/// paints over the glass tiers (Liquid Glass / M3E platform views) — the leak
/// the notes rows shipped with. This is the one kit-level press affordance;
/// content widgets ([ArxaKitListTile], [ArxaKitChip]) and app rows use it
/// instead of `InkWell`/`InkResponse`.
///
/// With no [onTap] and no [onLongPress] the child is returned untouched (a
/// label row / decorative tag), matching the `InkWell` null-handler idiom it
/// replaces.
class ArxaKitPressable extends StatefulWidget {
  const ArxaKitPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  /// Content the press state dims.
  final Widget child;

  /// Tap handler. `null` with a `null` [onLongPress] disables the affordance.
  final VoidCallback? onTap;

  /// Long-press handler. The dim also tracks the long-press hold, which is
  /// exactly where the ink leak was visible.
  final VoidCallback? onLongPress;

  @override
  State<ArxaKitPressable> createState() => _ArxaKitPressableState();
}

class _ArxaKitPressableState extends State<ArxaKitPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onLongPressStart:
            widget.onLongPress == null ? null : (_) => _setPressed(true),
        onLongPressEnd:
            widget.onLongPress == null ? null : (_) => _setPressed(false),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
