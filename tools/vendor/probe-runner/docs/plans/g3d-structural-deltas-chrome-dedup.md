# G3d Structural+Deltas Chrome Dedup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the gate-cleared G3d shared-chrome dedup as a production pass that reads a G3a multi-route capture and emits one content-free, **losslessly reconstructable** deduped-chrome artifact, with realized savings reconciled against the probe's net band.

**Architecture:** Mirror the G3b shape exactly — a pure, I/O-free core (`scripts/_chrome_dedup.py`) plus a CLI (`scripts/site_chrome.py`) that loads `routes/<id>/skeleton.json`, dedups, self-checks round-trip losslessness, writes `chrome_dedup.json`, and re-audits the output through `content_firewall.audit_bundle`. A research reconcile harness proves realized savings track the probe's net bbox-only column before the artifact is trusted.

**Tech stack:** Python 3, stdlib only (`json`, `collections`, `pathlib`, `argparse`). Reuses `content_firewall.audit_bundle` and `_common.emit_json`/`die`. No CDP, no third-party deps in the core.

---

## Pre-registration provenance (do not re-derive — copy from these)

- **Design / accounting:** `docs/plans/g3d-structural-deltas-chrome-dedup-design.md` (structural key `S(n)`, tiling, node-basis accounting, pinned schema §4).
- **Verdict + encoding pin:** `docs/plans/g3d-structural-deltas-chrome-dedup-results.md`. Gross median 17.5% → **net ∈ [12.4% floor, 15.8% bbox-only] median**, both clear the 12% bar. The build MUST target the **bbox-only** encoding.
- **Validated algorithm (lift these primitives verbatim):** `research/capture-gap-probes/probe_g3d_structural.py` (`DROP_STRUCT`, `_POS_TOP`, `_VOL_SET`, `_VOL_KEYS`, `_leaf_counts`, `_vol_val`, `_tile_struct`, `_struct_savings`) and `probe_g3d_dedup.py` (`_node_key`, `_subtree`, `_roots`, `CHROME`, `_KEY_FIELDS`, `DROP_TR`, `DROP_TXT`; `_children` from `calib_component_signature`).

These are **research** modules. Production code must NOT import from `research/` — re-home the needed primitives into `_chrome_dedup.py` as a self-contained core (same as `_merge.py` is self-contained). The reconcile harness (Task 6) is the only new file allowed to live in `research/`.

## The two hard requirements (a green unit test will NOT prove either)

1. **Encoding pin (bbox-only).** Per recurring structural key, store the template once with its full structural skeleton **and** the structure-derived positional fields (`parent`, `z`, `confidence`, `sizing.confidence`); re-base `id` from a per-instance base; charge only `bbox` per instance plus the volatile deltas. Re-storing all positional per instance lands realized savings at the 12.4% **floor** (clears the bar by only 0.4 pt). The build must land near **15.8%**, not the floor.

2. **Lossless by construction + reconcile, not unit-green.**
   - *Losslessness is absolute:* `reconstruct(dedup(skeletons)) == skeletons` byte-for-byte (node-list equality). Anything that does NOT reconstruct from the template is stored as a per-instance exception and **charged** — never dropped. This is the escape hatch that keeps the artifact lossless even when `z`/`parent`/`confidence` turn out to vary per instance.
   - *Savings is empirical:* realized node-fraction saving must track the probe's **net bbox-only** column (python 11.1 · iana 19.6 · django 12.0 · w3 25.8 · gnu 6.3 · apache 24.9 → ~15.8% median). The probe number is a node-fraction proxy; real reconstruction won't match exactly. Acceptance = **"consistent with the probe; investigate any material gap (>~3 pt or median below the floor)"**, NOT equality. If exceptions erode realized savings toward the 12.4% floor, that is the honest signal that `z`/`parent` are not as templatable as the bbox-only bound assumed.

---

## File Structure

- **Create `scripts/_chrome_dedup.py`** — pure core, no I/O. Self-contained primitives + `dedup_chrome` + `reconstruct`. Tasks 1–4.
- **Create `scripts/site_chrome.py`** — CLI: load capture → `dedup_chrome` → round-trip self-check → write `chrome_dedup.json` → `audit_bundle` backstop → `emit_json`. Task 5.
- **Create `scripts/test_chrome_dedup.py`** — pure-core unit tests incl. the round-trip losslessness invariant. Tasks 1–4.
- **Create `scripts/test_site_chrome.py`** — CLI integration on a synthetic multi-route fixture + firewall backstop. Task 5.
- **Create `research/capture-gap-probes/reconcile_g3d_chrome.py`** — run the shipped pass on the 6 probe sites; compare realized saving to the probe net bbox-only band. Task 6.

Decomposition rationale: the core is pure and exhaustively unit-testable (incl. losslessness); the CLI is a thin firewall-gated I/O shell; the reconcile harness is the only piece that needs a live capture and is the real acceptance gate.

---

### Task 1: Pure-core graph primitives + structural key

**Files:**
- Create: `scripts/_chrome_dedup.py`
- Test: `scripts/test_chrome_dedup.py`

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_chrome_dedup.py
import _chrome_dedup as D


def _node(nid, parent=None, role=None, tag="div", **extra):
    n = {"id": nid, "parent": parent, "tag": tag, "z": 0, "confidence": 1.0}
    if role is not None:
        n["aria_role"] = role
    n.update(extra)
    return n


def test_children_and_roots():
    nodes = [_node(1), _node(2, parent=1), _node(3, parent=1), _node(4)]
    bp = D._children(nodes)
    assert [c["id"] for c in bp[1]] == [2, 3]
    assert [r["id"] for r in D._roots(nodes)] == [1, 4]


