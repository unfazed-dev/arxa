# UI recipes — the widget catalog

The app-UI patterns a Surface is allowed to be composed from. Each recipe is
copy-adapt ready: the component takes its props (the server passes the ctx
bag — `{ prefs, locale, locales, translate }` merged in — as the single props
object; `t` is a prop, used as `{translate('home.title') as string}`), the CSS is
flex/grid with `gap` (never inline-flow spacing), tokens are CSS custom
properties, naming is BEM-ish (`.block__el--mod`, matching `frames.css`).

**The family class contract (style modules).** For app-kind artifacts the
widget library ALSO implements the 26 component families with the canonical
classes the style overlays key on — buttons `.btn`, menus `.menu .mi`,
fields `.fieldwrap .input`, selects `.select-wrap .select`, switches
`.sw`, segmented `.seg`, accordions `.acc-item`, and so on. The law per
family per style lives in [`styles/app/<style>/SPEC.md`](../styles/app/README.md)
(read the selected style FIRST); behavior is the interaction recipe there —
five classes, exact constants. Eight dropdown laws and field indicator
exclusivity apply to every style.

**How to use this catalog — widgets-first.** Before composing any surface,
inventory the design's repeated patterns and define them as components in
`ui/common/` + `ui/widgets/` (dialogs/bottomsheets under their own folders) —
start by copying the drop-ins from [`starter-partials/widgets/`](../starter-partials/widgets/)
and adapt. *Then* compose surfaces, only from that library. A pattern used on
two surfaces is never copied: the second use extracts it (DESIGN-ARCHITECTURE,
"Shared widgets"). Three near-identical implementations of the same widget
is the most expensive drift this medium allows.

**Conventions every recipe assumes**

- **Motion** is the closed 7-name vocabulary (DESIGN-ARCHITECTURE): `swap`,
  `traverse`, `spotlight`, `reveal`, `disclose`, `notify`, `pending`. Each
  recipe names which of the seven it rides; all timing comes from the
  `--motion-*` tokens in `starter-partials/motion.css`, and everything is
  gated inside `@media (prefers-reduced-motion: no-preference)`.
- **Icons** come from the runtime `Icon` component: import it relative from
  the file to the artifact root (`import Icon from '../../../runtime/icon.tsx'`
  — the server bundles a browser-compatible `icon.tsx` there), then
  `<Icon name="arrow-left" />` or `<Icon name="x" size={20} cls="foo"
  label="Close" />` — Lucide kebab-case names, `currentColor`, decorative
  (`aria-hidden`) by default, `label` opts into a meaningful accessible
  icon. Never emoji, never hand-drawn SVG glyphs.
- **Ladder** branches live in CSS on the window-size-class boundaries
  (`min-width: 600px` / `840px`); never hardcode the freeze widths 390/744/1280
  anywhere — those are for shooting (see `references/viewport-ladder.md`).
- **Partials** referenced below (`_name.tsx`) live in
  `starter-partials/widgets/`; copy them to the placement-law tier their
  consumers require (`references/app-architecture.md`) and
  `assets/css/widgets.css` into your artifact. Shared cross-surface
  fragments are component imports (relative paths, **including the `.tsx`
  extension**); a surface re-renders one independently as a Named Fragment —
  a named PascalCase export of the `*_view.tsx` file, rendered by the
  viewmodel as `'ui/.../x_view.html#fragmentName'` (the `.html` viewRef is
  kept for registry parity; `#fragmentName` maps to the named export
  `FragmentName`). hono/jsx escapes everything by default — trusted HTML
  goes through `raw(...)` from 'hono/utils/html' (never `raw()` user data),
  and control flow is plain JS: ternaries, `{cond && (...)}` (never guard on
  a bare number — `{count && ...}` renders a literal `0`), and
  `{items.map((item) => (...))}` with `key` on dynamic lists.

---

## 1. Buttons & action rows

**Use:** any committed action — submits, mutations, primary/secondary pairs.
Actions in a row, never floating solo in text.

**Component:**

```tsx
import type { FC } from 'hono/jsx';

interface Action {
  url: string;
  label: string;
  kind?: string;
  target?: string;
}

export const ActionRow: FC<{ actions: Action[]; stack?: boolean }> = ({ actions, stack }) => (
  <div class={`action-row${stack ? ' action-row--stack' : ''}`}>
    {actions.map((action) => (
      <button key={a.url} class={`btn${action.kind ? ` btn--${action.kind}` : ''}`} type="button"
              hx-post={a.url} hx-target={a.target}
              hx-swap={a.target ? undefined : 'none transition:false'}>{action.label}</button>
    ))}
  </div>
);
```

(hono/jsx drops an attribute whose value is `undefined` — conditional
attributes like `hx-target` and the `hx-swap` fallback above need no extra
branching.)

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

