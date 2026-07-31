import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';

/// The chrome every widget-gallery tab shares: the 'Kit Showcase' app bar
/// (search shortcut + overflow menu) and the compose [KitNativeFabMenu],
/// built from the reusable [KitNativeAppBar] (a `PreferredSizeWidget`, so it
/// slots straight into `Scaffold.appBar` with no wrapper). Notes renders its
/// own per-view `KitNativeAppBar`s in that same slot (compact nav bar, leading
/// back via `KitGlyphs.back`, compose [KitNativeFabMenu]) instead of this chrome.
///
/// Each gallery shell wraps its `NestedRouter` in this so the tab is a
/// self-contained chrome Scaffold, created once on first visit and kept
/// mounted by the IndexedStack — the paradigm the host shells follow.
class ShowcaseGalleryChrome extends StatelessWidget {
  const ShowcaseGalleryChrome({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabsRouter = context.tabsRouter;
    return Scaffold(
      appBar: KitNativeAppBar(
        title: 'Kit Showcase',
        actions: [
          KitNativeIconButton(
            glyph: KitGlyphs.search,
            onPressed: () => tabsRouter.setActiveIndex(1),
          ),
          KitNativePopupMenu(
            glyph: KitGlyphs.more,
            items: const [
              KitMenuItem(label: 'Refresh', glyph: KitGlyphs.refresh),
              KitMenuItem(label: 'Settings', glyph: KitGlyphs.settings),
              KitMenuItem(
                  label: 'Sign out',
                  glyph: KitGlyphs.signOut,
                  isDestructive: true),
            ],
            onSelect: (item) => locator<KitNotificationService>()
                .show(item.label, context: context),
          ),
        ],
      ),
      body: child,
      // Headroom shim: see the M3E clipping note on the kit widget.
      floatingActionButton: SizedBox(
        height: defaultTargetPlatform == TargetPlatform.android ? 280 : null,
        child: KitNativeFabMenu(
          glyph: KitGlyphs.add,
          items: const [
            KitMenuItem(label: 'New post', glyph: KitGlyphs.compose),
            KitMenuItem(label: 'New photo', glyph: KitGlyphs.camera),
            KitMenuItem(label: 'New event', glyph: KitGlyphs.newEvent),
          ],
          onSelect: (item) => locator<KitNotificationService>()
              .show(item.label, context: context),
        ),
      ),
    );
  }
}
