import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:stacked_services/stacked_services.dart' show BottomSheetService;
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';
import 'showcase_profile_viewmodel.dart';

class ShowcaseProfileViewMobile
    extends ViewModelWidget<ShowcaseProfileViewModel> {
  const ShowcaseProfileViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileViewModel viewModel) {
    return ListView(
      // Bottom = safe-area + tab-bar block so the last card can scroll
      // clear of the floating KitNativeTabBar — the shell extends the body
      // under it (extendBody) and previously the button laid out
      // unreachable beneath the bar.
      padding: EdgeInsets.fromLTRB(
          kSize16,
          kSize16,
          kSize16,
          kSize16 +
              MediaQuery.paddingOf(context).bottom +
              kShowcaseTabBarBlockHeight),
      children: [
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShowcaseSectionLabel('Navigation rail'),
              verticalSpaceSmall,
              // ponytail: NavigationRail wants bounded height; a fixed SizedBox
              // is the simplest showcase container (a real app puts it in a Row
              // beside content that fills the screen height). 330 fits the M3E
              // tier's real metrics — 36px top spacer + menu button (~60px) +
              // 3 × 74px destinations (66 item + 4+4 gaps); at 260 the rail's
              // internal list clipped Alerts on Android.
              SizedBox(
                height: 330,
                child: Row(
                  children: [
                    KitNativeNavigationRail(
                      selectedIndex: viewModel.railIndex,
                      onDestinationSelected: viewModel.setRailIndex,
                      destinations: const [
                        KitRailDestination(
                            glyph: KitGlyphs.person, label: 'Account'),
                        KitRailDestination(
                            glyph: KitGlyphs.lock, label: 'Privacy'),
                        KitRailDestination(
                            glyph: KitGlyphs.alerts, label: 'Alerts'),
                      ],
                    ),
                    const VerticalDivider(),
                    Expanded(
                      child: Center(
                        child: Text(
                            'Selected: ${ShowcaseProfileViewModel.railLabels[viewModel.railIndex]}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        )
            // iOS 26 scroll edge effect (ADR 0010): glass content softens
            // where it slides under the floating tab bar — external to this
            // scrollable, so the occlusion is explicit (notes folder view is
            // the exemplar). Cards only: the bare toolbar/labels are chrome,
            // not content.
            .scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
        verticalSpaceMedium,
        const ShowcaseSectionLabel('Toolbar'),
        KitNativeToolbar(
          actions: [
            KitToolbarAction(
                label: 'Share',
                glyph: KitGlyphs.share,
                onPressed: () => locator<KitNotificationService>()
                    .show('Shared', context: context)),
            KitToolbarAction(
                label: 'Edit',
                glyph: KitGlyphs.edit,
                onPressed: () => locator<KitNotificationService>()
                    .show('Edit', context: context)),
            KitToolbarAction(
                label: 'Delete',
                glyph: KitGlyphs.delete,
                isDestructive: true,
                onPressed: () => locator<KitNotificationService>().show(
                    'Deleted',
                    kind: KitNotificationKind.error,
                    context: context)),
          ],
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShowcaseSectionLabel('Toast & sheet'),
              verticalSpaceSmall,
              SizedBox(
                height: kButtonHeightMedium,
                child: KitNativeButton(
                  label: 'Show toast',
                  glyph: KitGlyphs.alertsBadge,
                  onPressed: () => locator<KitNotificationService>().show(
                      'Hello from Kit!',
                      kind: KitNotificationKind.info,
                      context: context),
                ),
              ),
              verticalSpaceSmall,
              SizedBox(
                height: kButtonHeightMedium,
                child: KitNativeButton(
                  label: 'Show sheet',
                  glyph: KitGlyphs.sheet,
                  // The shipping stacked sheet path: the locator's
                  // BottomSheetService is KitBottomSheetService, which
                  // presents through kitShowNativeSheet from the ROOT
                  // navigator context. Never pass a tab's own context here —
                  // tabs live inside a NestedRouter, and a modal pushed on
                  // the nested navigator renders behind the tab bar.
                  onPressed: () =>
                      locator<BottomSheetService>().showBottomSheet(
                    title: 'Native sheet',
                    description:
                        'BottomSheetService presents through the kit\'s '
                        'adaptive sheet — CNBottomSheet on iOS, Material 3 '
                        'modal sheet on Android.',
                  ),
                ),
              ),
            ],
          ),
        ).scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShowcaseSectionLabel('Motion'),
              verticalSpaceSmall,
              SizedBox(
                height: kButtonHeightMedium,
                child: KitNativeButton(
                  label: 'Motion showcase',
                  // Relative push within the profile tab's nested router —
                  // the pushed route's animation drives the demo's
                  // KitMotionScope (wake on push, scrubbed set-down on
                  // iOS swipe-back).
                  onPressed: () => context.router.pushNamed('motion'),
                ),
              ),
            ],
          ),
        ).scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShowcaseSectionLabel('Maps'),
              verticalSpaceSmall,
              SizedBox(
                height: kButtonHeightMedium,
                child: KitNativeButton(
                  label: 'Maps showcase',
                  // appbox_kit_maps port — OpenStreetMap out of the box,
                  // Mapbox tiles via --dart-define=MAPBOX_PUBLIC_TOKEN.
                  onPressed: () => context.router.pushNamed('maps'),
                ),
              ),
            ],
          ),
        ).scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ShowcaseSectionLabel('Components'),
              verticalSpaceSmall,
              SizedBox(
                height: kButtonHeightMedium,
                child: KitNativeButton(
                  label: 'Components showcase',
                  // Video-parity sweep (ADR 0011): drawer, glass sheet,
                  // dialog, input bar, grouped lists, chips, center toast.
                  onPressed: () => context.router.pushNamed('components'),
                ),
              ),
            ],
          ),
        ).scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
      ],
    );
  }
}
