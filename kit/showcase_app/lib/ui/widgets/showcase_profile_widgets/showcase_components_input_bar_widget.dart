import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_showcase_app/ui/widgets/common/showcase_tabs_shared/widgets.dart';

/// Docked input bar. The shell extends the body under the floating tab
/// bar, so the bar is lifted by the tab-bar block; it rides the
/// keyboard itself via its own viewInsets padding.
class ShowcaseComponentsInputBarWidget extends StatelessWidget {
  const ShowcaseComponentsInputBarWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kShowcaseTabBarBlockHeight),
      child: AppBoxKitNativeInputBar(
        hintText: 'Message',
        leading: [
          AppBoxKitNativeIconButton(
            glyph: AppBoxKitGlyphs.add,
            onPressed: () => _toast(context, 'Attach'),
          ),
        ],
        trailing: [
          AppBoxKitNativeIconButton(
            glyph: AppBoxKitGlyphs.mic,
            onPressed: () => _toast(context, 'Voice'),
          ),
        ],
        onSubmitted: (text) => _toast(context, 'Sent: $text'),
      ),
    );
  }
}
