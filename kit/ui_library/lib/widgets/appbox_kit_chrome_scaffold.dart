import 'package:flutter/material.dart';
import 'package:appbox_kit_core/platform/appbox_kit_platform.dart';

import 'appbox_kit_native_app_bar.dart';
import 'appbox_kit_native_floating_bar.dart';

/// THE chrome scaffold (liquid-glass law, ratified 2026-08-13): one
/// Scaffold-level widget that turns title/actions/body into the ratified
/// top-chrome pattern for whatever tier the app is running on. Hosts never
/// assemble chrome by hand — the clip-0813 saga proved every hand-assembled
/// arrangement wrong at least once.
///
/// The tier branch lives HERE because tier is a RUNTIME property (one iOS
/// binary runs on iOS 18 and 26 alike), so no scaffolder can emit per-tier
/// code:
/// - **Liquid Glass tier** (iOS 26+/macOS 26+): `Scaffold.appBar` is null and
///   the body goes full-bleed under [AppBoxKitFloatingChrome] — native
///   floating chrome, content culled at the physical screen edge, minimize
///   behavior by default. A Flutter-drawn opaque bar over in-scroll native
///   glass is the arrangement the law forbids (seam pop OR over-bar flash —
///   law rule 4).
/// - **Android**: boxed [AppBoxKitNativeAppBar], which renders `AppBarM3E` —
///   Material 3 Expressive is the first-class Android idiom here, not a
///   fallback (see docs/m3e-law.md).
/// - **Everything else** (desktop/web/pre-26 Cupertino): boxed
///   [AppBoxKitNativeAppBar] fallback tiers.
///
/// Scope (v1): shell/tab-root surfaces. There is deliberately no `leading`
/// slot — the glass branch has no device-ratified floating back affordance
/// yet, so pushed routes keep `Scaffold` + [AppBoxKitNativeAppBar].
///
/// Lists under the glass branch must add `MediaQuery.paddingOf(context).top`
/// to their top padding (the floating chrome raises it; boxed tiers report 0)
/// and hosts with native glass in scroll content should pass
/// `extendBehindTopBar: true` to their `AppBoxKitEdgeAwareListView` for
/// materialization headroom.
class AppBoxKitChromeScaffold extends StatelessWidget {
  const AppBoxKitChromeScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.behavior = AppBoxKitFloatingBarBehavior.minimize,
    this.debugForceGlassTier,
  });

  /// Surface content. Full-bleed on the glass tier; below the bar elsewhere.
  final Widget body;

  /// Bar title — the floating pill on glass, the bar title elsewhere.
  final String? title;

  /// Trailing actions — native glass controls on the native tiers.
  final List<Widget>? actions;

  /// Forwarded to `Scaffold.floatingActionButton` on every tier.
  final Widget? floatingActionButton;

  /// Glass-tier scroll reaction. The ratified default is full minimize.
  /// Ignored on boxed tiers (a boxed bar does not tuck).
  final AppBoxKitFloatingBarBehavior behavior;

  /// Test seam: forces the glass branch on, or off, in environments where
  /// `AppBoxKitPlatform.supportsLiquidGlass` cannot vary (widget tests).
  @visibleForTesting
  final bool? debugForceGlassTier;

  @override
  Widget build(BuildContext context) {
    final glass = debugForceGlassTier ?? AppBoxKitPlatform.supportsLiquidGlass;
    return Scaffold(
      appBar: glass
          ? null
          : AppBoxKitNativeAppBar(title: title, actions: actions),
      body: glass
          ? AppBoxKitFloatingChrome(
              title: title,
              actions: actions,
              behavior: behavior,
              body: body,
            )
          : body,
      floatingActionButton: floatingActionButton,
    );
  }
}
