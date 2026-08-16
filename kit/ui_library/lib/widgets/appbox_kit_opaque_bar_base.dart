import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNGlassEffect, LiquidGlassConfig, LiquidGlassContainer;
import 'package:flutter/material.dart';

import 'appbox_kit_frosted_surface.dart';

/// The opaque pinned-strip base — the flat, fully opaque panel every docked
/// chrome strip paints under itself so scrolled content NEVER shows through
/// the gap between the strip and its neighbors. Extracted from
/// [AppBoxKitNativeInputBar] (its `opaqueGlass` backing) so strips docked
/// AROUND pinned chrome — a composer's pending-attachment row, accessory
/// bars — compose the exact same base instead of leaving a transparent seam.
///
/// Two layers, both load-bearing:
///
/// 1. [AppBoxKitFrostedSurface] with `platformViewSafe: true` and the tint
///    token at **alpha 1.0** — opaque by definition, and a plain fill
///    rather than a BackdropFilter because a saveLayer cannot span the
///    frame slices UiKitViews create (flutter#175048; the strip may host CN
///    platform-view buttons).
/// 2. A `LiquidGlassContainer` with the **plain** effect — a native anchor,
///    not a visual: over a platform-view-bearing scrollable the engine's
///    view slicer keeps Flutter ops above the platform views only while they
///    intersect a platform-view rect, so without a stationary platform view
///    under it the opaque base drops to the difference-clipped background
///    canvas and reads translucent. `plain` renders nothing (clear fill,
///    Glass.identity) so no glass-on-glass stacking can occur; on tiers
///    without native glass the vendor container degrades to its bare child.
///
/// transition-exempt: the anchor mounts a platform view that renders
/// nothing, so riding a route slide shows nothing and there is nothing to
/// chrome-gate (same exemption the input bar's base carries).
///
/// Public surface is the child alone — the tint/anchor are the contract,
/// not knobs.
class AppBoxKitOpaqueBarBase extends StatelessWidget {
  const AppBoxKitOpaqueBarBase({super.key, required this.child});

  /// The strip's content. Padding, SafeArea, and spacing belong to the
  /// caller (the base is a full-bleed paint, not a layout).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LiquidGlassContainer(
      config: const LiquidGlassConfig(effect: CNGlassEffect.plain),
      child: AppBoxKitFrostedSurface(
        borderRadius: 0,
        platformViewSafe: true,
        tint: scheme.surfaceContainerLowest.withValues(alpha: 1.0),
        child: child,
      ),
    );
  }
}