**htmx:** `hx-post` + `hx-swap="none transition:false"` for fire-and-forget
mutations (pair with a toast, recipe 14); `hx-target` + Named Fragment when the
mutation re-renders a region. In-flight state is free: htmx toggles
`.htmx-request` on the button.

> `transition:false` is not optional boilerplate. `transitions:true`
> wraps every swap in a view transition, and `hx-swap="none"` alone does not
> suppress it — the transition rides the swap cycle, not the swap style. A
> fire-and-forget POST without it cross-fades the whole view, which reads as
> the app reloading. See ADR-0003's 2026-08-03 amendment.
>
> **Which `none` needs it:** the ones that render NOTHING — a pure state write
> (prefs, a committed drag, a save with only an in-flight indicator). A `none`
> swap whose response carries **OOB** content (the toast recipes below) does
> change the DOM, and there the transition is wanted — leave it on. The test is
> "does anything visible change?", not "is the swap style `none`?".

**Ladder:** compact stacks primary actions full-width (`action-row--stack`);
medium/expanded keep the end-aligned row.

**Motion:** `pending` on submit; `swap` when a target re-renders.

**Flutter:** AppBoxKitNativeButton, AppBoxKitNativeSplitButton; AppBoxKitNativeIconButton for icon-only.

**Navigational variant — CTA link** (partial `_cta-link.tsx` exporting
`CtaLink`, props: `cta = { href, label, icon?, external?, hx? }`). When the
action is *go somewhere* rather than *do something* — card footers, "view on
canvas", artifact cross-links — use the cta-link instead of a ghost button:
label with a trailing affordance glyph (`icon` defaults to `chevron-right`,
`arrow-up-right` when `external`, `false` for a bare text link). Fragment
navigation passes `hx: { get?, target, swap?, pushUrl? }` (`get` defaults to
`href`, `swap` to `outerHTML`). Motion: `traverse`, or `swap` under `hx`.
Flutter: AppBoxKitListTile trailing chevron / AppBoxKitNativeButton(link).

## 2. Icon

**Use:** every glyph in the artifact. The runtime component renders vendored
Lucide SVGs server-side — decorative by default, meaningful with `label`.

**Component:** none — import `Icon` from `runtime/icon.tsx` (relative from the
file to the artifact root). Wrap in `.icon-btn` when the icon IS the button:

```tsx
import Icon from '../../../runtime/icon.tsx';

<a class="icon-btn" href="/settings" aria-label="Settings">
  <Icon name="settings" size={20} />
</a>
<Icon name="lock" size={16} label="Private" />  {/* meaningful: role="img" + <title> */}
```

**CSS:**

```css
.icon-btn { display: inline-flex; align-items: center; justify-content: center;
  width: 40px; height: 40px; border: 0; border-radius: 999px; background: transparent;
  color: inherit; cursor: pointer; text-decoration: none; }
.icon-btn:hover { background: color-mix(in srgb, currentColor 10%, transparent); }
```

**htmx:** none — icons ride whatever widget carries them. Unknown names
render a dashed placeholder + server-side warning, so a typo is visible in
the prototype, not silent.

**Ladder:** size is per-widget (22 nav-rail, 20 toolbar, 18 list/menu); never
scale icons between rungs — composition changes, not glyph size.

**Motion:** none of its own; `pending` spinners add `.indicator-spin` (recipe 17).

**Flutter:** AppBoxKitGlyphs (core kit).

## 3. Nav rail (the railbar's container)

**Use:** the primary nav on medium+ rungs (tab-shell archetype) — the
railbar in app chrome. Compact's primary nav is the tabbar (recipe 5); the
nav-rail's overflow destinations ride the compact drawer.

**Component:** partial — `_nav-rail.tsx` exporting `NavRail` (props:
`nav = { brand?, drawer?, items: [{ id, label, icon, href, current? }] }`).
Render it in the shell; expose it as a Named Fragment for fragment re-render:

```tsx
import { NavRail } from '../../common/widgets/_nav-rail.tsx';

export const NavRailFragment: FC<{ nav: NavData }> = ({ nav }) => <NavRail nav={nav} />;
```

(A fragment render — the viewmodel rendering `'.../x_view.html#navRailFragment'` —
calls the named export with exactly the props the endpoint passes. Nothing
leaks in from a render context beyond the server's merged
`{ prefs, locale, locales, translate }`, so whatever a fragment needs, the endpoint
puts in the props.)

**CSS:** `.nav-rail` in widgets.css — `display: none` on compact; floating
icon-only nav-rail (76px, sticky) at ≥600; icon+label (224px) at ≥840.
Active item: `.is-active` + `aria-current="page"`.

