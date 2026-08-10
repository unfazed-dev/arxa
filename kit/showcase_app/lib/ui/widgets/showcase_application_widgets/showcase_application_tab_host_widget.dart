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
          bottomNavigationBar: AppBoxKitNativeTabBar(
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
        );
      },
    );
  }
}
