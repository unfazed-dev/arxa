// Retired: this file's Listener-based app-wide dismissal was replaced by the
// per-input default (ArxaKitInputTapBehavior) after the re-tap regression —
// a raw pointer-down listener cannot tell an outside tap from a re-tap on the
// focused field itself, so the keyboard dropped mid-tap. The symbols keep
// their old import path so hosts and the scaffolder contract stay source-
// compatible; the canonical home is now arxa_kit_input_tap_behavior.dart.
import 'arxa_kit_input_tap_behavior.dart' show ArxaKitInputTapBehavior;
export 'arxa_kit_input_tap_behavior.dart'
    show
        ArxaKitInputTapBehavior,
        abxInputTapGroupId,
        arxaKitDismissKeyboard,
        ArxaKitKeyboardX;

/// Source-compat alias: the retired app-wide widget's name now routes to the
/// per-input default. Wrapping a whole app still "works" (the region wraps
/// everything, every tap is inside) — but it is pointless now: each kit input
/// already carries [ArxaKitInputTapBehavior]. Kept only so old imports and
/// the scaffolder's showcase contract keep compiling during migration.
@Deprecated(
    'Use ArxaKitInputTapBehavior per input; app-wide wrapping is retired')
typedef ArxaKitDismissKeyboard = ArxaKitInputTapBehavior;