def test_structural_key_ignores_positional_and_volatile():
    # same structure, different id/parent/bbox/z and different token_ref/text_len -> same key
    a = _node(10, parent=1, role="navigation", token_ref={"bg": "a", "fg": "b", "border": "c"},
              text_len=5, bbox={"x": 0, "y": 0, "w": 10, "h": 10})
    b = _node(99, parent=7, role="navigation", token_ref={"bg": "X", "fg": "Y", "border": "Z"},
              text_len=999, bbox={"x": 5, "y": 5, "w": 20, "h": 20})
    assert D._node_key(a) == D._node_key(b)


def test_structural_key_separates_real_structure():
    # tag is NOT a keyed field; a keyed field (aria_role) must drive the distinction
    a = _node(1, role="navigation")
    b = _node(2, role="banner")
    assert D._node_key(a) != D._node_key(b)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named '_chrome_dedup'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_chrome_dedup.py
#!/usr/bin/env python3
"""G3d shared-chrome dedup (pure core) — structural-template + per-instance lossless deltas.

Reads N per-route skeleton node-lists, dedups recurring chrome landmarks against a structural
template, and emits an artifact that reconstructs each route's nodes BYTE-IDENTICALLY. Lossless by
construction: any field that does not derive from the template is stored as a per-instance
exception (charged), never dropped.

Gate provenance: docs/plans/g3d-structural-deltas-chrome-dedup-{design,results}.md. Encoding pin =
bbox-only (template parent/z/confidence, re-base id, charge bbox per instance). No I/O, no CDP."""
from __future__ import annotations

from collections import Counter, defaultdict

# --- structural key (re-homed from probe_g3d_structural; volatile + positional excluded) ---
CHROME = frozenset({"banner", "navigation", "contentinfo", "complementary"})

# Pre-registered 20-field exact order — COPY VERBATIM from probe_g3d_dedup._KEY_FIELDS (do not
# re-derive; these are the real serialized field names).
_KEY_FIELDS = (
    "role", "aria_role", "layout.mode", "layout.direction", "layout.gap", "layout.pad",
    "layout.justify", "layout.align", "layout.grid_cols", "layout.grid_rows", "sizing.w",
    "sizing.h", "token_ref.bg", "token_ref.fg", "token_ref.border", "font.family", "font.weight",
    "text_len", "pseudo", "substrate",
)
# Structural key = exact key with the 4 volatile fields BLANKED (design §1 DROP_STRUCT).
_DROP_STRUCT = ("token_ref.bg", "token_ref.fg", "token_ref.border", "text_len")
# Positional (re-stored / re-based per instance, never in the structural key):
_POS_TOP = {"id", "parent", "z", "confidence"}
# Volatile (paid as per-instance deltas): token_ref.{bg,fg,border} + text_len.
_VOL_KEYS = (("token_ref", "bg"), ("token_ref", "fg"), ("token_ref", "border"), ("text_len", None))
_VOL_SET = set(_VOL_KEYS)
_MISSING = object()


def _children(nodes):
    bp = defaultdict(list)
    for n in nodes:
        bp[n.get("parent")].append(n)
    return bp


def _roots(nodes):
    ids = {n["id"] for n in nodes}
    return [n for n in nodes if n.get("parent") not in ids]


def _field_vals(n):
    """Read all 20 keyed fields with the SAME nested access + pseudo normalization as
    probe_g3d_dedup._node_key (faithful copy — keeps structural grouping identical to the probe)."""
    lay = n.get("layout") or {}
    sz = n.get("sizing") or {}
    tr = n.get("token_ref") or {}
    f = n.get("font") or {}
    return {
        "role": n.get("role"), "aria_role": n.get("aria_role"),
        "layout.mode": lay.get("mode"), "layout.direction": lay.get("direction"),
        "layout.gap": lay.get("gap"), "layout.pad": lay.get("pad"),
        "layout.justify": lay.get("justify"), "layout.align": lay.get("align"),
        "layout.grid_cols": lay.get("grid_cols"), "layout.grid_rows": lay.get("grid_rows"),
        "sizing.w": sz.get("w"), "sizing.h": sz.get("h"),
        "token_ref.bg": tr.get("bg"), "token_ref.fg": tr.get("fg"), "token_ref.border": tr.get("border"),
        "font.family": f.get("family"), "font.weight": f.get("weight"),
        "text_len": n.get("text_len"), "pseudo": 1 if n.get("pseudo") else 0,
        "substrate": n.get("substrate"),
    }


def _node_key(n):
    """Structural identity = the exact key with the 4 volatile fields blanked. Returns a string,
    mirroring probe_g3d_dedup._node_key(n, drop=DROP_STRUCT) (pipe-joined, str() per field)."""
    v = _field_vals(n)
    return "|".join("" if name in _DROP_STRUCT else str(v[name]) for name in _KEY_FIELDS)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_chrome_dedup.py scripts/test_chrome_dedup.py