**htmx:** none — plain boosted `<a href>`. The server marks `current` per
route; boosted swaps carry the state automatically.

**Ladder:** hidden → icon-only → icon+label. The compact drawer is the same
partial rendered with `nav.drawer: true`, mounted inside `<div id="nav-drawer"
popover>` and opened by the header panel's `popovertarget` button (native
popover, zero JS).

**Motion:** `traverse` (boosted navigation crossfade).

**Flutter:** AppBoxKitNativeNavigationRail; AppBoxKitDrawer for the compact drawer form.

## 4. Tabs

**Use:** switching between peer views INSIDE one surface (nested-shell
archetype) — not primary navigation. 2–5 tabs.

**Component:** partial — `_tabs.tsx` exporting `Tabs` (props: `tabs = {
endpoint, oob?, items: [{ id, label, current? }] }`), plus the surface's
panel fragment:

```tsx
import { Tabs } from '../../common/widgets/_tabs.tsx';

export const TabPanel: FC<{ tabs: TabsData; panel: { body: string } }> = ({ tabs, panel }) => (
  <Fragment>
    <Tabs tabs={tabs} />
    <div id="tab-panel" class="tabs__panel">{panel.body}</div>
  </Fragment>
);
```

**CSS:** `.tabs` in widgets.css — flex row, `overflow-x: auto`, active tab
underlined via `.is-active::after`.

**htmx:** each tab: `hx-get="<endpoint>?tab=<id>" hx-target="#tab-panel"
hx-swap="outerHTML"`. The fragment endpoint renders `TabPanel` with
`tabs.oob: true` — the bar re-renders out-of-band (`hx-swap-oob="outerHTML"`
on `#tabs`) so the active marker moves with the panel. The full-page route
reads `?tab=` for deep links.

**Ladder:** identical composition all rungs; expanded may place tabs beside
the app bar instead of under it — wider gutters only, same partial.

**Motion:** `swap` on the panel.

**Flutter:** AppBoxKitAnimatedTabStack (+ AppBoxKitDirectionalTabTransition,
AppBoxKitNativeTabBar for the bar alone).

## 5. Tabbar

**Use:** THE primary nav on compact (tab-shell default chrome). 3–5 top-level
destinations only.

