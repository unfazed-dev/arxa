import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart';

/// Motion showcase — every appbox_kit_motion feature on one pushed surface:
///
/// * **Route-driven wake**: the whole screen sits under a [KitMotionScope]
///   with no explicit driver, so the route's push animation *is* the
///   timeline — content wakes as the page arrives, and the iOS swipe-back
///   gesture scrubs the set-down in reverse.
/// * **Spec presets + master switch**: the segmented control swaps
///   [KitMotionSpec] presets; the switch flips `enabled` (everything renders
///   settled when off — same behavior reduce-motion triggers automatically).
/// * **Manual replay**: a nested scope with its own controller driver,
///   replayable on demand.
/// * **flutter_animate adapter**: [KitMotionAdapter] hands the scope's
///   timeline to a plain `.animate()` chain.
class ShowcaseMotionViewMobile
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) {
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Motion',
      ),
      body: KitMotionScope(
        // No driver: adopts the enclosing route's animation. Push plays the
        // wake; iOS swipe-back scrubs the set-down interactively.
        spec: viewModel.spec,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kSize16, kSize16, kSize16, 120),
          children: <Widget>[
            const ShowcaseMotionHeaderCardWidget(),
            verticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Spec presets'),
            verticalSpaceSmall,
            ShowcaseMotionSpecControlsWidget(viewModel: viewModel),
            verticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Manual replay'),
            verticalSpaceSmall,
            ShowcaseMotionManualReplayCardWidget(spec: viewModel.spec),
            verticalSpaceMedium,
            const ShowcaseSectionLabelWidget('flutter_animate adapter'),
            verticalSpaceSmall,
            const ShowcaseMotionAdapterCardWidget(),
            verticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Gesture driver + springs'),
            verticalSpaceSmall,
            ShowcaseMotionDragScrubCardWidget(spec: viewModel.spec),
            verticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Accessibility'),
            verticalSpaceSmall,
            const ShowcaseMotionA11yCardWidget(),
          ].wakeAll(),
        ),
      ),
    );
  }
}
