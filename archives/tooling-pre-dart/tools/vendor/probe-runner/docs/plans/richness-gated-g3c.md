# Richness-gated G3c — Phase-1 de-risk probe — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the content-free Phase-1 calibration probe that runs the pre-registered richness-gated G3c bar (`docs/plans/richness-gated-g3c-design.md`) and emits BUILD / DEFER.

**Architecture:** A self-contained probe in `research/capture-gap-probes/` (mirrors `probe_g3c_revisit.py`): pure metric functions (richness predicate, recurrence gate, composition-novelty, coverage, verdict) that take plain node-lists and are unit-tested with hand-built skeletons; plus a HOST-CDP orchestration layer (capture via the production `site_capture` path, firewall-audit every bundle, Floor-A determinism). It reuses `calib_component_signature` (`C`) for `_children / signature / _is_styled / recurrence / _jaccard / _cdp_reachable / _audit_clean` and `web_skeleton.LANDMARK_ROLES`.

**Tech Stack:** Python 3.13, pytest 9.0.2, Chrome DevTools Protocol (`:9222`), existing `scripts/site_capture.py` + `scripts/content_firewall.py` + `scripts/web_skeleton.py`.

**Test command (all tasks):** `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`

---

## File Structure

- **Create** `research/capture-gap-probes/probe_g3c_richness_gated.py` — pure metric core + HOST-CDP orchestration + `main()`.
- **Create** `research/capture-gap-probes/test_g3c_richness_gated.py` — pytest unit tests over hand-built node-lists (no browser).
- **Modify** `research/capture-gap-probes/README.md` — add the probe to the manifest + the live-run instructions.

All pure functions take `landmark_roles` as an injected parameter (clean testability); the probe supplies `web_skeleton.LANDMARK_ROLES` at the call site. Chrome-landmark set is a module constant `CHROME_LANDMARKS = {"banner","navigation","contentinfo","complementary"}`.

---

### Task 1: Scaffold the probe module (constants + pre-registered bar + reuse imports)

**Files:**
- Create: `research/capture-gap-probes/probe_g3c_richness_gated.py`

- [ ] **Step 1: Write the module skeleton** (no tests yet — this is the shared header all later tasks import)

```python
#!/usr/bin/env python3
"""G3c RICHNESS-GATED de-risk probe (Phase-1, throwaway). Pre-registration:
`docs/plans/richness-gated-g3c-design.md`. NOT in the shipped unit suite.

QUESTION: does a richness-gated G3c synthesizer produce value design_system.json (G3b,
verified flat value-freq) does NOT already carry, on the sites where it fires?

============================  PRE-REGISTERED BAR (not bendable after numbers seen)  ===
Fixed knobs: depth=3, collapse policy, signature levels {0:role, 1:+layout} (token_ref
EXCLUDED -- proven recurrence-collapsing in §C9-R-G3c-revisit).
GATE (per site, runtime + eval filter): gated-in iff best of {role,+layout} clears
    core >= 3 AND jac >= 0.5  (landmark-aria-anchored roots).
RICHNESS predicate (home route, at rest): rich iff
    >= 4 distinct landmark roles AND >= 8 repeated styled subtrees (occ>=2, depth>=2, styled root).
composition-NOVEL component: recurring (>=2 routes) landmark-anchored subtree with depth>=2,
    styled root, >=2 styled children spanning >=2 DISTINCT roles, NOT a generic wrapper
    (excludes bare box>text / single-child / styled-child-roles subset of {text}).
COVERAGE: styled main-content nodes (minus chrome-landmark subtrees) attributable to a
    novel component / total styled main-content nodes, per gated route.
VERDICT: BUILD iff (0 of 6 docs controls clear novel>=5 AND cov>=0.15)  AND
    (>=3 rich candidates clear novel>=5 AND cov>=0.15)  AND (>=4 rich gate in).
    <4 rich gate in => DEFER-as-finding. Else DEFER. No cohort expansion.
=======================================================================================

Content-free: reads mechanism keys only from already-redacted bundles; audits every bundle
BEFORE analysis; prints counts / jaccard / role NAMES / netloc / returncodes only -- never
node content, never subprocess stderr. HOST Bash (CDP :9222; unreachable from ctx sandbox).
"""
import argparse
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import calib_component_signature as C       # _children, signature, _is_styled, recurrence, _jaccard, capture helpers
import content_firewall as cf               # audit_bundle
from web_skeleton import LANDMARK_ROLES     # production landmark allowlist

DEPTH = 3
POLICY = "collapse"
CHROME_LANDMARKS = {"banner", "navigation", "contentinfo", "complementary"}

# Pre-registered thresholds (frozen).
GATE_CORE, GATE_JAC = 3, 0.5
RICH_LANDMARKS, RICH_SUBTREES = 4, 8
K_NOVEL, COVERAGE_MIN = 5, 0.15
MIN_RICH_GATED, MIN_RICH_CLEAR = 4, 3

_SZ = {"fill": "L", "fixed": "X", "hug": "H"}  # NOT [0]: fill/fixed both start "f"

# FROZEN cohort (spec §3). 4 routes each.
CONTROLS = {
    "python.org": ["https://www.python.org/", "https://www.python.org/about/",
                   "https://www.python.org/downloads/", "https://www.python.org/community/"],
    "iana.org": ["https://www.iana.org/", "https://www.iana.org/domains",
                 "https://www.iana.org/numbers", "https://www.iana.org/about"],
    "djangoproject.com": ["https://www.djangoproject.com/", "https://www.djangoproject.com/start/",
                          "https://www.djangoproject.com/download/", "https://www.djangoproject.com/community/"],
    "w3.org": ["https://www.w3.org/", "https://www.w3.org/standards/",
               "https://www.w3.org/participate/", "https://www.w3.org/about/"],
    "gnu.org": ["https://www.gnu.org/", "https://www.gnu.org/philosophy/philosophy.html",
                "https://www.gnu.org/software/software.html", "https://www.gnu.org/help/help.html"],
    "apache.org": ["https://www.apache.org/", "https://www.apache.org/foundation/",
                   "https://www.apache.org/licenses/", "https://www.apache.org/events/current-event.html"],
}
RICH = {
    "mui.com": ["https://mui.com/", "https://mui.com/material-ui/", "https://mui.com/material-ui/all-components/", "https://mui.com/core/"],
    "ant.design": ["https://ant.design/", "https://ant.design/components/overview/", "https://ant.design/components/button/", "https://ant.design/components/card/"],
    "getbootstrap.com": ["https://getbootstrap.com/", "https://getbootstrap.com/docs/5.3/components/buttons/", "https://getbootstrap.com/docs/5.3/components/card/", "https://getbootstrap.com/docs/5.3/components/navbar/"],
    "carbondesignsystem.com": ["https://carbondesignsystem.com/", "https://carbondesignsystem.com/components/overview/", "https://carbondesignsystem.com/components/button/usage/", "https://carbondesignsystem.com/components/tile/usage/"],
    "primer.style": ["https://primer.style/", "https://primer.style/components", "https://primer.style/foundations", "https://primer.style/guides"],
    "chakra-ui.com": ["https://chakra-ui.com/", "https://chakra-ui.com/docs/components/concepts/overview", "https://chakra-ui.com/docs/components/button", "https://chakra-ui.com/docs/components/card"],
    "stripe.com": ["https://stripe.com/", "https://stripe.com/payments", "https://stripe.com/billing", "https://stripe.com/connect"],
    "vercel.com": ["https://vercel.com/", "https://vercel.com/products/previews", "https://vercel.com/products/observability", "https://vercel.com/solutions/nextjs"],
}
```

