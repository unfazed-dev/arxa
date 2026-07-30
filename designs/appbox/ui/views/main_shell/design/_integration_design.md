# Integration — design tab surfaces (design.prototype / design.chat / design.freeze)

Everything below is owned by the integrator; nothing in the design surface
directory touches shared files.

## Layout contract this tab codes against

- **Shell**: the timeline renders in `{% block bottombar %}` (the footer
  panel `#panel-footer`). All three design views fill that block. In the
  design shell the footer timeline carries the design sub-steps (artboards →
  inspect · fine-tune → approval → freeze) with live refinement state from
  the facade (`timeline(d, L, t)`).
- **Panels**: every stage interaction swaps `#panels` **outerHTML** — the
  three content panels are one swap unit: the activity panel
  (`ui/common/panel_views.html` `pv.frame`, side left), the main panel
  (`#panel-main`, filled per surface), and the permanent composer panel
  (`ui/common/composer_panel.html` `cp.frame`). The retired two-state chat
  (is-centered/is-docked), the close routes and `collapseHref` are gone —
  the composer is single-state and always mounted.
- **Composer**: the shared card `ui/common/composer.html` (`cm.field`) —
  the context tray on top, a borderless textarea, an action bar below
  (+ suggestions, LLM model menu, send). Model picks hx-get
  `{base}/model/:id` and mutate `sessionData.agent.model` via
  services/facades/agent_menus.js. The tray holds the pinned-screens
  filmstrip: it auto-expands on pin (`d.trayOpen = true` in `pin()`), its
  head row is a checkbox whose `change` hx-gets `{base}/tray?state=toggle`
  (answered 204 — the checkbox flips and animates locally; the route only
  mirrors it), and the height animation is `grid-template-rows: 0fr → 1fr`
  with a reduced-motion-gated transition — visible both ways.
- **Activity panel**: `pv.frame` (left side). The design registry is
  screens / artifacts / files; view hrefs (`/design/panel/:view`) swap
  `#panel-left-body` — the id `panel_views.frame` owns. The files view's
  rows open in the main panel (`/design/file?path=`).
