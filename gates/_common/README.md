# gates/_common

Shared helpers every gate may use. This is the **only** sideways import a gate
is permitted — no gate imports a sibling gate (R4). If two gates need the same
logic, it moves here, not sideways.

| helper | what it does |
|---|---|
| `state_reader.sh` | reads pipeline state (`state_get <field>`, `state_targets`) |
| `porcelain_diff.sh` | regeneration assertion via `git status --porcelain`, never `git diff --exit-code` |
| `sarif.sh` | SARIF emitter — the machine contract for GUI, companion and CI |
| `report.sh` | `pass`/`fail` — the shared exit-and-message contract |

A gate sources these with:

```sh
source "$(dirname "$0")/../_common/state_reader.sh"
```