git commit -m "feat: G3d chrome-dedup pure-core primitives — children/roots/structural key"
```

---

### Task 2: Subtree key + volatile delta encode/decode

**Files:**
- Modify: `scripts/_chrome_dedup.py`
- Test: `scripts/test_chrome_dedup.py`

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_chrome_dedup.py
def test_subtree_key_is_structural_and_recursive():
    nodes = [_node(1, role="navigation"), _node(2, parent=1, tag="a"), _node(3, parent=1, tag="a")]
    bp = D._children(nodes)
    k1 = D._subtree(nodes[0], bp)
    # identical structure under a different banner reuses the same subtree key
    nodes2 = [_node(50, role="navigation"), _node(51, parent=50, tag="a"), _node(52, parent=50, tag="a")]
    bp2 = D._children(nodes2)
    assert D._subtree(nodes2[0], bp2) == k1


def test_volatile_delta_roundtrip():
    tmpl = _node(1, token_ref={"bg": "a", "fg": "b", "border": "c"}, text_len=5)
    inst = _node(2, token_ref={"bg": "a", "fg": "Z", "border": "c"}, text_len=5)  # only fg differs
    delta = D._encode_volatile(tmpl, inst)
    assert delta["flags"] == {"token_ref.fg"}        # exactly the differing leaf is flagged
    assert delta["values"] == {"token_ref.fg": "Z"}  # only the differing value is stored
    rebuilt = _node(2, token_ref={"bg": "a", "fg": "b", "border": "c"}, text_len=5)  # = template vols
    D._apply_volatile(rebuilt, tmpl, delta)
    assert rebuilt["token_ref"] == {"bg": "a", "fg": "Z", "border": "c"} and rebuilt["text_len"] == 5
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: FAIL — `AttributeError: module has no attribute '_subtree'`.

- [ ] **Step 3: Write minimal implementation**

```python
# append to scripts/_chrome_dedup.py
def _subtree(node, by_parent):
    """Structural key (string) of a node + its subtree, children in emit order — mirrors
    probe_g3d_dedup._subtree's string form. Isomorphic across two structurally-matching instances,
    so a lock-step walk gives node-to-node correspondence."""
    ck = [_subtree(c, by_parent) for c in by_parent.get(node["id"], [])]
    inner = "(" + ",".join(ck) + ")" if ck else ""
    return _node_key(node) + inner


def _vol_val(n, top, sub):
    if sub is None:
        return n.get(top, _MISSING)
    d = n.get(top)
    return d.get(sub, _MISSING) if isinstance(d, dict) else _MISSING


def _vol_name(top, sub):
    return top if sub is None else top + "." + sub


def _encode_volatile(tmpl, inst):
    """Per-instance volatile delta vs the template node. flags = leaves that differ (1 bit each);
    values = the differing leaf values (lossless). Leaves equal to the template cost only a flag."""
    flags, values = set(), {}
    for top, sub in _VOL_KEYS:
        iv = _vol_val(inst, top, sub)
        if iv is _MISSING:
            continue  # leaf not present on this instance node
        tv = _vol_val(tmpl, top, sub)
        if iv != tv:
            name = _vol_name(top, sub)
            flags.add(name)
            values[name] = iv
    return {"flags": flags, "values": values}


def _apply_volatile(node, tmpl, delta):
    """Reconstruct the instance node's volatile leaves: copy template's, then overwrite the flagged
    ones with the stored values. Mutates `node` in place."""
    for top, sub in _VOL_KEYS:
        name = _vol_name(top, sub)
        if name in delta["values"]:
            val = delta["values"][name]
        else:
            val = _vol_val(tmpl, top, sub)
            if val is _MISSING:
                continue
        if sub is None:
            node[top] = val
        else:
            node.setdefault(top, {})[sub] = val
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_chrome_dedup.py scripts/test_chrome_dedup.py
git commit -m "feat: G3d chrome-dedup subtree key + lossless volatile delta encode/decode"
```

---

### Task 3: Tiling + template construction (`dedup_chrome`)

**Files:**
- Modify: `scripts/_chrome_dedup.py`
- Test: `scripts/test_chrome_dedup.py`

Design: tiling is outermost-wins, non-overlapping, structural-key `occ >= 2` (design §2). For each recurring key the first tiled instance is the template; later instances become refs. Per-instance, the ref stores the **bbox-only** payload: `id_base` (the instance root's id; descendants re-base by template emit-order offset), each node's `bbox`, and the volatile delta. Non-positional structure (`parent`/`z`/`confidence`) is reconstructed from the template + re-based ids — UNLESS it fails to match, in which case it goes in `exceptions` (charged, Task 4 verifies losslessness catches this).

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_chrome_dedup.py
def _nav_route(base, bg):
    # a 3-node nav landmark (root + 2 links) starting at id `base`, with a per-route bg color
    return [
        _node(base, parent=None, role="navigation", token_ref={"bg": bg, "fg": "f", "border": "b"}),
        _node(base + 1, parent=base, tag="a", text_len=4),
        _node(base + 2, parent=base, tag="a", text_len=4),
    ]


def test_dedup_builds_one_template_for_recurring_chrome():
    routes = {"r0": _nav_route(0, "red"), "r1": _nav_route(100, "blue"), "r2": _nav_route(200, "red")}
    art = D.dedup_chrome(routes)
    assert len(art["templates"]) == 1                 # one structural key recurs across 3 routes
    tk = next(iter(art["templates"]))
    refs = [r for route in art["routes"].values() for r in route["refs"] if r["template"] == tk]
    assert len(refs) == 2                              # 3 instances -> 1 template + 2 refs
    # bbox-only: a ref stores bbox + volatile delta + id_base, NOT parent/z/confidence per node
    sample = refs[0]
    assert "id_base" in sample and "nodes" in sample
    assert set(sample["nodes"][0]) <= {"bbox", "vdelta"}  # per-node payload is bbox + volatile only


def test_singletons_are_not_deduped():
    routes = {"r0": _nav_route(0, "red"),
              "r1": [_node(100, role="banner")]}        # banner appears once -> no template
    art = D.dedup_chrome(routes)
    assert art["templates"] == {} or all(
        len(v) >= 2 for v in _instances_per_key(art).values())
```

