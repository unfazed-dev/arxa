import 'package:flutter/material.dart';

class ArxaKitOutlineOnHover extends StatefulWidget {
  final Widget child;
  final Color hoverOutlineColor;
  final double outlineWidth;

  const ArxaKitOutlineOnHover({
    super.key,
    required this.child,
    required this.hoverOutlineColor,
    this.outlineWidth = 2,
  });

  @override
  State<ArxaKitOutlineOnHover> createState() => _OutlineOnHoverState();
}

class _OutlineOnHoverState extends State<ArxaKitOutlineOnHover> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (e) => _mouseEnter(true),
      onExit: (e) => _mouseEnter(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                widget.hoverOutlineColor.withValues(alpha: _hovering ? 0.3 : 0),
            width: widget.outlineWidth,
          ),
        ),
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
