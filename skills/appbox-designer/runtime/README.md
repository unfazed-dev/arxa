# appbox-designer Runtime

The shared server for every Artifact (ADR-0001). One implementation; artifacts
are pure MVVM content (ADR-0005) — views, viewmodels, fixtures, assets.

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
artifact JS (viewmodels, TSX views) executes in a headless-Chrome worker
tab driven over CDP. Edits anywhere in the artifact (views, l10n,
fixtures, routes, assets) re-import the artifact modules cache-busted in the
same worker tab — no manual relaunch, no stale views. Sessions and
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
│   ├── common/base.tsx           # root layout component: boilerplate head, boost, toasts
│   └── views/<shell>_shell/
│       ├── <shell>_shell_view.tsx
│       └── <surface>/
│           ├── <surface>_view.tsx        # page (default export) + its Named Fragments (named exports)
│           └── <surface>_viewmodel.js    # context builders + handlers
└── assets/{css,fonts,images,media}/      # served at /assets/
```

Consumed design-system copies live in `_ds/<slug>/` at the artifact root
(`appbox design ds-import`) and are served at `/_ds/` — wire their CSS
into `ui/common/base.tsx` per `built-in-skills/use-design-system.md`. The
React `_ds_bundle.js` never loads in an artifact (zero-custom-JS contract);
components are recreated as TSX components.

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
| `h.render(c, view, ctx?, status?)` | render `ui/…/x_view.html` or `x_view.html#fragment`; cookie prefs are merged into the context automatically |
| `h.form(c)` | parsed POST body |
| `h.session(c)` | `{ id, data }` — in-memory session store |
| `h.prefs(c)` / `h.setPrefs(c, patch)` | small scalar prefs cookie (theme, accent, role) |
| `h.locale(c)` / `h.t(c)` | resolved request locale / a `t` bound to it (L10n below) |
| `h.timers.start/extend/remaining/stop` | server-held deadlines for load-polling timers |
| `h.noContent(c)` | 204 — mutation done, no swap |
| `h.stopPolling(c)` | 286 — cancel a poll |
| `h.refresh(c)` | `HX-Refresh` — full reload (theme changes) |
| `h.location(c, url)` | `HX-Location` — client-side nav (use instead of 3xx) |

## Views (TSX / hono/jsx)

Views are **TSX components** rendered by hono/jsx, bundled by esbuild into a
self-contained render module at server boot (and re-bundled on hot reload).
There is no template language: composition is component imports and
`children`, inheritance is gone, and every value is a JS expression.

- A surface's view file is `<surface>_view.tsx`. Its **default export** is the
  page component; **named PascalCase exports** are the surface's Named
  Fragments.
- **ViewRefs keep the `.html` name for registry parity.** Viewmodels render
  `h.render(c, 'ui/views/main_shell/home/home_view.html', ctx)` and
  `h.render(c, 'ui/views/main_shell/home/home_view.html#listSwap', ctx)` —
  the generated render registry (`generateRenderTsx`, appboxd/lib/
  design_tools.dart) maps `x_view.html` → the `.tsx` file's default export,
  and `x_view.html#listSwap` → the named export `ListSwap` (the fragment name
  is the export's name with a lowercase first letter).
- Every component receives the **context bag as its single props object**:
  what the viewmodel passed, plus the server-merged `{ prefs, locale,
  locales, t }`. Fragments get the same bag the viewmodel handed to
  `h.render` — nothing is captured from an outer render.
- Pages wrap in their shell the way hello-hda does: the page component
  renders `<MainShell …>{children}</MainShell>`, the shell renders
  `<Base …>`, and `Base` emits `{raw('<!doctype html>')}` + `<html>`.
- **Autoescape is on by default** (hono/jsx escapes all text and attribute
  values — the nunjucks autoescape equivalent). Trusted HTML opts out with
  `raw(...)` from `hono/utils/html`; element content can use
  `dangerouslySetInnerHTML={{ __html }}`. Never `raw()` user data.
- Shared cross-surface fragments are `_name.tsx` widgets placed per the
  two-tier placement law (`references/showcase-anatomy.md` §2), pulled in with
  a plain `import { Card } from '../../widgets/common/base/_card.tsx'` (the `.tsx`
  extension is included) and rendered as `<Card card={card} />`. Parameters
  are explicit typed props — nothing reads a magic context bag. The drop-in
  starter library lives in `starter-partials/widgets/`.
- Control flow is JS: `{cond ? <A/> : <B/>}`, `{items.map((i) => …)}` (with
  `key` on dynamic lists). Never guard on a bare number — `{count && …}`
  renders a literal `0`; write `{count > 0 && …}`.
- hono/jsx dialect: `class=` (not `className`), `for=`, boolean attrs as
  `hidden={true}` / `disabled={expr}`; htmx attributes stay plain strings
  (`hx-post="/x" hx-swap="none"`); dynamic attributes use braces; an
  attribute whose name contains a colon (`hx-status:422`) needs a spread —
  `{...{ 'hx-status:422': '{}' }}`.

## Icons (`<Icon>` component)

The full Lucide set (ISC, ~2000 glyphs) is vendored at
`runtime/vendor/lucide/icons/<kebab-name>.svg` by `appbox design vendor-fetch` and
inlined **server-side** via the `Icon` component — no client JS, and no SRI:
nothing is served to the browser as a file, so there is no fetched
subresource to pin (the manifest records the npm tarball hash instead).

```tsx
import Icon from '../../../../runtime/icon.tsx';  // relative to the artifact root's runtime/icon.tsx

<Icon name="arrow-left" />                                {/* 24px, decorative */}
<Icon name="search" size={20} cls="my-ic" />              {/* size + class */}
<Icon name="trash-2" label="Delete" strokeWidth={1.5} />  {/* accessible img */}
```

The design server bundles a browser-compatible `runtime/icon.tsx` (backed by
the prefetched `__icons` map); the ejected app ships the same component
backed by the vendored set. Decorative by default (`aria-hidden` +
`focusable="false"`); with `label` it gets `role="img"`, `aria-label`, and a
`<title>`. Names are validated against `[a-z0-9-]+`; an unknown name renders
a visible dashed-square placeholder. Icons inherit `currentColor` — style
them with CSS `color`.

## Boilerplate head (copy from `examples/hello-hda/ui/common/base.tsx`)

Every artifact's `base.tsx` carries: the vendored htmx 4 script tag (blocking,
with SRI), the deferred island tags — the named islands of ADR-0002's amendments, loaded from
/assets/vendor/ as screens need them, and the enforcement meta config:

