/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the overlays demo — a card whose buttons
/// show a native dialog, a resizable frosted sheet, a center toast, and open
/// the host shell's drawer.
///
/// Requirements:
/// 1. [Dialog and sheet] — browse-the-components-gallery
/// Native dialog and frosted sheet overlays, pushed on the root navigator.
/// 2. [Sheet height] — browse-the-components-gallery
/// Three buttons present the sheet at 92% (the framework default), 56% and
/// 30% of screen height; a native slider inside the open sheet resizes it
/// live between 20% and 92%.
/// 3. [Center toast] — browse-the-components-gallery
/// A center-positioned toast through the notification service.
/// 4. [Drawer trigger] — browse-the-components-gallery
/// A button opens the host shell's drawer.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; the overlays are imperative kit calls on the root navigator.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_overlays_card_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/enums/showcase_profile_enums/enums.dart';
import 'package:arxa_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Sheet heights the three preset buttons present at, as fractions of screen
/// height. 0.92 is the Cupertino route's own default — `1 - _kTopGapRatio`,
/// `cupertino/sheet.dart:30`.
const double _kDefaultSheetHeight = 0.92;
const double _kMinSheetHeight = 0.20;

class ShowcaseComponentsOverlaysCardWidget extends StatelessWidget {
  const ShowcaseComponentsOverlaysCardWidget({super.key});

  /// Modals must be pushed on the root navigator so they cover the tab bar.
  static BuildContext _modalContext(BuildContext fallback) =>
      StackedService.navigatorKey?.currentContext ?? fallback;

  static void _toast(BuildContext context, String message) =>
      arxaKitLocator<ArxaKitNotificationService>()
          .show(message, context: context);

  /// The height notifier is created per presentation and disposed when the
  /// sheet's future completes, so its lifetime is exactly the sheet's.
  ///
  /// Holding it in State instead would look tidier and be wrong: the sheet is
  /// pushed on the *root* navigator while this card lives inside a tab shell, so
  /// the two lifetimes are not nested and a disposed card could tear the
  /// notifier out from under a still-listening sheet. Scoping it here also keeps
  /// the widget stateless.
  static Future<void> _showSheetAt(BuildContext context, double factor) async {
    final ValueNotifier<double> height = ValueNotifier<double>(factor);
    try {
      await arxaKitShowSheet<void>(
        context: _modalContext(context),
        heightFactor: height,
        builder: (_) => _ResizableSheetBody(height: height),
      );
    } finally {
      height.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArxaKitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ShowcaseSectionLabelWidget('Overlays'),
          arxaKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: ArxaKitNativeButton(
              label: 'Show dialog',
              glyph: ArxaKitGlyphs.info,
              onPressed: () async {
                final result =
                    await arxaKitShowNativeDialog<ShowcaseDialogResult>(
                  context: _modalContext(context),
                  title: 'Delete note?',
                  message: 'This cannot be undone.',
                  actions: [
                    const ArxaKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Keep note',
                      role: ArxaKitDialogActionRole.primary,
                      value: ShowcaseDialogResult.kept,
                    ),
                    const ArxaKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Cancel',
                      value: ShowcaseDialogResult.cancelled,
                    ),
                    const ArxaKitNativeDialogAction<ShowcaseDialogResult>(
                      label: 'Delete',
                      glyph: ArxaKitGlyphs.delete,
                      role: ArxaKitDialogActionRole.destructive,
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
          arxaKitVerticalSpaceSmall,
          const ShowcaseSectionLabelWidget('Sheet height'),
          arxaKitVerticalSpaceXSmall,
          // Equal thirds so the three read as one control, not three buttons
          // that happen to sit together.
          SizedBox(
            height: abxButtonHeightMedium,
            child: Row(
              children: [
                for (final (String label, double factor) in const [
                  ('92%', _kDefaultSheetHeight),
                  ('56%', 0.56),
                  ('30%', 0.30),
                ]) ...[
                  Expanded(
                    child: ArxaKitNativeButton(
                      label: label,
                      onPressed: () => _showSheetAt(context, factor),
                    ),
                  ),
                  if (factor != 0.30) arxaKitHorizontalSpaceSmall,
                ],
              ],
            ),
          ),
          arxaKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            child: ArxaKitNativeButton(
              label: 'Show center toast',
              glyph: ArxaKitGlyphs.alertsBadge,
              onPressed: () =>
                  arxaKitLocator<ArxaKitNotificationService>().show(
                'Centered',
                position: ArxaKitToastPosition.center,
                context: context,
              ),
            ),
          ),
          arxaKitVerticalSpaceSmall,
          SizedBox(
            height: abxButtonHeightMedium,
            // Builder: openDrawer needs a context UNDER this Scaffold.
            child: Builder(
              builder: (scaffoldContext) => ArxaKitNativeButton(
                label: 'Open drawer',
                glyph: ArxaKitGlyphs.more,
                onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's contents: a native slider bound to the same notifier that sizes
/// the sheet, so dragging it resizes the sheet under the finger.
///
/// Layout is deliberate. The slider is pinned above a scrollable body rather
/// than sitting in one scrolling column: at the 20% minimum the sheet is short
/// enough that a slider inside the scroll view could be scrolled out of reach,
/// leaving no way to make the sheet bigger again. The scroll view is what keeps
/// the prose from overflowing at that height instead of throwing.
class _ResizableSheetBody extends StatelessWidget {
  const _ResizableSheetBody({required this.height});

  final ValueNotifier<double> height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, double value, __) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Sheet height',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${(value * 100).round()}%',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: height,
            builder: (_, double value, __) => ArxaKitNativeSlider(
              value: value,
              min: _kMinSheetHeight,
              max: _kDefaultSheetHeight,
              onChanged: (double next) => height.value = next,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Frosted sheet body',
                    style: theme.textTheme.titleLarge,
                  ),
                  arxaKitVerticalSpaceXSmall,
                  Text(
                    'This body is one ArxaKitFrostedSurface panel with the '
                    'sheet\'s own top corners and grabber, sized live by the '
                    'slider above. The page behind is dimmed by the sheet\'s '
                    'overlay — tap it to dismiss.',
                    style: theme.textTheme.bodyMedium,
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
