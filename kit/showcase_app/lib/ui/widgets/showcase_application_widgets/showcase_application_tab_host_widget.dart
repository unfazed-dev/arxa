/// A widget is a reusable UI building block: props in via the constructor,
/// widgets out via `build`. It never owns business logic.
///
/// This is the user interface for the application shell's tab host — a stacked
/// tabs router that mounts the four tab shells (home, search, profile, notes)
/// with a floating bottom tab bar and an animated tab stack.
///
/// Requirements:
/// 1. [Tab host] — shell-demos.home-and-application-shells.browse-the-application-shell
/// Mounts the four tab shells with a floating tab bar.
///
/// Relationships:
///
///       ┌─────────────────────────────┐
///       │ application tab host widget │
///       └─────────────────────────────┘
///         ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_application_widgets/showcase_application_tab_host_widget.dart
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_application_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/showcase_tabs_consts.dart';
import 'package:appbox_kit_showcase_app/ui/views/showcase_application_hub/showcase_application_hub_view.dart';

class ShowcaseApplicationTabHostWidget extends StatelessWidget {
  const ShowcaseApplicationTabHostWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StackedTabsRouter.builder(
      routes: ShowcaseApplicationHubView.tabs,
      homeIndex: 0,
      // `children` are the four tab shells — each already a full chrome
      // Scaffold. No app bar / FAB / fade here: the host stays structurally
      // identical across switches, so nothing tears down.
      builder: (context, children, tabsRouter) {
        // Warms the Liquid Glass surface pipeline once at boot so the FIRST
        // glass-card route push doesn't materialize on-screen (measured
        // first-push-only 39.6ms raster spike — docs/plans/
        // glass-push-hotspot-fix.md). Wraps the shell root, mounted once.
        return AppBoxKitGlassWarmup(
            // Motion (pushed, not boot-visible) mounts a native switch; no
            // boot screen does, so its kind warms here (first-push 23.8ms
            // residual measured with the container-only warmer).
            alsoWarm: const [
              AppBoxKitNativeSwitch(value: false),
            ],
            child: Scaffold(
              // Let the body extend behind the floating tab bar pill so content
              // scrolls underneath it (matches AppBoxKitBottomNavScaffold behaviour).
              // Without this the body is laid out above the bar and produces a
              // hard cut against the scaffold background.
              extendBody: true,
              // Mirror the extendBody padding into viewPadding so per-tab FABs
              // float clear of the glass bar (flutter#145680).
              // The pipeline default — AppBoxKitAnimatedTabStack, self-driving (it
              // tracks the previous index, so the router's `animation` is not
              // needed). Platform-resolved: an INSTANT cross-cut on iOS, matching
              // UITabBarController and keeping one tab on stage per frame so a
              // switch never changes the frame's platform-view set (that change is
              // what made switches flicker on these native-chrome tabs); the
              // paired, direction-aware slide on Android, where the tab bodies are
              // Flutter-rendered. Slide-only there too — fade ghosts platform
              // views (flutter#24164/#148639; review check 1c2).
              // Scrim host OUTSIDE both viewPadding-raising wrappers: its opaque
              // band is sized from the RAW device inset, and both lifts below
              // mirror bar clearance into `viewPadding` for their subtrees.
              // Bottom mirror of the top chrome's status-bar scrim — the per-child
              // scroll edge effect is inert on the glass tier, so this is the only
              // bottom-edge dissolve on device (clip 18-50).
              //
              // Yields with the tab bar: the scrim's fadeExtent spans the
              // floating-bar block, sized to dissolve content under the SHARED
              // bar. A route that docks its own bar (the Components composer)
              // must get the raw edge — keeping the scrim up dissolves content
              // into the background right where that route's own bar sits,
              // defeating its glass sampling of the content scrolling under it.
              body: AppBoxKitBottomEdgeScrimHost(
                enabled: !_docksOwnBar(tabsRouter.topRoute.name),
                child: AppBoxKitExtendBodyFabLift(
                  child: _DockFabLift(
                    // When the tab bar yields, the route's own dock occupies the same
                    // band — but it lives on a NESTED Scaffold, so the ancestor
                    // Scaffold that positions the gallery FAB sees `bottomSheetSize
                    // == Size.zero` and cannot lift for it. The FAB's clearance was
                    // never about the bar being a bar: it came from the bar's height
                    // reaching `minViewPadding.bottom` and feeding `safeMargin`
                    // (`floating_action_button_location.dart:566`). Keep supplying
                    // that band and the FAB holds the exact position it had.
                    //
                    // viewPadding only — `SafeArea` reads `padding`, so this cannot
                    // push the composer around.
                    //
                    // ponytail: a constant, not the dock's measured height — the tab
                    // host cannot see into a nested route. It is exact today because
                    // the composer's own bar is `kShowcaseTabBarBlockHeight` tall and
                    // its safe-area inset is already in the base `viewPadding`, so
                    // both sides track the inset together (verified: a 16pt gap at a
                    // 34pt indicator AND at zero). The ceiling is a dock TALLER than
                    // this constant — a multiline composer — which would under-clear.
                    // Measure the dock and plumb the height up if that day comes.
                    extraViewPadding: _docksOwnBar(tabsRouter.topRoute.name)
                        ? kShowcaseTabBarBlockHeight
                        : 0,
                    child: AppBoxKitAnimatedTabStack(
                      activeIndex: tabsRouter.activeIndex,
                      // Tab pages are background-less (this host scaffold paints the
                      // shared surface), so the incoming layer must carry the
                      // scaffold color during a run or the outgoing tab reads
                      // through it (ghosting). Inert on iOS, which never runs.
                      backgroundColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      children: children,
                    ),
                  ),
                ),
              ),
              // One bottom dock at a time: a route that pins its own bar there
              // wins the slot and the shared tab bar yields (see [_docksOwnBar]).
              //
              // Read at build time, with no listener of its own: a nested push
              // calls `notifyAll`, which notifies the ROOT controller
              // (`stacked/…/routing_controller.dart:79-81`); the root delegate
              // then rebuilds this subtree, so `build` re-runs on every nav change
              // anywhere. Verified — swapping in a listenable that never fires
              // left both handoff tests green, so a `ListenableBuilder` here would
              // be inert decoration. `showcase_bottom_dock_handoff_test.dart` is
              // what catches it if that ever stops being true.
              //
              // `topRoute` descends into the ACTIVE tab only, so the yield is
              // per-tab by construction: switching to Home brings the bar straight
              // back even though Components is still mounted in the profile tab's
              // stack. A "someone claimed the dock" counter raised by the mounted
              // route would instead hide the bar in every tab — the C2 shape in
              // docs/plans/glass-chrome-root-cause-fixes.md.
              //
              // `null` and NOT a zero-height `SizedBox`: `Scaffold` strips the
              // body's bottom padding whenever `bottomNavigationBar != null`
              // (`scaffold.dart:3032`), and `removePadding` takes the same amount
              // off `viewPadding` too (`media_query.dart:946-951`). A shrunk-but-
              // present bar therefore consumed the home-indicator inset and handed
              // back nothing, so the route's own dock had no inset left to clear
              // it with and sat on the indicator. Measured: both `padding.bottom`
              // and `viewPadding.bottom` arrived at the composer as 0.0.
              bottomNavigationBar: _docksOwnBar(tabsRouter.topRoute.name)
                  ? null
                  : AppBoxKitNativeTabBar(
                      tabs: [
                        for (final tab in ShowcaseTab.values)
                          AppBoxKitTab(
                            glyph: switch (tab) {
                              ShowcaseTab.home => AppBoxKitGlyphs.home,
                              ShowcaseTab.search => AppBoxKitGlyphs.search,
                              ShowcaseTab.profile => AppBoxKitGlyphs.profile,
                              ShowcaseTab.notes => AppBoxKitGlyphs.notes,
                            },
                            label: tab.label,
                          ),
                      ],
                      currentIndex: tabsRouter.activeIndex,
                      onTap: tabsRouter.setActiveIndex,
                    ),
            ));
      },
    );
  }
}

