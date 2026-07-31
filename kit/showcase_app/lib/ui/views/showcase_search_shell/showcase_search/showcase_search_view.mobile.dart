import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';
import 'showcase_search_viewmodel.dart';

class ShowcaseSearchViewMobile
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize16),
      children: [
        // No controller: the bar manages its own field, and the submit value
        // arrives via onSubmitted — the VM holds no TextEditingController
        // (never-prefill query → onChanged/onSubmitted, per the forms playbook).
        KitNativeSearchBar(
          hint: 'Search places, cafes, parks…',
          onSubmitted: (s) => locator<KitNotificationService>()
              .show('Search: $s', context: context),
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ShowcaseSectionLabel('Radius'),
                  const Spacer(),
                  ShowcaseValueChip(viewModel.radius.toStringAsFixed(2)),
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
                  const ShowcaseSectionLabel('Price range'),
                  const Spacer(),
                  ShowcaseValueChip(
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
        ),
        verticalSpaceMedium,
        // The kit's grouped-list idiom (replacing the hand-composed
        // KitGlassCard + Divider + ShowcaseLabeledSwitch rows): margin zero —
        // the ListView padding already insets 16.
        KitListSection(
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
        ),
      ],
    );
  }
}
