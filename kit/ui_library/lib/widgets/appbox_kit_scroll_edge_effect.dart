import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The edge of a scrollable a [AppBoxKitScrollEdgeEffect] treats.
enum AppBoxKitScrollEdge {
  /// Leading edge — content sliding under a pinned top bar.
  top,

  /// Trailing edge — content entering from under bottom chrome (a tab bar
  /// over `Scaffold(extendBody: true)`, an input bar…).
  bottom,
}

/// Style of a [AppBoxKitScrollEdgeEffect], mirroring iOS 26's
/// `UIScrollEdgeEffect.Style`.
enum AppBoxKitScrollEdgeEffectStyle {
  /// Resolves to [soft] — the system default on iOS 26.
  automatic,

  /// Progressive blur with a gentle fade: a faint remnant (alpha 0.15) of
  /// the fully covered child stays readable through the blur.
  soft,

  /// Full obscuration: double the blur strength and a fade all the way to
  /// alpha 0 at full cover (pointers ignored there). For edges where the
  /// legibility of the chrome above must be absolute.
  hard,
}

/// Progressive blur/fade applied to scrollable *content* at the edge beneath
/// pinned chrome — the iOS 26 `UIScrollEdgeEffect` semantic, in pure Flutter
/// (ADR 0010). There is no native tier — this is a content effect, not
/// chrome — so the widget is named `Kit*`, never `AppBoxKitNative*`.
///
/// **Why.** Apple's scroll edge effects treat the *content*, never the
/// chrome: where a list underlaps a bar, the content progressively blurs and
/// fades toward the edge while the bar itself stays mounted and untouched.
/// This supersedes [AppBoxKitScrollOcclusionGate] for scroll duty — chrome stops
/// hiding on scroll, and the content (the Flutter-drawn frosted tier of the
/// ADR's glass split) softens under the bar instead of vanishing.
///
/// **How.** The covered fraction of the child drives both a blur
/// (`ImageFiltered` — it blurs the child's own pixels, so the effect behaves
/// identically over any tier beneath it, unlike a `BackdropFilter`, which
/// can never sample native pixels) and an alpha fade. Geometry comes from
/// the viewport's `getOffsetToReveal`, which already folds pinned slivers'
/// `maxScrollObstructionExtent` into the reveal offset — so under a pinned
/// `AppBoxKitNativeSliverAppBar` / `SliverAppBar` the effect needs **zero
/// configuration**. Use [occlusionPadding] only for chrome overlaid from
/// *outside* the scrollable (e.g. a tab bar stacked over
/// `Scaffold(extendBody: true)` at the [AppBoxKitScrollEdge.bottom] edge).
///
/// **Cost.** A child fully clear of the edge builds its own bare subtree —
/// the blur/opacity layers exist only for the widget or two currently
/// crossing an edge. Those layers are inserted at that boundary, which
/// reparents the child: fine for Flutter-drawn content, the tier this
/// widget is designed for. Platform-view glass does not belong inside a
/// scrollable at all under the tier split — that rule, not this widget,
/// governs it.
///
/// **Usage.** Wrap a content surface that lives inside a scrollable beneath
/// pinned chrome (or use the [.scrollEdgeEffect()] sugar):
///
/// ```dart
/// AppBoxKitScrollEdgeEffect(
///   child: AppBoxKitGlassCard(...), // frosted-tier content
/// )
/// ```
///
/// Treat both ends of a scrollable by nesting one wrapper per edge:
///
/// ```dart
/// card
///     .scrollEdgeEffect() // top, zero-config under the pinned bar
///     .scrollEdgeEffect(edge: AppBoxKitScrollEdge.bottom, occlusionPadding: 56)
/// ```
class AppBoxKitScrollEdgeEffect extends StatefulWidget {
  const AppBoxKitScrollEdgeEffect({
    super.key,
    required this.child,
    this.style = AppBoxKitScrollEdgeEffectStyle.automatic,
    this.edge = AppBoxKitScrollEdge.top,
    this.occlusionPadding = 0.0,
  });

  /// The scrollable content to soften at the edge.
  final Widget child;

  /// Blur/fade strength profile. Defaults to
  /// [AppBoxKitScrollEdgeEffectStyle.automatic], which resolves to `.soft`.
  final AppBoxKitScrollEdgeEffectStyle style;

  /// Which viewport edge the coverage is measured against. Defaults to
  /// [AppBoxKitScrollEdge.top].
  final AppBoxKitScrollEdge edge;

  /// Extra covered pixels beyond what the viewport self-reports (pinned
  /// slivers are already accounted for). For chrome overlaid from *outside*
  /// the scrollable.
  final double occlusionPadding;

  @override
  State<AppBoxKitScrollEdgeEffect> createState() => _KitScrollEdgeEffectState();
}

class _KitScrollEdgeEffectState extends State<AppBoxKitScrollEdgeEffect> {
  ScrollPosition? _position;

  /// Covered fraction, quantized to 1/50 steps: 0 = fully clear of the edge,
  /// 1 = fully covered.
  double _t = 0.0;
  bool _engaged = false;

