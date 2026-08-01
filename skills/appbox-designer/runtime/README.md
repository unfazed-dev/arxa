# appbox-designer Runtime

The shared server for every Artifact (ADR-0001). One implementation; artifacts
are pure MVVM content (ADR-0005) — templates, viewmodels, fixtures, assets.

> **The server is the Dart design server now** (2026-07-31, commit 4f9c458):
> `appbox design serve` → `appboxd/lib/design_server.dart` (artifact JS runs
> in a headless-Chrome worker over CDP; Dart owns HTTP, routing, state, hot
> reload, and the pidfile registry). The Node runtime that used to live here
> (`serve.mjs`, `lib/*.mjs`, `lint.mjs`, `serve.test.mjs`, `eject.mjs`) is
> **retired — archived under `archives/tooling-pre-dart/`**; what remains in
> this directory is `vendor/` (the SRI-pinned client libraries artifacts load)
> and `ladder.json`. The process contract documented below is the Dart
> server's; it deliberately preserves the old runtime's observable semantics.

## Commands

```sh
appbox design serve <artifact-dir|design-name> [--port 4319] [--host 127.0.0.1] [--json] [--no-watch]
appbox design lint  <artifact-dir>                 # zero-custom-client-JS check
appbox design check-wiring <artifact-dir> <property>
#   fragments | mutations-posted | urls-resolve | targets-exist
appbox design pseudolocalize <artifact-dir>        # en → qps-ploc pseudo-locale
appbox design vendor-fetch                         # (re)vendor htmx + extensions
```

`serve` takes a path **or** a bare design name — `appbox-app` resolves to
`designs/appbox-app` — because anything offering "preview this prototype" has
a name, not a path.

It binds **127.0.0.1**. A prototype is unreleased client work and has no
business on the wifi; `--host 0.0.0.0` is still there for previewing on a
phone, and says so on stdout when you use it.

For a caller that spawns it (a UI preview button, a script):

```sh
appbox design serve appbox-app --port 0 --json
# {"url":"http://127.0.0.1:52953/","port":52953,"host":"127.0.0.1","pid":40311,"artifact":"/…/designs/appbox-app"}
```

`--port 0` takes any free port, so nothing collides when several prototypes run
at once, and `--json` prints one line **after the socket is listening** — read
it and the server is up, not merely spawned. The `port` reported is the one the
OS actually bound. Failures go to stderr as plain text and exit non-zero
(`69` port in use, `66` no such artifact, `64` bad usage); stdout stays empty,
so a parsed ready-record is never ambiguous.

**Hot reload is on by default.** The Dart design server is a single process;
artifact JS (viewmodels, Nunjucks views) executes in a headless-Chrome worker
tab driven over CDP. Edits anywhere in the artifact (templates, l10n,
fixtures, routes, assets) re-import the artifact modules cache-busted in the
same worker tab — no manual relaunch, no stale templates. Sessions and
server-side timers live in Dart state, so they ride out a reload. A viewmodel
exception becomes a 500, never a crashed server, so no crash-respawn
supervision is needed. Reload messages go to stderr; the stdout ready-record
is printed once.

**Ctrl+C stops every instance serving the same artifact**, including ones from
earlier terminals — instances are tracked as pidfiles under
`<system-temp>/appbox-designer-serve/` (one file per instance, so no shared
registry and no lock). **SIGTERM stops only the signalled instance** —
that is how a UI closing one preview leaves the others running. The ready
record's `pid` is the server (kill it to stop the server cleanly).

`--no-watch` serves with no watcher and no registry — the ejected
app's `appbox design serve . --no-watch` uses it; keep it for anything
productionized.

New artifacts start by copying `examples/hello-hda/` — it is the reference
implementation of everything below.

## Artifact tree

