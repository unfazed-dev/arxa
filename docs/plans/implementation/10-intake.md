# 10 — Intake: wizard UI + phase (hybrid)

**Goal.** A client conversation becomes a brief plus a seeded registry, through
either a wizard in the app or a headless phase.

**Blocks:** 14 (optional path). **Depends on:** 08.

## Shape (§22, hybrid confirmed)

Two front ends, **one engine**:

| surface | who | when |
|---|---|---|
| **wizard UI** in the desktop app | Michelle, and Evan with a client in the room | guided, step by step, resumable |
| **`app-box-intake` phase** (headless) | agents, harness invocation, re-runs | scripted or re-derived |

Both write the same artefacts. The wizard is a **view over the phase**, not a
parallel implementation — if the two can disagree, this plan has failed.

## The guardrail

> **Intake elicits. It does not generate.**

A phase that writes the brief produces confident fiction: requirements nobody
asked for, stated with the authority of ones they did. Where inference is
unavoidable, **mark it** — the same discipline as the playbook generator's
`TODO(prose)` markers, which a test counts.

## Steps

- [ ] **10.1** Define the intake schema in `pipeline/state/`: audience, the
      three things the app must do, existing systems, **targets**, brand,
      constraints, out-of-scope. Every field records **who supplied it**:
      `client`, `founder`, or `inferred`.
- [x] **10.2** Implement the engine in `skills/app-box-intake/` — questions,
      validation, and artefact emission. **No UI code here.**
- [x] **10.3** Emit `docs/design/brief.md` from the schema, with every
      `inferred` field visibly marked in the output.
- [x] **10.4** Emit the **seeded `registry.json`** — ids, tabs, comps, and
      `surface: null` for anything named but not yet designed.
- [ ] **10.5** Build the wizard surfaces in the desktop app over the same
      engine. Resumable, skippable, and **never blocking**: Michelle skips it
      entirely on first run and still reaches the showcase app.
- [ ] **10.6** Add the traceability gate: **every registry entry traces to a
      brief requirement.** An entry with no trace is a FAIL naming the entry.
      This is the assertion intake exists to enable.
- [x] **10.7** Accept a hand-written brief as valid input. Intake is optional;
      the gate in 10.6 runs either way.

## Done-when

1. Wizard and headless phase produce **byte-identical** artefacts from the same
   answers — prove it, or they are two implementations.
2. Every `inferred` field is marked in the emitted brief.
3. The traceability gate fails on a registry entry with no brief requirement,
   and names it.
4. Skipping intake entirely still reaches a working prototype.
5. A hand-written brief passes the same gate.
