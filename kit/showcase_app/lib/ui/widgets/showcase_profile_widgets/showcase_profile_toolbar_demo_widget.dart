import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

/// [AppBoxKitNativeToolbar] demo — every action toasts through the located
/// [AppBoxKitNotificationService] (the delete action uses the error kind).
class ShowcaseProfileToolbarDemoWidget extends StatelessWidget {
  const ShowcaseProfileToolbarDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitNativeToolbar(
      actions: [
        AppBoxKitToolbarAction(
            label: 'Share',
            glyph: AppBoxKitGlyphs.share,
            onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>()
                .show('Shared', context: context)),
        AppBoxKitToolbarAction(
            label: 'Edit',
            glyph: AppBoxKitGlyphs.edit,
            onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>()
                .show('Edit', context: context)),
        AppBoxKitToolbarAction(
            label: 'Delete',
            glyph: AppBoxKitGlyphs.delete,
            isDestructive: true,
            onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>().show('Deleted',
                kind: AppBoxKitNotificationKind.error, context: context)),
      ],
    );
  }
}
