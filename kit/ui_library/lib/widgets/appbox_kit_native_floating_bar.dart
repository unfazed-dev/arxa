import 'package:cupertino_native_better/cupertino_native_better.dart'
    show LiquidGlassContainer, LiquidGlassConfig;
import 'package:flutter/material.dart';
import 'package:appbox_kit_core/common/appbox_kit_app_constants.dart';

import 'appbox_kit_native_chrome_gate.dart';

/// Height of the floating bar's control block, below the status bar: the
/// 44pt control row plus the same breathing gap the boxed app bar reserves.
/// Hosts that lay content full-bleed behind the bar add this (plus the
/// status-bar inset) to their content's top padding.
const double kAppBoxKitFloatingBarBlockHeight = 44 + abxGap8;

/// Floating top chrome for the Liquid Glass tier — the top-edge counterpart
/// of the floating native tab bar.
///
/// Why this exists (allowlist rule 4, clips 12-48/13-17/13-32): a
/// Flutter-drawn opaque app bar cannot coexist with native glass controls in
/// the scrollable beneath it — culling them at the bar seam pops/shimmers,
/// and painting them behind the bar flashes body content OVER the bar
/// (overlay-layer churn, flutter#86787 class). Native chrome resolves both:
/// this bar's glass surface is a platform view painted after the scrolled
/// content, so it composites above every platform view in that content with
/// deterministic UIView z-order — the exact lifecycle that keeps the bottom
/// tab bar clean. Content scrolls full-bleed behind it and culls at the
/// physical screen edge, off-screen.
///
/// Layout contract: place over a full-bleed body (Stack), and raise the
/// body's `MediaQuery.padding.top` by [kAppBoxKitFloatingBarBlockHeight] so
/// descendants inset themselves. The title rides its own native glass
/// capsule; actions are expected to be native glass controls already
/// (icon buttons, popup menus). On tiers without native glass the vendor
/// container degrades to its bare child — hosts should only mount this bar
/// on `AppBoxKitPlatform.supportsLiquidGlass`.
class AppBoxKitNativeFloatingBar extends StatelessWidget {
  const AppBoxKitNativeFloatingBar({super.key, this.title, this.actions});

  /// Title text, shown in a native glass capsule at the leading edge.
  final String? title;

  /// Trailing action widgets — native glass controls, spaced [abxGap8].
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, abxGap8),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              if (title != null)
                // Chrome-gated like every glass-bearing kit widget: the
                // capsule's platform view hides during route slides so it
                // cannot leak over the outgoing/incoming routes.
                LiquidGlassContainer(
                  config: const LiquidGlassConfig(),
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: Text(
                          title!,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ).chromeGated(),
              const Spacer(),
              if (actions != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: abxGap8,
                  children: actions!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
