/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a search filter card. It binds radius and
/// price-range sliders to the search viewmodel, letting the user narrow the
/// results.
///
/// Requirements:
/// 1. [Filter controls]
/// Radius slider and price-range slider bound to the search viewmodel.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_search_widgets/showcase_search_filter_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

class ShowcaseSearchFilterCardWidget extends StatelessWidget {
  const ShowcaseSearchFilterCardWidget({super.key, required this.viewModel});

  final ShowcaseSearchViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
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
          AppBoxKitNativeSlider(
            value: viewModel.radius,
            divisions: 10,
            onChanged: viewModel.setRadius,
          ),
          appBoxKitVerticalSpaceSmall,
          Row(
            children: [
              const ShowcaseSectionLabelWidget('Price range'),
              const Spacer(),
              ShowcaseValueChipWidget(
                  '${viewModel.priceStart.toStringAsFixed(2)} – ${viewModel.priceEnd.toStringAsFixed(2)}'),
            ],
          ),
          AppBoxKitNativeRangeSlider(
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
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
