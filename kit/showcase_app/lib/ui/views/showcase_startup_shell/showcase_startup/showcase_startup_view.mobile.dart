/// The startup leaf's view. A view reads streams out and calls actions in —
/// it draws what the user sees and forwards the user's input; here the one
/// input is telling the viewmodel to boot once the view is ready.
///
/// This is the user interface for the startup leaf. It shows a loading
/// indicator while the app boots and kicks the boot off as soon as it is
/// ready.
///
/// Requirements:
/// 1. [Boot trigger] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// Once the view is ready, it tells the viewmodel to run the boot logic.
/// 2. [Loading screen] — shell-demos.startup-and-unknown-shells.boot-through-the-startup-shell
/// While boot runs, a loading indicator is shown.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │       startup view       │
///   └──────────────────────────┘
///   ACT ▼
///   [1]
///   ┌──────────────────────────┐
///   │    startup viewmodel     │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
///  actions (ACT)
///    1. runStartupLogic
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/widgets/showcase_startup_widgets/widgets.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_startup_shell/showcase_startup/showcase_startup_viewmodel.dart';

class ShowcaseStartupViewMobile
    extends ViewModelWidget<ShowcaseStartupViewModel> {
  const ShowcaseStartupViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseStartupViewModel viewModel) {
    return const ShowcaseStartupLoadingWidget();
  }
}
