/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the navigation-rail demo — a native
/// navigation rail bound to the viewmodel's selected index, beside the
/// selected destination's label.
///
/// Requirements:
/// 1. [Navigation rail] — view-the-profile-surface
/// A native navigation rail bound to the viewmodel's rail index.
/// 2. [Selected label] — view-the-profile-surface
/// The selected destination's label is shown beside the rail.
///
/// Relationships:
///
///     ┌──────────────────────────┐
///     │ profile rail card widget │
///     └──────────────────────────┘
///        ACT ▼         ▲ STRM
///        [1-2]
///        ┌───────────────────┐
///        │ profile viewmodel │
///        └───────────────────┘
///     ════════ abxAction ════════
///
///   streams (STRM)            actions (ACT)
///     1. railIndex              1. setRailIndex
///     2. rail
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_profile_rail_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Navigation-rail card: a [AppBoxKitNativeNavigationRail] bound to the
/// viewmodel's rail index, beside the selected destination's label.
class ShowcaseProfileRailCardWidget extends StatelessWidget {
  const ShowcaseProfileRailCardWidget({required this.viewModel, super.key});

  final ShowcaseProfileViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Navigation rail'),
          appBoxKitVerticalSpaceSmall,
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
                AppBoxKitNativeNavigationRail(
                  selectedIndex: viewModel.railIndex,
                  onDestinationSelected: viewModel.setRailIndex,
                  destinations: [
                    for (final rail in ShowcaseProfileRail.values)
                      AppBoxKitRailDestination(
                        glyph: switch (rail) {
                          ShowcaseProfileRail.account => AppBoxKitGlyphs.person,
                          ShowcaseProfileRail.privacy => AppBoxKitGlyphs.lock,
                          ShowcaseProfileRail.alerts => AppBoxKitGlyphs.alerts,
                        },
                        label: rail.label,
                      ),
                  ],
                ),
                const VerticalDivider(),
                Expanded(
                  child: Center(
                    child: Text(
                        'Selected: ${viewModel.rail.label}',
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
      edge: AppBoxKitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
