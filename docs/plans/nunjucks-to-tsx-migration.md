# Nunjucks → hono/jsx Migration Plan

> **Status:** Draft — awaiting approval. The [eject-web-productionization agents
> agreement](../eject-web-productionization-agents.md) freezes the artifact contract
> (template format, lint rules). This plan unfreezes it. User has authorized full
> replace.

## Decision

Replace nunjucks with `hono/jsx` across both runtimes (Dart design server +
ejected Hono app). Templates become typed `.tsx` components. Zero client-side JS
contract preserved — hono/jsx renders to HTML strings on the server.

## Why

1. **Type safety**: every template is a typed function. The hand-written
   `nunjucks.d.ts`, `SafeString` casts, and `templates.js` loader complexity
   all disappear. Template errors surface at compile time.
2. **No preload.js**: TSX is compiled at build time. Workers don't need a
   runtime-bundled template blob. The dual-mode (fs/preload) branching in
   `templates.js`, `l10n.js`, and `helpers.js` vanishes.
3. **Editor support**: IntelliSense, go-to-definition, refactoring in `.tsx`
   files. Nunjucks templates are opaque strings to every tool.
4. **The JSDoc rung proved out**: `noImplicitAny: true` passes. TSX is the
   natural next step — full types, not annotations-on-untyped-code.

## Scope — what changes

### Template files (58 total)

| Artifact | `.html` files | Heaviest |
|---|---|---|
| hello-hda | 9 | `home_view.html` (islands, includes, i18n) |
| arxa-studio | 49 | `loop_view.html` (152 nunjucks tags), `design_viewer.html` (129) |

All become `.tsx`. The nunjucks construct → TSX mapping:

| Nunjucks | TSX |
|---|---|
| `{% extends "base.html" %}` + `{% block x %}` | `<Base>{children}</Base>` or layout props |
| `{% macro tick(c) %}` (Named Fragment) | `export function Tick(props): JSX.Element` |
| `view.html#tick` dispatch | dynamic import of the component by name |
| `{{ t('key', {count: n}) }}` | `t('key', {count: n})` — same function, returns string |
| `{{ icon('name') }}` | `<Icon name="name" size={24} />` component |
| `{% include "partial.html" %}` | `<Partial {...props} />` |
| `{% set x = ... %}` | `const x = ...` |
| `{% for item in items %}` | `{items.map(item => ...)}` |
| `{% if cond %}` | `{cond && ...}` or ternary |
| Auto-escaping | JSX auto-escapes by default |
| `SafeString` | `dangerouslySetInnerHTML` (rare — only for pre-trusted SVG) |

### Runtime modules (eject)

**Deleted:**
- `runtime/templates.js` (nunjucks Environment, loaders, fragment dispatch)
- `runtime/nunjucks.d.ts` (ambient declaration)
- `runtime/types.d.ts` → slimmed (remove nunjucks refs, keep Context/Helpers/Prefs)
- `runtime/preload.js` generation in design_tools.dart (Workers compile TSX at build time)

**Replaced:**
- `runtime/templates.js` → `runtime/render.tsx` (hono/jsx renderer, component registry)
- `runtime/helpers.js` → updated `render()` to call the TSX renderer instead of nunjucks

**Unchanged:**
- `runtime/router.js` (route dispatch)
- `runtime/state.js`, `runtime/timers.js`, `runtime/realtime.js`
- `runtime/l10n.js` (the `t()` function — it already returns strings; SafeString wrapper removed)
- `runtime/forms.js`, `runtime/routes.js`

### Dart design server

**`worker_shim.js`** (267 lines) — the nunjucks environment setup is replaced:
- `nunjucks.Environment` + `prefetchedLoader` → hono/jsx component registry
- `templatesRender()` → component lookup + `renderToString()`
- The `{% import "file" as f %}{{ f.macro(c) }}` fragment dispatch → direct component call

**`worker_page.html`** — drop the nunjucks `<script>` tag. The TSX shim loads
pre-compiled components instead of template source strings.

**`_inject()` in `worker.dart`** — instead of injecting `.html` source strings,
inject compiled `.tsx` component modules (or compile-on-the-fly via esbuild in
the worker tab).

### Lint rules (frozen contract — user must authorize change)

