---
name: appbox-intake
description: Use to turn a client conversation into validated intake answers plus a seeded registry.json — the head of ONE chain whose tail (`appbox emit story-map`) emits the unified design brief. OPTIONAL, runs before design. Elicits requirements; never generates design or code. Trigger on "intake a project", "write the brief", "seed the registry", "what does the client want". Drives `appbox intake` (the Dart port in appboxd/lib/intake.dart).
---

# appbox-intake — elicit the answers, seed the registry

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
appbox intake  →  validated answers  →  appbox emit story-map --answers <f>  →  docs/design/brief.md (unified)
                     +
              registry seeded at the design root
```

Intake is the **head** of a single sequential chain; `appbox emit story-map`
(appbox-story-mapper) is its **tail** and writes the unified
`docs/design/brief.md`. When answers are present, that brief is the intake
sections (Product, Audience, What the app must do, Existing systems, Targets,
Locales, Brand, Design direction, Content anchors, Constraints, Out of scope,
Layout template) + Releases + the epic/feature/story hierarchy + a **surface
inventory built from the intake-declared surfaces**. Standalone story-map (no
answers) still works exactly as before — intake is optional (plan 10.7).

## What you produce (and what you do not)

Two artefacts, written by the chain:

1. **Validated answers** — elicited with `appbox intake`, conforming to
   `intake.schema.json`. Beyond the core fields, intake elicits four optional
   groups:
   - **`direction`** — `{adjectives: [...], avoids: [...]}`: the design
     direction (what it should feel like, what it must not).
   - **`contentAnchors`** — real content examples the app must show.
   - **`locales`** — locale codes (e.g. `[en, pl]`), rendered after Targets in
     the brief; drives the i18n capability and the ARB catalog set
     (`l10n/app_en.arb` template + one ARB per locale) the designer authors.
   - **per-surface `states`** — UI state names (loading, empty, error, …),
     carried into the registry seed and the brief's surface table.
   The **audience** is elicited in JTBD form: *"When [situation], I want
   [motivation], so I can [outcome]."*
2. **The seeded registry** — `appbox intake emit` seeds it at the **design
   root**: `designs/<app>/models/screens_model/registry.json`, or whatever
   structure.json's `"registry"` field names — the same path
   `appbox gate intake` reads. `docs/design/registry.json` is only a fallback
   when no design root exists. One entry per surface the client named, with
   keys `{id, label, shell, comp, surface}`. `surface` is **always `null`** —
   intake names what the client asked for; design binds a surface to each.
   `comp` is derived by convention (`shop.cart` → `ShopCart`), never authored.
   A hand-written brief whose surface table carries `priority` / `release`
   columns (e.g. from `appbox-story-mapper`) passes them through as optional
   sibling metadata — additive, never woven into the four canon keys.

The unified `docs/design/brief.md` is emitted by the chain's tail —
`appbox emit story-map --answers <answers.json>` (when `--answers` is omitted
it auto-discovers `pipeline/state/run.intake.json`, then
`pipeline/state/default.intake.json`). Every field whose provenance is
`inferred` is **visibly marked** in the brief — a reader who skims must not
miss it.

You do **not** produce: views, viewmodels, routes, copy, layouts, component
libraries, or anything that is design. That is the next phase. If you find
yourself writing a screen, stop — you are in the wrong skill.

## Provenance is the whole contract

Every field records **who supplied it**: `client` (stated by the client),
`founder` (stated by the founder), or `inferred` (could not be elicited; a
placeholder the brief MUST flag). There is no fourth value. "Guessed",
"assumed", "default", "probably" are all `inferred` — and `inferred` is the
only value that gets marked. Recording content as `client` that the client did
not state is the single most damaging thing this skill can do; it manufactures
authority the brief does not have.

## Procedure

1. **Elicit, do not write.** Work through the question set (the fields in
   `intake.schema.json`) with the client or founder. Capture answers verbatim —
   rephrase nothing. Where the client did not answer, leave the field absent or
   mark it `inferred` with a placeholder value, never an invented one.

2. **Author the answers document.** One JSON object conforming to
   `intake.schema.json`. Each surface the client named becomes an entry with
   `id` (`<shell>.<short>`), `label`, `shell`, `provenance` — plus the optional
   `states` list (the UI states that screen must cover). Do not set `comp` or
   `surface` — the engine derives `comp` and forces `surface: null`. Record the
   optional groups when elicited: `direction` (`{adjectives, avoids}`),
   `contentAnchors`, `locales`. Capture the audience in JTBD form: *"When
   [situation], I want [motivation], so I can [outcome]."*

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
   appbox intake emit --answers <answers.json>
   ```
   Validate first if you only want a check:
   ```sh
   appbox intake validate <answers.json>
   ```
   `emit` validates the answers and seeds the registry at the design root
   (`designs/<app>/models/screens_model/registry.json`, or structure.json's
   `"registry"` field; `docs/design/registry.json` only when no design root
   exists). Paths are overridable via `--brief-out` / `--registry-out`, or the
   `INTAKE_BRIEF_OUT` / `INTAKE_REGISTRY_OUT` env vars. Invalid input writes
   **nothing** — no partial artefacts. Then run the chain's tail to write the
   unified brief:
   ```sh
   appbox emit story-map --answers <answers.json> \
     --output docs/design/story_map.html \
     --data-out docs/design/story-map.json \
     --brief-out docs/design/brief.md
   ```

5. **Or accept a hand-written brief (plan 10.7).** A brief a human wrote is the
   ideal case — it is already the client's words. Seed the registry from its
   surface table without rewriting a word:
   ```sh
   appbox intake seed --brief docs/design/brief.md
   ```
   A brief with no surface table yields an empty seed (the designer authors the
   registry). That is not an error; intake is optional.

6. **Hand off to design.** The brief and the seed are the inputs to
   `appbox-designer`. The emitted `## Layout template` section is consumed by
   the designer **verbatim** — structure the designer starts from, never
   rewritten at design time. The traceability gate (plan 10.6 —
   `appbox gate intake`, pure Dart in `appboxd/lib/gate_intake.dart`) then
   asserts every registry entry traces to a brief requirement and back, and —
   when intake answers exist — that the brief carries `## Surface inventory`
   (and `## Layout template` when a layoutTemplate was elicited). That is the
   assertion this phase exists to enable.

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
appbox intake --self-test
```
It asserts, negatively: feed N surfaces, the emitted registry has exactly N
(no invented entries); every `surface` is `null`; every `inferred` field is
marked in the brief and the mark does not leak onto `client` fields; bad
provenance / malformed ids / duplicate ids are all rejected and named.

## Common mistakes

- **Inventing a field the client did not state.** If they were silent, the
  field is `inferred` with a placeholder, or absent. Never fabricate a
  requirement with `client` provenance.
- **Binding a `surface`.** Intake names; design binds. A non-null surface in a
  seed means intake did design's job — the self-test fails it.
- **Rephrasing the client.** Capture verbatim. Polishing their words is editing
  the brief, which is generation by another name.
- **Forgetting intake is optional.** Forcing it on a first run costs the buyer
  the demo that earns trust. A hand-written brief, or none at all, is valid.
- **Trusting the emit without validating.** `emit` validates internally and
  refuses to write on error, but run `validate` while you author to catch
  provenance and id mistakes early.
