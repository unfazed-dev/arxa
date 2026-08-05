import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart' show StackedService;
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Overlays card: native dialog, frosted sheet, center toast, and a button
/// that opens the host Scaffold's drawer.
class ShowcaseComponentsOverlaysCardWidget extends StatelessWidget {
  const ShowcaseComponentsOverlaysCardWidget({super.key});

  /// Modals must be pushed on the root navigator so they cover the tab bar.
  static BuildContext _modalContext(BuildContext fallback) =>
      StackedService.navigatorKey?.currentContext ?? fallback;

  static void _toast(BuildContext context, String message) =>
      locator<KitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShowcaseSectionLabelWidget('Overlays'),
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
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      verticalSpaceXSmall,
                      Text(
                        'The grabber above and this body are one '
                        'KitFrostedSurface panel (blur 30, 28dp '
                        'corners) floating over the dimmed host page.',
                        style: Theme.of(sheetContext).textTheme.bodyMedium,
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
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
