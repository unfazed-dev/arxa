import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart' show BottomSheetService;
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Toast & sheet card: a [KitNotificationService] toast plus the shipping
/// stacked sheet path.
class ShowcaseProfileFeedbackCardWidget extends StatelessWidget {
  const ShowcaseProfileFeedbackCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShowcaseSectionLabelWidget('Toast & sheet'),
          verticalSpaceSmall,
          SizedBox(
            height: kButtonHeightMedium,
            child: KitNativeButton(
              label: 'Show toast',
              glyph: KitGlyphs.alertsBadge,
              onPressed: () => locator<KitNotificationService>().show(
                  'Hello from Kit!',
                  kind: KitNotificationKind.info,
                  context: context),
            ),
          ),
          verticalSpaceSmall,
          SizedBox(
            height: kButtonHeightMedium,
            child: KitNativeButton(
              label: 'Show sheet',
              glyph: KitGlyphs.sheet,
              // The shipping stacked sheet path: the locator's
              // BottomSheetService is KitBottomSheetService, which
              // presents through kitShowNativeSheet from the ROOT
              // navigator context. Never pass a tab's own context here —
              // tabs live inside a NestedRouter, and a modal pushed on
              // the nested navigator renders behind the tab bar.
              onPressed: () => locator<BottomSheetService>().showBottomSheet(
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
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
