/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the profile surface — the demo of the kit's
/// navigation rail, toolbar, and feedback surfaces, plus cards that link into
/// the Motion, Maps, and Components showcases. The mobile variant owns the
/// gallery chrome (chrome is per-surface, so this tab root carries it rather
/// than the shell — the routes it pushes carry only their own) and lays the
/// demo cards out in a scrolling list inside it; the tablet and desktop
/// variants are stubs.
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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_gallery_chrome/showcase_gallery_chrome_widget.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';

class ShowcaseProfileViewMobile
    extends ViewModelWidget<ShowcaseProfileViewModel> {
  const ShowcaseProfileViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileViewModel viewModel) {
    // The list owns the scroll edge treatment, not the cards: every child is
    // softened where it underlaps the floating tab bar, including the bare
    // toolbar demo and the section labels, which the old per-widget
    // `.scrollEdgeEffect()` calls skipped ("cards only") and which therefore
    // stayed crisp at full alpha while their neighbours faded.
    //
    // Top fade is auto-skipped by the wrapper: extendBehindTopBar moves the
    // cull boundary above the physical top, so a top band is off-screen by
    // construction (edges stays at its both-on default).
    // Builder below the chrome: the chrome sits INSIDE this view now, and the
    // glass tier raises MediaQuery.padding.top for its body subtree only — see
    // the home list's note.
    return ShowcaseGalleryChromeWidget(
      child: Builder(
        builder: (context) => ArxaKitEdgeAwareListView(
          bottomOcclusion: kShowcaseTabBarBlockHeight,
          // Materialization headroom above the physical top — see the home
          // list's note (clip 13-53-b; safe since the chrome went native).
          extendBehindTopBar: true,
          // Bottom = safe-area + tab-bar block so the last card can scroll
          // clear of the floating ArxaKitNativeTabBar — the shell extends the
          // body under it (extendBody) and previously the button laid out
          // unreachable beneath the bar.
          // Top inset mirrors the home list: full-bleed behind the floating
          // native bar on the glass tier, flush under the boxed bar elsewhere.
          padding: EdgeInsets.fromLTRB(
              abxSize16,
              abxSize16 + MediaQuery.paddingOf(context).top,
              abxSize16,
              abxSize16 +
                  MediaQuery.paddingOf(context).bottom +
                  kShowcaseTabBarBlockHeight),
          children: [
            ShowcaseProfileRailCardWidget(viewModel: viewModel),
            arxaKitVerticalSpaceMedium,
            const ShowcaseSectionLabelWidget('Toolbar'),
            const ShowcaseProfileToolbarDemoWidget(),
            arxaKitVerticalSpaceMedium,
            const ShowcaseProfileFeedbackCardWidget(),
            arxaKitVerticalSpaceMedium,
            // Relative push within the profile tab's nested router —
            // the pushed route's animation drives the demo's
            // ArxaKitMotionScope (wake on push, scrubbed set-down on
            // iOS swipe-back). The pushed route replaces this chrome rather
            // than stacking under it — it is not a descendant of the
            // ShowcaseGalleryChromeWidget above.
            const ShowcaseProfileNavCardWidget(
              title: 'Motion',
              buttonLabel: 'Motion showcase',
              routeName: 'motion',
            ),
            arxaKitVerticalSpaceMedium,
            // arxa_kit_maps port — OpenStreetMap out of the box,
            // Mapbox tiles via --dart-define=MAPBOX_PUBLIC_TOKEN.
            const ShowcaseProfileNavCardWidget(
              title: 'Maps',
              buttonLabel: 'Maps showcase',
              routeName: 'maps',
            ),
            arxaKitVerticalSpaceMedium,
            // Video-parity sweep (ADR 0011): drawer, glass sheet,
            // dialog, input bar, grouped lists, chips, center toast.
            const ShowcaseProfileNavCardWidget(
              title: 'Components',
              buttonLabel: 'Components showcase',
              routeName: 'components',
            ),
          ],
        ),
      ),
    );
  }
}
