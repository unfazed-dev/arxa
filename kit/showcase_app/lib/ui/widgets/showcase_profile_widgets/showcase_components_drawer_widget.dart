import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// glassPeek drawer — stock Drawer machinery (edge-swipe, drag-close,
/// scrim) with the frosted peek skin; menu rows are KitListTiles.
class ShowcaseComponentsDrawerWidget extends StatelessWidget {
  const ShowcaseComponentsDrawerWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      locator<KitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (drawerContext) => KitDrawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: kSize16),
            children: [
              const KitListTile(
                glyph: KitGlyphs.person,
                title: 'Showcase User',
                subtitle: 'evan@seed.local',
              ),
              verticalSpaceSmall,
              KitListSection(
                showDividers: false,
                children: [
                  for (final (glyph, label) in [
                    (KitGlyphs.home, 'Home'),
                    (KitGlyphs.settings, 'Settings'),
                    (KitGlyphs.info, 'About'),
                  ])
                    KitListTile(
                      glyph: glyph,
                      title: label,
                      onTap: () {
                        Scaffold.of(drawerContext).closeDrawer();
                        _toast(drawerContext, label);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
