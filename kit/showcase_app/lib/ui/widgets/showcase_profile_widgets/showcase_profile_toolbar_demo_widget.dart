import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';

/// [KitNativeToolbar] demo — every action toasts through the located
/// [KitNotificationService] (the delete action uses the error kind).
class ShowcaseProfileToolbarDemoWidget extends StatelessWidget {
  const ShowcaseProfileToolbarDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitNativeToolbar(
      actions: [
        KitToolbarAction(
            label: 'Share',
            glyph: KitGlyphs.share,
            onPressed: () => locator<KitNotificationService>()
                .show('Shared', context: context)),
        KitToolbarAction(
            label: 'Edit',
            glyph: KitGlyphs.edit,
            onPressed: () => locator<KitNotificationService>()
                .show('Edit', context: context)),
        KitToolbarAction(
            label: 'Delete',
            glyph: KitGlyphs.delete,
            isDestructive: true,
            onPressed: () => locator<KitNotificationService>().show('Deleted',
                kind: KitNotificationKind.error, context: context)),
      ],
    );
  }
}
