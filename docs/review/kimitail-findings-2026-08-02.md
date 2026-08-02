# kimitail findings — 2026-08-02 (post flows/.appbox refactor)

Original standing instruction was "document only"; that was overridden the
same day and the findings were worked. Status per finding below. Three of
the seven turned out to be wrong or imprecise about their own symptom —
those corrections are recorded rather than quietly dropped, because the
mechanism each named was still real.

## Debt (deliberate, tracked)

1. **Project-model migration is partial.** — **OPEN, rescoped.**
   The original framing ("same overlay pattern as design_model") is wrong.
   `intake_model` is one fixture standing in for **three** phases' output:
   intake (`skills/appbox-intake`), story-mapper
   (`skills/appbox-story-mapper`), and moodboarder
   (`skills/appbox-moodboarder`). Only intake has a project-side home.
   `skills/appbox-intake/intake.schema.json:1-78` — the canonical
   elicitation list — has no `personas`, `map`, or `moodboard` field, and
   `docs/plans/architecture.md:895` states **"Intake elicits; it does not
   generate."** So inventing project-side schemas for those would violate
   §22, not fix a gap.
   Classification of the 13 keys, the Slice A fixes, and the Slice B plan
   live in `docs/plans/intake-build-project-aware.md`.
   `build_model`: see the projectStage trap in that plan — **never seed
   fixture json under a project's `build/`**; `project.dart:117-122` treats
   any `.json` there, recursively, as "this project reached `gates`".
2. **`gate_intake` is design-root-bound** — **CLOSED** (`e523c82`).
   `appbox gate intake --project <name>` resolves the flat
   `intake/{answers.json,brief.md,registry.json}` layout that
   `IntakeEngine.emit` writes (`appboxd/lib/intake.dart:747-751`), reusing
   `projectDir`/`shellDir`/`validProjectName` from `project.dart`. No-flag
   behaviour byte-identical. Also fixed a `RangeError` on a bare
   `--project`.
3. **Hot reload misses nested JS modules** — **CLOSED** (`e523c82`), but
   the prescribed fix was impossible. "Version-query every import" cannot
   work: a dynamic `import()` is evaluated once per realm and relative
   specifiers resolve against the base URL's path, so a cache-busting query
   on the entry is dropped by `./services/x.js`. Only a fresh realm empties
   the module map. `JsWorker.reload()` now re-navigates the worker page,
   re-injects, then re-boots — ~850ms per watcher-triggered reload, zero
   per-request cost. A failed reboot was previously discarded silently,
   which is how this stayed invisible; it now writes to stderr.
   Verified empirically: editing `design_facade.js` (a nested import)
   changed the served output with no restart, and reverted cleanly.
4. **Selftest's route-200 sweep needs a populated `~/.appbox`** —
   **CLOSED** (`e523c82`), symptom was false. The selftest already passed
   24/24 with no projects: the null-overlay guard landed in `457d61c`,
   ~7h before this doc was written. The sweep regexed only
   `app.routes.js`, whose 13 GET literals are all `/build/*` and
   `/workspace/*` — **zero** project-dependent routes were in the swept
   set, so "skip project-dependent routes" would have skipped nothing.
   The real defect was the inverse: coverage was **13 of 60** routes and
   the whole `/design` shell was unswept. Fixed by following the
   `routes.*.js` imports; 2xx accepted (trays legitimately answer 204);
   project-backed modules held back with a visible reason when no project
   is mounted. Populated 24/24 → 24/24 with 60 routes swept; empty 24/24
   with 42 swept, 18 held back. Falsifiability proven by breaking a
   `routes.design.js` route and watching the check flip.

## Smells (small, real)

5. **Dead `strip: true` flag** — **CLOSED** (`72c24e9`).
6. **Petal & Stem generic stubs** — **CLOSED**, and it was not all dead
   code. `screen_stub_view.html` 99 → 63 lines.
   - The **body** `elif kind == …` chain was dead as the finding said: all
     10 portalo kinds have partials and `confirmation` exists nowhere.
   - The **header/nav** chain was a **live user-visible bug**. It tested
     `kind in ['home','cart','checkout','confirmation']` *before* testing
     `partial`, so those three surfaces rendered a "Petal & Stem" brand in
     the header while the body correctly rendered portalo's real screen.
     Post-fix they render `Portalo` via `t('app.brand')`, matching
     `portalo.account`'s already-correct behaviour (used as the regression
     control). Only ever visible on non-embed access: both iframe callers
     (`design_facade.js:374`, `design_viewer.html:162`) pass `embed=1`, and
     the header is gated by `{% if not embed %}`.
   - `screen_stub_view.html` is a **shared** renderer — the design lens's
     canvas/proto/thumb iframes use it too (`git show 0faf823`) — so it is
     not evidence-only as the finding implied. Five `embed=1` variants
     re-verified post-deletion.
   - Still open, separate: the Petal & Stem fixture text in
     `files_repository.js:7,38` (`BRIEF_MD`, `STORY_MAP_HTML`), wired into
     build's Files tab via `file_views.js` → `build_facade.js:26`.
