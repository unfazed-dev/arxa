import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';

import 'showcase_shell_view.dart';
import 'showcase_shell_viewmodel.dart';

class ShowcaseShellViewMobile extends ViewModelWidget<ShowcaseShellViewModel> {
  const ShowcaseShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseShellViewModel viewModel) {
    return StackedTabsRouter.builder(
      routes: ShowcaseShellView.tabs,
      homeIndex: 0,
      // `children` are the four tab shells — each already a full chrome
      // Scaffold. No app bar / FAB / fade here: the host stays structurally
      // identical across switches, so nothing tears down.
      builder: (context, children, tabsRouter) {
        return Scaffold(
          // Let the body extend behind the floating tab bar pill so content
          // scrolls underneath it (matches KitBottomNavScaffold behaviour).
          // Without this the body is laid out above the bar and produces a
          // hard cut against the scaffold background.
          extendBody: true,
          // Mirror the extendBody padding into viewPadding so per-tab FABs
          // float clear of the glass bar (flutter#145680).
          // Paired, direction-aware switch: the outgoing tab's live element
          // slides out (toward the edge opposite the incoming tab's origin,
          // RTL-mirrored) while the incoming slides in. This is the pipeline
          // default — KitAnimatedTabStack, self-driving (it tracks the
          // previous index, so the router's `animation` is not needed),
          // slide-only: fade ghosts platform views on native-chrome tabs
          // (flutter#24164/#148639; review check 1c2).
          body: KitExtendBodyFabLift(
            child: KitAnimatedTabStack(
              activeIndex: tabsRouter.activeIndex,
              children: children,
            ),
          ),
          bottomNavigationBar: KitNativeTabBar(
            tabs: const [
              KitTab(glyph: KitGlyphs.home, label: 'Home'),
              KitTab(glyph: KitGlyphs.search, label: 'Search'),
              KitTab(glyph: KitGlyphs.profile, label: 'Profile'),
              KitTab(glyph: KitGlyphs.notes, label: 'Notes'),
            ],
            currentIndex: tabsRouter.activeIndex,
            onTap: tabsRouter.setActiveIndex,
          ),
        );
      },
    );
  }
}
