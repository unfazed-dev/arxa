# coverage

The SCAFFOLD COVERAGE gate (vendored from `scaffold_coverage_gate.sh`, plan 03).
The seam nothing crossed: freeze guarantees the design's surface map; scaffold
validates shell shape; **neither compares the two**. This gate does — every
frozen surface of an adopted shell must be scaffolded with the target-derived
form-factor set. Findings route through `gates/_common/sarif.sh`.

## Asserts

- **C1 coverage** — every frozen surface of an adopted shell is mapped and its
  dir carries the full form-factor set (`config/app-box.config.json` viewports →
  `mobile/tablet/desktop` + viewmodel).
- **C2 orphans** — a real surface dir not mapped is a view the design never asked for.
- **C3 undeclared** — a shell with real surface dirs must be in `selfContained`
  (closes the un-adopt escape hatch).
- **C4 progress** — unadopted shells are REPORTED with counts, never silent.

## 4.4 — missing input fails loudly

A gate that cannot find its input **must fail**. Missing `structure.json` used to
print `coverage N/A` and exit 0 — a silent pass on missing design state. It now
exits 1, naming the missing input.

## Run

```sh
coverage.sh [app-root]                     # 0 pass / 1 FAIL / 2 env
KIT_DESIGN_DIR=design/new coverage.sh
bash coverage/selftest.sh                  # R5: happy + NEGATIVE cases (incl. 4.4)
```
