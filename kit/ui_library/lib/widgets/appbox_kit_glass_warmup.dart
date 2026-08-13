import 'package:cupertino_native_better/cupertino_native_better.dart'
    show
        CNGlassEffect,
        CNGlassEffectShape,
        LiquidGlassConfig,
        LiquidGlassContainer;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

/// Warms the iOS 26 Liquid Glass **surface** pipeline at boot so the first
/// route pushed with glass cards doesn't pay materialization on-screen.
///
/// Measured (device, profile mode, 2026-08-14 — `docs/plans/
/// glass-push-hotspot-fix.md`): the glass route-push jank is
/// **first-push-only** — push 1 of a glass-card route hit a 39.6ms raster
/// frame (4.8% of frames over the 60Hz budget) while pushes 2 and 3 of the
/// SAME route peaked at 10–12ms with **zero** frames over budget. Glass
/// *controls* (buttons, segmented) were already on screen when push 1
/// janked, so the warm-up is per glass **kind**, once per process — the
/// expensive kind is the surface container ([LiquidGlassContainer], what
/// [AppBoxKitGlassCard]'s native tier mounts).
///
/// Wrap the app's shell root ONCE:
///
/// ```dart
/// AppBoxKitGlassWarmup(child: shellScaffold)
/// ```
///
/// Mechanics:
/// - Mounts one 44×44 [LiquidGlassContainer] with the exact card-tier config
///   (rect / radius 16 / [CNGlassEffect.regular]), so the warmed pipeline is
///   the one real cards hit. The cost lands during launch settle, off-screen.
/// - `Transform.translate(100000, 0)` — law rule 8
///   (`docs/liquid-glass-allowlist.md`): a hidden platform view feeds its
///   UNCLIPPED rect to the engine's view slicer, so off-screen translation
///   is the ONLY hide that cannot slice on-screen content. Alpha or clip
///   tricks here would reintroduce the ghost-geometry class this repo
///   already eradicated.
/// - Stays mounted (no self-removal timer): removing it would change the
///   platform-view set for zero benefit, and a translated view can never
///   intersect anything. NOT `chromeGated()` on purpose — the gate would
///   unmount it during every route transition and replay the materialization
///   churn this widget exists to prefetch.
/// - No-op (returns [child] bare) on every tier without Liquid Glass.
class AppBoxKitGlassWarmup extends StatelessWidget {
  const AppBoxKitGlassWarmup({
    super.key,
    required this.child,
    this.alsoWarm = const <Widget>[],
  });

  /// The subtree to wrap — typically the app shell root.
  final Widget child;

  /// Extra native kinds to warm alongside the surface container — one
  /// instance each, mounted in the same rule-8 off-screen band. Warm-up is
  /// per glass KIND, once per process: pass a kind here when a pushed route
  /// mounts it but no boot-visible screen does (measured: Motion's switch
  /// cost a first-push 23.8ms raster spike until warmed; kinds already on a
  /// boot screen warm themselves and don't belong in this list).
  final List<Widget> alsoWarm;

  // transition-exempt: the warm view is translated 100000px off-screen and
  // never enters a frame the user sees, so it has no slide to leak over —
  // the one thing the gate exists to prevent. Gating it would be actively
  // harmful: the gate unmounts on every route transition, and each re-mount
  // replays the glass materialization this widget exists to pay ONCE at boot
  // (law rule 9, docs/research/perf-measurement-native-coexistence.md).
  @override
  Widget build(BuildContext context) {
    if (!AppBoxKitPlatform.supportsLiquidGlass) return child;
    return Stack(
      // Non-directional so the wrap imposes no Directionality requirement.
      alignment: Alignment.topLeft,
      children: [
        child,
        Positioned(
          // No width/height: the warm views size themselves, so extra
          // `alsoWarm` kinds can never overflow a fixed band.
          left: 0,
          top: 0,
          child: Transform.translate(
            offset: const Offset(100000, 0),
            child: IgnorePointer(
              child: ExcludeSemantics(
                // The warm views are SIBLINGS of the host's Scaffold, so they
                // sit outside its Material. Any warm kind that falls back to a
                // Flutter tier (headless tests, or a device path where the
                // platform view can't build) then asserts "No Material widget
                // found" and takes the whole app down — measured: the warm
                // switch broke three showcase chrome tests. Transparency type
                // paints nothing.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LiquidGlassContainer(
                        config: LiquidGlassConfig(
                          shape: CNGlassEffectShape.rect,
                          cornerRadius: 16,
                          effect: CNGlassEffect.regular,
                        ),
                        child: SizedBox(width: 44, height: 44),
                      ),
                      ...alsoWarm,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
