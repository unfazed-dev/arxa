/// arxa_kit_state — a pure-Dart async state vocabulary for arxa_kit apps.
///
/// A sealed [ArxaKitState] (idle/pending/loading/success/error) with when/map
/// combinators, a [ArxaKitStateNotifier] (current value + broadcast stream) with a
/// guarded [ArxaKitStateNotifier.track] helper, and a legal-transition matrix
/// ([ArxaKitStateTransition]). Zero Flutter dependency.
///
/// This is the state vocabulary the other kits' ports are intended to return.
/// The v0 kits already shipped with their own typed results; unifying them onto
/// [ArxaKitState] is a documented later phase — there are no cross-kit imports now.
///
/// See `arxa_kit_testing.dart` for the state-sequence recorder and scripted notifier.
library;

export 'persistence/arxa_kit_state_persistence.dart';
export 'retry/arxa_kit_retry_policy.dart';
export 'state/arxa_kit_failure.dart';
export 'state/arxa_kit_state.dart';
export 'state/arxa_kit_state_notifier.dart';
export 'state/arxa_kit_state_transition.dart';
