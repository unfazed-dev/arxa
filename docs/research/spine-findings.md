# appbox spine — measured findings

Scored against `appbox-spine-rubric.md`, which was written first. Every number
below has the command that produced it. Where a pre-compaction claim of mine was
wrong, the correction is stated rather than quietly replaced.

## Corrections to what I told you earlier

| I said | Actually |
|---|---|
| flutter-crew invalidates via `golden.sha256` | `golden.sha256` is a **test fixture** (snapshot golden). The real mechanism is `stages/gen_freshness.py` — regenerate into a temp copy, diff against the committed layer. Stronger than a hash. |
| flutter-crew is "22,738 LOC / 22 tests" | 22,738 LOC in `stages/` — correct. But "22 tests" undercounts by 28×: **628 assertions** (515 in stage `--self-test` blocks, 113 in `test/`). Advisor was right that test *functions* are the wrong unit. |
| asko is "12 stages, all green" | Ledger is **10 green, 2 stale, 3 planned**. The 12-green number comes from `smoke.py` S5, which rebuilds from scratch. |
| stacked_kit has "no invalidation" | Confirmed — this one held up. |

## Suite results (all run, none inferred)

| repo | command | result |
|---|---|---|
| flutter-crew | `pytest` (repo root) | **BROKEN** — 5 collection errors, interrupted |
| flutter-crew | `pytest test stages` | 44 passed, 1 xfailed, 2.15s |
| asko | `orchestrate.py status` | 10 green · 2 stale · 3 planned |
| asko | `smoke.py` | **5/7** |
| stacked_kit | `test_gates.sh` | 83/83 |
| stacked_kit | `test_memory.sh` | 33/33 |
| stacked_kit | `pipeline.sh selftest` | 105/105 |

`pytest` at flutter-crew's root fails only because of an **untracked** `test.bak/`
(0 tracked files) colliding on module basenames. It would not ship broken — but
the working copy is broken today, which is how "22 tests" got believed.

asko's two smoke failures are load-bearing:
- **S6 genericity: FAIL** — 4 design literals in pipeline code. asko's pipeline
  still leaks the app it was built for. It is not yet a generic tool.
- **tree-clean: FAIL** — 5 tracked files dirty after the suite. The suite mutates
  its own repo.

## D2 — the mutation experiment (the reason for this whole exercise)

asko's `dep_hash` (`orchestrate.py:89`) keys on `path:size:mtime_ns`. Reimplemented
verbatim and probed:

| experiment | result |
|---|---|
| E1 content changed | invalidates — **correct** |
| E2 same bytes rewritten (what `git clone`/`checkout`/`rsync` does) | **false invalidation** — every stage rebuilds on a fresh clone |
| E3 content changed, mtime restored (`rsync -t`, `touch -r`) | **STALE GREEN** — the pipeline skips a changed input |
| E4 same content, different checkout path | hash differs — the ledger is **not portable between machines** |

E3 is the precise failure a freshness gate exists to prevent. asko's own
`output/app/SETUP.md:90` already flags "mtime-based `dep_hash`".

**But** asko's `smoke.py` S3 (staleness propagation) and S4 (gate integrity under
fault injection) both pass — so the mechanism does work on the happy path, and
asko is the only one of the three that **fault-injects its own gates**. That
adversarial habit is worth more than the hash function it is testing.

**Port the ledger shape. Replace the hash with content hashing.** ~6 lines.

flutter-crew's `gen_freshness.py` avoids the whole class of bug by not hashing at
all: it re-runs `build_runner` into a temp copy and diffs the materialised
artifacts. It cannot be fooled by mtime because it never reads mtime. Its docstring
names the real incident it closes (atlet booting past its splash because a
committed `app.router.dart` had drifted from source).

## D2, the other way round — probing the mechanism I *accepted*

I first probed asko's `dep_hash` adversarially and accepted flutter-crew's
`gen_freshness` from a docstring. That asymmetry is not defensible when the spine
call rests on the latter, so it was run to the same standard.

| check | result |
|---|---|
| `gen_freshness.py --self-test` | **PASS** |
| clean fixture copy | `FAIL — 6 files checked, 1 drifted`, names the file, prints the exact regenerate command |
| after a hand-edit to `app.locator.dart` | committed hash moves `181d96d0 → c67ed8a2`; the **fresh** side stays `5e11966e` |
| exit code on drift | **1** |

The moving-committed / stable-fresh pair is the proof it genuinely re-derives rather
than comparing a stored value to itself. The mechanism holds.

**Two defects found while doing it:**

1. **flutter-crew's own shipped fixture is drifted.** Running the gate against the
   untouched `test/fixtures/atlet/.blueprint/design-v2/target` exits 1. The gate is
   evidently not run against its own fixture in CI.