- [ ] **Step 2: Verify the module imports cleanly**

Run: `python3 -c "import sys; sys.path.insert(0,'research/capture-gap-probes'); import probe_g3c_richness_gated as P; print(sorted(P.LANDMARK_ROLES)); print(len(P.CONTROLS), len(P.RICH))"`
Expected: prints the 13 landmark roles then `6 8`.

- [ ] **Step 3: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py
git commit -m "feat: scaffold richness-gated G3c probe (frozen cohort + pre-registered bar)"
```

---

### Task 2: Test fixture helper + node token

**Files:**
- Create: `research/capture-gap-probes/test_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import probe_g3c_richness_gated as P

LM = {"navigation", "main", "banner", "contentinfo", "complementary", "region", "form"}


def node(nid, role, parent, aria=None, styled=False):
    """Minimal skeleton node. styled -> flex layout + a bg token_ref (passes C._is_styled)."""
    return {
        "id": nid, "role": role, "parent": parent, "aria_role": aria,
        "layout": {"mode": "flex" if styled else "block", "direction": "row",
                   "gap": 0.0, "pad": [0, 0, 0, 0], "justify": "normal", "align": "normal",
                   "grid_cols": None, "grid_rows": None},
        "sizing": {"w": "fixed", "h": "fixed", "confidence": "high"},
        "token_ref": {"bg": "surface" if styled else None, "fg": None, "border": None},
    }


def test_node_token_level0_is_role_only_level1_adds_layout_and_aria_anchor():
    plain = node(1, "box", 0, styled=True)
    assert P._node_token(plain, 0) == "box"
    assert "flex" in P._node_token(plain, 1)
    landmark = node(2, "box", 0, aria="navigation", styled=True)
    assert P._node_token(landmark, 1).startswith("navigation@")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py::test_node_token_level0_is_role_only_level1_adds_layout_and_aria_anchor -v`
Expected: FAIL — `AttributeError: module ... has no attribute '_node_token'`.

- [ ] **Step 3: Add `_node_token` + `_token_of` to the probe**

```python
def _node_token(n, level):
    """level 0 = role; level 1 = role + layout-mode + sizing. token_ref EXCLUDED.
    Landmark aria_role prefixes as a semantic anchor (mirrors probe_g3c_revisit)."""
    role = n.get("role") or "?"
    base = role
    if level >= 1:
        parts = [role]
        lay = n.get("layout") or {}
        mode = lay.get("mode")
        if mode and mode != "block":
            parts.append(mode + ("-" + (lay.get("direction") or "")[:3] if mode == "flex" else ""))
        sz = n.get("sizing") or {}
        if sz.get("w") or sz.get("h"):
            parts.append(_SZ.get(sz.get("w"), "?") + _SZ.get(sz.get("h"), "?"))
        base = "·".join(parts)
    ar = n.get("aria_role")
    return (ar + "@" + base) if ar else base