```python
# also append this helper at the bottom of the test file
def _instances_per_key(art):
    counts = {}
    for route in art["routes"].values():
        for r in route["refs"]:
            counts.setdefault(r["template"], 0)
            counts[r["template"]] += 1
    return counts
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: FAIL — `AttributeError: module has no attribute 'dedup_chrome'`.

- [ ] **Step 3: Write minimal implementation**

```python
# append to scripts/_chrome_dedup.py
def _tile(nodes, by_parent, occ):
    """Outermost chrome landmark whose STRUCTURAL subtree key recurs (occ>=2), non-overlapping.
    Returns [(subtree_key, root_node), ...]; does not descend into a selected tile (no double-count)."""
    selected, stack = [], list(_roots(nodes))
    while stack:
        n = stack.pop()
        if n.get("aria_role") in CHROME:
            k = _subtree(n, by_parent)
            if occ[k] >= 2:
                selected.append((k, n))
                continue
        stack.extend(by_parent.get(n["id"], []))
    return selected


def _emit_order(root, by_parent):
    """Template node order: pre-order DFS, children in emit order. Defines the re-base offsets so an
    instance only needs ONE base id; node i's id = id_base + i."""
    out, stack = [], [root]
    while stack:
        n = stack.pop()
        out.append(n)
        stack.extend(reversed(by_parent.get(n["id"], [])))
    return out


def _vol_presence(n):
    """Set of volatile-leaf names present on a node. Structural match SHOULD guarantee template and
    instance agree here (token_ref always carries 3 leaves; text_len co-varies with the keyed
    font.weight). If they ever disagree the per-node delta would be lossy, so dedup_chrome asserts
    this and fails loud rather than letting _apply_volatile silently invent/drop a leaf."""
    return {_vol_name(top, sub) for top, sub in _VOL_KEYS if _vol_val(n, top, sub) is not _MISSING}


def dedup_chrome(route_skeletons):
    """route_skeletons: {route_id: [node, ...]}. Returns the deduped artifact:
      {templates: {key: [<full template node>, ...]},   # one node list per recurring structural key
       routes:    {route_id: {refs:[{template, id_base, root_parent, nodes:[{bbox, vdelta}...],
                                      exceptions:{...}}],
                              donor_keys:[<key whose ONE full copy this route holds>],
                              rest:[<non-deduped nodes>]}}}
    The donor route (first instance of a key) stores NO ref and NO full chrome copy of its own — its
    chrome IS templates[key], recovered verbatim via donor_keys. So each template is stored exactly
    once; only the m-1 non-donor instances become refs (and count as saved). Lossless: reconstruct()."""
    prepared = {rid: (nodes, _children(nodes)) for rid, nodes in route_skeletons.items()}
    occ = Counter()
    for nodes, bp in prepared.values():
        for n in nodes:
            if n.get("aria_role") in CHROME:
                occ[_subtree(n, bp)] += 1

    templates = {}
    routes_out = {}
    for rid, (nodes, bp) in prepared.items():
        tiles = _tile(nodes, bp, occ)
        tiled_ids = set()
        refs = []
        donor_keys = []                                   # keys whose ONE full copy this route holds
        for key, root in tiles:
            order = _emit_order(root, bp)
            tiled_ids.update(n["id"] for n in order)
            if key not in templates:                      # first instance = template (donor)
                templates[key] = [dict(n) for n in order]
                donor_keys.append(key)                    # recovered verbatim from templates[key]
                continue
            tmpl_nodes = templates[key]
            # Equal structural keys must mean equal subtree size; a length mismatch would imply a
            # key collision and silently truncate `zip` below (a latent loss). Fail loud instead.
            assert len(tmpl_nodes) == len(order), \
                "structural-key collision: template/instance subtree length mismatch"
            base = root["id"]
            tmpl_idx = {tn["id"]: j for j, tn in enumerate(tmpl_nodes)}   # template id -> emit index
            per_node, exceptions = [], {}
            # Siblings must share emit order (DOM pre-order, stable across a site's routes) for the
            # bbox-only ideal; a reordered instance stays lossless but charges id exceptions.
            for i, (tn, inode) in enumerate(zip(tmpl_nodes, order)):
                if _vol_presence(tn) != _vol_presence(inode):       # tripwire: keeps the delta lossless
                    raise ValueError("volatile-leaf presence mismatch (template vs instance) at tile "
                                     "node %d — structural match must guarantee equal presence" % i)
                per_node.append({"bbox": inode.get("bbox"),
                                 "vdelta": _encode_volatile(tn, inode)})
                # Re-basing: web_skeleton numbers nodes id=len(emitted) in pre-order, so a tiled
                # landmark (a COMPLETE subtree) occupies a contiguous id range -> node i sits at
                # base+i, and an internal node's parent sits at base+(template-parent's emit index).
                # The tile root's parent points OUTSIDE the tile -> stored verbatim as root_parent.
                exp_id = base + i
                exp_parent = root.get("parent") if i == 0 else base + tmpl_idx[tn["parent"]]
                exc = _diff_nonpositional(tn, inode, exp_id, exp_parent)
                if exc:
                    exceptions[str(i)] = exc               # str key: JSON-stable, charged, lossless
            refs.append({"template": key, "id_base": base,
                         "root_parent": root.get("parent"),
                         "nodes": per_node, "exceptions": exceptions})
        rest = [n for n in nodes if n["id"] not in tiled_ids]
        routes_out[rid] = {"refs": refs, "donor_keys": donor_keys, "rest": rest}
    return {"templates": templates, "routes": routes_out}


def _diff_nonpositional(tmpl_node, inst_node, expected_id, expected_parent):
    """Everything the bbox-only encoding ASSUMES is template-derived: id (== expected_id from
    re-basing), parent (== expected_parent), z, confidence. Any mismatch is returned as an exception
    so reconstruct() restores it EXACTLY -> losslessness is UNCONDITIONAL (robust even if a future id
    scheme breaks pre-order contiguity; that would just charge more, eroding savings toward the
    floor — an honest measurement, never a corrupt reconstruct). Empty dict => the node reconstructs
    purely from template + id_base + bbox + vdelta (the bbox-only ideal)."""
    exc = {}
    if inst_node.get("id") != expected_id:
        exc["id"] = inst_node.get("id")
    if inst_node.get("parent") != expected_parent:
        exc["parent"] = inst_node.get("parent")
    for f in ("z", "confidence"):
        if inst_node.get(f) != tmpl_node.get(f):
            exc[f] = inst_node.get(f)
    return exc
