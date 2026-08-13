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

class ShowcaseMotionViewMobile
    extends ViewModelWidget<ShowcaseMotionViewModel> {
  const ShowcaseMotionViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseMotionViewModel viewModel) {
    // Law rule 1 — no partial alpha over platform views. The spec-controls and
    // manual-replay children host native glass in scroll (segmented control,
    // two native buttons; both native by §2 allowlist), and a wake fade over
    // them washes the glass out while the labels survive. Those slots wake on
    // the slide channel alone; every other child keeps the full spec, so the
    // demo still shows the fade.
    final glassSafeSpec = viewModel.spec.copyWith(fade: false);
    return AppBoxKitChromeScaffold(
      // Pushed route on THE chrome scaffold, not a hand-assembled Scaffold +
      // boxed bar: the glass tier now floats native chrome over a full-bleed
      // body, so the list culls at the physical screen edge instead of at a
      // mid-screen bar seam (law rule 4). The native back button is lawful in
      // the leading slot under rule 5's interactive-bar-controls carve-out.
      leading: AppBoxKitNativeIconButton(
        glyph: AppBoxKitGlyphs.back,
        onPressed: () => context.popRoute(),
      ),
      title: 'Motion',
      // Builder: the floating chrome raises `MediaQuery.padding.top` for its
      // BODY subtree only, so the list's inset must be read from a context
      // BELOW this scaffold. Reading it from the view's own context would take
      // the unraised inset on glass and a bare status-bar inset on the boxed
      // tier, where Scaffold has already stripped it — wrong on both branches.
      body: Builder(
        builder: (context) => AppBoxKitMotionScope(
          // No driver: adopts the enclosing route's animation. Push plays the
          // wake; iOS swipe-back scrubs the set-down interactively.
          spec: viewModel.spec,
          // Edge treatment owned by the list (see AppBoxKitEdgeAwareListView)
          // so a child added later inherits it instead of regressing the
          // screen.
          //
          // `extendBehindTopBar` is ON now that this route moved to the chrome
          // scaffold: the list's native glass (segmented control, replay
          // buttons) needs materialization headroom, and the overdraw region
          // is off-screen above NATIVE floating chrome. The clip 13-32
          // regression needed the opaque Flutter bar this migration removed.
          child: AppBoxKitEdgeAwareListView(
            extendBehindTopBar: true,
            // Top inset: 0 under the boxed bar (Scaffold strips it); the
            // status-bar + floating-bar block on glass, where the body is
            // full-bleed. Bottom 120 unchanged.
            padding: EdgeInsets.fromLTRB(
                abxSize16,
                abxSize16 + MediaQuery.paddingOf(context).top,
                abxSize16,
                120),
            children: <Widget>[
              ...<Widget>[
                const ShowcaseMotionHeaderCardWidget(),
                appBoxKitVerticalSpaceMedium,
                const ShowcaseSectionLabelWidget('Spec presets'),
                appBoxKitVerticalSpaceSmall,
              ].wakeAll(),
              ...<Widget>[
                ShowcaseMotionSpecControlsWidget(viewModel: viewModel),
                appBoxKitVerticalSpaceMedium,
                const ShowcaseSectionLabelWidget('Manual replay'),
                appBoxKitVerticalSpaceSmall,
                ShowcaseMotionManualReplayCardWidget(spec: viewModel.spec),
              ].wakeAll(from: 4, spec: glassSafeSpec),
              ...<Widget>[
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
              ].wakeAll(from: 9),
            ],
          ),
        ),
      ),
    );
  }
}
