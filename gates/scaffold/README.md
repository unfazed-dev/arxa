# scaffold

The SHELL STRUCTURE gate (vendored from `shell_structure_gate.sh`, plan 03).
Validates the self-contained shell pattern on a host app's `lib/ui/views/` tree.

Contract: `lib/ui/views/.shell-structure.json` `{ "selfContained": […] }`.
Shells not listed are skipped (incremental migration). Absent manifest or empty
list → WARN + exit 0 (no shell has opted in; never false-fails, never
rubber-stamps). Findings route through `gates/_common/sarif.sh`.

## Asserts

- **SN** snackbars/ placement (legal app-level or shell-local, nowhere else)
- **S5** `*_facade.dart` / `*_repository.dart` live under `services/facades/` /
  `services/repositories/` (placement, not existence — runs even with no manifest)
- **S8** peer-service registration (a registered kit service's `locator<Y>()`
  peers are also registered)
- **S10** overlay ownership by enum reference (a sole-consumer overlay belongs in
  its shell)
- **S0–S4** manifest shape, view+viewmodel pairs, design-system.md vocabulary,
  locality, barrels; **S6** widget home; **S7** no layout-swapping in shared
  widgets; **S9** no variant-to-variant component imports.

## Does not assert

- That surfaces are *covered* against the design — coverage's job.
- A view count or a fixed shape — the gate asserts a value, never a count.

## Run

```sh
scaffold.sh [app-root]                     # 0 pass / 1 FAIL / 2 env
bash scaffold/selftest.sh                  # R5: happy + NEGATIVE cases
```
