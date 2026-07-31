# Regime-4a — CSS @keyframes Timeline Capture (design spec)

**Status:** approved design; implementation plan to follow (`docs/plans/regime4a-keyframes-capture.md`).
**Rung:** P12, first half of Regime-4 ("authored-rule/keyframe parse"). The second half —
authored cascade (R4b) — is deferred to its own brainstorm (blocked on a matched-vs-inactive
content-free wall; see §10).

**Goal:** capture, as an additive per-node `keyframes` sidecar, the time-driven CSS `@keyframes`
animation timeline each element references — keyframe offsets + animated-property values + timing —
content-free, joined by `backendNodeId`. This is the intermediate animation *curve* that the
R1–R3 computed-snapshot regimes structurally cannot see (they capture only static states).

---

## §1 — Probe premise (throwaway host-CDP probe; run + deleted by the controller)

Two synthetic-page probes (self-authored → IP-safe to inspect fully) established, by **measurement**:

- **PR1 — `getAnimations()` is running-only and systematically misses entrance one-shots.**
  At t=1.5s post-navigate, `document.getAnimations()` returned only a `running` (long-delay, in
  before-phase) and a `finished+fill:forwards` animation; a **`fill:none` finite one-shot that had
  finished was ABSENT.** Because real captures snapshot *after* adaptive settle, fill:none entrance
  animations (fade/slide-in on load) finish first and are missed systematically — not as an edge case.
- **PR2 — `CSS.getMatchedStylesForNode.cssKeyframesRules` covers ALL play states** (the decisive
  fact). Called on a finished one-shot, a not-yet-started (5s-delay) node, and a finished+retained
  node, it returned `cssKeyframesRules_count=1` with full frames for each. It is keyed off the
  computed `animation-name`, which stays set in every play state. → authored path is the primary
  mechanism; coverage is measured, not inferred.
- **PR3 — `cssKeyframesRules` frame shape:** each keyframe carries `keyText` — a CDP `Value`
  object `{text, range}`, NOT a bare string; the selector string (`"0%"`/`"50%"`/`"100%"`) is
  in `.text`, and the parser unwraps `.text` (same as `animationName.text` was always handled —
  corrected after the host gate surfaced the real shape)
  + `style.cssProperties` (`name`,`value`); properties arrive **duplicated** (longhand + shorthand
  expansion) and each frame carries an internal source `range` (line/col). The rule carries
  `animationName.text` (`"spin"` — an **author identifier**). Parse drops `range`, dedups props,
  and **drops the name**.
- **PR4 — `CSS.getMatchedStylesForNode` returns ONLY the node's referenced keyframes** (probe1:
  `.spinner` → 1 (`spin`); a no-animation `.brandbox` → none). No name-matching needed: take what
  is returned for the node.
- **PR5 — computed `animation-*` is the candidate selector + the content-free timing source.**
  `animation-name != "none"` identifies which nodes animate; `animation-name` is a **list** for
  multi-animation nodes and pairs positionally with the `animation-duration`/`-timing-function`/
  `-iteration-count`/`-direction`/`-delay`/`-fill-mode` lists. All of these are content-free
  (enums/numbers); the name is used transiently to find candidates and is never persisted.
- **PR6 — zero new CDP wiring.** The `CSS` domain is already `enable`d (R3b uses
  `CSS.forcePseudoState`), and `DOM.pushNodesByBackendIdsToFrontend` (backendNodeId → frontend
  nodeId) is already plumbed by R3b. R4a reuses both verbatim.
- **PR7 — `getAnimations().getKeyframes()` gives a fully-COMPUTED timeline** (offset, resolved
  value, per-keyframe easing, computedOffset) but only for *running* animations (PR1). This is the
  basis of the documented `var()`/`calc()`-resolution follow-on (§6), not the primary path.

---

## §2 — Scope, props, sidecar shape

### §2.1 `ANIMATABLE_PROPS` (curated, content-free)

The props `@keyframes` typically drive, all content-free (CSS keywords/lengths/functions/colors):

```
transform, opacity, filter, color, background-color, border-color,
box-shadow, translate, rotate, scale
```

