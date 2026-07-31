---
name: "mobile-prototype"
description: "Mobile prototype\nPin-to-home-screen-ready mobile prototype"
---
The user is building a mobile prototype that they'll open on an iPhone and pin to their home screen. Build it as an Artifact served by the Runtime (the contract is `runtime/README.md`), ready for that flow by default — don't ask first.

## Required <head> tags

> **Viewport ladder — not optional.** Author this surface at **every rung in
> the active ladder**, derived from the project's targets and read from config
> — never assumed to be phone-only. See
> [`../references/viewport-ladder.md`](../references/viewport-ladder.md). What
> the prototype omits at a width, someone downstream invents without ever
> seeing your design.
>
> **Declare structure as you go** — registry entry and `surfaceId` before the
> directory exists, per [`declare-structure.md`](declare-structure.md).


Always include these in `ui/common/base.html`'s head (alongside the boilerplate htmx meta config), otherwise the "pin to home screen" banner won't trigger in the preview and the prototype won't install cleanly:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="<short prototype title>">
<link rel="apple-touch-icon" href="/assets/images/icon.png">
<link rel="icon" href="/assets/images/icon.png">
```

## App icon

Create an icon.png in the artifact's `assets/images/` (512×512, square, no transparency on the edges — iOS masks it to a rounded square itself). Make a simple, bold mark that reads at small sizes: a single glyph or monogram on a solid or two-tone background. Avoid photo backgrounds, tiny type, or gradient washes that muddy at 60×60. If the user hasn't specified a brand, pick a deliberate single accent color and use it consistently across the icon and the prototype UI. If an image backend is available you can **generate** this icon — see [`generate-images.md`](generate-images.md) — still favoring a simple, bold mark that reads at 60×60; save it as `assets/images/icon.png`. With no backend, draw a simple mark instead.

## Layout — full-bleed with device frame on desktop

By default, the app should fill the entire viewport on phone widths (safe-area insets honoured via env(safe-area-inset-*)) — no page chrome, no max-width container, edge-to-edge content. The status bar area should feel intentional (matching background or a gradient that tucks under the notch).

On large viewports, present the app inside a device frame so the designer can see it as a "phone on desktop" during iteration: copy `starter-partials/frames/ios.html` (or `android.html`) plus `starter-partials/frames/frames.css` into the artifact and render each surface as the frame's content. The partial carries the device-sized rectangle (~390×844), corner radius, and drop shadow in pure CSS; the app content inside keeps its full-bleed phone layout unchanged.

## No fake chrome

Do NOT draw a fake iOS status bar (the "9:41 · battery · wifi" strip at the top) or a fake virtual keyboard at the bottom in your surfaces. When the prototype is installed to the home screen, the real iOS status bar and real keyboard render on top of your layout — a painted fake looks doubled up and childish. Leave that space alone and let env(safe-area-inset-top) / env(safe-area-inset-bottom) reserve the room. Device chrome in the desktop preview belongs to the frame partial, never to your app content.

App content lives in surfaces inside the shell — `base.html` already wraps everything in the in-body `#app`. Navigation, state, transitions, forms — everything that makes it feel like a real app — all work through the Runtime: boosted navigation between surfaces, htmx swaps for in-place updates, server-side state per the State Playbook. Zero custom client-side JavaScript — `appbox design lint <artifact-dir>` must stay clean.
