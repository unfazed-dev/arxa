# app-box-designer Runtime

The shared server for every Artifact (ADR-0001). One implementation; artifacts
are pure MVVM content (ADR-0005) — templates, viewmodels, fixtures, assets.

## Commands

```sh
node runtime/serve.mjs <artifact-dir|design-name> [--port 4319] [--host 127.0.0.1] [--json]
node runtime/lint.mjs  <artifact-dir>                 # zero-custom-client-JS check
node runtime/vendor/fetch.mjs                         # (re)vendor htmx + extensions
```

`serve` takes a path **or** a bare design name — `app-box-app` resolves to
`designs/app-box-app` — because anything offering "preview this prototype" has
a name, not a path.

It binds **127.0.0.1**. A prototype is unreleased client work and has no
business on the wifi; `--host 0.0.0.0` is still there for previewing on a
phone, and says so on stdout when you use it.

For a caller that spawns it (a UI preview button, a script):

```sh
node runtime/serve.mjs app-box-app --port 0 --json
# {"url":"http://127.0.0.1:52953/","port":52953,"host":"127.0.0.1","pid":40311,"artifact":"/…/designs/app-box-app"}
```

`--port 0` takes any free port, so nothing collides when several prototypes run
at once, and `--json` prints one line **after the socket is listening** — read
it and the server is up, not merely spawned. The `port` reported is the one the
OS actually bound. Failures go to stderr as plain text and exit non-zero
(`69` port in use, `66` no such artifact, `64` bad usage); stdout stays empty,
so a parsed ready-record is never ambiguous.

New artifacts start by copying `examples/hello-hda/` — it is the reference
implementation of everything below.

## Artifact tree

```
<artifact>/
├── app.routes.js                 # the URL inventory: [method, path, handler]
├── models/<domain>_model/…       # shapes + fixtures (add when needed)
├── services/{repositories,facades}/…
├── ui/
│   ├── common/base.html          # root layout: boilerplate head, boost, toasts
│   └── views/<shell>_shell/
│       ├── <shell>_shell_view.html
│       └── <surface>/
│           ├── <surface>_view.html       # page + its Named Fragments (macros)
│           └── <surface>_viewmodel.js    # context builders + handlers
└── assets/{css,fonts,images,media}/      # served at /assets/
```

Consumed design-system copies live in `_ds/<slug>/` at the artifact root
(`agents/import-design-system.mjs`) and are served at `/_ds/` — wire their CSS
into `ui/common/base.html` per `built-in-skills/use-design-system.md`. The
React `_ds_bundle.js` never loads in an artifact (zero-custom-JS contract);
components are recreated as Nunjucks partials.

## Route table

`app.routes.js` default-exports an array of `[method, path, handler]`:

```js
import * as home from './ui/views/main_shell/home/home_viewmodel.js';

export default [
  ['GET', '/', home.page],
  ['POST', '/prefs/accent', home.setAccent],
];
```

## ViewModel handlers

Every handler is `(c, h) => Response`. `c` is the Hono context; `h` is the
Runtime helper object:

| helper | use |
|---|---|
| `h.render(c, view, ctx?, status?)` | render `ui/…/x_view.html` or `x_view.html#macro`; cookie prefs are merged into the context automatically |
| `h.form(c)` | parsed POST body |
| `h.session(c)` | `{ id, data }` — in-memory session store |
| `h.prefs(c)` / `h.setPrefs(c, patch)` | small scalar prefs cookie (theme, accent, role) |
| `h.timers.start/extend/remaining/stop` | server-held deadlines for load-polling timers |
| `h.noContent(c)` | 204 — mutation done, no swap |
| `h.stopPolling(c)` | 286 — cancel a poll |
| `h.refresh(c)` | `HX-Refresh` — full reload (theme changes) |
| `h.location(c, url)` | `HX-Location` — client-side nav (use instead of 3xx) |

## Templates (Nunjucks)

- Pages `{% extends %}` their shell, shells extend `ui/common/base.html`.
- A **Named Fragment** is a macro in the surface's view file, renderable alone
  via `view.html#macroName`. Macros take one argument — the context bag `c` —
  and pages call them as `{{ macroName(c) }}`.
- Shared cross-surface fragments are `_name.html` partials under
  `ui/widgets|dialogs|bottomsheets/`, pulled in with `{% include %}`.

## Boilerplate head (copy from `examples/hello-hda/ui/common/base.html`)

Every artifact's `base.html` carries: the vendored htmx script tag (blocking,
with SRI), the extension tags, and the enforcement meta config:

```html
<meta name="htmx-config" content='{"allowEval":false,"allowScriptTags":false,
"globalViewTransitions":true,"historyRestoreAsHxRequest":false,
"reportValidityOfForms":true,"responseHandling":[
 {"code":"204","swap":false},{"code":"[23]..","swap":true},
 {"code":"422","swap":true},{"code":"[45]..","swap":false,"error":true},
 {"code":"...","swap":true}]}'>
```

Body: `<body hx-boost="true" hx-sync="this:replace" hx-ext="head-support,preload">`.

## State playbook quick recipes (ADR-0004)

- **Theme/accent/role**: POST → `h.setPrefs(c, {accent:'lagoon'})` → `h.refresh(c)`;
  render CSS vars on an in-body wrapper (`#app`), never on `<body>`/`<html>`
  attributes (they don't update under boosted swaps).
- **Countdown**: `hx-get="/timer/tick" hx-trigger="load delay:1s" hx-swap="outerHTML"`;
  each tick renders `timers.remaining(id)`; drop the trigger (or 286) at zero.
- **Toasts**: respond `hx-swap="none"` (or `HX-Reswap: none`) + an
  `hx-swap-oob="beforeend:#toasts"` fragment.
- **Validation errors**: return 422 + the re-rendered form (the meta config
  swaps 422s).

## The no-JS contract (ADR-0002)

Allowed: the vendored libraries above. Banned anywhere in artifact templates:
`<script>` tags that don't point at `/assets/vendor/`, `hx-on:*`, `js:`-prefixed
attributes, `[expr]` trigger filters. `node runtime/lint.mjs` enforces it;
`allowEval:false` is the runtime backstop.

Comments (`<!-- -->`, `{# #}`) are stripped before matching, so writing down
*why* a rule exists cannot break the build — and a commented-out `<script>` is
not a script. Every rule is a pure selector; none reads an opt-out marker.