```
<artifact>/
├── serve.mjs                     # formerly `node serve.mjs` (archived) — now served via `appbox design serve <dir>`
├── app.routes.js                 # the URL inventory: [method, path, handler]
├── l10n/app_<locale>.arb         # string catalogs (add when i18n; en first)
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
(`appbox design ds-import`) and are served at `/_ds/` — wire their CSS
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
| `h.locale(c)` / `h.t(c)` | resolved request locale / a `t` bound to it (L10n below) |
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

## Icons (`icon()` global)

The full Lucide set (ISC, ~2000 glyphs) is vendored at
`runtime/vendor/lucide/icons/<kebab-name>.svg` by `appbox design vendor-fetch` and
inlined **server-side** via a Nunjucks global — no client JS, and no SRI:
nothing is served to the browser as a file, so there is no fetched
subresource to pin (the manifest records the npm tarball hash instead).

```njk
{{ icon('arrow-left') }}                                   {# 24px, decorative #}
{{ icon('search', {size: 20, cls: 'my-ic'}) }}             {# size + class #}
{{ icon('trash-2', {label: 'Delete', strokeWidth: 1.5}) }} {# accessible img #}
```

Decorative by default (`aria-hidden` + `focusable="false"`); with `label` it
gets `role="img"`, `aria-label`, and a `<title>`. Names are validated against
`[a-z0-9-]+` (path-traversal safe); an unknown name renders a visible
dashed-square placeholder and warns on the server console. Icons inherit
`currentColor` — style them with CSS `color`.

## Boilerplate head (copy from `examples/hello-hda/ui/common/base.html`)

Every artifact's `base.html` carries: the vendored htmx script tag (blocking,
with SRI), the extension tags, the deferred island tags — the named islands of ADR-0002's amendments, loaded from
/assets/vendor/ as screens need them, and the enforcement meta config:

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
- **Language**: built-in `GET/POST /prefs/lang?lang=<locale>` does the same
  dance (setPrefs + refresh/302); the switcher is plain anchors
  (`ui/common/_lang_switcher.html`, see L10n below).
- **Countdown**: `hx-get="/timer/tick" hx-trigger="load delay:1s" hx-swap="outerHTML"`;
  each tick renders `timers.remaining(id)`; drop the trigger (or 286) at zero.
- **Toasts**: respond `hx-swap="none"` (or `HX-Reswap: none`) + an
  `hx-swap-oob="beforeend:#toasts"` fragment.
- **Validation errors**: return 422 + the re-rendered form (the meta config
  swaps 422s).

## L10n (i18n)

Optional per artifact. Chrome and surface strings live in catalogs, never
hardcoded in templates: `l10n/app_<locale>.arb` — plain JSON (lines starting
`//` are stripped before parse; `@`-prefixed ARB metadata keys are ignored).
Every `app_<locale>.arb` on disk IS an available locale — writing
`app_qps-ploc.arb` registers `qps-ploc`. An artifact with no `l10n/` dir is
unaffected: `t()` passes the key through and the locale is always `en`.

```njk
{{ t('home.title') }}                        {# page renders + macros #}
{{ t('itemCount', {count: demoCount}) }}     {# {var} + ICU plural subset #}
```

- **`t` is a Nunjucks global** (rebound per render to the request locale — safe
  because renders are synchronous), so Named Fragment macros see it too.
  ViewModels use `h.t(c)` for strings the context carries (nav labels) and
  `h.locale(c)` for the locale itself.
- **Fallback chain**: active locale → `en` → the key literal. Jargon dimension:
  with level `plain`/`technical` (prefs key `jargon`), `t` tries
  `key+'Plain'`/`key+'Technical'` first, then the base key (base = balanced).
- **Values**: `{var}` interpolation (vars HTML-escaped; catalog text is
  authored and trusted) and the ICU plural subset
  `{count, plural, =0{…} one{…} few{…} many{…} other{…}}` — category selection
  via built-in `Intl.PluralRules`, zero deps. Polish works out of the box:
  1 → one, 2–4/22–24 → few, 0/5–21 → many.
- **Key parity across catalogs is a selftest check**, not a hope — a locale
  missing a key silently renders English otherwise.

**Locale resolution** (router middleware, merged into every render context as
`locale`; `locales` lists the catalogs): `?lang=` query → prefs cookie `lang` →
`Accept-Language` (q-factor order, exact then base-tag match — `pl-PL` matches
a `pl` catalog) → `'en'`. `base.html` sets `<html lang="{{ locale or 'en' }}">`;
HTML responses carry `Vary: Accept-Language`.

**Switching** is built into the runtime (ADR-0004 prefs recipe — every
artifact, no route-table entry): `/prefs/lang?lang=<locale>` (GET or POST) does
`h.setPrefs(c, {lang})`, then `h.refresh(c)` for htmx-boosted requests or a
302 back to the Referer for plain navigation. The switcher is plain anchors —
copy `examples/hello-hda/ui/common/_lang_switcher.html` into the chrome:

```njk
{% include "ui/common/_lang_switcher.html" %}
```

**Localized content** follows the data spine per locale: seeds
`<name>_seed.<locale>.json` (identical IDs/schema across locales) are the SSOT,
the generator emits `<name>_fixtures.<locale>.json` (never hand-edited,
`_generated_from` provenance kept), repositories take the locale and fall back
to `en`. `appbox design pseudolocalize <artifact-dir>` derives
`app_qps-ploc.arb` and `*_seed.qps-ploc.json` from the English SSOT (wrapped,
accented, ~35% padded — truncation and hardcoded strings become visible);
re-run the model generator afterwards.

## The no-JS contract (ADR-0002)

Allowed: the vendored libraries above, plus the named islands of ADR-0002's
amendments (first-party data-attribute islands and third-party declarative web
components, all vendored in runtime/vendor/). Banned anywhere in artifact
templates:
`<script>` tags that don't point at `/assets/vendor/`, `hx-on:*`, `js:`-prefixed
attributes, `[expr]` trigger filters. `appbox design lint` enforces it;
`allowEval:false` is the runtime backstop.

Comments (`<!-- -->`, `{# #}`) are stripped before matching, so writing down
*why* a rule exists cannot break the build — and a commented-out `<script>` is
not a script. Every rule is a pure selector; none reads an opt-out marker.
