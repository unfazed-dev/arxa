# Provenance-routed text editing + the 4-font menu (Increment 4)

Status: font layer landed (`a17a393`); seed/ARB source windows landed; router pending.

## 1. The seed determination (the coordinator's stop condition)

**Verdict: seed-backed text exists, is user-visible, and the seed write branch is
exercisable. The documented "untestable branch" stop condition does NOT trigger.**

Evidence, re-runnable:

```sh
find ~/.appbox/projects/portalo -regex '.*/models/[^/]*/[^/]*_seed\.[A-Za-z0-9-]*\.json'
# design/models/design_model/design_seed.{en,pl,qps-ploc}.json   (3 locales)
```

portalo ships 12 surfaces, 2 ARB files, and 3 localized seeds. The seed carries
human-visible copy, not just config:

| seed path | value |
|---|---|
| `run.project` | `"Portalo"` |
| `run.brief` | `"Portalo — a design-forward ecommerce app…"` |
| `run.stateLabel` | `"Frozen — manifest frz_9c41e2"` |
| `screens.N.label` | `"Splash"`, `"Startup"`, … |
| `screens.N.summary` / `.summaryPlain` | full sentences |

`inc5-portalo` has the identical layout; `foxglove-demo` has no design/ tree at
all and is the empty-project case the router must tolerate.

### The subtlety the router has to respect

Surfaces do **not** name seed keys. Grepping portalo's surface partials for
bindings yields only loop variables — `{{ next.to }}`, `{{ pqs }}`, `{{ tab.id }}`.
The seed reaches the DOM through the studio's viewmodels/facades, which load it
and pass rows into templates.

Consequence: **provenance for a rendered string cannot be recovered by parsing
the surface template.** The router must resolve it by locating the string's
origin in the loaded data (seed value lookup / the viewmodel row that produced
it), not by reading the partial. A template-parsing router would classify every
seed-backed string as "hardcoded in surface" and write to the wrong file.

### Dead end recorded

`renderProjectSurface` does not exist in this repo. It was a hypothesized symbol
of mine; several searches chased it. Project surfaces are not rendered through a
server-side context map — the design server prefetches them as *templates* plus
*fixtures* and the client assembles them. Do not re-chase this name.

## 2. Why the three write targets each need a raw-source window

`appboxd/lib/design_server/worker.dart` (~L190–246). The prefetch already served
parsed JSON at `/project/<rel>`; that cannot be the edit target, because
re-serialising a decoded map reorders keys and drops the `@`-metadata siblings an
ARB carries. So each provenance class gets a read-only raw window under
`/project-src/` plus an index (fs_shim has no `readdir`, so the list itself must
be a fixture):

- `design/surfaces/**.html` → `surfaceSrcIndex` → `project-src/index.json`
- `design/l10n/*.arb` → `arbSrcIndex` → `project-src/l10n-index.json`
- `**/models/*/*_seed.<locale>.json` → `seedSrcIndex` → `project-src/seed-index.json`

Separate indices, not extra members of `index.json`: that file is already an
array the widget manager consumes, and a project may ship any locale set
(`app_qps-ploc.arb` exists in the studio, not in portalo) — so the editor reports
the locales it **found** rather than guessing names.

Seeds are matched by the `_seed.<locale>` basename, not by "json under models/".
`theme.json` and `fonts.json` are SSOT config files in that same directory; a
router that offered them as text-edit targets would propose rewriting the accent
palette when the user retitles a card.

Writes still go through `/__project_write`; the watcher re-prefetches (~200ms)
like every other project edit.

## 3. The font menu

`models/fonts.json` is the SSOT for which families exist (4: `lexend`, `grotesk`,
`lora`, `mono`); `assets/css/fonts.css` is its CSS projection and now the only
place a `@font-face` is declared — Lexend's six blocks moved out of `app.css`.

The menu works through four variables rather than restating `font-family` per
component, because `app.css` hardcoded the family a dozen times (`'Lexend Deca'`
on labels, `'Lexend Giga'` on display type). A bare `[data-font]` rule would have
re-skinned body copy and left every heading and chip on Lexend.

    --font-ui   --font-display   --font-label   --font-mono

Verified: `:root` and all four `#app[data-font=…]` blocks set **all four**
variables, so no family falls back to Times.

`[data-font]` sits on `#app` — the element already carrying `data-theme` and
`data-accent`: one token scope, one specificity model. `body` keeps a literal
Lexend stack as the pre-boot fallback; it is the one element outside `#app` and
so cannot read a variable set on it.

**Deliberately not built:** a `fonts.css` generator mirroring
`services/theme_tokens.js`. `theme.css` is pure derivation from `theme.json`;
`fonts.css` is not — its `unicode-range` strings and design rationale are not in
`fonts.json`, so generating it would mean inventing SSOT data and embedding prose
in a template literal.

## 4. Remaining

1. `services/font_tokens.js` — **reader only**: `fonts()`, `fontIds()`,
   `defaultFont()`. Must copy `theme_tokens.js`'s worker constraints verbatim:
   `node:fs` only (no `node:url`/`node:path` — the worker's import map shims only
   `node:fs`, exporting just `readFileSync`/`existsSync`), and read per call — a
   module-load cache would pin the first render's value for the process lifetime.
2. `prefs_viewmodel.js` — `font` handler, allowlist = `fontIds()`, mirroring the
   existing `accent` handler (refresh-exempt).
3. `data-font` on `#app` in **both** `ui/common/base.html` and
   `ui/views/main_shell/build/loop/screen_stub_view.html`.
4. The ARB/seed/surface router, honouring §1's constraint.
