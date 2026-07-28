---
name: app-box-tester
description: Use when writing/running tests for a appbox-built target — mocktail the repository Ports for unit/TDD, probe-runner for visual + smoke, Patrol for native E2E. Trigger on "test the app", "write tests", "TDD", "visual test", "smoke test", "E2E".
---

# tester — TDD (Ports mocked), visual, smoke, E2E

## Core principle
The architecture contract is statically enforced by `arch_guard` (ADR-0003) — do
NOT re-assert "ViewModel extends BaseViewModel" or "Supabase in infrastructure"
in tests. This role writes FEATURE tests: the behavior, not the contract.

## TDD loop (red-green-refactor)
1. **Red** — write the test first against a repository Port (interface in
   `domain/`), mocking it with **mocktail** (no codegen). It fails (no impl yet).
2. **Green** — builder emits the minimum code to pass (Ports locator-injected;
   Supabase adapter behind the Port).
3. **Refactor** — keep tests green; `arch_guard` stays PASS.

```dart
// unit test mocks the Port, NEVER Supabase directly
class _FakeWorkoutRepo extends Mock implements WorkoutRepository {}
// red:
when(() => repo.all()).thenAnswer((_) async => [sample]);
expect(await viewModel.load(), [sample]);
```

## Layers (cheapest first, escalate scope)
| layer | tool | checks |
|-------|------|--------|
| unit | `flutter_test` + **mocktail** | VM logic, Port contracts (Ports mocked) |
| widget | `flutter_test` | a View renders given a VM state |
| smoke | **probe-runner** (`tools/vendor/probe-runner`, Flutter target) | app boots, first screen renders, no crash |
| visual | **probe-runner** (`tools/vendor/probe-runner`, screencapture) | pixel diff vs the source `design/*.html` |
| E2E | **Patrol** (native) | real taps/scrolls across screens on ios/android |

## Rules
- Tests are **extension points** (factory emits once; operator owns). The
  contract is `arch_guard`'s job — don't duplicate it.
- Mock the **Port**, never Supabase — keeps tests infrastructure-free (ADR-0003).
- Freeze the suite into `.blueprint/<source>/test/` → replayable (reproducibility).

## Output
- A passing suite (unit→widget→smoke→visual→E2E) + the freeze. The reviewer gates on it.
