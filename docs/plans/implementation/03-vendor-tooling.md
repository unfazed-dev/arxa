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

- [x] **3.1** Copy each source above into `tools/vendor/<name>/`, preserving its
      internal structure. Do not edit logic in this step — copy first, rename
      second, so a diff against upstream stays meaningful.
- [x] **3.2** Write `tools/vendor/VENDOR.lock`: one row per vendored item with
      **source repo, path, upstream commit SHA, and copy date**. This file is
      the freshness oracle.
- [x] **3.3** Write `tools/vendor/check_freshness.sh`: for each row, compare the
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

## Scoped app-dependency vendoring (O1)

Separate from tooling vendoring above: this is how a **scaffolded app** gets its
kit packages, since the kit is private and no buyer can pull it.

- [ ] **3.9** Add `dependencyMode: "vendored" | "hosted"` to
      `config/app-box.config.json`, defaulting to `vendored`. **Every kit
      reference in a generated `pubspec.yaml` goes through this switch.** No
      code branches on the kit being private — it branches on the config value.
      This is what makes publishing a config flip rather than a rewrite.
- [ ] **3.10** Derive the kit set **per app** from targets + selected
      capabilities. Do not vendor all 21. Reuse the §11 derivation pattern; a
      phone-only app with no maps gets no `stacked_kit_maps`.
- [ ] **3.11** In `vendored` mode, copy the derived kits into
      `<app>/packages/` and emit **path deps between them**. This also removes a
      live fragility: the kit's internal `path: ../sibling` deps currently
      resolve to a SHA, which is why `stacked_kit_data from git is forbidden`
      bites. Vendored path deps are the layout pub actually wants — verify this
      resolves cleanly before proceeding.
- [ ] **3.12** In `hosted` mode, emit ordinary version constraints. Implement it
      now even though it is unusable until the kit is published — an untested
      branch is not a migration path.
- [ ] **3.13** Write `tools/migrate_dependency_mode.sh`: converts an existing app
      between modes — delete `packages/`, rewrite `pubspec.yaml`, re-resolve.
      Idempotent, and guarded on the **desired end state**.
- [ ] **3.14** Record the vendored kit SHA in the app's own lock so
      `check_freshness.sh` covers app deps as well as tooling.

## Done-when

1. `tools/vendor/VENDOR.lock` lists every vendored item with a real SHA.
2. `check_freshness.sh` reports **fresh** immediately after copying, and reports
   **stale** when a row's SHA is edited by one character (prove the negative).
3. `tools/lint_conventions.sh` passes — no stripped names remain outside the
   allowed files.
4. Copied suites pass at or above the recorded baseline.
5. `pipeline.sh` runs end to end against a fixture with no absolute paths.
6. A scaffolded app in `vendored` mode **builds with no network and no access to
   the kit repository** — that is the whole point; prove it on a clean machine.
7. The derived kit set is **smaller than 21** for an app that does not use every
   capability. If it is always 21, the derivation is not working.
8. `migrate_dependency_mode.sh` round-trips: `vendored → hosted → vendored`
   leaves the app byte-identical. (Assert the `hosted` leg against a local
   fixture registry until the kit is published.)

## Do not

- Do not "improve" copied logic in this plan. Copy, rename, de-hardcode. Fixes
  belong to the plan that owns that behaviour (05, 06, 07).
- Do not vendor `test.bak`-style dead copies. If a source has both a live and a
  backup file, take the live one only.
