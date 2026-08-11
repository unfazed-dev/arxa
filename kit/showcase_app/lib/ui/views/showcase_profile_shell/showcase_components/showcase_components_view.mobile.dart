/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the components gallery — one pushed surface
/// proving each wave-1/2 kit capability: the frosted surface, chip carousel,
/// grouped list, glassPeek drawer, native dialog and frosted sheet, the docked
/// input bar, and the center toast. The tablet and desktop variants reuse the
/// mobile surface (the demos are form-factor-independent). The viewmodel is an
/// empty placeholder — every demo is an imperative kit call, no state held.
///
/// Requirements:
/// 1. [Frosted surface] — browse-the-components-gallery
/// An explicit frosted glass panel (the content-layer tier).
/// 2. [Chip carousel] — browse-the-components-gallery
/// A snapping capability rail of chips.
/// 3. [Grouped list] — browse-the-components-gallery
/// A settings-style grouped list of tiles.
/// 4. [Drawer] — browse-the-components-gallery
/// A glassPeek drawer with menu rows.
/// 5. [Dialog and sheet] — browse-the-components-gallery
/// Native dialog and frosted sheet overlays, pushed on the root navigator.
/// 6. [Input bar] — browse-the-components-gallery
/// A docked input bar that rides the keyboard.
/// 7. [Center toast] — browse-the-components-gallery
/// A center-positioned toast through the notification service.
///
/// Relationships:
///
///      ┌─────────────────┐
///      │ components view │
///      └─────────────────┘
///   ┌──────────────────────┐
///   │ components viewmodel │
///   └──────────────────────┘
///  ════════ abxAction ════════
///
///   No streams or actions — the viewmodel is an empty placeholder; every
///   demo is an imperative kit call.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_components/showcase_components_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/showcase_profile_widgets/widgets.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart';

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
        // Bottom clearance for the docked input bar alone — the host tab bar
        // yields its slot on this route, so the old extra 64 is dead space.
        // `Scaffold` never insets the body for a `bottomSheet`; this padding
        // is the only thing keeping the last card off the bar.
        padding: const EdgeInsets.fromLTRB(0, abxSize16, 0, 96),
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
