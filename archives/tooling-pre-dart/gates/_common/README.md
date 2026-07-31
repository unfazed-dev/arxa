# gates/_common

Shared helpers every gate may use. This is the **only** sideways import a gate
is permitted — no gate imports a sibling gate (R4). If two gates need the same
logic, it moves here, not sideways.

| helper | what it does |
|---|---|
| `state_reader.sh` | reads pipeline state (`state_get <field>`, `state_targets`); `state_set <field> <value>` writes a scalar to LIVE state only (the tracked seed `default.state.json` is read-only) |
| `design_hash.sh` | the canonical §6 design-tree hash: sha256 over sorted relative paths + contents (excludes `.DS_Store`, `approval.lock`) |
| `assert_design_fresh.sh` | the §6 checker — fails red naming `designHash` when the design moved after freeze; fail-open only for a legacy empty hash |
| `porcelain_diff.sh` | regeneration assertion via `git status --porcelain`, never `git diff --exit-code` |
| `sarif.sh` | SARIF emitter — the machine contract for GUI, companion and CI |
| `report.sh` | `pass`/`fail` — the shared exit-and-message contract |

A gate sources these with:

```sh
source "$(dirname "$0")/../_common/state_reader.sh"
```
