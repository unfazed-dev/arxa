# intake (traceability)

The TRACEABILITY gate (plan 10.6). The assertion intake exists to enable
(architecture §22): **every registry surface traces to an intake answer, and
every intake answer traces to a registry surface.** No orphans either way.

A registry entry the client never asked for, or a client requirement the
registry silently dropped, is a FAIL naming the surface id. This is the
"cheapest place to be wrong" made enforceable — the brief is the one output a
non-technical client can validate, and this gate ties it to the registry the
designer consumes.

## Sources

Checked in order; the first non-empty source wins:

1. **intake answers** — the pipeline state intake slot (`pipeline/state/run.intake.json`),
   or the skill's answers document via `--answers`. Reads the `answers.surfaces[*].id`
   set.
2. **hand-written brief** (10.7) — a brief whose surface table seeds the registry.
   The gate parses the table for `<tab>.<short>` ids, the same pattern the engine's
   `seed_from_brief` uses. `docs/design/brief.md` by default.

If no source exists AND no registry exists, the gate passes vacuously — nothing
to trace (greenfield). A registry with entries but no traceable source is a FAIL:
every entry is untraced.

## Asserts

- **T1 orphan answer** — a surface id in the intake answers (or brief) that is
  NOT in the registry. The client asked for something the registry dropped.
- **T2 unanswered surface** — a surface id in the registry that is NOT in the
  intake answers (or brief). A registry entry the client never asked for.
- **T3 duplicate ids** — a surface id appearing more than once in the registry.
  Surface ids are permanent; duplicates are a bug.

## Run

```sh
intake.sh                                         # reads pipeline state defaults
intake.sh --answers answers.json --registry docs/design/registry.json
intake.sh --brief docs/design/brief.md            # hand-written brief (10.7)
bash selftest.sh                                  # R5: happy + NEGATIVE cases
```

Exit: 0 pass / 1 FAIL / 2 env.
