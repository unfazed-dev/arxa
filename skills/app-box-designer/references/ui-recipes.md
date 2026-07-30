# UI recipes — the component catalog

The app-UI patterns a Surface is allowed to be composed from. Each recipe is
copy-adapt ready: the macro takes the context bag `c`, the CSS is flex/grid
with `gap` (never inline-flow spacing), tokens are CSS custom properties,
naming is BEM-ish (`.block__el--mod`, matching `frames.css`).

**How to use this catalog — components-first.** Before composing any surface,
inventory the design's repeated patterns and define them as macros/partials in
`ui/common/` + `ui/widgets/` (dialogs/bottomsheets under their own folders) —
start by copying the drop-ins from [`starter-partials/components/`](../starter-partials/components/)
and adapt. *Then* compose surfaces, only from that library. A pattern used on
two surfaces is never copied: the second use extracts it (DESIGN-ARCHITECTURE,
"Shared components"). Three near-identical implementations of the same widget
is the most expensive drift this medium allows.

**Conventions every recipe assumes**

- **Motion** is the closed 7-name vocabulary (DESIGN-ARCHITECTURE): `swap`,
  `traverse`, `spotlight`, `reveal`, `disclose`, `notify`, `pending`. Each
  recipe names which of the seven it rides; all timing comes from the
  `--motion-*` tokens in `starter-partials/motion.css`, and everything is
  gated inside `@media (prefers-reduced-motion: no-preference)`.
- **Icons** come from the runtime Nunjucks global: `{{ icon('arrow-left') }}`
  or `{{ icon('x', {size: 20, cls: 'foo', label: 'Close'}) }}` — Lucide
  kebab-case names, `currentColor`, decorative (`aria-hidden`) by default,
  `label` opts into a meaningful accessible icon. Never emoji, never
  hand-drawn SVG glyphs.
- **Ladder** branches live in CSS on the window-size-class boundaries
  (`min-width: 600px` / `840px`); never hardcode the freeze widths 390/744/1280
  anywhere — those are for shooting (see `references/viewport-ladder.md`).
- **Partials** referenced below (`_name.html`) live in
  `starter-partials/components/`; copy them to `ui/widgets/components/` and
  `assets/css/components.css` into your artifact. Shared cross-surface
  fragments are pulled with `{% include %}`; a surface re-renders one
  independently by wrapping the include in a Named Fragment macro.

---

## 1. Buttons & action rows

**Use:** any committed action — submits, mutations, primary/secondary pairs.
Actions in a row, never floating solo in text.

**Macro:**

```html
{% macro action_row(c) %}
<div class="action-row{% if c.stack %} action-row--stack{% endif %}">
  {% for a in c.actions %}
  <button class="btn{% if a.kind %} btn--{{ a.kind }}{% endif %}" type="button"
          hx-post="{{ a.url }}"{% if a.target %} hx-target="{{ a.target }}"{% endif %}
          {% if not a.target %} hx-swap="none"{% endif %}>{{ a.label }}</button>
  {% endfor %}
</div>
{% endmacro %}
```

**CSS:**

```css
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  min-height: 40px; padding: 0 16px; border: 0; border-radius: 10px;
  background: var(--btn-bg, var(--accent)); color: var(--btn-fg, #fff);
  font-family: var(--c-font); font-weight: 600; cursor: pointer; text-decoration: none; }
.btn--ghost { --btn-bg: transparent; --btn-fg: var(--accent);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, currentColor 30%, transparent); }
.action-row { display: flex; gap: 8px; justify-content: flex-end; flex-wrap: wrap; }
@media (max-width: 599.98px) { .action-row--stack { flex-direction: column; align-items: stretch; } }
```

**htmx:** `hx-post` + `hx-swap="none"` for fire-and-forget mutations (pair with
a toast, recipe 14); `hx-target` + Named Fragment when the mutation re-renders
a region. In-flight state is free: htmx toggles `.htmx-request` on the button.

