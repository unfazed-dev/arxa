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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home/showcase_home_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart';

class ShowcaseHomeView extends StackedView<ShowcaseHomeViewModel> {
  const ShowcaseHomeView({super.key});

  @override
  ShowcaseHomeViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseHomeViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseHomeViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseHomeViewMobile(),
      tablet: (_) => const ShowcaseHomeViewTablet(),
      desktop: (_) => const ShowcaseHomeViewDesktop(),
    );
  }
}
