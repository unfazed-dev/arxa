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

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/app/app.router.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_application_enums/enums.dart';
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
        return Scaffold(
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
          body: AppBoxKitExtendBodyFabLift(
            child: AppBoxKitAnimatedTabStack(
              activeIndex: tabsRouter.activeIndex,
              // Tab pages are background-less (this host scaffold paints the
              // shared surface), so the incoming layer must carry the scaffold
              // color during a run or the outgoing tab reads through it
              // (ghosting). Inert on iOS, which never runs.
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              children: children,
            ),
          ),
          // One bottom dock at a time: a route that pins its own bar there
          // wins the slot and the shared tab bar yields (see [_docksOwnBar]).
          // Listening to `root` and not to `tabsRouter` is load-bearing — a
          // push inside a tab's NESTED router notifies itself and the root
          // controller only (`stacked/…/routing_controller.dart:79-81`), so a
          // listener on this TabsRouter never learns the profile tab moved to
          // Components.
          bottomNavigationBar: ListenableBuilder(
            listenable: tabsRouter.root,
            builder: (context, _) {
              // `topRoute` descends into the ACTIVE tab only, so the yield is
              // per-tab by construction: switching to Home brings the bar
              // straight back even though Components is still mounted in the
              // profile tab's stack. A global "someone claimed the dock"
              // counter would hide the bar in every tab — the C2 shape in
              // docs/plans/glass-chrome-root-cause-fixes.md.
              if (_docksOwnBar(tabsRouter.topRoute.name)) {
                return const SizedBox.shrink();
              }
              return AppBoxKitNativeTabBar(
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
              );
            },
          ),
        );
      },
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
