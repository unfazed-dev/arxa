import 'package:flutter/material.dart';
import 'package:stacked_services/stacked_services.dart' show StackedService;
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
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
            height: axButtonHeightMedium,
            child: AppBoxKitNativeButton(
              label: 'Show dialog',
              glyph: AppBoxKitGlyphs.info,
              onPressed: () async {
                final result = await appBoxKitShowNativeDialog<String>(
                  context: _modalContext(context),
                  title: 'Delete note?',
                  message: 'This cannot be undone.',
                  actions: [
                    const AppBoxKitNativeDialogAction<String>(
                      label: 'Keep note',
                      role: AppBoxKitDialogActionRole.primary,
                      value: 'kept',
                    ),
                    const AppBoxKitNativeDialogAction<String>(
                      label: 'Cancel',
                      value: 'cancelled',
                    ),
                    const AppBoxKitNativeDialogAction<String>(
                      label: 'Delete',
                      glyph: AppBoxKitGlyphs.delete,
                      role: AppBoxKitDialogActionRole.destructive,
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
          appBoxKitVerticalSpaceSmall,
          SizedBox(
            height: axButtonHeightMedium,
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
            height: axButtonHeightMedium,
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
            height: axButtonHeightMedium,
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
