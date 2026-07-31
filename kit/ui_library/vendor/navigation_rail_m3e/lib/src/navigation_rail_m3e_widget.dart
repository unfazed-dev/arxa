import 'dart:ui' show lerpDouble;

import 'package:fab_m3e/fab_m3e.dart';
import 'package:flutter/material.dart';
import 'package:icon_button_m3e/icon_button_m3e.dart';

import 'modality.dart';
import 'rail_destination_m3e.dart';
import 'rail_fab_slot.dart';
import 'rail_item.dart';
import 'rail_section_m3e.dart';
import 'rail_theme.dart';
import 'rail_tokens_adapter.dart';
import 'type.dart';

/// Material 3 Expressive Navigation Rail — single widget that animates between states.
class NavigationRailM3E extends StatefulWidget {
  /// Creates a Material 3 Expressive navigation rail.
  const NavigationRailM3E({
    super.key,
    this.type = NavigationRailM3EType.expanded,
    this.modality = NavigationRailM3EModality.standard,
    required this.sections,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.fab,
    this.hideWhenCollapsed = false,
    this.expandedWidth,
    this.onDismissModal,
    this.onTypeChanged,
    this.labelBehavior = NavigationRailM3ELabelBehavior.alwaysShow,
    this.scrollable = true,
    this.trailing,
    this.trailingAtBottom = true,
    this.background,
  });

  /// Presentation type for the rail (collapsed or expanded or alwaysCollapsed or alwaysExpanded).
  final NavigationRailM3EType type;

  /// How the rail is shown (standard or modal overlay).
  final NavigationRailM3EModality modality;

  /// Sections and destinations to display.
  final List<NavigationRailM3ESection> sections;

  /// Index of the currently selected destination.
  final int selectedIndex;

  /// Called when a destination is selected.
  final ValueChanged<int> onDestinationSelected;

  /// Optional FAB/extended FAB shown near the top cluster.
  final NavigationRailM3EFabSlot? fab;

  /// When [type] is collapsed and this is true, rail animates to width 0.
  final bool hideWhenCollapsed;

  /// Custom expanded width (220–360). Clamped to theme bounds.
  final double? expandedWidth;

  /// Called to dismiss when in modal mode.
  final VoidCallback? onDismissModal;

  /// Called when the built-in menu button toggles the rail type.
  final ValueChanged<NavigationRailM3EType>? onTypeChanged;

  /// Controls how labels are shown when the rail is expanded.
  final NavigationRailM3ELabelBehavior labelBehavior;

  /// Whether the rail's main content area should be scrollable.
  /// Defaults to true to match the current behavior.
  final bool scrollable;

  /// Optional trailing widget, always conceptually placed after the sections.
  /// When [trailingAtBottom] is true, it's pinned to the bottom of the rail,
  /// leaving flexible space between the sections and the trailing.
  /// When false, it's inserted immediately after the sections within the content.
  final Widget? trailing;

  /// Controls where the trailing is placed relative to the rail's bottom.
  /// If true, [trailing] is pinned to the bottom with space to the sections.
  /// If false, [trailing] appears directly after the sections.
  final bool trailingAtBottom;

  /// Optional background color for the rail. If null, falls back to
  /// [NavigationRailTokensAdapter.containerColor] from the current theme.
  final Color? background;

  @override
  State<NavigationRailM3E> createState() => _NavigationRailM3EState();
}

