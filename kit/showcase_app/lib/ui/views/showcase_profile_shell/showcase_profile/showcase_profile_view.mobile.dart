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
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart';

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
    // No topEdge: the gallery chrome's AppBoxKitNativeAppBar is an opaque
    // Scaffold.appBar with no extendBodyBehindAppBar, so content never
    // underlaps it — a top effect would fade content just before it clips.
    return AppBoxKitEdgeAwareListView(
      bottomOcclusion: kShowcaseTabBarBlockHeight,
      // NO extendBehindTopBar — see the home list's note (clip 13-32:
      // content flashes over the bar when platform views paint behind it).
      // Bottom = safe-area + tab-bar block so the last card can scroll
      // clear of the floating AppBoxKitNativeTabBar — the shell extends the body
      // under it (extendBody) and previously the button laid out
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
        appBoxKitVerticalSpaceMedium,
        const ShowcaseSectionLabelWidget('Toolbar'),
        const ShowcaseProfileToolbarDemoWidget(),
        appBoxKitVerticalSpaceMedium,
        const ShowcaseProfileFeedbackCardWidget(),
        appBoxKitVerticalSpaceMedium,
        // Relative push within the profile tab's nested router —
        // the pushed route's animation drives the demo's
        // AppBoxKitMotionScope (wake on push, scrubbed set-down on
        // iOS swipe-back).
        const ShowcaseProfileNavCardWidget(
          title: 'Motion',
          buttonLabel: 'Motion showcase',
          routeName: 'motion',
        ),
        appBoxKitVerticalSpaceMedium,
        // appbox_kit_maps port — OpenStreetMap out of the box,
        // Mapbox tiles via --dart-define=MAPBOX_PUBLIC_TOKEN.
        const ShowcaseProfileNavCardWidget(
          title: 'Maps',
          buttonLabel: 'Maps showcase',
          routeName: 'maps',
        ),
        appBoxKitVerticalSpaceMedium,
        // Video-parity sweep (ADR 0011): drawer, glass sheet,
        // dialog, input bar, grouped lists, chips, center toast.
        const ShowcaseProfileNavCardWidget(
          title: 'Components',
          buttonLabel: 'Components showcase',
          routeName: 'components',
        ),
      ],
    );
  }
}
