# Dogfood report — plan 14 (the acceptance test)

**Run:** 2026-07-27. **Executor:** builder agent (Phase B/C/D only — Phase A is
founder-led). **Subject:** D1 = `designs/app-box-app/` (the app-box-designer
producer; `macos` target). **Flutter:** 3.44.0. **Render backend:** `uv` +
playwright + cached Chromium (working). **Baseline:** `HEAD=3402d82`, tree clean,
`lint_conventions.sh` exit 0.

This report records what passed, what was blocked, and — most important — every
place a gate was green over something broken, or a human had to intervene the
plans did not predict. **Evidence first; verdicts honest.**

---

## TL;DR

The **data layer is sound and provably fail-safe**: `structure.json` is
registry-derived and byte-stable; the round-trip, orphan, drift, target-stale and
human-gate smoke tests all pass with the offender named. The freeze gate's
~4× error-inflation bug is fixed (runtime-proven: 1 error across 4 surfaces at 1
width is reported exactly once).

The **pipeline cannot yet ingest D1 end-to-end**, for one root reason: the freeze
gate (plan 04) and the coverage gate's ceremony paths are wired for the
**stacked_kit producer** contract (`surfaces/*.html` + `tokens.json` + four docs),
while D1 is the **app-box-designer htmx producer** (`ui/views/**/*.html` +
`registry.json`). Freeze fails D1 on six shape checks before it ever renders, and
no scaffolder exists to turn D1 into the Flutter `app/` (which is currently the
stacked_kit **showcase app**, not a D1 scaffold). Everything blocked in Phase B/C
traces back to that one producer-shape seam.

---

## 14.9 — gate pass counts (run_all.sh over D1)

`KIT_DESIGN_DIR=designs/app-box-app bash gates/run_all.sh "$(pwd)"` (APP=repo
root so the design dir resolves):

| gate | verdict | evidence |
|---|---|---|
| **freeze** | **FAIL** | 6 shape checks: `tokens.json`, `design-system.md`, `exclusions.json`, `direction-approved.md`, `brand-spec.md` missing; `no surfaces — designs/app-box-app/surfaces/*.html missing` |
| **structure** | **PASS** | `in-sync`; `20 screens / 15 frozen / 5 excluded, 6 tab roots land on a surface`; tracked+committed |
| **scaffold** | **PASS (vacuous)** | `WARN: no …/lib/ui/views — nothing to check (shell structure gate is app-only)` → exit 0. **Green over no scaffolded app — see honest-bar #5.** |
| **coverage** | **FAIL** | macos keychain ceremony: `macos/Runner/DebugProfile.entitlements missing`, `Release.entitlements missing`; `0/15 frozen surface(s) in 0 adopted shell(s) of 1` |
| **review** | **N/A** | `no …/lib/ui/views` |
| **deploy** | **FAIL** | `target: macos` ✓; `deploy.version is not confirmed`; `deploy.account is not confirmed` |

**Totals: 2 passed, 3 failed, 1 N/A.** run_all exit 1.