- **Main panel**: `#panel-main`. The artboards (flow tiles — the only
  viewer mode; the prototype mode's device-chrome preview is retired) fill
  it by default; a file row replaces them with the file in its server-picked
  render mode until `?file=none`. Compact/medium rungs show one content
  panel at a time under the panel bar (`?panel=activity|main|composer`,
  `mp.panelBar`).
- **Viewer**: `ui/common/design_viewer.html` `dv.designViewer(c.viewer)` —
  flow tiles only. Controller acts (`/design/viewer?bg=/inspect=/panel=`)
  swap `#design-viewer`. `v.contextBase` enables the tile pins.

## 1. Routes — `designs/appbox/app.routes.js`

Import the design route table and spread it into the default export:

```js
import designRoutes from './ui/views/main_shell/design/routes.design.js';

export default [
  ['GET', '/', mainShell.page],
  ...designRoutes,
  // ...existing build/workspace/prefs routes
];
```

`shellRoots.design` is already `'/design'` — no change needed there.

Routes (18):

| method | path | handler | purpose |
|---|---|---|---|
| GET | `/design` | prototype.page | design stage: artboards + composer (`?screen=<id>` deep-pins a chip, `?file=` deep-links the main panel) |
| GET | `/design/panel` | prototype.panel | screens-view epic filter fragment |
| GET | `/design/panel/:view` | prototype.panelView | activity panel body swap (screens / artifacts / files) |
| GET | `/design/panel/size/:side/:size` | prototype.panelSize | s/m/l width steps |
| POST | `/design/panel/size/:side` | prototype.panelSizePx | drag-handle px width |
| GET | `/design/file` | prototype.file | file row → main panel render mode fragment |
| GET | `/design/viewer` | prototype.viewer | viewer controller acts (bg/inspect/panel), swaps `#design-viewer` |
| GET | `/design/screen/:id` | prototype.screen | legacy artboard deep-link → pins context, swaps panels |
| POST | `/design/layout/artboard/:id` | prototype.artboardLayout | flow tile drag persist |
| POST | `/design/undo/:stack` / `/design/redo/:stack` | prototype.undo/redo | canvas + chat stacks |
| GET | `/design/chat` | chat.page | the one design chat (`?screen=<id>`/`none`) |
| POST | `/design/chat/messages` | chat.send | the one composer: `approve` / refine |
| GET | `/design/chat/context/:id` | chat.context | context-chip toggle (`?state=toggle\|on\|off`) |
| POST | `/design/chat/context/element` | chat.elementContext | inspect.js element pin |
| GET | `/design/chat/context/element/remove` | chat.elementContextRemove | element chip × |
| POST | `/design/chat/context/bulk` | chat.bulkContext | marquee bulk pin |
| GET | `/design/chat/screen/:id` | chat.select | legacy per-screen pick → pins the chip |
| POST | `/design/chat/screen/:id/messages` | chat.send | legacy alias: pins its screen, then sends |
| POST | `/design/chat/screen/:id/revert/:cp` | chat.revert | one-tap checkpoint revert + toast |
| GET | `/design/chat/model/:id` / `/design/chat/tray` | chat.model / chat.tray | composer chrome |
| GET | `/design/freeze` | freeze.page | freeze & trace stage + approval card |
| GET | `/design/freeze/file` | freeze.file | file row → main panel render mode fragment |
| POST | `/design/freeze/messages` | freeze.send | freeze chat; preset `approve` signs the manifest |
| POST | `/design/freeze/recheck` | freeze.recheck | drift recheck fragment + toast |
| GET | `/design/freeze/context/:id` | freeze.context | filmstrip unpin on the freeze surface |
| GET | `/design/freeze/model/:id` / `/design/freeze/tray` | freeze.model / freeze.tray | composer chrome |

Dropped with the panel refactor: `/design/chat/close`, `/design/freeze/close`
(the composer is permanent — there is nothing to close).

## 2. Stylesheet — `designs/appbox/ui/common/base.html`

Already links `design.css` and `viewer.css` — no change needed.

## 3. Shell nav (optional) — `designs/appbox/ui/views/main_shell/main_shell_view.html`

The design views render with `activeShell: 'design'`; add a Design destination to the
shell nav if it isn't there yet:

```html
<a class="shell-link {{ 'is-active' if activeShell == 'design' }}" href="/design">Design</a>
```

## Notes for the integrator

- Session state is namespaced under `sessionData.design` (`drafted`,
  `context`, `designThread`, `chatCheckpoints`, `reverted`, `viewer`,
  `activityFilter`, `activityView`, `panelSize`, `panelSizePx`, `currentFile`,
  `panel`, `approved`, `driftRechecks`) — no collision with build/intake
  keys. `barOpenFor`, per-screen `threads`/`chatThreads`, `chatScreen` and
  `chatCentered` are retired.
- The flow: `/design` opens directly on the artboards with the composer
  panel on the right — intake already generated the design, so there is no
  draft-all gate (`drafted` defaults true). Context pins toggle via
  `/design/chat/context/:id`; pinned screens get `.ctx-<tone>` outlines on
  the canvas + `in context` tags, non-context artboards dim (only while at
  least one pin exists).
- The manifest approval is seeded state (`approval.state` in
  `models/design_model/seed.json`); the session starts from it and the freeze
  chat's `approve the manifest` quick-reply (preset value `approve`) flips it
  idempotently. Seed it `pending` to demo the locked-Build state.
- Fixture: `models/design_model/run.json` is generated — edit
  `models/design_model/seed.json` and re-run `node generate.mjs` there.
- The design viewer is flow-only; the build evidence canvas shares it as a
  read-only static canvas (`v.static`, no pins/drag).
