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
