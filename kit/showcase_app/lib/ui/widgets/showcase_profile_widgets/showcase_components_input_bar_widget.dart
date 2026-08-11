/// A widget is a reusable piece of a view — a card, control, or section that
/// composes the kit's primitives and turns the user's taps into callbacks or
/// imperative kit calls. A widget holds no business logic; the view that
/// places it owns the data.
///
/// This is the user interface for the input-bar demo — a docked input bar
/// that owns the bottom dock (the host tab bar yields it while Components is
/// on screen), riding the keyboard via its own viewInsets padding.
///
/// Requirements:
/// 1. [Input bar] — browse-the-components-gallery
/// A docked input bar with attach and voice leading actions and a submit handler.
///
/// Relationships: a self-contained presentational widget — no viewmodel
/// binding; actions toast through the notification service.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/widgets/showcase_profile_widgets/showcase_components_input_bar_widget.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseComponentsInputBarWidget extends StatelessWidget {
  const ShowcaseComponentsInputBarWidget({super.key});

  static void _toast(BuildContext context, String message) =>
      appBoxKitLocator<AppBoxKitNotificationService>().show(message, context: context);

  @override
  Widget build(BuildContext context) {
    // No tab-bar lift: this bar owns the bottom dock while Components is the
    // active tab's top route, and the host tab bar yields the slot
    // (`showcase_application_tab_host_widget.dart`), so there is no longer
    // anything above the screen edge to clear.
    //
    // Deliberately NOT claiming the bar's internal SafeArea handles the home
    // indicator: whether `MediaQuery.padding.bottom` survives the ancestor
    // Scaffolds to reach it is unmeasured (needs a device — see
    // docs/plans/bottom-dock-handoff.md). If the indicator ever crowds the
    // bar, that is the thing to measure first.
    return AppBoxKitNativeInputBar(
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
    );
  }
}