```tsx
<meta name="htmx-config" content='{"transitions":true,"implicitInheritance":true,"noSwap":[204,304,"4xx","5xx"]}' />
```

htmx 4 notes: `transitions` is the renamed `globalViewTransitions`;
`implicitInheritance` restores v2's attribute inheritance (v4 turns it off —
without it the body's hx-boost/hx-sync reach nothing); `noSwap` restates the
old responseHandling blackout — 4xx/5xx never clobber a panel. v4 validates
forms with `reportValidity()` natively (`reportValidityOfForms` is gone), and
`allowEval` has no v4 equivalent — the eval switch is `htmx.initSecurity()`,
custom JS this artifact bans (ADR-0002).

Body: `<body hx-boost="true" hx-sync="this:replace" …>`. `hx-ext` does not
exist in htmx 4 (the head-support/preload extensions are gone; see the
studio's base.tsx header comment for the full v2→v4 mapping).
A form that must swap a 422 validation response opts out of the 4xx blackout
with `{...{ 'hx-status:422': '{}' }}` on the form.

## State playbook quick recipes (ADR-0004)

- **Theme/accent/role**: POST → `h.setPrefs(c, {accent:'lagoon'})` → `h.refresh(c)`;
  render CSS vars on an in-body wrapper (`#app`), never on `<body>`/`<html>`
  attributes (they don't update under boosted swaps).
- **Language**: built-in `GET/POST /prefs/lang?lang=<locale>` does the same
  dance (setPrefs + refresh/302); the switcher is plain anchors
  (`ui/views/main_shell/shared/widgets/lang_switcher.tsx` in hello-hda, see L10n below).
- **Countdown**: `hx-get="/timer/tick" hx-trigger="load delay:1s" hx-swap="outerHTML"`;
  each tick renders `timers.remaining(id)`; drop the trigger (or 286) at zero.
- **Toasts**: respond `hx-swap="none"` (or `HX-Reswap: none`) + an
  `hx-swap-oob="beforeend:#toasts"` fragment.
- **Validation errors**: return 422 + the re-rendered form (the
  `hx-status:422` escape above swaps it in place).

## L10n (i18n)

Optional per artifact. Chrome and surface strings live in catalogs, never
hardcoded in views: `l10n/app_<locale>.arb` — plain JSON (lines starting
`//` are stripped before parse; `@`-prefixed ARB metadata keys are ignored).
Every `app_<locale>.arb` on disk IS an available locale — writing
`app_qps-ploc.arb` registers `qps-ploc`. An artifact with no `l10n/` dir is
unaffected: `t()` passes the key through and the locale is always `en`.

```tsx
{t('home.title') as string}                     {/* pages render + fragments */}
{t('itemCount', { count: demoCount }) as string}  {/* {var} + ICU plural subset */}
```

- **`t` arrives in the context bag** — the server merges `{ prefs, locale,
  locales, t }` into every render context (rebound per render to the request
  locale), so Named Fragment components see it as a prop too. Views type it
  as `type TFn = (key: string, vars?: Record<string, unknown>) => unknown;`
  and cast results (`as string` — `t` returns `unknown`). ViewModels use
  `h.t(c)` for strings the context carries (nav labels) and `h.locale(c)` for
  the locale itself.
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
a `pl` catalog) → `'en'`. `base.tsx` sets `<html lang={locale}>`;
HTML responses carry `Vary: Accept-Language`.

**Switching** is built into the runtime (ADR-0004 prefs recipe — every
artifact, no route-table entry): `/prefs/lang?lang=<locale>` (GET or POST) does
`h.setPrefs(c, {lang})`, then `h.refresh(c)` for htmx-boosted requests or a
302 back to the Referer for plain navigation. The switcher is a plain-anchors
component — copy
`examples/hello-hda/ui/views/main_shell/shared/widgets/lang_switcher.tsx`
into the chrome and render `<LangSwitcher … />`.

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
views:
`<script>` tags that don't point at `/assets/vendor/`, `hx-on:*`, `js:`-prefixed
attributes, `[expr]` trigger filters. `appbox design lint` enforces it;
htmx 4 evaluates no attribute expressions at all (the v2 `allowEval:false`
switch has no v4 equivalent — see base.tsx's header comment).

Comments (`<!-- -->`, `{/* */}`, `//`) are stripped before matching, so writing down
*why* a rule exists cannot break the build — and a commented-out `<script>` is
not a script. Every rule is a pure selector; none reads an opt-out marker.
