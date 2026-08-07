/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a hover-translate effect. It shifts a child
/// by x/y offsets when the mouse enters and back when the mouse leaves.
///
/// Requirements:
/// 1. [Hover translate]
/// Translates the child on mouse hover and animates the transition.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/mouse_transforms/translate_on_hover_widget.dart
library;

import 'package:flutter/material.dart';

class TranslateOnHoverWidget extends StatefulWidget {
  final Widget child;
  final double? x;
  final double? y;
  // You can also pass the translation in here if you want to
  const TranslateOnHoverWidget({super.key, required this.child, this.x, this.y});

  @override
  State<TranslateOnHoverWidget> createState() => _TranslateOnHoverState();
}

class _TranslateOnHoverState extends State<TranslateOnHoverWidget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final nonHoverTransform = Matrix4.identity();
    final hoverTransform = Matrix4.identity()
      ..translateByDouble(widget.x ?? 0, widget.y ?? 0, 0, 1);
    return MouseRegion(
      onEnter: (e) => _mouseEnter(true),
      onExit: (e) => _mouseEnter(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _hovering ? hoverTransform : nonHoverTransform,
        child: widget.child,
      ),
    );
  }

  void _mouseEnter(bool hover) {
    setState(() {
      _hovering = hover;
    });
  }
}
