import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Navigation-rail card: a [KitNativeNavigationRail] bound to the
/// viewmodel's rail index, beside the selected destination's label.
class ShowcaseProfileRailCardWidget extends StatelessWidget {
  const ShowcaseProfileRailCardWidget({required this.viewModel, super.key});

  final ShowcaseProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Navigation rail'),
          verticalSpaceSmall,
          // ponytail: NavigationRail wants bounded height; a fixed SizedBox
          // is the simplest showcase container (a real app puts it in a Row
          // beside content that fills the screen height). 330 fits the M3E
          // tier's real metrics — 36px top spacer + menu button (~60px) +
          // 3 × 74px destinations (66 item + 4+4 gaps); at 260 the rail's
          // internal list clipped Alerts on Android.
          SizedBox(
            height: 330,
            child: Row(
              children: [
                KitNativeNavigationRail(
                  selectedIndex: viewModel.railIndex,
                  onDestinationSelected: viewModel.setRailIndex,
                  destinations: const [
                    KitRailDestination(
                        glyph: KitGlyphs.person, label: 'Account'),
                    KitRailDestination(glyph: KitGlyphs.lock, label: 'Privacy'),
                    KitRailDestination(
                        glyph: KitGlyphs.alerts, label: 'Alerts'),
                  ],
                ),
                const VerticalDivider(),
                Expanded(
                  child: Center(
                    child: Text(
                        'Selected: ${ShowcaseProfileViewModel.railLabels[viewModel.railIndex]}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        // iOS 26 scroll edge effect (ADR 0010): glass content softens
        // where it slides under the floating tab bar — external to this
        // scrollable, so the occlusion is explicit (notes folder view is
        // the exemplar). Cards only: the bare toolbar/labels are chrome,
        // not content.
        .scrollEdgeEffect(
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
