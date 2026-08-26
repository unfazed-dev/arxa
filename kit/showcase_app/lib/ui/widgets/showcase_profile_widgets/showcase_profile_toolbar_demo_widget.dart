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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseProfileToolbarDemoWidget extends StatelessWidget {
  const ShowcaseProfileToolbarDemoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArxaKitNativeToolbar(
      actions: [
        ArxaKitToolbarAction(
            label: 'Share',
            glyph: ArxaKitGlyphs.share,
            onPressed: () => arxaKitLocator<ArxaKitNotificationService>()
                .show('Shared', context: context)),
        ArxaKitToolbarAction(
            label: 'Edit',
            glyph: ArxaKitGlyphs.edit,
            onPressed: () => arxaKitLocator<ArxaKitNotificationService>()
                .show('Edit', context: context)),
        ArxaKitToolbarAction(
            label: 'Delete',
            glyph: ArxaKitGlyphs.delete,
            isDestructive: true,
            onPressed: () => arxaKitLocator<ArxaKitNotificationService>()
                .show('Deleted',
                    kind: ArxaKitNotificationKind.error, context: context)),
      ],
    );
  }
}
