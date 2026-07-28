# Pseudo-element GEOMETRY follow-on — DE-RISK (pre-registration)

**Rung:** §C9-R-P8 landed `::before`/`::after`/`::marker` content-free STYLE + `content` token but
explicitly deferred their GEOMETRY (gaps:780). Diagnosis: `parse_snapshot` already reads
`bounds[i] → bbox` for EVERY layout row incl. pseudo rows, but `to_skeleton` skips pseudo rows
(web_skeleton.py:565) and `_collect_pseudo` (line 626) harvests only sparse style — it **drops
`r["bbox"]`**. So pseudo geometry is captured-then-discarded, NOT a new pass. The follow-on would
carry a content-free bbox subset into `node_pseudo[nid]["::after"]`.

**Status:** de-risk COMPLETE → **SHIPPED** (§C9-R-P8-GEOM). Bar cleared 3/3; built inline-TDD; full
suite 530 green; real css_style bundle carries pseudo bbox + audits clean. (Build note at bottom.)

---

## Why a fixture won't answer it (proxy-trap, per [[forcepseudostate-on-only-validity-not-capturable]])

A sized-`::after` fixture (`content:""; width:50px; height:20px`) proves only the PLUMBING (bounds
flow through). It cannot tell whether REAL decorative pseudos carry geometry worth shipping. So the
de-risk reads a REAL capture's pseudo rows, not a crafted fixture.

## Gate — mechanism + signal in one real read (pre-registered)

**SHIP iff**, across ≥2 distinct real pages, ≥30% of pseudo rows that already carry captured
style/content ALSO have **non-degenerate bounds** (`w>0 AND h>0`) that are **NOT trivially derivable
from the originator's bbox** — i.e. the pseudo's own box differs in size OR offset from its parent
element's box (a decorative bar / badge / divider with its own dimensions), not merely equal-or-
contained-identical. AND index alignment is confirmed: `bounds[i]` is demonstrably the pseudo's OWN
box (≥1 case where it differs from the parent's), not the parent's row mislabeled.

**DEFER iff** any of:
- pseudo bounds are mostly **0×0** (bare `content:""` with no box) — nothing to ship.
- pseudo bounds mostly **equal the originator's bbox** — geometry is trivially derivable, adds nothing.
- **index misalignment** — `bounds[i]` for a pseudo row is actually the parent's box (the load-bearing
  assumption fails) → cannot trust the value.
- signal on **<2** distinct real pages (no demo+1).

**Firewall:** non-issue — bbox is content-free mechanism, already shipped for every real node. One
audit run confirms; no canary for pure floats.

Honest outcome: if real pseudo bounds are mostly degenerate/parent-derivable → DEFER (web-CDP axis
stays at ceiling). If varied and informative → first SHIP of this "proceed to next" sequence.

---

## Gate RESULT — SHIP (2026-06-03; harness `scripts/derisk_pseudo_geometry.py`, 3 real sites)

| site | pseudo_rows | styled(content) | degenerate(0×0) | parent_equal | **distinct** | distinct&styled / styled |
|---|---|---|---|---|---|---|
| getbootstrap.com (docs) | 80 | 28 | 4 | 2 | 74 | **79%** |
| en.wikipedia.org (CSS article) | 492 | 310 | 136 | 0 | 356 | **56%** |
| tailwindcss.com | 354 | 354 | 92 | 12 | 250 | **71%** |

**Bar = ≥30% on ≥2 sites → cleared on 3/3.** Examples of real, non-derivable geometry:
- `HEADER::after` 912×**1** (a 1px divider bar — own height; parent is 39.6 tall) — wikipedia.
- `::before` **2880**×1 full-bleed line on a **1360**-wide parent (overflows it — cannot be derived) — tailwind.
- `BUTTON::after` 8×4 dropdown caret at an offset distinct from the 63×40 button — bootstrap.
- `INPUT/LABEL::after` 12×12 icon checkmarks at specific positions — wikipedia.

**Index alignment CONFIRMED:** `distinct > 0` on all 3, and samples show the pseudo box differs from the
parent box in size AND/OR offset (912×1 vs 912×39.6; 2880 vs 1360) — so `bounds[i]` is the pseudo's OWN
rendered box, not the originator's row. The load-bearing assumption holds.

**Conservative note (honest):** the `styled` denominator counted only non-empty `content`; the highest-
value cases are `content:""` decorative boxes (dividers/bars/gradients) styled via bg/border — those
are EXTRA pseudos the rung attaches (via the bg/border branch of `_collect_pseudo`), not counted in
`styled`. So the real distinct-geometry yield is ≥ the % shown. ~26–28% are degenerate 0×0 (bare
`content:""` with no box) — the build gates geometry on `w>0 AND h>0`, attaching nothing for those.

**Firewall:** non-issue — pseudo bbox is content-free mechanism floats, identical in kind to the bbox
already shipped for every real node. One `audit_bundle` run on a rebuilt bundle confirms.

**→ BUILD** (inline TDD; small, scoped): stop dropping `r["bbox"]` in the pseudo-harvest path; attach a
content-free pseudo bbox (`w>0 AND h>0` gate) into `node_pseudo[nid]["::…"]`. Shape + consumers
(`apply_node_pseudo`, firewall) verified during the build.

## Build RESULT — SHIPPED (2026-06-03, inline TDD)

**Changes (2 lines of logic + passthrough):**
- `web_skeleton.py` (pseudo-harvest, ~line 627): when the kept sparse style `sv` is non-empty AND the
  pseudo's `r["bbox"]` has `w>0 AND h>0`, attach `sv = {**sv, "bbox": bb}`. Geometry rides along on an
  already-kept pseudo; a 0×0 box attaches nothing.
- `_style.redact_pseudo`: the `bbox` key (a geometry DICT) is passed through verbatim — `content` →
  `redact_content_value`, every other STRING prop → `redact_style_value`. (Without this, the dict hit
  `redact_style_value` and raised `'dict' has no attribute 'lower'` — the TDD-red proof.)

**Tests (4 new, all green; full `scripts/` suite 530 passed, +4, zero regressions):**
- `test_to_skeleton_attaches_pseudo_bbox_when_nondegenerate` / `..._omits_..._when_degenerate`
- `test_redact_pseudo_passes_bbox_through_untouched`
- `test_audit_clean_on_pseudo_bbox_geometry`

**Real-artifact confirm (validate-real-artifact, not synthetic-only):** re-ran
`fixtures/css_style/run_css_style.py` (deterministic local capture→bundle→firewall). GATE PASS; the
on-disk `_bundle/skeleton.json` now carries pseudo bbox — `::before` 79.06×74, `::after` 1×1, `::marker`
16×18.5 — and an independent `audit_bundle` on the bundle dir returns `[]` (clean). Firewall confirmed a
non-issue as predicted (bbox floats serialize as JSON numbers, never scanned as strings). Deeper reason
(pre-answers "doesn't a text-pseudo's width leak content?"): a text-bearing pseudo's width/height is the
SAME lossy text-geometry the bundle already ships for every real text node — and real text nodes carry
`bbox` PLUS `text_len`, whereas a pseudo ships `bbox` ONLY. Strictly *less* revealing than the
already-accepted real-text tolerance, not a new vector.

**Engine insight (non-obvious):** the geometry was captured-then-DISCARDED — `parse_snapshot` already
reads `bounds[i]` for pseudo rows; only the harvest path dropped it. Not a new capture pass.
