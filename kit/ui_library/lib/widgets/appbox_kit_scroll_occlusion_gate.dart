import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTabBarRouteObserver;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'appbox_kit_native_chrome_gate.dart' show AppBoxKitChromeHideMode;

/// Scroll-driven occlusion guard for "liquid glass" surfaces — **retired
/// from scroll duty by ADR 0010**; kept only for the residual case where
/// Flutter must paint over a platform view.
///
/// **Superseded for scroll.** Apple's iOS 26 semantics never hide chrome:
/// scrolled content under pinned bars is treated with a progressive
/// blur/fade of the *content* — [AppBoxKitScrollEdgeEffect] — not an alpha-hide of
/// the surface. New scroll-under-pinned-chrome work must use
/// [AppBoxKitScrollEdgeEffect]; the reviewer's objective gate
/// (`review_checklist.sh` check 1i) now requires it. The scroll-triggered
/// hide below remains only for surfaces not yet migrated.
///
/// **Residual duty (ADR 0010 part 3).** A content-layer *platform view*
/// sitting where Flutter must paint over chrome still composites above
/// Flutter's scene and must be driven to alpha 0 — the blur-over-glass
/// cases, e.g. a native glass surface under a kit modal blur. The
/// modal-depth path ([CNTabBarRouteObserver.anyModalDepth]) covers exactly
/// that and is unaffected by the ADR.
///
/// **Why.** On iOS, `UiKitView`s (every `CN*` glass widget) composite in a
/// native layer *above* the Flutter scene. When one scrolls under pinned
/// chrome (a collapsed `SliverAppBar`), the compositor's native clip chain is
/// the only thing occluding it — and that chain is historically unreliable
/// during scroll (flutter/flutter #25965, #76097, #154664), leaving a sharp
/// ghost of the view floating over the bar. Pure-Flutter glass
/// (`AppBoxKitGlassCard`'s `BackdropFilter`) hits the same class of artifact while
/// any platform view exists in the tree (flutter/flutter #175048, open).
///
/// **Fix pattern** (same machinery as [AppBoxKitNativeChromeGate]): drive the child
/// to alpha 0 by the time its slot is fully covered. `RenderOpacity` skips
/// painting entirely at alpha 0, and a platform view absent from the frame's
/// layer tree is removed from the native view hierarchy — nothing left to
/// ghost. Alpha is proportional to the covered fraction on the way there, so
/// the surface reads as sliding behind the bar rather than popping out.
/// Opacity is the one mutator iOS hybrid composition applies to platform
/// views reliably (no transforms, no clips).
///
/// **Usage (residual case only — scroll duty moved to
/// [AppBoxKitScrollEdgeEffect]).** Wrap a glass surface that lives inside a
/// scrollable where Flutter must paint over chrome:
///
/// ```dart
/// AppBoxKitScrollOcclusionGate(
///   child: AppBoxKitNativeIconButton(...), // or AppBoxKitGlassCard, CNButton, maps…
/// )
/// ```
///
/// Pinned chrome is detected automatically: the viewport's
/// `getOffsetToReveal` already folds pinned slivers'
/// `maxScrollObstructionExtent` into the reveal offset, so anything a pinned
/// `SliverAppBar` covers counts as occluded with no configuration. Use
/// [occlusionPadding] only for overlap the viewport can't know about
/// (overlay chrome stacked outside the scrollable).
///
/// Also hides the child once it scrolls fully past the viewport's leading
/// edge even with no pinned chrome at all, which covers the "stale layer
/// parked at its last on-screen position" failure.
///
/// Pair with [AppBoxKitNativeChromeGate] (compose both) when the same surface must
/// also vanish under modal blurs.
class AppBoxKitScrollOcclusionGate extends StatefulWidget {
  const AppBoxKitScrollOcclusionGate({
    super.key,
    required this.child,
    this.occlusionPadding = 0.0,
    this.hideMode = AppBoxKitChromeHideMode.keepAlive,
  });

  final Widget child;

  /// Extra occluded pixels beyond what the viewport self-reports (pinned
  /// slivers are already accounted for). For chrome overlaid from *outside*
  /// the scrollable.
  final double occlusionPadding;

  /// How pixels come off screen once fully covered. [AppBoxKitChromeHideMode
  /// .keepAlive] (default) keeps the native view instance alive — restore is
  /// jank-free. [AppBoxKitChromeHideMode.unmount] destroys it and holds layout with
  /// a same-size placeholder (escape hatch if a specific native view
  /// misbehaves at alpha 0).
  final AppBoxKitChromeHideMode hideMode;

  @override
  State<AppBoxKitScrollOcclusionGate> createState() => _KitScrollOcclusionGateState();
}

class _KitScrollOcclusionGateState extends State<AppBoxKitScrollOcclusionGate> {
  ScrollPosition? _position;