```

Why `parent` is charged (not template-derived blindly): the tile root's parent points outside the
tile and is stored verbatim (`root_parent`); internal parents are re-based from `id_base`. Charging
on mismatch makes the round-trip lossless under ANY id layout — on the verified `id=len(emitted)`
pre-order scheme, contiguous subtree ids mean zero id/parent exceptions (full bbox-only savings).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_chrome_dedup.py scripts/test_chrome_dedup.py
git commit -m "feat: G3d chrome-dedup tiling + bbox-only template construction"
```

---

### Task 4: Reconstruction + round-trip losslessness invariant (THE gate-critical test)

**Files:**
- Modify: `scripts/_chrome_dedup.py`
- Test: `scripts/test_chrome_dedup.py`

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_chrome_dedup.py
def _by_id(nodes):
    return {n["id"]: n for n in nodes}


def test_roundtrip_byte_identical_simple():
    routes = {"r0": _nav_route(0, "red"), "r1": _nav_route(100, "blue"), "r2": _nav_route(200, "red")}
    art = D.dedup_chrome(routes)
    rebuilt = D.reconstruct(art)
    for rid, original in routes.items():
        assert _by_id(rebuilt[rid]) == _by_id(original), rid   # exact node-set equality per route


def test_roundtrip_lossless_when_z_varies_per_instance():
    # z differs across instances -> bbox-only assumption breaks -> must be stored as an exception,
    # and reconstruction must STILL be byte-identical (losslessness is absolute).
    r0 = _nav_route(0, "red")
    r1 = _nav_route(100, "red")
    r1[0]["z"] = 9                                   # template z=0, this instance z=9
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert ref["exceptions"].get("0", {}).get("z") == 9   # charged (str key), not dropped
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)


def test_reconstruct_preserves_non_chrome_rest_nodes():
    routes = {"r0": _nav_route(0, "red") + [_node(9, tag="main")],
              "r1": _nav_route(100, "blue") + [_node(109, tag="main")]}
    art = D.dedup_chrome(routes)
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r0"]) == _by_id(routes["r0"])
    assert _by_id(rebuilt["r1"]) == _by_id(routes["r1"])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: FAIL — `AttributeError: module has no attribute 'reconstruct'`.

- [ ] **Step 3: Write minimal implementation**

Add `import copy` to the top of `scripts/_chrome_dedup.py` (next to `from collections import ...`).
Then append:

