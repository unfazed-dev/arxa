# Intake surfaces — integration notes

Three surfaces on the Chat-Centric Layout: the intake tab root IS a chat (the
interview), artifacts open on a canvas that docks the chat right, the left
multi-view rail carries thread / artifacts / files, and the read-only stage
timeline lives in the bottom bar.

| surface | route (tab root) | canvas artifacts |
|---|---|---|
| `intake.mapping` Story Mapping | `/intake` | `map/full` (live) · `map/priorities` · `map/releases` · `story/:id` |
| `intake.brief` Design Brief | `/intake/brief` | `doc/full` · `doc/surfaces` |
| `intake.moodboard` Moodboard | `/intake/moodboard` | `gallery/all` · `gallery/:boardId` · `shot/:shotId` |

## Layout contract

- `ui/common/chat_stage.html` (`cs.wrap`) and `ui/common/rail_views.html`
  (`mv.frame`) are consumed with **call/caller** — both ship `caller()`
  bodies. The composer and chat messages are intake-local macros in
  `_shared.html`: `rail.composer` / `rail.msg` hardcode `hx-target="#canvas"`,
  which only exists while docked — every intake interaction targets
  `#stage-layout` (outerHTML) instead, the chat-stage component's own
  contract. Same CSS classes, so app.css/chat.css styling applies unchanged.
- The stage-bar FAB follow-up thread is retired: follow-ups are plain chat;
  the open artifact rides as a context chip (`removeHref` → `/close`).
- The timeline macro call sits in `{% block bottombar %}` (the shell's
  `footer#bottom-bar`); the old top `timeline` block is gone. Interview
  progress moves the timeline, so stage fragment responses re-render it
  out-of-band (`hx-swap-oob`).

## 1. Wire the routes (`app.routes.js`)

`ui/views/main_shell/intake/routes.intake.js` exports the same
`[method, path, handler]` array shape as `app.routes.js` (already spread
there). Per surface: `GET page`, `GET artifact/:kind/:id`, `GET close`,
`GET rail?view=`, `POST messages`. Mapping adds the interview:
`POST depth` · `POST answer` · `POST skip` · `GET edit?q=` · `POST approve`.
The retired routes (`/filter`, `/bar/*`, `/artifact/*/messages`) are gone.

## 2. Link the stylesheet

`assets/css/intake.css` holds all intake-specific styles (zones grid,
question carousel, status dots + rollups, MoSCoW chips, brief document,
moodboard gallery, rail-view cards/badges). `app.css` is untouched. Add to
`ui/common/base.html` after the app.css link:

```html
<link rel="stylesheet" href="/assets/css/intake.css">
```

## 3. Regenerating data

`models/intake_model/intake.json` is generated — never hand-edit.
Source of truth is `models/intake_model/seed.json`. Besides the story map /
brief / moodboard, the seed now carries display/runtime data:

- `questionBanks` — three separate banks (`simple` / `normal` / `advanced`),
  the depth choice in the first chat message picks one;
- `statuses` — pipeline status per generated story id (`s-<n>`), feeding the
  live map's status dots and rollups (absent = `pending`);
- `files` — the files rail view's generated-project list with badges;
- `state` — the interview's initial state (depth, answers, generated,
  approved, approvedVersion, currentVersion); the facade clones it into the
  session and mutates the clone. Post-approval answer edits bump
  `currentVersion`; the "changed since approval" badge shows while
  `approvedVersion ≠ currentVersion`.

Regenerate: `node designs/appbox/models/intake_model/generate.mjs`

## 4. Session state

All ephemeral UI state lives under `sessionData.intake` (`interview`,
composer `extra`, `current` artifact per surface, `railView` per surface,
`msgSeq`) — no collision with other facades' session keys.
