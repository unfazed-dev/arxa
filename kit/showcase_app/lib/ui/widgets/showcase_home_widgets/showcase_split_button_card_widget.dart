import 'package:flutter/material.dart';
import 'package:ui_library/ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Split-button card: primary "Send" action with a confirm flow via
/// [KitNotificationService], plus a menu of alternate send actions.
class ShowcaseSplitButtonCardWidget extends StatelessWidget {
  const ShowcaseSplitButtonCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return KitGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShowcaseSectionLabelWidget('Split button'),
          verticalSpaceSmall,
          Center(
            child: KitNativeSplitButton(
              label: 'Send',
              glyph: KitGlyphs.send,
              onAction: () => locator<KitNotificationService>().show(
                'Send this message?',
                kind: KitNotificationKind.warning,
                actionLabel: 'Confirm',
                onAction: () => locator<KitNotificationService>().show('Sent',
                    kind: KitNotificationKind.success, context: context),
                context: context,
              ),
              menuItems: const [
                KitMenuItem(label: 'Send now', glyph: KitGlyphs.send),
                KitMenuItem(label: 'Schedule', glyph: KitGlyphs.schedule),
                KitMenuItem(label: 'Save draft', glyph: KitGlyphs.saveDraft),
              ],
              onMenuSelected: (item) =>
                  locator<KitNotificationService>().show(item.label,
                      context: context),
            ),
          ),
        ],
      ),
    ).scrollEdgeEffect(
      edge: KitScrollEdge.bottom,
      occlusionPadding: kShowcaseTabBarBlockHeight,
    );
  }
}