**Ladder:** compact stacks primary actions full-width (`action-row--stack`);
medium/expanded keep the end-aligned row.

**Motion:** `pending` on submit; `swap` when a target re-renders.

**Flutter:** KitNativeButton, KitNativeSplitButton; KitNativeIconButton for icon-only.

**Navigational variant — CTA link** (partial `_cta-link.html`, context:
`cta = { href, label, icon?, external?, hx? }`). When the action is *go
somewhere* rather than *do something* — card footers, "view on canvas",
artifact cross-links — use the cta-link instead of a ghost button: label with
a trailing affordance glyph (`icon` defaults to `chevron-right`,
`arrow-up-right` when `external`, `false` for a bare text link). Fragment
navigation passes `hx: { get?, target, swap?, pushUrl? }` (`get` defaults to
`href`, `swap` to `outerHTML`). Motion: `traverse`, or `swap` under `hx`.
Flutter: KitListTile trailing chevron / KitNativeButton(link).

## 2. Icon

**Use:** every glyph in the artifact. The runtime global renders vendored
Lucide SVGs server-side — decorative by default, meaningful with `label`.

**Macro:** none — call the global. Wrap in `.icon-btn` when the icon IS the button:

```html
<a class="icon-btn" href="/settings" aria-label="Settings">
  {{ icon('settings', {size: 20}) }}
</a>
{{ icon('lock', {size: 16, label: 'Private'}) }}  {# meaningful: role="img" + <title> #}
```

**CSS:**

```css
.icon-btn { display: inline-flex; align-items: center; justify-content: center;
  width: 40px; height: 40px; border: 0; border-radius: 999px; background: transparent;
  color: inherit; cursor: pointer; text-decoration: none; }
.icon-btn:hover { background: color-mix(in srgb, currentColor 10%, transparent); }
```

**htmx:** none — icons ride whatever component carries them. Unknown names
render a dashed placeholder + server-side warning, so a typo is visible in
the prototype, not silent.

**Ladder:** size is per-component (22 rail, 20 toolbar, 18 list/menu); never
scale icons between rungs — composition changes, not glyph size.

**Motion:** none of its own; `pending` spinners add `.indicator-spin` (recipe 17).

**Flutter:** KitGlyphs (core kit).

## 3. Nav rail / sidebar

**Use:** the primary nav on medium+ rungs (tab-shell archetype). Compact's
primary nav is the bottom bar (recipe 5); the rail's overflow destinations
ride the compact drawer.

**Macro:** partial — `_nav-rail.html` (context: `rail = { brand?, drawer?,
items: [{ id, label, icon, href, current? }] }`). Include in the shell; wrap
for fragment re-render:

```html
{% macro nav_rail(c) %}{% set rail = c.rail %}{% include "ui/widgets/components/_nav-rail.html" %}{% endmacro %}
```

(The `{% set %}` shadows the context key from the bag: a fragment render
`{% import %}`s the view file, and imported macros see only their arguments
+ globals — not the render context. Includes under a `{% extends %}` page
see the full context either way.)

**CSS:** `.nav-rail` in components.css — `display: none` on compact; floating
icon-only rail (76px, sticky) at ≥600; icon+label (224px) at ≥840. Active
item: `.is-active` + `aria-current="page"`.

**htmx:** none — plain boosted `<a href>`. The server marks `current` per
route; boosted swaps carry the state automatically.

**Ladder:** hidden → icon-only → icon+label. The compact drawer is the same
partial with `rail.drawer: true`, included inside `<div id="nav-drawer"
popover>` and opened by the app bar's `popovertarget` button (native popover,
zero JS).

**Motion:** `traverse` (boosted navigation crossfade).

**Flutter:** KitNativeNavigationRail; KitDrawer for the compact drawer form.

## 4. Tabs

**Use:** switching between peer views INSIDE one surface (nested-shell
archetype) — not primary navigation. 2–5 tabs.

