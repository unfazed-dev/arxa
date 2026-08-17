---
name: appbox-intake
description: Use when a client conversation needs to become validated intake answers plus a seeded registry.json and flows.json — the head of ONE chain whose tail (`appbox emit story-map`) emits the unified design brief. OPTIONAL, runs before design. Elicits requirements; never generates design or code. Trigger on "intake a project", "write the brief", "seed the registry", "what does the client want". Drives `appbox intake` (the Dart port in appboxd/lib/intake.dart).
---

# appbox-intake — elicit the answers, seed the registry + flows

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
appbox intake  →  validated answers  →  appbox emit story-map --answers <f>  →  docs/intake/brief.md (unified)
                     +
              registry + flows seeded in the project's ~/.appbox intake/ dir
```

Intake is the **head** of a single sequential chain; `appbox emit story-map`
(appbox-story-mapper) is its **tail** and writes the unified
`docs/intake/brief.md`. When answers are present, that brief is the intake
sections (Product, Audience, What the app must do, Existing systems, Targets,
Locales, Brand, Design direction, Content anchors, Constraints, Out of scope,
Layout template) + Releases + the epic/feature/story hierarchy + a **surface
inventory built from the intake-declared surfaces**. Standalone story-map (no
answers) still works exactly as before — intake is optional (plan 10.7).

**Chain position:** stage 1 of `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Upstream:** the client conversation — optionally preceded by stage 0 (`appbox-story-mapper`, `appbox-moodboarder`) when the run began as a story map; the whole run may be started and dispatched by `appbox-orchestrator` (stage Ø, the front door), which hands off to `appbox-cicd` day-zero bootstrap before this stage.
- **Downstream:** `appbox-story-mapper` is this chain's tail (`--answers` → the unified brief); then `appbox-designer`, which consumes the brief + registry seed and the emitted `## Layout template` section **verbatim**.

## Projects live in ~/.appbox

Every user project is `~/.appbox/projects/<name>/{intake,design,build,settings}`
(`appbox project init <name>`; `APPBOX_HOME` overrides the root; the studio
design itself stays in the repo — ~/.appbox holds user projects only). Emitting
with `--project <name>` writes ALL intake outputs there:

```
~/.appbox/projects/<name>/intake/
  answers.json     the validated answers, verbatim
  brief.md         the emitted brief (inferred fields marked)
  registry.json    the seeded registry (see below)
  flows.json       declared flows, or derived drafts marked inferred
  personas.json    the elicited user types ([] when none were named)
  map.json         the story map, ids content-derived, counts baked in
  moodboard.json   boards/references/shots, shot src precomputed
  direction.json   adjectives/avoids, field provenance promoted per item
```

The last four are Slice B1. All four are pure functions of `answers.json` and
all four degrade to their EMPTY shape when the answering group is absent — every
project that existed before Slice B has all four groups missing, and re-emitting
one of those must keep working rather than fail.

**Where the last three get their input.** `direction.json` and `personas.json`
come from groups intake elicits itself (`direction`, `personas`). The other two
come from documents intake does NOT own:

| artifact | answers group | written by |
|---|---|---|
| `map.json` | `answers.map` | `appbox-story-mapper` |
| `moodboard.json` | `answers.moodboard` | `appbox-moodboarder` |

Those two skills deposit their document into `answers.json` under that key;
intake republishes it with ids, counts and `shot.src` baked in, and carries
every field it does not recognise through untouched — intake is a republisher
here, and a republisher that drops the author's fields is the bug. Shapes:
`skills/appbox-story-mapper/story-map.schema.json` and
`skills/appbox-moodboarder/moodboard.schema.json`.

## What you produce (and what you do not)

Two artefacts, written by the chain:

