/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the feedback-surfaces demo — a card whose
/// buttons fire a toast and present a native sheet through the notification
/// service.
///
/// Requirements:
/// 1. [Feedback surfaces] — view-the-profile-surface
/// Toast and native-sheet demos through the notification service.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the toast and sheet are imperative kit calls.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_profile_feedback_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

class ShowcaseProfileFeedbackCardWidget extends StatelessWidget {
  const ShowcaseProfileFeedbackCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShowcaseSectionLabelWidget('Toast & sheet'),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show toast',
              glyph: AppBoxKitGlyphs.alertsBadge,
              onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>().show(
                  'Hello from Kit!',
                  kind: AppBoxKitNotificationKind.info,
                  context: context),
            ),
          ),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show sheet',
              glyph: AppBoxKitGlyphs.sheet,
              // The kit notice path: AppBoxKitNotificationService.notice
              // presents through the kit's adaptive sheet from the ROOT
              // navigator context. Never pass a tab's own context here —
              // tabs live inside a NestedRouter, and a modal pushed on
              // the nested navigator renders behind the tab bar.
              onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>().notice(
                title: 'Native sheet',
                message: 'The kit presents through its '
                    'adaptive sheet — CNBottomSheet on iOS, Material 3 '
                    'modal sheet on Android.',
              ),
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
