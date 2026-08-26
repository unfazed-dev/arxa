/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a split-button demo card. It shows a primary
/// "Send" action with a confirm flow and a menu of alternate send actions.
///
/// Requirements:
/// 1. [Split button demo]
/// A native split button with confirm gate and action menu.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_home_widgets/showcase_split_button_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

class ShowcaseSplitButtonCardWidget extends StatelessWidget {
  const ShowcaseSplitButtonCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ArxaKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Split button'),
          arxaKitVerticalSpaceSmall,
          Center(
            child: ArxaKitNativeSplitButton(
              label: 'Send',
              glyph: ArxaKitGlyphs.send,
              onAction: () =>
                  arxaKitLocator<ArxaKitNotificationService>().show(
                'Send this message?',
                kind: ArxaKitNotificationKind.warning,
                actionLabel: 'Confirm',
                onAction: () => arxaKitLocator<ArxaKitNotificationService>()
                    .show('Sent',
                        kind: ArxaKitNotificationKind.success,
                        context: context),
                context: context,
              ),
              menuItems: const [
                ArxaKitMenuItem(
                    label: 'Send now', glyph: ArxaKitGlyphs.send),
                ArxaKitMenuItem(
                    label: 'Schedule', glyph: ArxaKitGlyphs.schedule),
                ArxaKitMenuItem(
                    label: 'Save draft', glyph: ArxaKitGlyphs.saveDraft),
              ],
              onMenuSelected: (item) =>
                  arxaKitLocator<ArxaKitNotificationService>()
                      .show(item.label, context: context),
            ),
          ),
        ],
      ),
    );
    // Edge treatment belongs to the enclosing ArxaKitEdgeAwareListView.
  }
}