12. **`pri.name.undefined` rendered on every project surface row.**
    Introduced and caught within this session, but worth recording as a
    class of bug: `surfaces_view.html` rendered MoSCoW chips unconditionally
    (`t('pri.name.' ~ s.priority)`). Project registry entries carry no
    `priority`/`release` — those are story-mapper's columns — and nunjucks
    `~` stringifies undefined, so the literal text `pri.name.undefined`
    appeared in a chip on all 10 rows. Guarded with `{% if s.priority %}` /
    `{% if s.release %}`. Lesson for the surfaces work generally: when a
    panel switches from the studio fixture to a project artifact, every
    field the template reads must be re-checked for absence, not just the
    ones that changed shape. A sweep of all 13 studio routes for
    `undefined`/`NaN` now comes back clean.
7. **Historical plan doc references dead routes** — **CLOSED** (`72c24e9`).

## New findings (2026-08-02, found while fixing the above)

8. **A selftest check that cannot fail — and cannot simply be patched.**
   `design selftest --negative` reports `proven 24, unproven 1` (exit 1):
   *"fixtures record their seed provenance"* does not fail under its
   mutation. Mechanism: the check (`design_selftest.dart:333-334`) and its
   mutation (`708-713`) share the glob `_fixtures.*\.json$`, which has
   matched **zero files** since `c77e6cf` replaced the old design artifact
   and fixtures were renamed to `*_seed.<locale>.json` (23 JSON files under
   `models/`, none matching). The check passes over an empty set; the
   mutation early-returns on `if (files.isEmpty) return;`. Neither reaches
   an assertion. Reproduced on pristine HEAD, so it predates this work.
   **Repointing the glob is not the fix** — `_generated_from` appears
   nowhere in the artifact, and no seed carries provenance under any other
   key, so a corrected glob turns this check red. The contract is genuinely
   unmet, not merely unchecked. Closing it needs a decision: either the
   seed emitter starts stamping provenance, or the check is deleted as an
   artifact of a retired convention. A generated file with no record of
   what generated it is the thing the check existed to prevent, which
   argues for the former.
11. **A skipped check reads as a pass.** When the JS worker fails to boot,
    `design selftest` emits
    `skip  every GET route answers 200 — render boot failed: …` and still
    reports **`passed 23, failed 0`** — exit 0, nothing red. Reproduced
    deliberately: a duplicate `export const` in `build_facade.js` (a
    SyntaxError) took the whole artifact down, every route was unreachable,
    and the summary line looked green. The only signal was the check count
    silently dropping from 24 to 23, which nothing asserts on.
    A boot failure means the render half of the suite did not run; that
    should FAIL, not skip. Minimum fix: treat `render boot failed` as a
    failure, or assert an expected check count so a vanishing check is
    itself an error. Same family as finding 8 — a check that cannot fail
    and a check that silently doesn't run are the same defect wearing
    different clothes.
10. **Headless Chrome leaks on server shutdown** — **CLOSED.** 16 orphaned
    `appbox-design-worker` Chrome trees (ppid=1, ages 15-23h) were found on
    the dev machine, predating this session.
    Measured per signal rather than assumed — `_ChromeHandle.close()` was
    never the problem:

    | signal | worker after | verdict |
    |---|---|---|
    | SIGTERM | dead | already clean |
    | SIGHUP | **alive** | leaked |
    | SIGKILL | **alive** | leaked |

    Two causes and two fixes:
    - **SIGHUP was unhandled** (closing the terminal orphaned a tree every
      time) and **SIGINT was only wired under `!noWatch`** (so `--no-watch`
      + ^C leaked the same way). Both now always installed and routed to
      `shutdown()`. The sibling-sweep stays SIGINT-only — "^C stops every
      instance serving this artifact" is deliberate and must not spread to
      SIGTERM/SIGHUP.
    - **SIGKILL is uncatchable**, so no handler can close that hole.
      `_ChromeHandle.sweepOrphans()` now runs at boot: it reaps Chromes that
      carry our own `--user-data-dir` prefix under systemTemp **and** have
      been reparented to init, then deletes the profile dirs they held
      (skipping any still claimed by a running Chrome). A live worker is
      always a child of its own Dart server, never of pid 1, so a running
      instance cannot match. Each reap is announced on stderr — a silent
      sweep would be the same invisible-failure trap as findings 8 and 11.

    Verified end to end: SIGHUP now reaps the worker; a SIGKILLed server's
    orphan is reaped by the next boot with
    `design serve: reaped orphaned worker chrome <pid>`; and a concurrently
    running server on another port survived three sweeps untouched.
9. **`gate --all` silently drops `--project`.** `_runAllGates`
   (`appboxd/bin/appbox.dart`) parses only `--app`/`--repo`, so
   `appbox gate --all --project x` ignores the flag without warning.
   Cleanest fix: promote `project` onto `GateContext` so every gate can
   carry it, rather than threading a named param per gate.

## Verified NOT debt (checked, closing)

- `models/screens_model/flows.json` vs `structure.json` flow edges:
  structure.json is GENERATED from the authored layer — not drift.
- The `.dv-zoom` non-wrapping row concern from the pre-flows viewer:
  superseded — the views lens wraps (flex-wrap) and flows rows are the
  intended single-row-per-flow layout.
- `models/screens_model/registry.json` vs `intake/registry.json` is **not**
  a fixture/fallback pair. The first is appbox-studio's own chrome
  registry (used only for `labelOf()` shell labels); the second is the
  target project's screen registry. Same field shape, disjoint domains.
- `files_repository.js`'s `"registry": "models/screens_model/registry.json"`
  is a string literal inside mock file-viewer body text, never resolved as
  a path.
