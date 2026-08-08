/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the motion demo — every appbox_kit_motion
/// feature on one pushed surface: route-driven wake/set-down (the route's own
/// animation is the timeline), spec presets with a master switch, manual
/// replay, the flutter_animate adapter, and a gesture-driven scrub card. The
/// tablet and desktop variants reuse the mobile surface (motion specs are
/// form-factor-independent).
///
/// Requirements:
/// 1. [Route-driven wake] — view-the-motion-demo
/// The screen wakes under the route's own animation; iOS swipe-back scrubs it back.
/// 2. [Spec presets] — view-the-motion-demo
/// A segmented control swaps the motion spec preset.
/// 3. [Master switch] — view-the-motion-demo
/// A switch flips motion enabled, rendering every scope settled when off.
/// 4. [Manual replay] — view-the-motion-demo
/// A nested scope replays wake/set-down on demand.
/// 5. [flutter_animate adapter] — view-the-motion-demo
/// A plain animate chain driven by the enclosing scope's timeline.
/// 6. [Gesture driver] — view-the-motion-demo
/// A horizontal drag scrubs the scope's timeline and settles with a spring.
/// 7. [Accessibility] — view-the-motion-demo
/// Reduce-motion (or the master switch off) renders every scope settled.
///
/// Relationships:
///
///      ┌─────────────┐
///      │ motion view │
///      └─────────────┘
///      ACT ▼   ▲ STRM
///      [1-2]   [1-3]
///   ┌──────────────────┐
///   │ motion viewmodel │
///   └──────────────────┘
/// ════════ abxAction ════════
///
///   streams (STRM)            actions (ACT)
///     1. spec                   1. setPreset
///     2. presetIndex            2. setEnabled
///     3. enabled
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.dart
library;

import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.desktop.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.tablet.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

class ShowcaseMotionView extends StackedView<ShowcaseMotionViewModel> {
  const ShowcaseMotionView({super.key});

  /// Identity stamped at emit time (Q12 triple).
  static const AppBoxKitInspectAttrs inspectAttrs = AppBoxKitInspectAttrs(
    screenId: 'showcase.motion',
    surfaceId: 'surface.profile.motion',
    anatomyNodeId: 'anatomy:view.body',
  );

  @override
  Widget builder(
    BuildContext context,
    ShowcaseMotionViewModel viewModel,
    Widget? child,
  ) {
    return ScreenTypeLayout.builder(
      mobile: (_) => const ShowcaseMotionViewMobile(),
      tablet: (_) => const ShowcaseMotionViewTablet(),
      desktop: (_) => const ShowcaseMotionViewDesktop(),
    );
  }

  @override
  ShowcaseMotionViewModel viewModelBuilder(BuildContext context) =>
      ShowcaseMotionViewModel();
}