  /// 1.0 = fully shown, 0.0 = fully covered (paint skipped, native detached).
  double _alpha = 1.0;

  /// Depth at mount — the baseline (mirrors [AppBoxKitNativeChromeGate]). A gate
  /// mounted inside an already-open modal stays visible; anything opened
  /// *after* us (kit sheets bump the depth via `appBoxKitShowNativeSheet`) counts
  /// as covering us.
  late final int _mountDepth;

  /// A modal (kit sheet / popup / overlay) is above → treat as fully
  /// covered regardless of scroll position. Platform views composite over
  /// *native sheet chrome* too, so scroll coverage alone is not enough.
  bool _modalHidden = false;

  /// Child's last laid-out size — unmount-mode placeholder footprint.
  Size? _lastSize;

  @override
  void initState() {
    super.initState();
    _mountDepth = CNTabBarRouteObserver.anyModalDepth.value;
    CNTabBarRouteObserver.anyModalDepth.addListener(_onModalDepthChanged);
  }

  void _onModalDepthChanged() {
    final hidden = CNTabBarRouteObserver.anyModalDepth.value > _mountDepth;
    if (hidden == _modalHidden) return;
    // Instant, no fade: fading = bleeding through the sheet/blur.
    setState(() => _modalHidden = hidden);
  }

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
    CNTabBarRouteObserver.anyModalDepth.removeListener(_onModalDepthChanged);
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

    // Scroll offset that would place our top exactly at the unobstructed
    // leading edge — pinned slivers' maxScrollObstructionExtent is already
    // folded in, so scrolling past it means we're sliding under pinned
    // chrome. pixels - reveal = covered pixels.
    final reveal = viewport.getOffsetToReveal(box, 0.0).offset;
    final covered = position.pixels - reveal + widget.occlusionPadding;

    final coveredFraction = (covered / box.size.height).clamp(0.0, 1.0);

    // Quantize to limit rebuild churn; snap the endpoints so alpha 0 is
    // *exactly* 0 (paint skip → native detach) slightly before full cover.
    var alpha = 1.0 - coveredFraction;
    alpha = alpha >= 0.98
        ? 1.0
        : (alpha <= 0.02 ? 0.0 : (alpha * 50).roundToDouble() / 50);
    if (alpha == _alpha) return;
    setState(() => _alpha = alpha);
  }

  @override
  Widget build(BuildContext context) {
    final unmounting = widget.hideMode == AppBoxKitChromeHideMode.unmount;
    final alpha = _modalHidden ? 0.0 : _alpha;

    if (unmounting && alpha == 0.0) {
      // Same-size stand-in: the no-layout-shift guarantee for this mode.
      final s = _lastSize;
      return s == null
          ? const SizedBox.shrink()
          : SizedBox(width: s.width, height: s.height);
    }

    Widget child = widget.child;
    if (unmounting) {
      child = _MeasureSize(onSize: (size) => _lastSize = size, child: child);
    }

    // Constant tree shape in keepAlive mode — the child must never be
    // reparented, or the platform view re-inits anyway.
    return IgnorePointer(
      ignoring: alpha == 0.0,
      child: Opacity(opacity: alpha, child: child),
    );
  }
}

/// Records the child's size after every layout (unmount mode only).
/// Callback writes a field — never setState — so mid-layout calls are safe.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onSize);

  @override
  void updateRenderObject(
          BuildContext context, _RenderMeasureSize renderObject) =>
      renderObject.onSize = onSize;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onSize);

  ValueChanged<Size> onSize;

  @override
  void performLayout() {
    super.performLayout();
    onSize(size);
  }
}

/// Call-site sugar matching kit_motion's `.wake(order: n)` house style.
///
/// ```dart
/// AppBoxKitNativeSearchBar(...).scrollOcclusion().wake(order: 1)
/// ```
///
/// Retired from scroll duty by ADR 0010 together with
/// [AppBoxKitScrollOcclusionGate] — scrolled content under pinned chrome uses
/// `.scrollEdgeEffect()` ([AppBoxKitScrollEdgeEffect]) instead; this remains only
/// for the blur-over-glass residual.
///
/// Apply to the whole fade unit (native leaf *plus* its Flutter siblings —
/// e.g. a button + badge `Stack`) so everything dims in lockstep. Do **not**
/// apply to widgets riding the pinned chrome itself (`leading:`/`actions:`
/// of the sliver bar): those share the scrollable's `ScrollPosition`, so the
/// gate would count them as covered the moment the bar collapses.
extension AppBoxKitScrollOcclusionX on Widget {
  Widget scrollOcclusion({
    Key? key,
    double occlusionPadding = 0.0,
    AppBoxKitChromeHideMode hideMode = AppBoxKitChromeHideMode.keepAlive,
  }) =>
      AppBoxKitScrollOcclusionGate(
        key: key,
        occlusionPadding: occlusionPadding,
        hideMode: hideMode,
        child: this,
      );
}
