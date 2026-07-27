# 03 — Vendor the tooling

**Goal.** app_box owns a working copy of the pipeline and phase skills, with no
dependency on a private repo and no reference to where it came from.

**Blocks:** 04, 11, 13. **Depends on:** 02.

## Why vendor (settled, §17)

The kit stays **private**. A port means re-proving 628 assertions and
maintaining two implementations that drift; a shim needs the buyer to reach a
private repo. Vendoring gives a working copy plus a *detectable* staleness
signal.

## Source

| take | from | lines |
|---|---|---|
| `pipeline.sh` | `stacked_kit/tools/pipeline.sh` | 1,018 |
| gate scripts | `stacked_kit/tools/{freeze_design,shell_structure_gate,scaffold_coverage_gate}.sh` | 308 / 796 / 270 |
| gate suites | `stacked_kit/tools/{test_gates,test_memory}.sh` | 537 / 435 |
| design judge | `stacked_kit/tools/enforce_design.dart` | — |
| emitters | `stacked_kit/tools/{emit_structure,emit_htmx,emit_playground}/` | — |
| registry | `stacked_kit/tools/kit_registry/` | — |
| playbook generator | `stacked_kit/tools/gen_playbook.py` | 232 |
| phase skills | `flutter-crew/skills/{designer,builder,deployer,review,tester,lint}` | — |
| renderer | `flutter-crew/stages/generate_view.py` | 3,931 |
| supporting stages | `flutter-crew/stages/{blueprint,emit,transform_tokens,synthesize,map_all,run_pipeline,init}.py` | — |

## Steps

- [ ] **3.1** Copy each source above into `tools/vendor/<name>/`, preserving its
      internal structure. Do not edit logic in this step — copy first, rename
      second, so a diff against upstream stays meaningful.
- [ ] **3.2** Write `tools/vendor/VENDOR.lock`: one row per vendored item with
      **source repo, path, upstream commit SHA, and copy date**. This file is
      the freshness oracle.
- [ ] **3.3** Write `tools/vendor/check_freshness.sh`: for each row, compare the
      recorded SHA against the upstream repo's current SHA for that path. Report
      drift per item. **It must fail loudly, not warn** — a stale vendor copy
      that reports "ok" is the exact stale-green pattern this project documents.
      Skip cleanly (exit 0, message) when upstream is unreachable — unreachable
      is not the same as fresh, and the message must say so.
- [ ] **3.4** **Rename into app_box's namespace** (R2). Strip `flutter-crew`,
      `crew`, `kimi`, `stacked_kit`-as-tool-identity, `p2` from: filenames,
      function names, CLI help, log strings, config keys, doc links. Skills
      become `app-box-scaffolder`, `app-box-reviewer`, `app-box-builder`,
      `app-box-deployer`.
      **Not stripped:** `stacked_kit` where it names a real runtime dependency
      of a scaffolded app (R2 exception 2).
- [ ] **3.5** Move `pipeline.sh` to `pipeline/pipeline.sh` and repoint every
      path it resolves at `config/app-box.config.json` and `pipeline/state/`.
      **No absolute paths** (R3).
- [ ] **3.6** Replace every hardcoded constant found during 3.4–3.5 with a
      config lookup. Known offenders from the survey: the **390×844 viewport
      literal in `freeze_design.sh` (two places) and `emit_htmx.py`**, and the
      **five-file form-factor list in `scaffold_coverage_gate.sh:144`**.
      Both become config/state reads — plans 06 and 05 depend on it.
- [ ] **3.7** Copy `gen_playbook.py` and its `TODO(prose)` discipline verbatim
      (architecture §20). Generate one playbook per `app-box-*` skill. Copy the
      matching assertion from `test_memory.sh` that the marker count is zero.
- [ ] **3.8** Run every copied suite. Record the pass count in `VENDOR.lock` as
      the baseline. Any later drop is a regression.

## Done-when

1. `tools/vendor/VENDOR.lock` lists every vendored item with a real SHA.
2. `check_freshness.sh` reports **fresh** immediately after copying, and reports
   **stale** when a row's SHA is edited by one character (prove the negative).
3. `tools/lint_conventions.sh` passes — no stripped names remain outside the
   allowed files.
4. Copied suites pass at or above the recorded baseline.
5. `pipeline.sh` runs end to end against a fixture with no absolute paths.

## Do not

- Do not "improve" copied logic in this plan. Copy, rename, de-hardcode. Fixes
  belong to the plan that owns that behaviour (05, 06, 07).
- Do not vendor `test.bak`-style dead copies. If a source has both a live and a
  backup file, take the live one only.
