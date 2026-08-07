/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a hover-scale effect. It enlarges a child
/// when the mouse enters and returns it when the mouse leaves, animated with
/// an ease-out curve.
///
/// Requirements:
/// 1. [Hover scale]
/// Scales the child on mouse hover and animates the transition.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/mouse_transforms/scale_on_hover_widget.dart
library;

import 'package:flutter/material.dart';

class ScaleOnHoverWidget extends StatefulWidget {
  final double scale;
  final Widget child;
  // You can also pass the translation in here if you want to
  const ScaleOnHoverWidget({super.key, required this.child, this.scale = 1.1});

  @override
  State<ScaleOnHoverWidget> createState() => _ScaleOnHoverState();
}

class _ScaleOnHoverState extends State<ScaleOnHoverWidget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scaleTransform = Matrix4.identity()
      ..scaleByDouble(widget.scale, widget.scale, widget.scale, 1);
    final noScaleTransform = Matrix4.identity();
    return MouseRegion(
      onEnter: (e) => _mouseEnter(true),
      onExit: (e) => _mouseEnter(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCirc,
        transform: _hovering ? scaleTransform : noScaleTransform,
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
