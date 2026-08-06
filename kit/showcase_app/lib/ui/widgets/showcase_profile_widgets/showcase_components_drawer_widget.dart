import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// glassPeek drawer — stock Drawer machinery (edge-swipe, drag-close,
/// scrim) with the frosted peek skin; menu rows are AppBoxKitListTiles.
class ShowcaseComponentsDrawerWidget extends StatelessWidget {
  const ShowcaseComponentsDrawerWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (drawerContext) => AppBoxKitDrawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: axSize16),
            children: [
              const AppBoxKitListTile(
                glyph: AppBoxKitGlyphs.person,
                title: 'Showcase User',
                subtitle: 'evan@seed.local',
              ),
              appBoxKitVerticalSpaceSmall,
              AppBoxKitListSection(
                showDividers: false,
                children: [
                  for (final (glyph, label) in [
                    (AppBoxKitGlyphs.home, 'Home'),
                    (AppBoxKitGlyphs.settings, 'Settings'),
                    (AppBoxKitGlyphs.info, 'About'),
                  ])
                    AppBoxKitListTile(
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
