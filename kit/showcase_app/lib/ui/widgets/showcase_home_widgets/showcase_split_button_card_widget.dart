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
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Split-button card: primary "Send" action with a confirm flow via
/// [AppBoxKitNotificationService], plus a menu of alternate send actions.
class ShowcaseSplitButtonCardWidget extends StatelessWidget {
  const ShowcaseSplitButtonCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Split button'),
          appBoxKitVerticalSpaceSmall,
          Center(
            child: AppBoxKitNativeSplitButton(
              label: 'Send',
              glyph: AppBoxKitGlyphs.send,
              onAction: () => appBoxKitLocator<AppBoxKitNotificationService>().show(
                'Send this message?',
                kind: AppBoxKitNotificationKind.warning,
                actionLabel: 'Confirm',
                onAction: () => appBoxKitLocator<AppBoxKitNotificationService>().show('Sent',
                    kind: AppBoxKitNotificationKind.success, context: context),
                context: context,
              ),
              menuItems: const [
                AppBoxKitMenuItem(label: 'Send now', glyph: AppBoxKitGlyphs.send),
                AppBoxKitMenuItem(label: 'Schedule', glyph: AppBoxKitGlyphs.schedule),
                AppBoxKitMenuItem(label: 'Save draft', glyph: AppBoxKitGlyphs.saveDraft),
              ],
              onMenuSelected: (item) =>
                  appBoxKitLocator<AppBoxKitNotificationService>().show(item.label,
                      context: context),
            ),
          ),
        ],
      ),
    ).scrollEdgeEffect(
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
