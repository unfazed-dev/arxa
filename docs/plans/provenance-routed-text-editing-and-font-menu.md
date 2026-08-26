# Provenance-routed text editing + the 4-font menu (Increment 4)

Status: font layer landed (`a17a393`); seed/ARB source windows landed; router pending.

## 1. The seed determination (the coordinator's stop condition)

**Verdict: seed-backed text exists, is user-visible, and the seed write branch is
exercisable. The documented "untestable branch" stop condition does NOT trigger.**

Evidence, re-runnable:

```sh
find ~/.arxa/projects/portalo -regex '.*/models/[^/]*/[^/]*_seed\.[A-Za-z0-9-]*\.json'
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

`arxa/lib/design_server/worker.dart` (~L190–246). The prefetch already served
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

## 4. The router (`services/repositories/text_repository.js`)

Classifies a widget's copy before writing, because writing to the wrong file is
silent: the studio would show the edit (its own `/project-src/` key is updated
immediately) while the real owner kept the old string and the next build
reverted it.

| class | test | write target |
|---|---|---|
| `arb` | the element *is* `{{ t('k') }}`, **or** contains exactly one `t()` key | that key in `design/l10n/app_<locale>.arb` |
| `mixed` | two or more distinct `t()` keys | refused — which one did the user click? |
| `bound` | a lone `{{ a.b }}` binding | refused, with the seed list — see §1 |
| `literal` | no template syntax | the surface partial itself |

The "exactly one key" rule matters: most real widgets are
`{{ icon('user') }} {{ t('k') }}`. Measured on portalo's 26 widgets, whole-element
matching alone routed 6; adding the single-key rule routes **11**, leaves 13
genuinely ambiguous, 1 with no text, 1 literal.

ARB writes never re-serialise. `setArbValue` swaps only the value's own JSON
string literal by regex, re-escaped with `JSON.stringify` — verified against
portalo's real 84-key catalogue: key count, key order, and every other value
unchanged.

**The override case.** 57 of the 64 keys portalo's surfaces reference are in its
own catalogue; 7 (`app.brand`, `auth.continue`, `auth.email`, …) resolve from the
artifact's base catalogue, which worker.dart merges *under* the project. Editing
those means adding a project override. `addArbValue` does that, but only behind
an explicit `allowOverride` flag — otherwise a typo'd key would silently create a
dead entry. The default is a precise error naming the file and the reason.

`screensUsing()` is wrapped: a project with no intake registry still edits, since
that list is provenance commentary, not a write target.

### Not yet wired

The router is a repository with no route or view yet. Wiring it means a facade
method + a POST beside `setWidgetAttr` (`prototype_viewmodel.js:131` →
`design_facade.setWidgetAttr` → `widget_repository.setWidgetAttr`), which is the
exact shape to copy. The seed writer is deliberately absent — §1 shows the seed
key is not recoverable from the template, so it needs the viewmodel's value
lookup, not another regex.
