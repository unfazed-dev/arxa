/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the profile tab's shell — the container
/// that hosts the profile tab's nested router inside the gallery chrome and
/// routes it to the right form-factor variant. The mobile variant wraps the
/// tab's own navigation stack in the gallery chrome; the tablet and desktop
/// variants are stubs. The viewmodel is an empty placeholder (the shell only
/// routes), kept to satisfy the showcase's five-file surface pattern.
///
/// Requirements:
/// 1. [Profile tab host] — view-the-profile-surface
/// The shell hosts the profile tab's nested router and routes it to a form-factor variant.
///
/// Relationships:
///
///      ┌────────────────────┐
///      │ profile shell view │
///      └────────────────────┘
///   ┌─────────────────────────┐
///   │ profile shell viewmodel │
///   └─────────────────────────┘
///   ════════ abxAction ════════
///
///   No streams or actions — the viewmodel is an empty placeholder.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile_shell_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellView
    extends StackedView<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'showcase.profile',
    surfaceId: 'surface.profile.shell',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseProfileShellViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseProfileShellViewMobile(),
      tablet: (_) => const ShowcaseProfileShellViewTablet(),
      desktop: (_) => const ShowcaseProfileShellViewDesktop(),
    );
  }

  @override
  ShowcaseProfileShellViewModel viewModelBuilder(
    BuildContext context,
  ) =>
      ShowcaseProfileShellViewModel();
}
