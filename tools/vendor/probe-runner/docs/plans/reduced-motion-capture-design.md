# Reduced-motion Capture (design spec)

**Status:** approved design; implementation plan to follow (`docs/plans/reduced-motion-capture.md`).
**Rung:** P13. A standalone accessibility-variant rung (NOT part of Regime-4, which is
authored-rule/keyframe parse + cascade). Sits beside Regime-3a as another emulated-media
condition, but with a motion-focused watched prop set and its own sidecar.

**Goal:** capture, as an additive per-node `reduced_motion` sidecar, the computed-style
DELTA each element exhibits under emulated `prefers-reduced-motion: reduce` — i.e. which
motion-bearing properties (animation/transition/scroll) the design suppresses or shortens
for the accessibility variant — content-free, joined by `backendNodeId`. This is the
declared reduced-motion adaptation the R1 static snapshot cannot see.

---

## §1 — Probe premise (throwaway host-CDP probe; run + deleted by the controller)

A self-authored synthetic page (`@media (prefers-reduced-motion: reduce)` rules → IP-safe to
inspect fully) established, by **measurement**:

- **PR1 — `Emulation.setEmulatedMedia` with `prefers-reduced-motion` is effective.** Setting
  `features=[{name:"prefers-reduced-motion", value:"reduce"}]` and re-reading computed style
  changed the page's motion props; flipping back to `no-preference` is the clean base. Same
  CDP mechanism Regime-3a already uses for `prefers-color-scheme`/`forced-colors`/
  `prefers-contrast` — **zero new CDP wiring.**
- **PR2 — six watched props move under `reduce` (measured base → reduced):**
  `animation-name` (`spin` → `none`), `animation-duration` (`2s` → `0s`),
  `animation-iteration-count` (`infinite` → `1`), `transition-duration` (`0.5s` → `0s`),
  `transition-property` (`opacity` → `none`), `scroll-behavior` (`smooth` → `auto`). All are
  content-free CSS keywords/durations. `scroll-behavior` confirms the common
  smooth-scroll-off pattern is captured.
- **PR3 — `animation-play-state` does NOT move** (`running` → `running`). Turning an
  animation off via `animation: none` removes the animation entirely; the default
  `play-state` of "no animation" is still reported `running`, so it carries no reduced-motion
  signal. **Excluded** from the watched set (anti-bloat; measured, not inferred).
