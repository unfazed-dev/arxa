/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the profile surface — the demo of the kit's
/// navigation rail, toolbar, and feedback surfaces, plus cards that link into
/// the Motion, Maps, and Components showcases. The mobile variant lays the
/// demo cards out in a scrolling list; the tablet and desktop variants are
/// stubs.
///
/// Requirements:
/// 1. [Navigation rail] — view-the-profile-surface
/// A native navigation rail bound to the viewmodel's selected index.
/// 2. [Toolbar] — view-the-profile-surface
/// A native toolbar with share, edit, and delete actions.
/// 3. [Feedback surfaces] — view-the-profile-surface
/// Toast and native-sheet demos through the notification service.
/// 4. [Gallery links] — view-the-profile-surface
/// Cards that push the Motion, Maps, and Components showcase routes.
///
/// Relationships:
///
///      ┌──────────────┐
///      │ profile view │
///      └──────────────┘
///      ACT ▼    ▲ STRM
///      [1-2]
///   ┌───────────────────┐
///   │ profile viewmodel │
///   └───────────────────┘
/// ════════ abxAction ════════
///
///   streams (STRM)            actions (ACT)
///     1. railIndex              1. setRailIndex
///     2. rail
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.desktop.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.tablet.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.mobile.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';

class ShowcaseProfileView extends StackedView<ShowcaseProfileViewModel> {
  const ShowcaseProfileView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const ArxaKitInspectAttrs inspectAttrs = ArxaKitInspectAttrs(
    screenId: 'showcase.profile',
    surfaceId: 'surface.profile.profile',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  ShowcaseProfileViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseProfileViewModel();

  @override
  Widget builder(
    BuildContext context,
    ShowcaseProfileViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseProfileViewMobile(),
      tablet: (_) => const ShowcaseProfileViewTablet(),
      desktop: (_) => const ShowcaseProfileViewDesktop(),
    );
  }
}
