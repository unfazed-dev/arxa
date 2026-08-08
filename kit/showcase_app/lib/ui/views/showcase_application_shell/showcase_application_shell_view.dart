/// The application shell's view (route `/showcase`). A view is actions in,
/// streams out: the user taps and the viewmodel acts; a value changes and the
/// view redraws the part listening to it.
///
/// This is the user interface for the showcase's tabbed root shell. It mounts
/// four tab shells — home, search, profile, notes — as a stacked tabs router,
/// each kept alive across switches. The shell owns only the body outlet and the
/// bottom tab bar; every tab owns its own chrome.
///
/// Requirements:
/// 1. [Tab host] — shell-demos.home-and-application-shells.browse-the-application-shell
/// The shell mounts the four tab shells through a stacked tabs router.
///
/// Relationships:
///
///          ┌────────────────────────┐
///          │ application shell view │
///          └────────────────────────┘
///       ┌─────────────────────────────┐
///       │ application shell viewmodel │
///       └─────────────────────────────┘
///         ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_application_shell/showcase_application_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_application_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_shell/showcase_application_shell_viewmodel.dart';

class ShowcaseApplicationShellView extends StackedView<ShowcaseApplicationShellViewModel> {
  const ShowcaseApplicationShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'showcase.application',
    surfaceId: 'surface.application.shell',
    anatomyNodeId: 'anatomy:shell.surface',
  );

  /// One entry per tab, in [ShowcaseTab] order; names/paths must match the
  /// shell's children in `app.dart`. (`final`: enum field reads aren't const.)
  static final tabs = [
    PageRouteInfo('ShowcaseHomeShellView', path: ShowcaseTab.home.path),
    PageRouteInfo('ShowcaseSearchShellView', path: ShowcaseTab.search.path),
    PageRouteInfo('ShowcaseProfileShellView', path: ShowcaseTab.profile.path),
    PageRouteInfo('ShowcaseNotesShellView', path: ShowcaseTab.notes.path),
  ];

  @override
  Widget builder(
    BuildContext context,
    ShowcaseApplicationShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseApplicationShellViewMobile(),
      tablet: (_) => const ShowcaseApplicationShellViewTablet(),
      desktop: (_) => const ShowcaseApplicationShellViewDesktop(),
    );
  }

  @override
  ShowcaseApplicationShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseApplicationShellViewModel();
}