1. **Validated answers** — elicited with `appbox intake`, conforming to
   `intake.schema.json`. The FIRST closed question of every intake is
   **`product.kind`** — *is this product a **site** (web/landing: htmx +
   islands, the designer's eject is runnable site code) or an **app**
   (Flutter targets, scaffold → build → stores)?* It is not the same axis
   as a target: a Flutter app may target `web` while being kind `app`, and
   a site is kind `site` regardless of hosting. Record it as
   `product.kind: site|app` — for repo-mode projects `appbox project sync
   <app-dir>` pushes it (with targets/locales) into the `appbox.json`
   marker, and every downstream stage (moodboard gathering prompts,
   commission stack text, scaffolder, deployer) branches on it. Beyond the
   core fields, intake elicits four optional groups:
   - **`direction`** — `{adjectives: [...], avoids: [...]}`: the design
     direction (what it should feel like, what it must not).
   - **`contentAnchors`** — real content examples the app must show.
   - **`locales`** — locale codes (e.g. `[en, pl]`), rendered after Targets in
     the brief; drives the i18n capability and the ARB catalog set
     (`l10n/app_en.arb` template + one ARB per locale) the designer authors.
   - **per-surface `states`** — UI state names (loading, empty, error, …),
     carried into the registry seed and the brief's surface table.
   - optional per-surface flags: **`requiresAuth`** (the screen sits behind
     sign-in) and **`tab`** (bottom-tab membership — the scaffolder's shell
     group), booleans carried into the registry.
   The **audience** is elicited in JTBD form: *"When [situation], I want
   [motivation], so I can [outcome]."*

   **`personas`** — the user types, asked as its own question (Slice B2):

   > **Who are the main types of people who will use this?**
   > Name each one as you'd describe them to a new hire — as many as you
   > actually have, not a round number. For each, if you know it: what are
   > they trying to get done, what makes it painful today, where and when
   > do they use it, how comfortable are they with tools like this, and do
   > any of them have access needs?

   **Variable N.** Take as many as the client names and stop — one is a
   valid answer, so is seven. Do not pad to three, do not prompt for "a
   couple more", and do NOT synthesise one from `audience`: that field is a
   single JTBD sentence with no name, role or goals, so anything built from
   it is invention wearing the authority of elicitation (§22). If the
   client names none, omit the key — `personas.json` is then `[]`, which
   truthfully says nobody was named. Per-persona sub-answers left blank stay
   absent; a blank `accessibility` means unstated, never "none".
2. **The seeded registry + flows** — `appbox intake emit` seeds them in the
   project's `intake/` dir (with `--project`), or at the design root
   (`designs/<app>/models/screens_model/registry.json`, or whatever
   structure.json's `"registry"` field names) without it — the same path
   `appbox gate intake` reads. `docs/intake/registry.json` is only a fallback
   when no design root exists. One entry per surface the client named, with
   keys `{id, label, shell, comp, route, surface}`. `comp` and `route` are
   derived by convention (`shop.cart` → `ShopCart`, `/cart`), never authored —
   an answers `route` key overrides per surface. `surface` is **always
   `null`** — intake names what the client asked for; design binds a surface
   to each. `comp` is derived by convention, never authored.
   A hand-written brief whose surface table carries `priority` / `release`
   columns (e.g. from `appbox-story-mapper`) passes them through as optional
   sibling metadata — additive, never woven into the canon keys.

## Flows — derive + confirm

Flows wire the declared surfaces into linear user journeys; they are how the
designer later produces views + flows + prototype deterministically. Shape
(flows.json v2):

```json
[{ "id": "flow-browse-buy", "name": "Browse and buy", "provenance": "founder",
   "edges": [{ "from": "portalo.home", "to": "portalo.category",
               "trigger": "Category tile", "action": "push" }] }]
```

- **Edges** are `{from, to, trigger, action?}`; endpoints must be declared
  intake surfaces (flows wire what the client named, nothing else).
- **`action` is typed**: `push | replace | back | modal | system` (default
  `push`). `system` marks non-gesture edges (auth-success, deep-link) — the
  scaffolder maps them to route guards, never to buttons.
- **Linear chains only**: a screen has at most one outgoing and one incoming
  edge per flow. No branches, no loops, no self-edges — the validator rejects
  them by name. A screen may appear in MANY flows (multi-flow membership).
- **Derive + confirm**: when answers carry no `flows` group, the engine
  derives one draft flow per shell (surfaces chained in declaration order,
  trigger `continue`) marked `provenance: inferred` — a draft to confirm, never
  a fact. Confirming flips provenance:
  ```sh
  appbox intake flows confirm --project <name> --flow <id> --as founder|client
  ```

The unified `docs/intake/brief.md` is emitted by the chain's tail —
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

## How to elicit — one question at a time

The question set is a CONVERSATION, never a form dump:

- **One question at a time.** Ask, wait for the answer, record it, then ask
  the next. Never paste the whole schema or a wall of questions.
- **Attach a recommendation to every closed question** — recommended option
  first, one sentence of tradeoff — the way `appbox-cicd`'s bootstrap grills
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
   appbox intake emit --answers <answers.json> --project <name>
   ```
   Validate first if you only want a check:
   ```sh
   appbox intake validate <answers.json>
   ```
   With `--project`, every output lands in the project's
   `~/.appbox/projects/<name>/intake/` dir (answers/brief/registry/flows).
   Without `--project`, `emit` **refuses to run** unless you pass an
   explicit `--brief-out` (or set `INTAKE_BRIEF_OUT`) — the old default
   silently overwrote the repo-root brief (then docs/design/brief.md), which inside any
   appbox repo is a tracked file. The registry path (when explicitly
   emitted) still defaults to the design root
   (`designs/<app>/models/screens_model/registry.json`, or structure.json's
   `"registry"` field; `docs/intake/registry.json` only when no design root
   exists), overridable via `--registry-out` / `INTAKE_REGISTRY_OUT`.
   Invalid input writes **nothing** — no partial artefacts. Client strings
   are markdown-escaped by the emitter. Then run the chain's tail to write
   the unified brief:
   ```sh
   appbox emit story-map --answers <answers.json> \
     --output docs/intake/story_map.html \
     --data-out docs/intake/story-map.json \
     --brief-out docs/intake/brief.md
   ```

5. **Or accept a hand-written brief (plan 10.7).** A brief a human wrote is the
   ideal case — it is already the client's words. Seed the registry from its
   surface table without rewriting a word:
   ```sh
   appbox intake seed --brief docs/intake/brief.md
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