def _token_of(nodes, level):
    return {n["id"]: _node_token(n, level) for n in nodes}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/test_g3c_richness_gated.py research/capture-gap-probes/probe_g3c_richness_gated.py
git commit -m "feat: G3c probe node-token (role / +layout, token_ref excluded)"
```

---

### Task 3: Landmark-anchored route signatures

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
def test_route_sigs_anchor_on_landmark_aria_roots_only():
    # nav landmark (id1) with 2 styled children; a non-landmark styled box (id4) is NOT a root.
    nodes = [
        node(0, "unknown_box", None),
        node(1, "box", 0, aria="navigation", styled=True),
        node(2, "link", 1, styled=True), node(3, "link", 1, styled=True),
        node(4, "box", 0, styled=True),  # styled but no aria -> not a landmark root
    ]
    sigs, by_parent = P._route_sigs_with_meta(nodes, 1, LM)
    assert len(sigs) == 1                       # only the navigation root
    only = next(iter(sigs))
    assert only.startswith("navigation@")
    assert P._route_sig_set(nodes, 1, LM) == set(sigs)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py::test_route_sigs_anchor_on_landmark_aria_roots_only -v`
Expected: FAIL — no `_route_sigs_with_meta`.

- [ ] **Step 3: Add the anchoring helpers**

```python
def _landmark_roots(nodes, by_parent, landmark_roles):
    return [n for n in nodes if n.get("aria_role") in landmark_roles and by_parent.get(n["id"])]


def _route_sigs_with_meta(nodes, level, landmark_roles, depth=DEPTH):
    """sig -> first exemplar node, plus the by_parent map. Collapse policy, landmark roots."""
    by_parent = C._children(nodes)
    tok = _token_of(nodes, level)
    sigs = {}
    for n in _landmark_roots(nodes, by_parent, landmark_roles):
        s = C.signature(n, by_parent, tok, depth, POLICY)
        sigs.setdefault(s, n)
    return sigs, by_parent


def _route_sig_set(nodes, level, landmark_roles, depth=DEPTH):
    return set(_route_sigs_with_meta(nodes, level, landmark_roles, depth)[0])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c landmark-anchored route signatures (+ exemplar map)"
```

---

### Task 4: The recurrence gate

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
def _rich_routes():
    """4 identical routes with 3 recurring landmark structures -> core=3, jac=1.0."""
    def one():
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="navigation", styled=True),
                node(2, "link", 1, styled=True), node(3, "button", 1, styled=True),
                node(4, "box", 0, aria="region", styled=True),
                node(5, "button", 4, styled=True), node(6, "text", 4, styled=True),
                node(7, "box", 0, aria="form", styled=True),
                node(8, "textbox", 7, styled=True), node(9, "button", 7, styled=True)]
    return [one() for _ in range(4)]


def _divergent_routes():
    """One shared region card (recurs) + a navigation whose child ROLE differs per route
    (vary role, NOT count -- collapse policy collapses count). core=1 (region only), jac~0.33."""
    uniq = ["button", "text", "link", "image"]
    def one(r):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "button", 1, styled=True), node(3, "text", 1, styled=True),
                node(4, "box", 0, aria="navigation", styled=True),
                node(5, uniq[r], 4, styled=True), node(6, "image", 4, styled=True)]
    return [one(r) for r in range(4)]


def test_gate_passes_when_landmark_structures_recur_across_routes():
    gated, best = P.gate(_rich_routes(), LM)
    assert gated is True
    assert best["core"] >= P.GATE_CORE and best["jac"] >= P.GATE_JAC