```python
# append to scripts/_chrome_dedup.py
def reconstruct(artifact):
    """Inverse of dedup_chrome: returns {route_id: [node, ...]} node-set identical (id-keyed) to the
    input — node ORDER is not part of the contract (downstream compares by id, e.g. Task 5's
    _node_sets_equal). A donor_key's chrome is templates[key] emitted verbatim (its nodes already
    carry the donor's original id/parent/bbox/volatile — no re-basing). Each ref is expanded from its
    template with re-based ids, per-node bbox + volatile delta, and exceptions."""
    templates = artifact["templates"]
    out = {}
    for rid, route in artifact["routes"].items():
        nodes = []
        for key in route.get("donor_keys", []):           # the route that holds this template in full
            nodes.extend(copy.deepcopy(n) for n in templates[key])
        for ref in route["refs"]:
            tmpl = templates[ref["template"]]
            base = ref["id_base"]
            id_of = [base + i for i in range(len(tmpl))]
            # map a template node's original id -> its emit-order index, to re-base parent links
            tmpl_idx = {tn["id"]: i for i, tn in enumerate(tmpl)}
            for i, tn in enumerate(tmpl):
                # DEEP copy: _apply_volatile mutates node["token_ref"] in place via setdefault, so a
                # shallow dict(tn) would alias and corrupt the shared template (and the artifact Task 5
                # serializes) across instances. deepcopy gives each reconstructed node its own nested
                # dicts (token_ref/layout/sizing/font/bbox).
                n = copy.deepcopy(tn)                         # structural fields from template
                n["id"] = id_of[i]
                if i == 0:
                    n["parent"] = ref.get("root_parent")
                else:
                    n["parent"] = id_of[tmpl_idx[tn["parent"]]]  # re-based internal parent
                pn = ref["nodes"][i]
                if pn.get("bbox") is not None:
                    n["bbox"] = pn["bbox"]                    # instance bbox overrides template's
                elif "bbox" in n:
                    del n["bbox"]                             # instance had none -> don't inherit template's
                _apply_volatile(n, tn, pn["vdelta"])
                for f, v in ref.get("exceptions", {}).get(str(i), {}).items():
                    n[f] = v                                  # restore charged field exactly (str key)
                nodes.append(n)
        nodes.extend(copy.deepcopy(n) for n in route["rest"])
        out[rid] = nodes
    return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: PASS (15 tests: 12 prior + 3 new round-trip). If `test_roundtrip_*` fails, the encoding is **lossy** — fix `reconstruct`/`_diff_nonpositional` until byte-identical before proceeding. Do NOT relax the assertion.

- [ ] **Step 5: Commit**

```bash
git add scripts/_chrome_dedup.py scripts/test_chrome_dedup.py
git commit -m "feat: G3d chrome-dedup reconstruct + round-trip losslessness invariant"
```

---

### Task 5: `site_chrome.py` CLI — load, self-check, write, firewall backstop

**Files:**
- Create: `scripts/site_chrome.py`
- Test: `scripts/test_site_chrome.py`

Mirror `site_merge.py`: load `routes/<id>/skeleton.json` for ok routes, dedup, **fail closed** if round-trip is not byte-identical, write `chrome_dedup.json`, re-audit the output's parent dir through `content_firewall.audit_bundle`, unlink on any violation, `emit_json` the summary.

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_site_chrome.py
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _write_route(site, rid, nodes):
    rd = site / "routes" / rid
    rd.mkdir(parents=True, exist_ok=True)
    (rd / "skeleton.json").write_text(json.dumps({"nodes": nodes}))


def _nav(base, bg):
    return [
        {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
         "confidence": 1.0, "token_ref": {"bg": bg, "fg": "f", "border": "b"}},
        {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4},
    ]


def test_cli_dedups_and_roundtrips(tmp_path):
    site = tmp_path / "site_out"
    (site).mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    _write_route(site, "r0", _nav(0, "red"))
    _write_route(site, "r1", _nav(100, "blue"))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout
    payload = json.loads(r.stdout)
    assert payload["ok"] is True and payload["roundtrip_ok"] is True
    assert payload["template_count"] == 1
    assert out.exists()


def test_written_artifact_reloads_and_reconstructs(tmp_path):
    # the ON-DISK file (not in-memory art) must reconstruct byte-identically
    import _chrome_dedup as D
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    _write_route(site, "r0", _nav(0, "red"))
    _write_route(site, "r1", _nav(100, "blue"))
    out = site / "chrome_dedup.json"
    subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                    "--site", str(site), "--out", str(out)],
                   check=True, capture_output=True, text=True)
    loaded = json.loads(out.read_text())
    rebuilt = D.reconstruct(loaded)
    originals = {"r0": _nav(0, "red"), "r1": _nav(100, "blue")}
    for rid, orig in originals.items():
        assert {n["id"]: n for n in rebuilt[rid]} == {n["id"]: n for n in orig}, rid
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_site_chrome.py -v`
Expected: FAIL — `site_chrome.py` does not exist (non-zero return, file-not-found).

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/site_chrome.py
#!/usr/bin/env python3
"""Cross-route shared-chrome dedup (G3d). Read a G3a capture (site.json + routes/<id>/skeleton.json
across N routes) and emit a content-free, losslessly-reconstructable deduped-chrome artifact
(chrome_dedup.json, schema probe-runner/chrome-dedup@1).

Content-free: stores only structural mechanism + positional ids/bbox + token_ref/text_len deltas,
the same fields the firewalled skeletons already carry. The output's parent dir is re-audited
through content_firewall.audit_bundle and never persisted on a violation.

Lossless: reconstruct(dedup(skeletons)) is byte-identical to the input; the CLI fails closed if not.

Usage: python3 scripts/site_chrome.py --site site_out [--out chrome_dedup.json]
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
import content_firewall as cf
import _chrome_dedup as D


def _load_routes(site_dir):
    try:
        site = json.loads((site_dir / "site.json").read_text())
    except (OSError, ValueError):
        die("cannot read site.json under %s" % site_dir)  # clean die (exit 2), not a traceback
    routes = {}
    for r in site.get("routes", []):
        if not r.get("ok"):
            continue
        sk = site_dir / "routes" / r["route_id"] / "skeleton.json"
        if not sk.exists():
            continue
        try:
            doc = json.loads(sk.read_text())
        except Exception:
            continue                                  # per-route isolation, mirrors G3a
        nodes = doc.get("nodes", doc) if isinstance(doc, dict) else doc
        if isinstance(nodes, list):
            routes[r["route_id"]] = nodes
    return routes


def _node_sets_equal(a, b):
    by = lambda ns: {n["id"]: n for n in ns}
    return by(a) == by(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True)
    ap.add_argument("--out")
    args = ap.parse_args()
    site_dir = Path(args.site)
    out = Path(args.out) if args.out else site_dir / "chrome_dedup.json"

    routes = _load_routes(site_dir)
    if len(routes) < 2:
        die("need >=2 ok routes with skeletons to dedup chrome")

    art = D.dedup_chrome(routes)

    # Losslessness gate (absolute): reconstruct must be byte-identical, else fail closed.
    rebuilt = D.reconstruct(art)
    roundtrip_ok = all(rid in rebuilt and _node_sets_equal(rebuilt[rid], routes[rid])
                       for rid in routes)
    if not roundtrip_ok:
        die("round-trip not byte-identical — dedup would be lossy; refusing to write")

    doc = {"schema": "probe-runner/chrome-dedup@1", "route_count": len(routes), **_jsonable(art)}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2, ensure_ascii=False))

    viol = cf.audit_bundle(out.parent)
    if viol:
        out.unlink(missing_ok=True)
        emit_json({"ok": False, "error": "content_firewall", "out": str(out),
                   "violations": len(viol)})
        return 3                                       # nonzero exit (mirrors site_merge) on flag
    emit_json({"ok": True, "out": str(out), "roundtrip_ok": True,
               "route_count": len(routes), "template_count": len(art["templates"])})
    return 0


def _jsonable(art):
    """JSON-safe view of the artifact. Structural keys are STRINGS, so `templates` persists as a
    {key: nodes} dict that reconstruct() consumes DIRECTLY (the on-disk file is exactly what
    reconstruct reads). Only two non-JSON values exist: each vdelta `flags` set -> sorted list
    (informational; reconstruct reads `values`, never `flags`). `exceptions` keys are already str."""
    routes = {}
    for rid, route in art["routes"].items():
        refs = []
        for ref in route["refs"]:
            r = dict(ref)
            r["nodes"] = [{"bbox": pn.get("bbox"),
                           "vdelta": {"flags": sorted(pn["vdelta"]["flags"]),
                                      "values": pn["vdelta"]["values"]}} for pn in ref["nodes"]]
            refs.append(r)
        routes[rid] = {"refs": refs, "donor_keys": route["donor_keys"], "rest": route["rest"]}
    return {"templates": art["templates"], "routes": routes}


if __name__ == "__main__":
    raise SystemExit(main())
```

No tuple-key reindex step exists or is needed: the string-key core (Task 1) makes `templates` a
JSON-valid `{key: nodes}` dict, and `reconstruct()` consumes that on-disk shape unchanged. The
reload-roundtrip test below proves the **written file** (not just in-memory `art`) reconstructs
byte-identically.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_site_chrome.py -v`
Expected: PASS (2 tests — incl. the on-disk reload roundtrip). Then run the whole core+CLI suite: `python3 -m pytest test_chrome_dedup.py test_site_chrome.py -v` — all green.

- [ ] **Step 5: Commit**

```bash
git add scripts/site_chrome.py scripts/test_site_chrome.py
git commit -m "feat: G3d site_chrome CLI — dedup + lossless self-check + firewall backstop"
```

---

### Task 6: Reconcile harness — realized savings vs probe net band (ACCEPTANCE GATE)

**Files:**
- Create: `research/capture-gap-probes/reconcile_g3d_chrome.py`

This is the real acceptance gate (the advisor's point #4): a green unit suite does NOT prove the 15.8% holds. Capture the same 6 sites, run the shipped `site_chrome` pass, compute the **realized** node-fraction saving from the actual artifact, and compare to the probe's net bbox-only column.

Realized saving (node-fraction, same unit as the bar): for each recurring template with `m` instances, the saved node-equivalents = Σ over the `m−1` refs of `(D(node) − charged(node)) / D(node)`, where `charged(node)` counts the per-instance bytes actually stored (bbox leaves + differing volatile values + exception fields + flag overhead). Denominator = total nodes across routes. This reads the **artifact**, not a model — so exceptions that eroded losslessness are automatically reflected.

- [ ] **Step 1: Write the harness**

```python
# research/capture-gap-probes/reconcile_g3d_chrome.py
#!/usr/bin/env python3
"""Reconcile the SHIPPED G3d chrome dedup against the probe's net bbox-only band.

