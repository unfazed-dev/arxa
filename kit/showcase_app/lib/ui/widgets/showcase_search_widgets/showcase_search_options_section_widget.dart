import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// "Open now" / "Outdoor seating" switch section for the search leaf.
/// View-specific composite (wires [ShowcaseSearchViewModel]).
class ShowcaseSearchOptionsSectionWidget extends StatelessWidget {
  const ShowcaseSearchOptionsSectionWidget({super.key, required this.viewModel});

  final ShowcaseSearchViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    // The kit's grouped-list idiom (replacing the hand-composed
    // KitGlassCard + Divider + ShowcaseLabeledSwitch rows): margin zero —
    // the ListView padding already insets 16.
    return KitListSection(
      margin: EdgeInsets.zero,
      children: [
        KitListTile(
          title: 'Open now',
          trailing: KitNativeSwitch(
            value: viewModel.openNow,
            onChanged: viewModel.setOpenNow,
            semanticLabel: 'Open now',
          ),
        ),
        KitListTile(
          title: 'Outdoor seating',
          trailing: KitNativeSwitch(
            value: viewModel.outdoor,
            onChanged: viewModel.setOutdoor,
            semanticLabel: 'Outdoor seating',
          ),
        ),
      ],
    ).scrollEdgeEffect(
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