def test_gate_fails_when_landmark_compositions_diverge_across_routes():
    gated, best = P.gate(_divergent_routes(), LM)
    assert gated is False
    assert (best["core"] < P.GATE_CORE) or (best["jac"] < P.GATE_JAC)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -k gate -v`
Expected: FAIL — no `gate`.

- [ ] **Step 3: Add `gate`**

```python
def gate(route_node_lists, landmark_roles, depth=DEPTH):
    """Best of {role(0), +layout(1)} clears core>=GATE_CORE AND jac>=GATE_JAC. Returns
    (gated_in: bool, best: {level, core, jac}). best = the strongest level seen (for reporting),
    preferring a passing level."""
    best = {"level": None, "core": 0, "jac": 0.0, "pass": False}
    for level in (0, 1):
        per = [_route_sig_set(nl, level, landmark_roles, depth) for nl in route_node_lists]
        rec = C.recurrence(per)
        core, jac = len(rec["core"]), rec["jac"]
        passes = core >= GATE_CORE and jac >= GATE_JAC
        better = (passes, core, jac) > (best["pass"], best["core"], best["jac"])
        if better:
            best = {"level": level, "core": core, "jac": jac, "pass": passes}
    return best["pass"], best
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c recurrence gate (best of role/+layout, core>=3 AND jac>=0.5)"
```

---

### Task 5: composition-novelty (the discrimination existence-proof)

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test** (positive composed card recurs; generic box>text repeat + single-child wrapper EXCLUDED)

```python
def _card_route():
    """A recurring 'card': region landmark > styled box with a styled accent button + styled
    text (>=2 styled children, 2 distinct roles, not subset of {text}). PLUS a generic
    box>text repeat and a single-child wrapper that MUST be excluded."""
    nodes = [node(0, "unknown_box", None)]
    # the card (novel): region root -> box -> (button, text)
    nodes += [node(1, "box", 0, aria="region", styled=True),
              node(2, "box", 1, styled=True),
              node(3, "button", 2, styled=True), node(4, "text", 2, styled=True)]
    # generic wrapper (must be EXCLUDED): main -> box -> text only
    nodes += [node(5, "box", 0, aria="main", styled=True),
              node(6, "box", 5, styled=True), node(7, "text", 6, styled=True)]
    # single-child styled wrapper (EXCLUDED: <2 styled children): form -> box -> box
    nodes += [node(8, "box", 0, aria="form", styled=True),
              node(9, "box", 8, styled=True)]
    return nodes


def test_composition_novel_includes_real_card_excludes_generic_and_single_child():
    routes = [_card_route() for _ in range(4)]   # all three structures recur on all routes
    novel = P.composition_novel_components(routes, 1, LM)
    # exactly one novel component: the region card. main(box>text) and form(box) excluded.
    assert len(novel) == 1
    assert novel[0].startswith("region@")


def test_composition_novel_requires_two_distinct_child_roles():
    # region > box > (button, button): 2 styled children but only ONE role -> excluded.
    def two_same(_):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "box", 1, styled=True),
                node(3, "button", 2, styled=True), node(4, "button", 2, styled=True)]
    assert P.composition_novel_components([two_same(i) for i in range(4)], 1, LM) == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -k composition -v`
Expected: FAIL — no `composition_novel_components`.

- [ ] **Step 3: Add the novelty predicate + aggregator**

```python
def _has_composition(node_, by_parent):
    """∃ a node ANYWHERE in this subtree with >=2 styled children spanning >=2 DISTINCT roles
    whose styled-child role-set is not a subset of {text} -- a real, non-generic branch. (A
    landmark commonly wraps a single container that holds the children, so the branch need not
    be at the root.)"""
    stack = [node_]
    while stack:
        cur = stack.pop()
        kids = by_parent.get(cur["id"], [])
        styled = [k for k in kids if C._is_styled(k)]
        roles = {(k.get("role") or "?") for k in styled}
        if len(styled) >= 2 and len(roles) >= 2 and not (roles <= {"text"}):
            return True
        stack.extend(kids)
    return False


def _is_novel_composition(node_, by_parent):
    """§4 clauses 2-4 on an exemplar (clause 1 = recurrence, handled by the caller): root
    styled, depth>=2 (>=1 child), AND the subtree contains a real non-generic composition
    branch. Excludes bare box>text chains, single-child wrappers, and text-only branches."""
    if not by_parent.get(node_["id"]):
        return False                          # depth>=2 needs >=1 child level
    if not C._is_styled(node_):
        return False                          # styled root
    return _has_composition(node_, by_parent)


def composition_novel_components(route_node_lists, level, landmark_roles, depth=DEPTH):
    """Signatures that (1) recur in >=2 routes AND (2-4) whose exemplar is a non-generic
    composed subtree. Returns the list of novel signature strings."""
    per_sets, exemplar = [], {}
    for nl in route_node_lists:
        sigs, bp = _route_sigs_with_meta(nl, level, landmark_roles, depth)
        per_sets.append(set(sigs))
        for s, n in sigs.items():
            exemplar.setdefault(s, (n, bp))
    rec = C.recurrence(per_sets)
    recurring = set(rec["core"]) | set(rec["shared_ge2_not_core"])
    return [s for s in recurring if _is_novel_composition(*exemplar[s])]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c composition-novelty (recurrence + non-generic composed subtree)"
```

---

### Task 6: coverage (main-content minus chrome)

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
def test_coverage_excludes_chrome_and_counts_styled_main_under_novel_only():
    nodes = _card_route()                      # region card (novel) + generic main + form
    routes = [_card_route() for _ in range(4)]
    novel = P.composition_novel_components(routes, 1, LM)   # the region card sig
    cov = P.coverage(nodes, novel, 1, LM)
    # styled main-content (not under banner/nav/contentinfo/complementary):
    #   region card subtree {1,2,3,4}=4, generic-main subtree {5,6,7}=3, form subtree {8,9}=2,
    #   root id0 is unknown_box NOT styled. Total styled main = 4+3+2 = 9.
    # covered = region card subtree styled nodes {1,2,3,4} = 4. 4/9 = 0.444.
    assert cov == 0.444


def test_coverage_zero_when_no_novel_components():
    nodes = _card_route()
    assert P.coverage(nodes, [], 1, LM) == 0.0
```

