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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search/showcase_search_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart';

class ShowcaseSearchViewDesktop
    extends ViewModelWidget<ShowcaseSearchViewModel> {
  const ShowcaseSearchViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseSearchView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
