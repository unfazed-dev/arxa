# Integration — design tab surfaces (design.prototype / design.chat / design.freeze)

Everything below is owned by the integrator; nothing in the design surface
directory touches shared files.

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

Routes added (11):

| method | path | handler | surface |
|---|---|---|---|
| GET | `/design` | prototype.page | design.prototype (tab root) |
| GET | `/design/rail` | prototype.rail | rail epic filter fragment |
| GET | `/design/screen/:id` | prototype.screen | canvas swap (`?bar=open` opens stage bar) |
| GET | `/design/bar/:id` | prototype.bar | stage bar toggle (`?state=open|fab`) |
| POST | `/design/screen/:id/messages` | prototype.askScreen | artboard-scoped thread |
| GET | `/design/chat` | chat.page | design.chat (`?screen=<id>` deep-link, `?screen=none` clears context) |
| GET | `/design/chat/screen/:id` | chat.select | thread swap + strip re-dim |
| POST | `/design/chat/screen/:id/messages` | chat.send | scoped message → reply + checkpoint |
| POST | `/design/chat/screen/:id/revert/:cp` | chat.revert | one-tap checkpoint revert |
| GET | `/design/freeze` | freeze.page | design.freeze |
| POST | `/design/freeze/recheck` | freeze.recheck | drift recheck fragment + toast |

## 2. Stylesheet — `designs/appbox/ui/common/base.html`

Add after the `app.css` link:

```html
<link rel="stylesheet" href="/assets/css/design.css">
```

## 3. Shell nav (optional) — `designs/appbox/ui/views/main_shell/main_shell_view.html`

The design views render with `activeTab: 'design'`; the shell nav currently
has no Design tab. To add one:

```html
<a class="shell-tab {{ 'is-active' if activeTab == 'design' }}" href="/design">Design</a>
```

The pages work without it (timeline links + direct URLs), the tab just won't
be highlighted in the nav.

## Notes for the integrator

- Session state is namespaced under `sessionData.design` — no collision with
  build (`barOpenFor`, `threads`, …) or intake keys.
- The timeline links on all three design pages point to `/design`,
  `/design/chat`, `/design/freeze`; brief/moodboard items render as non-links
  until the intake surfaces land (their hrefs can be filled then).
- Fixture: `models/design_model/run.json` is generated — edit
  `models/design_model/seed.json` and re-run `node generate.mjs` there.