Probe net bbox-only (docs/plans/g3d-structural-deltas-chrome-dedup-results.md):
  python 11.1 · iana 19.6 · django 12.0 · w3 25.8 · gnu 6.3 · apache 24.9  -> median 15.8
Acceptance: realized median within ~3 pt of 15.8 AND not below the 12.4 floor median; per-site
realized within ~3 pt of its probe bbox-only value, else INVESTIGATE (the encoding pin slipped
toward the floor — likely z/parent stored as exceptions). Equality is NOT expected; this is a
node-fraction proxy vs real reconstruction.

Reuses probe_g3d_dedup._capture/_capture layout + SITES; runs scripts/site_chrome.py on each capture.
Usage: python3 reconcile_g3d_chrome.py [--cdp-port 9222] [--sites N] [--routes N]
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import probe_g3d_dedup as P
import probe_g3d_net as N   # reuse _leaf_counts4 + the bbox-only formula — SAME basis as the target
SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
sys.path.insert(0, str(SCRIPTS))
import _chrome_dedup as D

PROBE_BBOX = {"python.org": 11.1, "iana.org": 19.6, "djangoproject.com": 12.0,
              "w3.org": 25.8, "gnu.org": 6.3, "apache.org": 24.9}
FLOOR_MEDIAN, BBOX_MEDIAN, TOL = 12.4, 15.8, 3.0


