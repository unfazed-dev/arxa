Pipeline state: schema, seed, and the target derivation table.

| file | what it is |
|---|---|
| `state.schema.json` | JSON Schema for a run's state (phase, targets, approval tokens, design hash, kit SHA). |
| `default.state.json` | the seed state a new run starts from. |
| `targets.derivation.json` | **DATA** (plan 06): one entry per platform target → the viewports it implies + the platform ceremonies the scaffold must emit. |

## targets.derivation.json (6.1)

A config-driven map, not code. Adding a target is a **data edit** here — gate
logic never changes. Each entry carries:

- `viewports` — viewport **names** (mobile/tablet/desktop) the target implies;
  the actual widths live in `config/app-box.config.json`, never here (R3).
- `ceremonies` — platform file/key checks the coverage gate (C5) asserts; an
  absent file (or a named key missing from it) fails the gate naming it (6.8).
- `inherits` — pulls a parent's viewports AND ceremonies before this entry's own
  (e.g. `pwa` inherits `web`).

The freeze gate derives its render widths and the coverage gate derives its
form-factor set (and ceremony set) from this table + the targets in state (6.2).
Targets are written to state, never carried as a flag — except that **gate and
golden runs take `--targets` explicitly** (6.3): ambient state in a
reproducibility run is the stale-green defect.
