/// The search leaf's form-factor variant. A view is actions in, streams out.
///
/// This is the user interface for the search demo surface — the variant renders
/// the native search controls wired to the filter viewmodel (mobile) or a
/// placeholder (desktop, tablet).
///
/// Requirements:
/// 1. [Filter state] — search-and-attachments.search.search-notes-by-text
/// The variant wires the native search controls to the viewmodel.
///
/// Relationships:
///
///         ┌─────────────────────┐
///         │ search leaf variant │
///         └─────────────────────┘
///         ACT ▼
///         [1-4]
///       ┌─────────────────────────┐
///       │  search leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search/showcase_search_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_search_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewMobile
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    // Edge treatment owned by the list (see AppBoxKitEdgeAwareListView) — this
    // also covers the search bar, which the per-widget calls skipped. No
    // topEdge: the search bar scrolls with the content, it is not pinned
    // chrome, and the gallery app bar is opaque.
    return AppBoxKitEdgeAwareListView(
      bottomOcclusion: kShowcaseTabBarBlockHeight,
      // Trailing clearance so the last section can scroll clear of the
      // floating tab bar (otherwise its edge effect never disengages).
      padding: EdgeInsets.fromLTRB(
          abxSize16,
          abxSize16,
          abxSize16,
          abxSize16 +
              MediaQuery.paddingOf(context).bottom +
              kShowcaseTabBarBlockHeight),
      children: [
        // No controller: the bar manages its own field, and the submit value
        // arrives via onSubmitted — the VM holds no TextEditingController
        // (never-prefill query → onChanged/onSubmitted, per the forms playbook).
        AppBoxKitNativeSearchBar(
          hint: 'Search places, cafes, parks…',
          onSubmitted: (s) => appBoxKitLocator<AppBoxKitNotificationService>()
              .show('Search: $s', context: context),
        ),
        appBoxKitVerticalSpaceMedium,
        ShowcaseSearchFilterCardWidget(viewModel: viewModel),
        appBoxKitVerticalSpaceMedium,
        ShowcaseSearchOptionsSectionWidget(viewModel: viewModel),
      ],
    );
  }
}
