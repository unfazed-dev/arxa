# Kasane motion re-baseline — live capture results & bundle assessment

> **✅ FIXTURE RE-CAPTURED & CORRECTED (2026-06-02, viewport 1440 — matches the original).** The
> committed `fixtures/kasane-rebaseline/` now reflects the **bound** state, not the node-229
> collision. Re-ran the live pipeline on the current engine (2D-binding fix landed: `web_skeleton`
> ÷dpr → CSS-px, `web_anim` emits transform-corrected `absX`, `match_motion` 2D-binds on `anchor_x`,
> `anim_ref` is a list). Acceptance — all met, **5 motion rows** (4 hero + 1 menu):
> - hero binds to **two distinct nodes**: "Handcrafted" (tx **−663.08**) → **node 77** (cx 395.5 =
>   anchor_x 395), "With Urushi" (tx **+663.08**) → **node 81** (cx 1052.9 = anchor_x 1053). No more
>   node-229 collision; both `certified`, `maxDriftPx=0`.
> - menu reveal **included**: `menu.reveal#op` (time/opacity, `cubic-bezier(0.76,0,0.24,1)`,
>   amplitude +1.0) → **node 10** (cx 1306.7 = anchor_x 1307, the header trigger) — a clean
>   single-mover time-class bind. Live getAnimations confirms it is unchanged: **52** in-nav spans,
>   opacity 0→1, dur 1000 ms, stagger 0/20/40… ms (`waapi.json`, fresh).
> - `anim_ref` is a **list** on every bound node: `10→['menu.reveal#op']`,
>   `77→['h1#0#tx','h1#0#op']`, `81→['h1#1#tx','h1#1#op']`.
> - **CSS-px frame**: hero text y≈415, page 1440×36130, max node y≈36130 (not ~2× device-px).
>
> **The 5/29 vs 6/2 deltas are VIEWPORT-SCALING, not page drift.** Captured at the documented 1440
> viewport, hero amplitude is ∓663.08 ≈ the original ∓647.565 (minor live variance). An
> intra-session capture at a narrower 1200 window gave ∓550.83 — and 550.83/663.08 ≈ 0.83 ≈
> 1200/1440, i.e. the amplitude (and absX 395/1053 vs 330/877, page height) scale with width. The
> animation did **not** change. Numbers in §1/§3 below are the 2026-05-29 device-px-frame capture
> (node 229, old file sizes) and are **historical** — the fixture now supersedes them.
>
> **The menu was a responsive breakpoint, not a redesign.** `.Nav_nav__dtTHU` is absent from REST
> DOM and below a ~1440 desktop breakpoint a narrower window never mounts it (REST count 0; mounts
> on burger click → `Nav_nav__dtTHU` + `Nav_wrapper`/`Nav_textContainer`/`Nav_imageContainer`). At
> 1440 it returns and is captured as above. Raw evidence: `anim.json` (web_anim, now carries
> `absX`), `waapi.json` (fresh menu getAnimations), `skeleton.json`/`tokens.json`/`motion.json`,
> `bundle/`. The old `anim_hero2.json` (device-px-era web_anim, no `absX`) is removed —
> superseded by `anim.json`.
>
> **Engine fix shipped first (commit before the fixture):** added `PROBE_RUNNER_CDP_TIMEOUT`
> (default 20s) to `_web_eval.py` — kasane's `DOMSnapshot.captureSnapshot` exceeds the WS read
> timeout; raised to 90s for this capture. A real robustness gap, not a fixture hack.

> **⚠️ SUPERSEDED IN PART (2026-05-29, same day).** §2 and §4 below diagnosed the binding
> failure as `match_motion` x-blindness. That was a real but SECONDARY symptom. The PRIMARY
> root cause, found while fixing it (plan `probe-runner-2d-motion-binding.md`), is that
> `web_skeleton` stored bboxes in **device px** while motion anchors were **CSS px** — a 2×
> mismatch on retina. In particular the "canonical REST y = 1061.5" claimed in §2 was a
> **device-px** value and is NOT the hero (the hero is y=365 CSS / 730 device). After the fix
> (web_skeleton ÷dpr; web_anim emits REST-frame absX/absY; adapter signed-amp + rank-unique
> names + anchor_x; match_motion 2D-binds + anim_ref as list), the two hero words bind
> correctly to two DISTINCT nodes (Handcrafted→node80 tx<0, With Urushi→node84 tx>0), each
> node's anim_ref a LIST carrying both its channels. Corrected bundle + raw evidence:
> `probe-runner fixtures/kasane-rebaseline/` (skeleton_css/anim_x/bundle_css) and
> `/tmp/kbundle/raw/t5.out`. Treat the numbers in §3 (which used the device-px skeleton) as
> the pre-fix state; the motion SHAPES (curves, mirror tx ∓216→∓864, menu reveal) remain
> correct — only the coordinate FRAME and binding were wrong.

