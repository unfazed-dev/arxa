import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// Settings-style grouped list — [AppBoxKitListSection] of [AppBoxKitListTile]s, each
/// toasting its title.
class ShowcaseComponentsSettingsSectionWidget extends StatelessWidget {
  const ShowcaseComponentsSettingsSectionWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

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