**Component:** partial — `_tabbar.tsx` exporting `TabBar`, reading the SAME
`nav` prop shape as `_nav-rail.tsx` (one viewmodel source feeds both; the
tabbar is the nav-rail's compact form). Render as the last element of the
shell's scrolling column — it is sticky-bottom.

```tsx
import { TabBar } from '../../common/widgets/_tabbar.tsx';

export const TabBarFragment: FC<{ nav: NavData }> = ({ nav }) => <TabBar nav={nav} />;
```

**CSS:** `.tabbar` in widgets.css — flex row, icon over label,
`env(safe-area-inset-bottom)` padding; `display: none` from 600px up.

**htmx:** none — boosted links; `current` marks the active destination.

**Ladder:** compact only. If a surface renders identically at medium (e.g. an
auth gate with no nav), say so explicitly in its notes.

**Motion:** `traverse`.

**Flutter:** AppBoxKitBottomNavScaffold.

## 6. App bar / toolbar

**Use:** every surface's top chrome — title + leading (back/drawer) +
actions. The ladder's shipped default: compact/medium show title + drawer
action + dropdown menu; expanded shows the full action row.

**Component:** partial — `_appbar.tsx` exporting `AppBar` (props: `bar = {
title, back?, drawer?, actions: [{ icon, label, href }] }`). Actions render
twice from the one list: inline row (≥840) and inside a native `<details>`
dropdown (<840) — the zero-JS responsive menu; CSS shows exactly one.

```tsx
import { AppBar } from '../../common/widgets/_appbar.tsx';

export const AppBarFragment: FC<{ bar: BarData }> = ({ bar }) => <AppBar bar={bar} />;
```

**CSS:** `.appbar` in widgets.css — sticky top, flex row with gap, title
ellipsis; `.appbar__menu-list` is the absolutely-positioned dropdown card.

**htmx:** actions are boosted links; the dropdown needs no htmx (`<details>`
is the whole mechanism — a server roundtrip to open a menu is a bug).

**Ladder:** as above; desktop shells may additionally pin a `.appbar` per
pane in master–detail.

**Motion:** `disclose` on the dropdown; `traverse` on actions.

**Flutter:** AppBoxKitNativeAppBar; AppBoxKitNativeSliverAppBar (collapsing),
AppBoxKitNativeToolbar (desktop).

## 7. List rows & sections

**Use:** the inset-grouped-list archetype — settings, collections, any
homogeneous record list. Sections group rows under headers.

**Component:** partial `_list-row.tsx` exporting `ListRow` (props: `row = {
id, title, subtitle?, detail?, icon?, href?, chevron?, oob? }`), composed by
a section component in the surface:

```tsx
import { ListRow } from '../../common/widgets/_list-row.tsx';

export const ListSection: FC<{ section: { title: string; rows: RowData[] } }> = ({ section }) => (
  <section class="list-section">
    <h2 class="list-section__header">{section.title}</h2>
    <div class="list-section__card">
      {section.rows.map((row) => <ListRow key={row.id} row={row} />)}
    </div>
  </section>
);
```

**CSS:** `.list-section` / `.list-row` in widgets.css — rounded section
card, 1px separators between rows, leading icon tile, trailing
detail/chevron; whole-row `<a>` when `href` is set.

**htmx:** row navigation is boosted links. Single-row updates: the mutation
endpoint responds `hx-swap="none"` and renders the partial with `row.oob:
true` — the row root (`id={`row-${row.id}`}`) carries
`hx-swap-oob="outerHTML"` and htmx swaps it over the stale row in place.

**Ladder:** compact full-width grouped rows; medium wider inset; expanded the
list becomes the master pane of a master–detail pair (same rows, narrower
column).

**Motion:** `swap` on row OOB; `traverse` on row links.

**Flutter:** AppBoxKitListTile (row), AppBoxKitListSection (grouped card + header).

## 8. Card

**Use:** a self-contained content unit — media, title, summary, actions —
repeated in a grid (dashboard-stack archetype) or stacked singly.

**Component:** partial `_card.tsx` exporting `Card` (props: `card = { id,
media?, title, subtitle?, body?, actions?, vt? }`):

```tsx
import { Card } from '../../common/widgets/_card.tsx';

<div class="card-grid">
  {cards.map((card) => <Card key={card.id} card={card} />)}
</div>
```

**CSS:** `.card` in widgets.css — flex column with gap, radius + hairline
ring, actions pinned to the bottom; `.card-grid` is the ladder: 1 column → 2
(≥600) → 3 (≥840).

**htmx:** cards are usually static; make one a target by its stable root id
(`card-${card.id}`) for OOB refreshes, exactly like recipe 7's row. Set
`card.vt: true` for a shared-element morph into the detail surface — the
partial derives a per-record `view-transition-name` (motion.css §2).

**Ladder:** the grid columns above; a card never stretches edge-to-edge past
medium — the grid caps it.

**Motion:** `spotlight` (opt-in via `vt`); `traverse` on its links.

**Flutter:** AppBoxKitGlassCard / AppBoxKitFrostedSurface.

## 9. Chip

**Use:** compact filters, tags, single-select facets. Filter chips navigate;
they never mutate directly.

**Component:**

```tsx
import Icon from '../../../runtime/icon.tsx';

interface Chip {
  id: string;
  label: string;
  icon?: string;
  current?: boolean;
}

export const ChipRow: FC<{ chips: Chip[]; chipUrl: string }> = ({ chips, chipUrl }) => (
  <div class="chip-row">
    {chips.map((chip) => (
      <a key={chip.id} class={`chip${chip.current ? ' is-active' : ''}`} href={`${chipUrl}${chip.id}`}
         aria-current={chip.current ? 'true' : undefined}>
        {chip.icon && <Icon name={chip.icon} size={14} />}
        <span>{chip.label}</span>
      </a>
    ))}
  </div>
);
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

**Flutter:** AppBoxKitChip; AppBoxKitChipCarousel for the scrolling row.

## 10. Form fields (+ the 422 validation flow)

**Use:** any user input. The form-flow archetype: full-width fields on
compact, centered fixed-width column on expanded — never fields stretched to
1280px.

**Component:** partial `_form-field.tsx` exporting `FormField` (props:
`field = { name, label, type?, value?, placeholder?, autocomplete?,
required?, hint?, error? }`):

```tsx
import { FormField } from '../../common/widgets/_form-field.tsx';

export const ProfileForm: FC<{ fields: FieldData[] }> = ({ fields }) => (
  <form id="profile-form" hx-post="/profile" hx-swap="outerHTML" {...{ 'hx-status:422': '{}' }}>
    {fields.map((field) => <FormField key={field.name} field={field} />)}
    <div class="action-row"><button class="btn" type="submit">Save</button></div>
  </form>
);
```

**CSS:** `.field` in widgets.css — label/input/hint column with gap;
`.field--invalid` paints the error state; focus ring via `:focus` outline.

**htmx:** the POST handler validates server-side; on failure it re-renders
`ProfileForm` with values + per-field `error` at **status 422** — the
base.tsx htmx config (`"noSwap":[204,304,"4xx","5xx"]`) would black a 4xx
out, so the form opts back in with the `hx-status:422` spread attribute
(empty merge = swap like a normal response). Native `required` etc. run
first — htmx 4 validates forms with `reportValidity()` natively. Success
paths: `h.location()` to navigate, or `hx-swap="none"` + toast (recipe 14).

**Ladder:** form column `max-width` capped (≈480px) from medium up.

**Motion:** `pending` on submit; `swap` on the re-rendered form.

**Flutter:** AppBoxKitNativeTextField + AppBoxKitFieldController (forms kit).

## 11. Search / filter input

**Use:** the pinned-search-list archetype — query-as-you-type over a list
fragment.

**Component:**

```tsx
import Icon from '../../../runtime/icon.tsx';

export const SearchBar: FC<{ q?: string; placeholder?: string; endpoint: string }> = ({
  q,
  placeholder,
  endpoint,
}) => (
  <div class="search-bar">
    <Icon name="search" size={18} cls="search-bar__icon" />
    <input class="search-bar__input" type="search" name="q" value={q ?? ''}
           placeholder={placeholder ?? 'Search'} aria-label="Search"
           hx-get={endpoint} hx-trigger="input changed delay:300ms, search"
           hx-target="#results" hx-swap="innerHTML" />
  </div>
);
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

**Flutter:** AppBoxKitNativeSearchBar.

## 12. Dialog / popover

**Use:** confirms, short forms, focused decisions. Three mechanisms, all zero
JS — pick by whether the content needs the server at all.

**Component:** partial `_dialog.tsx` exporting `Dialog` for server-driven
dialogs (props: `dialog = { title, body, scrim?, dismiss?, actions? }`). The
shell owns an empty host:

```tsx
<button class="btn" hx-get="/confirm-delete" hx-target="#dialog-host" hx-swap="innerHTML">
  Delete
</button>
<div id="dialog-host"></div>
```

For stateless popovers/menus use the native form — no endpoint at all:

```tsx
<button class="icon-btn" popovertarget="sort-pop" aria-label="Sort">
  <Icon name="arrow-up-down" size={20} />
</button>
<div id="sort-pop" popover class="popover">… boosted sort links …</div>
```

For static confirms/info overlays whose content the view already owns — no
endpoint, no host, not even a request — use the declarative `_modal.tsx`
exporting `Modal` (props: `modal = { trigger, label?, cardClass?,
closeLabel? }`, body passed as `children`): a pure `<details>` toggle; the
open summary stretches into the scrim (click outside closes) and the card
floats above it. The body is JSX composed in the surface and passed as
`children` (type `Child` from 'hono/jsx') — a trusted HTML string goes
through `raw(...)` from 'hono/utils/html', never `raw()` on user data. Esc
does not close (no JS) — note it in the surface's design notes if the
product expects it.

**CSS:** `.dialog` in widgets.css — fixed, centered, radius + shadow;
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

**Flutter:** ui_library sheet/dialog services; AppBoxKitNativePopupMenu for menus.

## 13. Bottom sheet

**Use:** action sheets and contextual pickers on touch rungs — the mobile
form of recipe 12's overlay.

**Component:** partial `_bottom-sheet.tsx` exporting `BottomSheet` (props:
`sheet = { title?, items: [{ icon?, label, href, danger? }], dismiss? }`),
swapped into `<div id="sheet-host">` like the dialog.

**CSS:** `.sheet` in widgets.css — fixed bottom, top radius, grab handle,
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

**Component:** partial `_toast.tsx` exporting `Toast` (props: `toast = {
text, kind?, icon?, linger? }`). The host is one line in base.tsx:
`<div id="toasts"></div>`. The mutation endpoint renders ONLY the toast —
as a **Named Fragment of the current view**, never the widget file directly
(the render registry maps `*_view.tsx` exports only, so a bare widget path
is not a renderable viewRef):

```js
export const del = (context, helpers) => {
  facade.delete(context.req.param('id'));
  return helpers.render(context, `${VIEW}#toastSwap`,
    { toast: { text: 'Item deleted', kind: 'success', linger: true } });
};
```

```tsx
// in <surface>_view.tsx — the fragment composes the shared component:
export function ToastSwap({ toast }) {
  return <Toast toast={toast} />; // Toast's root carries hx-swap-oob
}
```

**CSS:** `.toast` + `#toasts` in widgets.css — pill, fixed bottom-center
host, `pointer-events: none` on the host / `auto` on the toast. Enter/exit
motion is motion.css §5; `toast--linger` fades after `--toast-ttl`.

