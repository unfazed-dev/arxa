import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart' show StackedService;
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/common/showcase_tabs_shared.dart';

import 'showcase_components_viewmodel.dart';

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

  /// Modals must be pushed on the root navigator so they cover the tab bar.
  static BuildContext _modalContext(BuildContext fallback) =>
      StackedService.navigatorKey?.currentContext ?? fallback;

  static void _toast(BuildContext context, String message) =>
      locator<KitNotificationService>().show(message, context: context);

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
      // glassPeek drawer — stock Drawer machinery (edge-swipe, drag-close,
      // scrim) with the frosted peek skin; menu rows are KitListTiles.
      drawer: Builder(
        builder: (drawerContext) => KitDrawer(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: kSize16),
              children: [
                const KitListTile(
                  glyph: KitGlyphs.person,
                  title: 'Showcase User',
                  subtitle: 'evan@seed.local',
                ),
                verticalSpaceSmall,
                KitListSection(
                  showDividers: false,
                  children: [
                    for (final (glyph, label) in [
                      (KitGlyphs.home, 'Home'),
                      (KitGlyphs.settings, 'Settings'),
                      (KitGlyphs.info, 'About'),
                    ])
                      KitListTile(
                        glyph: glyph,
                        title: label,
                        onTap: () {
                          Scaffold.of(drawerContext).closeDrawer();
                          _toast(drawerContext, label);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      // Docked input bar. The shell extends the body under the floating tab
      // bar, so the bar is lifted by the tab-bar block; it rides the
      // keyboard itself via its own viewInsets padding.
      bottomSheet: Padding(
        padding: const EdgeInsets.only(bottom: kShowcaseTabBarBlockHeight),
        child: KitNativeInputBar(
          hintText: 'Message',
          leading: [
            KitNativeIconButton(
              glyph: KitGlyphs.add,
              onPressed: () => _toast(context, 'Attach'),
            ),
          ],
          trailing: [
            KitNativeIconButton(
              glyph: KitGlyphs.mic,
              onPressed: () => _toast(context, 'Voice'),
            ),
          ],
          onSubmitted: (text) => _toast(context, 'Sent: $text'),
        ),
      ),
      body: ListView(
        // Bottom clearance for the docked input bar + the floating tab bar.
        padding: const EdgeInsets.fromLTRB(0, kSize16, 0, 160),
        children: [
          const _Inset(child: ShowcaseSectionLabel('Frosted surface')),
          verticalSpaceSmall,
          const _Inset(
            child: KitFrostedSurface(
              padding: EdgeInsets.all(kSize16),
              child: Text(
                'An explicit KitFrostedSurface — the ADR 0010 content-layer '
                'glass tier (Flutter-drawn frost: BackdropFilter + tint + rim '
                'highlight). Sheet/dialog bodies and the drawer skin compose '
                'on this same widget.',
              ),
            ),
          ),
          verticalSpaceMedium,
          const _Inset(child: ShowcaseSectionLabel('Chip carousel')),
          verticalSpaceSmall,
          KitChipCarousel(
            snap: true,
            children: [
              for (final (glyph, label) in [
                (KitGlyphs.home, 'Home'),
                (KitGlyphs.search, 'Search'),
                (KitGlyphs.notes, 'Notes'),
                (KitGlyphs.camera, 'Camera'),
                (KitGlyphs.mic, 'Voice'),
                (KitGlyphs.share, 'Share'),
                (KitGlyphs.edit, 'Edit'),
                (KitGlyphs.star, 'Star'),
                (KitGlyphs.tag, 'Tag'),
                (KitGlyphs.settings, 'Settings'),
              ])
                KitChip(
                  glyph: glyph,
                  label: label,
                  onTap: () => _toast(context, label),
                ),
            ],
          ),
          verticalSpaceMedium,
          KitListSection(
            header: 'Settings',
            children: [
              KitListTile(
                glyph: KitGlyphs.person,
                title: 'Account',
                trailingValue: 'Evan',
                showChevron: true,
                onTap: () => _toast(context, 'Account'),
              ),
              KitListTile(
                glyph: KitGlyphs.lock,
                title: 'Privacy',
                showChevron: true,
                onTap: () => _toast(context, 'Privacy'),
              ),
              KitListTile(
                glyph: KitGlyphs.alerts,
                title: 'Notifications',
                trailingValue: 'On',
                showChevron: true,
                onTap: () => _toast(context, 'Notifications'),
              ),
            ],
          ),
          verticalSpaceMedium,
          _Inset(
            child: KitGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ShowcaseSectionLabel('Overlays'),
                  verticalSpaceSmall,
                  SizedBox(
                    height: kButtonHeightMedium,
                    child: KitNativeButton(
                      label: 'Show dialog',
                      glyph: KitGlyphs.info,
                      onPressed: () async {
                        final result = await kitShowNativeDialog<String>(
                          context: _modalContext(context),
                          title: 'Delete note?',
                          message: 'This cannot be undone.',
                          actions: [
                            const KitNativeDialogAction<String>(
                              label: 'Keep note',
                              role: KitDialogActionRole.primary,
                              value: 'kept',
                            ),
                            const KitNativeDialogAction<String>(
                              label: 'Cancel',
                              value: 'cancelled',
                            ),
                            const KitNativeDialogAction<String>(
                              label: 'Delete',
                              glyph: KitGlyphs.delete,
                              role: KitDialogActionRole.destructive,
                              value: 'deleted',
                            ),
                          ],
                        );
                        if (result != null && context.mounted) {
                          _toast(context, 'Dialog: $result');
                        }
                      },
                    ),
                  ),
                  verticalSpaceSmall,
                  SizedBox(
                    height: kButtonHeightMedium,
                    child: KitNativeButton(
                      label: 'Show frosted sheet',
                      glyph: KitGlyphs.sheet,
                      onPressed: () => kitShowNativeSheet(
                        context: _modalContext(context),
                        builder: (sheetContext) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Frosted sheet body',
                                style:
                                    Theme.of(sheetContext).textTheme.titleLarge,
                              ),
                              verticalSpaceXSmall,
                              Text(
                                'The grabber above and this body are one '
                                'KitFrostedSurface panel (blur 30, 28dp '
                                'corners) floating over the dimmed host page.',
                                style:
                                    Theme.of(sheetContext).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  verticalSpaceSmall,
                  SizedBox(
                    height: kButtonHeightMedium,
                    child: KitNativeButton(
                      label: 'Show center toast',
                      glyph: KitGlyphs.alertsBadge,
                      onPressed: () => locator<KitNotificationService>().show(
                        'Centered',
                        position: KitToastPosition.center,
                        context: context,
                      ),
                    ),
                  ),
                  verticalSpaceSmall,
                  SizedBox(
                    height: kButtonHeightMedium,
                    // Builder: openDrawer needs a context UNDER this Scaffold.
                    child: Builder(
                      builder: (scaffoldContext) => KitNativeButton(
                        label: 'Open drawer',
                        glyph: KitGlyphs.more,
                        onPressed: () =>
                            Scaffold.of(scaffoldContext).openDrawer(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal inset for full-bleed ListView children (the carousel and the
/// list section carry their own 16dp margins).
class _Inset extends StatelessWidget {
  const _Inset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: kSize16),
        child: child,
      );
}
