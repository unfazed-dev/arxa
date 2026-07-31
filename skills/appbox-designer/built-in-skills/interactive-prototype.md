---
name: "interactive-prototype"
description: "Interactive prototype — a working hypermedia app with real interactions, real state, zero custom client-side JS"
---

Build a fully interactive prototype as a **server-first hypermedia app**: every screen is a real URL serving a full page; interactions are htmx requests answered with server-rendered fragments; state lives on the server. It should feel like a real working app — hover states, form validation, animated transitions, multi-step flows — with no React, no client state, no hand-written JS.

**Read `runtime/README.md` (the contract) and copy `examples/hello-hda/` before writing anything.** What follows is the authoring playbook.

## Authoring flow

> **Viewport ladder — not optional.** Author this surface at **every rung in
> the active ladder**, derived from the project's targets and read from config
> — never assumed to be phone-only. See
> [`../references/viewport-ladder.md`](../references/viewport-ladder.md). What
> the prototype omits at a width, someone downstream invents without ever
> seeing your design.
>
> **Declare structure as you go** — registry entry and `surfaceId` before the
> directory exists, per [`declare-structure.md`](declare-structure.md).


1. Inventory the screens and their URLs (the route table *is* the app map).
2. Copy `examples/hello-hda/` → your artifact dir; rename shell/surfaces.
3. Models + fixtures first (`models/`, `services/repositories|facades/`) — the data the screens bind to.
4. Shell (chrome + nav) in `ui/views/<shell>_shell/`, then one Surface at a time: `<surface>_view.html` (page + Named Fragment macros) + `<surface>_viewmodel.js` (context builders + handlers).
5. Serve, then verify per surface: `appbox design lint`, `appbox lens check`, playwright screenshot + `ReadMediaFile`.

## The playbook (copy these patterns)

- **Navigation** — plain `<a href>`; `<body hx-boost>` upgrades it. Every pushed URL must render a full page (deep links, back button, cache-miss restore). Long nav lists get `preload` for snap.
- **Partial update** — `hx-get="/x" hx-target="#y" hx-swap="outerHTML"` where `/x` returns a Named Fragment (`view.html#macro`) for `HX-Request` calls. Server branches full-page vs fragment in the ViewModel.
- **Forms** — real `<form>` + HTML5 validation (`reportValidityOfForms` is on). Valid POST → 200 with the next-state fragment (no PRG needed). Invalid → **422 + re-rendered form** (the meta config swaps 422s). Mutations that change nothing visible → `h.noContent(c)` (204).
- **Tabs / filters** — URL-as-state: GET form or links with `?tab=…`, server renders the active state, `hx-push-url="true"` so it deep-links.
- **Sheets / dialogs** — deep-linkable flows get **real routes** (a sheet is a page styled as an overlay; back button closes it). Transient confirmations: a fragment swapped into a persistent `#modal` container in the shell. Trivial popovers: the Popover API (`<button popovertarget>`), and the Invoker Commands API (`commandfor`/`command="show-modal"`) for modal dialogs — both zero-JS.
- **Toasts** — respond with the main swap + `<div hx-swap-oob="beforeend:#toasts">…</div>` (or `hx-swap="none"` for pure-OOB responses). Expiry: CSS fade (stays in DOM) or the `load delay:5s` → null-endpoint + `HX-Reswap: delete` pattern.
- **Theme / accent / role** — POST to a prefs endpoint → `h.setPrefs(c, …)` → `h.refresh(c)` (full reload; body/html attributes don't update under boosted swaps). Render CSS vars on an in-body wrapper (`#app`).
- **Timers / countdowns** — server holds the deadline; the view polls: `hx-get="/timer/tick" hx-trigger="load delay:1s" hx-swap="outerHTML"`, each tick renders `timers.remaining(id)`, and the fragment drops its trigger (or the handler answers `h.stopPolling(c)`, 286) at zero. Never decrement client-side.
- **Preserve Islands** — a playing media element that must survive navigation: `<div id="player" hx-preserve>` with the same id on every page. Never answer a request touching it with `hx-swap="none"`.
- **Race safety** — `<body hx-sync="this:replace">` (already in `base.html`); buttons that mutate get `hx-disabled-elt="this"`.

## Motion (CSS only)

Pull `starter-partials/motion.css` into the artifact. Recipes: exit = `.htmx-swapping` transition + `swap:<dur>`; entry = `.htmx-added` start state + `settle:<dur>`; route morphs = `view-transition-name` on shared chrome (global view transitions are enabled in the meta config); popovers = `:popover-open` + `@starting-style` + `allow-discrete` on `display`/`overlay`; accordions = `::details-content` (fallback `grid-template-rows: 0fr→1fr`). Wrap all opt-in motion in `@media (prefers-reduced-motion: no-preference)`.

## Read States

Every list/feed surface renders the closed set — idle, loading (indicator CSS during the request), error, empty, data — as server-side template branches, switchable via a `?state=` param on the surface's URL for design review.

## Accessibility floor

Semantic HTML, `<label>` on every input, `aria-live="polite"` on async swap targets, never swap the element that currently has focus, prefer `<details>`/dialog/popover natives over ARIA-heavy widgetry.

## Do NOT attempt (needs custom JS — out of the contract)

Live clocks without a server tick, drag/swipe gestures, canvas/Lottie, auto-dismiss that removes DOM on a timer without a poll, client-computed validation messages, query-param logic that bypasses the server. If a design genuinely needs one, say so and propose the closest playbook alternative.

## Verify before surfacing

`appbox design lint <artifact-dir>` → `appbox lens check <url>` → `npx playwright screenshot <url> /tmp/x.png` + `ReadMediaFile`. All three pass, then give the user the served URL.