**Date:** 2026-05-29 · **Task #33** · live page `https://kasane-keyboard.com/craftanddesign`
**Transport:** dedicated debug Chrome (`--remote-debugging-port=9222`, temp profile `/tmp/kbundle/chrome-profile`) ← probe-runner verbs via `--cdp-port 9222`.
**Artifacts:** `/tmp/kbundle/` + durable copy in probe-runner `fixtures/kasane-rebaseline/`.

Supersedes the stale §3 motion anchors flagged in `kasane-page-epoch`. Every number below is a **measured** scalar (file sizes via `os.path.getsize`, counts via `len()`, EXIT codes echoed) — this session's tool-text channel was corrupting/eliding output (see `env-verify-via-exitcodes-not-output`), and a draft of this doc carried two **fabricated** figures (a single-file md5 and "894 KB") that were never measured; they were caught and removed. Raw evidence: `/tmp/kbundle/raw/`.

---

## 1. What the live page actually does (ground truth)

### Scroll motion — hero `h1` (web_anim, certified)
Two **mirror** movers (a diverging parallax), NOT duplicates:

| mover | text | `tx` from→to | `op` from→to | curve | active scroll |
|---|---|---|---|---|---|
| 0 (`hL`) | "Handcrafted" | −216 → **−863.7** | 0.75 → 0 | `cubic-bezier(0,0,0.58,1)` ease-out | [165, 1088] |
| 1 (`hR`) | "With Urushi" | +216 → **+863.7** | 0.75 → 0 | `cubic-bezier(0,0,0.58,1)` ease-out | [165, 1088] |

Certifies only when the scroll `--range` is matched to the element's live REST y (used [165:1265], steps 32). Full-page coarse sampling certified **0 / 23** channels — the page is 32 310 px tall; coarse steps can't resolve any active window. **It was coarseness, not one-shot reveals.**

### Menu open — `.Nav_nav__dtTHU` (WAAPI getAnimations oracle, exact)
- **52** in-nav span animations, **all** `cubic-bezier(0.76, 0, 0.24, 1)`, **dur 1000 ms**, `fill: both`.
- **opacity 0 → 1 only. ZERO transform keyframes** — a staggered *text-opacity reveal*, NOT a slide.
- Stagger: **delay 0 → 300 ms** in 20 ms steps across the 52 spans.
- Backdrop `.Header_background__pMdl3` dims to opacity 0.5. Burger morphs on the same curve; 2× `<p>` ease-out 350 ms.
- `getComputedStyle.transitionDuration = 0s` → **framer/WAAPI, not a CSS transition** (source label reflects this: `waapi_getAnimations`).

### Live selectors (old ones stale)
- Menu **trigger** = `.Header_el__lSXpJ` (the real `onclick` handler, 67×15 px). The visible `.Header_burger__lA_tO` is a 23×2 px line inside it.
- Menu **panel** = `.Nav_nav__dtTHU`. Backdrop = `.Header_background__pMdl3`.

---

## 2. Anchor instability (the core re-baseline correction)

`web_anim` reported the hero `absY` as **365**, **1991**, then **1098** across load/scroll states. Cause: the hero is *itself being translated by the scroll animation*, so `getBoundingClientRect().top + scrollY` is **not** invariant mid-animation. The canonical REST y (skeleton frame) is **1061.5**.