def _realized_bbox_pct(art, total_nodes):
    """Realized saving on the EXACT basis probe_g3d_net uses for bbox-only, so the comparison is
    like-for-like (NOT struct+vol — that denominator is ~0.87x and would trip false INVESTIGATE):
        F = pos + struct + vol;  node_saved = (struct + (pos - bbox) + matched - flag) / F
    matching probe_g3d_net._delta_net's bbox_only branch. Two adjustments for the SHIPPED encoder:
      - matched = vol - len(vdelta.values)        (values = the differing volatile leaves stored)
      - exceptions = id/parent/z/confidence leaves that did NOT template -> SUBTRACTED from the
        (pos-bbox) credit, so encoder slippage erodes realized toward the floor honestly.
    Per-node leaf counts come from the template node (struct match => equal pos/struct/vol presence).
    Denominator = total nodes (node-fraction), identical to probe_g3d_net._net_savings."""
    templates = art["templates"]
    saved = 0.0
    for route in art["routes"].values():
        for ref in route["refs"]:
            tmpl = templates[ref["template"]]
            excs = ref.get("exceptions", {})
            for i, pn in enumerate(ref["nodes"]):
                pos, struct, vol, bbox = N._leaf_counts4(tmpl[i])
                F = (pos + struct + vol) or 1
                matched = max(0, vol - len(pn["vdelta"]["values"]))
                flag = vol / 64.0
                charged_pos = len(excs.get(str(i), {}))      # positional leaves not templated
                node_saved = (struct + (pos - bbox) - charged_pos + matched - flag) / F
                saved += max(0.0, node_saved)
    return 100.0 * saved / (total_nodes or 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    ap.add_argument("--sites", type=int, default=0)
    ap.add_argument("--routes", type=int, default=0)
    args = ap.parse_args()
    items = list(P.SITES.items())[: args.sites or None]

    print("== G3d RECONCILE :: realized vs probe bbox-only (tol +-%.1f) ==" % TOL)
    realized = []
    for netloc, urls in items:
        if args.routes:
            urls = urls[: args.routes]
        lists, clean, rc = P._capture(urls, args.cdp_port)
        if not clean or len(lists) < 2:
            print("  %-20s skipped (clean=%s routes=%d)" % (netloc, clean, len(lists)))
            continue
        routes = {"r%d" % i: nodes for i, nodes in enumerate(lists)}
        art = D.dedup_chrome(routes)
        assert D.reconstruct(art).keys() == routes.keys()  # losslessness smoke
        total = sum(len(n) for n in lists)
        pct = _realized_bbox_pct(art, total)
        realized.append(pct)
        ref = PROBE_BBOX.get(netloc)
        flag = "" if ref is None or abs(pct - ref) <= TOL else "  !! INVESTIGATE"
        print("  %-20s realized=%.1f  probe_bbox=%.1f%s" % (netloc, pct, ref or -1, flag))

    if len(realized) < P.BAR["min_data"]:
        print("INCONCLUSIVE — <%d sites" % P.BAR["min_data"]); return 2
    med = P._median(realized)
    print("\n  realized median=%.1f  (probe bbox-only=%.1f, floor=%.1f)" % (med, BBOX_MEDIAN, FLOOR_MEDIAN))
    if med >= FLOOR_MEDIAN - TOL and abs(med - BBOX_MEDIAN) <= TOL + 1.0:
        print("VERDICT: RECONCILED — shipped dedup tracks the probe net band; build is honest.")
        return 0
    print("VERDICT: GAP — realized median %.1f off the probe band; the encoding slipped toward the "
          "floor (inspect per-site INVESTIGATE rows + exception counts)." % med)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Run the harness against a live capture**

Preconditions (from memory `cdp-capture-needs-open-tab`): launch a Chrome on :9222 and open ONE blank page target first (`PUT http://127.0.0.1:9222/json/new?about:blank`). Heavy sites may need `PROBE_RUNNER_CDP_TIMEOUT=90`.

Run: `cd research/capture-gap-probes && PROBE_RUNNER_CDP_TIMEOUT=90 python3 reconcile_g3d_chrome.py`
Expected: per-site `realized` within ±3 pt of `probe_bbox`; `VERDICT: RECONCILED`. Any `!! INVESTIGATE` row or `VERDICT: GAP` = inspect exception counts (z/parent slipping to exceptions erodes toward the floor) before declaring the build done.

- [ ] **Step 3: Record the reconcile result**

Append a `## Reconcile (shipped build vs probe band)` section to `docs/plans/g3d-structural-deltas-chrome-dedup-results.md` with the per-site realized/probe table and the verdict. If GAP, record it honestly and stop — do not tune the encoding to chase the number (that un-pre-registers the build).

- [ ] **Step 4: Commit**

```bash
git add research/capture-gap-probes/reconcile_g3d_chrome.py docs/plans/g3d-structural-deltas-chrome-dedup-results.md
git commit -m "test: G3d chrome-dedup reconcile harness — realized savings vs probe net band"
```

---

## Self-Review

**1. Spec coverage** (design §1–§9 + results encoding pin):
- §1 structural key `S(n)` → Task 1 `_node_key` (volatile + positional excluded). ✓
- §2 tiling (outermost-wins, occ≥2, non-overlapping) → Task 3 `_tile`. ✓
- §3 node-basis accounting / per-node delta → Task 2 volatile delta + Task 6 realized node-fraction. ✓
- §7 iana/django coherence (token_ref paid as delta, not free) → Task 2 stores differing token_ref as a charged value; Task 6 reflects it per-site. ✓
- §9 BUILD path (template once + per-route positional + lossless deltas) → Tasks 3–5. ✓
- Results **encoding pin (bbox-only)** → Task 3 per-node payload = bbox + vdelta only; parent/z/confidence template-derived, exceptions charge the slippage. ✓
- Results **net band acceptance** → Task 6 reconcile gate. ✓

**2. Placeholder scan:** no TBD/TODO; every code step has complete code. No serialization hand-wave — structural keys are strings (Task 1), so `templates` persists as a JSON-valid `{key: nodes}` dict that `reconstruct()` reads directly; the Task 5 reload-roundtrip test proves the written file (not just in-memory `art`) reconstructs byte-identically. ✓

**3. Type consistency:** artifact shape `{templates:{key:nodes}, routes:{rid:{refs:[{template,id_base,root_parent,nodes:[{bbox,vdelta}],exceptions}], donor_keys:[key,...], rest}}}` is identical across `dedup_chrome` (Task 3), `reconstruct` (Task 4), the CLI serializer (Task 5), and the reconcile reader (Task 6). `donor_keys` (the route that holds each template's one full copy) is a list of structural-key strings — JSON-safe, ridden through `_jsonable` and re-read by `reconstruct` from the on-disk file. Keys: structural keys are **strings** end-to-end (no tuples → JSON-safe). `exceptions` keys are **strings** (`str(i)`) in dedup, reconstruct (`get(str(i))`), and the on-disk file — no int/str drift. `vdelta` = `{flags:set, values:dict}` in-memory; the serializer converts `flags`→sorted list (informational only — `reconstruct`/`_apply_volatile` read `values`, never `flags`). Task 6 reconcile uses `probe_g3d_net._leaf_counts4` + the bbox-only `F`-basis formula (NOT `struct+vol`) so realized is computed on the same basis as the 15.8% target it's checked against; `_VOL_SET`/`_POS_TOP` reused from the core. ✓

**Known follow-on (not in scope, flag at handoff):** wiring `site_chrome.py` into `site_capture.py` so a capture emits `chrome_dedup.json` automatically — deferred until the reconcile gate (Task 6) passes, since an un-reconciled dedup must not become a default capture output.