**htmx:** the triggering form/button sets `hx-swap="none"` (or the handler
sends `HX-Reswap: none`); the partial root carries
`hx-swap-oob="beforeend:#toasts"`, so the toast appends to the host while the
view stays put. CSS hides a lingered toast; the node leaves the DOM the next
time the server re-renders `#toasts` — only the server removes.

**Ladder:** same pill all rungs; `max-width` caps it on expanded.

**Motion:** `notify`.

**Flutter:** AppBoxKitNotificationService.show.

## 15. Table / data density

**Use:** genuinely tabular data on expanded rungs — admin, reporting. If the
"table" is really a list, use recipe 7.

**Component:**

```tsx
interface Column {
  id: string;
  label: string;
}

export const DataTable: FC<{
  columns: Column[];
  rows: Record<string, unknown>[];
  density?: string;
}> = ({ columns, rows, density }) => (
  <div class="table-scroll">
    <table class={`data-table data-table--${density ?? 'comfortable'}`}>
      <thead>
        <tr>{columns.map((col) => (
          <th key={col.id}><a href={`?sort=${col.id}`}>{col.label}</a></th>
        ))}</tr>
      </thead>
      <tbody>
        {rows.map((row, rowIndex) => (
          <tr key={rowIndex}>
            {columns.map((col) => <td key={col.id}>{r[col.id] as string}</td>)}
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);
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
the `density` prop.

**Ladder:** compact wraps the table in `.table-scroll` (horizontal scroll) or
the surface swaps to recipe 7 rows — decide per surface, never squeeze.

**Motion:** `traverse` on sort; `swap` if the table is a fragment target.

**Flutter:** none — compose AppBoxKitListTile at compact density, or custom.

## 16. Empty state

**Use:** a list/search with zero results, a cleared inbox, an unstarted
feature. Always pair the copy with the action that fills it.

**Component:** partial `_empty-state.tsx` exporting `EmptyState` (props:
`empty = { icon?, title, body?, action? }`). The view branches server-side:

```tsx
import { EmptyState } from '../../common/widgets/_empty-state.tsx';

