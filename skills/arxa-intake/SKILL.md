---
name: arxa-intake
description: Use when a client conversation needs to become validated intake answers plus a seeded registry.json and flows.json — the head of ONE chain whose tail (`arxa emit story-map`) emits the unified design brief. OPTIONAL, runs before design. Elicits requirements; never generates design or code. Trigger on "intake a project", "write the brief", "seed the registry", "what does the client want". Drives `arxa intake` (the Dart port in arxa/lib/intake.dart).
---

# arxa-intake — elicit the answers, seed the registry + flows

> Per-skill playbook (the folded canon for this phase): [`INTAKE_playbook.mdx`](INTAKE_playbook.mdx)

## Core principle

> **Intake elicits; it does not generate.** (architecture §22)

A phase that *writes* the brief produces confident fiction — requirements nobody
asked for, stated with the authority of ones they did. Intake asks and records.
Where it must infer, it **marks the inference explicitly**, the same way a prose
generator emits `TODO(prose)` for narrative it has no source for. The brief is
the client's words; that is the entire value, and a generated brief has none.

This is an **optional** phase. A hand-written brief is valid input, and on a
first run the buyer skips intake entirely and still reaches the showcase app
(`journeys.md` J1). Never put a questionnaire between a buyer and the demo.

## Where intake sits — one chain, one brief

```
arxa intake  →  validated answers  →  arxa emit story-map --answers <f>  →  docs/intake/brief.md (unified)
                     +
              registry + flows seeded in the project's ~/.arxa intake/ dir
```

Intake is the **head** of a single sequential chain; `arxa emit story-map`
(arxa-story-mapper) is its **tail** and writes the unified
`docs/intake/brief.md`. When answers are present, that brief is the intake
sections (Product, Audience, What the app must do, Existing systems, Targets,
Locales, Brand, Design direction, Content anchors, Constraints, Out of scope,
Layout template) + Releases + the epic/feature/story hierarchy + a **surface
inventory built from the intake-declared surfaces**. Standalone story-map (no
answers) still works exactly as before — intake is optional (plan 10.7).

**Chain position:** stage 1 of `arxa-orchestrator` (Ø, front door) → `arxa-story-mapper / arxa-moodboarder` (0, optional) → `arxa-intake` (1) → `arxa-designer` (2) → `arxa-scaffolder` (3) → `arxa-builder` (4) → `arxa-tester` (5) → `arxa-reviewer` (6) → `arxa-deployer` (9) — cross-cutting: `arxa-lint` (7), `arxa-lens` (8), `arxa-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/arxa-system-map.md`; the CLI FSM phases: `arxa/lib/phases.dart`.

- **Upstream:** the client conversation — optionally preceded by stage 0 (`arxa-story-mapper`, `arxa-moodboarder`) when the run began as a story map; the whole run may be started and dispatched by `arxa-orchestrator` (stage Ø, the front door), which hands off to `arxa-cicd` day-zero bootstrap before this stage.
- **Downstream:** `arxa-story-mapper` is this chain's tail (`--answers` → the unified brief); then `arxa-designer`, which consumes the brief + registry seed and the emitted `## Layout template` section **verbatim**.

## Provenance is the whole contract

Every field records **who supplied it**: `client` (stated by the client),
`founder` (stated by the founder), or `inferred` (could not be elicited; a
placeholder the brief MUST flag). There is no fourth value. "Guessed",
"assumed", "default", "probably" are all `inferred` — and `inferred` is the
only value that gets marked. Recording content as `client` that the client did
not state is the single most damaging thing this skill can do; it manufactures
authority the brief does not have.

## How to elicit — one question at a time

The question set is a CONVERSATION, never a form dump:

- **One question at a time.** Ask, wait for the answer, record it, then ask
  the next. Never paste the whole schema or a wall of questions.
- **Attach a recommendation to every closed question** — recommended option
  first, one sentence of tradeoff — the way `arxa-cicd`'s bootstrap grills
  its nine decisions. Use the `ask_user_question` tool for closed picks
  (targets, locales, layout category/archetype, priority clashes); keep
  open fields (the JTBD audience sentence, `contentAnchors`) free-form.
- **Variable N** — personas, surfaces, anchors: take as many as the client
  names and stop. One is a valid answer; so is seven.
- **Ground with search, attribute honestly.** When the client names a
  domain, brand or competitor you don't know, a web search may inform YOUR
  next question — but search results are never `client` provenance. Either
  ask the client to confirm (then it is `client`), or record `inferred`.
  Cite the anchor in the conversation, not in the answers.
- **Escape is the emitter's job, not yours.** Record client strings
  verbatim, markup included — `intake emit` neutralizes markdown/HTML in
  elicited values before they reach the brief.

## Procedure

1. **Elicit, do not write.** Work through the question set (the fields in
   `intake.schema.json`) with the client or founder — one question at a
   time (see above). Capture answers verbatim — rephrase nothing. Where the
   client did not answer, leave the field absent or mark it `inferred` with
   a placeholder value, never an invented one.

