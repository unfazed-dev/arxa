import 'package:flutter/material.dart';
import 'package:m3e_design/m3e_design.dart';

import 'enums.dart';
import 'extended_fab_m3e.dart';

class FabMenuItem {
  FabMenuItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  final Widget icon;
  final Widget label;
  final VoidCallback onPressed;
  final String? semanticLabel;
}

class FabMenuController extends ChangeNotifier {
  bool _open = false;
  bool get isOpen => _open;
  void open() {
    if (!_open) {
      _open = true;
      notifyListeners();
    }
  }

  void close() {
    if (_open) {
      _open = false;
      notifyListeners();
    }
  }

  void toggle() {
    _open = !_open;
    notifyListeners();
  }
}

class FabMenuM3E extends StatefulWidget {
  const FabMenuM3E({
    super.key,
    required this.primaryFab,
    required this.items,
    this.direction = FabMenuDirection.up,
    this.spacing,
    this.overlay = true,
    this.overlayColor,
    this.controller,
    this.alignment = Alignment.bottomRight,
    this.popOnItemTap = true,
    this.heroTag,
  });

  /// The FAB that toggles the menu (typically a primary FabM3E or ExtendedFabM3E).
  final Widget primaryFab;

  /// Menu items displayed when open.
  final List<FabMenuItem> items;

  /// Direction in which children expand.
  final FabMenuDirection direction;

  /// Spacing between items.
  final double? spacing;

  /// Show a scrim overlay behind the menu when open.
  final bool overlay;
  final Color? overlayColor;

  /// Optional external controller; if omitted, an internal one is created.
  final FabMenuController? controller;

  /// Alignment within the Stack (e.g., bottomRight in a Scaffold).
  final Alignment alignment;

  /// Whether to automatically close the menu when an item is tapped.
  final bool popOnItemTap;

  final Object? heroTag;

  @override
  State<FabMenuM3E> createState() => _FabMenuM3EState();
}

class _FabMenuM3EState extends State<FabMenuM3E>
    with SingleTickerProviderStateMixin {
  late final FabMenuController _controller =
      widget.controller ?? FabMenuController();
  // Patched (vendored fork): the M3E FAB Menu reveals items with a staggered
  // spring from the FAB, so a slightly longer forward window keeps the cascade
  // legible (200ms was too tight to read the stagger).
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 200),
  );

  // Fraction of the timeline used to spread item start times (the stagger); the
  // remaining (1 - spread) is each item's own reveal window.
  static const double _staggerSpread = 0.5;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    if (widget.controller == null) _controller.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onChange() {
    if (_controller.isOpen) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.m3e.spacing; // use spacing scale via context extension
    final gap = widget.spacing ?? sp.md;

    final children = <Widget>[];

    // M3E: items spring from the FAB, staggered (the item nearest the FAB leads),
    // each scaling from the corner that faces the FAB rather than a shared centre
    // origin. Interval.transform on the raw controller value avoids allocating a
    // CurvedAnimation per item per build (which would leak in Flutter 3.44).
    final int n = widget.items.length;
    final Alignment origin = _originFor(widget.direction);
    for (int i = 0; i < n; i++) {
      final item = widget.items[i];
      final double startT = n <= 1 ? 0.0 : (i / (n - 1)) * _staggerSpread;
      final double endT = n <= 1 ? 1.0 : startT + (1.0 - _staggerSpread);
      final Interval interval =
          Interval(startT, endT, curve: Curves.easeOutCubic);
      final w = _buildMenuItem(context, item);
      final animatedChild = AnimatedBuilder(
        animation: _anim,
        child: w,
        builder: (context, child) {
          final double t = interval.transform(_anim.value.clamp(0.0, 1.0));
          return Opacity(
            opacity: t,
            child: Transform.scale(scale: t, alignment: origin, child: child),
          );
        },
      );
      // Positioned must be a direct child of the Stack.
      children.add(_positioned(animatedChild, i, gap));
    }

    final menu = Stack(
      alignment: widget.alignment,
      clipBehavior: Clip.none,
      children: [
        // Primary FAB
        Align(
          alignment: widget.alignment,
          child: _wrapToggle(widget.primaryFab),
        ),
        // Menu items
        ...children,
      ],
    );

    final overlay = widget.overlay && _controller.isOpen
        ? Positioned.fill(
            child: GestureDetector(
              onTap: _controller.toggle,
              child: ColoredBox(
                color:
                    widget.overlayColor ?? Colors.black.withValues(alpha: 0.25),
              ),
            ),
          )
        : const SizedBox.shrink();

    return Stack(
      children: [
        overlay,
        Positioned.fill(
            child: IgnorePointer(
                ignoring: !_controller.isOpen, child: Container())),
        menu,
      ],
    );
  }

  Widget _wrapToggle(Widget child) {
    final core = GestureDetector(
      onTap: _controller.toggle,
      behavior: HitTestBehavior.opaque,
      child: child,
    );

    if (widget.heroTag != null && context.findAncestorWidgetOfExactType<Hero>() == null) {
      return Hero(tag: widget.heroTag!, child: core);
    }
    return core;
  }

  Widget _positioned(Widget child, int index, double gap) {
    final offset = (index + 1) *
        (gap +
            56); // base step; extended affects height, but 56 is a practical default
    switch (widget.direction) {
      case FabMenuDirection.up:
        return Positioned(
          right: 0,
          bottom: offset,
          child: child,
        );
      case FabMenuDirection.down:
        return Positioned(
          right: 0,
          top: offset,
          child: child,
        );
      case FabMenuDirection.left:
        return Positioned(
          right: offset,
          bottom: 0,
          child: child,
        );
      case FabMenuDirection.right:
        return Positioned(
          left: offset,
          bottom: 0,
          child: child,
        );
    }
  }

  // Scale origin for each item: the corner facing the FAB, so items appear to
  // grow out of it (M3E) instead of ballooning from their own centre.
  Alignment _originFor(FabMenuDirection d) {
    switch (d) {
      case FabMenuDirection.up:
        return Alignment.bottomRight;
      case FabMenuDirection.down:
        return Alignment.topRight;
      case FabMenuDirection.left:
        return Alignment.centerRight;
      case FabMenuDirection.right:
        return Alignment.centerLeft;
    }
  }

  Widget _buildMenuItem(BuildContext context, FabMenuItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: ExtendedFabM3E(
        icon: item.icon,
        label: item.label,
        onPressed: () {
          item.onPressed();
          if (widget.popOnItemTap) _controller.close();
        },
        kind: FabM3EKind.surface,
        size: FabM3ESize.regular,
        density: FabM3EDensity.regular,
        semanticLabel: item.semanticLabel,
      ),
    );
  }
}
