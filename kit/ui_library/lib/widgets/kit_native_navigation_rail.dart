import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart'
    show
        NavigationRailM3E,
        NavigationRailM3EDestination,
        NavigationRailM3ESection,
        NavigationRailM3EType;

import 'package:appbox_kit_core/common/kit_glyphs.dart';
import 'package:appbox_kit_core/platform/kit_platform.dart';

/// One rail stop. [icon] drives the M3E tier and the Flutter fallback;
/// [sfSymbol] is reserved for a future iOS Liquid Glass rail tier (mirrors
/// [KitTab]'s shape).
///
/// Prefer [glyph] (a paired icon + SF Symbol from [KitGlyphs]) over the raw
/// [icon] / [sfSymbol] escape hatches — one token, both tiers, no drift.
class KitRailDestination {
  const KitRailDestination({
    this.glyph,
    IconData? icon,
    required this.label,
    String? sfSymbol,
  })  : assert(glyph != null || icon != null,
            'KitRailDestination needs a glyph or an icon'),
        _icon = icon,
        _sfSymbol = sfSymbol;

  /// Paired Material icon + SF Symbol (see [KitGlyphs]).
  final KitGlyph? glyph;

  final IconData? _icon;
  final String? _sfSymbol;

  /// Material glyph — raw `icon` override first, then [glyph].
  IconData get icon => (_icon ?? glyph?.icon)!;

  /// SF Symbol name — raw `sfSymbol` override first, then [glyph].
  String? get sfSymbol => _sfSymbol ?? glyph?.sfSymbol;

  final String label;
}

/// Adaptive navigation rail — three-tier structural gate (mirrors [KitNativeTabBar]):
/// - **Android M3 Expressive** — [NavigationRailM3E]. The kit's flat
///   [KitRailDestination] list is wrapped in a single
///   [NavigationRailM3ESection] (the M3E rail groups destinations by section;
///   the kit exposes a flat list to keep the API primitive).
/// - **iOS/macOS** — a kit-owned Cupertino-styled rail (pill highlight +
///   caption labels, theme-tinted). Material's [NavigationRail] reads as
///   Android chrome on Apple, and it demands more bounded height than its
///   content (it clips inside short showcase boxes); the Cupertino tier
///   shrink-wraps its column instead.
/// - **Fallback** (desktop/web) — Material [NavigationRail].
///
/// The public surface is **primitives only** so hosts never import
/// `m3e_collection`. [extended] maps to the M3E tier's `type`
/// (`expanded` / `collapsed`) and to [NavigationRail.extended] on fallback.
///
/// Like the M3E tier, the Cupertino tier carries its own menu toggle button —
/// [extended] seeds the initial state and host changes to it still win, but
/// the user can expand/collapse the rail in place on every platform.
class KitNativeNavigationRail extends StatelessWidget {
  const KitNativeNavigationRail({
    super.key,
    required this.selectedIndex,
    this.onDestinationSelected,
    required this.destinations,
    this.wantNative = true,
    this.extended = false,
  });

  /// Currently selected destination index. Host-owned (the rail is a
  /// projection, never a second source of truth — same contract as
  /// [KitNativeTabBar.currentIndex]).
  final int selectedIndex;

  /// Notified on destination tap.
  final ValueChanged<int>? onDestinationSelected;

  /// Flat list of rail stops. Mapped into the M3E tier's sectioned model.
  final List<KitRailDestination> destinations;

  /// Host opt-out of native chrome.
  final bool wantNative;

  /// Expanded (label-visible) rail vs collapsed (icon-only). Maps to the M3E
  /// tier's `type` and seeds the Cupertino tier's internal toggle.
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final want = wantNative && KitPlatform.supportsComposeM3E;
    if (want) return _m3e(context);
    // Apple: Material's NavigationRail is Android chrome — render the
    // Cupertino-styled tier instead (also immune to the M3E/Material rails'
    // bounded-height clipping: the column shrink-wraps).
    if (KitPlatform.isIOS) {
      return _CupertinoRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
        extended: extended,
      );
    }
    return _material(context);
  }

  // Kit rails float inside cards, not edge-attached — clip the spec-square
  // (corner.none) container to M3E corner.large so it reads as an expressive
  // floating surface. Kit-side clip rather than a fork param so appbox_kit
  // keeps compiling against the unpatched pub navigation_rail_m3e.
  Widget _m3e(BuildContext context) => ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: NavigationRailM3E(
          key: key,
          type: extended
              ? NavigationRailM3EType.expanded
              : NavigationRailM3EType.collapsed,
          // The kit exposes a flat destination list; the M3E rail sections them.
          // Wrap in a single section so the host's ordering is preserved 1:1.
          sections: [
            NavigationRailM3ESection(
              destinations: [
                for (final d in destinations)
                  NavigationRailM3EDestination(
                    icon: Icon(d.icon),
                    label: d.label,
                  ),
              ],
            ),
          ],
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected ?? (_) {},
        ),
      );

  Widget _material(BuildContext context) => NavigationRail(
        key: key,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        extended: extended,
        destinations: [
          for (final d in destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
        ],
      );
}

