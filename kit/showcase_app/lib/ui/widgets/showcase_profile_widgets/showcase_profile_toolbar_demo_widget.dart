/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the toolbar demo — a native toolbar whose
/// share, edit, and delete actions toast through the notification service.
///
/// Requirements:
/// 1. [Toolbar] — view-the-profile-surface
/// A native toolbar with share, edit, and delete actions.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; each action toasts through the located notification service.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_profile_toolbar_demo_widget.dart
library;

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
