---
name: appbox-intake
description: Use to turn a client conversation into a design brief plus a seeded registry.json — OPTIONAL, runs before design. Elicits requirements; never generates design or code. Trigger on "intake a project", "write the brief", "seed the registry", "what does the client want". Drives skills/appbox-intake/intake.py.
---

# appbox-intake — elicit the brief, seed the registry

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

## What you produce (and what you do not)

Two artefacts, both written by the engine (`intake.py`):

1. **`docs/design/brief.md`** — one section per elicited field (product,
   audience, the things the app must do, existing systems, targets, brand,
   constraints, out-of-scope, and the layout template when one was picked).
   Every field whose provenance is `inferred` is
   **visibly marked** in the output — a reader who skims must not miss it.
   The brief also records **`locales`** (e.g. `[en, pl]`) and the **default
   locale** for the project — this drives the i18n capability and the ARB
   catalog set (`l10n/app_en.arb` template + one ARB per locale) the designer
   authors.
2. **`docs/design/registry.json`** — the **seed** the designer consumes: one
   entry per surface the client named, with keys `{id, label, shell, comp,
   surface}`. `surface` is **always `null`** — intake names what the client
   asked for; design binds a surface to each. `comp` is derived by convention
   (`shop.cart` → `ShopCart`), never authored. A hand-written brief whose
   surface table carries `priority` / `release` columns (e.g. from
   `appbox-story-mapper`) passes them through as optional sibling metadata —
   additive, never woven into the four canon keys.

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
   `id` (`<shell>.<short>`), `label`, `shell`, `provenance`. Do not set `comp` or
   `surface` — the engine derives `comp` and forces `surface: null`.

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
   python skills/appbox-intake/intake.py emit --answers <answers.json>
   ```
   Validate first if you only want a check:
   ```sh
   python skills/appbox-intake/intake.py validate <answers.json>
   ```
   Outputs default under `docs/design/` (overridable via `--brief-out` /
   `--registry-out`, or the `INTAKE_BRIEF_OUT` / `INTAKE_REGISTRY_OUT` env
   vars). Invalid input writes **nothing** — no partial artefacts.

5. **Or accept a hand-written brief (plan 10.7).** A brief a human wrote is the
   ideal case — it is already the client's words. Seed the registry from its
   surface table without rewriting a word:
   ```sh
   python skills/appbox-intake/intake.py seed --brief docs/design/brief.md
   ```
   A brief with no surface table yields an empty seed (the designer authors the
   registry). That is not an error; intake is optional.

6. **Hand off to design.** The brief and the seed are the inputs to
   `appbox-designer`. The emitted `## Layout template` section is consumed by
   the designer **verbatim** — structure the designer starts from, never
   rewritten at design time. The traceability gate (plan 10.6, owned by
   `gates/`) then asserts every registry entry traces to a brief requirement —
   the assertion this phase exists to enable.

## The guardrail, as a test

The engine's self-test is the proof the guardrail holds:
```sh
python skills/appbox-intake/intake.py --self-test
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
