/// The home shell's view. A view reads streams out and calls actions in — it
/// draws what the user sees and forwards the user's input; right now the
/// shell's viewmodel is a passive anchor, so there is nothing to call or read
/// yet.
///
/// This is the user interface for the home shell's outer frame. It wraps a
/// nested router in the gallery chrome so the home tab renders inside.
///
/// Requirements:
/// 1. [Home shell frame] — shell-demos.home-and-application-shells.browse-the-home-shell
/// The shell wraps a nested router in the gallery chrome so the home tab renders inside.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │     home shell view      │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │   home shell viewmodel   │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No actions or streams yet — the viewmodel is a passive anchor.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home_shell_view.desktop.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_home_shell/showcase_home_shell_viewmodel.dart';

class ShowcaseHomeShellViewDesktop
    extends ViewModelWidget<ShowcaseHomeShellViewModel> {
  const ShowcaseHomeShellViewDesktop({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeShellViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, DESKTOP UI - ShowcaseHomeShellView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
