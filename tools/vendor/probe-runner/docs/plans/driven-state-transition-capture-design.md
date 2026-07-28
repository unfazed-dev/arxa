# Driven-state transition capture — design spec

**Status:** approved (2026-05-31). Next: implementation plan via writing-plans → subagent-driven execution.

**Roadmap context:** First roadmap item after per-state component capture (P4). Continues the G4 / `web_states` line. Completes CONTEXT.md **principle #3** ("A component is States + Transitions") for the web (CDP) substrate: P4 captured each driven State *as a component*; this captures the **Transition** that reveals it.

---

## Goal

For each driven interaction State, capture the **revealing animation as a content-free motion-law** (which properties animate, duration, delay, easing) and attach it to that State's `component`. Read the engine's **declared** law — never sampled frames.

## Principle alignment

- **Content-free invariant.** The transition carries ONLY: CSS property *names* (`transform`/`opacity`/… — names, never values), numeric `duration_ms`/`delay_ms`, a declared easing (cubic-bezier coefficients or a named keyword), and a `getBoundingClientRect()` bbox anchor. No page text, no keyframe values, no real URLs/bytes. The start/end geometry is already the REST→component endpoints; the law = props + timing + easing between them.
- **The core never guesses (on-ethos with `_anim_core`).** The declared law is **exact-by-construction** (read from the engine, not measured), so the reproduce-on-revisit certification that scroll-capture needs is moot for the law's *value*. What is NOT deterministic is *which* animations get caught (see Coverage ceiling) — the spec states this plainly rather than overclaiming.
- **Honest ceiling.** Un-mappable easings (`steps()`, mixed per-keyframe easing) and uncaught motion (JS-rAF with no WAAPI/CSS animation object; transitions shorter than capture latency) are recorded as `certified:false` + reason or simply absent — never force-fit.

## Mechanism — WAAPI `document.getAnimations()`

Chosen over the CDP `Animation` domain. Rationale:
- web_states is **already CDP-only** (`die()` if no `ev.sess`), so CDP Animation costs no transport symmetry — but the transport interface is deliberately **`ev(expr)`-only** (`_Eval` = `ev` + `close`; `sess` is a `_CDPEval` implementation detail with request/response `send` but **no event-buffering API**). CDP `Animation.animationStarted` collection would require extending the transport beyond its minimal contract **plus** backendNodeId→skeleton-node resolution.
- `getAnimations()` needs ONLY the existing `ev()` + an inline `getBoundingClientRect()` anchor; binds to a component node by bbox (the `match_motion` band approach). Zero new plumbing, respects the established abstraction.
- **Accepted cost:** `getAnimations()` is a *snapshot* → a poll-race. web_states drives the trigger, so we control capture timing; the residual miss (ultra-short / already-finished) is a documented honest ceiling.

## Coverage ceiling (explicit — NOT deterministic)

Each captured law's value is exact. **Coverage is best-effort:**
- Transitions that finish before the capture instant are missed.
- Transitions that have not yet *started* at the capture instant are missed — CSSTransition objects are created on the next style recalc, so calling `getAnimations()` in the same microtask as `click()` can return empty. Capture must occur in the **live window** (≈1–2 frames post-click), pinned by the feasibility gate below.
- JS-`requestAnimationFrame`-driven motion with no WAAPI/CSS animation object has no declared law → not captured (honest ceiling).

## Scope (YAGNI)

- **Open transition only** — the reveal. Not the close/reverse.
- Attach to the State's existing `component` (P4 structure). No new top-level bundle key.
- Schema stays **`probe-states/1`** — `transition` is an additive State key (the `component`/`consent` precedent).

## Data shape

```jsonc
"transition": {
  "n_anims": N,
  "anims": [
    {
      "node": <component-local id | null>,   // bbox-bound to a component node; null = mount/backdrop
      "props": ["transform", "opacity"],      // animated CSS property NAMES (content-free)
      "duration_ms": 240.0,
      "delay_ms": 0.0,
      "easing": {
        "klass": "ease-out" | "cubic-bezier" | "linear" | "steps",
        "bezier": [x1, y1, x2, y2] | null     // control points; null ONLY when not bezier-representable (steps)
      },
      "certified": true | false,
      "reason": null | "steps()" | "mixed-keyframe-easing" | "unbound"
    }
  ]
}
```
`transition` is `null` when nothing animated on reveal.