{rows.length > 0 ? <>… list …</> : <EmptyState empty={empty} />}
```

(Arrays are always truthy in JS too — test `.length`, never the bare array.
And never write `{rows.length && ...}` to guard a block: JSX renders a
falsy number literally, so an empty list would paint a stray `0` — guard
with `rows.length > 0 && ...` or a ternary.)

**CSS:** `.empty-state` in widgets.css — centered column with gap, width
capped at 360px (centered-state archetype).

**htmx:** the optional action is a boosted link; in fragment contexts the
empty state is just what the list fragment renders when the facade returns
zero rows.

**Ladder:** identical composition at every rung — say so in the surface's
notes so the scaffolder knows it was decided, not forgotten.

**Motion:** rides the `swap` of whatever fragment contains it.

**Flutter:** none — compose icon + copy + AppBoxKitNativeButton.

## 17. Loading: skeleton + pending indicator

**Use:** first-paint loads (skeleton) and in-flight requests (pending
indicator). Two different states — never a spinner where a skeleton belongs.

**Component:** skeleton as the INITIAL content of a lazy fragment; htmx
replaces it on load:

```tsx
export const ListSkeleton: FC<{ endpoint: string; rows?: number }> = ({ endpoint, rows = 4 }) => (
  <div id="list-body" hx-get={endpoint} hx-trigger="load" hx-swap="outerHTML">
    {Array.from({ length: rows }, (_, i) => (
      <div key={rowIndex} class="skeleton" style="height: 52px; border-radius: 10px;"></div>
    ))}
  </div>
);
```

Pending on a trigger — the indicator is a child, shown only in flight:

```tsx
<button class="btn" hx-post="/save" hx-swap="none transition:false">
  <Icon name="loader-circle" size={16} cls="htmx-indicator indicator-spin" />
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

**Flutter:** AppBoxKitNativeLoadingIndicator, AppBoxKitNativeProgress;
AppBoxKitLazyIndexedStack for the deferred-pane case.

## 18. Pagination / load-more

**Use:** long lists. Numbered pager when position matters (admin tables);
load-more when flow matters (feeds).

**Component:**

```tsx
import Icon from '../../../runtime/icon.tsx';

export const Pager: FC<{ page: number; pages: number }> = ({ page, pages }) => (
  <nav class="pager" aria-label="Pagination">
    {page > 1 && (
      <a class="btn btn--ghost" href={`?page=${page - 1}`}>
        <Icon name="chevron-left" size={16} /><span>Prev</span></a>
    )}
    <span class="pager__status">Page {page} of {pages}</span>
    {page < pages && (
      <a class="btn btn--ghost" href={`?page=${page + 1}`}>
        <span>Next</span><Icon name="chevron-right" size={16} /></a>
    )}
  </nav>
);

export const ItemsTail: FC<{ oob?: boolean; nextPage?: number; endpoint: string }> = ({
  oob,
  nextPage,
  endpoint,
}) => (
  <div id="items-tail" class="load-more" hx-swap-oob={oob ? 'outerHTML' : undefined}>
    {nextPage !== undefined && (
      <button class="btn btn--ghost" type="button"
              hx-get={`${endpoint}?page=${nextPage}`}
              hx-target="#items" hx-swap="beforeend">Load more</button>
    )}
  </div>
);
```

