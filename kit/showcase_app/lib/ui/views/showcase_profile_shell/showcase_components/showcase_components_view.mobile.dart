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
    return AppBoxKitChromeScaffold(
      // THE reuse unit (law): a pushed route sets `leading` rather than
      // hand-assembling Scaffold + AppBoxKitNativeAppBar. The native back
      // button is lawful in the bar's leading slot under rule 5's
      // interactive-bar-controls carve-out.
      leading: AppBoxKitNativeIconButton(
        glyph: AppBoxKitGlyphs.back,
        onPressed: () => context.popRoute(),
      ),
      title: 'Components',
      drawer: const ShowcaseComponentsDrawerWidget(),
      // The composer rides the keyboard itself (viewInsets), so the Scaffold
      // must not also resize — and, less obviously, `resizeToAvoidBottomInset`
      // is what decides whether the `bottomSheet` slot keeps its bottom
      // padding: Scaffold registers that slot with
      // `removeBottomPadding: _resizeToAvoidBottomInset`
      // (`scaffold.dart:3086`). Left at the default `true`, the dock is handed
      // padding.bottom = 0 (and viewPadding with it) and lands on the home
      // indicator — measured, that was the composer sitting flush at the
      // screen edge.
      resizeToAvoidBottomInset: false,
      bottomSheet: const ShowcaseComponentsInputBarWidget(),
      // Edge treatment owned by the list (see AppBoxKitEdgeAwareListView) so a
      // child added later inherits it instead of regressing the screen.
      //
      // Builder: the padding below must be read BELOW the scaffold. The glass
      // tier's floating chrome raises MediaQuery.padding.top for its body
      // subtree only, so reading it at this view's own context (above the
      // scaffold) would miss the raise and tuck the first card under the bar.
      body: Builder(
        builder: (context) => AppBoxKitEdgeAwareListView(
          // Materialization headroom, lawful since the migration above: on the
          // glass tier the body is full-bleed under NATIVE floating chrome, so
          // the cull/re-add boundary sits off-screen and iOS 26's glass
          // re-materialize finishes unseen (clip 13-53-b). The flag is
          // unconditional across tiers and that is safe: 13-32 needed platform
          // views painting behind an opaque Flutter bar, and the boxed tiers
          // have none in this list. The overlays card's buttons are the only
          // platform-view-capable children (the chip rail, settings group and
          // frosted section are pure Flutter, and the native slider lives in a
          // PRESENTED sheet, not in the scroll), and on boxed tiers they are
          // AppBarM3E/IconButtonM3E on Android and CNButton's CupertinoButton
          // fallback pre-26 (button.dart:1158) — Flutter either way. So the
          // overdraw there is Flutter-only paint behind the bar.
          extendBehindTopBar: true,
          // Bottom clearance for the docked input bar alone — the host tab bar
          // yields its slot on this route, so the old extra 64 is dead space.
          // `Scaffold` never insets the body for a `bottomSheet`; this padding
          // is the only thing keeping the last card off the bar. No tab-bar or
          // viewPadding.bottom term (unlike home): the tab bar yields this slot
          // and the input bar owns its own SafeArea, so one would double-count.
          //
          // Top inset: 0 under the boxed bar (Scaffold strips it); status bar
          // + kAppBoxKitFloatingBarBlockHeight on glass, where the floating
          // chrome raises padding.top for its body subtree. Pinned both tiers
          // by showcase_components_view_test.
          padding: EdgeInsets.fromLTRB(
              0, abxSize16 + MediaQuery.paddingOf(context).top, 0, 96),
          children: const [
            ShowcaseComponentsInsetWidget(
                child: ShowcaseSectionLabelWidget('Frosted surface')),
            appBoxKitVerticalSpaceSmall,
            ShowcaseComponentsInsetWidget(
                child: ShowcaseComponentsFrostedSectionWidget()),
            appBoxKitVerticalSpaceMedium,
            ShowcaseComponentsInsetWidget(
                child: ShowcaseSectionLabelWidget('Chip carousel')),
            appBoxKitVerticalSpaceSmall,
            ShowcaseComponentsChipRailWidget(),
            appBoxKitVerticalSpaceMedium,
            ShowcaseComponentsSettingsSectionWidget(),
            appBoxKitVerticalSpaceMedium,
            ShowcaseComponentsInsetWidget(
                child: ShowcaseComponentsOverlaysCardWidget()),
          ],
        ),
      ),
    );
  }
}
