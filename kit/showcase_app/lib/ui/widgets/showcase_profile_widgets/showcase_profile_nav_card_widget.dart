import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Section-labeled card with a single button that pushes a named route —
/// used for the profile tab's Motion/Maps/Components showcase links.
class ShowcaseProfileNavCardWidget extends StatelessWidget {
  const ShowcaseProfileNavCardWidget({
    required this.title,
    required this.buttonLabel,
    required this.routeName,
    super.key,
  });

  final String title;
  final String buttonLabel;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShowcaseSectionLabelWidget(title),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: buttonLabel,
              onPressed: () => context.router.pushNamed(routeName),
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
