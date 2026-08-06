import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart' show BottomSheetService;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Toast & sheet card: a [AppBoxKitNotificationService] toast plus the shipping
/// stacked sheet path.
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
              // The shipping stacked sheet path: the appBoxKitLocator's
              // BottomSheetService is AppBoxKitBottomSheetService, which
              // presents through appBoxKitShowNativeSheet from the ROOT
              // navigator context. Never pass a tab's own context here —
              // tabs live inside a NestedRouter, and a modal pushed on
              // the nested navigator renders behind the tab bar.
              onPressed: () => appBoxKitLocator<BottomSheetService>().showBottomSheet(
                title: 'Native sheet',
                description: 'BottomSheetService presents through the kit\'s '
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
