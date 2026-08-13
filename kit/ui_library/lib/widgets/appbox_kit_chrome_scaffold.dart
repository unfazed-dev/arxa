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
/// Scope: shell/tab-root surfaces AND pushed routes. The v1 scoping (tab
/// roots only, no `leading` slot, because the glass branch had no
/// device-ratified floating back affordance) is SUPERSEDED by the
/// 2026-08-13 ruling that ratified one. A pushed route now uses this
/// scaffold with [leading] set — never a hand-assembled `Scaffold` +
/// [AppBoxKitNativeAppBar], which is exactly the hand-assembly the law's
/// reuse unit exists to prevent.
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
    this.leading,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomSheet,
    this.drawer,
    this.resizeToAvoidBottomInset = true,
    this.behavior = AppBoxKitFloatingBarBehavior.minimize,
    this.debugForceGlassTier,
  });

  /// Surface content. Full-bleed on the glass tier; below the bar elsewhere.
  final Widget body;

  /// Back/close affordance — the floating bar's leading slot on glass, the
  /// boxed bar's `leading` elsewhere. Setting it suppresses the boxed tier's
  /// implied back button (this widget IS the affordance); leaving it null
  /// keeps the tier's automatic one, unchanged. On glass it does not tuck —
  /// see [AppBoxKitNativeFloatingBar.leading].
  final Widget? leading;

  /// Bar title — the floating pill on glass, the bar title elsewhere.
  final String? title;

  /// Trailing actions — native glass controls on the native tiers.
  final List<Widget>? actions;

  /// Forwarded to `Scaffold.floatingActionButton` on every tier.
  final Widget? floatingActionButton;

  /// Forwarded to `Scaffold.bottomSheet` on every tier — the persistent
  /// sheet sits below the body on both branches, so no tier branch is needed.
  final Widget? bottomSheet;

  /// Forwarded to `Scaffold.drawer` on every tier — the drawer is edge-driven
  /// and overlays whichever chrome the tier drew, so no tier branch is needed.
  final Widget? drawer;

  /// Forwarded to `Scaffold.resizeToAvoidBottomInset` on every tier. Hosts
  /// whose [bottomSheet] rides the keyboard itself must pass `false`, which
  /// also keeps that slot's bottom padding (`Scaffold` registers it with
  /// `removeBottomPadding: _resizeToAvoidBottomInset`).
  final bool resizeToAvoidBottomInset;

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
          : AppBoxKitNativeAppBar(
              title: title,
              actions: actions,
              leading: leading,
              // A supplied leading IS the back affordance — letting the tier
              // imply a second one would double it.
              automaticallyImplyLeading: leading == null,
            ),
      body: glass
          ? AppBoxKitFloatingChrome(
              leading: leading,
              title: title,
              actions: actions,
              behavior: behavior,
              body: body,
            )
          : body,
      floatingActionButton: floatingActionButton,
      bottomSheet: bottomSheet,
      drawer: drawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}
