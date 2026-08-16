/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the grouped-list demo — a settings-style
/// AppBoxKitListSection of tiles that toast their title on tap.
///
/// Requirements:
/// 1. [Grouped list] — browse-the-components-gallery
/// A settings-style grouped list whose tiles toast their title on tap.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; taps toast through the notification service.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_settings_section_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseComponentsSettingsSectionWidget extends StatelessWidget {
  const ShowcaseComponentsSettingsSectionWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>()
          .show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return AppBoxKitListSection(
      header: 'Settings',
      children: [
        AppBoxKitListTile(
          glyph: AppBoxKitGlyphs.person,
          title: 'Account',
          trailingValue: 'Evan',
          showChevron: true,
          onTap: () => _toast(context, 'Account'),
        ),
        AppBoxKitListTile(
          glyph: AppBoxKitGlyphs.lock,
          title: 'Privacy',
          showChevron: true,
          onTap: () => _toast(context, 'Privacy'),
        ),
        AppBoxKitListTile(
          glyph: AppBoxKitGlyphs.alerts,
          title: 'Notifications',
          trailingValue: 'On',
          showChevron: true,
          onTap: () => _toast(context, 'Notifications'),
        ),
      ],
    );
  }
}
