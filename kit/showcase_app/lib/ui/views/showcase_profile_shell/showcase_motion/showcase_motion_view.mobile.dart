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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

/// Motion showcase — every appbox_kit_motion feature on one pushed surface:
///
/// * **Route-driven wake**: the whole screen sits under a [AppBoxKitMotionScope]
///   with no explicit driver, so the route's push animation *is* the
///   timeline — content wakes as the page arrives, and the iOS swipe-back
///   gesture scrubs the set-down in reverse.
/// * **Spec presets + master switch**: the segmented control swaps
///   [AppBoxKitMotionSpec] presets; the switch flips `enabled` (everything renders
///   settled when off — same behavior reduce-motion triggers automatically).
/// * **Manual replay**: a nested scope with its own controller driver,
///   replayable on demand.
/// * **flutter_animate adapter**: [AppBoxKitMotionAdapter] hands the scope's
///   timeline to a plain `.animate()` chain.
class ShowcaseMotionViewMobile
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) {
    return Scaffold(
      appBar: AppBoxKitNativeAppBar(
        leading: AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Motion',
      ),
      body: AppBoxKitMotionScope(
        // No driver: adopts the enclosing route's animation. Push plays the
        // wake; iOS swipe-back scrubs the set-down interactively.
        spec: viewModel.spec,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(abxSize16, abxSize16, abxSize16, 120),
          children: <Widget>[
            const ShowcaseMotionHeaderCardWidget(),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Spec presets'),
            appBoxKitVerticalSpaceSmall,
            ShowcaseMotionSpecControlsWidget(viewModel: viewModel),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Manual replay'),
            appBoxKitVerticalSpaceSmall,
            ShowcaseMotionManualReplayCardWidget(spec: viewModel.spec),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('flutter_animate adapter'),
            appBoxKitVerticalSpaceSmall,
            const ShowcaseMotionAdapterCardWidget(),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Gesture driver + springs'),
            appBoxKitVerticalSpaceSmall,
            ShowcaseMotionDragScrubCardWidget(spec: viewModel.spec),
            appBoxKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Accessibility'),
            appBoxKitVerticalSpaceSmall,
            const ShowcaseMotionA11yCardWidget(),
          ].wakeAll(),
        ),
      ),
    );
  }
}