2. **10 of 32 stages have no `--self-test`:** `arch_guard`, `detect_crew_project`,
   `detect_stack`, `emit`, `extract_tokens`, `guard`, `run_pipeline`, `snapshot_test`,
   `test_gate`, `viz`. `run_pipeline.py` is the orchestrator and `emit.py` is an
   emitter — the two places an untested module hurts most. **Three of them
   (`extract_tokens`, `guard`, `run_pipeline`) are inside the 7 modules asko
   vendored.** `generate_view.py` *does* self-test, so step 5's risk is contained.

Neither overturns the call. Both are inherited debt appbox must close rather than
copy, and they revise D3 for flutter-crew downward from "628 assertions" to "628
assertions covering 22 of 32 stages."

## What the web research actually supports

Named as an input in the request, so stated explicitly rather than left implicit —
including where it does *not* support what I earlier claimed.

| finding | where it lands |
|---|---|
| **Content-addressed stores** (Nix, Guix) key on content, never on timestamps | This is precisely the `dep_hash` correction. The E3 stale-green defect is the exact failure mode content addressing exists to eliminate. Not a stylistic preference — a solved problem being re-solved wrongly. |
| **Hermeticity = no network during build**, not artifacts committed to VCS | Corrects an over-read of mine from earlier in this work: these findings do **not** support committing render evidence to git. They support the `none` mode and network-free stage execution. |
| **SARIF (OASIS)** — `partialFingerprints` for stable finding identity, provenance block | §5. The reason not to invent a findings schema: fingerprints give "same failure as last run?" for free, which is what the UI's timeline needs. |
| **Evaluator–optimizer loop** (gate produces critique, generator consumes it) | Already the FSM's shape, and asko's `orchestrate.py` cites it by name in its header. The discipline it implies — the evaluator never authors what it grades — is the rule the `--fix-cmd` seam exists to enforce. |
| **Durable execution**: run state outside the process, resumable | `run.json` + `history.jsonl` at the root, not in the output. Why closing the desktop app cannot lose a run. |

## Scorecard

0 absent · 1 manual/unenforced · 2 enforced with a known gap · 3 enforced and a test fails when it regresses

| | flutter-crew | asko | stacked_kit |
|---|---|---|---|
| **D1 determinism** | **3** — 0 model calls in 32/32 stages | **3** — S1: 12 stages, 0 non-deterministic | **1** — tooling is deterministic, but the model authors *every Dart surface* via `--fix-cmd` |
| **D2 invalidation** | **3** — regenerate-and-diff, self-tested | **2** — works, but mtime-keyed (E2/E3/E4) | **0** — none |
| **D3 verification depth** | **2** — 628 assertions / 25k LOC | **2** — 7 smoke properties incl. fault injection | **3** — 221 suite assertions + adversarial twins per gate |
| **D4 portability** | **1** — 27 files w/ `/Volumes/`, incl. `stages/parity.py` | **0** — `orchestrate.py:45` hard-codes another repo's absolute path as a default | **3** — **0 absolute paths in 1,244 tracked files** |
| **D5 harness agnosticism** | **3** — ships `.claude-plugin` *and* `.zcode-plugin` | **1** — CLI only, assumes `CREW_HOME` | **2** — skills are harness-portable, install.sh symlinks |
| **D6 observability** | **3** — **29/32** stages emit JSON | **2** — ledger + history.jsonl + smoke JSON | **1** — **6/22** gates emit JSON; the rest print |
| **D7 decoupling** | **2** — writes into target's `.blueprint/` | **3** — `input/ work/ output/` at root | **2** — writes `.kit/state/` into the target app |
| **D8 human gates** | **1** — operator commands, no blocking gate | **1** — operator-run freeze acts | **3** — 2 formal gates + `ESC_LIMIT=3` |
**No total is given, deliberately.** The rubric calls D4 "a hard filter, not a
preference" — averaging it with seven peers as one-eighth contradicts that, and an
unweighted total would read as "flutter-crew 18, stacked_kit 15" while the prose
says the opposite. D4 and D2 are gates; the rest are gradients. Read the rows.

## Do flutter-crew's 22,738 lines emit *stacked MVVM*, or generic Flutter?

This decides whether the emitters are worth anything to you. Measured in `stages/`:

| token | occurrences |
|---|---|
| `ViewModel` | 178 |
| `locator` | 47 |
| `BaseViewModel` | 24 |
| `StackedView` | 14 |
| `StackedApp` | 7 |
| **`ScreenTypeLayout`** | **0** |
| **`ViewModelBuilder`** | **0** |

It emits real stacked MVVM — `generate_view.py:1904` is
`class {Name}View extends StackedView<{Name}ViewModel>`. And it uses a pattern
**stacked_kit does not have**:

