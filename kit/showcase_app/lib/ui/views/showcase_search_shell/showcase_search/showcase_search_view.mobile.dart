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
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_search_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewMobile
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: abxSize16, vertical: abxSize16),
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