  /// Hysteresis dead band: engage only above [_enterThreshold], release only
  /// below [_exitThreshold]. A single boundary flips state on ordinary scroll
  /// jitter for rows resting near pinned chrome ("lists break all the time").
  static const double _enterThreshold = 0.04;
  static const double _exitThreshold = 0.01;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_recompute);
      _position = position?..addListener(_recompute);
    }
    // Initial geometry lands after the first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _position?.removeListener(_recompute);
    super.dispose();
  }

  void _recompute() {
    if (!mounted) return;
    final position = _position;
    final box = context.findRenderObject();
    if (position == null ||
        !position.hasPixels ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        box.size.height <= 0) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;

    // The viewport's getOffsetToReveal folds pinned slivers'
    // maxScrollObstructionExtent into the reveal offset, so pinned chrome is
    // detected automatically. Top: pixels scrolled past the leading reveal =
    // covered. Bottom is symmetric: pixels short of the trailing reveal =
    // covered (the child still pokes out under the trailing fold).
    final reveal = viewport
        .getOffsetToReveal(box, widget.edge == AppBoxKitScrollEdge.top ? 0.0 : 1.0)
        .offset;
    final covered = widget.edge == AppBoxKitScrollEdge.top
        ? position.pixels - reveal + widget.occlusionPadding
        : reveal - position.pixels + widget.occlusionPadding;

    final raw = (covered / box.size.height).clamp(0.0, 1.0);
    if (_engaged) {
      if (raw <= _exitThreshold) _engaged = false;
    } else if (raw >= _enterThreshold) {
      _engaged = true;
    }
    // Quantize to limit rebuild churn; snap the endpoints so t == 0 is
    // *exactly* 0 (identity wrappers, no filter layer) and t == 1 is full.
    final t = !_engaged
        ? 0.0
        : raw >= 0.98
            ? 1.0
            : (raw * 50).roundToDouble() / 50;
    if (t == _t) return;
    setState(() => _t = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final hard = widget.style == AppBoxKitScrollEdgeEffectStyle.hard;
    final sigma = (hard ? 16.0 : 8.0) * t;
    final alpha = hard ? 1.0 - t : 1.0 - 0.85 * t;

    // The wrapper chain is ALWAYS mounted — constant tree shape. Returning
    // widget.child raw at t == 0 changes the tree depth, so the child's
    // Element (and any platform view inside it) is unmounted and re-created
    // at every threshold crossing; the remount is the visible artifact. At
    // rest every wrapper is driven to identity instead: ignoring false,
    // opacity 1.0 (RenderOpacity pushes no layer at 1.0), Clip.none, and
    // sigma 0 — _EdgeEffectBlur paints its child directly at sigma 0, so no
    // ImageFilterLayer/saveLayer is created either.
    //
    // Blur the child's own pixels, never the backdrop — the effect must
    // behave identically over any tier beneath it. ClipRect keeps the blur
    // bleed inside the child's slot; at rest there is nothing to bleed, so
    // clipping is disabled rather than unmounted.
    return IgnorePointer(
      ignoring: alpha == 0.0,
      child: Opacity(
        opacity: alpha,
        child: ClipRect(
          clipBehavior: sigma == 0.0 ? Clip.none : Clip.hardEdge,
          child: _EdgeEffectBlur(
            sigma: sigma,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// [ImageFiltered] look-alike that stays mounted at rest without paying for
/// the filter: at `sigma == 0` the render object paints its child directly —
/// no [ImageFilterLayer], no saveLayer — while the widget (and therefore the
/// child's Element) never leaves the tree.
class _EdgeEffectBlur extends SingleChildRenderObjectWidget {
  const _EdgeEffectBlur({required this.sigma, super.child});

  final double sigma;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEdgeEffectBlur(sigma: sigma);

  @override
  void updateRenderObject(
      BuildContext context, _RenderEdgeEffectBlur renderObject) {
    renderObject.sigma = sigma;
  }
}

class _RenderEdgeEffectBlur extends RenderProxyBox {
  _RenderEdgeEffectBlur({required double sigma}) : _sigma = sigma;

  double _sigma;
  double get sigma => _sigma;
  set sigma(double value) {
    if (value == _sigma) return;
    final wasIdentity = _sigma == 0.0;
    _sigma = value;
    if (wasIdentity != (value == 0.0)) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _sigma > 0.0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_sigma == 0.0) {
      layer = null; // identity — child paints in place, no saveLayer
      super.paint(context, offset);
      return;
    }
    final imageFilterLayer = (layer as ImageFilterLayer?) ?? ImageFilterLayer();
    imageFilterLayer.imageFilter =
        ui.ImageFilter.blur(sigmaX: _sigma, sigmaY: _sigma);
    context.pushLayer(imageFilterLayer, super.paint, offset);
    layer = imageFilterLayer;
  }
}

/// Call-site sugar matching the kit's `.scrollOcclusion()` house style.
///
/// ```dart
/// AppBoxKitGlassCard(...).scrollEdgeEffect()
/// ```
///
/// Apply to the whole softening unit (a card *plus* any overlays stacked on
/// it) so everything blurs in lockstep. Do **not** apply it to widgets
/// riding the pinned chrome itself (`leading:`/`actions:` of the sliver
/// bar): chrome is never edge-effected — those share the scrollable's
/// `ScrollPosition`, so the effect would count them as covered the moment
/// the bar collapses.
extension AppBoxKitScrollEdgeEffectX on Widget {
  Widget scrollEdgeEffect({
    Key? key,
    AppBoxKitScrollEdgeEffectStyle style = AppBoxKitScrollEdgeEffectStyle.automatic,
    AppBoxKitScrollEdge edge = AppBoxKitScrollEdge.top,
    double occlusionPadding = 0.0,
  }) =>
      AppBoxKitScrollEdgeEffect(
        key: key,
        style: style,
        edge: edge,
        occlusionPadding: occlusionPadding,
        child: this,
      );
}
