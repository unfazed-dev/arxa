import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:stacked/stacked.dart';

import 'showcase_application_shell_view.desktop.dart';
import 'showcase_application_shell_view.tablet.dart';
import 'showcase_application_shell_view.mobile.dart';
import 'showcase_application_shell_viewmodel.dart';

/// The showcase's routed shell — the template for how a bespoke appbox_kit
/// app hangs tab SHELLS off the router, mirroring the host `app.dart` pattern
/// (every domain is a shell route with children).
///
/// Tabs are a [StackedTabsRouter] — stacked's IndexedStack tabs model: each
/// tab is its own shell route with its own nested navigation stack, all four
/// stay alive across switches (scroll positions, in-progress edits, pushed
/// routes survive), and tab taps call [TabsRouter.setActiveIndex] instead of
/// pushing — the root back stack stays clean.
///
/// This shell is a **stable nav host**: it owns ONLY the body outlet (the
/// IndexedStack of tab shells) and the bottom tab bar. Every tab owns its OWN
/// chrome (app bar, FAB) inside its shell view — the same pattern as the
/// host's `TrainShellView`/`ShopShellView` (each shell is a self-contained
/// chrome Scaffold). Chrome must NOT live here and toggle per-tab: a native
/// app bar / FAB that mounts for some tabs and nulls for others is recreated
/// on every switch (platform views rebuild, the body re-fades) — that is what
/// made the Notes tab "reload" on tap. With chrome hoisted into the shells,
/// switching tabs only flips which already-mounted Scaffold the IndexedStack
/// reveals — no teardown, no fade, no flash.
///
/// The tab routes are declared as name-based [PageRouteInfo]s (names = page
/// class names, which this package owns), so the shell never imports the
/// generated router — the route block just has to declare the same four
/// children (see `lib/app/app.dart`).
class ShowcaseApplicationShellView extends StackedView<ShowcaseApplicationShellViewModel> {
  const ShowcaseApplicationShellView({super.key});

  /// One entry per tab, in tab order. Names/paths must match the shell's
  /// children in `app.dart` — the single contract between shell and routes.
  static const tabs = [
    PageRouteInfo('ShowcaseHomeShellView', path: 'home'),
    PageRouteInfo('ShowcaseSearchShellView', path: 'search'),
    PageRouteInfo('ShowcaseProfileShellView', path: 'profile'),
    PageRouteInfo('ShowcaseNotesShellView', path: 'notes'),
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
