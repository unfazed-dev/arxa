# Richness-gated G3c — recurring-component synthesis (DESIGN / pre-registration)

**Status:** pre-registration spec (de-risk-first). Approved 2026-06-03.
**Lineage:** G3c DEFERRED ×2 — §C9-R-G3c-calib (coarse geometry vocab) and §C9-R-G3c-revisit
(landmark anchor fails strict cross-site `core≥3 ∧ jac≥0.5` recurrence bar). The revisit explicitly
named the two rescues: a per-site **richness gate** (synthesize only where components actually
recur) OR a re-registered looser bar. This spec takes the **richness-gate** path and re-registers a
*stricter, value-anchored* bar (novelty ∧ coverage), not a looser one.

---

## 0. Shape — de-risk-first, two phases (mirrors G3d)

- **Phase 1 (this deliverable):** a throwaway, content-free **calibration probe** with a
  pre-registered BUILD bar. It answers one question: *does a richness-gated G3c synthesizer produce
  value that `design_system.json` (G3b) does not already carry, on the sites where it fires?*
- **Phase 2 (only if Phase 1 clears):** build the synthesizer — `components.json` emitted at site
  level, content-free, firewall-audited, with the runtime richness gate shipped. Its own gated
  brainstorm→spec→plan→build cycle.

