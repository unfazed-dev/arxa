Pipeline state: schema, seed, and the target derivation table.

| file | what it is |
|---|---|
| `state.schema.json` | JSON Schema for a run's state (phase, targets, approval tokens, design hash, kit SHA). |
| `default.state.json` | the seed state a new run starts from. |
| `targets.derivation.json` | **DATA** (plan 06): one entry per platform target → the viewports it implies + the platform ceremonies the scaffold must emit. |
| `intake.state.schema.json` | JSON Schema for the intake state slot (plan 10.1): elicited answers + emitted artefact paths. The answers shape references `skills/appbox-intake/intake.schema.json` (the engine's artefact format); this schema binds answers into pipeline state. |
| `default.intake.json` | the seed intake state (answers null — intake not yet run). |

## targets.derivation.json (6.1)

A config-driven map, not code. Adding a target is a **data edit** here — gate
logic never changes. Each entry carries:

- `viewports` — viewport **names** (mobile/tablet/desktop) the target implies;
  the actual widths live in `config/appbox.config.json`, never here (R3).
- `ceremonies` — platform file/key checks the coverage gate (C5) asserts; an
  absent file (or a named key missing from it) fails the gate naming it (6.8).
- `inherits` — pulls a parent's viewports AND ceremonies before this entry's own
  (e.g. `pwa` inherits `web`).

The freeze gate derives its render widths and the coverage gate derives its
form-factor set (and ceremony set) from this table + the targets in state (6.2).
Targets are written to state, never carried as a flag — except that **gate and
golden runs take `--targets` explicitly** (6.3): ambient state in a
reproducibility run is the stale-green defect.

## intake.state.schema.json (10.1)

The pipeline-owned state slot for intake answers. The skill
(`skills/appbox-intake/intake.schema.json`) defines the **artefact format** —
what the engine validates and emits against; this schema defines the **state
slot** — where elicited answers live in pipeline state. Both the desktop wizard
(10.5) and the headless phase write the same answers here (one engine, two
fronts — DW1: byte-identical output). `answers` carries provenance
(`client|founder|inferred`) on every field; `artefacts` records where
`appbox intake emit` wrote. The registry seed lands at the design root
(`designs/<app>/models/screens_model/registry.json`, or structure.json's
`"registry"` field; `docs/design/registry.json` only when no design root
exists); the unified `docs/design/brief.md` is written by the chain's tail,
`appbox emit story-map --answers <f>`.
The traceability gate (10.6) reads this slot to assert no orphans: every
registry surface traces to an intake answer, and vice versa.
