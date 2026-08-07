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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_shell_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_notes_shell/showcase_notes_shell_viewmodel.dart';

class ShowcaseNotesShellViewMobile
    extends ViewModelWidget<ShowcaseNotesShellViewModel> {
  const ShowcaseNotesShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseNotesShellViewModel viewModel) {
    return const NestedRouter();
  }
}