A **DEFER is a legitimate honest outcome.** The bar is committed before any capture and is **not to
be bent after the numbers are seen** (the fix for this session-family's recurrence over-read).

## 1. What the synthesizer would emit (the product being justified)

A site-level `components.json`: a **design-system COMPONENT layer** above G3b's flat token layer.
Each entry = a recurring, landmark-anchored subtree promoted to a named, reusable component
definition: its **composition** (role-tree skeleton + per-node design axes) + occurrence count.

```
{ schema: "probe-runner/components@1",
  components: [
    { key: <structural sig>, occ: 7, routes: [...],
      tree: <role-tree: surface-box[flex-col] > (accent-cta, text)>,
      axes: { root: {layout, sizing, token_ref}, children: [...] } },
    ... ] }
```

**Why this is the only G3c product worth building:** `design_system.json` is **purely flat
value-frequency** — verified by reading `scripts/_merge.py::build_design_system`: it carries
`palette` (role→hex, exact+clustered, route-freq) and `scalars`
(`type_scale/weights/families/spacing/radii/shadows`, flat value-freq). It has **zero composition,
zero containment, zero co-occurrence**. G3c's only marginal add over G3b is therefore COMPOSITION —
*which child roles co-occur under which styled parent, in what layout*. That is the entire value
thesis, and the bar must prove it is **material and non-generic**, not merely present.

## 2. Richness gate (runtime predicate + Phase-1 eval filter)

Gate-in ⇒ "components recur here, synthesize." Gate-out ⇒ "emit empty, honestly."

**GATE PREDICATE** (the existing per-site recurrence metric from `probe_g3c_revisit.py`, fixed
knobs `depth=3, policy="collapse"`): a site gates IN iff the **best of `{role, +layout}`** enrichment
levels clears `core ≥ 3 ∧ jac ≥ 0.5`, where `core` = signatures present in ALL ok routes, `jac` =
mean pairwise Jaccard of per-route signature sets.

Rationale: python.org & w3.org cleared exactly this in the revisit (known-good split); the 6 docs
sites mostly fail it → they are the built-in **negative control**. `+token_ref` (L2) is excluded
from the gate — the revisit proved it collapses recurrence everywhere (any future G3c MUST NOT key
cross-route matching on token_ref).

The gate (cross-route recurrence) and the richness predicate (§3, single-page at-rest) measure
**different things**; a site can be rich at rest yet fail the recurrence gate. That divergence is
itself informative ("rich but doesn't recur") and is handled by the validity rule in §6.

## 3. Cohort — FROZEN at spec time (no post-hoc swaps)

### 3a. Negative controls (6 — retained as-is, expected to gate OUT)
`python.org · iana.org · djangoproject.com · w3.org · gnu.org · apache.org`
(the §C9-R-G3c-revisit cohort; same 4 routes each as that probe).

### 3b. Rich candidates (8 — selected by the §3c predicate, frozen now)
Component-rich habitat (design-system showcases + component-dense marketing), bot-friendly,
multi-route, content-free-capturable:
1. `mui.com`
2. `ant.design`
3. `getbootstrap.com`
4. `carbondesignsystem.com`
5. `primer.style`
6. `chakra-ui.com`
7. `stripe.com`
8. `vercel.com`

4 routes per site (home + 3 section/component routes), chosen at spec time. A frozen site that
FAILS the §3c richness predicate at capture is **reported and excluded from the gated-in pool**
(not silently replaced) — the predicate confirms at-rest richness; it does not license substitution.

### 3c. Content-free richness predicate (site selection / confirmation)
Computed on the home route, at rest, mechanism-keys only: a site is "rich" iff
`≥ 4 distinct landmark roles (web_skeleton.LANDMARK_ROLES) ∧ ≥ 8 repeated styled subtrees`
where a "repeated styled subtree" = a depth≥2 subtree whose structural signature occurs `≥2` times
on the page with a styled root (flex/grid OR token_ref).

## 4. composition-novel component (the value unit)

Sharpened to dodge the revisit's **vacuous distinctiveness=1.00** trap. Because `design_system.json`
is flat, *any* multi-node composition is "not derivable from DS" — so that clause does **zero**
discriminating work and is dropped as a standalone test. The discriminating work is
**non-genericity + cross-route recurrence**:

A subtree counts as composition-novel iff ALL hold:
1. **recurs** cross-route: structural signature present in ≥2 ok routes (core or shared);
2. `depth ≥ 2` AND root styled (flex/grid OR token_ref);
3. `≥ 2 styled children` spanning `≥ 2 DISTINCT child roles`;
4. **not the universal generic wrapper**: excludes bare `box>text`, single-child wrappers, and any
   composition whose entire styled-child role-set ⊆ `{text}`.

(Signature enrichment for matching = `{role, +layout}` — token_ref excluded per §2.)

## 5. coverage (materiality)

Per gated-in route: `coverage = (styled main-content nodes attributable to ANY composition-novel
component) / (total styled main-content nodes)`. **Main-content = nodes minus chrome landmarks**
(`banner/navigation/contentinfo/complementary` — already G3d's turf; excluded so G3c is measured on
its own ground). Reported per site (median over its gated routes); never averaged across sites.

## 6. PRE-REGISTERED BUILD BAR (committed before capture; not bendable)

BUILD the Phase-2 synthesizer **iff ALL** hold:
- **(NEG control — discrimination)** `0 of the 6 docs controls` clear the full POSITIVE value bar
  (`≥5 novel ∧ coverage ≥15%`). Note from the revisit data: the 4 sparse controls
  (django/gnu/iana/apache) gate OUT on recurrence, while python.org & w3.org **legitimately gate
  IN** (`core≥3 ∧ jac≥0.5` cleared there) — so the control is *not* "the gate rejects all docs
  sites." It is the stronger claim that the **whole pipeline (gate + value)** yields **no
  BUILD-qualifying docs site**: even the two that recur produce only generic / low-coverage
  composition. If a docs control *does* clear the value bar, that is a real falsification — the
  metric fails to discriminate habitat — and forces DEFER.
- **(POSITIVE)** `≥ 3` gated-in **rich candidates (§3b)** EACH clear `≥ 5 composition-novel
  components ∧ coverage ≥ 15%`;
- **(VALIDITY)** `≥ 4` rich candidates gate in with data. If `< 4` gate in, the verdict is
  **DEFER-as-finding** ("even pre-selected component-rich sites do not show cross-route component
  recurrence") — there is **no iterative cohort expansion** (the frozen 8 is sized so a short pool
  is itself the result, not a prompt to fish for friendlier sites).

Otherwise **DEFER** (documented, legitimate).

### Number anchoring (defensibility)
- `K = 5` novel components: anchored to the calib's richest site — python.org gave **17 core / 165
  distinct, jac 0.34, 66% of depth-2 sigs page-unique**. `5` ≈ 30% of python's core, but the
  non-genericity clause (§4) demands composed/distinct components, which docs-site cores lacked — so
  the controls correctly fail even if a few gate in. Not transplanted from G3d.
- `coverage ≥ 15%`: **the softest number** (no prior coverage measurement exists). Justification: a
  library explaining <15% of styled main-content is too thin to warrant a separate artifact. Flagged
  as the first knob to revisit; may be re-set by a one-shot pre-data coverage calibration before the
  bar is locked, if desired — but once locked, frozen.
- Gate `core≥3 ∧ jac≥0.5`: the revisit's own per-site threshold (python/w3 cleared it), reused
  unchanged so the gate is not tuned to the new cohort.

## 7. Content-free posture (non-negotiable)

- Probe reads **mechanism keys only** (`role, aria_role, layout, sizing, token_ref`) from
  already-redacted bundles captured through the PRODUCTION `site_capture` path.
- **Every bundle audited** (`content_firewall.audit_bundle`) BEFORE analysis; per-bundle audit cost
  budgeted (this is new probe code, not a `probe_g3c_revisit.py` reuse — novelty-vs-DS + coverage
  over main-minus-chrome are genuinely new).
- Prints ONLY counts / jaccard / role NAMES / netloc / returncodes. Never node content, never
  subprocess stderr.
- Floor-A determinism check (same URL captured twice, compared) required TRUE.
- Phase-2 `components.json` ships through the firewall like every other bundle artifact; the runtime
  richness gate means sparse sites emit an empty `components` list (honest, not faked).

## 8. Testing (Phase-1 probe)

- Pure-core unit tests for: signature/recurrence reuse, the §4 novelty predicate (generic-wrapper
  exclusion, distinct-role count), the §5 coverage accounting (chrome exclusion, no double-count).
- Floor-A determinism leg.
- Fixture: a synthetic skeleton with a known recurring composed card (positive) + a generic
  box>text repeat (must be EXCLUDED by §4) → existence-proof the metric discriminates.
- Live legs run on HOST CDP `:9222` (unreachable from the ctx sandbox); manual harness, env-skip in
  CI (per the `live-cdp-capture-is-manual-harness-not-pytest` pattern).

## 9. Out of scope (YAGNI)

- token_ref-keyed matching (proven recurrence-collapsing — §2).
- Lossless dedup / node-savings framing (that is G3d's axis; G3c here is a design-system artifact,
  measured by novelty+coverage, not bytes).
- Component *naming* semantics (a content-free engine cannot name "card" vs "tile"; keys are
  structural signatures).
- Cohort expansion beyond the frozen 14 (selection-bias guard).