The four ADR-0002 rules at `design_tools.dart:60-71` scan `.html` files. After
migration:
1. Templates are `.tsx`, not `.html` — the scan target changes
2. The zero-custom-JS contract still holds (hono/jsx renders server-side, ships
   zero client JS) — but the enforcement mechanism adapts
3. The `<script>` regex (rule 1) still applies to any remaining `.html` files
   (shells, includes that stay as HTML)
4. A new lint rule may be needed: "no `use client` directive" or equivalent to
   ensure TSX components don't ship client-side

### Dependencies

- **Removed from eject**: `nunjucks`
- **Added to eject**: `hono/jsx` (built into hono — no separate package needed)
- **Removed from Dart server**: `nunjucks.min.js` vendor file
- The `nunjucks` entries in `_packages` and the vendor manifest are removed

## Phases

### Phase A — TSX rendering infrastructure (no templates converted yet)

**Goal:** build the TSX rendering pipeline alongside nunjucks, prove it works
on one template, then convert the rest.

1. **`runtime/render.tsx`** — the TSX renderer module:
   - A `render(viewRef, ctx)` function that resolves a component by path and
     renders it with `hono/jsx`
   - A `renderFragment(viewRef, macroName, ctx)` function for Named Fragment
     dispatch (the `#macro` equivalent)
   - Component registry: a map from view path to component function

2. **Fragment dispatch design** — the critical risk:
   - Current: `env.renderString('{% import "file" as f %}{{ f.macro(c) }}', ctx)`
   - TSX: `import { Macro } from './file.tsx'; renderTostring(<Macro {...ctx} />)`
   - The viewmodel calls `h.render(c, 'timer_view.html#tick', ctx)`. The renderer
     splits on `#`, dynamically imports the component, calls it.
   - **Decision:** static registry (all components imported at boot) vs dynamic
     import (file-path → URL → import()). Static is simpler and the eject knows
     all templates at build time. **Go static.**

3. **`<Icon>` component** — replaces the `icon()` nunjucks global:
   - Props: `{ name: string, size?: number, cls?: string, label?: string, strokeWidth?: number }`
   - Reads from the same Lucide SVG set (bundled in preload for Workers, fs for node)
   - Returns `<svg>...</svg>` as JSX

4. **`<Base>` layout** — replaces `{% extends "base.html" %}`:
   - A component that wraps children with `<html>`, `<head>`, `<body>`
   - Accepts props: `{ title?: string, accent?: string, locale?: string }`

5. **Verify on ONE template** — convert `timer_view.html` → `timer_view.tsx`:
   - The `tick` macro becomes `export function Tick(props)`
   - The `/timer/tick` route renders `<Tick {...ctx} />`
   - htmx poll swaps the fragment — verify the HTML output is byte-identical
   - **This is the proof point. If the fragment HTML differs, stop and investigate.**

**Verification gate:**
- `timer_view.tsx` renders identical HTML to `timer_view.html`
- `arxa lens check` passes on the `/timer` route
- Pixel compare: 0.95+ vs the nunjucks-rendered golden

### Phase B — Convert all hello-hda templates (9 files)

Convert the remaining 8 templates. The 3-deep inheritance chain
(`base.html` → `main_shell_view.html` → leaf) becomes nested components.

Files in conversion order:
1. `ui/common/base.html` → `ui/common/base.tsx` (the `<Base>` layout)
2. `ui/views/main_shell/main_shell_view.html` → shell component wrapping `<Base>`
3. `ui/views/main_shell/home/home_view.html` → home page component
4. `ui/views/main_shell/timer/timer_view.html` → (done in Phase A)
5. `ui/views/main_shell/shared/widgets/_nav-rail.html` → `<NavRail>` component
6. `ui/views/main_shell/shared/widgets/_lang_switcher.html` → `<LangSwitcher>`
7. `ui/views/main_shell/shared/widgets/_bottom-nav.html` → `<BottomNav>`
8. `ui/views/main_shell/home/widgets/_list-row.html` → `<ListRow>`
9. `ui/views/main_shell/home/widgets/_form-field.html` → `<FormField>`

**Verification gate:**
- `arxa design lint` passes (adapted for `.tsx`)
- `arxa design selftest` passes
- `arxa lens check` + ladder on every route
- Pixel compare 0.95+ on all viewports