class _NavigationRailM3EState extends State<NavigationRailM3E>
    with TickerProviderStateMixin {
  OverlayEntry? _modalEntry;
  OverlayEntry? _collapsedPeekEntry;
  final LayerLink _anchor = LayerLink();
  bool _suppressInk = false;

  // Internal expanded/collapsed state. Initialized from widget.type and then
  // controlled internally by the rail's menu button.
  bool _expanded = false;

  // Fork patch: ONE explicit controller drives the width AND both layer
  // opacities, so every effect is synchronized frame-for-frame and collapse
  // is the exact time-reverse of expand (controller.reverse()). Upstream
  // chained implicit animations (AnimatedContainer width + a discrete layout
  // swap), which desynced and read as lag.
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: _expandDuration,
    value: _expanded ? 1.0 : 0.0,
  );

  /// Width progress — the M3E default spatial spring (web-fallback cubic).
  /// The reverse curve is the flipped spring: a straight time-reversal would
  /// spend its first ~300ms inside the spring's settle/overshoot tail (width
  /// frozen at ~220), which reads as lag; flipped, the collapse starts
  /// moving immediately and lands with the same gentle spring settle.
  late final Animation<double> _widthT = CurvedAnimation(
    parent: _transition,
    curve: _expandCurve,
    reverseCurve: _expandCurve.flipped,
  );

  /// Layer opacities — Material fade-through on sub-intervals of the SAME
  /// controller (outgoing layout fades first, incoming after; no overshoot —
  /// the M3E effects role).
  late final Animation<double> _collapsedOpacity =
      Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
    parent: _transition,
    curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
  ));
  late final Animation<double> _expandedOpacity = CurvedAnimation(
    parent: _transition,
    curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
  );

  void _applyExpanded(bool value) {
    _expanded = value;
    if (value) {
      _transition.forward();
    } else {
      _transition.reverse();
    }
  }

  bool get _isExpanded => _expanded;
  bool get _isModal => widget.modality == NavigationRailM3EModality.modal;
  bool get _needsOverlay => _isModal && _isExpanded;
  bool get _needsCollapsedPeek =>
      !_isExpanded && !_isModal && widget.hideWhenCollapsed && _canToggle;

  bool get _canToggle =>
      widget.type == NavigationRailM3EType.collapsed ||
      widget.type == NavigationRailM3EType.expanded;

  NavigationRailM3EType get _notifiedType => _expanded
      ? NavigationRailM3EType.expanded
      : NavigationRailM3EType.collapsed;

  @override
  void initState() {
    super.initState();
    // Initialize internal expanded state from the provided type.
    // When toggleable (collapsed/expanded), mirror the provided type.
    // When locked (alwaysCollapse/alwaysExpand), infer via enum name.
    if (_canToggle) {
      _expanded = widget.type == NavigationRailM3EType.expanded;
    } else {
      final name = widget.type.toString();
      final isAlwaysCollapse = name.contains('alwaysCollapse');
      _expanded = !isAlwaysCollapse; // alwaysExpand => true
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  @override
  void didUpdateWidget(covariant NavigationRailM3E oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Suppress ink effects briefly during type transitions to avoid flicker.
    if (oldWidget.type != widget.type) {
      setState(() => _suppressInk = true);
      // Fork patch: 560ms — must outlast the 500ms expand animation.
      Future.delayed(const Duration(milliseconds: 560), () {
        if (mounted) setState(() => _suppressInk = false);
      });
    }

    // Keep internal state in sync with locking semantics of `always*` types.
    final bool oldCanToggle =
        oldWidget.type == NavigationRailM3EType.collapsed ||
            oldWidget.type == NavigationRailM3EType.expanded;
    final bool newCanToggle = _canToggle;

    if (!newCanToggle) {
      // Force the locked state.
      final name = widget.type.toString();
      final bool lockExpanded = !name.contains('alwaysCollapse');
      if (_expanded != lockExpanded) {
        setState(() => _applyExpanded(lockExpanded));
      }
    } else if (!oldCanToggle && newCanToggle) {
      // Transition from locked to toggleable: seed from the new default.
      final bool startExpanded = widget.type == NavigationRailM3EType.expanded;
      if (_expanded != startExpanded) {
        setState(() => _applyExpanded(startExpanded));
      }
    } else if (oldWidget.type != widget.type) {
      // Fork patch: honor host-driven collapsed <-> expanded changes too —
      // upstream only synced the locked `always*` types, so a host toggling
      // `type` after first build was silently ignored.
      final bool hostExpanded = widget.type == NavigationRailM3EType.expanded;
      if (_expanded != hostExpanded) {
        setState(() => _applyExpanded(hostExpanded));
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());
  }

  @override
  void dispose() {
    _transition.dispose();
    _removeOverlay();
    _removeCollapsedPeekOverlay();
    super.dispose();
  }

  void _syncOverlay() {
    if (!mounted) return;

    // Expanded modal overlay management
    if (_needsOverlay) {
      if (_modalEntry == null) {
        _insertOverlay();
      } else {
        _modalEntry!.markNeedsBuild();
      }
    } else {
      _removeOverlay();
    }

    // Collapsed peek overlay management (standard modality with hideWhenCollapsed)
    if (_needsCollapsedPeek) {
      if (_collapsedPeekEntry == null) {
        _insertCollapsedPeekOverlay();
      } else {
        _collapsedPeekEntry!.markNeedsBuild();
      }
    } else {
      _removeCollapsedPeekOverlay();
    }
  }

  void _insertOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _modalEntry = OverlayEntry(builder: (ctx) => _buildModalOverlay(ctx));
    overlay.insert(_modalEntry!);
  }

  void _removeOverlay() {
    _modalEntry?.remove();
    _modalEntry = null;
  }

  void _insertCollapsedPeekOverlay() {
    final overlay = Overlay.of(context, rootOverlay: true);
    _collapsedPeekEntry =
        OverlayEntry(builder: (ctx) => _buildCollapsedPeekOverlay(ctx));
    overlay.insert(_collapsedPeekEntry!);
  }

  void _removeCollapsedPeekOverlay() {
    _collapsedPeekEntry?.remove();
    _collapsedPeekEntry = null;
  }

  void _setExpanded(bool value) {
    if (_expanded == value) return;
    setState(() {
      _applyExpanded(value);
      _suppressInk = true;
    });
    // Fork patch: 560ms — must outlast the 500ms expand animation.
    Future.delayed(const Duration(milliseconds: 560), () {
      if (mounted) setState(() => _suppressInk = false);
    });
    // Notify listeners (if any) for backward compatibility.
    widget.onTypeChanged?.call(_notifiedType);
  }

  Widget _buildModalOverlay(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isExpanded,
            child: GestureDetector(
              onTap: widget.onDismissModal,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                color: Theme.of(context)
                    .colorScheme
                    .scrim
                    .withValues(alpha: _isExpanded ? 0.32 : 0.0),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Material(
            type: MaterialType.transparency,
            child: _buildRailCore(context),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedPeekOverlay(BuildContext context) {
    // A small floating menu button anchored to the rail's target, visible when
    // the rail is fully hidden (hideWhenCollapsed == true).
    Widget btn = IconButtonM3E(
      icon: const Icon(Icons.menu),
      tooltip: 'Expand',
      onPressed: _canToggle ? () => _setExpanded(true) : null,
    );
    if (_suppressInk) {
      final t = Theme.of(context);
      btn = Theme(
        data: t.copyWith(
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: btn,
      );
    }

    return CompositedTransformFollower(
      link: _anchor,
      showWhenUnlinked: false,
      offset: const Offset(8, 36), // slight inset and same top spacing as rail
      child: Material(
        type: MaterialType.transparency,
        child: btn,
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, {required bool isExpanded}) {
    if (!_canToggle) return const SizedBox.shrink();

    final alignment = isExpanded ? Alignment.centerLeft : Alignment.center;
    Widget button = IconButtonM3E(
      icon: Icon(isExpanded ? Icons.menu_open : Icons.menu),
      tooltip: isExpanded ? 'Collapse' : 'Expand',
      onPressed: () => _setExpanded(!isExpanded),
    );

    if (_suppressInk) {
      final t = Theme.of(context);
      button = Theme(
        data: t.copyWith(
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 12),
      child: Align(
        alignment: alignment,
        child: button,
      ),
    );
  }

  Widget? _buildFab(BuildContext context, {required bool isExpanded}) {
    final fab = widget.fab;
    if (fab == null) return null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 12),
      child: isExpanded
          ? ExtendedFabM3E(
              label: Text(fab.label),
              icon: fab.icon,
              onPressed: fab.onPressed,
              tooltip: fab.tooltip,
              heroTag: fab.heroTag,
              kind: fab.kind,
              size: fab.size,
              shapeFamily: FabM3EShapeFamily.square,
              density: fab.density,
              elevation: 0,
              semanticLabel: fab.semanticLabel,
            )
          : FabM3E(
              icon: fab.icon,
              onPressed: fab.onPressed,
              tooltip: fab.tooltip,
              heroTag: fab.heroTag,
              kind: fab.kind,
              size: fab.size,
              shapeFamily: FabM3EShapeFamily.square,
              density: fab.density,
              elevation: 0,
              semanticLabel: fab.semanticLabel,
            ),
    );
  }

  Widget? _buildTrailing(BuildContext context, {required bool isExpanded}) {
    final tr = widget.trailing;
    if (tr == null) return null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, end: 16, bottom: 12),
      child: Align(
        alignment: isExpanded ? Alignment.centerLeft : Alignment.center,
        child: tr,
      ),
    );
  }

  List<Widget> _buildChildren(BuildContext context,
      {required bool isExpanded}) {
    final theme = Theme.of(context).extension<NavigationRailM3ETheme>() ??
        const NavigationRailM3ETheme();

    final children = <Widget>[];
    children.add(const SizedBox(height: 36));
    children.add(_buildMenuButton(context, isExpanded: isExpanded));
    final fabWidget = _buildFab(context, isExpanded: isExpanded);
    if (fabWidget != null) children.add(fabWidget);

    if (isExpanded) {
      for (final section in widget.sections) {
        if (section.header != null) {
          children.add(Padding(
            padding: EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
              top: theme.sectionHeaderSpacingTop,
              bottom: theme.sectionHeaderSpacingBottom,
            ),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              child: section.header!,
            ),
          ));
        }
        for (final dest in section.destinations) {
          final index = _destinationIndex(widget.sections, dest);
          children.add(Padding(
            padding: EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
              top: theme.itemVerticalGap,
              bottom: theme.itemVerticalGap,
            ),
            child: RailItem(
              destination: dest,
              selected: index == widget.selectedIndex,
              onTap: () => widget.onDestinationSelected(index),
              expanded: true,
              labelBehavior: widget.labelBehavior,
              suppressInk: _suppressInk,
            ),
          ));
        }
      }
    } else {
      final all = widget.sections.expand((s) => s.destinations).toList();
      for (int i = 0; i < all.length; i++) {
        children.add(Padding(
          padding: EdgeInsetsDirectional.only(
              start: 16.0,
              end: 16.0,
              top: theme.itemVerticalGap,
              bottom: theme.itemVerticalGap),
          child: RailItem(
            destination: all[i],
            selected: i == widget.selectedIndex,
            onTap: () => widget.onDestinationSelected(i),
            expanded: false,
            labelBehavior: widget.labelBehavior,
            suppressInk: _suppressInk,
          ),
        ));
      }
    }
    // Place trailing after sections when not bottom-pinned.
    if (widget.trailing != null && !widget.trailingAtBottom) {
      final trailingWidget = _buildTrailing(context, isExpanded: isExpanded);
      if (trailingWidget != null) children.add(trailingWidget);
    }
    return children;
  }

  // Fork patch: M3E expressive motion — the expanded-rail expansion uses the
  // default spatial spring; this cubic/duration is the documented web
  // fallback for it (m3.material.io motion physics page).
  static const Duration _expandDuration = Duration(milliseconds: 500);
  static const Cubic _expandCurve = Cubic(0.38, 1.21, 0.22, 1.00);

  /// One full layout (collapsed or expanded) — always mounted, width-pinned.
  Widget _buildLayout(BuildContext context, {required bool isExpanded}) {
    final children = _buildChildren(context, isExpanded: isExpanded);
    final bottomTrailing = (widget.trailing != null && widget.trailingAtBottom)
        ? _buildTrailing(context, isExpanded: isExpanded)
        : null;

    if (widget.scrollable) {
      if (bottomTrailing != null) {
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: children,
              ),
            ),
            bottomTrailing,
          ],
        );
      }
      return ListView(
        padding: EdgeInsets.zero,
        children: children,
      );
    } else {
      if (bottomTrailing != null) {
        return Column(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
            bottomTrailing,
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
  }

  Widget _buildRailCore(BuildContext context) {
    final tokens = NavigationRailTokensAdapter(context);
    final theme = Theme.of(context).extension<NavigationRailM3ETheme>() ??
        const NavigationRailM3ETheme();
    final double expandedTarget =
        (widget.expandedWidth ?? theme.expandedMinWidth)
            .clamp(theme.expandedMinWidth, theme.expandedMaxWidth)
            .toDouble();
    final double collapsedBase =
        widget.hideWhenCollapsed ? 0.0 : theme.collapsedWidth;
    // M3E: standard rail container is corner.none; modal expanded is
    // corner.large.
    final BorderRadius? radius = _isModal && _isExpanded
        ? const BorderRadius.all(Radius.circular(16))
        : null;
    final decoration = BoxDecoration(
      color: widget.background ?? tokens.containerColor,
      borderRadius: radius,
    );

    // Fork patch: both width-pinned layouts are ALWAYS mounted; their
    // opacities (FadeTransition — repaint only, never Opacity/saveLayer) and
    // the container width all derive from the one controller, so they run in
    // lockstep and reverse symmetrically. Content never re-lays-out against
    // intermediate widths — upstream swapped layouts unclipped and threw
    // transient RenderFlex overflows every transition.
    Widget layer({required bool isExpanded}) => IgnorePointer(
          ignoring: isExpanded != _expanded,
          child: FadeTransition(
            opacity: isExpanded ? _expandedOpacity : _collapsedOpacity,
            child: SizedBox(
              width: isExpanded ? expandedTarget : theme.collapsedWidth,
              child: _buildLayout(context, isExpanded: isExpanded),
            ),
          ),
        );

    final Widget content = ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: expandedTarget,
        maxWidth: expandedTarget,
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            layer(isExpanded: false),
            layer(isExpanded: true),
          ],
        ),
      ),
    );

    // Only the width container rebuilds per frame — the layers above are the
    // cached `child` (AnimatedBuilder child-caching best practice).
    return AnimatedBuilder(
      animation: _widthT,
      child: content,
      builder: (context, child) {
        // The spatial cubic overshoots past 1; clamp only the low end so a
        // hideWhenCollapsed base of 0 never lerps negative.
        var w = lerpDouble(collapsedBase, expandedTarget, _widthT.value)!;
        if (w < 0) w = 0;
        return Container(
          width: w,
          clipBehavior: radius == null ? Clip.none : Clip.antiAlias,
          decoration: decoration,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep overlay in sync after build completes to avoid layout side-effects.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverlay());

    final Widget child =
        _needsOverlay ? const SizedBox.shrink() : _buildRailCore(context);

    // Always provide an anchor target for positioning collapsed peek overlay.
    return CompositedTransformTarget(link: _anchor, child: child);
  }

  static int _destinationIndex(List<NavigationRailM3ESection> sections,
      NavigationRailM3EDestination dest) {
    var i = 0;
    for (final s in sections) {
      for (final d in s.destinations) {
        if (identical(d, dest)) return i;
        i++;
      }
    }
    return 0;
  }
}