Curated, not exhaustive — mirrors the R1–R3 whitelist discipline. Layout-thrash props
(`width`/`height`/`top`/`left`) are excluded: bbox already carries rendered size, and they are not
the design-salient part of an animation curve. The set is a single constant, extendable later.

### §2.2 Candidate / timing props

Added to the captured computed-prop set (used for candidate selection + timing; content-free):

```
animation-name (TRANSIENT — candidate select + positional pairing; NEVER persisted),
animation-duration, animation-timing-function, animation-iteration-count,
animation-direction, animation-delay, animation-fill-mode
```

### §2.3 Per-node sidecar shape

```
keyframes: [
  { timing: { duration, easing, iterations, direction, delay, fill },
    frames: [ { offset: 0.0, props: { transform: "rotate(0deg)" } },
              { offset: 1.0, props: { transform: "rotate(360deg)" } } ] },
  ...one entry per animation on the node...
]
```

`offset` is `float` (parsed from `keyText`: `"50%"` → `0.5`; `from`/`to` → `0.0`/`1.0`). Timing
values are content-free (`duration` ms or seconds-string, `easing` the timing-function string,
`iterations` number or `"infinite"`, etc.). No `@keyframes` name, no `backendNodeId`, no source
ranges. A node with no animation gets no `keyframes` field.

---

## §3 — Capture flow (`capture_with_keyframes`)

Single navigate (no per-condition re-navigate — unlike R3a/R3c there is no global override; this is
a one-pass enrichment). Steps:

1. `_capture_one(ev, engine, url)` → base skeleton + `node_backend` ({node_id: backendNodeId}).
   Then a dedicated `_snapshot_recs(ev, ANIM_CANDIDATE_PROPS)` read (same navigate, no override —
   the 3c-generalized `_snapshot_recs(ev, props)` already supports non-`WANT_STYLES` lists) →
   `{backendNodeId: {animation-*}}`, re-keyed to `node_id` via `node_backend`.
2. Candidate node_ids = those whose computed `animation-name != "none"`.
3. For each candidate: `DOM.pushNodesByBackendIdsToFrontend([backendNodeId])` → frontend nodeId
   (R3b plumbing); `CSS.getMatchedStylesForNode(nodeId)` → `cssKeyframesRules`.
4. Parse each `cssKeyframesRule` → `frames` over `ANIMATABLE_PROPS` (keyText→offset; dedup
   longhand/shorthand; drop `range`; drop name). Pair each with its timing from the node's
   positional `animation-*` lists (PR5).
5. Attach `_node_keyframes[node_id] = [{timing, frames}, ...]`.

CDP-only (`hasattr(ev,"sess")` guard). No `Emulation` override → no `clearDeviceMetricsOverride`
cleanup needed. Drop-on-miss: a candidate whose `getMatchedStylesForNode` returns no
`cssKeyframesRules` (e.g. animation-name references a non-existent `@keyframes`) is simply omitted.

---

## §4 — Join

`backendNodeId` (probe-stable, internal) is the candidate→keyframes join: the computed snapshot
gives `{node_id: backendNodeId}` and `animation-name`; the push converts backendNodeId→frontend
nodeId for the `getMatchedStylesForNode` call; results re-key to `node_id` for the sidecar.
`backendNodeId` and frontend `nodeId` are INTERNAL — never written to disk.

---

## §5 — Reuse map

**New code:**
- `_style.redact_keyframes` — redactor for the `[{timing,frames}]` shape (belt: any `url()`/data-uri
  in a value → `url("<asset>")`; values are otherwise content-free animatable keywords/lengths).
- `bundle_writer.apply_node_keyframes(nodes, node_kf)` — mirrors `apply_node_responsive`/`_theme`/
  `_pseudo_state`: attach redacted `keyframes` field; runs before `cf.redact_node`.
- a frame-parse helper (keyText→offset, dedup, whitelist filter, drop range/name).
- `web_skeleton.capture_with_keyframes` + `--keyframes` flag (its own `elif` branch).

