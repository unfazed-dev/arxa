/// A view composes adaptive primitives from the kit's native family and binds
/// the viewmodel's streams with [AppBoxKitStreamBuilder], calling the viewmodel's
/// actions on user input. It never contains business logic — every decision
/// lives in the viewmodel, and only the subtree bound to a changed stream
/// redraws.
///
/// This is the user interface for the notes shell — a nested router host that
/// mounts the Folders, folder-detail, and editor screens under the Notes tab.
/// The shell viewmodel is empty (a lifecycle token); all routing is declarative.
///
/// Requirements:
/// 1. [Nested routing]
/// The mobile variant keeps its own navigation stack; tablet and desktop are
/// placeholder surfaces.
///
/// Relationships:
///
///   ┌──────────────────────────────┐
///   │       notes shell view       │
///   └──────────────────────────────┘
///      ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellView extends StackedView<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'showcase.notes',
    surfaceId: 'surface.notes.shell',
    anatomyNodeId: 'anatomy:shell.surface',
  );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseNotesShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseNotesShellViewMobile(),
      tablet: (_) => const ShowcaseNotesShellViewTablet(),
      desktop: (_) => const ShowcaseNotesShellViewDesktop(),
    );
  }

  @override
  ShowcaseNotesShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseNotesShellViewModel();
}
