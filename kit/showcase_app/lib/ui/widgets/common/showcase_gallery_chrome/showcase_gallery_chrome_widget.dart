/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for the chrome every widget-gallery TAB ROOT
/// shares — the 'Kit Showcase' app bar (search shortcut + overflow menu) and
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
    // THE chrome scaffold (liquid-glass law): the tier branch — glass
    // floating chrome / M3E boxed / fallback boxed — lives in the kit
    // widget, not here. Behavior stays the device-ratified full minimize
    // (2026-08-13). This widget is the dogfood consumer the law's plan
    // names; hand-assembling chrome here again is a law violation.
    return AppBoxKitChromeScaffold(
      title: 'AppBox Showcase',
      actions: _actions(context),
      behavior: AppBoxKitFloatingBarBehavior.minimize,
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
        child: AppBoxKitNativeFabMenu(
          glyph: AppBoxKitGlyphs.add,
          items: const [
            AppBoxKitMenuItem(
                label: 'New post', glyph: AppBoxKitGlyphs.compose),
            AppBoxKitMenuItem(
                label: 'New photo', glyph: AppBoxKitGlyphs.camera),
            AppBoxKitMenuItem(
                label: 'New event', glyph: AppBoxKitGlyphs.newEvent),
          ],
          onSelect: (item) => appBoxKitLocator<AppBoxKitNotificationService>()
              .show(item.label, context: context),
        ),
      ),
    );
  }
}
