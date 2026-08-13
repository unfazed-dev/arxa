/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for the chrome every widget-gallery tab shares —
/// the 'Kit Showcase' app bar (search shortcut + overflow menu) and the compose
/// floating-action-button menu. Each gallery shell puts its nested router
/// inside this widget so the tab owns its own chrome.
///
/// Requirements:
/// 1. [Gallery chrome] — profile-and-gallery-demos.gallery.browse-the-components-gallery
/// The shared app bar and compose button every gallery tab uses.
///
/// Relationships:
///
///       ┌──────────────────────────┐
///       │  gallery chrome widget   │
///       └──────────────────────────┘
///        ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_application_enums/enums.dart';

class ShowcaseGalleryChromeWidget extends StatelessWidget {
  const ShowcaseGalleryChromeWidget({required this.child, super.key});
  final Widget child;

  List<Widget> _actions(BuildContext context) {
    final tabsRouter = context.tabsRouter;
    return [
      AppBoxKitNativeIconButton(
        glyph: AppBoxKitGlyphs.search,
        onPressed: () => tabsRouter.setActiveIndex(ShowcaseTab.search.index),
      ),
      AppBoxKitNativePopupMenu(
        glyph: AppBoxKitGlyphs.more,
        items: const [
          AppBoxKitMenuItem(label: 'Refresh', glyph: AppBoxKitGlyphs.refresh),
          AppBoxKitMenuItem(label: 'Settings', glyph: AppBoxKitGlyphs.settings),
          AppBoxKitMenuItem(
              label: 'Sign out',
              glyph: AppBoxKitGlyphs.signOut,
              isDestructive: true),
        ],
        onSelect: (item) => appBoxKitLocator<AppBoxKitNotificationService>()
            .show(item.label, context: context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Glass tier: NATIVE floating top chrome over a full-bleed body — the
    // top-edge counterpart of the floating tab bar. A Flutter-drawn opaque
    // bar cannot coexist with native glass controls scrolling beneath it
    // (seam pop OR over-bar flash — allowlist rule 4, clips 12-48/13-17/
    // 13-32; ruling 2026-08-13). Content culls at the physical screen edge;
    // nested-route Scaffolds inset themselves via the raised MediaQuery
    // padding, unmodified.
    final glass = AppBoxKitPlatform.supportsLiquidGlass;
    return Scaffold(
      appBar: glass
          ? null
          : AppBoxKitNativeAppBar(
              title: 'Kit Showcase',
              actions: _actions(context),
            ),
      body: !glass
          ? child
          : AppBoxKitFloatingChrome(
              title: 'Kit Showcase',
              actions: _actions(context),
              // Trying hide (2026-08-13): whole bar slides off the top on
              // scroll-away, returns on scroll-back. Previous pick was
              // minimize (actions tuck, title pill stays) — one-word swap
              // to go back.
              behavior: AppBoxKitFloatingBarBehavior.hide,
              body: child,
            ),
      // NOTE on the FAB and a route's bottom dock: when a gallery route pins
      // its own dock (Components pins a chat composer), this Scaffold cannot
      // see it — the dock is a `bottomSheet` on a NESTED Scaffold, so
      // `bottomSheetSize` here is `Size.zero` and no
      // `FloatingActionButtonLocation` can react to it. The lift is supplied
      // from above instead, by raising `viewPadding.bottom` in the tab host
      // (`showcase_application_tab_host_widget.dart`), which feeds this
      // Scaffold's `minViewPadding` and therefore `endFloat`'s safe margin.
      // Headroom shim: see the M3E clipping note on the kit widget.
      floatingActionButton: SizedBox(
        height: defaultTargetPlatform == TargetPlatform.android ? 280 : null,
        child: AppBoxKitNativeFabMenu(
          glyph: AppBoxKitGlyphs.add,
          items: const [
            AppBoxKitMenuItem(label: 'New post', glyph: AppBoxKitGlyphs.compose),
            AppBoxKitMenuItem(label: 'New photo', glyph: AppBoxKitGlyphs.camera),
            AppBoxKitMenuItem(label: 'New event', glyph: AppBoxKitGlyphs.newEvent),
          ],
          onSelect: (item) => appBoxKitLocator<AppBoxKitNotificationService>()
              .show(item.label, context: context),
        ),
      ),
    );
  }
}
