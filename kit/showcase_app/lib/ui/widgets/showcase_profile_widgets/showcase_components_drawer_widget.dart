/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the drawer demo — a glassPeek drawer with
/// stock open/drag-close/scrim machinery and menu rows of list tiles.
///
/// Requirements:
/// 1. [Drawer] — browse-the-components-gallery
/// A glassPeek drawer whose menu rows toast their label on tap.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; menu taps close the drawer and toast.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_drawer_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

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
            padding: const EdgeInsets.symmetric(vertical: abxSize16),
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
