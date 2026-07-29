# Integration — design tab surfaces (design.prototype / design.chat / design.freeze)

Everything below is owned by the integrator; nothing in the design surface
directory touches shared files.

## Layout contract this tab codes against

- **Shell**: the timeline renders in `{% block bottombar %}` (the bottom bar;
  the old top strip is gone). All three design views fill that block.
- **Chat stage**: `ui/common/chat_stage.html` (landed) — used as
  `{% call cs.wrap({ eyebrow, docked, collapseHref }) %}…{% endcall %}` with
  `{{ cs.ctxStrip(c.strip) }}` rendered by the caller directly over the
  composer. The strip is the pinned-screens filmstrip:
  `strip: [{ id, label, tone, src, removeHref }]` — `src` iframes the
  screen's stub render; tones come from chat.css's palette
  (`cyan | violet | olive | amber`) plus the design-tab extension in
  viewer.css (`blue | ember`). Each thumb's × hx-gets `removeHref` and swaps
  `#stage-layout` **outerHTML** — the same contract the filmstrip/artboard
  pins and the composers use, and why `stageSwap` fragments render the
  `#stage-layout` container itself. `collapseHref` is per-surface
  (`{base}/close`): it unpins every screen and recenters the chat
  (`d.chatCentered`; any later pin re-docks). The × and close routes are
  scoped to the rendered surface (`/design/chat/*` vs `/design/freeze/*`) so
  a freeze swap never returns the prototype stage.
- **Stage container**: `#stage-layout` wraps chat + canvas. Its flex base and
  `.is-docked .canvas` behaviour come from build.css; the design views add
  `is-docked` to the container when an artifact is open.
- **Multi-view rail**: `ui/common/rail_views.html` `mv.frame` (left side).
  The design registry is screens / artifacts / files; view hrefs
  (`/design/rail/:view`) swap `#rail-left-body` — the id `rail_views.frame`
  owns.

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

`tabRoots.design` is already `'/design'` — no change needed there.

Routes (15):

| method | path | handler | purpose |
|---|---|---|---|
| GET | `/design` | prototype.page | design stage; chat + draft-all offer (`?screen=<id>` deep-pins a chip) |
| GET | `/design/rail` | prototype.rail | screens-view epic filter fragment |
| GET | `/design/rail/:view` | prototype.railView | rail carousel body swap (screens / artifacts / files) |
| GET | `/design/viewer` | prototype.viewer | viewer toolbar acts (bg/os/mode), swaps `#design-viewer` |
| GET | `/design/screen/:id` | prototype.screen | legacy artboard deep-link → pins context, swaps stage |
| GET | `/design/chat` | chat.page | retired Screen Chat, re-skinned onto the stage (`?screen=<id>`/`none`) |
| POST | `/design/chat/messages` | chat.send | the one composer: `draft-all` / `approve` / refine |
| GET | `/design/chat/context/:id` | chat.context | context-chip toggle (`?state=toggle\|on\|off`) — filmstrip, artboard pin, rail card |
| GET | `/design/chat/screen/:id` | chat.select | legacy per-screen pick → pins the chip, swaps stage |
| POST | `/design/chat/screen/:id/messages` | chat.send | legacy alias: pins its screen, then sends |
| POST | `/design/chat/screen/:id/revert/:cp` | chat.revert | one-tap checkpoint revert + toast |
| GET | `/design/freeze` | freeze.page | freeze & trace stage + approval card |
| POST | `/design/freeze/messages` | freeze.send | freeze chat; preset `approve` signs the manifest |
| POST | `/design/freeze/recheck` | freeze.recheck | drift recheck fragment + toast |

Dropped from the old table: `GET /design/bar/:id` and the stage-bar
`POST /design/screen/:id/messages` — the stage bar is gone (single input
path: no text inputs outside the chat).

## 2. Stylesheet — `designs/appbox/ui/common/base.html`

Already links `design.css` and `viewer.css` — no change needed.

## 3. Shell nav (optional) — `designs/appbox/ui/views/main_shell/main_shell_view.html`

The design views render with `activeTab: 'design'`; add a Design tab to the
shell nav if it isn't there yet:

```html
<a class="shell-tab {{ 'is-active' if activeTab == 'design' }}" href="/design">Design</a>
```

## Notes for the integrator

- Session state is namespaced under `sessionData.design` (`drafted`,
  `context`, `designThread`, `chatCheckpoints`, `reverted`, `viewer`,
  `railFilter`, `railView`, `approved`, `driftRechecks`) — no collision with
  build/intake keys. `barOpenFor`, per-screen `threads`/`chatThreads` and the
  `chatScreen` key are retired.
- The flow: `/design` opens on the chat (centered, `docked:false`) with the
  draft-all offer; the quick-reply `draft all 11 surfaces` (preset value
  `draft-all`) sets `drafted` and the board-mode canvas appears with the chat
  docked. Context pins toggle via `/design/chat/context/:id`; pinned screens
  get `.ctx-<tone>` outlines on the canvas + `in context` tags, non-context
  artboards dim (only while at least one pin exists).
- The manifest approval is seeded state (`approval.state` in
  `models/design_model/seed.json`); the session starts from it and the freeze
  chat's `approve the manifest` quick-reply (preset value `approve`) flips it
  idempotently. Seed it `pending` to demo the locked-Build state.
- Fixture: `models/design_model/run.json` is generated — edit
  `models/design_model/seed.json` and re-run `node generate.mjs` there.
- `ui/common/design_viewer.html` gained board mode + `v.contextBase`; single
  and rungs modes are unchanged for the build evidence canvas.
