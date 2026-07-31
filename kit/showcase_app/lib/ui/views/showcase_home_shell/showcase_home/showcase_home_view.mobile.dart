import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';
import 'showcase_home_viewmodel.dart';

class ShowcaseHomeViewMobile extends ViewModelWidget<ShowcaseHomeViewModel> {
  const ShowcaseHomeViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseHomeViewModel viewModel) {
    // Smoke-test each KitNotificationKind. Routed through KitNotificationService
    // so Android renders the M3E snackbar (variant derived from kind, configs
    // from setupKitSnackbars) and iOS renders CNToast — no Material snackbar
    // leaks on iOS.
    // KitNativeIconButton so each button shape-morphs on press (Android M3E)
    // and renders liquid glass on iOS 26 — matching every other kit icon
    // button. The semantic tint (muted/good/danger/warn) flows through `color`.
    Widget snackbarButton(
      KitGlyph glyph,
      Color color,
      KitNotificationKind kind,
      String label, {
      KitToastPosition position = KitToastPosition.top,
    }) =>
        KitNativeIconButton(
          glyph: glyph,
          color: color,
          onPressed: () => locator<KitNotificationService>().show(
            label,
            kind: kind,
            position: position,
            context: context,
          ),
        );

    return ListView(
      padding:
          const EdgeInsets.symmetric(horizontal: kSize16, vertical: kSize16),
      children: [
        const Center(
          child: Text(
            'Kit Showcase',
            style:
                TextStyle(fontSize: kFontXXXLarge, fontWeight: FontWeight.w900),
          ),
        ),
        verticalSpaceMedium,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            snackbarButton(KitGlyphs.info, KitColors.muted,
                KitNotificationKind.info, 'Info'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.success, KitColors.good,
                KitNotificationKind.success, 'Success'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.error, KitColors.danger,
                KitNotificationKind.error, 'Error'),
            horizontalSpaceSmall,
            snackbarButton(KitGlyphs.warning, KitColors.warn,
                KitNotificationKind.warning, 'Warning',
                position: KitToastPosition.center),
          ],
        ),
        verticalSpaceMedium,
        // Phase 2b (option B): KitNativeButton delegates to CNButton →
        // real Liquid Glass on iOS 26. Height from the kit's button token;
        // width is intrinsic (no magic numbers).
        SizedBox(
          height: kButtonHeightMedium,
          child: KitNativeButton(
            label: 'Glass CTA',
            glyph: KitGlyphs.star,
            onPressed: () => locator<KitNotificationService>().show(
                'native button tapped',
                position: KitToastPosition.bottom,
                context: context),
          ),
        ),
        verticalSpaceMedium,
        // Native segmented control that drives KitThemeService's theme mode
        // — proves the kit theme is wired end-to-end (see swatch below).
        const ShowcaseThemeModeSegmentedDemo(),
        verticalSpaceLarge,

        // --- Showcase: feedback tier (progress / loading / split button) ---
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShowcaseSectionLabel('Progress & loading'),
              verticalSpaceSmall,
              Row(
                children: [
                  Expanded(
                    // ponytail: determinate 0.6 shows the fill; indeterminate
                    // circular animates; loading indicator is the 3rd tier.
                    child: KitNativeProgress.linear(value: 0.6),
                  ),
                  horizontalSpaceSmall,
                  KitNativeProgress.circular(), // factory, not const-able
                  horizontalSpaceSmall,
                  const KitNativeLoadingIndicator(size: 32),
                ],
              ),
            ],
          ),
        )
            // iOS 26 scroll edge effect (ADR 0010): glass content softens
            // where it slides under the floating tab bar — external to this
            // scrollable, so the occlusion is explicit (notes folder view is
            // the exemplar). Content-only: the native chrome demos above
            // (buttons/segmented) are never edge-effected.
            .scrollEdgeEffect(
          edge: KitScrollEdge.bottom,
          occlusionPadding: kShowcaseTabBarBlockHeight,
        ),
        verticalSpaceMedium,
        KitGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShowcaseSectionLabel('Split button'),
              verticalSpaceSmall,
              Center(
                child: KitNativeSplitButton(
                  label: 'Send',
                  glyph: KitGlyphs.send,
                  onAction: () => locator<KitNotificationService>().show(
                    'Send this message?',
                    kind: KitNotificationKind.warning,
                    actionLabel: 'Confirm',
                    onAction: () => locator<KitNotificationService>().show(
                        'Sent',
                        kind: KitNotificationKind.success,
                        context: context),
                    context: context,
                  ),
                  menuItems: const [
                    KitMenuItem(label: 'Send now', glyph: KitGlyphs.send),
                    KitMenuItem(label: 'Schedule', glyph: KitGlyphs.schedule),
                    KitMenuItem(
                        label: 'Save draft', glyph: KitGlyphs.saveDraft),
                  ],
                  onMenuSelected: (item) => locator<KitNotificationService>()
                      .show(item.label, context: context),
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
