/// The search shell's view (route `/showcase/search`). A view is actions in,
/// streams out: the user taps and the viewmodel acts; a value changes and the
/// view redraws the part listening to it.
///
/// This is the user interface for the search tab's shell. It is a
/// router-outlet host that mounts the search leaf; the mobile variant wraps
/// the outlet in the gallery chrome.
///
/// Requirements:
/// 1. [Search host] — search-and-attachments.search.search-notes-by-text / search-and-attachments.search.open-a-note-from-a-search-result
/// The shell hosts the search leaf through a nested router.
///
/// Relationships:
///
///          ┌───────────────────┐
///          │ search shell view │
///          └───────────────────┘
///       ┌────────────────────────┐
///       │ search shell viewmodel │
///       └────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.desktop.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.tablet.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_view.mobile.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_search_shell/showcase_search_shell_viewmodel.dart';

class ShowcaseSearchShellView
    extends StackedView<ShowcaseSearchShellViewModel> {
  const ShowcaseSearchShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const ArxaKitInspectAttrs inspectAttrs = ArxaKitInspectAttrs(
    screenId: 'showcase.search',
    surfaceId: 'surface.search.shell',
    anatomyNodeId: 'anatomy:shell.surface',
  );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseSearchShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseSearchShellViewMobile(),
      tablet: (_) => const ShowcaseSearchShellViewTablet(),
      desktop: (_) => const ShowcaseSearchShellViewDesktop(),
    );
  }

  @override
  ShowcaseSearchShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseSearchShellViewModel();
}
