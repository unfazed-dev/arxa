import 'package:cupertino_native_better/cupertino_native_better.dart'
    show CNTextFieldFocus;
import 'package:flutter/widgets.dart';

/// The kit-wide tap-region group: every kit input's region joins it, so the
/// inputs act as one region ("if any member of a group is hit, onTapOutside is
/// not called for any member" — TapRegion.groupId docs). Tapping one kit input
/// while another holds focus hands focus over field-to-field with no dismissal.
const Object abxInputTapGroupId = 'appbox.kit.inputs';

/// Tap-outside keyboard dismissal as a per-input default — the kit's
/// replacement for the retired app-wide pointer listener.
///
/// ## Why per-input (the re-tap regression)
///
/// The old shape wrapped the whole app in a raw `Listener(onPointerDown:
/// dismiss)`. A pointer-down lands on the *focused field itself* when the user
/// re-taps it to move the caret — the listener unfocused it on finger-down and
/// the keyboard dropped out from under the finger. Listener-based dismissal has
/// no notion of "outside"; the framework's own discriminator for that is the
/// TapRegion registry (`TapRegionSurface`, installed automatically by
/// WidgetsApp/MaterialApp/CupertinoApp — app.dart:1836): a tap is outside only
/// when the hit-test path contains no member of the region group.
///
/// ## Why a kit wrapper and not Flutter's defaults
///
/// Flutter's default `EditableTextTapOutsideIntent` handler does NOT unfocus
/// for touch events on native mobile platforms ("to conform with the platform
/// conventions", editable_text.dart:6781-6796). So a plain `TextField` — and
/// every scaffolded appbox app, which ship no keyboard wiring of their own —
/// has no tap-outside dismissal at all. Appbox wants one by default, on every
/// tier, so the kit owns it here, once, per input.
///
/// ## What it does
///
/// Wraps the input in a grouped [TextFieldTapRegion]. On an outside tap-down
/// it runs the same two-tier dismissal the old listener ran:
/// `FocusManager.instance.primaryFocus?.unfocus()` for Flutter-rendered
/// fields, plus [CNTextFieldFocus.dismiss] for the native tier, whose keyboard
/// no FocusNode can reach. Both are no-ops when nothing is focused.
///
/// A drag that starts outside the region begins with a pointer-down, so it
/// dismisses too — the ScrollViewKeyboardDismissBehavior.onDrag parity the old
/// listener had.
///
/// ## Native tier
///
/// The wrapper region covers the CN platform view as well: iOS platform-view
/// touches are forwarded through Flutter's pointer pipeline and hit test
/// (UiKitView gesture forwarding), so the wrapper's RenderTapRegion is on the
/// hit path via its hit child and field taps classify as inside. No Flutter
/// event is lost and none is invented.
class AppBoxKitInputTapBehavior extends StatelessWidget {
  const AppBoxKitInputTapBehavior({
    super.key,
    required this.child,
    this.dismissOnOutsideTap = true,
  });

  final Widget child;

  /// Set false to suspend the default (a screen driving focus itself).
  final bool dismissOnOutsideTap;

  @override
  Widget build(BuildContext context) {
    if (!dismissOnOutsideTap) return child;
    return TextFieldTapRegion(
      groupId: abxInputTapGroupId,
      onTapOutside: (_) => appBoxKitDismissKeyboard(),
      child: child,
    );
  }
}

/// Dismisses the keyboard on both tiers, whichever is up.
///
/// Safe to call when nothing is focused. Prefer the [BuildContext] extension
/// ([AppBoxKitKeyboardX.dismissKeyboard]) at call sites that have a context;
/// this bare function exists for the ones that do not.
void appBoxKitDismissKeyboard() {
  // Flutter-rendered fields (Material tier, TextFieldM3E, any host TextField).
  final FocusNode? focused = FocusManager.instance.primaryFocus;
  if (focused != null && focused.hasPrimaryFocus) focused.unfocus();
  // Native tier — invisible to the line above; see the class docs.
  CNTextFieldFocus.dismiss();
}

/// Imperative keyboard dismissal from any [BuildContext].
extension AppBoxKitKeyboardX on BuildContext {
  /// Closes the keyboard, whichever tier raised it.
  ///
  /// ```dart
  /// onPressed: () {
  ///   context.dismissKeyboard();
  ///   submit();
  /// }
  /// ```
  void dismissKeyboard() => appBoxKitDismissKeyboard();
}