**CSS:**

```css
.pager { display: flex; align-items: center; justify-content: center; gap: 12px; }
.pager__status { font-size: 13px; color: color-mix(in srgb, CanvasText 55%, Canvas); }
.load-more { display: flex; justify-content: center; padding: 16px 0; }
```

**htmx:** the pager is plain boosted links (full view re-render per view —
right for tables). Load-more: the button appends the next view's rows to
`#items` (`hx-swap="beforeend"`); the endpoint's response is the rows PLUS
`ItemsTail` rendered with `oob: true` + the next view number (or no
button when exhausted) — the OOB swap replaces the control that triggered it.

**Ladder:** load-more on compact (scroll flow); pager acceptable from medium
up; never infinite-scroll — no JS.

**Motion:** `swap` on appended rows; `pending` on the button.

**Flutter:** AppBoxKitLazyIndexedStack.

## 19. Multi-view panel (the stateful widget)

**Use:** a secondary panel beside the stage that switches between several
registered views (thread / artifacts / files / runs…) from an icon carousel —
the Chat-Centric Layout's activity and composer panels. Not primary navigation
(recipe 3).

This is the reference implementation of the Widget-state contract
(DESIGN-ARCHITECTURE, "Widget state"): every piece of panel UI state is
server session state, namespaced per shell, rendered back as classes — and
the panel's parts refresh out-of-band so nothing ever shows a stale copy.

**Component:** partial — `_panel-views.tsx`. `Frame` wraps the caller's
`children`; part components `Head` / `Body` / `Bar` carry their own ids
(`#panel-activity-top|-body|-bottom`) and an `oob` flag — the component
hardcodes the activity ids rather than templating a retired `side` param
(canon: `designs/appbox-studio/ui/common/_integration_panels.md`):

```tsx
import { Frame } from '../../common/widgets/_panel-views.tsx';

<Frame label={c.activityLabel} views={c.activityViews}
       size={c.panelSize} sizeHref={c.panelSizeHref}>
  …markup for the active view…
</Frame>
```

`views`: `[{ id, icon, label, href, active }]` — one carousel button per
registered view, `href` targets `#panel-activity-body`. `size` is `'s'|'m'|
'l'`; `sizeHref` marks the panel resizable — the top section renders a drag
handle (`.panel-resize`) that the vendored drag.js island wires to POST
the px width (`…/panel/size/activity`). Requires l10n keys
`panel.activity.views`, `panel.resize` (only with `sizeHref`).

**State (facade, per shell):** `activityView` (active view id),
`panelSize` (width step enum — discrete and server-validated, never a dragged
pixel value), `panelSizePx` (px width from the drag handle), plus whatever
domain filter the shell owns. All under `sessionData.<shell>`; routes
`<base>/panel?view=…` and `<base>/panel/size/activity/<step>` mutate and
re-render.

**htmx wiring:**

- **view switch** — carousel targets `#panel-activity-body`; the response is
  the body content PLUS head and bar rendered with `oob: true`, so the active
  icon and the head label track the server. The `<aside>` itself (user's
  scroll, width class) is never replaced.
- **resize** — the drag handle POSTs the px width on release and the whole
  aside re-renders `outerHTML`; safe because the width is server state (the
  response re-renders it), unlike a CSS `resize` drag which cannot persist
  at all.
- **stage acts** — anything that changes the panel's data (pins, approvals,
  decisions) re-feeds body + head + bar OOB in the same response.
- **view render** — emits `Frame` only; OOB parts are response-only markup.

**CSS:** `.panel .panel-activity` + `.panel-size-s|m|l` width classes (`transition:
width` on `--panel-w`); `.panel-views-icon.is-active` takes the accent ring. Below the
expanded rung the panel bar picks the single visible content panel (recipe:
the `?panel=` switcher).

**Ladder:** expanded shows all panels; medium/compact show one content panel
at a time under the panel bar.

**Motion:** `swap` on view switches; width transition on the size step.

**Flutter:** per-shell panel controller (view / size / filter as typed state)
driving an adaptive panel — no single kit primitive, compose.

## 20. Auto Layout (the attribute layer)

**Use:** the default layout discipline of every widget-library widget
(DESIGN-ARCHITECTURE, "Auto Layout"). A container opts in with `data-layout`;
its children size per axis with `data-resize-x` / `data-resize-y`. The rules
ship in `starter-partials/widgets/widgets.css` ("Auto Layout" block) —
static attribute selectors, zero client JS. Never hand-write one-off flex
classes for what the attributes already say; reach for a class only for what
the attributes deliberately don't cover (colors, radius, min/max constraints).