### Phase C — Convert arxa-studio templates (49 files)

The heavy lift. 47 files with nunjucks logic, 1760 tag occurrences. The
heaviest: `loop_view.html` (152 tags), `design_viewer.html` (129),
`intake/_shared.html` (106).

This is mechanical once the pattern is proven. Fan out:
- Shared widgets → components first (they're imported everywhere)
- Then surfaces in dependency order (shells before leaves)
- The `{% set x = c.x %}{% include %}` context-shadowing pattern becomes
  prop-passing to child components — straightforward but volume-heavy

**Verification gate:**
- Studio lint + selftest clean
- Lens check + ladder on key studio surfaces
- The studio's `{% macro %}` fragments all dispatch correctly

### Phase D — Dart design server migration

Replace `worker_shim.js` with a TSX rendering shim:

1. **Compile pipeline**: the Dart server pre-compiles `.tsx` → `.js` (via
   esbuild in a one-shot at boot or hot-reload) before injecting into Chrome
2. **`worker_shim.js`** → `worker_shim_tsx.js`: drops nunjucks Environment,
   uses a component registry + `renderToString()` from hono/jsx
3. **`worker_page.html`**: drops the nunjucks `<script>`, loads the compiled
   component bundle
4. **`_inject()` in `worker.dart`**: injects compiled JS instead of HTML source

**Verification gate:**
- Dart design server serves hello-hda with identical HTML output
- Hot reload works (re-compile + re-inject)
- Studio renders correctly

### Phase E — Cleanup

1. Remove `nunjucks` from `_packages`, vendor manifest, and all deps
2. Remove `runtime/templates.js`, `runtime/nunjucks.d.ts`, `runtime/types.d.ts`
   (slimmed or deleted if TSX provides native types)
3. Remove `runtime/preload.js` generation (Workers compile TSX at build time)
4. Remove the nunjucks-specific code paths in `l10n.js` (preload branch) and
   `templates.js` (deleted)
5. Update `tsconfig.json` — add `"jsx": "react-jsx"`, `"jsxImportSource": "hono/jsx"`
6. Update lint rules — scan `.tsx` instead of `.html`, keep the zero-JS contract
7. Update ADR-0002 and ADR-0003 to reflect the TSX template system
8. Update the eject README template

**Verification gate:**
- Full test suite passes (1287+ Dart tests)
- Both artifacts eject + typecheck clean (node + cloudflare)
- Lens check clean on all surfaces
- Zero references to `nunjucks` anywhere in the repo

## Risks

1. **Named Fragment fidelity (HIGHEST)**: the `{% macro %}` + `#macro` dispatch
   is how every htmx partial swap works. If the TSX fragment renders different
   HTML (whitespace, attribute ordering, auto-escape behavior), partial swaps
   break silently. Phase A proves this on one template before committing to
   the full conversion.

2. **Studio template volume**: 49 files, 1760 tag occurrences. Mechanical but
   error-prone at scale. Phase C should be subagent-fanned with per-file pixel
   compare gates.

3. **Chrome worker compilation**: the Dart design server runs templates in
   headless Chrome. TSX needs compilation (TypeScript → JS) before Chrome can
   execute it. esbuild is already a dependency — the question is whether
   on-the-fly compilation in the worker is fast enough for hot reload (~850ms
   current budget).

4. **Auto-escape parity**: nunjucks autoescapes `&`, `<`, `>`, `"`. JSX
   autoescapes the same set plus `'`. The difference could cause minor HTML
   output changes. Phase A catches this.

5. **ICU plural in `t()`**: the current `t()` function handles ICU plural
   syntax in ARB catalogs and returns `SafeString`. In TSX, `t()` returns a
   plain string (JSX escapes it). The SafeString wrapper is dropped — this is
   correct because the `t()` output is pre-escaped (interpolated vars are
   escaped inside `t()`, catalog text is trusted).

## Out of scope

- Client-side hydration of TSX components (hono/jsx supports it, but the
  zero-custom-JS contract forbids it)
- Suspense/streaming rendering (the synchronous render model matches the
  current nunjucks behavior)
- HonoX meta-framework (we're ejecting standalone Hono apps, not adopting a
  file-based router)
