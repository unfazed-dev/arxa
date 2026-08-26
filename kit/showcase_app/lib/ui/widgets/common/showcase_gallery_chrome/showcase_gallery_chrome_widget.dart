/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for the chrome every widget-gallery TAB ROOT
/// shares — the 'Arxa Showcase' app bar (search shortcut + overflow menu) and
/// the compose floating-action-button menu. Chrome is per-surface: each tab
/// ROOT view puts its own body inside this widget, and the shell above it is a
/// bare nested router. A route pushed on top of a tab root therefore renders
/// with only its own chrome — no double-bar stack (ruling 2026-08-13).
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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/enums/showcase_application_enums/enums.dart';

class ShowcaseGalleryChromeWidget extends StatelessWidget {
  const ShowcaseGalleryChromeWidget({required this.child, super.key});
  final Widget child;

  List<Widget> _actions(BuildContext context) {
    final tabsRouter = context.tabsRouter;
    return [
      ArxaKitNativeIconButton(
        glyph: ArxaKitGlyphs.search,
        onPressed: () => tabsRouter.setActiveIndex(ShowcaseTab.search.index),
      ),
      ArxaKitNativePopupMenu(
        glyph: ArxaKitGlyphs.more,
        items: const [
          ArxaKitMenuItem(label: 'Refresh', glyph: ArxaKitGlyphs.refresh),
          ArxaKitMenuItem(label: 'Settings', glyph: ArxaKitGlyphs.settings),
          ArxaKitMenuItem(
              label: 'Sign out',
              glyph: ArxaKitGlyphs.signOut,
              isDestructive: true),
        ],
        onSelect: (item) => arxaKitLocator<ArxaKitNotificationService>()
            .show(item.label, context: context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // THE chrome scaffold (liquid-glass law): the tier branch — glass
    // floating chrome / M3E boxed / fallback boxed — lives in the kit
    // widget, not here. Behavior stays the device-ratified full minimize
    // (2026-08-13). This widget is the dogfood consumer the law's plan
    // names; hand-assembling chrome here again is a law violation.
    return ArxaKitChromeScaffold(
      title: 'Arxa Showcase',
      actions: _actions(context),
      behavior: ArxaKitFloatingBarBehavior.minimize,
      body: child,
      // The FAB is scoped to the tab root that mounts this chrome. A pushed
      // route (Components and its composer dock, Motion, Maps) is no longer a
      // descendant of this Scaffold, so it never has to clear a FAB it does
      // not own — the old cross-Scaffold lift, raised from the tab host's
      // `viewPadding.bottom`, is now only load-bearing for a dock pinned by a
      // tab root itself. Headroom shim: see the M3E clipping note on the kit
      // widget.
      floatingActionButton: SizedBox(
        height: defaultTargetPlatform == TargetPlatform.android ? 280 : null,
        child: ArxaKitNativeFabMenu(
          glyph: ArxaKitGlyphs.add,
          items: const [
            ArxaKitMenuItem(
                label: 'New post', glyph: ArxaKitGlyphs.compose),
            ArxaKitMenuItem(
                label: 'New photo', glyph: ArxaKitGlyphs.camera),
            ArxaKitMenuItem(
                label: 'New event', glyph: ArxaKitGlyphs.newEvent),
          ],
          onSelect: (item) => arxaKitLocator<ArxaKitNotificationService>()
              .show(item.label, context: context),
        ),
      ),
    );
  }
}