Note: `complementary` is in `CHROME_LANDMARKS`; this fixture uses `region`/`main`/`form` (all main-content), so nothing is chrome-excluded here — the exclusion path is covered by the next assertion.

```python
def test_coverage_drops_chrome_landmark_subtrees():
    # a navigation (chrome) card identical to a region (main) card; only the region one counts.
    def mixed(_):
        return [node(0, "unknown_box", None),
                node(1, "box", 0, aria="region", styled=True),
                node(2, "button", 1, styled=True), node(3, "text", 1, styled=True),
                node(4, "box", 0, aria="navigation", styled=True),
                node(5, "button", 4, styled=True), node(6, "text", 4, styled=True)]
    routes = [mixed(i) for i in range(4)]
    novel = P.composition_novel_components(routes, 1, LM)
    # both region@ and navigation@ are novel; coverage counts only the region (main) subtree.
    cov = P.coverage(mixed(0), novel, 1, LM)
    # styled main = region subtree {1,2,3}=3 (nav subtree {4,5,6} is chrome-excluded). covered=3. 3/3=1.0
    assert cov == 1.0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -k coverage -v`
Expected: FAIL — no `coverage`.

- [ ] **Step 3: Add coverage + subtree helpers**

```python
def _subtree_ids(node_, by_parent):
    out, stack = [], [node_]
    while stack:
        cur = stack.pop()
        out.append(cur["id"])
        stack.extend(by_parent.get(cur["id"], []))
    return out


def _chrome_ids(nodes, by_parent, landmark_roles):
    ids = set()
    for n in nodes:
        if n.get("aria_role") in CHROME_LANDMARKS:
            ids.update(_subtree_ids(n, by_parent))
    return ids


def coverage(nodes, novel_sigs, level, landmark_roles, depth=DEPTH):
    """styled main-content nodes (minus chrome subtrees) attributable to a novel component
    / total styled main-content nodes. Rounded to 3 dp."""
    by_parent = C._children(nodes)
    tok = _token_of(nodes, level)
    chrome = _chrome_ids(nodes, by_parent, landmark_roles)
    styled_main = {n["id"] for n in nodes if C._is_styled(n) and n["id"] not in chrome}
    if not styled_main:
        return 0.0
    novel = set(novel_sigs)
    covered = set()
    for n in _landmark_roots(nodes, by_parent, landmark_roles):
        if C.signature(n, by_parent, tok, depth, POLICY) in novel:
            covered.update(i for i in _subtree_ids(n, by_parent) if i in styled_main)
    return round(len(covered) / len(styled_main), 3)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c coverage (styled main-content minus chrome, attributable to novel)"
```

---

### Task 7: richness predicate (cohort selection / confirmation)

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
def test_richness_predicate_rich_when_enough_landmarks_and_repeated_subtrees():
    nodes = [node(0, "unknown_box", None)]
    # 4 distinct landmark roles
    for j, ar in enumerate(("navigation", "main", "complementary", "form")):
        nodes.append(node(100 + j, "box", 0, aria=ar, styled=True))
        nodes.append(node(200 + j, "text", 100 + j, styled=True))
    # 8 DISTINCT repeated styled subtree shapes, each appearing twice (occ=2). n_repeated counts
    # DISTINCT sigs with occ>=2 -> need 8 different shapes, not one shape x8.
    nid = 300
    for r2 in ("button", "text", "link", "image", "heading", "textbox", "menuitem", "tab"):
        for _ in range(2):
            nodes += [node(nid, "box", 0, styled=True),
                      node(nid + 1, r2, nid, styled=True), node(nid + 2, "text", nid, styled=True)]
            nid += 3
    is_rich, n_lm, n_rep = P.richness_predicate(nodes, LM)
    assert n_lm >= P.RICH_LANDMARKS and n_rep >= P.RICH_SUBTREES and is_rich is True