**Macro:** partial — `_tabs.html` (context: `tabs = { endpoint, oob?, items:
[{ id, label, current? }] }`), plus the surface's panel fragment:

```html
{% macro tab_panel(c) %}
{% set tabs = c.tabs %}{% include "ui/widgets/components/_tabs.html" %}
<div id="tab-panel" class="tabs__panel">{{ c.panel.body }}</div>
{% endmacro %}
```

**CSS:** `.tabs` in components.css — flex row, `overflow-x: auto`, active tab
underlined via `.is-active::after`.

**htmx:** each tab: `hx-get="<endpoint>?tab=<id>" hx-target="#tab-panel"
hx-swap="outerHTML"`. The fragment endpoint renders `tab_panel(c)` with
`tabs.oob: true` — the bar re-renders out-of-band (`hx-swap-oob="outerHTML"`
on `#tabs`) so the active marker moves with the panel. The full-page route
reads `?tab=` for deep links.

**Ladder:** identical composition all rungs; expanded may place tabs beside
the app bar instead of under it — wider gutters only, same partial.

**Motion:** `swap` on the panel.

**Flutter:** KitAnimatedTabStack (+ KitDirectionalTabTransition,
KitNativeTabBar for the bar alone).

## 5. Bottom nav

**Use:** THE primary nav on compact (tab-shell default chrome). 3–5 top-level
destinations only.

