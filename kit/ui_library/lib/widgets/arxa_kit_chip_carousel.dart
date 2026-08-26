import 'package:flutter/material.dart';

import 'package:arxa_kit_core/common/arxa_kit_app_constants.dart';

/// A horizontal rail of chips (usually `ArxaKitChip`s) — edge-faded when the
/// content overflows, with optional snap-to-chip settling. Pure-Flutter on
/// every tier — there is **no** native (Liquid-Glass / M3-Expressive)
/// chip-rail surface to wrap, so this widget is named `ArxaKitChipCarousel` (a
/// content widget), **not** `ArxaKitNativeChipCarousel`. See
/// `core/NATIVE_COMPONENTS.md` ("Content widgets"). This is the capability-
/// chip rail idiom; it is **not** the M3-Expressive browsing `Carousel`
/// (that matrix row stays deferred — different component).
///
/// Behaviours worth naming:
/// - **Intrinsic height** — the rail is a horizontal
///   [SingleChildScrollView] + [Row], so it sizes itself to its tallest
///   child and never needs a host-supplied height. Rails are small
///   (capability chips), so lazy building buys nothing here.
/// - **Edge fades** — when the content overflows, the leading/trailing edges
///   fade out over [fadeExtent] through a [ShaderMask], but only on the side
///   that has more content (at rest at the start, only the trailing edge
///   fades). No fade is drawn when everything fits.
/// - **Snapping** — with [snap] on, scroll settling springs to the nearest
///   chip start instead of parking mid-chip. Chip widths are measured after
///   layout (labels vary), so no fixed item extent is imposed; off by
///   default.
class ArxaKitChipCarousel extends StatefulWidget {
  const ArxaKitChipCarousel({
    super.key,
    required this.children,
    this.spacing = abxPad8,
    this.padding = const EdgeInsets.symmetric(horizontal: abxPad16),
    this.snap = false,
    this.fadeExtent = abxSize24,
  });

  /// The chips. Wrapped internally for width measurement — keys on the
  /// children themselves are not preserved.
  final List<Widget> children;

  /// Gap between chips. Defaults to [abxPad8].
  final double spacing;

  /// Content inset inside the scroll view (scrolls with the chips), so the
  /// first/last chip never sits flush against the viewport edge. Defaults to
  /// 16dp horizontal; pass [EdgeInsets.zero] for a flush rail.
  final EdgeInsetsGeometry? padding;

  /// Whether scroll settling snaps to the nearest chip start. Off by
  /// default.
  final bool snap;

  /// Width of the edge fade in logical px. `0` disables fades.
  final double fadeExtent;

  @override
  State<ArxaKitChipCarousel> createState() => _KitChipCarouselState();
}

class _KitChipCarouselState extends State<ArxaKitChipCarousel> {
  final _controller = ScrollController();
  var _keys = <GlobalKey>[];
  var _snapOffsets = const <double>[];
  var _hasOverflow = false;
  var _canScrollBack = false;
  var _canScrollForward = false;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.children.length, (_) => GlobalKey());
    _controller.addListener(_updateFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  @override
  void didUpdateWidget(ArxaKitChipCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      _keys = List.generate(widget.children.length, (_) => GlobalKey());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _remeasure());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Measures chip widths after layout and derives the snap offsets (the
  /// scroll offset at which each chip's leading edge hits the viewport
  /// start, including the leading content padding).
  void _remeasure() {
    if (!mounted) return;
    final padLeft =
        (widget.padding?.resolve(Directionality.of(context)) ?? EdgeInsets.zero)
            .left;
    final offsets = <double>[];
    var cum = padLeft;
    for (final key in _keys) {
      final width = key.currentContext?.size?.width;
      if (width == null) return; // not laid out yet — keep previous offsets
      offsets.add(cum);
      cum += width + widget.spacing;
    }
    _snapOffsets = offsets;
    _updateFades();
  }

  void _updateFades() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final hasOverflow = pos.maxScrollExtent > 0.5;
    final canBack = pos.pixels > pos.minScrollExtent + 0.5;
    final canForward = pos.pixels < pos.maxScrollExtent - 0.5;
    if (hasOverflow != _hasOverflow ||
        canBack != _canScrollBack ||
        canForward != _canScrollForward) {
      setState(() {
        _hasOverflow = hasOverflow;
        _canScrollBack = canBack;
        _canScrollForward = canForward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = ScrollConfiguration.of(context).getScrollPhysics(context);
    final rail = SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: widget.snap
          ? _ChipSnapPhysics(
              snapOffsets: () => _snapOffsets,
              parent: base.applyTo(const AlwaysScrollableScrollPhysics()),
            )
          : null,
      padding: widget.padding,
      child: Row(
        children: [
          for (var i = 0; i < widget.children.length; i++) ...[
            KeyedSubtree(key: _keys[i], child: widget.children[i]),
            if (i < widget.children.length - 1) SizedBox(width: widget.spacing),
          ],
        ],
      ),
    );

    if (!_hasOverflow || widget.fadeExtent <= 0) return rail;

    // Fade only the side(s) with hidden content. dstIn keeps the rail's own
    // painting untouched where the gradient is opaque.
    // glass-law-exempt: chips are Flutter-only by the ratified chip contract
    // (D2 chip singularity ruling) — no platform view can enter this rail, so
    // the saveLayer never spans one. If a native chip is ever ratified, this
    // fade must move to plain viewport clipping first.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final f = (widget.fadeExtent / rect.width).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _canScrollBack ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            _canScrollForward ? Colors.transparent : Colors.black,
          ],
          stops: [0.0, f, 1 - f, 1.0],
        ).createShader(rect);
      },
      child: rail,
    );
  }
}

/// Scroll physics that settles on the nearest chip start. The natural
/// settle point of the gesture is estimated with a clamping simulation,
/// then replaced by a spring to the nearest measured snap offset.
class _ChipSnapPhysics extends ScrollPhysics {
  const _ChipSnapPhysics({required this.snapOffsets, super.parent});

  /// Measured chip-start offsets; may be empty before first layout.
  final List<double> Function() snapOffsets;

  @override
  _ChipSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChipSnapPhysics(snapOffsets: snapOffsets, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out-of-range (overscroll) stays platform-owned.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final offsets = snapOffsets();
    if (offsets.isEmpty) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final settle = ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      tolerance: tolerance,
    ).x(double.infinity);
    final target = _nearest(offsets, settle)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() <= tolerance.distance &&
        velocity.abs() <= tolerance.velocity) {
      return null; // already parked on a chip
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  double _nearest(List<double> offsets, double target) {
    var best = offsets.first;
    for (final o in offsets) {
      if ((o - target).abs() < (best - target).abs()) best = o;
    }
    return best;
  }
}
