/// appbox_kit_state — a pure-Dart async state vocabulary for appbox_kit apps.
///
/// A sealed [KitState] (idle/pending/loading/success/error) with when/map
/// combinators, a [KitStateNotifier] (current value + broadcast stream) with a
/// guarded [KitStateNotifier.track] helper, and a legal-transition matrix
/// ([KitStateTransition]). Zero Flutter dependency.
///
/// This is the state vocabulary the other kits' ports are intended to return.
/// The v0 kits already shipped with their own typed results; unifying them onto
/// [KitState] is a documented later phase — there are no cross-kit imports now.
///
/// See `testing.dart` for the state-sequence recorder and scripted notifier.
library;

export 'persistence/kit_state_persistence.dart';
export 'retry/kit_retry_policy.dart';
export 'state/kit_failure.dart';
export 'state/kit_state.dart';
export 'state/kit_state_notifier.dart';
export 'state/kit_state_transition.dart';