**Macro:** partial — `_bottom-nav.html`, reading the SAME `rail` context key
as `_nav-rail.html` (one viewmodel source feeds both; the bottom nav is the
rail's compact form). Include as the last element of the shell's scrolling
column — it is sticky-bottom.

```html
{% macro bottom_nav(c) %}{% set rail = c.rail %}{% include "ui/widgets/components/_bottom-nav.html" %}{% endmacro %}
```

**CSS:** `.bottom-nav` in components.css — flex row, icon over label,
`env(safe-area-inset-bottom)` padding; `display: none` from 600px up.

**htmx:** none — boosted links; `current` marks the active destination.

**Ladder:** compact only. If a surface renders identically at medium (e.g. an
auth gate with no nav), say so explicitly in its notes.

**Motion:** `traverse`.

**Flutter:** KitBottomNavScaffold.

## 6. App bar / toolbar

**Use:** every surface's top chrome — title + leading (back/drawer) +
actions. The ladder's shipped default: compact/medium show title + drawer
action + dropdown menu; expanded shows the full action row.

**Macro:** partial — `_appbar.html` (context: `bar = { title, back?, drawer?,
actions: [{ icon, label, href }] }`). Actions render twice from the one list:
inline row (≥840) and inside a native `<details>` dropdown (<840) — the
zero-JS responsive menu; CSS shows exactly one.

```html
{% macro appbar(c) %}{% set bar = c.bar %}{% include "ui/widgets/components/_appbar.html" %}{% endmacro %}
```

**CSS:** `.appbar` in components.css — sticky top, flex row with gap, title
ellipsis; `.appbar__menu-list` is the absolutely-positioned dropdown card.

**htmx:** actions are boosted links; the dropdown needs no htmx (`<details>`
is the whole mechanism — a server roundtrip to open a menu is a bug).

**Ladder:** as above; desktop shells may additionally pin a `.appbar` per
pane in master–detail.

**Motion:** `disclose` on the dropdown; `traverse` on actions.

**Flutter:** KitNativeAppBar; KitNativeSliverAppBar (collapsing),
KitNativeToolbar (desktop).

## 7. List rows & sections

**Use:** the inset-grouped-list archetype — settings, collections, any
homogeneous record list. Sections group rows under headers.

**Macro:** partial `_list-row.html` (context: `row = { id, title, subtitle?,
detail?, icon?, href?, chevron?, oob? }`), composed by a section macro in the
surface:

```html
{% macro list_section(c) %}
<section class="list-section">
  <h2 class="list-section__header">{{ c.section.title }}</h2>
  <div class="list-section__card">
    {% for row in c.section.rows %}{% include "ui/widgets/components/_list-row.html" %}{% endfor %}
  </div>
</section>
{% endmacro %}
```

**CSS:** `.list-section` / `.list-row` in components.css — rounded section
card, 1px separators between rows, leading icon tile, trailing
detail/chevron; whole-row `<a>` when `href` is set.

**htmx:** row navigation is boosted links. Single-row updates: the mutation
endpoint responds `hx-swap="none"` and renders the include with `row.oob:
true` — the row root (`id="row-{{ row.id }}"`) carries
`hx-swap-oob="outerHTML"` and htmx swaps it over the stale row in place.

**Ladder:** compact full-width grouped rows; medium wider inset; expanded the
list becomes the master pane of a master–detail pair (same rows, narrower
column).

**Motion:** `swap` on row OOB; `traverse` on row links.

**Flutter:** KitListTile (row), KitListSection (grouped card + header).

## 8. Card

**Use:** a self-contained content unit — media, title, summary, actions —
repeated in a grid (dashboard-stack archetype) or stacked singly.

**Macro:** partial `_card.html` (context: `card = { id, media?, title,
subtitle?, body?, actions?, vt? }`):

```html
<div class="card-grid">
  {% for card in cards %}{% include "ui/widgets/components/_card.html" %}{% endfor %}
</div>
```

**CSS:** `.card` in components.css — flex column with gap, radius + hairline
ring, actions pinned to the bottom; `.card-grid` is the ladder: 1 column → 2
(≥600) → 3 (≥840).

**htmx:** cards are usually static; make one a target by its stable root id
(`card-{{ card.id }}`) for OOB refreshes, exactly like recipe 7's row. Set
`card.vt: true` for a shared-element morph into the detail surface — the
partial derives a per-record `view-transition-name` (motion.css §2).

**Ladder:** the grid columns above; a card never stretches edge-to-edge past
medium — the grid caps it.

**Motion:** `spotlight` (opt-in via `vt`); `traverse` on its links.

**Flutter:** KitGlassCard / KitFrostedSurface.

## 9. Chip

**Use:** compact filters, tags, single-select facets. Filter chips navigate;
they never mutate directly.

**Macro:**

```html
{% macro chip_row(c) %}
<div class="chip-row">
  {% for chip in c.chips %}
  <a class="chip{% if chip.current %} is-active{% endif %}" href="{{ c.chip_url }}{{ chip.id }}"
     {% if chip.current %}aria-current="true"{% endif %}>
    {% if chip.icon %}{{ icon(chip.icon, {size: 14}) }}{% endif %}
    <span>{{ chip.label }}</span>
  </a>
  {% endfor %}
</div>
{% endmacro %}
```

**CSS:**

```css
.chip-row { display: flex; gap: 8px; overflow-x: auto; padding: 4px 0; }
.chip { display: inline-flex; align-items: center; gap: 6px; min-height: 32px;
  padding: 0 12px; border-radius: 999px; font-size: 13px; font-weight: 500;
  color: inherit; text-decoration: none; white-space: nowrap;
  box-shadow: inset 0 0 0 1px color-mix(in srgb, currentColor 25%, transparent); }
.chip.is-active { background: color-mix(in srgb, var(--accent) 16%, transparent);
  color: var(--accent); box-shadow: none; }
```

**htmx:** boosted `href` per chip (`?filter=<id>`); the server re-renders the
filtered list. For in-place filtering give the row `hx-get` + a list fragment
target (recipe 11's pattern).

**Ladder:** same pill all rungs; the row scrolls horizontally on compact,
wraps (`flex-wrap`) on expanded.

**Motion:** `traverse` / `swap` depending on nav vs in-place.

**Flutter:** KitChip; KitChipCarousel for the scrolling row.

## 10. Form fields (+ the 422 validation flow)

**Use:** any user input. The form-flow archetype: full-width fields on
compact, centered fixed-width column on expanded — never fields stretched to
1280px.

**Macro:** partial `_form-field.html` (context: `field = { name, label,
type?, value?, placeholder?, autocomplete?, required?, hint?, error? }`):

```html
{% macro profile_form(c) %}
<form id="profile-form" hx-post="/profile" hx-swap="outerHTML">
  {% for field in c.fields %}{% include "ui/widgets/components/_form-field.html" %}{% endfor %}
  <div class="action-row"><button class="btn" type="submit">Save</button></div>
</form>
{% endmacro %}
```

**CSS:** `.field` in components.css — label/input/hint column with gap;
`.field--invalid` paints the error state; focus ring via `:focus` outline.

**htmx:** the POST handler validates server-side; on failure it re-renders
`profile_form(c)` with values + per-field `error` at **status 422** — the
base.html meta config (`"code":"422","swap":true"`) swaps it like a normal
response. Native `required` etc. run first (`reportValidityOfForms: true` in
the same meta). Success paths: `h.location()` to navigate, or `hx-swap="none"`
+ toast (recipe 14).

**Ladder:** form column `max-width` capped (≈480px) from medium up.

**Motion:** `pending` on submit; `swap` on the re-rendered form.

**Flutter:** KitNativeTextField + KitFieldController (forms kit).

## 11. Search / filter input

**Use:** the pinned-search-list archetype — query-as-you-type over a list
fragment.

**Macro:**

```html
{% macro search_bar(c) %}
<div class="search-bar">
  {{ icon('search', {size: 18, cls: 'search-bar__icon'}) }}
  <input class="search-bar__input" type="search" name="q" value="{{ c.q }}"
         placeholder="{{ c.placeholder or 'Search' }}" aria-label="Search"
         hx-get="{{ c.endpoint }}" hx-trigger="input changed delay:300ms, search"
         hx-target="#results" hx-swap="innerHTML" />
</div>
{% endmacro %}
```

**CSS:**

```css
.search-bar { display: flex; align-items: center; gap: 8px; padding: 0 12px;
  min-height: 40px; border-radius: 999px;
  background: color-mix(in srgb, CanvasText 6%, Canvas); }
.search-bar__icon { color: color-mix(in srgb, CanvasText 45%, Canvas); flex-shrink: 0; }
.search-bar__input { flex: 1; min-width: 0; border: 0; background: none;
  font: inherit; font-family: var(--c-font); color: inherit; outline: none; }
```

**htmx:** `hx-trigger="input changed delay:300ms, search"` (debounced typing +
the native search-event for the clear button); the endpoint renders the
results fragment into `#results`. The input sits OUTSIDE the target, so focus
and the in-flight caret survive swaps. Add `hx-push-url="true"` when the query
should be shareable.

**Ladder:** pinned above the results on compact/medium; expanded adds the
detail pane beside `#results` — the input does not widen past the list pane.

**Motion:** `pending` while querying; `swap` on results.

**Flutter:** KitNativeSearchBar.

## 12. Dialog / popover

**Use:** confirms, short forms, focused decisions. Three mechanisms, all zero
JS — pick by whether the content needs the server at all.

**Macro:** partial `_dialog.html` for server-driven dialogs (context:
`dialog = { title, body, scrim?, dismiss?, actions? }`). The shell owns an
empty host:

```html
<button class="btn" hx-get="/confirm-delete" hx-target="#dialog-host" hx-swap="innerHTML">
  Delete
</button>
<div id="dialog-host"></div>
```

For stateless popovers/menus use the native form — no endpoint at all:

```html
<button class="icon-btn" popovertarget="sort-pop" aria-label="Sort">
  {{ icon('arrow-up-down', {size: 20}) }}
</button>
<div id="sort-pop" popover class="popover">… boosted sort links …</div>
```

For static confirms/info overlays whose content the page already owns — no
endpoint, no host, not even a request — use the declarative `_modal.html`
(context: `modal = { trigger, body, label?, cardClass?, closeLabel? }`): a
pure `<details>` toggle; the open summary stretches into the scrim (click
outside closes) and the card floats above it. `body` is trusted HTML composed
in the surface (`{% set %}` capture), rendered `|safe`. Esc does not close
(no JS) — note it in the surface's design notes if the product expects it.

**CSS:** `.dialog` in components.css — fixed, centered, radius + shadow;
`.overlay-scrim` dims. `.modal` is the declarative variant: `<details>` root,
the open `<summary>` doubles as the fixed scrim, `.modal-card` centers like
`.dialog`. Popover styling and its open/close transitions are
motion.css §3 (`@starting-style` + `allow-discrete`).

**htmx:** the trigger swaps the dialog (rendered `<dialog open>`) into the
host. Close: `<form method="dialog">` for instant native dismiss, or an
hx-endpoint returning the emptied host when closing mutates state. Scrim
click does not dismiss — no JS to catch it; note it in the surface's design
notes if the product expects it.

**Ladder:** same centered dialog all rungs, `width: min(400px, 100vw - 32px)`.

**Motion:** `reveal`.

**Flutter:** ui_library sheet/dialog services; KitNativePopupMenu for menus.

## 13. Bottom sheet

**Use:** action sheets and contextual pickers on touch rungs — the mobile
form of recipe 12's overlay.

**Macro:** partial `_bottom-sheet.html` (context: `sheet = { title?, items:
[{ icon?, label, href, danger? }], dismiss? }`), swapped into
`<div id="sheet-host">` like the dialog.

**CSS:** `.sheet` in components.css — fixed bottom, top radius, grab handle,
safe-area padding. From 600px up the SAME markup presents as a centered
dialog (M3 behaviour) and the grab handle hides.

**htmx:** identical to the dialog: `hx-get` → host; items are boosted links
(traverse away); dismiss via `<form method="dialog">` or a close endpoint.

**Ladder:** bottom sheet on compact; centered dialog from medium up — one
markup path, CSS branches.

**Motion:** `reveal`.

**Flutter:** ui_library sheet service.

## 14. Toast

**Use:** transient confirmation of a mutation — saved, deleted, sent. Never
for errors that need action (use a dialog) or state that must persist.

**Macro:** partial `_toast.html` (context: `toast = { text, kind?, icon?,
linger? }`). The host is one line in base.html: `<div id="toasts">`. The
mutation endpoint renders ONLY the toast:

```js
export const del = (c, h) => {
  facade.delete(c.req.param('id'));
  return h.render(c, 'ui/widgets/components/_toast.html',
    { toast: { text: 'Item deleted', kind: 'success', linger: true } });
};
```

**CSS:** `.toast` + `#toasts` in components.css — pill, fixed bottom-center
host, `pointer-events: none` on the host / `auto` on the toast. Enter/exit
motion is motion.css §5; `toast--linger` fades after `--toast-ttl`.

**htmx:** the triggering form/button sets `hx-swap="none"` (or the handler
sends `HX-Reswap: none`); the partial root carries
`hx-swap-oob="beforeend:#toasts"`, so the toast appends to the host while the
page stays put. CSS hides a lingered toast; the node leaves the DOM the next
time the server re-renders `#toasts` — only the server removes.

**Ladder:** same pill all rungs; `max-width` caps it on expanded.

**Motion:** `notify`.

**Flutter:** KitNotificationService.show.

## 15. Table / data density

**Use:** genuinely tabular data on expanded rungs — admin, reporting. If the
"table" is really a list, use recipe 7.

**Macro:**

```html
{% macro data_table(c) %}
<div class="table-scroll">
  <table class="data-table data-table--{{ c.density or 'comfortable' }}">
    <thead>
      <tr>{% for col in c.columns %}
        <th><a href="?sort={{ col.id }}">{{ col.label }}</a></th>
      {% endfor %}</tr>
    </thead>
    <tbody>
      {% for r in c.rows %}<tr>
        {% for col in c.columns %}<td>{{ r[col.id] }}</td>{% endfor %}
      </tr>{% endfor %}
    </tbody>
  </table>
</div>
{% endmacro %}
```

**CSS:**

```css
.table-scroll { overflow-x: auto; }
.data-table { width: 100%; border-collapse: collapse; font-family: var(--c-font);
  font-size: 14px; }
.data-table th, .data-table td { padding: 10px 12px; text-align: left;
  border-bottom: 1px solid color-mix(in srgb, CanvasText 10%, transparent); }
.data-table th a { color: inherit; text-decoration: none; font-weight: 600; }
.data-table--compact th, .data-table--compact td { padding: 5px 12px; font-size: 13px; }
```

**htmx:** sort headers are boosted `?sort=` links (server re-renders the
table). Density is a pref: POST to `/prefs/density` → `h.setPrefs` →
`h.refresh` (state playbook), and the viewmodel passes `prefs.density` as
`c.density`.

**Ladder:** compact wraps the table in `.table-scroll` (horizontal scroll) or
the surface swaps to recipe 7 rows — decide per surface, never squeeze.

**Motion:** `traverse` on sort; `swap` if the table is a fragment target.

**Flutter:** none — compose KitListTile at compact density, or custom.

## 16. Empty state

**Use:** a list/search with zero results, a cleared inbox, an unstarted
feature. Always pair the copy with the action that fills it.

**Macro:** partial `_empty-state.html` (context: `empty = { icon?, title,
body?, action? }`). The view branches server-side:

```html
{% if rows | length %}… list …{% else %}
{% include "ui/widgets/components/_empty-state.html" %}
{% endif %}
```

(Empty arrays are truthy in Nunjucks — always test `| length`, never the
bare array.)

**CSS:** `.empty-state` in components.css — centered column with gap, width
capped at 360px (centered-state archetype).

**htmx:** the optional action is a boosted link; in fragment contexts the
empty state is just what the list fragment renders when the facade returns
zero rows.

**Ladder:** identical composition at every rung — say so in the surface's
notes so the scaffolder knows it was decided, not forgotten.

**Motion:** rides the `swap` of whatever fragment contains it.

**Flutter:** none — compose icon + copy + KitNativeButton.

## 17. Loading: skeleton + pending indicator

**Use:** first-paint loads (skeleton) and in-flight requests (pending
indicator). Two different states — never a spinner where a skeleton belongs.

**Macro:** skeleton as the INITIAL content of a lazy fragment; htmx replaces
it on load:

```html
{% macro list_skeleton(c) %}
<div id="list-body" hx-get="{{ c.endpoint }}" hx-trigger="load" hx-swap="outerHTML">
  {% for i in range(0, c.rows or 4) %}
  <div class="skeleton" style="height: 52px; border-radius: 10px;"></div>
  {% endfor %}
</div>
{% endmacro %}
```

Pending on a trigger — the indicator is a child, shown only in flight:

```html
<button class="btn" hx-post="/save" hx-swap="none">
  {{ icon('loader-circle', {size: 16, cls: 'htmx-indicator indicator-spin'}) }}
  <span>Save</span>
</button>
```

**CSS:** `.skeleton` shimmer is motion.css §6 (reduced motion gets the static
base block); `.htmx-indicator` fade + `.indicator-spin` rotation are
motion.css §1 — add only geometry per surface.

**htmx:** `hx-trigger="load"` fetches the real fragment over the skeleton.
`pending` is automatic: `.htmx-request` on the trigger while in flight (plus
`cursor: progress` for everyone — state, not decoration).

**Ladder:** skeletons mirror the layout of the content at that rung (row
heights, grid columns) — a phone-shaped skeleton on expanded is a tell.

**Motion:** `pending`.

**Flutter:** KitNativeLoadingIndicator, KitNativeProgress;
KitLazyIndexedStack for the deferred-pane case.

## 18. Pagination / load-more

**Use:** long lists. Numbered pager when position matters (admin tables);
load-more when flow matters (feeds).

**Macro:**

```html
{% macro pager(c) %}
<nav class="pager" aria-label="Pagination">
  {% if c.page > 1 %}
  <a class="btn btn--ghost" href="?page={{ c.page - 1 }}">
    {{ icon('chevron-left', {size: 16}) }}<span>Prev</span></a>
  {% endif %}
  <span class="pager__status">Page {{ c.page }} of {{ c.pages }}</span>
  {% if c.page < c.pages %}
  <a class="btn btn--ghost" href="?page={{ c.page + 1 }}">
    <span>Next</span>{{ icon('chevron-right', {size: 16}) }}</a>
  {% endif %}
</nav>
{% endmacro %}

{% macro items_tail(c) %}
<div id="items-tail" class="load-more"{% if c.oob %} hx-swap-oob="outerHTML"{% endif %}>
  {% if c.next_page %}
  <button class="btn btn--ghost" type="button"
          hx-get="{{ c.endpoint }}?page={{ c.next_page }}"
          hx-target="#items" hx-swap="beforeend">Load more</button>
  {% endif %}
</div>
{% endmacro %}
```

**CSS:**

```css
.pager { display: flex; align-items: center; justify-content: center; gap: 12px; }
.pager__status { font-size: 13px; color: color-mix(in srgb, CanvasText 55%, Canvas); }
.load-more { display: flex; justify-content: center; padding: 16px 0; }
```

**htmx:** the pager is plain boosted links (full page re-render per page —
right for tables). Load-more: the button appends the next page's rows to
`#items` (`hx-swap="beforeend"`); the endpoint's response is the rows PLUS
`items_tail(c)` rendered with `oob: true` + the next page number (or no
button when exhausted) — the OOB swap replaces the control that triggered it.

**Ladder:** load-more on compact (scroll flow); pager acceptable from medium
up; never infinite-scroll — no JS.

**Motion:** `swap` on appended rows; `pending` on the button.

**Flutter:** KitLazyIndexedStack.

---

## Naming alignment — recipe → partial → Flutter primitive

| Recipe | Drop-in partial | Flutter primitive (kit registry) |
|---|---|---|
| Buttons & action rows | `_cta-link.html` (navigational variant) | KitNativeButton, KitNativeIconButton, KitNativeSplitButton |
| Icon | — (runtime global) | KitGlyphs (core) |
| Nav rail / sidebar | `_nav-rail.html` | KitNativeNavigationRail; KitDrawer (drawer form) |
| Tabs | `_tabs.html` | KitAnimatedTabStack, KitDirectionalTabTransition, KitNativeTabBar |
| Bottom nav | `_bottom-nav.html` | KitBottomNavScaffold |
| App bar / toolbar | `_appbar.html` | KitNativeAppBar, KitNativeSliverAppBar, KitNativeToolbar |
| List rows & sections | `_list-row.html` | KitListTile, KitListSection |
| Card | `_card.html` | KitGlassCard, KitFrostedSurface |
| Chip | — (macro) | KitChip, KitChipCarousel |
| Form fields + 422 | `_form-field.html` | KitNativeTextField + KitFieldController (forms kit) |
| Search / filter | — (macro) | KitNativeSearchBar |
| Dialog / popover | `_dialog.html` (server-driven), `_modal.html` (declarative) | ui_library sheet/dialog services; KitNativePopupMenu |
| Bottom sheet | `_bottom-sheet.html` | ui_library sheet service |
| Toast | `_toast.html` | KitNotificationService.show |
| Table / data density | — (macro) | none — compose KitListTile / custom |
| Empty state | `_empty-state.html` | none — compose icon + copy + KitNativeButton |
| Loading / skeleton | — (motion.css) | KitNativeLoadingIndicator, KitNativeProgress, KitLazyIndexedStack |
| Pagination / load-more | — (macros) | KitLazyIndexedStack |