- **PR4 — the delta is the same shape as a Regime-3a theme delta.** It is a flat
  `{prop: value}` map of changed computed props, identical in structure to a `dark`/`contrast`
  condition delta → the `_theme` pure core (`diff_theme`/`build_node_theme`/`rekey_by_node_id`)
  and the `redact_theme` redactor apply VERBATIM (the redactor is a true alias, not a new
  walker — unlike R4a's `[{timing,frames}]` shape).

---

## §2 — Scope, props, sidecar shape

### §2.1 `MOTION_PROPS` (curated, content-free; probe-confirmed)

```
animation-name, animation-duration, animation-iteration-count,
transition-duration, transition-property, scroll-behavior
```

Six props, every one measured (PR2) to move under `reduce`. `animation-play-state` excluded
(PR3). Layout/size props excluded (bbox carries size; not motion). `MOTION_PROPS` is a single
constant, extendable later. NOT a subset of `THEME_PROPS` — hence a dedicated capture path
with its own prop list (the same reason Regime-3c's `RESPONSIVE_PROPS` is dedicated).

### §2.2 Per-node sidecar shape

```
reduced_motion: { "reduce": { animation-name: "none", animation-duration: "0s",
                              transition-duration: "0s", scroll-behavior: "auto", ... } }
```

A `{label: {prop: value}}` map with the single label `"reduce"` — identical in structure to
`theme: {dark:{...}, contrast:{...}}`. Only CHANGED props appear (diff vs base). A node with no
reduced-motion delta gets no `reduced_motion` field. Values are content-free CSS
keywords/durations. No `backendNodeId`.

---

## §3 — Capture flow (`capture_with_reduced_motion`)

Single navigate (mirrors `capture_with_themes` with ONE condition). Steps:

1. `_capture_one(ev, engine, url)` → base skeleton + `node_backend` ({node_id: backendNodeId}).
2. `Emulation.setEmulatedMedia({features:[{name:"prefers-reduced-motion", value:"no-preference"}]})`;
   `base = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))`.
3. `Emulation.setEmulatedMedia({features:[{name:"prefers-reduced-motion", value:"reduce"}]})`;
   `cond = _theme.styles_by_backend(_snapshot_recs(ev, MOTION_PROPS))`.
4. `delta = _theme.diff_theme(base, cond, MOTION_PROPS)` (per backendNodeId).
5. `node_rm = _theme.build_node_theme({"reduce": delta})` (re-keyed to node_id via
   `node_backend` inside the `_theme` core); `sk["_node_reduced_motion"] = {str(k): v ...}`.
6. `Emulation.setEmulatedMedia({features: []})` — clear emulation (mirror
   `capture_with_themes`' final clear), leaving the session unpolluted.

CDP-only (`hasattr(ev,"sess")` guard). No device-metrics/pseudo-state machinery. Drop-on-empty:
a node with no changed prop yields no delta and no field.

---

## §4 — Join

`backendNodeId` (DOMSnapshot-stable across the base→reduced re-snapshot on one navigate) is the
join: both snapshots key by backendNodeId; `diff_theme` diffs per backend; `build_node_theme`/
`rekey_by_node_id` map back to `node_id`. `backendNodeId` is INTERNAL — never written to disk.

---

## §5 — Reuse map

**New code:**
- `web_skeleton.MOTION_PROPS` constant.
- `web_skeleton.capture_with_reduced_motion` + `--reduced-motion` flag (its own `elif` branch).
- `bundle_writer.apply_node_reduced_motion(nodes, node_rm)` — mirrors `apply_node_theme`;
  attaches the redacted `reduced_motion` field; runs before `cf.redact_node`.
- `_style.redact_reduced_motion = redact_theme` — an ALIAS (same flat `{label:{prop:value}}`
  shape; identical to how `redact_pseudo_state`/`redact_responsive` alias `redact_theme`).

**Reused unchanged:** `Emulation.setEmulatedMedia` (R3a); `_snapshot_recs(ev, props)` (already
generalized for non-`WANT_STYLES` lists); `_theme.diff_theme`/`build_node_theme`/
`styles_by_backend`/`rekey_by_node_id`; the `_node_*` sidecar → `bundle_writer.main` pop
(`int(k)` re-key) → `assemble(..., node_reduced_motion=None)` → `apply_node_*` → firewall thread;
`content_firewall.py` (`reduced_motion` is not a CONTENT_KEYS entry; `redact_node` preserves it;
`audit_bundle`'s key-aware walk recurses into `node.reduced_motion.reduce.<prop>`).

---

## §6 — Ceilings (documented, not silently dropped)

- **Declared variant only.** Captures the CSS-declared reduced-motion adaptation (computed-prop
  delta). Whether JavaScript actually honors `matchMedia('(prefers-reduced-motion: reduce)')`
  to suppress JS-driven motion is NOT captured — that is `web_anim`'s domain, out of scope.
- **No re-capture of the R4a keyframes timeline under reduce.** When a site sets
  `animation: none`, the `animation-name → none` delta already records the suppression; the
  full keyframes re-capture adds nothing for the common case and is explicitly out of scope
  (a possible follow-on only if sites are measured to commonly SWAP `@keyframes` under reduce).
- **Single condition.** Only `reduce` vs `no-preference`; there is no third
  `prefers-reduced-motion` state to capture.

---

## §7 — Bundle + firewall

`bundle_writer` threading mirrors `theme`/`responsive` exactly: `main` pops
`_node_reduced_motion` (before `_node_backend`), `int(k)`-re-keys, passes
`node_reduced_motion=` to `assemble`; `apply_node_reduced_motion` attaches the redacted field
after the other `apply_node_*` calls and before `cf.redact_node`. `content_firewall.py` is
**UNCHANGED** — a prose-canary test plants un-redacted prose in
`node.reduced_motion.reduce.<prop>` and asserts `audit_bundle` trips via the key-aware prose
walk (TDD inversion: passes without touching the firewall — the existing walker already reaches
the new key; this is the same flat dict nesting as `theme`).

---

## §8 — Testing

- **Host CDP gate** (`fixtures/reduced-motion/run_reduced_motion.py`, controller-run): synthetic
  page with `@media (prefers-reduced-motion: reduce)` rules — `#known` (animates + smooth-scroll
  ancestor → carries the reduce delta: `animation-name`→`none`, `animation-duration`→`0s`,
  `scroll-behavior`→`auto`), `#static` (no motion → no `reduced_motion` field, isolation).
  Asserts: the delta props/values correct per node; `_node_reduced_motion` / `_node_backend` /
  per-node `backend` never on disk; bundle audit CLEAN. Nodes identified by fixed-px bbox
  (motion props don't change layout size — no rotate/scale AABB issue from R4a).
- **Unit:** `MOTION_PROPS` shape test; `capture_with_reduced_motion` orchestration (fake CDP:
  base/reduced snapshot, diff, sidecar keyed by str, name/backend internal); `redact_reduced_motion
  is redact_theme` alias assertion; `apply_node_reduced_motion` attach + None-safe; firewall prose
  canary.
- **Content-free real-site harness** (`fixtures/reduced-motion/validate_realsite.py`): mirrors the
  (now content-free) `fixtures/keyframes/validate_realsite.py` — prints ONLY host netloc + count of
  nodes-with-reduced_motion + the SET of changed-prop NAMES + counts; never values/full-URL.
  Failure paths print returncode only (never subprocess stderr — the content-free harness
  convention established when the `ContentLeak` message was scrubbed).

---

## §9 — CLI

`--reduced-motion` (a bare flag; no argument — single condition, so unlike `--themes` it takes no
labels) joins the existing mutually-exclusive
`if args.themes / elif args.pseudo_states / elif args.breakpoints / elif args.keyframes /
elif args.viewports / else` chain (first-match-wins). Its branch assigns `out_obj`, guards
`hasattr(ev,"sess")` → `die` with a CDP-transport hint, and closes `ev` in `finally` — mirroring
the `--keyframes` branch.

---

## §10 — Relationship to other rungs

Reduced-motion is a sibling of Regime-3a (another emulated-media condition) but distinct: a
motion-focused prop set and its own `_node_reduced_motion` sidecar/field (not folded into
`_node_theme`, to keep the accessibility-variant signal cleanly separable). It is independent of
R4a (keyframes) and R4b (cascade); it does not depend on or block either.
