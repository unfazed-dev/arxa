# Probe-runner

A **design extractor**: it drives a real browser/device (Chrome, iOS sim, Android emulator, Flutter) at any target and emits a content-free reproduction of a page/app's *design*, never a copy of its *content*.

## The architecture (4 principles)

1. **Design extractor, not a recorder.** Captures *design* — structure, geometry, tokens, layout, states, motion — for any target on any platform. It does not copy content.
2. **Content-free is a bundle invariant.** The firewall enforces it at packaging; a **capture verb** is a pure recorder that never runs the firewall.
3. **A component is States + Transitions.** Reproduce a component across its states (minus content), not as one frozen snapshot.
4. **Honest ceiling.** Where a region isn't reproducible (canvas/video/opaque embed, or native pixels), label it — never fake it.

Everything below is the glossary for these. Platform-specific *implementation* (how tokens are sampled, how states are driven, native fidelity mechanics) is decided when each platform is built — it is not architecture.

## Language

**Target**:
The single thing probe-runner is pointed at, runs, and controls — a web **URL**, or an app/bundle-id (iOS/Android/Flutter). Platform-agnostic input; the engine never branches on its identity.
_Avoid_: making "URL" special — URL is just the web target.

**Capture verb**:
A pure recorder that drives a **target** and emits raw structure (web: DOMSnapshot; native: a11y/semantics tree + screen-recording-derived motion). Content-blind — never runs the firewall.
_Avoid_: scraper, crawler.

**Mechanism**:
The reproducible part of a design — structure, geometry, design tokens, layout intent, motion, states. What probe-runner keeps.
Per-node visual CSS (filter, backdrop-filter, box-shadow, full border + corner radii, clip-path, mix-blend-mode, transform-origin, background gradients) is captured content-free as a resolved-value `style` field; an external image `url()` is redacted to a `url("<asset>")` marker at packaging (a same-document `#fragment` mechanism ref is kept).
_Avoid_: structure-only (tokens/motion are mechanism too).

**Content**:
The raw payload — text, image/video/audio bytes, real asset URLs. What probe-runner must NOT retain.
_Avoid_: data, assets (too broad).

**Bundle**:
The packaged, content-free output assembled by `bundle_writer`. Content-free is enforced, not assumed.
_Avoid_: capture, export, dump.

**Content firewall**:
The IP boundary (`content_firewall`) that redacts **content** from emitted nodes and audits a written **bundle** for any leak. A packaging-time gate — lives in `bundle_writer`/`slots`, never in a **capture verb**.
_Avoid_: filter, sanitizer, validator.

**Design token**:
An aggregate describing visual style — palette, type scale, spacing, radii, shadows. **Mechanism**, never **content**.
_Avoid_: theme, style (too broad).

**Slot**:
The typed placeholder a redacted **content** node becomes — `{type, box, aspect, sizing, fill_hint}` — that a rebuilding agent fills. Two families: **content slots** (`text`/`image`/`video`/`audio`/`svg`, swappable) and **opaque-substrate** placeholders (`canvas`/opaque-iframe — a live mechanism renders here; not swappable).
_Avoid_: field, element.

**State**:
One configuration of a component (dialog closed vs open, slider at a value, tab selected). A component is a graph of **States** + **Transitions**; the goal is to reproduce it across all its states, minus **content**. A page's load-time **occluding overlay** (a `position:fixed`, viewport-covering, top-of-stack layer — the consent-class mechanism) is one such State; `web_states` records it content-free (`kind:"occluding_overlay"`) and attempts a content-blind Escape **Transition**, honestly recording whether it `cleared`. It never clicks a button blind (that would take an unknown real action — an **Honest ceiling**). For a driven interaction State, `web_states` now records its revealed subtree as a content-free, reproducible `component` (re-rooted mini-skeleton: structure + sizing/layout/font + colors + a `mount` to its REST attach point), not just an appeared-node count — so a State is captured *as a component*, not merely detected. The reveal between REST and that State is captured as a content-free `transition` (the component's revealing motion-law: which CSS properties animate + duration + delay + easing, read from the engine's declared animation), completing the State→Transition pair for the web substrate. Coverage of which animations are caught is best-effort (an Honest ceiling); each captured law's value is exact.
_Avoid_: variant, mode.

**Transition**:
The motion between two **States** (a dialog's open animation, a slider's drag), captured as a numeric motion-law — never frames.
_Avoid_: animation (reserve for the law, not the frames).

**Honest ceiling**:
The labeled limit where a region can't be reproduced content-free (canvas/WebGL, video, cross-site iframe; on native, anything whose only style source is the content-bearing frame). The bundle marks the limit rather than faking past it.
_Avoid_: failure, gap (it's a declared boundary, not a bug).

**Provenance**:
Metadata about where a capture came from (the **Target**, a timestamp) — describes the capture, is not the page's payload. Lives in the bundle manifest.
_Avoid_: source, origin.

## Relationships

- A **capture verb** runs against any **target** and emits raw structure WITHOUT invoking the **content firewall**.
- `bundle_writer` assembles a **bundle**, then runs the **content firewall** as an unconditional gate.
- A redacted **content** node becomes a typed **Slot**; an un-reproducible region becomes an **Honest ceiling** marker.
- A component is reproduced as **States** (snapshots of **mechanism**) joined by **Transitions** (motion-laws).

## Example dialogue

> **Dev:** "If the firewall is core, does `web_skeleton` need it when capturing `https://site.com`?"
> **Domain expert:** "No. A **capture verb** is a pure recorder for *any* **target**. The **content firewall** runs later, when `bundle_writer` packages the **bundle**. Capture stays content-blind; packaging enforces content-free."
> **Dev:** "And a dialog?"
> **Domain expert:** "A dialog is two **States** plus a **Transition** — capture each state's **mechanism** and the motion between them, minus the text inside."

## Flagged ambiguities

- "URL" — resolved: just the **web target**, not special; the engine never branches on a target's value.
- Native implementation (token sampling, state driving, fidelity, medium detection) — out of architecture scope; **build-time** decisions governed by the **Honest ceiling** principle, recorded when each platform is built.