Canonical button — hugs both axes, icon + label with a gap:

```tsx
<button class="btn" data-layout data-gap="8" data-align-y="center"
        data-resize-x="hug" data-resize-y="hug" type="button"
        hx-post={a.url}>
  <Icon name="check" size={16} /><span>{action.label}</span>
</button>
```

Card in a list — the list flows vertically, each card fills the row and
flows its own content; the header row uses `data-gap="auto"` to push the
badge to the far end:

```tsx
<ul class="card-list" data-layout data-flow="v" data-gap="8">
  {c.cards.map((card) => (
    <li key={card.id} class="card" data-layout data-flow="v" data-gap="12" data-pad="16"
        data-resize-x="fill">
      <div data-layout data-gap="auto" data-align-y="center">
        <h3 class="card__title" data-resize-x="hug">{card.title}</h3>
        <span class="card__badge" data-resize-x="fixed">{card.badge}</span>
      </div>
      <p class="card__body">{card.body}</p>
      <div data-layout data-gap="8" data-align-x="end">
        <button class="btn btn--ghost" type="button">Dismiss</button>
        <button class="btn" type="button">Open</button>
      </div>
    </li>
  ))}
</ul>
```

Escape hatch — one child out of the flow (an overlapping badge on the card
corner); the `[data-layout]` parent is already `position: relative`:

```tsx
<span class="card__pin" data-layout-ignore style="top: 8px; right: 8px;">
  <Icon name="pin" size={14} />
</span>
```

Two ignored children in one frame is the signal to drop `data-layout` from
that frame entirely — it's an art-directed composition, not a flow.

**htmx:** none — layout is render-time markup; swaps re-render attributes
from server state like any other attribute.

**Ladder:** attributes are rung-independent; when composition itself changes
across the ladder, branch in the widget's class CSS on the
window-size-class boundaries, same as every other recipe.

**Motion:** none of its own — children ride whatever motion the widget
already owns.

**Flutter:** Row/Column (flow) + Expanded (fill) / SizedBox (fixed);
Stack + Positioned for the escape hatch.

---

## Naming alignment — recipe → partial → Flutter primitive

| Recipe | Drop-in partial | Flutter primitive (kit registry) |
|---|---|---|
| Buttons & action rows | `_cta-link.tsx` (navigational variant) | AppBoxKitNativeButton, AppBoxKitNativeIconButton, AppBoxKitNativeSplitButton |
| Icon | — (`runtime/icon.tsx` component) | AppBoxKitGlyphs (core) |
| Nav rail (railbar) | `_nav-rail.tsx` | AppBoxKitNativeNavigationRail; AppBoxKitDrawer (drawer form) |
| Tabs | `_tabs.tsx` | AppBoxKitAnimatedTabStack, AppBoxKitDirectionalTabTransition, AppBoxKitNativeTabBar |
| Tabbar | `_tabbar.tsx` | AppBoxKitBottomNavScaffold |
| App bar / toolbar | `_appbar.tsx` | AppBoxKitNativeAppBar, AppBoxKitNativeSliverAppBar, AppBoxKitNativeToolbar |
| List rows & sections | `_list-row.tsx` | AppBoxKitListTile, AppBoxKitListSection |
| Card | `_card.tsx` | AppBoxKitGlassCard, AppBoxKitFrostedSurface |
| Chip | — (component) | AppBoxKitChip, AppBoxKitChipCarousel |
| Form fields + 422 | `_form-field.tsx` | AppBoxKitNativeTextField + AppBoxKitFieldController (forms kit) |
| Search / filter | — (component) | AppBoxKitNativeSearchBar |
| Dialog / popover | `_dialog.tsx` (server-driven), `_modal.tsx` (declarative) | ui_library sheet/dialog services; AppBoxKitNativePopupMenu |
| Bottom sheet | `_bottom-sheet.tsx` | ui_library sheet service |
| Toast | `_toast.tsx` | AppBoxKitNotificationService.show |
| Table / data density | — (component) | none — compose AppBoxKitListTile / custom |
| Empty state | `_empty-state.tsx` | none — compose icon + copy + AppBoxKitNativeButton |
| Loading / skeleton | — (motion.css) | AppBoxKitNativeLoadingIndicator, AppBoxKitNativeProgress, AppBoxKitLazyIndexedStack |
| Pagination / load-more | — (components) | AppBoxKitLazyIndexedStack |
| Multi-view panel | `_panel-views.tsx` | per-shell panel controller (view/size/filter) + adaptive panel — compose |
| Auto Layout | — (attribute layer in widgets.css) | Row/Column + Expanded (fill) / SizedBox (fixed); Stack + Positioned (ignore) |
