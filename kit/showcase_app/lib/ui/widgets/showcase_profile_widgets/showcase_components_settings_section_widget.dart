import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// Settings-style grouped list — [KitListSection] of [KitListTile]s, each
/// toasting its title.
class ShowcaseComponentsSettingsSectionWidget extends StatelessWidget {
  const ShowcaseComponentsSettingsSectionWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      locator<KitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return KitListSection(
      header: 'Settings',
      children: [
        KitListTile(
          glyph: KitGlyphs.person,
          title: 'Account',
          trailingValue: 'Evan',
          showChevron: true,
          onTap: () => _toast(context, 'Account'),
        ),
        KitListTile(
          glyph: KitGlyphs.lock,
          title: 'Privacy',
          showChevron: true,
          onTap: () => _toast(context, 'Privacy'),
        ),
        KitListTile(
          glyph: KitGlyphs.alerts,
          title: 'Notifications',
          trailingValue: 'On',
          showChevron: true,
          onTap: () => _toast(context, 'Notifications'),
        ),
      ],
    );
  }
}
