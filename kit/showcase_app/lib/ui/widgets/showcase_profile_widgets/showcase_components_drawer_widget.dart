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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseComponentsDrawerWidget extends StatelessWidget {
  const ShowcaseComponentsDrawerWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      arxaKitLocator<ArxaKitNotificationService>()
          .show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (drawerContext) => ArxaKitDrawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: abxSize16),
            children: [
              const ArxaKitListTile(
                glyph: ArxaKitGlyphs.person,
                title: 'Showcase User',
                subtitle: 'evan@seed.local',
              ),
              arxaKitVerticalSpaceSmall,
              ArxaKitListSection(
                showDividers: false,
                children: [
                  for (final (glyph, label) in [
                    (ArxaKitGlyphs.home, 'Home'),
                    (ArxaKitGlyphs.settings, 'Settings'),
                    (ArxaKitGlyphs.info, 'About'),
                  ])
                    ArxaKitListTile(
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