**Reused unchanged:** R3b `DOM.pushNodesByBackendIdsToFrontend` push; the `_node_*` sidecar →
`bundle_writer.main` pop (`int(k)` re-key) → `assemble(..., node_keyframes=None)` →
`apply_node_*` → firewall pattern; `content_firewall.py` (`keyframes` is not a CONTENT_KEYS entry;
`redact_node` preserves it; `audit_bundle`'s key-aware walk recurses into
`node.keyframes[i].frames[j].props[prop]` and `node.keyframes[i].timing`).

---

## §6 — Ceilings (documented, not silently dropped)

- **`var()`/`calc()` in keyframe values unresolved.** Authored `cssKeyframesRules` values are
  authored text, not computed (PR3); a keyframe using `var(--x)` keeps `var(--x)`, not the resolved
  value. The computed `getAnimations().getKeyframes()` path (PR7) would resolve them but is
  running-only (PR1) — captured as a noted follow-on (a hybrid: authored for coverage + computed
  overlay for running nodes), explicitly out of R4a scope.
- **CSS transitions (`transition-*`) are not `@keyframes`** — out of scope (no discrete timeline;
  a separate future rung if needed).
- **JS/scroll-driven motion** (GSAP, scroll-linked) is `web_anim`/`web_states`' domain, not CSS
  `@keyframes` — out of scope, no overlap.
- **Multi-animation positional pairing** assumes `animation-name[i]` ⇄ `animation-duration[i]` etc.
  (the CSS spec's list-pairing rule); a node with mismatched list lengths uses CSS repetition
  semantics — documented, handled by the parse helper.

---

## §7 — Bundle + firewall

`bundle_writer` threading mirrors `responsive`/`theme`/`pseudo_state` exactly:
`main` pops `_node_keyframes` (before `_node_backend`), `int(k)`-re-keys, passes
`node_keyframes=` to `assemble`; `apply_node_keyframes` attaches the redacted field after the other
`apply_node_*` calls and before `cf.redact_node`. `content_firewall.py` is **UNCHANGED** — a
prose-canary test plants un-redacted prose in `node.keyframes[0].frames[0].props.transform` and
asserts `audit_bundle` trips via the key-aware prose walk (TDD inversion: passes without touching
the firewall — proves the existing walker recurses into the new key).

---

## §8 — Testing

- **Host CDP gate** (`fixtures/keyframes/run_keyframes.py`, controller-run): synthetic page with
  `#spin` (infinite `transform` rotate), `#pulse` (3-stop `opacity`+`transform`), `#oneshot`
  (fill:none finite — must be captured though absent from `getAnimations`, proving PR2 end-to-end),
  `#delayed` (long delay — not-yet-started, must be captured), `#static` (no animation → no
  `keyframes` field, isolation). Asserts: offsets/props correct per node; `_node_keyframes` /
  `_node_backend` / per-node `backend` never on disk; `@keyframes` name never on disk; bundle audit
  CLEAN.
- **Unit:** `redact_keyframes` shape + url-belt; frame-parse helper (keyText→offset, dedup,
  whitelist, multi-anim pairing); `apply_node_keyframes` attach + None-safe; `capture_with_keyframes`
  orchestration (fake CDP: candidate select, push, parse, sidecar); firewall prose canary.
- **Content-free real-site harness** (`fixtures/keyframes/validate_realsite.py`): prints ONLY host
  netloc + count of nodes-with-keyframes + animatable-prop NAMES + counts; never values/full-URL.
  `bundle_writer` raising = caught leak.

---

## §9 — CLI

`--keyframes` (a bare flag; no argument) joins the existing mutually-exclusive
`if args.themes / elif args.pseudo_states / elif args.breakpoints / elif args.viewports / else`
chain (first-match-wins, documented). Guards `hasattr(ev,"sess")` → `die` with a CDP-transport hint
on non-CDP transports.

---

## §10 — Relationship to R4b (deferred)

R4b (authored cascade) is a **separate rung**, blocked on a content-free wall the probe surfaced:
matched-only authored rules are content-free-coherent but modest value (provenance over
already-captured values); inactive authored rules (`.dark-mode`, variant classes) are the
high-value part but binding one requires the author **class name** — a head-on collision with the
content-free invariant (no matching element to synthesize a structural selector from). R4b gets its
own brainstorm opening with that matched-vs-inactive tier decision. R4a does not depend on it.
