/// The search leaf's form-factor variant. A view is actions in, streams out.
///
/// This is the user interface for the search demo surface — the mobile variant
/// owns the gallery chrome (chrome is per-surface, so this tab root carries it
/// rather than the shell) and renders the native search controls wired to the
/// filter viewmodel inside it; desktop and tablet are placeholders.
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
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_search_widgets/widgets.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewMobile
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    // Builder below the chrome: the chrome sits INSIDE this view now, and the
    // glass tier raises MediaQuery.padding.top for its body subtree only — see
    // the home list's note.
    return ShowcaseGalleryChromeWidget(
      child: Builder(
        builder: (context) =>
            // Edge treatment owned by the list (see ArxaKitEdgeAwareListView)
            // — this also covers the search bar, which the per-widget calls
            // skipped. Top fade is auto-skipped here: extendBehindTopBar puts the
            // cull boundary above the physical top, so a top band is unseen.
            ArxaKitEdgeAwareListView(
          bottomOcclusion: kShowcaseTabBarBlockHeight,
          // Materialization headroom above the physical top — see the home
          // list's note (clip 13-53-b; safe since the chrome went native).
          extendBehindTopBar: true,
          // Trailing clearance so the last section can scroll clear of the
          // floating tab bar (otherwise its edge effect never disengages).
          // Top inset mirrors the home list: full-bleed behind the floating
          // native bar on the glass tier, flush under the boxed bar elsewhere.
          padding: EdgeInsets.fromLTRB(
              abxSize16,
              abxSize16 + MediaQuery.paddingOf(context).top,
              abxSize16,
              abxSize16 +
                  MediaQuery.paddingOf(context).bottom +
                  kShowcaseTabBarBlockHeight),
          children: [
            // No controller: the bar manages its own field, and the submit value
            // arrives via onSubmitted — the VM holds no TextEditingController
            // (never-prefill query → onChanged/onSubmitted, per the forms
            // playbook).
            ArxaKitNativeSearchBar(
              hint: 'Search places, cafes, parks…',
              onSubmitted: (s) =>
                  arxaKitLocator<ArxaKitNotificationService>()
                      .show('Search: $s', context: context),
            ),
            arxaKitVerticalSpaceMedium,
            ShowcaseSearchFilterCardWidget(viewModel: viewModel),
            arxaKitVerticalSpaceMedium,
            ShowcaseSearchOptionsSectionWidget(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}
