/// The search shell's form-factor variant. A view is actions in, streams out.
///
/// This is the user interface for the search tab's shell — the variant renders
/// the router outlet (mobile wraps it in the gallery chrome).
///
/// Requirements:
/// 1. [Search host] — search-and-attachments.search.search-notes-by-text / search-and-attachments.search.open-a-note-from-a-search-result
/// The variant hosts the search leaf.
///
/// Relationships:
///
///        ┌──────────────────────┐
///        │ search shell variant │
///        └──────────────────────┘
///       ┌────────────────────────┐
///       │ search shell viewmodel │
///       └────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search_shell_view.tablet.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_viewmodel.dart';

class ShowcaseSearchShellViewTablet
    extends ViewModelWidget<ShowcaseSearchShellViewModel> {
  const ShowcaseSearchShellViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseSearchShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseSearchShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
