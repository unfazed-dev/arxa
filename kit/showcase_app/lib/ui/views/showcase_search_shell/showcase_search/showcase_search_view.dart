/// The search leaf's view (route `/showcase/search`, nested under the search
/// shell). A view is actions in, streams out.
///
/// This is the user interface for the search demo surface — native search bar,
/// sliders, range slider, and switches, all state-driven so the controls
/// respond. The desktop, tablet, and mobile variants each render the surface.
///
/// Requirements:
/// 1. [Filter state] — search-and-attachments.search.search-notes-by-text
/// The leaf wires the native search controls to the filter viewmodel.
///
/// Relationships:
///
///           ┌──────────────────┐
///           │ search leaf view │
///           └──────────────────┘
///           ACT ▼
///           [1-4]
///       ┌─────────────────────────┐
///       │  search leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search/showcase_search_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.desktop.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.tablet.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_view.mobile.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchView extends StackedView<ShowcaseSearchViewModel> {
  const ShowcaseSearchView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const ArxaKitInspectAttrs inspectAttrs = ArxaKitInspectAttrs(
    screenId: 'showcase.search',
    surfaceId: 'surface.search.search',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  ShowcaseSearchViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseSearchViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseSearchViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseSearchViewMobile(),
      tablet: (_) => const ShowcaseSearchViewTablet(),
      desktop: (_) => const ShowcaseSearchViewDesktop(),
    );
  }
}
