# appbox_kit_state

Pure-Dart async **state vocabulary** for `appbox_kit` apps — a sealed
`KitState<T>` (idle / pending / loading / success / error), a
`KitStateNotifier<T>` (current value + broadcast stream) with a guarded
`track` helper, and a legal-transition matrix. **Zero Flutter dependency.**

## Why

The other kits' ports each shipped v0 with their own typed result shapes. This
package is the *intended* common vocabulary those ports converge on — but that
unification is a **documented later phase**. There are **no cross-kit imports
now**; `appbox_kit_state` depends on nothing but `dart:async` and `meta`.

## The state vocabulary

```dart
sealed class KitState<T> {}
final class KitIdle<T>    extends KitState<T> {}
final class KitPending<T> extends KitState<T> {}
final class KitLoading<T> extends KitState<T> { final double? progress; }
final class KitSuccess<T> extends KitState<T> { final T data; }
final class KitError<T>   extends KitState<T> { final KitFailure failure; }
```

Every case implements **value equality**, so state sequences compare directly
in tests. Fold with pattern matching or the combinators:

```dart
final label = state.when(
  idle:    () => 'Idle',
  pending: () => 'Queued',
  loading: (progress) => 'Loading ${progress ?? 0}',
  success: (data) => 'Got $data',
  error:   (failure) => failure.message,
);
```

`when`/`maybeWhen` fold over payloads; `map`/`maybeMap` fold over the case
objects. Convenience: `isBusy`, `isSuccess`, `dataOrNull`, `failureOrNull`.

## KitStateNotifier

Current value plus a broadcast stream — no Flutter, no rxdart.

```dart
final notifier = KitStateNotifier<Profile>();

// Drives loading -> success/error and returns the value (or null on error):
await notifier.track(repository.loadProfile());

notifier.stream.listen((state) => /* rebuild */);
notifier.state;          // synchronous current value
notifier.reset();        // back to KitIdle
notifier.dispose();
```

### Transition guard

`emit` checks the target against `KitStateTransition`'s legal matrix. A
transition **outside** the matrix (e.g. `idle → success` without passing
through a busy state) trips an **assertion in debug** but is still applied, so
release builds never crash on an unexpected sequence. The matrix:

| from ↓ / to → | idle | pending | loading | success | error |
|---------------|:----:|:-------:|:-------:|:-------:|:-----:|
| **idle**      |  ✓   |    ✓    |    ✓    |         |       |
| **pending**   |  ✓   |    ✓    |    ✓    |    ✓    |   ✓   |
| **loading**   |  ✓   |         |    ✓    |    ✓    |   ✓   |
| **success**   |  ✓   |    ✓    |    ✓    |         |       |
| **error**     |  ✓   |    ✓    |    ✓    |         |       |

Set `guardTransitions: false` to disable the check.

## Failures

`KitError` carries a `KitFailure { code, message, cause?, stackTrace? }`.
`code` is the stable i18n key (see `KitFailureCode`); `message` is the
fallback. `KitFailure.from(error)` normalizes any thrown object.

## Testing

`package:appbox_kit_state/testing.dart` provides:

- **`KitStateRecorder<T>`** — subscribes to a notifier and records the emitted
  sequence for `expect(recorder.states, [...])` (leans on value equality).
- **`KitScriptedStateNotifier<T>`** — bypasses the guard so tests can push
  illegal or repeated sequences via `script` / `scriptAll`.

```dart
final notifier = KitStateNotifier<int>();
final recorder = KitStateRecorder<int>(notifier);
await notifier.track(Future.value(42));
await Future<void>.delayed(Duration.zero); // drain the broadcast queue
expect(recorder.states, const [KitIdle<int>(), KitLoading<int>(), KitSuccess<int>(42)]);
```

## Roadmap (file stubs)

- **`KitStatePersistence`** (`persistence/`) — hydrate the last terminal state
  across launches. Port defined; snapshot-backed implementation is scheduled.
- **`KitRetryPolicy`** (`retry/`) — backoff/attempt policy. Value object and
  delay curve are testable now; `track` integration is scheduled.
