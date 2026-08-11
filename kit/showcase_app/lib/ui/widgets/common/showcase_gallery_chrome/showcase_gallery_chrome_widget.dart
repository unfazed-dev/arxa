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

  @override
  Widget build(BuildContext context) {
    final tabsRouter = context.tabsRouter;
    return Scaffold(
      appBar: AppBoxKitNativeAppBar(
        title: 'Kit Showcase',
        actions: [
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
        ],
      ),
      body: child,
      // A gallery route may pin its own bottom dock (Components pins a chat
      // composer as `bottomSheet`). Material's endFloat would then park the
      // FAB straddling that dock's top edge, over its trailing control; this
      // location clears it instead. Identical to endFloat when no dock is
      // present, so it is set unconditionally.
      floatingActionButtonLocation: AppBoxKitFabAboveDock.endFloat,
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