### Easing mapping (`map_easing`)
- Declared `cubic-bezier(x1,y1,x2,y2)` → match a named easing in `_anim_core.EASINGS` within tolerance (`klass` = that name, `bezier` = its control points); else `klass:"cubic-bezier"` carrying the raw control points.
- `linear` → `klass:"linear"`, `bezier:[0,0,1,1]` (representable), `certified:true`.
- `steps(...)` → `klass:"steps"`, `bezier:null`, `certified:false`, `reason:"steps()"`. Mixed per-keyframe easing → `certified:false`, `reason:"mixed-keyframe-easing"`. Never force-fit a non-bezier law to a bezier.

### Node binding (`_bind_node`)
Match each animation's bbox anchor to a component-local node id by center/box proximity within a band (reusing the `match_motion`/`_matches_rest` proximity idea). No match → `node:null`, `reason:"unbound"` (e.g., the modal mount/backdrop, which P4 collapses into `mount`).

## Components / files

- **`scripts/_transition.py`** (new, pure core — no browser, no I/O, unit-tested):
  - `map_easing(declared_easing, kf_easings) -> {klass, bezier, certified, reason}`
  - `_bind_node(bbox, component, radius) -> int | None`
  - `build_transition(anims_raw, component, radius=24.0) -> {n_anims, anims} | None` (radius is tight — an animated element's own bbox should coincide with its component node's bbox, unlike `match_motion`'s 400px band for loosely-anchored scroll motion)
  - Imports `EASINGS` from `_anim_core`.
- **`scripts/web_states.py`** (modify):
  - Add `_TRANSITION_JS` (in-page `getAnimations()` reader emitting the raw records: `duration`, `delay`, `easing`, per-keyframe easings, property names, bbox, `playState`).
  - **Fix loop ordering** → `click → (live-window delay) → capture transition → sleep(0.3) → after snapshot → diff/component → build_transition`.
  - Attach `transition` per state; add `transitions_built` to the `--out` summary.
  - Import `build_transition` from `_transition`.
- **`scripts/test_transition.py`** (new): pure-core unit tests — easing mapping (named match, raw bezier, linear, steps→uncertified), node binding (match / unbound), `build_transition` (multi-anim, null-when-empty, content-free fields only), and a content-free assertion (no unexpected keys / no values).
- **`scripts/test_content_firewall.py`** (modify): add a test writing a `transition`-carrying states.json (cubic-bezier + named easing strings, property names, bbox) into a clean bundle and asserting `cf.audit_bundle(dir) == []` (advisor #4 — re-verify the P4 raw-token blocker).
- **`fixtures/transition/run_transition.py`** (new): host gate (CDP, `dangerouslyDisableSandbox`). Serves a page with a button revealing a `display`/`opacity` panel via a **240ms `ease-out`** `opacity`+`transform` transition; drives `web_states --url --out`; asserts a captured law with the right `duration_ms≈240`, `klass≈ease-out`, `props⊇{opacity,transform}`, bound to a component node. Doubles as the regression gate.

## Pre-build feasibility gate (advisor #1) — Task 0

A **go/no-go host spike** BEFORE any real implementation: prove a CSS transition is observable in `getAnimations()` at the capture instant, and pin the exact post-click live-window delay (≈1–2 frames). If transitions are not observable with `ev()`-only timing, stop and re-evaluate the mechanism before building. Same gate-before-claim discipline as P4, moved earlier per advisor.

## Testing strategy

- **Pure core** (`_transition.py`) → exhaustive unit tests (TDD), no browser.
- **Firewall** → real `cf.audit_bundle` on a `transition`-carrying states.json.
- **End-to-end** → offline host gate (`run_transition.py`) on a self-served page with a known transition; assert the law + binding + content-free output. Run on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox).

## Commits

Single-line messages, no trailers. Stage files explicitly by path. One commit per task. Local on master — do NOT push.
