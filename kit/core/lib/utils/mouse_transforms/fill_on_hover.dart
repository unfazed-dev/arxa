import 'package:flutter/material.dart';

class FillOnHover extends StatefulWidget {
  final Widget? child;
  final Color fillColor;
  final double opacity;
  final BorderRadius borderRadius;
  final bool disabled;

  const FillOnHover({
    super.key,
    this.child,
    required this.fillColor,
    this.opacity = 0.1,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.disabled = false,
  });

  @override
  State<FillOnHover> createState() => _FillOnHoverState();
}

class _FillOnHoverState extends State<FillOnHover> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.disabled ? null : (e) => _mouseEnter(true),
      onExit: widget.disabled ? null : (e) => _mouseEnter(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: (_hovering && !widget.disabled)
              ? widget.fillColor.withValues(alpha: widget.opacity)
              : Colors.transparent,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child ?? const SizedBox(),
      ),
    );
  }

  void _mouseEnter(bool hover) {
    setState(() {
      _hovering = hover;
    });
  }
}
