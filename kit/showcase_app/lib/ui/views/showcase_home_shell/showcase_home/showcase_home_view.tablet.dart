/// The home tab's view. A view reads streams out and calls actions in — it
/// draws what the user sees and forwards the user's input; right now the tab's
/// viewmodel is a passive anchor, so the body renders from stateless demo
/// widgets directly.
///
/// This is the user interface for the home tab's body. It lays out the demo
/// widgets — snackbar smokes, the Glass CTA, the theme-mode toggle, and the
/// feedback tier (progress, loading, split button) — so the kit gallery can be
/// browsed.
///
/// Requirements:
/// 1. [Home tab body] — shell-demos.home-and-application-shells.browse-the-home-shell
/// The home tab shows the kit's demo widgets so the gallery can be browsed.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │        home view         │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │      home viewmodel      │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No actions or streams yet — the body is stateless demo widgets.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home/showcase_home_view.tablet.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

class ShowcaseHomeViewTablet extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewTablet({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Hello, TABLET UI - ShowcaseHomeView!',
          style: TextStyle(
            fontSize: 35,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
