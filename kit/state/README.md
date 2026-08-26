# arxa_kit_state

Pure-Dart async **state vocabulary** for `arxa_kit` apps — a sealed
`ArxaKitState<T>` (idle / pending / loading / success / error), a
`ArxaKitStateNotifier<T>` (current value + broadcast stream) with a guarded
`track` helper, and a legal-transition matrix. **Zero Flutter dependency.**

## Why

The other kits' ports each shipped v0 with their own typed result shapes. This
package is the *intended* common vocabulary those ports converge on — but that
unification is a **documented later phase**. There are **no cross-kit imports
now**; `arxa_kit_state` depends on nothing but `dart:async` and `meta`.

## The state vocabulary

```dart
sealed class ArxaKitState<T> {}
final class ArxaKitIdle<T>    extends ArxaKitState<T> {}
final class ArxaKitPending<T> extends ArxaKitState<T> {}
final class ArxaKitLoading<T> extends ArxaKitState<T> { final double? progress; }
final class ArxaKitSuccess<T> extends ArxaKitState<T> { final T data; }
final class ArxaKitError<T>   extends ArxaKitState<T> { final ArxaKitFailure failure; }
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

## ArxaKitStateNotifier

Current value plus a broadcast stream — no Flutter, no rxdart.

```dart
final notifier = ArxaKitStateNotifier<Profile>();

// Drives loading -> success/error and returns the value (or null on error):
await notifier.track(repository.loadProfile());

notifier.stream.listen((state) => /* rebuild */);
notifier.state;          // synchronous current value
notifier.reset();        // back to ArxaKitIdle
notifier.dispose();
```

### Transition guard

`emit` checks the target against `ArxaKitStateTransition`'s legal matrix. A
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

`ArxaKitError` carries a `ArxaKitFailure { code, message, cause?, stackTrace? }`.
`code` is the stable i18n key (see `ArxaKitFailureCode`); `message` is the
fallback. `ArxaKitFailure.from(error)` normalizes any thrown object.

## Testing

`package:arxa_kit_state/arxa_kit_testing.dart` provides:

- **`ArxaKitStateRecorder<T>`** — subscribes to a notifier and records the emitted
  sequence for `expect(recorder.states, [...])` (leans on value equality).
- **`ArxaKitScriptedStateNotifier<T>`** — bypasses the guard so tests can push
  illegal or repeated sequences via `script` / `scriptAll`.

```dart
final notifier = ArxaKitStateNotifier<int>();
final recorder = ArxaKitStateRecorder<int>(notifier);
await notifier.track(Future.value(42));
await Future<void>.delayed(Duration.zero); // drain the broadcast queue
expect(recorder.states, const [ArxaKitIdle<int>(), ArxaKitLoading<int>(), ArxaKitSuccess<int>(42)]);
```

## Roadmap (file stubs)

- **`ArxaKitStatePersistence`** (`persistence/`) — hydrate the last terminal state
  across launches. Port defined; snapshot-backed implementation is scheduled.
- **`ArxaKitRetryPolicy`** (`retry/`) — backoff/attempt policy. Value object and
  delay curve are testable now; `track` integration is scheduled.