2. **Author the answers document.** One JSON object conforming to
   `intake.schema.json`. Each surface the client named becomes an entry with
   `id` (`<shell>.<short>`), `label`, `shell`, `provenance` — plus the optional
   `states` list (the UI states that screen must cover) and the optional
   `requiresAuth` / `tab` booleans. Do not set `comp` or `surface` — the
   engine derives `comp` (and `route`) and forces `surface: null`. Record the
   optional groups when elicited: `direction` (`{adjectives, avoids}`),
   `contentAnchors`, `locales`. Record the journeys the client described as
   the `flows` group (shape above — linear chains, typed actions); when the
   client did not describe journeys, omit `flows` and let the engine derive
   drafts marked `inferred` for the confirm step. Capture the audience in
   JTBD form: *"When [situation], I want [motivation], so I can [outcome]."*

3. **Offer the layout template.** After the fields are elicited and before
   emit, offer the **Layout Template** pick. First the app **category** from
   the closed list in `layout_templates.json` (ecommerce, social,
   productivity, dashboard, editorial, landing, custom). Then the **archetype
   gallery** for that category: the six archetypes (feed, list-detail,
   supporting-pane, dashboard, hero-scroll, detail-column) shown as **plain
   colored boxes** with their **named containers**, one per **rung** of the
   viewport ladder (compact / medium / expanded) — 4–8 options per form
   factor, with the category's `defaultFor` archetype **pre-selected**. Never
   style the boxes; feedback must stay on structure. Record the choice in the
   answers JSON as `layoutTemplate`, copied **verbatim** from
   `layout_templates.json` (`{category, archetype, areas, containers}` —
   intake never composes or edits a template). If the client declines, omit
   the field; do not infer one.

4. **Emit.**
   ```sh
   arxa intake emit --answers <answers.json> --project <name>
   ```
   Validate first if you only want a check:
   ```sh
   arxa intake validate <answers.json>
   ```
   With `--project`, every output lands in the project's
   `~/.arxa/projects/<name>/intake/` dir (answers/brief/registry/flows).
   Without `--project`, `emit` **refuses to run** unless you pass an
   explicit `--brief-out` (or set `INTAKE_BRIEF_OUT`) — the old default
   silently overwrote the repo-root brief (then docs/design/brief.md), which inside any
   arxa repo is a tracked file. The registry path (when explicitly
   emitted) still defaults to the design root
   (`designs/<app>/models/screens_model/registry.json`, or structure.json's
   `"registry"` field; `docs/intake/registry.json` only when no design root
   exists), overridable via `--registry-out` / `INTAKE_REGISTRY_OUT`.
   Invalid input writes **nothing** — no partial artefacts. Client strings
   are markdown-escaped by the emitter. Then run the chain's tail to write
   the unified brief:
   ```sh
   arxa emit story-map --answers <answers.json> \
     --output docs/intake/story_map.html \
     --data-out docs/intake/story-map.json \
     --brief-out docs/intake/brief.md
   ```

5. **Or accept a hand-written brief (plan 10.7).** A brief a human wrote is the
   ideal case — it is already the client's words. Seed the registry from its
   surface table without rewriting a word:
   ```sh
   arxa intake seed --brief docs/intake/brief.md
   ```
   A brief with no surface table yields an empty seed (the designer authors the
   registry). That is not an error; intake is optional.

6. **Hand off to design.** The brief and the seed are the inputs to
   `arxa-designer`. The emitted `## Layout template` section is consumed by
   the designer **verbatim** — structure the designer starts from, never
   rewritten at design time. The traceability gate (plan 10.6 —
   `arxa gate intake`, pure Dart in `arxa/lib/gate_intake.dart`) then
   asserts every registry entry traces to a brief requirement and back, and —
   when intake answers exist — that the brief carries `## Surface inventory`
   (and `## Layout template` when a layoutTemplate was elicited). That is the
   assertion this phase exists to enable.

## References

- [`references/project-layout.md`](references/project-layout.md) — load when you're about to run `emit`/`seed` and need the exact `~/.arxa/projects/<name>/intake/` file layout, or need to trace which skill (`arxa-story-mapper` vs `arxa-moodboarder`) owns `map.json` / `moodboard.json`.
- [`references/artifacts-and-flows.md`](references/artifacts-and-flows.md) — load while authoring the answers document: full schema detail for `product.kind`, the optional groups (`direction`, `contentAnchors`, `locales`, per-surface `states`/`requiresAuth`/`tab`), the full `personas` question text, registry-seeding rules (`comp`/`route`/`surface` derivation), and the `flows.json` shape (edges, typed actions, linear-chain rule, derive+confirm).
- [`references/guardrail-and-mistakes.md`](references/guardrail-and-mistakes.md) — load before/after `emit` to run the `--self-test` guardrail checklist and cross-check against the named common mistakes (inventing fields, binding `surface`, rephrasing the client, skipping validate).