> Note on APP choice. Gates resolve `KIT_DESIGN_DIR` **relative to `$APP`**, and
> coverage's ceremony paths are **app-root-relative**. D1 lives at the
> **repo root** (`designs/`); the macos entitlements live under `app/macos/`.
> No single `$APP` makes both resolve: at `$APP=app/` the design dir becomes
> `app/designs/app-box-app` (not found); at `$APP=repo-root` the ceremony paths
> miss `app/macos/Runner/`. The entitlements themselves are correct — both
> `app/macos/Runner/{DebugProfile,Release}.entitlements` carry
> `keychain-access-groups`. This is a wiring seam, not a content defect
> (intervention #4).

---

## Phase B — freeze

### 14.5 structure.json is registry-derived — **PASS**

```
$ KIT_DESIGN_DIR=designs/app-box-app python3 tools/emit_structure/emit_structure.py --check
in-sync …/designs/app-box-app/structure.json                          [exit 0]
$ KIT_DESIGN_DIR=designs/app-box-app python3 tools/emit_structure/emit_structure.py
unchanged …/structure.json (write-on-diff: content identical)
  20 screens, 15 with a surface, 5 excluded (surface:null)            [exit 0]
$ git status --porcelain    # empty
```

The emitter joins each declared surface to its viewmodel on the viewmodel's
**exported `surfaceId`** (`emit_structure.py:35,107-112`), not filename
similarity. `tab→shell` is derived from the surface prefix (`:87-91`); `surface:
null` **is** the exclusion, preserved verbatim (`:168-180`). Confirmed
non-filename-inferred by source.

### 14.6 freeze renders D1 at one width (macos → desktop) — **BLOCKED (defect)**

```
$ KIT_DESIGN_DIR=designs/app-box-app bash gates/freeze/freeze.sh --targets macos "$(pwd)"
FAIL: shape: designs/app-box-app/tokens.json missing
FAIL: shape: designs/app-box-app/design-system.md missing
FAIL: shape: designs/app-box-app/exclusions.json missing
FAIL: shape: designs/app-box-app/direction-approved.md missing
FAIL: shape: designs/app-box-app/brand-spec.md missing
  ✓ shape: structure.json
FAIL: shape: no surfaces — designs/app-box-app/surfaces/*.html missing
freeze: FAIL (6 shape check(s))                                       [exit 1]
```

D1 is the app-box-designer htmx producer: surfaces live at
`ui/views/stage_shell/**/*_view.html` (Jinja-extending
`ui/common/base.html`), authored through `models/screens_model/registry.json` +
`app.routes.js`. The freeze gate (plan 04) expects the **stacked_kit producer**:
`surfaces/*.html` standalone + `tokens.json` + `design-system.md` +
`exclusions.json` + `direction-approved.md` + `brand-spec.md` (`freeze.sh:137-
145`). The render pass never runs because shape fails first. **Root cause of all
of 14.6/14.7/14.8 — see honest-bar #1.**

### 14.7 error count is exact (the ~4× inflation bug is fixed) — **PASS (mechanism, runtime-proven)**

Cannot reach render on D1 (shape fails first), so the fix is proven on a
freeze-shape fixture: **one** `console.error` planted in one of **four** surfaces,
rendered at the single macos-derived width (desktop), reported **exactly once**:

```
✓ render: x_shell_a_view.html @ desktop (1280x800) loaded
✓ render: x_shell_b_view.html @ desktop (1280x800) loaded
✓ render: x_shell_c_view.html @ desktop (1280x800) loaded
✓ render: x_shell_d_view.html @ desktop (1280x800) loaded
FAIL: render: console/page error — x_shell_b_view@desktop: THE_ONE_ERROR
  render: 4 surface/viewport render(s) across 1 derived width(s), 1 error(s)   [exit 1]
```

`1 error(s)`, not four. The fix is structural (`freeze.sh:286-296`): the
console/pageerror handler is registered on a **fresh page per (surface,
viewport)**, so it cannot accumulate across surfaces. Also covered by
`gates/freeze/selftest.sh` case "4.3 proof" (selftest: **23 passed, 0 failed**).

---

## Phase C — scaffold + review

### 14.8 scaffold D1 — three layout files/surface for macos — **BLOCKED (no scaffolder)**

There is **no scaffolder tool**. `skills/app-box-scaffolder/` is a README only;
`pipeline.sh`'s scaffold gate delegates to vendored stacked_kit paths
(`skills/kit-scaffolder/scripts/scaffold_gate.sh`,
`tools/vendor/scaffold_coverage/…`). The committed Flutter `app/` is the
**stacked_kit showcase app**, not a scaffold of D1:

- `app/lib/ui/views/.shell-structure.json` declares `selfContained:
  ["showcase_notes_shell"]` — a shell whose directory **does not exist**, so the
  scaffold gate FAILS on `app/` (`manifest names 'showcase_notes_shell' but … does
  not exist (S0)`).
- `find app/lib/ui/views -path '*stage_shell*'` → **nothing**. D1's shell
  (`stage_shell`) is entirely absent from `app/`.

So there is no D1-derived `_view.dart` + `_view.desktop.dart` + `_viewmodel.dart`
set (the expected macos three) to count. The **derivation itself is correct and
self-tested**: `coverage.sh --self-test` proves `--targets macos → desktop only →
THREE files, no empty .mobile/.tablet` (selftest case 6.5/6.6, **all green**).
What is missing is the producer that emits those files from D1.

### 14.10 / D2 (companion) — **BLOCKED**: needs plan 12, not built.

---

## Phase D — the smoke tests that matter

### 14.11 Round-trip — **PASS**

`crud create projects.smoke → emit_structure → crud delete --confirm roundtrip → emit_structure`.

```
baseline registry.json sha: 624dcdb9c50195bbf68a733b5ded0dccbe327815
create  → wrote structure.json (21 screens, 16 with surface)
delete  → wrote structure.json (20 screens, 15 with surface)
final registry.json sha   : 624dcdb9c50195bbf68a733b5ded0dccbe327815   (identical)
git status --porcelain    : (empty — D1 tree byte-identical)
```

### 14.12 Orphan — **PASS** (authored layer; scaffold-layer orphan N/A for D1)

Deleted registry entry `settings.kits` but left its viewmodel pair on disk. Both
owning gates fail and name the offender:

```
$ crud verify designs/app-box-app
FAIL: orphan pair ui/views/stage_shell/settings/kits/ declares surfaceId
  'settings.kits' but no registry entry has that id                 [exit 1]

$ structure gate
FAIL: viewmodel ui/views/stage_shell/settings/kits/kits_viewmodel.js exports
  surfaceId 'settings.kits' but the registry declares no such screen
structure: FAIL (1 check group(s))                                  [exit 1]
```

> The coverage gate's C2 orphan (`the design never froze`) is a **scaffold-layer**
> assertion over `lib/ui/views/`. D1 has no scaffolded layer, so it is N/A here;
> its behavior is proven by `coverage.sh --self-test` (case C2, green). For D1
> the orphan is caught at the authored layer by `structure` + `crud verify`, both
> naming the directory.

### 14.13 Drift — **PASS** (porcelain, not git diff)

Three planted defects, each fails and names the offender:

| defect | result |
|---|---|
| append one space to `structure.json` | `drifted from the authored layer` + `modified — regenerate then commit it (porcelain, not git-diff)` — exit 1 |
| flip one token (`StageShell`→`StageShellX`) | same — exit 1 |
| add `ui/views/stage_shell/ghost/ghost_viewmodel.js` (`surfaceId='projects.ghost'`, undeclared) | `viewmodel …/ghost/ghost_viewmodel.js exports surfaceId 'projects.ghost' but the registry declares no such screen` — exit 1 |

All restored; `git status --porcelain` clean after.

### 14.14 Targets — **PASS** (mechanism; D1 can't reach the approval check)

Cannot mint an approval **on D1** (freeze fails D1 shape, and `--approve` only
stamps after every check passes — `freeze.sh:316-333`). Proven on a passing-shape
fixture instead:

```
freeze.sh --targets macos --approve     → freeze: APPROVED (design/approval.lock stamped)
freeze.sh --targets macos               → ✓ approval.lock valid (targets=macos)
freeze.sh --targets macos,web           → FAIL: approval STALE — targets changed since
                                          approval (approved ['macos']; now ['macos','web'])
                                                                       [exit 1]
```

Adding `web` after approval invalidates the stamp loudly, naming the reason.
Covered by `freeze/selftest.sh` (6.7 proof, 23/0).

### 14.15 Human gates halt, minting nothing — **PASS**

An automated run reaches each human gate and stops; no token is written by any
gate. Live demo of Human Gate 1 (in an isolated `KIT_PIPELINE_STATE_DIR`):

```
pipeline.sh init                         → phase=prototype, humanApproved=False, approvalTokens=<absent>
(simulate automated green gate: prototype.status=passed, humanApproved left False)
pipeline.sh advance                      → FAIL: cannot advance — Human Gate 1 has not approved
                                                                       [exit 1]
after: phase=prototype, humanApproved=False, approvalTokens=<absent — nothing minted]
```

| human gate | owner | automated behaviour |
|---|---|---|
| HG1 design/prototype | `pipeline.sh advance` requires `prototype.humanApproved==true` (`pipeline.sh:370-373`), set **only** by `gate prototype --approve` (`:337`) | advance **halts**, nothing minted (proven above) |
| frozen-design stamp | `freeze.sh` writes `approval.lock` **only** when `--approve` (`:322`); a normal run re-validates but never mints | normal run prints `(approval: no …/approval.lock — run … --approve)` |
| HG2 review | `pipeline.sh done` requires `review.approved==true && !dirty` (`:502`), set **only** by `review approve` (`:406`) | done halts; no gate writes `review.approved` |
| HG3 deploy | `deploy.sh` **reads** `approvalTokens.deploy.{version,account}`; no gate writes them | deploy **FAIL** (`version`/`account` not confirmed) — proven in 14.9 |

---

## The honest bar — green over broken, and the R5 guard

The plan's standing instruction: *if a gate passes while something is broken,
that is the failure.* Findings, ranked by blast radius:

1. **Producer-shape seam (blocks 14.6/14.7/14.8/14.14-on-D1).** The freeze gate
   and coverage's ceremony paths are written for the stacked_kit producer; D1 is
   the htmx producer. Result: freeze **cannot ever pass D1 as authored**, and the
   render/error-count and scaffold checks are unreachable on the real design.
   Until freeze learns the htmx producer shape (or D1 emits the freeze contract),
   D1 is unfreezable through the existing gates. **This is the single blocker for
   Done-when #1.**

2. **`app/` is not D1; no scaffolder.** The Flutter app is the stacked_kit
   showcase app (`showcase_notes_shell`, which doesn't exist as a dir). There is
   no tool that turns D1 → Flutter, so "scaffold D1" and "coverage of D1" have no
   target. Done-when #4 (the macOS app built by app_box) is not yet demonstrable
   on D1.

3. **R5 meta-guard is RED over a passing gate (false negative).**
   `gates/test_gates_can_fail.sh` greps the **delegator file**
   `coverage/selftest.sh` for the literal `NEGATIVE`; coverage's negatives live in
   `coverage.sh`'s embedded `--self-test` (a different file). So the guard reports
   `coverage/selftest.sh has no NEGATIVE case — R5 requires >=1` and exits 1,
   **while `coverage.sh --self-test` passes 10+ negative cases** (6.5, 6.6, 6.8,
   6.3, C1–C3, 4.4). This is the honest-bar defect class **inverted**: a red
   guard over a gate that provably can fail. Coverage is honest; the guard is
   looking in the wrong file.

4. **Design-dir vs app-root wiring.** `KIT_DESIGN_DIR` and the coverage ceremony
   paths are both `$APP`-relative, but D1 sits at the repo root and the macos
   entitlements sit under `app/`. No `$APP` satisfies both. The entitlements'
   *content* is correct (both carry `keychain-access-groups`); the gate just
   can't see them from the same root it sees D1 from.

5. **Scaffold vacuous PASS.** Against repo-root the scaffold gate prints `WARN:
   no lib/ui/views` and exits 0 (app-only by design). In a full `run_all` it
   reads as **PASS while literally nothing is scaffolded** — the textbook
   green-over-broken. Benign only because nothing downstream depends on it here.

6. **Coverage C4 green-on-nothing for a frozen design.** With no shell adopted,
   coverage reports `0/15 frozen surfaces in 0 adopted shells` and **passes**
   (incremental-admission design, `coverage.sh:229-237`, selftest case C4). For a
   frozen design with no scaffold this means coverage passes while zero surfaces
   are scaffolded. By design — but it cannot, on its own, assert the scaffold
   exists for D1.

7. **crud pair layout ≠ D1 convention.** `crud` writes pairs to
   `ui/views/<tab>/<short>/`; D1 authors at `ui/views/<shell>/<tab>/<short>/`.
   Harmless to the round-trip (delete removes exactly what create wrote) but a
   convention drift to resolve before D1 is CRUD-driven end-to-end.

8. **Transient `.kit/` not gitignored + trips lint.** `run_all.sh` writes
   `.kit/state/gates.sarif` (absolute paths), which is neither gitignored nor
   exempt from `lint_conventions.sh` R3 (absolute-path literal). It made lint
   exit 1 until the dirs were removed. Repo-hygiene gap: gate output should be
   gitignored or live under an already-ignored state dir.

---

## Blocked, honestly (not faked)

| item | reason |
|---|---|
| 14.1–14.4 (Phase A design) | founder-led, not the builder's task |
| 14.10 / D2 (companion) | needs plan 12, not built |
| 14.16 credentials | needs a signed+notarised build; no Apple creds |
| 14.17 prototype runtime no-Node | needs plan 09's embedded engine; only the spawn-contract `serve.py` exists |
| 14.18 companion pair/serve/kill | needs plan 12 |
| 14.19 Michelle's clean-machine path | needs a clean machine (env) |
| 14.6 / 14.8 / 14.14-on-D1 | blocked by the producer-shape seam (honest-bar #1), not by env |

---

## Done-when scorecard

| # | criterion | status |
|---|---|---|
| 1 | D1 and D2 both pass every gate | **NOT MET** — D1 fails freeze/coverage/deploy; D2 not built. Root cause: producer-shape seam (#1) + no scaffolder (#2). |
| 2 | Form-factor counts differ correctly (3 vs 4), derived | **MET (at the derivation layer)** — `coverage.sh --self-test` proves macos→3, ios/android→4, derived from targets; never configured per surface. Not yet observable on a real D1/D2 scaffold. |
| 3 | All Phase D smoke tests pass, incl. every negative | **MET** — 14.11/14.12/14.13/14.15 pass with offenders named; 14.7 mechanism + 14.14 mechanism pass (on fixtures, since D1 can't reach them). |
| 4 | app_box's macOS app, built by app_box, runs and drives its pipeline | **NOT MET** — `app/` is the showcase app; no D1-built app exists. |
| 5 | Written report: gate counts, Michelle timing, intervention points | **MET (this report)** — Michelle timing N/A (14.19 blocked: no clean machine). |

---

## Verdict

The gate **machinery** is in good shape: gates fail when they should, name the
offending file, refuse to mint approvals automatically, and the data-layer
invariants (registry-derived structure, drift/orphan/round-trip/stale-target)
hold with byte-level evidence. The freeze error-count fix is real and
runtime-proven.

The **product loop is not yet closed on D1**, because the freeze+coverage gates
were built against a different producer contract than the one `app-box-designer`
emits, and no scaffolder turns D1 into a Flutter app. Closing that seam (and
giving `app/` a real D1 scaffold, or pointing the gates at a D1-shaped design) is
the prerequisite for Done-when #1 and #4. The R5 meta-guard false-negative (#3)
should be fixed alongside, so the honesty net itself is honest.