```
abstract class {name}ViewModelBase extends BaseViewModel   // regenerated every run, do NOT hand-edit
class {name}ViewModel extends {name}ViewModelBase          // hand-editable
```

That split is what makes deterministic regeneration survive hand edits. stacked_kit's
ViewModels are wholly LLM-authored, which is *why* it has no D2 — there is nothing
to regenerate and diff against. This is the single most portable idea in the corpus.

The two zeros are the gap: flutter-crew emits **no responsive form-factor dispatch**,
which is exactly what stacked_kit's 73 checks demand (`form_factor_files: all 5
present`). So the emitters are a starting point, not a drop-in.

**Three stacked-MVVM emitters exist on this machine** — flutter-crew's
`generate_view.py`, asko's `12-presentation/{emit_presentation,view_generator}.py`,
and stacked_kit's `kit-designer` skill. That triplication *is* the consolidation
opportunity appbox exists to close.

*Update — this is now closed.* The end-to-end run was done on p2's
`train_shell_today_view`; see `appbox-headtohead-train-shell.md`. Summary:

- The chain **does** reach Dart deterministically (`DONE (deterministic, no LLM)`,
  `golden.sha256` emitted). The census inference held.
- Its gates **do** bite: a non-exhaustive classify stand-in was rejected at a 95%
  coverage floor, exit 1.
- Judged by stacked_kit's own `enforce_design`: **flutter-crew 4 of 17 applicable
  checks failed; p2's stacked_kit-built surface passed 73/73.**
- The blocker is not the emitter — it is the **input model**. flutter-crew captures
  composition from JSX components; p2's JSX is branch-matrixed on
  `role × state × params.branch`, so `capture_design` grabbed a conditional subtree
  (the offline banner) and emitted 7 of 112 nodes as if it were the screen.
- Which emitter is the base (open question 2) now has evidence: flutter-crew's
  `generate_view` produces clean, idiomatic Dart with the `ViewModelBase` split —
  but needs form-factor dispatch and the kit vocabulary added, and an **HTML
  capture path**, since `capture_design` is JSX-only.

## The finding that outranks the scorecard

`asko/pipeline/stages/09-ui/vendor/PROVENANCE.md`:

> a vendored, pristine copy of the deterministic (non-LLM) half of the
> flutter-crew UI codegen chain. asko replays it to turn the committed design
> into `work/breakdown.json` without a live model.

**You already made this decision once.** Under real pressure, on a real project,
you picked flutter-crew's deterministic core as the thing to replay — 7 modules,
stdlib-only, layout mirrored so no path patching was needed. That is a stronger
signal than any score here.

One defect in it: vendored from commit `7a4f08d` with the **working tree dirty**.
The exact input is unreproducible. appbox must vendor from a clean tag.

## Spine call

Hypothesis "flutter-crew is the spine" — **confirmed for execution, refuted for product.**

It wins the four dimensions that decide whether a pipeline is trustworthy
(D1 determinism, D2 invalidation, D5 harness, D6 observability). It loses the two
that decide whether it is sellable (D4 portability, D8 human gates), and it has
no Flutter/stacked-MVVM component library at all.

stacked_kit loses on execution and wins on product: the only clean repo, the only
formal human gates, the deepest adversarial test corpus, and the 22 kits +
73-check MVVM enforcement that encode your actual domain opinion. That knowledge
is the expensive part and cannot be rebuilt cheaply.

**So the split is not "pick a winner", it is a clean seam:**

- **flutter-crew decides HOW a stage runs** — stage module + `--self-test` + JSON
  emit + regenerate-and-diff freshness. One execution model, not three.
- **stacked_kit decides WHAT is enforced and WHAT is built** — the 22 kits, the
  73 design checks, the two human gates, the adversarial twin discipline.
- **asko contributes the ledger** (`run.json` + `history.jsonl` + fault-injected
  smoke), content-hashed instead of mtime-keyed.
- **factory contributes packaging** — `install.sh`, relative symlinks, one tool
  per directory, pointed at any project.

### Correction: D6 does not require porting the gates

I first wrote that stacked_kit's gates "get ported into flutter-crew's stage
contract." That is wrong, and it contradicts a decision already made during the
grilling: **`KIT_FINDINGS_OUT` sidecars, for all gates**.

Porting 22 tools would mean re-proving 221 assertions and every adversarial twin —
weeks of work to buy a property a sidecar buys in an afternoon. A gate keeps its
logic, its exit code and its stdout, and additionally writes SARIF to
`$KIT_FINDINGS_OUT` when the variable is set. Nothing existing changes behaviour;
the UI gets something to draw. D6 goes 6/22 → 22/22 without touching a single
assertion.

The rule that survives: **flutter-crew's stage contract is the shape new work
takes.** Existing stacked_kit gates are wrapped, not rewritten.
