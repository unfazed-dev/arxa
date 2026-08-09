# Intake surfaces — integration notes

The intake shell is a **typeform journey**: eight surfaced steps, each walking
one item at a time in the main panel (a question, a persona, a shell's
surface group, a flow, a direction group) — prefilled from the fixture with a
provenance chip, confirmed or corrected, never blank. The composer panel is
the chat rail, always in the current step's context; the activity panel
carries thread / artifacts / files; the journey timeline lives in the footer
panel.

| surface | route | main panel |
|---|---|---|
| `intake.interview` Interview | `/intake` (shell root) | mode pick → question cards → answer summary |
| `intake.personas` Personas | `/intake/personas` | persona cards (item engine) |
| `intake.surfaces` Surfaces | `/intake/surfaces` | shell groups × surface rows + states |
| `intake.flows` Flows | `/intake/flows` | persona-bound edge chains over the registry |
| `intake.mapping` Story Map | `/intake/map` | `map/full` (auto-opens once generated) · `map/priorities` · `map/releases` · `story/:id` |
| `intake.direction` Direction | `/intake/direction` | adjectives / avoids / references groups |
| `intake.brief` Design Brief | `/intake/brief` | `doc/full` · `doc/surfaces` — carries the approval gate |
| `intake.moodboard` Moodboard | `/intake/moodboard` | `gallery/all` · `gallery/:boardId` · `shot/:shotId` |

## Modes

The interview's first move picks the mode (question bank + journey shape):
**simple** auto-answers from suggestions, auto-accepts every prefill, and
collapses the journey to interview → brief; **normal** (default) shows every
step prefilled for confirmation (with accept-all); **advanced** (expert)
shows every step with no auto-accept.

## The item engine

`personas` / `surfaces` / `flows` / `direction` share one protocol in
`services/facades/intake_facade.js`: items come from the fixture
(prefills + provenance), the session records `{confirmed | edited | skipped}`
per item (`sessionData.intake.steps.<step>`), `current` = first open item,
corrections merge over the prefill at render. Actions per step:
`POST confirm` · `POST save` (correction) · `POST skip` · `GET edit?item=` ·
`POST accept-all`. The interview runs the same protocol over its question
bank (`POST answer` · `POST skip` · `GET edit?q=`).

## Layout contract

- `ui/common/composer_panel.html` (`cp.frame`) and
  `ui/views/main_shell/shared/widgets/activity_panel.html` (`pa.frame`) are consumed with
  **call/caller** — both ship `caller()` bodies. The composer is the shared
  card `ui/common/composer.html` (`cm.field`): a borderless textarea over an
  action bar (+ suggestions, LLM model menu, send). The model options hx-get
  `{base}/model/:id` (per-surface routes) and swap `#panels` (outerHTML);
  the selection lives on the shared `sessionData.agent.model`
  (services/facades/agent_menus.js). All menus open UPWARD — the composer
  sits at the panel floor.
- Every stage interaction swaps `#panels` **outerHTML** — the three content
  panels (activity / main / composer) are one swap unit; the timeline rides
  out-of-band (`hx-swap-oob`) since step progress moves it too.
- Follow-ups are plain chat; on the artifact surfaces (mapping / brief /
  moodboard) the open artifact rides the main panel until another one
  replaces it. A file row in the files view opens the file in the main panel
  (`{base}/file?path=`, mode picked server-side from the extension) until
  `?file=none`.
- Compact/medium rungs show one content panel at a time under the panel bar
  (`?panel=activity|main|composer`, `mp.panelBar`).
- The timeline macro call sits in `{% block bottombar %}` (the shell's
  `footer#panel-footer`); it is mode-aware (simple collapses the stages) and
  marks the first unfinished stage active.

## 1. Wire the routes (`app.routes.js`)

`ui/views/main_shell/intake/routes.intake.js` exports the same
`[method, path, handler]` array shape as `app.routes.js` (already spread
there). Per surface: `GET page`, `GET file`, `GET model/:id`, `GET panel`,
`GET panel/size/:side/:size`, `POST messages`. The four item steps add
`POST confirm|save|skip|accept-all` + `GET edit`; the interview adds
`POST depth|answer|skip` + `GET edit?q=`; the artifact surfaces add
`GET artifact/:kind/:id`; mapping and brief each carry `POST approve`.

## 2. Link the stylesheet

`assets/css/intake.css` holds all intake-specific styles (step stages, item
strips, provenance chips, mode cards, edge chains, status dots + rollups,
MoSCoW chips, brief document, moodboard gallery, activity-view
cards/badges). `app.css` is untouched. Linked in `ui/common/base.html` after
the app.css link:

```html
<link rel="stylesheet" href="/assets/css/intake.css">
```

## 3. Regenerating data

`models/intake_model/intake.<locale>.json` is generated — never hand-edit.
Source of truth is `models/intake_model/intake_seed.<locale>.json`. Besides
the story map / brief / moodboard, the seed carries display/runtime data:

- `questionBanks` — three separate banks (`simple` / `normal` / `advanced`),
  the mode choice picks one;
- `personas` — the drafted personas (goals / frustrations / contexts /
  proficiency / accessibility / provenance);
- `flows` — persona-bound edge sets over the screen registry
  (`{from, to, trigger, label?}`, ids resolve to labels in the facade);
- `direction` — adjectives / avoids / moodboard references, each with
  provenance;
- `brief.surfaces[].states` + `.provenance` — the states each surface must
  cover;
- `statuses` — pipeline status per generated story id (`s-<n>`), feeding the
  live map's status dots and rollups (absent = `pending`);
- `files` — the files activity view's generated-project list with badges
  (file bodies live in `services/repositories/files_repository.js`);
- `state` — the interview's initial state (depth, answers, generated,
  approved, approvedVersion, currentVersion); the facade clones it into the
  session and mutates the clone. Post-approval answer edits bump
  `currentVersion`; the "changed since approval" badge shows while
  `approvedVersion ≠ currentVersion`.

Regenerate: `node designs/appbox-studio/models/intake_model/generate.mjs`

## 4. Session state

All ephemeral UI state lives under `sessionData.intake` (`interview`,
`steps.<step>` item records, composer `extra`, `current` artifact per
surface, `currentFile` per surface, `activityView` per surface, `panelSize`,
`panel`, `msgSeq`) — no collision with other facades' session keys.