/// Raises `viewPadding.bottom` for the subtree, so a descendant [Scaffold]
/// floats its FAB clear of a band that Scaffold cannot otherwise see.
///
/// Deliberately `viewPadding` and not `padding`: [SafeArea] and every
/// content-inset consumer read `padding`, so raising that would shove real
/// content around. `FloatingActionButtonLocation` reads `minViewPadding`
/// (`floating_action_button_location.dart:566`), which is what this feeds —
/// the same lever [AppBoxKitExtendBodyFabLift] pulls for the tab bar.
class _DockFabLift extends StatelessWidget {
  const _DockFabLift({required this.extraViewPadding, required this.child});

  final double extraViewPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ALWAYS wrap — never `if (extra <= 0) return child`. That early return
    // changes the tree SHAPE between builds, so the Element below is not
    // reused and the whole tab stack remounts: the nested routers lose their
    // stacks and a pushed route is dropped on the floor. Measured here — the
    // Components push vanished and the app bounced back to the tab root. It is
    // the same shape recorded as C4 in
    // docs/plans/glass-chrome-root-cause-fixes.md. A `+ 0` MediaQuery is free.
    final MediaQueryData mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        viewPadding: mq.viewPadding.copyWith(
          bottom: mq.viewPadding.bottom + math.max(0.0, extraViewPadding),
        ),
      ),
      child: child,
    );
  }
}

/// Routes that pin their own bar in the bottom dock, so the shared tab bar
/// must not draw there too.
///
/// Components hosts a chat input bar as `Scaffold.bottomSheet`; a nested
/// `Scaffold` extends under the host's `extendBody: true` body, so the two
/// land on the same pixels. Yielding costs tab switching on that screen —
/// back is the only way out — which is the accepted trade for one dock.
bool _docksOwnBar(String routeName) =>
    routeName == ShowcaseComponentsViewRoute.name;