def test_richness_predicate_sparse_when_few_landmarks():
    nodes = [node(0, "unknown_box", None), node(1, "box", 0, aria="navigation", styled=True),
             node(2, "text", 1, styled=True)]
    is_rich, n_lm, n_rep = P.richness_predicate(nodes, LM)
    assert is_rich is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -k richness -v`
Expected: FAIL — no `richness_predicate`.

- [ ] **Step 3: Add `richness_predicate`**

```python
def richness_predicate(home_nodes, landmark_roles, depth=DEPTH):
    """§3c: rich iff >=RICH_LANDMARKS distinct landmark roles AND >=RICH_SUBTREES repeated
    (occ>=2) styled subtrees on the home route. Returns (is_rich, n_landmarks, n_repeated)."""
    by_parent = C._children(home_nodes)
    n_landmarks = len({n.get("aria_role") for n in home_nodes
                       if n.get("aria_role") in landmark_roles})
    tok = _token_of(home_nodes, 1)
    styled_roots = [n for n in home_nodes if C._is_styled(n) and by_parent.get(n["id"])]
    cnt = Counter(C.signature(n, by_parent, tok, depth, POLICY) for n in styled_roots)
    n_repeated = sum(1 for c in cnt.values() if c >= 2)
    return (n_landmarks >= RICH_LANDMARKS and n_repeated >= RICH_SUBTREES), n_landmarks, n_repeated
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (12 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c content-free richness predicate (>=4 landmarks AND >=8 repeated subtrees)"
```

---

### Task 8: verdict aggregation (the pre-registered bar)

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`
- Modify: `research/capture-gap-probes/test_g3c_richness_gated.py`

- [ ] **Step 1: Write the failing test**

```python
def _res(netloc, gated, novel, cov):
    return {"netloc": netloc, "gated_in": gated, "novel": novel, "coverage": cov}


def test_verdict_build_when_controls_clean_and_three_rich_clear():
    controls = [_res("python.org", True, 2, 0.05), _res("w3.org", True, 1, 0.10)] + \
               [_res(n, False, 0, 0.0) for n in ("iana.org", "django", "gnu", "apache")]
    rich = [_res("mui.com", True, 7, 0.30), _res("ant.design", True, 6, 0.22),
            _res("getbootstrap.com", True, 5, 0.18), _res("primer.style", True, 3, 0.10)]
    v, _why = P.verdict(controls, rich)
    assert v == "BUILD"


def test_verdict_defer_when_a_control_clears_the_value_bar():
    controls = [_res("python.org", True, 6, 0.20)] + [_res(n, False, 0, 0.0) for n in "bcdef"]
    rich = [_res("mui.com", True, 7, 0.30), _res("ant.design", True, 6, 0.22),
            _res("getbootstrap.com", True, 5, 0.18), _res("primer.style", True, 5, 0.16)]
    v, _ = P.verdict(controls, rich)
    assert v == "DEFER"


def test_verdict_defer_as_finding_when_fewer_than_four_rich_gate_in():
    controls = [_res(n, False, 0, 0.0) for n in "abcdef"]
    rich = [_res("mui.com", True, 9, 0.40), _res("ant.design", True, 8, 0.35),
            _res("getbootstrap.com", True, 7, 0.30)] + [_res("x", False, 0, 0.0)]
    v, why = P.verdict(controls, rich)
    assert v == "DEFER" and "rich" in why.lower()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -k verdict -v`
Expected: FAIL — no `verdict`.

- [ ] **Step 3: Add `verdict`**

```python
def _clears(r):
    return r["gated_in"] and r["novel"] >= K_NOVEL and r["coverage"] >= COVERAGE_MIN


def verdict(control_results, rich_results):
    """Apply the pre-registered §6 bar. Returns (decision, why)."""
    controls_clearing = [r for r in control_results if _clears(r)]
    rich_gated = [r for r in rich_results if r["gated_in"]]
    rich_clearing = [r for r in rich_results if _clears(r)]
    if len(rich_gated) < MIN_RICH_GATED:
        return "DEFER", ("DEFER-as-finding: only %d/%d rich candidates gated in "
                         "(rich-but-not-recurrent)" % (len(rich_gated), MIN_RICH_GATED))
    if controls_clearing:
        return "DEFER", ("neg-control falsified: %d docs control(s) cleared the value bar "
                         "(metric does not discriminate habitat)" % len(controls_clearing))
    if len(rich_clearing) >= MIN_RICH_CLEAR:
        return "BUILD", "%d rich candidates clear (>=%d novel AND >=%.0f%% coverage); 0 controls clear" \
            % (len(rich_clearing), K_NOVEL, COVERAGE_MIN * 100)
    return "DEFER", "only %d/%d rich candidates clear the value bar" % (len(rich_clearing), MIN_RICH_CLEAR)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
Expected: PASS (15 tests).

- [ ] **Step 5: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py research/capture-gap-probes/test_g3c_richness_gated.py
git commit -m "feat: G3c verdict aggregation (pre-registered BUILD/DEFER bar)"
```

---

### Task 9: HOST-CDP orchestration + Floor-A + `main()`

**Files:**
- Modify: `research/capture-gap-probes/probe_g3c_richness_gated.py`

This task has no unit test — it drives a real browser (HOST CDP `:9222`), validated by the live run in Task 11. It reuses `C._cdp_reachable`, `C._capture_to_tmp`, `C._load_skeletons`.

- [ ] **Step 1: Add capture + per-site eval + Floor-A**

```python
import shutil
import tempfile
import subprocess


def _capture_routes(urls, port):
    """site_capture a route list through the PRODUCTION path. Returns (node_lists, clean, rc).
    returncode ONLY on failure (never stderr); audits the bundle before returning."""
    out = Path(tempfile.mkdtemp(prefix="g3c_rg_"))
    try:
        rc = subprocess.run(
            [sys.executable, str(SCRIPTS / "site_capture.py"),
             "--urls", ",".join(urls), "--out", str(out), "--cdp-port", str(port)],
            cwd=str(SCRIPTS), capture_output=True, text=True).returncode
        if rc != 0:
            return [], False, rc
        clean = not cf.audit_bundle(out)
        lists = []
        try:
            site = json.loads((out / "site.json").read_text())
            for row in site.get("routes", []):
                if row.get("ok"):
                    sk = out / "routes" / row["route_id"] / "skeleton.json"
                    lists.append(json.loads(sk.read_text()).get("nodes") or [])
        except (OSError, ValueError, KeyError):
            pass
        return lists, clean, rc
    finally:
        shutil.rmtree(out, ignore_errors=True)


def _eval_site(netloc, urls, port, want_rich):
    """Capture, audit, gate, then (if gated-in) novelty+coverage on the BEST passing level.
    Returns a result dict or None (audit-fail / insufficient routes)."""
    lists, clean, rc = _capture_routes(urls, port)
    if not clean:
        print("  %-22s AUDIT NOT CLEAN -- excluded (firewall)" % netloc)
        return None
    if len(lists) < 2:
        print("  %-22s ok_routes=%d rc=%d -- insufficient (<2)" % (netloc, len(lists), rc))
        return None
    rich, n_lm, n_rep = richness_predicate(lists[0], LANDMARK_ROLES)
    gated, best = gate(lists, LANDMARK_ROLES)
    level = best["level"] if gated else 1
    novel = composition_novel_components(lists, level, LANDMARK_ROLES) if gated else []
    cov = round(sum(coverage(nl, novel, level, LANDMARK_ROLES) for nl in lists) / len(lists), 3) \
        if gated else 0.0
    res = {"netloc": netloc, "rich": rich, "n_landmarks": n_lm, "n_repeated": n_rep,
           "gated_in": gated, "level": best["level"], "core": best["core"], "jac": best["jac"],
           "novel": len(novel), "coverage": cov}
    print("  %-22s rich=%s(lm=%d,rep=%d) gated=%s(L%s core=%d jac=%.2f) novel=%d cov=%.3f"
          % (netloc, rich, n_lm, n_rep, gated, best["level"], best["core"], best["jac"],
             len(novel), cov))
    if want_rich and not rich:
        print("       NOTE: frozen rich candidate FAILED richness predicate -- excluded from rich pool")
    return res


def _floor_a(url, port):
    """Determinism: capture one url twice -> identical level-1 landmark sig set?"""
    a, ca, _ = _capture_routes([url], port)
    b, cb, _ = _capture_routes([url], port)
    if not a or not b or not ca or not cb:
        print("FLOOR_A: capture/audit failed")
        return
    sa = _route_sig_set(a[0], 1, LANDMARK_ROLES)
    sb = _route_sig_set(b[0], 1, LANDMARK_ROLES)
    print("FLOOR_A determinism (same URL, 2 captures): identical=%s |A|=%d |B|=%d"
          % (sa == sb, len(sa), len(sb)))
```

- [ ] **Step 2: Add `main()`**

```python
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--floor-a", help="capture this URL twice; assert identical sig set")
    ap.add_argument("--sites", type=int, default=0, help="cap candidates per cohort (0=all)")
    args = ap.parse_args()

    if not C._cdp_reachable(args.cdp_port):
        print("CDP_REACHABLE: False (Chrome :%d down)" % args.cdp_port)
        return 2
    print("CDP_REACHABLE: True")
    if args.floor_a:
        _floor_a(args.floor_a, args.cdp_port)
        return 0

    print("== G3c RICHNESS-GATED :: depth=%d policy=%s gate(core>=%d,jac>=%.1f) "
          "value(novel>=%d,cov>=%.2f) ==" % (DEPTH, POLICY, GATE_CORE, GATE_JAC, K_NOVEL, COVERAGE_MIN))
    ctrl_items = list(CONTROLS.items())[:args.sites or None]
    rich_items = list(RICH.items())[:args.sites or None]
    print("-- CONTROLS (expect gate-out / no value-bar clear) --")
    controls = [r for r in (_eval_site(n, u, args.cdp_port, False) for n, u in ctrl_items) if r]
    print("-- RICH CANDIDATES --")
    rich = [r for r in (_eval_site(n, u, args.cdp_port, True) for n, u in rich_items) if r]
    rich = [r for r in rich if r["rich"]]   # drop frozen candidates that failed richness

    dec, why = verdict(controls, rich)
    print("\n== VERDICT: %s ==\n   %s" % (dec, why))
    print("   controls_clearing=%d rich_gated=%d rich_clearing=%d"
          % (sum(1 for r in controls if _clears(r)),
             sum(1 for r in rich if r["gated_in"]), sum(1 for r in rich if _clears(r))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 3: Verify the module still imports + unit suite still green**

Run: `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v && python3 -c "import sys; sys.path.insert(0,'research/capture-gap-probes'); import probe_g3c_richness_gated"`
Expected: 15 passed; import OK.

- [ ] **Step 4: Commit**

```bash
git add research/capture-gap-probes/probe_g3c_richness_gated.py
git commit -m "feat: G3c probe HOST-CDP orchestration + Floor-A + main (verdict runner)"
```

---

### Task 10: README manifest + live-run instructions

**Files:**
- Modify: `research/capture-gap-probes/README.md`

- [ ] **Step 1: Add a probe row + run block** (append under the script manifest)

```markdown
### G3c richness-gated de-risk · `probe_g3c_richness_gated.py`
Pre-registration: `docs/plans/richness-gated-g3c-design.md`. HOST CDP only.
- Unit suite (no browser): `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
- Floor-A:   `python3 research/capture-gap-probes/probe_g3c_richness_gated.py --floor-a https://mui.com/`
- Full run:  `python3 research/capture-gap-probes/probe_g3c_richness_gated.py` (launch Chrome `:9222` first; open a blank tab — see memory `cdp-capture-needs-open-tab`)
Emits BUILD/DEFER per the §6 bar. Content-free: counts/jaccard/role-names/netloc only.
```

- [ ] **Step 2: Commit**

```bash
git add research/capture-gap-probes/README.md
git commit -m "docs: add G3c richness-gated probe to capture-gap-probes manifest"
```

---

### Task 11: Live run + record the verdict (manual harness)

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (append a `§C9-R-G3c-rg` results section)

This is a manual HOST leg (env-skip in CI per memory `live-cdp-capture-is-manual-harness-not-pytest`). It produces the actual pre-registered verdict.

- [ ] **Step 1: Launch Chrome on the host with an open tab**

Run (host shell, via `!` prefix): `/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/g3c-rg-chrome about:blank &`
Expected: Chrome window; `:9222` reachable.

- [ ] **Step 2: Floor-A determinism check first**

Run: `python3 research/capture-gap-probes/probe_g3c_richness_gated.py --floor-a https://mui.com/`
Expected: `FLOOR_A determinism ... identical=True`. If False, STOP — the signature is non-deterministic; fix before trusting any verdict.

- [ ] **Step 3: Full run**

Run: `python3 research/capture-gap-probes/probe_g3c_richness_gated.py 2>/dev/null`
Expected: per-site lines for 6 controls + 8 rich, then `== VERDICT: BUILD|DEFER ==`.

- [ ] **Step 4: Record the verdict** (append `§C9-R-G3c-rg — VERDICT: <BUILD|DEFER> ...` to the gaps doc with the per-site table, every-bundle-audited-CLEAN note, Floor-A=TRUE, and the honest finding — mirroring the existing `§C9-R-G3c-revisit` results block). Commit.

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record G3c richness-gated de-risk verdict (§C9-R-G3c-rg)"
```

- [ ] **Step 5: If BUILD — open the Phase-2 cycle** (separate brainstorm→spec→plan→build for `components.json` emitted via a `site_capture` post-processor, runtime richness gate shipped). If DEFER — the finding is the deliverable; update the §C9 ladder status line.

---

## Self-Review

**1. Spec coverage** (each design §):
- §0 two-phase shape → Tasks 1–11 are Phase-1; Task 11 Step 5 gates Phase-2. ✓
- §1 `components.json` → Phase-2 only (not this plan); the probe measures whether to build it. ✓
- §2 richness gate → Task 4 (`gate`). ✓ §3 cohort → Task 1 (`CONTROLS`/`RICH` frozen). ✓ §3c richness predicate → Task 7. ✓
- §4 composition-novel → Task 5 (incl. generic-wrapper + distinct-role exclusions). ✓
- §5 coverage (main minus chrome) → Task 6. ✓
- §6 BUILD bar (neg-control, positive, validity) → Task 8 (`verdict`). ✓
- §7 content-free (audit every bundle, no stderr, Floor-A) → Tasks 9 (`_capture_routes` audits, returncode-only), 11 (Floor-A). ✓
- §8 testing (pure-core units, discrimination fixture, live manual leg) → Tasks 2–8 units, Task 5 fixture, Task 11 live. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; Task 11 Step 4 references the existing `§C9-R-G3c-revisit` block as the format template (concrete, not a placeholder).

**3. Type consistency:** result dicts use `{netloc, gated_in, novel, coverage}` keys consistently in `_eval_site`, `_clears`, `verdict`, and the test `_res` helper. `gate` returns `(bool, {level,core,jac,pass})` consistently in Task 4 + Task 9. `_node_token(n, level)` / `_route_sig_set(nodes, level, landmark_roles, depth)` signatures match across Tasks 2–7. `composition_novel_components`/`coverage` both take `(…, level, landmark_roles, depth)`. ✓

**4. Reuse check:** `C._children / signature / _is_styled / recurrence / _cdp_reachable / _audit_clean` reused, not reimplemented (DRY). `web_skeleton.LANDMARK_ROLES` injected as `landmark_roles`. ✓
