/// A widget is a reusable piece of a view — it composes the kit's primitives
/// and holds no business logic; the view that places it owns the data.
///
/// This is the user interface for a search options section. It shows "Open
/// now" and "Outdoor seating" switches bound to the search viewmodel.
///
/// Requirements:
/// 1. [Option switches]
/// Open-now and outdoor-seating toggles bound to the search viewmodel.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_search_widgets/showcase_search_options_section_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchOptionsSectionWidget extends StatelessWidget {
  const ShowcaseSearchOptionsSectionWidget(
      {super.key, required this.viewModel});

  final ShowcaseSearchViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    // The kit's grouped-list idiom (replacing the hand-composed
    // AppBoxKitGlassCard + Divider + ShowcaseLabeledSwitch rows): margin zero —
    // the ListView padding already insets 16.
    return AppBoxKitListSection(
      margin: EdgeInsets.zero,
      children: [
        AppBoxKitListTile(
          title: 'Open now',
          trailing: AppBoxKitNativeSwitch(
            value: viewModel.openNow,
            onChanged: viewModel.setOpenNow,
            semanticLabel: 'Open now',
          ),
        ),
        AppBoxKitListTile(
          title: 'Outdoor seating',
          trailing: AppBoxKitNativeSwitch(
            value: viewModel.outdoor,
            onChanged: viewModel.setOutdoor,
            semanticLabel: 'Outdoor seating',
          ),
        ),
      ],
    );
    // Edge treatment belongs to the enclosing AppBoxKitEdgeAwareListView.
  }
}
