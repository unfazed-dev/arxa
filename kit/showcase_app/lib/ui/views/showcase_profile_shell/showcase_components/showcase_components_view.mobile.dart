import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

/// The video-parity components (ADR 0011) on one pushed surface:
///
/// * **AppBoxKitFrostedSurface** — an explicit content-tier glass card.
/// * **AppBoxKitChip + AppBoxKitChipCarousel** — a snapping capability rail.
/// * **AppBoxKitListSection + AppBoxKitListTile** — a settings-style grouped list (and
///   the drawer's menu rows).
/// * **AppBoxKitDrawer** — the `glassPeek` variant on this Scaffold (edge-swipe or
///   the 'Open drawer' button).
/// * **appBoxKitShowNativeDialog / appBoxKitShowNativeSheet** — presented from the ROOT
///   navigator context (tabs live in a NestedRouter; a modal pushed there
///   renders behind the tab bar — same rule as the profile tab's sheet).
/// * **AppBoxKitNativeInputBar** — docked via `Scaffold.bottomSheet`, riding the
///   keyboard itself.
/// * **Center toast** — `AppBoxKitNotificationService.show` with
///   `AppBoxKitToastPosition.center`.
class ShowcaseComponentsViewMobile
    extends ViewModelWidget<ShowcaseComponentsViewModel> {
  const ShowcaseComponentsViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseComponentsViewModel viewModel) {
    return Scaffold(
      appBar: AppBoxKitNativeAppBar(
        leading: AppBoxKitNativeIconButton(
          glyph: AppBoxKitGlyphs.back,
          onPressed: () => context.popRoute(),
        ),
        title: 'Components',
      ),
      drawer: const ShowcaseComponentsDrawerWidget(),
      bottomSheet: const ShowcaseComponentsInputBarWidget(),
      body: ListView(
        // Bottom clearance for the docked input bar + the floating tab bar.
        padding: const EdgeInsets.fromLTRB(0, abxSize16, 0, 160),
        children: const [
          ShowcaseComponentsInsetWidget(
              child: ShowcaseSectionLabelWidget('Frosted surface')),
          appBoxKitVerticalSpaceSmall,
          ShowcaseComponentsInsetWidget(child: ShowcaseComponentsFrostedSectionWidget()),
          appBoxKitVerticalSpaceMedium,
          ShowcaseComponentsInsetWidget(
              child: ShowcaseSectionLabelWidget('Chip carousel')),
          appBoxKitVerticalSpaceSmall,
          ShowcaseComponentsChipRailWidget(),
          appBoxKitVerticalSpaceMedium,
          ShowcaseComponentsSettingsSectionWidget(),
          appBoxKitVerticalSpaceMedium,
          ShowcaseComponentsInsetWidget(child: ShowcaseComponentsOverlaysCardWidget()),
        ],
      ),
    );
  }
}