/// Kit-owned Cupertino-styled rail: selected icon in a theme-primary pill,
/// caption label below — iOS sidebar vocabulary, driven by the active
/// [ColorScheme] so light/dark + brand colors flow through. Extended mode is
/// sidebar rows (icon + inline label, primary-pill selection), toggled by the
/// rail's own menu button (parity with the M3E tier's built-in toggle).
/// Content is laid out at the target width behind a ClipRect+OverflowBox so
/// the width animation reveals it instead of re-flowing it (same pattern as
/// the vendored navigation_rail_m3e fork).
// ponytail: pure Flutter — cupertino_native_better has no rail component
// yet; swap this tier for the native one when it lands ([KitRailDestination.
// sfSymbol] is already reserved for it).
class _CupertinoRail extends StatefulWidget {
  const _CupertinoRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.extended,
  });

  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final List<KitRailDestination> destinations;
  final bool extended;

  @override
  State<_CupertinoRail> createState() => _CupertinoRailState();
}

class _CupertinoRailState extends State<_CupertinoRail>
    with SingleTickerProviderStateMixin {
  static const double _collapsedWidth = 84;
  static const double _extendedWidth = 220;

  /// Seeded from the host's `extended`, then driven by the rail's own menu
  /// button. A host-driven `extended` change still wins (same contract as the
  /// forked M3E rail's type sync).
  late bool _expanded = widget.extended;

  /// ONE controller drives the width and both layer opacities in lockstep —
  /// collapse is the exact time-reverse of expand (controller.reverse()).
  /// Same architecture as the vendored navigation_rail_m3e fork.
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: _expanded ? 1.0 : 0.0,
  );
  late final Animation<double> _widthT =
      CurvedAnimation(parent: _transition, curve: Curves.easeInOutCubic);
  late final Animation<double> _stackOpacity =
      Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
    parent: _transition,
    curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
  ));
  late final Animation<double> _rowOpacity = CurvedAnimation(
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

  @override
  void didUpdateWidget(covariant _CupertinoRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extended != widget.extended) {
      setState(() => _applyExpanded(widget.extended));
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  Widget _column(ColorScheme scheme, {required bool extended}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _menuButton(scheme, extended: extended),
          for (var i = 0; i < widget.destinations.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDestinationSelected == null
                  ? null
                  : () => widget.onDestinationSelected!(i),
              child: extended ? _row(scheme, i) : _stack(scheme, i),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Both width-pinned layouts always mounted; opacities via FadeTransition
    // (repaint-only) on sub-intervals of the one controller (fade-through).
    Widget layer({required bool extended}) => IgnorePointer(
          ignoring: extended != _expanded,
          child: FadeTransition(
            opacity: extended ? _rowOpacity : _stackOpacity,
            child: SizedBox(
              width: extended ? _extendedWidth : _collapsedWidth,
              child: _column(scheme, extended: extended),
            ),
          ),
        );

    final content = ClipRect(
      child: OverflowBox(
        alignment: AlignmentDirectional.centerStart,
        minWidth: _extendedWidth,
        maxWidth: _extendedWidth,
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            layer(extended: false),
            layer(extended: true),
          ],
        ),
      ),
    );

    // Only the width box rebuilds per frame; the layers are the cached child.
    return AnimatedBuilder(
      animation: _widthT,
      child: content,
      builder: (context, child) => SizedBox(
        width: lerpDouble(_collapsedWidth, _extendedWidth, _widthT.value),
        child: child,
      ),
    );
  }

  /// Built-in expand/collapse toggle — the iOS counterpart of the M3E rail's
  /// menu button. Rendered once per layer, so the icon crossfades with it.
  Widget _menuButton(ColorScheme scheme, {required bool extended}) {
    return Align(
      alignment: extended ? AlignmentDirectional.centerStart : Alignment.center,
      child: Padding(
        padding: extended
            ? const EdgeInsetsDirectional.only(start: 14, bottom: 4)
            : const EdgeInsets.only(bottom: 4),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _applyExpanded(!_expanded)),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              extended ? Icons.menu_open : Icons.menu,
              size: 22,
              color: scheme.onSurfaceVariant,
              semanticLabel: extended ? 'Collapse rail' : 'Expand rail',
            ),
          ),
        ),
      ),
    );
  }

  /// Extended item: sidebar row — icon + inline label in a full-width pill.
  Widget _row(ColorScheme scheme, int i) {
    final selected = i == widget.selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              widget.destinations[i].icon,
              size: 22,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.destinations[i].label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Collapsed item: icon pill with a caption label below.
  Widget _stack(ColorScheme scheme, int i) {
    final selected = i == widget.selectedIndex;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? scheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              widget.destinations[i].icon,
              size: 22,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.destinations[i].label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
