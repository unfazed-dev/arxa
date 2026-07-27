# 04 — Gates, one folder each

**Goal.** Every gate isolated, self-tested, and provably able to fail.

**Blocks:** 05, 06, 07, 11. **Depends on:** 03.

## The shape (R4)

```
gates/<name>/
  <name>.sh|.py|.dart     reads state + files, asserts, exits 0 or 1
  selftest.sh             happy path AND at least one negative case
  README.md               what it asserts, and what it deliberately does not
```

No gate imports a sibling. Shared logic lives in `gates/_common/` only.

## The gates

| folder | from | asserts |
|---|---|---|
| `freeze/` | vendored `freeze_design.sh` | 6 frozen inputs present, surfaces render clean at **every active ladder width** |
| `structure/` | vendored structure checks | `structure.json` resolves, is in sync with the authored registry, no orphans either way |
| `scaffold/` | vendored `shell_structure_gate.sh` | shell/widget/overlay boundaries |
| `coverage/` | vendored `scaffold_coverage_gate.sh` | every frozen surface scaffolded with **the target-derived form-factor set** |
| `review/` | vendored `enforce_design.dart` | the design judge |
| `deploy/` | plan 11 | target + version + account confirmed |

## Steps

- [ ] **4.1** Split the vendored monolith scripts into the folders above. Where
      one script asserts several things (`freeze_design.sh` carries render *and*
      structure checks), split along the seam and move structure to
      `gates/structure/`.
- [ ] **4.2** Route every gate's findings through `gates/_common/`'s SARIF
      emitter. One transport for the GUI, the companion and a CI log.
      Human-readable output stays, but SARIF is the machine contract.
- [ ] **4.3** **Fix the console-handler accumulation bug** carried in from
      `freeze_design.sh`: `pg.on("console", …)` is registered **inside the loop
      on a shared page**, so handlers accumulate and each error is reported once
      per surface already visited — inflating counts ~4×. Register once, or use
      a fresh page per surface.
- [ ] **4.4** **Fix the silent-skip in coverage**: it currently reports
      `coverage N/A` when design state is missing, and exits 0. A gate that
      cannot find its input must **fail**, not pass quietly.
- [ ] **4.5** Give every gate a `selftest.sh` with **both** cases. The negative
      case plants a specific defect and asserts exit `1` **and** that the output
      names the offending file. A selftest proving only the happy path is
      rejected (R5).
- [ ] **4.6** Write `gates/run_all.sh`: runs each gate in dependency order,
      aggregates SARIF, exits non-zero if any gate failed. It **orchestrates**;
      it contains no assertions of its own.
- [ ] **4.7** Add a meta-test `gates/test_gates_can_fail.sh`: for every folder
      under `gates/`, assert a `selftest` exists and that it contains at least
      one negative case. This is the guard against R5 eroding.

## Done-when

1. Each gate folder has gate + selftest + README.
2. `grep -rn 'import\|source' gates/*/` shows **no** sibling-gate imports.
3. Every selftest passes, and **every one of them fails** when its planted
   defect is present.
4. `gates/test_gates_can_fail.sh` passes, and fails if a negative case is
   deleted from any gate.
5. Console errors are reported **once per surface**, not once per surface
   already visited — assert the exact count on a fixture with one known error.
6. Coverage with missing design state exits `1`, not `0`.
