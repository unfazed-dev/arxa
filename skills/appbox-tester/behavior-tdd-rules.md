# appbox behavior-TDD canon

The rules every appbox-scaffolded app and every kit package test suite follows.
Enforced by `appbox gate tests` (rule IDs **T1/T2/T3** below).

## Test anatomy

- **Name** = `<story-id> — <behavior sentence>`, story-ID verbatim from `map.json`:
  ```dart
  test('notes.folders.create-folder — creates folder and emits it in folder list', ...
  ```
- **Group per VM/service**: one `group('<ViewModelName>', ...)` per unit under
  test. No empty `group()` stubs — a group with no tests is a gate failure (T1).
- **Shape** = plain `flutter_test` group/test in blocTest arrange/act/assert
  order, with `// given / // when / // then` comments marking the three blocks:
  ```dart
  test('notes.folders.create-folder — creates folder and emits it in folder list', () async {
    // given
    final repo = FakeAppBoxKitRepository<Folder>();
    final vm = FolderListViewModel(repository: repo);
    // when
    await vm.createFolder('Work');
    // then
    expect(repo.items.map((f) => f.name), contains('Work'));
  });
  ```
- **NO new BDD packages.** Plain group/test is the canon. `bdd_widget_test` or
  similar is allowed only later, at the widget/acceptance layer, and only if an
  app's operator explicitly opts in.

## Streams rules (BehaviorSubject VMs)

- Register `expectLater` **before** the act — subscribing after the emission
  races and flakes.
- Use `emitsInOrder` with an explicit timeout (~500 ms):
  ```dart
  // given
  final expectation = expectLater(
    vm.foldersStream,
    emitsInOrder([isEmpty, hasLength(1)]).timeout(const Duration(milliseconds: 500)),
  );
  // when
  await vm.createFolder('Work');
  // then
  await expectation;
  ```
- Assert the **full sequence including the seeded value**, or `skip(1)`
  deliberately. Never silently drop the seed.
- **Never `fakeAsync` with BehaviorSubjects** — broadcast/replay semantics
  break under fake clocks. Real async only.
- **No wall-clock sleeps** (`sleep`, fixed `Future.delayed`) — wait on the
  stream or a `pump`, never on time.

## Banned anti-patterns (T2)

Each is a mechanical test: it tests the test, not the behavior.

1. **Getter/constructor/toString tests** — assert nothing a user can observe.
   ```dart
   // bad
   test('constructor sets name', () => expect(Folder('x').name, 'x'));
   // good
   test('notes.folders.create-folder — new folder appears in list', ...
   ```
2. **verify()-only tests** (mock-verification theater) — proves a call
   happened, not that the behavior is right.
   ```dart
   // bad
   await vm.save(); verify(() => repo.save(any()));
   // good — verify at most ONCE per test, only at a trust boundary:
   await vm.enqueueSync(); verify(() => sync.enqueue(any())); // real side effect
   ```
3. **Stub-then-assert-the-stub round-trips** — `when(repo.all).thenReturn([x]);
   expect(repo.all(), [x])` asserts mocktail, not the VM. Drop it.
4. **Stubbing port methods the behavior doesn't touch** — dead arrange code
   hides the real dependency graph. Stub only what the act path calls.
5. **Copying implementation logic to derive expectations** — recomputing the
   expected value with the same formula as the impl makes the test tautological.
   Hard-code the expected literal.
6. **Coverage-chasing** — tests written to hit a line, not to pin a behavior.
   If you can't name the story it protects, delete it.
7. **Empty group() stubs** — scaffolded placeholders. Gate T1 fails on them.

## Mocking rules

- **mocktail only.** No codegen mocks (no Mockito `@GenerateMocks`).
- **Kit fakes beat mocks.** When a package ships fakes in its
  `appbox_kit_testing.dart`, use them — they script real behavior:
  - `ui_library`: `FakeAppBoxKitNotificationService`,
    `FakeAppBoxKitBottomSheetService`, `FakeAppBoxKitNavigationControllerService`
  - `data`: `FakeAppBoxKitRepository<T>`, `FakeAppBoxKitDataFacade`
  - most hardware kits ship scriptable fakes — check before writing a `Mock`.
- Mock the **Port** (`domain/` interface), never the adapter/Supabase directly.

## Static state discipline

```dart
setUpAll(() => AppBoxKitData.initialize());        // once per file
tearDownAll(() => AppBoxKitData.resetForTesting());
setUp(() => appBoxKitLocator.reset());             // per test
```
- Platform-dependent UI tests: `AppBoxKitPlatform.override(...)` in arrange,
  restore in tearDown. Leaked overrides flake every sibling test.

## Traceability

- **Story-ID** (apps): `must`/`should` stories from `map.json` MUST be cited in
  ≥1 test name, **verbatim** (e.g. `notes.folders.create-folder`). `could`/
  `wont` may be cited but aren't gated.
- **Capability-ID** (kits): kit packages have no stories — cite
  `kit.<package>.<capability>` verbatim instead (e.g.
  `test('kit.data.repository — caches reads until invalidated', ...`).
- Gate **T1** enforces citation coverage + no empty stubs/groups;
  **T2** enforces the banned anti-patterns (lint scan);
  **T3** enforces `flutter test` green.

## Layer ladder

| layer | status | tool |
|-------|--------|------|
| VM behavior + service slice | **mandatory** | `flutter_test` + mocktail / kit fakes |
| widget | optional per app | `flutter_test` |
| visual/smoke | optional per app | appbox lens |
| E2E | optional per app | Patrol |

The mandatory layer is what the gate runs. Escalate up the ladder only when the
app's risk justifies it.

## References

- Fowler — GivenWhenThen: https://martinfowler.com/bliki/GivenWhenThen.html
- bloc testing: https://bloclibrary.dev/testing/
- Code with Andrea — async/stream tests: https://codewithandrea.com/articles/flutter-streams-tests/
- dart-lang/test README: https://github.com/dart-lang/test
- mocktail: https://pub.dev/packages/mocktail
