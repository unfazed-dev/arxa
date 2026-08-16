// Retired: this file's Listener-based app-wide dismissal was replaced by the
// per-input default (AppBoxKitInputTapBehavior) after the re-tap regression —
// a raw pointer-down listener cannot tell an outside tap from a re-tap on the
// focused field itself, so the keyboard dropped mid-tap. The symbols keep
// their old import path so hosts and the scaffolder contract stay source-
// compatible; the canonical home is now appbox_kit_input_tap_behavior.dart.
import 'appbox_kit_input_tap_behavior.dart' show AppBoxKitInputTapBehavior;
export 'appbox_kit_input_tap_behavior.dart'
    show
        AppBoxKitInputTapBehavior,
        abxInputTapGroupId,
        appBoxKitDismissKeyboard,
        AppBoxKitKeyboardX;

/// Source-compat alias: the retired app-wide widget's name now routes to the
/// per-input default. Wrapping a whole app still "works" (the region wraps
/// everything, every tap is inside) — but it is pointless now: each kit input
/// already carries [AppBoxKitInputTapBehavior]. Kept only so old imports and
/// the scaffolder's showcase contract keep compiling during migration.
@Deprecated(
    'Use AppBoxKitInputTapBehavior per input; app-wide wrapping is retired')
typedef AppBoxKitDismissKeyboard = AppBoxKitInputTapBehavior;
