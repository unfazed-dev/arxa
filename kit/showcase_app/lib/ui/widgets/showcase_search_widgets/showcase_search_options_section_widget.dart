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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchOptionsSectionWidget extends StatelessWidget {
  const ShowcaseSearchOptionsSectionWidget(
      {super.key, required this.viewModel});

  final ShowcaseSearchViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    // The kit's grouped-list idiom (replacing the hand-composed
    // ArxaKitGlassCard + Divider + ShowcaseLabeledSwitch rows): margin zero —
    // the ListView padding already insets 16.
    return ArxaKitListSection(
      margin: EdgeInsets.zero,
      children: [
        ArxaKitListTile(
          title: 'Open now',
          trailing: ArxaKitNativeSwitch(
            value: viewModel.openNow,
            onChanged: viewModel.setOpenNow,
            semanticLabel: 'Open now',
          ),
        ),
        ArxaKitListTile(
          title: 'Outdoor seating',
          trailing: ArxaKitNativeSwitch(
            value: viewModel.outdoor,
            onChanged: viewModel.setOutdoor,
            semanticLabel: 'Outdoor seating',
          ),
        ),
      ],
    );
    // Edge treatment belongs to the enclosing ArxaKitEdgeAwareListView.
  }
}
