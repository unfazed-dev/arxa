---
name: arxa-tester
description: Use when writing/running tests for a arxa-built target — mocktail the repository Ports for unit/TDD, arxa lens (arxa/lib/lens.dart, the probe-runner port) for visual + smoke, Patrol for native E2E. Trigger on "test the app", "write tests", "TDD", "visual test", "smoke test", "E2E".
---

# tester — behavior-TDD (Ports mocked), visual, smoke, E2E

> Per-skill playbook (the folded canon for this phase): [`TESTER_playbook.mdx`](TESTER_playbook.mdx)

## Core principle
**Behavior-TDD is the mandated posture.** The canon is
[behavior-tdd-rules.md](behavior-tdd-rules.md) — test anatomy, streams rules,
banned anti-patterns, mocking/static-state discipline, story-ID traceability.
`arxa gate tests` enforces it (T1 traceability, T2 anti-patterns, T3 green).
The architecture contract is statically enforced by `arch_guard` (ADR-0003) — do
NOT re-assert "ViewModel extends BaseViewModel" or "Supabase in infrastructure"
in tests. This role writes FEATURE tests: the behavior, not the contract.
When the repo's CI is wired ([`arxa-cicd`](../arxa-cicd/SKILL.md)), these
suites run inside it — `scripts/check.sh <area>` wrapping `arxa gate tests`;
CI re-uses this gate, it never re-implements it.

## Pipeline position

Stage 5 of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** `arxa-builder` — filled View/ViewModel bodies, handed over arch_guard-clean (the binding verdict is stage 6's).
- **Downstream:** `arxa-reviewer` — it gates on this stage's output: a passing suite (unit → widget → smoke → visual → E2E) plus the freeze. The visual/smoke layers capture via `arxa-lens`.

## TDD loop (red-first, mandated for new code)
1. **Red** — write the test first, named `<story-id> — <behavior sentence>`
   (story-ID verbatim from `map.json`; kits cite `kit.<package>.<capability>`),
   against a repository Port (interface in `domain/`), mocking it with
   **mocktail** (no codegen) — or a kit fake from `arxa_kit_testing.dart`
   when one exists. It fails (no impl yet).
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
| smoke | **arxa lens** (`arxa/lib/lens.dart` over `cdp.dart`, Flutter target) | app boots, first screen renders, no crash |
| visual | **arxa lens** (golden capture + compare; console/page errors fail) | byte/pixel diff vs the source `design/*.html` golden |
| E2E | **Patrol** (native) | real taps/scrolls across screens on ios/android |

## i18n (when the target carries `l10n/`)
- Probes run **per locale**: en + pl, plus `qps-ploc` (pseudolocale) for layout
  stress — long-accented pseudo-copy is the cheapest truncation/overflow finder.
- Smoke pattern: switch the locale (ArxaKitI18n override), assert the key strings
  re-render in the new locale.
- Goldens: at least one reference surface per locale.

## Rules
- Tests are **extension points** (factory emits once; operator owns). The
  contract is `arch_guard`'s job — don't duplicate it.
- Mock the **Port**, never Supabase — keeps tests infrastructure-free (ADR-0003).
- No mechanical tests (getter/verify-only/stub round-trips/empty stubs) —
  `arxa gate tests` T1/T2 fails them; the canon lists every ban.
- Freeze the suite into `.blueprint/<source>/test/` → replayable (reproducibility).

## Output
- A passing suite (unit→widget→smoke→visual→E2E) + the freeze. The reviewer gates on it.
