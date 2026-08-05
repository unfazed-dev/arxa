import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

/// The video-parity components (ADR 0011) on one pushed surface:
///
/// * **KitFrostedSurface** — an explicit content-tier glass card.
/// * **KitChip + KitChipCarousel** — a snapping capability rail.
/// * **KitListSection + KitListTile** — a settings-style grouped list (and
///   the drawer's menu rows).
/// * **KitDrawer** — the `glassPeek` variant on this Scaffold (edge-swipe or
///   the 'Open drawer' button).
/// * **kitShowNativeDialog / kitShowNativeSheet** — presented from the ROOT
///   navigator context (tabs live in a NestedRouter; a modal pushed there
///   renders behind the tab bar — same rule as the profile tab's sheet).
/// * **KitNativeInputBar** — docked via `Scaffold.bottomSheet`, riding the
///   keyboard itself.
/// * **Center toast** — `KitNotificationService.show` with
///   `KitToastPosition.center`.
class ShowcaseComponentsViewMobile
    extends ViewModelWidget<ShowcaseComponentsViewModel> {
  const ShowcaseComponentsViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseComponentsViewModel viewModel) {
    return Scaffold(
      appBar: KitNativeAppBar(
        leading: KitNativeIconButton(
          glyph: KitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Components',
      ),
      drawer: const ShowcaseComponentsDrawerWidget(),
      bottomSheet: const ShowcaseComponentsInputBarWidget(),
      body: ListView(
        // Bottom clearance for the docked input bar + the floating tab bar.
        padding: const EdgeInsets.fromLTRB(0, kSize16, 0, 160),
        children: const [
          ShowcaseComponentsInsetWidget(
              child: ShowcaseSectionLabelWidget('Frosted surface')),
          verticalSpaceSmall,
          ShowcaseComponentsInsetWidget(child: ShowcaseComponentsFrostedSectionWidget()),
          verticalSpaceMedium,
          ShowcaseComponentsInsetWidget(
              child: ShowcaseSectionLabelWidget('Chip carousel')),
          verticalSpaceSmall,
          ShowcaseComponentsChipRailWidget(),
          verticalSpaceMedium,
          ShowcaseComponentsSettingsSectionWidget(),
          verticalSpaceMedium,
          ShowcaseComponentsInsetWidget(child: ShowcaseComponentsOverlaysCardWidget()),
        ],
      ),
    );
  }
}
