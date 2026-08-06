/// appbox_kit_state — a pure-Dart async state vocabulary for appbox_kit apps.
///
/// A sealed [AppBoxKitState] (idle/pending/loading/success/error) with when/map
/// combinators, a [AppBoxKitStateNotifier] (current value + broadcast stream) with a
/// guarded [AppBoxKitStateNotifier.track] helper, and a legal-transition matrix
/// ([AppBoxKitStateTransition]). Zero Flutter dependency.
///
/// This is the state vocabulary the other kits' ports are intended to return.
/// The v0 kits already shipped with their own typed results; unifying them onto
/// [AppBoxKitState] is a documented later phase — there are no cross-kit imports now.
///
/// See `appbox_kit_testing.dart` for the state-sequence recorder and scripted notifier.
library;

export 'persistence/appbox_kit_state_persistence.dart';
export 'retry/appbox_kit_retry_policy.dart';
export 'state/appbox_kit_failure.dart';
export 'state/appbox_kit_state.dart';
export 'state/appbox_kit_state_notifier.dart';
export 'state/appbox_kit_state_transition.dart';
