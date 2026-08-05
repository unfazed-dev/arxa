import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Radius / price-range filter card for the search leaf. View-specific
/// composite (wires [ShowcaseSearchViewModel]).
class ShowcaseSearchFilterCardWidget extends StatelessWidget {
  const ShowcaseSearchFilterCardWidget({super.key, required this.viewModel});

  final ShowcaseSearchViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShowcaseSectionLabelWidget('Radius'),
              const Spacer(),
              ShowcaseValueChipWidget(viewModel.radius.toStringAsFixed(2)),
            ],
          ),
          KitNativeSlider(
            value: viewModel.radius,
            divisions: 10,
            onChanged: viewModel.setRadius,
          ),
          verticalSpaceSmall,
          Row(
            children: [
              const ShowcaseSectionLabelWidget('Price range'),
              const Spacer(),
              ShowcaseValueChipWidget(
                  '${viewModel.priceStart.toStringAsFixed(2)} – ${viewModel.priceEnd.toStringAsFixed(2)}'),
            ],
          ),
          KitNativeRangeSlider(
            values: RangeValues(viewModel.priceStart, viewModel.priceEnd),
            onChanged: (RangeValues v) =>
                viewModel.setPrice(v.start, v.end),
          ),
        ],
      ),
    )
        // iOS 26 scroll edge effect (ADR 0010): content softens where it
        // slides under the floating tab bar — external to this scrollable,
        // so the occlusion is explicit (same as the notes folder view).
        .scrollEdgeEffect(
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
