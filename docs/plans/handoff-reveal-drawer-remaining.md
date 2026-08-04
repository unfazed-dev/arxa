# Handoff — screen reveal-drawer plan, remaining work

**DONE 2026-08-05 — all five increments merged.** Inc 4 (Logic tab) merged as
`a3f0f97` (probes 17/17 incl. `widget-logic`); Inc 5 (container removal +
cleanup) merged as `7babc79` (probes 15/15 — explode/screen-composer deleted,
coverage migrated to flowwalk/shell-chrome/widget-tools/reveal-drawer).
Plan-level definition of done below is met; this file is kept as the record.
Follow-ups handed to the operator: real `~/.appbox/projects/portalo` carries a
stale qps-ploc fixture (regenerate via `design pseudolocalize` + the project's
generator, as was done for the Inc-5 disposable); stray `inc5-portalo` project
dir in `~/.appbox/projects/` is leftover clutter, safe to remove.

Session date: 2026-08-04. Repo: `/Volumes/developer_ssd/Developer/totem_labs/app-box`, branch `master`.

## Authority

- Plan (SSOT): `docs/plans/screen-reveal-drawer-composer-tools-logic.md` (committed `5aa7469`). Read it fully — D1–D9 locked decisions + a11y defaults are binding.
- Superseded: the "Components-container 2-col split" section of `docs/plans/widget-editing-autolayout-and-manager.md` (note is inline). The components container itself is slated for REMOVAL in Increment 5 — do not invest in it.

## State at handoff

| Increment | Status | Evidence |
|---|---|---|
| 1 — composer fragment `field(c, scope='')` | merged (`d9b8bd9`, merge `9f95f2b`) | served DOM byte-identical; probes 14/14 |
| 2 — reveal-drawer shell + Composer tab | merged (`abc0bbc`, master HEAD = fast-forward) | probes 15/15 (incl new `probe_reveal_drawer.dart`); analyze/ADR-0002 lint/W1–W6/check-wiring clean |
| 3 — selection + Tools tab | merged (`3128fe2`, merge `cf30ee7`) | probes 16/16 (incl new `probe_widget_tools.dart`); analyze/lint/wiring clean; selection reconciled with existing `d.widgetSel`/`POST /design/widget/select`; copy writes via new `POST /design/widget/text` → `facade.setWidgetCopy` |
| 4 — Logic tab | not started | — |
| 5 — remove components container + cleanup | not started | — |

Task tracker: task #4 (in_progress) tracks the whole plan.

## Landed surfaces the next increments build on

- Composer macro: `designs/appbox-studio/ui/views/main_shell/shared/widgets/composer.html` — `field(c, scope='')`, id suffix `--<scope>`, `data-composer-scope`, `c.swapTarget` (default `#panels`), `c.undoHref`/`c.redoHref`.
- Drawer: `.dv-reveal` wrapper per views-lens screen card in `shared/widgets/design_viewer.html`; aside `#dv-drawer-<slug>`; 3 tabs (Composer live; Tools/Logic placeholders); scope `drawer-<slug>`.
- Behavior island: `skills/appbox-designer/runtime/vendor/reveal.js` (ESC close, focus in/out, `aria-expanded`).
- Server: `GET /design/drawer/:screen` (state/tab in session `d.drawer`); drawer swaps answer `#drawerSwap` fragment; drawer undo/redo carry `?drawer=<id>` (+ `?screen=<id>` on send).
- Probes: `appboxd/lib/probes/studio/probe_reveal_drawer.dart` + `registry.dart`.

## Remaining increments (execute in order, one worktree subagent each)

### Inc 4 — Logic tab (NEXT — no agent running; session ended after inc 3 merge)
Deterministic graph from repo facts (function/facade/repository wiring for the selected widget/screen), technical + plain-human rendering, honest "unknown" for what static analysis can't prove — no LLM guessing, no fabricated edges. Templates only; deterministic template/probe pair. Probe: known widget → expected edges; unknown case renders the honest-unknown state.

### Inc 5 — remove components container + cleanup
Delete the components container UI and its now-dead routes/templates/CSS/l10n keys (all three arbs); migrate anything still referenced. Sweep probes for container references; add/keep a qps-ploc overflow check on drawer chrome. This is the ONLY increment allowed to delete container code.

## Non-negotiable gates (every increment)

1. `dart analyze` clean; ADR-0002 lint, W1–W6 gate, check-wiring clean.
2. Disposable project serve + `appbox design probe all` — **wait for process exit, read per-probe verdicts; never grep "ALL PASSED"**. Zero new FAILs vs 15/15 baseline; prove any FAIL pre-existing on a clean master disposable copy before more edits.
3. DOM checks via ctx_execute (dual/multi drawer instances ⇒ zero duplicate ids).
4. Kill servers, remove `~/.appbox/projects/portalo-*` disposables; tree clean.
5. l10n: new strings into `app_en.arb` + `app_pl.arb` + `app_qps-ploc.arb` (pseudolocale convention; hand-insert values, revert regenerator churn).
6. Commits: single line, no author mentions.

## Orchestration conventions

- One increment per worktree subagent (`isolation: worktree`); merge its commit into master from the main checkout after vetting, then `git worktree remove --force` + `git branch -D`.
- Context-mode routing is mandatory in prompts: no curl/wget/WebFetch; ctx_execute/ctx_batch_execute for big output; Bash only for git/short commands.
- Vet reports as leads, not facts: check `git show --stat <hash>`, confirm scope matches the increment, confirm probe counts, then merge.
- Known environment quirks: advisor `consult.sh` may be absent in worktrees (proceed without); selftest shows 3 pre-existing scaffold-route 500s and a `widget/clear` mutations-posted note — pre-existing on master, not regressions.

## Definition of done (plan level)

Container gone; every designed screen has the reveal-drawer with Composer / Tools / Logic tabs per D1–D9; probe suite green with the extended reveal-drawer coverage; task #4 completed; this handoff file deleted or marked done.
