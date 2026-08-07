/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the overlays demo — a card whose buttons
/// show a native dialog, a frosted sheet, a center toast, and open the host
/// scaffold's drawer.
///
/// Requirements:
/// 1. [Dialog and sheet] — browse-the-components-gallery
/// Native dialog and frosted sheet overlays, pushed on the root navigator.
/// 2. [Center toast] — browse-the-components-gallery
/// A center-positioned toast through the notification service.
/// 3. [Drawer trigger] — browse-the-components-gallery
/// A button opens the host scaffold's drawer.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the overlays are imperative kit calls on the root navigator.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_overlays_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Overlays card: native dialog, frosted sheet, center toast, and a button
/// that opens the host Scaffold's drawer.
class ShowcaseComponentsOverlaysCardWidget extends StatelessWidget {
  const ShowcaseComponentsOverlaysCardWidget({super.key});

  /// Modals must be pushed on the root navigator so they cover the tab bar.
  static BuildContext _modalContext(BuildContext fallback) =>
      StackedService.navigatorKey?.currentContext ?? fallback;

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return AppBoxKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShowcaseSectionLabelWidget('Overlays'),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show dialog',
              glyph: AppBoxKitGlyphs.info,
              onPressed: () async {
                final result = await appBoxKitShowNativeDialog<ShowcaseDialogResult>(
                  context: _modalContext(context),
                  title: 'Delete note?',
                  message: 'This cannot be undone.',
                  actions: [
                    const AppBoxKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Keep note',
                      role: AppBoxKitDialogActionRole.primary,
                      value: ShowcaseDialogResult.kept,
                    ),
                    const AppBoxKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Cancel',
                      value: ShowcaseDialogResult.cancelled,
                    ),
                    const AppBoxKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Delete',
                      glyph: AppBoxKitGlyphs.delete,
                      role: AppBoxKitDialogActionRole.destructive,
                      value: ShowcaseDialogResult.deleted,
                    ),
                  ],
                );
                if (result != null && context.mounted) {
                  _toast(context, 'Dialog: ${result.name}');
                }
              },
            ),
          ),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show frosted sheet',
              glyph: AppBoxKitGlyphs.sheet,
              onPressed: () => appBoxKitShowNativeSheet(
                context: _modalContext(context),
                builder: (sheetContext) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Frosted sheet body',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      appBoxKitVerticalSpaceXSmall,
                      Text(
                        'The grabber above and this body are one '
                        'AppBoxKitFrostedSurface panel (blur 30, 28dp '
                        'corners) floating over the dimmed host page.',
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show center toast',
              glyph: AppBoxKitGlyphs.alertsBadge,
              onPressed: () => appBoxKitLocator<AppBoxKitNotificationService>().show(
                'Centered',
                position: AppBoxKitToastPosition.center,
                context: context,
              ),
            ),
          ),
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            // Builder: openDrawer needs a context UNDER this Scaffold.
            child: Builder(
              builder: (scaffoldContext) => AppBoxKitNativeButton(
                label: 'Open drawer',
                glyph: AppBoxKitGlyphs.more,
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