→ Binding a scroll row at anchor 365 would attach hero motion to the **header** (nearest node within `match_motion`'s ±400 px band). **The re-baseline fix: anchor scroll rows to the skeleton REST frame (1061.5), not the producer's transient absY.**

---

## 3. The bundle (`bundle_writer`, schema `probe-skeleton/2`)

`bundle_writer --out` writes a **directory** (spec §5 layout), not a single file:

| file | bytes | md5(12) |
|---|---:|---|
| meta.json | 250 | e77d07ded007 |
| motion.json | 1 580 | 85c34c4dee11 |
| skeleton.json | 760 915 | 682894339ffe |
| tokens.json | 889 | a05c69aa72c2 |
| assets/manifest.json | 127 932 | ba271557fff2 |
| **total** | **891 566** | |

| section | result |
|---|---|
| meta | dpr 2, page 1440×32310, viewport 1440×813 |
| nodes | **951** (unknown_box 632, text 243, box 30, image 38, svg 8) |
| slots (manifest) | **289** (text 243, image 38, svg 8) |
| tokens | palette **6**, type_scale **17**, weights 4, families 6, spacing 19, radii 4, shadows 0 |
| motion | **5** rows, all pass `assert_contract`; round-trip `match_motion` = 5 in / 5 bound / 0 dropped |

motion rows (from the bundle's `motion.json`, verbatim):

| name | node_id | class | axis | amplitude | bezier | window | source |
|---|---|---|---|---:|---|---|---|
| hL#tx | 229 | scroll | x | −647.565 | 0,0,0.58,1 | [165,1088] | web_anim |
| hL#op | 229 | scroll | opacity | −0.75 | 0,0,0.58,1 | [165,1088] | web_anim |
| hR#tx | 229 | scroll | x | +647.565 | 0,0,0.58,1 | [165,1088] | web_anim |
| hR#op | 229 | scroll | opacity | −0.75 | 0,0,0.58,1 | [165,1088] | web_anim |
| menu.reveal#op | 28 | time | opacity | +1.0 | 0.76,0,0.24,1 | [0,1] | waapi_getAnimations |

---

## 4. Assessment — `match_motion` x-blindness degrades BOTH binding paths

The blocking finding: kasane's two hero words ("Handcrafted", "With Urushi") sit at the **same y (1061.5)** but different x, moving in **opposite** x directions (the signature diverging parallax). `match_motion` binds by **y-distance only (x-blind)**, so **all four co-located hero rows bind to the same node, id 229** (measured: `hL#tx node=229`, `hR#tx node=229`, collision `{229: 4}`). This loses the element→motion *assignment* on both paths the bundle exposes:

**Path A — `bundle/motion.json` array: DATA faithful, ASSIGNMENT degraded.** All 5 rows present; curve and sign are exact and distinct (`hL#tx −647.565`, `hR#tx +647.565` — signed amplitude is spec-conforming: the engine plan's contract example uses `-720`, `bundle_writer`'s test uses `-218.5`). The row *names* (`hL`/`hR`) still distinguish the two movers. **But every hero row carries `node_id=229`**, so a consumer that drives animation by node cannot tell which physical word diverges which way — both serialize against one skeleton node. The motion data survives; the mapping to two distinct skeleton nodes does not.

**Path B — `node.anim_ref` back-pointer: LOSSY (worse).** `anim_ref` is a single string; after assembly only **2** skeleton nodes carry it — node 28 (`menu.reveal#op`) and node 229 (**`hR#op` only** — last writer wins; the other 3 hero channels overwritten). A consumer walking nodes loses 3 of 4 hero channels entirely.

**The menu row is unaffected** (single mover, `menu.reveal#op` → node 28) — opacity reveals and any one-mover-per-y element bind cleanly on both paths.

### Required engine follow-ups (NOT done here — scope was capture + assess)
1. **`match_motion` x-blindness (root cause):** binding by y alone collapses co-located/mirror movers onto one node on BOTH paths, and the single-string `anim_ref` then overwrites. Fix: disambiguate binding by **(x,y)+axis**, and key `anim_ref` as a list. This is the prerequisite for the mirror to round-trip at all — neither `motion[]`-by-node_id nor `anim_ref` recovers it until this lands.
2. **`motion_adapter.adapt_web_anim`/`adapt_flipbook` `abs()` drops sign** → mirror direction lost, and both movers serialize as identical `h1#tx` (name collision). The contract expects signed amplitude (spec example `-720`; `bundle_writer` test `-218.5`), so `abs()` is non-conforming. Preserve signed `to−from` and emit unique names. (Hand-worked-around in this bundle as `hL`/`hR` with signed amp; the adapter still has the gap.)
3. **`klass=time` stagger uncaptured:** the contract has no field for the 0–300 ms 52-span stagger or the 1000 ms duration; only the per-span curve/window survive. Acceptable for shape fidelity; note as a known contract limit.

**Bottom line:** the engine produces a faithful, content-independent motion bundle for **single-mover-per-y** elements (the menu reveal round-trips exactly) when anchors come from the skeleton REST frame. For **co-located mirror** elements — kasane's signature diverging-hero, which is on the user's sole-interest axis — `match_motion`'s x-blindness loses the element→motion assignment on **both** the `motion[]`-by-node_id and `anim_ref` paths; the curve/sign data survives in the row names but cannot be mapped back to distinct skeleton nodes. Follow-up #1 (x-aware binding) is the prerequisite to fix this; it was out of scope for this capture+assess pass.
