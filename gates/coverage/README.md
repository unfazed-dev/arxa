# coverage

The SCAFFOLD COVERAGE gate (vendored from `scaffold_coverage_gate.sh`, plan 03).
The seam nothing crossed: freeze guarantees the design's surface map; scaffold
validates shell shape; **neither compares the two**. This gate does — every
frozen surface of an adopted shell must be scaffolded with the **target-derived
form-factor set**, and every active target's **platform ceremonies** must be
present. Findings route through `gates/_common/sarif.sh`.

## Two producer contracts (the producer-shape seam, dogfood P14 finding #1)

Branches on producer shape, detected by `app.routes.js` at the design root
(htmx) vs `surfaces/*.html` + `tokens.json` (stacked_kit):

- **stacked_kit producer** — full scaffold checks (C1–C5 below) over
  `lib/ui/views/.shell-structure.json` + the platform ceremonies.
- **htmx producer (app-box-designer)** — the producer IS the authored layer; its
  Flutter scaffold is downstream of the scaffolder and not yet present. So
  coverage **derives and reports** the target form-factor set the scaffold WILL
  require (e.g. `macos` → desktop → 3 files/surface) and **defers** the
  scaffold/ceremony checks (C4 incremental: a not-yet-scaffolded shell is
  reported, never silently green). Missing `structure.json` still fails loudly
  (4.4). Enforcement of the file set resumes once a scaffold exists.

## Targets drive coverage (plan 06)

`targets` live in **pipeline state** (6.2); gate + golden runs pass them
**explicitly** via `--targets` (6.3). The form-factor set and ceremony set both
**derive** from the targets via `pipeline/state/targets.derivation.json` —
adding a target is a data edit, not a gate edit.

## Asserts

- **C1 coverage** — every frozen surface of an adopted shell is mapped and its
  dir carries **exactly** the derived form-factor set (6.5): `_view.dart` + one
  `_view.<viewport>.dart` per viewport the targets imply + `_viewmodel.dart`.
  `--targets macos` → desktop only → **three** files; `--targets ios,android`
  → mobile+tablet → **four** files. No empty `.mobile`/`.tablet` is ever
  demanded for a target that does not imply it (6.6).
- **C2 orphans** — a real surface dir not mapped is a view the design never asked for.
- **C3 undeclared** — a shell with real surface dirs must be in `selfContained`
  (closes the un-adopt escape hatch).
- **C4 progress** — unadopted shells are REPORTED with counts, never silent.
- **C5 ceremonies (6.8)** — every active target's platform ceremonies (from the
  derivation table) are present: the file exists and, where a key is named, the
  file carries it. Absence fails the gate naming the missing file. Confirmed
  instances: iOS `NSLocalNetworkUsageDescription` / `NSBonjourServices`, macOS
  `keychain-access-groups` in **both** `DebugProfile` and `Release`
  entitlements, PWA `manifest.json` + service worker.

## 4.4 — missing input fails loudly

A gate that cannot find its input **must fail**. Missing `structure.json` used to
print `coverage N/A` and exit 0 — a silent pass on missing design state. It now
exits 1, naming the missing input.

## Run

```sh
coverage.sh --targets macos [app-root]          # 0 pass / 1 FAIL / 2 env
coverage.sh --targets ios,android               # 4-file mobile+tablet set
KIT_DESIGN_DIR=design/new coverage.sh
bash coverage/selftest.sh                       # R5: happy + NEGATIVE cases (incl. 4.4, 6.5–6.8)
```
