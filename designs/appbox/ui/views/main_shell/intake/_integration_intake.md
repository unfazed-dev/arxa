# Intake surfaces — integration notes

Three surfaces, all following the build/loop rail + canvas + stage-bar pattern:

| surface | route (tab root) | canvas artifacts |
|---|---|---|
| `intake.mapping` Story Mapping | `/intake` | `map/full` · `map/priorities` · `map/releases` · `story/:id` |
| `intake.brief` Design Brief | `/intake/brief` | `doc/full` · `doc/surfaces` |
| `intake.moodboard` Moodboard | `/intake/moodboard` | `gallery/all` · `gallery/:boardId` · `shot/:shotId` |

## 1. Wire the routes (`app.routes.js`)

`ui/views/main_shell/intake/routes.intake.js` exports the same
`[method, path, handler]` array shape as `app.routes.js`. Wire it:

```js
import intakeRoutes from './ui/views/main_shell/intake/routes.intake.js';

export default [
  ['GET', '/', mainShell.page],
  ...intakeRoutes,
  // ...existing build/workspace/prefs routes
];
```

Also update `tabRoots.intake` from `'/'` to `'/intake'` (mapping is the tab's
landing surface).

## 2. Link the stylesheet

`assets/css/intake.css` holds all intake-specific styles (MoSCoW chips, map
grid, brief document, moodboard gallery, intake rail-card type badges).
`app.css` is untouched. Add to `ui/common/base.html` after the app.css link:

```html
<link rel="stylesheet" href="/assets/css/intake.css">
```

## 3. Shell nav tab

The three views render with `activeTab: 'intake'`. Add an Intake tab to
`ui/views/main_shell/main_shell_view.html`:

```html
<a class="shell-tab {{ 'is-active' if activeTab == 'intake' }}" href="/intake">Intake</a>
```

## 4. Regenerating data

`models/intake_model/intake.json` is generated — never hand-edit.
Source of truth is `models/intake_model/seed.json` (story map verbatim from
`docs/design/story-map.json`; brief inventory from `docs/design/brief.md`;
moodboard curation from `docs/moodboards/`). Regenerate:

```sh
node designs/appbox/models/intake_model/generate.mjs
```

Moodboard screenshots are copied (not linked) from `docs/moodboards/shots/`
into `assets/images/moodboard/<board>/`; the seed's `shot.file` names must
match files there.

## 5. Session state

All ephemeral UI state lives under `sessionData.intake` (threads, bar open
state, current artifact per surface, composer extras, rail filters) — no
collision with the build facade's flat session keys.
