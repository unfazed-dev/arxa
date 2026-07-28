# gates

Every gate is isolated, self-tested, and **provably able to fail** (R5). One
folder per gate; a gate never imports a sibling gate (R4).

## Shape (R4)

```
gates/<name>/
  <name>.sh | .py | .dart     reads state + files, asserts, exits 0 or 1
  selftest.sh                 happy path AND at least one NEGATIVE case
  README.md                   what it asserts, and what it deliberately does not
```

- **One folder per gate.** A gate reads state/files, asserts, and exits `0`
  (pass), `1` (FAIL) or `2` (env / not-applicable). It never calls another gate
  and never imports from a sibling gate folder.
- **Shared logic lives in `_common/` only.** `state_reader.sh`, `sarif.sh`,
  `porcelain_diff.sh`, `report.sh`. If two gates need the same logic it moves
  here — it does not travel sideways.

## The gates

| folder | asserts |
|---|---|
| `intake/` | every registry surface traces to an intake answer and vice versa — no orphans either way (plan 10.6) |
| `freeze/` | the 6 frozen inputs are present and every surface renders clean at every active viewport |
| `structure/` | `structure.json` resolves, is in sync with the authored registry, no orphans either way |
| `scaffold/` | shell/widget/overlay boundaries (self-contained shells, services placement, peer registration) |
| `coverage/` | every frozen surface of an adopted shell is scaffolded with the target-derived form-factor set |
| `review/` | the design judge — pure-Dart static analyzer over the scaffolded views |
| `native_deps/` | every plugin dependency is packaged for each declared target's toolchain — today, Swift Package Manager on Apple platforms |
| `deploy/` | build target + version + releasing account are confirmed in pipeline state |

## R5 — every gate must be able to fail

Each gate's `selftest.sh` includes a `# NEGATIVE:` block: plant a specific
defect, assert the gate exits `1` **and** names the offending file. A selftest
that proves only the happy path is rejected at review. Assert regenerated output
with `git status --porcelain`, never `git diff --exit-code`.

## SARIF — one transport (plan 04.2)

Every gate routes its findings through `gates/_common/sarif.sh` so the GUI, the
companion and a CI log share one machine contract. Bash gates source it and call
`sarif_result`; the review gate emits JSON which `run_all.sh` routes through the
same emitter. Human-readable output stays in each gate.

## Orchestration

- **`run_all.sh`** runs every gate in dependency order
  (`freeze → structure → scaffold → coverage → review → deploy`), aggregates the
  per-gate SARIF into one document (`GATES_SARIF_OUT`, default
  `<app>/.kit/state/gates.sarif`), and exits non-zero if any gate failed. It
  orchestrates; it contains no assertions of its own. Env: `APPBOX_STATE`,
  `KIT_DESIGN_DIR`, `FREEZE_VIEWPORTS`.
- **`test_gates_can_fail.sh`** is the R5 guard: for every gate folder it asserts
  a selftest exists **and** contains at least one `NEGATIVE` case, then runs
  each. Delete a negative case from any gate and this meta-test fails.
