# Intake surfaces — integration notes

Three surfaces on the panel layout: the intake shell root IS a chat (the
interview) in the permanent composer panel, artifacts open in the main
panel, the activity panel carries thread / artifacts / files, and the
read-only stage timeline lives in the footer panel.

| surface | route (shell root) | main-panel artifacts |
|---|---|---|
| `intake.mapping` Story Mapping | `/intake` | `map/full` (live) · `map/priorities` · `map/releases` · `story/:id` |
| `intake.brief` Design Brief | `/intake/brief` | `doc/full` · `doc/surfaces` |
| `intake.moodboard` Moodboard | `/intake/moodboard` | `gallery/all` · `gallery/:boardId` · `shot/:shotId` |

## Layout contract

- `ui/common/composer_panel.html` (`cp.frame`) and
  `ui/common/panel_views.html` (`pv.frame`) are consumed with
  **call/caller** — both ship `caller()` bodies. The composer is the shared
  card `ui/common/composer.html` (`cm.field`): a borderless textarea over an
  action bar (+ suggestions, LLM model menu, send). The model options hx-get
  `{base}/model/:id` (per-surface routes) and swap `#panels` (outerHTML);
  the selection lives on the shared `sessionData.agent.model`
  (services/facades/agent_menus.js). All menus open UPWARD — the composer
  sits at the panel floor.
- Every stage interaction swaps `#panels` **outerHTML** — the three content
  panels (activity / main / composer) are one swap unit; the timeline rides
  out-of-band (`hx-swap-oob`) since interview progress moves it too.
- Follow-ups are plain chat; the open artifact rides the main panel until
  another one replaces it (there is no close act — the composer is
  permanent). A file row in the files view opens the file in the main panel
  (`{base}/file?path=`, mode picked server-side from the extension) until
  `?file=none`.
- Compact/medium rungs show one content panel at a time under the panel bar
  (`?panel=activity|main|composer`, `mp.panelBar`).
- The timeline macro call sits in `{% block bottombar %}` (the shell's
  `footer#panel-footer`).

## 1. Wire the routes (`app.routes.js`)

`ui/views/main_shell/intake/routes.intake.js` exports the same
`[method, path, handler]` array shape as `app.routes.js` (already spread
there). Per surface: `GET page`, `GET artifact/:kind/:id`, `GET file`,
`GET panel?view=`, `GET panel/size/:side/:size`, `POST messages`. Mapping
adds the interview: `POST depth` · `POST answer` · `POST skip` ·
`GET edit?q=` · `POST approve`. The retired routes (`/close`, `/filter`,
`/bar/*`, `/artifact/*/messages`) are gone.

## 2. Link the stylesheet

`assets/css/intake.css` holds all intake-specific styles (question
carousel, status dots + rollups, MoSCoW chips, brief document, moodboard
gallery, activity-view cards/badges). `app.css` is untouched. Add to
`ui/common/base.html` after the app.css link:

```html
<link rel="stylesheet" href="/assets/css/intake.css">
```

## 3. Regenerating data

`models/intake_model/intake.json` is generated — never hand-edit.
Source of truth is `models/intake_model/intake_seed.<locale>.json`. Besides
the story map / brief / moodboard, the seed now carries display/runtime
data:

- `questionBanks` — three separate banks (`simple` / `normal` / `advanced`),
  the depth choice in the first chat message picks one;
- `statuses` — pipeline status per generated story id (`s-<n>`), feeding the
  live map's status dots and rollups (absent = `pending`);
- `files` — the files activity view's generated-project list with badges
  (file bodies live in `services/repositories/files_repository.js`);
- `state` — the interview's initial state (depth, answers, generated,
  approved, approvedVersion, currentVersion); the facade clones it into the
  session and mutates the clone. Post-approval answer edits bump
  `currentVersion`; the "changed since approval" badge shows while
  `approvedVersion ≠ currentVersion`.

Regenerate: `node designs/appbox/models/intake_model/generate.mjs`

## 4. Session state

All ephemeral UI state lives under `sessionData.intake` (`interview`,
composer `extra`, `current` artifact per surface, `currentFile` per surface,
`activityView` per surface, `panelSize`, `panel`, `msgSeq`) — no collision
with other facades' session keys.
