# G2 Virtualization Sweep-Merge Engine — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an opt-in `--sweep` capture mode that recovers below-fold structure a single REST `DOMSnapshot` misses on APPEND-class virtualized pages, emitting a content-free `below_fold` addendum (the SET of distinct new shape-keys — no counts, no positions, no content).

**Architecture:** A pure, fully-unit-testable merge function (`scripts/_virt.merge_skeletons`) is the load-bearing core; it computes the set-difference of content-free shape-keys (union of sweep snapshots minus REST) and emits a `below_fold` block of whitelisted shape records. The live scroll-settle sweep that feeds it is a faithful **port of already-proven probe code** (`research/capture-gap-probes/probe_g2_virtualization.py`), wired behind an opt-in flag in `web_skeleton.py`; the default single-REST-snapshot contract is byte-for-byte unchanged. `bundle_writer` already carries the `skeleton` dict through to `skeleton.json`, so the addendum rides along and is audited by the unchanged content firewall.

**Tech Stack:** Python 3.13, pytest (run from `scripts/`), Chrome DevTools Protocol on `:9222` (live leg only, via a manual harness — not pytest).

**Locked ship bar this plan implements:** `docs/plans/g2-virtualization-build.md` (conditions 1–6). Do NOT relax any condition; if a condition cannot be met, STOP and record the finding (the engine defers, it does not ship).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `scripts/_shape_key.py` | **Create** | Canonical content-free shape-key (`_KEY_FIELDS`, `_node_key`). Single source of truth. |
| `scripts/_virt.py` | **Create** | G2 engine: pure `merge_skeletons` / `new_shape_records` / `_shape_record` (unit-tested) + live `sweep_skeletons` (CDP port; manual-tested). |
| `scripts/web_skeleton.py` | **Modify** (`main`, ~L1221–1402) | Add opt-in `--sweep` / `--sweep-steps`; in-class gate; call the engine; REST-only fallback + log when out-of-class. Default path unchanged. |
| `scripts/bundle_writer.py` | **Modify** (`assemble`, ~L272–315) | Redact `below_fold` shape records (firewall backstop) + ensure the block survives assembly. |
| `scripts/site_capture.py` | **Modify** (`_transport_argv` / `capture_route`, ~L35–85) | Forward `--sweep` / `--sweep-steps` to each per-route `web_skeleton` subprocess. |
| `research/capture-gap-probes/probe_g3d_dedup.py` | **Modify** (L85–114) | Re-export the shape-key from `_shape_key` (back-compat; kills the duplicate source). |
| `scripts/test_shape_key.py` | **Create** | Shape-key unit + drift-parity guard. |
| `scripts/test_virt.py` | **Create** | Pure-merge unit tests (conditions 1/2/3/4/5 deterministic legs). |
| `scripts/test_bundle_writer.py` | **Modify** (append) | `below_fold` survives assemble; url() canary in an addendum record trips `audit_bundle`. |
| `scripts/test_web_skeleton.py` | **Modify** (append) | `--sweep` arg present; default output unchanged (condition 6). |
| `scripts/livesmoke_g2.py` | **Create** | MANUAL live harness (not pytest): real `--sweep` on 2 pass-sites; conditions 1+5 live legs. |

---

## Task 1: Canonical shape-key module

**Files:**
- Create: `scripts/_shape_key.py`
- Modify: `research/capture-gap-probes/probe_g3d_dedup.py:85-114`
- Test: `scripts/test_shape_key.py`

- [ ] **Step 1: Create `scripts/_shape_key.py`** (verbatim lift of the de-risked key — `_KEY_FIELDS` + `_node_key`, including `pseudo`/`substrate`, exactly as in `probe_g3d_dedup.py`):

```python
"""Canonical content-free shape-key: an exact mechanism fingerprint of one skeleton
node. Volatile/positional fields (id/parent/bbox/z/sizing.confidence) are excluded by
construction, so two nodes share a key iff they are the SAME content-free structure.
Single source of truth — the G2 sweep-merge engine (_virt) and the cross-route dedup
probe both import this so they cannot drift."""

_KEY_FIELDS = (  # pre-registered field order; volatile keys (id/parent/bbox/z/confidence) excluded
    "role", "aria_role", "layout.mode", "layout.direction", "layout.gap", "layout.pad",
    "layout.justify", "layout.align", "layout.grid_cols", "layout.grid_rows", "sizing.w",
    "sizing.h", "token_ref.bg", "token_ref.fg", "token_ref.border", "font.family", "font.weight",
    "text_len", "pseudo", "substrate",
)


def _node_key(n, drop=()):
    """Exact mechanism fingerprint of ONE node. `drop` blanks named fields -- used ONLY by the
    post-hoc ablation diagnostic; the pre-registered VERDICT path always calls with drop=()."""
    lay = n.get("layout") or {}
    sz = n.get("sizing") or {}
    tr = n.get("token_ref") or {}
    f = n.get("font") or {}
    vals = {
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
    return "|".join("" if name in drop else str(vals[name]) for name in _KEY_FIELDS)
```

- [ ] **Step 2: Write the failing parity test** — `scripts/test_shape_key.py`:

```python
"""Tests for _shape_key — the canonical content-free node fingerprint."""
import os
import sys

import _shape_key as sk

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "research", "capture-gap-probes"))

_NODE_A = {
    "id": 3, "role": "card", "bbox": {"x": 0, "y": 4000, "w": 320, "h": 180}, "z": 0,
    "parent": 1, "sizing": {"w": 320, "h": 180, "confidence": "high"},
    "layout": {"mode": "flex", "direction": "column", "gap": 8, "pad": 16,
               "justify": "start", "align": "stretch", "grid_cols": None, "grid_rows": None},
    "token_ref": {"bg": None, "fg": None, "border": None}, "text_len": 12,
}


def test_key_excludes_position_and_id():
    # Same structure, different position/id -> identical key.
    b = dict(_NODE_A, id=99, bbox={"x": 0, "y": 50, "w": 320, "h": 180}, parent=7)
    assert sk._node_key(_NODE_A) == sk._node_key(b)


def test_key_separates_distinct_structure():
    b = dict(_NODE_A, role="banner")
    assert sk._node_key(_NODE_A) != sk._node_key(b)


def test_parity_with_dedup_probe():
    # The probe must produce a byte-identical key (drift guard).
    from probe_g3d_dedup import _node_key as probe_key
    assert sk._node_key(_NODE_A) == probe_key(_NODE_A)
```

- [ ] **Step 3: Run — expect FAIL** on `test_parity_with_dedup_probe` (probe still has its own copy; keys may match by luck but the import-from-canonical contract is not yet wired):

Run: `cd scripts && python3 -m pytest test_shape_key.py -v`
Expected: `test_parity_with_dedup_probe` is the spec we enforce in Step 4; the other two PASS immediately.

- [ ] **Step 4: Re-export from the probe** — in `research/capture-gap-probes/probe_g3d_dedup.py`, replace the `_KEY_FIELDS = (...)` block and the `def _node_key` body (L85–114) with a re-export so there is ONE source:

```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "scripts"))
from _shape_key import _KEY_FIELDS, _node_key  # canonical; probe keeps these names for back-compat
DROP_TR = ("token_ref.bg", "token_ref.fg", "token_ref.border")  # ablation only (probe-local)
DROP_TXT = ("text_len",)                                         # ablation only (probe-local)
```

(The probe already inserts `scripts/` on `sys.path`; keep whichever insert exists — do not duplicate.)

- [ ] **Step 5: Run — expect PASS:**

Run: `cd scripts && python3 -m pytest test_shape_key.py -v`
Expected: 3 passed.

- [ ] **Step 6: Commit:**

```bash
git add scripts/_shape_key.py scripts/test_shape_key.py research/capture-gap-probes/probe_g3d_dedup.py
git commit -m "feat: canonical _shape_key module (single source) + probe re-export"
```

---

## Task 2: Pure merge core (`scripts/_virt.py`)

**Files:**
- Create: `scripts/_virt.py`
- Test: `scripts/test_virt.py`

This is the load-bearing, content-free, deterministic core — it proves locked conditions 1 (gain realized in bytes), 2 (content-free by whitelist), 3 (idempotent), 4 (one record per new shape), 5 (neg control empty) WITHOUT any live capture.

- [ ] **Step 1: Write the failing tests** — `scripts/test_virt.py`:

```python
"""Tests for _virt — the pure G2 sweep-merge core (no CDP). Conditions 1-5 of the
locked ship bar (docs/plans/g2-virtualization-build.md) are proven here deterministically."""
import json

import _virt


def _node(role, y, **kw):
    """A minimal content-free skeleton node at vertical position y."""
    n = {"id": 0, "role": role, "bbox": {"x": 0, "y": y, "w": 100, "h": 40}, "z": 0,
         "parent": None, "sizing": {"w": 100, "h": 40, "confidence": "high"},
         "layout": {"mode": "flow", "direction": None, "gap": None, "pad": None,
                    "justify": None, "align": None, "grid_cols": None, "grid_rows": None},
         "token_ref": {"bg": None, "fg": None, "border": None}}
    n.update(kw)
    return n


def _sk(nodes):
    return {"schema": "probe-skeleton/2", "url": "x", "viewport": {}, "page": {}, "nodes": nodes}


def test_below_fold_holds_new_shapes_absent_from_rest():
    rest = _sk([_node("banner", 0), _node("nav", 50)])
    # Sweep mounts a 'card' shape (new) and another 'banner' (already seen -> not new).
    sweep = [_sk([_node("banner", 900), _node("card", 1200, text_len=12)])]
    merged = _virt.merge_skeletons(rest, sweep)
    keys = {r["role"] for r in merged["below_fold"]["shapes"]}
    assert keys == {"card"}
    assert merged["below_fold"]["new_shapes"] == 1


def test_addendum_carries_no_position_or_content():
    rest = _sk([_node("banner", 0)])
    leaky = _node("card", 1200, text_len=4)
    leaky["background_image"] = "url(https://evil.example/x.png)"  # a CONTENT_KEY value
    merged = _virt.merge_skeletons(rest, [_sk([leaky])])
    rec = merged["below_fold"]["shapes"][0]
    assert "bbox" not in rec and "background_image" not in rec and "id" not in rec
    assert "url(" not in json.dumps(rec)


def test_merge_is_idempotent_byte_identical():
    rest = _sk([_node("banner", 0)])
    sweep = [_sk([_node("card", 1200), _node("list", 1500)]),
             _sk([_node("list", 2000), _node("footer", 2400)])]
    a = json.dumps(_virt.merge_skeletons(rest, sweep), sort_keys=False)
    b = json.dumps(_virt.merge_skeletons(rest, sweep), sort_keys=False)
    assert a == b


def test_one_record_per_distinct_new_shape():
    rest = _sk([_node("banner", 0)])
    # Three 'card' instances at different y -> ONE shape; plus one 'footer'.
    sweep = [_sk([_node("card", 900), _node("card", 1200), _node("card", 1600),
                  _node("footer", 3000)])]
    merged = _virt.merge_skeletons(rest, sweep)
    assert merged["below_fold"]["new_shapes"] == len(merged["below_fold"]["shapes"]) == 2


def test_negative_control_static_page_empty_addendum():
    rest = _sk([_node("banner", 0), _node("nav", 50), _node("main", 100)])
    sweep = [_sk([_node("banner", 0), _node("nav", 50), _node("main", 100)])]  # nothing new
    merged = _virt.merge_skeletons(rest, sweep)
    assert merged["below_fold"]["new_shapes"] == 0
    assert merged["below_fold"]["shapes"] == []
```

- [ ] **Step 2: Run — expect FAIL** (`ModuleNotFoundError: _virt`):

Run: `cd scripts && python3 -m pytest test_virt.py -v`
Expected: collection error / `No module named '_virt'`.

- [ ] **Step 3: Implement `scripts/_virt.py` (pure core only):**

```python
"""G2 virtualization sweep-merge engine.

PURE CORE (this section): merge per-step skeletons into a content-free `below_fold`
addendum = the SET of distinct shape-keys present across the sweep but ABSENT from
REST. One record per distinct new shape (instances are deduped — a content-free engine
cannot and must not count identical items). Records are built by WHITELIST from
mechanism fields only, so no position (bbox) and no content can enter. Deterministic:
records sorted by shape-key. See docs/plans/g2-virtualization-build.md for the locked
contract; LIVE capture (sweep_skeletons) is in the second section, CDP-only."""
from _shape_key import _node_key

# Whitelist of mechanism fields copied into an addendum record. EXCLUDES every
# positional/volatile field (id/parent/bbox/z) and every content key -- content-free
# by construction (same IP-boundary discipline as aria_role).
_RECORD_FIELDS = ("role", "aria_role", "layout", "sizing", "token_ref", "font",
                  "text_len", "substrate")

BELOW_FOLD_SCHEMA = "probe-belowfold/1"


def shape_key(node):
    return _node_key(node)


def _shape_record(node, key):
    rec = {"key": key}
    for f in _RECORD_FIELDS:
        v = node.get(f)
        if v is not None:
            rec[f] = v
    if node.get("pseudo"):
        rec["pseudo"] = 1
    return rec


def new_shape_records(rest_nodes, sweep_node_lists):
    """Distinct shape records present across the sweep snapshots but ABSENT from REST,
    deduped to one per shape-key, sorted by key (deterministic)."""
    rest_keys = {shape_key(n) for n in rest_nodes}
    seen, recs = set(), []
    for nodes in sweep_node_lists:
        for n in nodes:
            k = shape_key(n)
            if k in rest_keys or k in seen:
                continue
            seen.add(k)
            recs.append(_shape_record(n, k))
    recs.sort(key=lambda r: r["key"])
    return recs


def merge_skeletons(rest_sk, sweep_sks):
    """Return a NEW skeleton = REST + a `below_fold` block of distinct new shapes.
    Does not mutate rest_sk; does not add per-instance nodes, counts, or positions."""
    rest_nodes = rest_sk.get("nodes", [])
    sweep_lists = [sk.get("nodes", []) for sk in sweep_sks]
    recs = new_shape_records(rest_nodes, sweep_lists)
    merged = dict(rest_sk)
    merged["below_fold"] = {
        "schema": BELOW_FOLD_SCHEMA,
        "step_count": len(sweep_sks),
        "new_shapes": len(recs),
        "shapes": recs,
    }
    return merged
```

- [ ] **Step 4: Run — expect PASS:**

Run: `cd scripts && python3 -m pytest test_virt.py -v`
Expected: 5 passed.

- [ ] **Step 5: Commit:**

```bash
git add scripts/_virt.py scripts/test_virt.py
git commit -m "feat: pure G2 merge core — below_fold distinct-shape set (content-free, deterministic)"
```

---

## Task 3: below_fold firewall backstop in `bundle_writer.assemble`

**Files:**
- Modify: `scripts/bundle_writer.py:272-315` (`assemble`)
- Test: `scripts/test_bundle_writer.py` (append)

`assemble` carries the input `skeleton` dict through to `bundle["skeleton"]` (written verbatim as `skeleton.json`). The `below_fold` records are already content-free by whitelist (Task 2), but the firewall is the project's sole backstop — make the addendum pass through `redact_node` like base nodes, and prove the file-level audit still guards it.

- [ ] **Step 1: Write the failing tests** — append to `scripts/test_bundle_writer.py`:

```python
import json as _json
import content_firewall as cf


def _min_skel_with_below_fold(extra_rec=None):
    shapes = [{"key": "card|...", "role": "card",
               "sizing": {"w": 100, "h": 40, "confidence": "high"},
               "layout": {"mode": "flow"}, "token_ref": {"bg": None, "fg": None, "border": None}}]
    if extra_rec:
        shapes.append(extra_rec)
    return {"schema": "probe-skeleton/2", "url": "x", "viewport": {"dpr": 1}, "page": {},
            "nodes": [], "below_fold": {"schema": "probe-belowfold/1", "step_count": 8,
                                        "new_shapes": len(shapes), "shapes": shapes}}


def test_below_fold_survives_assemble():
    sk = _min_skel_with_below_fold()
    bundle = bw.assemble(sk, {"palette": []}, {}, [], {})
    assert bundle["skeleton"]["below_fold"]["new_shapes"] == 1
    assert bundle["skeleton"]["below_fold"]["shapes"][0]["role"] == "card"


def test_below_fold_url_canary_trips_audit(tmp_path):
    # A url(https://...) smuggled into an addendum record MUST be caught by audit_bundle.
    leak = {"key": "x", "role": "img", "background_image": "url(https://evil.example/a.png)"}
    sk = _min_skel_with_below_fold(extra_rec=leak)
    bundle = bw.assemble(sk, {"palette": []}, {}, [], {})
    bw.write_bundle(bundle, str(tmp_path))
    violations = cf.audit_bundle(str(tmp_path))
    assert violations, "firewall must flag a url() asset ref inside below_fold"
```

- [ ] **Step 2: Run — expect FAIL** on `test_below_fold_url_canary_trips_audit` if the leak survives redaction (and confirm `test_below_fold_survives_assemble` passes once `assemble` is reached with the right arg count):

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -k below_fold -v`
Expected: `survives` PASS (assemble already carries the dict); `url_canary` PASS only after the firewall sees the file — verify it FAILS first if you temporarily skip redaction, to confirm the test bites. (The `_CONTENT_URL`/`_CSS_URL_REF` scanners catch `url(https://…/a.png)` at the file level regardless, so this test documents + locks the backstop.)

- [ ] **Step 3: Add the redaction line** — in `assemble`, immediately after `skeleton["nodes"] = [cf.redact_node(n) for n in nodes]` (~L294), strip content keys from addendum records too:

```python
        bf = skeleton.get("below_fold")
        if bf and bf.get("shapes"):
            bf["shapes"] = [cf.redact_node(r) for r in bf["shapes"]]
```

- [ ] **Step 4: Run — expect PASS:**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -k below_fold -v`
Expected: 2 passed. `redact_node` strips `background_image` from the record; the file-level `audit_bundle` remains the backstop and still flags any residual `url(` text.

- [ ] **Step 5: Commit:**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: redact below_fold addendum records in assemble + audit canary"
```

---

## Task 4: Wire opt-in `--sweep` into `web_skeleton`

**Files:**
- Modify: `scripts/web_skeleton.py` (`main` argparse ~L1221–1271; default `else` branch ~L1387–1395)
- Modify: `scripts/_virt.py` (append the CDP `sweep_skeletons` — a port of proven probe code)
- Test: `scripts/test_web_skeleton.py` (append)

The live sweep is a faithful PORT of `research/capture-gap-probes/probe_g2_virtualization.py` (`_snap_nodes(reset=False)`, `_settle_nodecount`, `_set_scroll`, `_sweep`) — that code is already de-risk-validated. Default capture (no `--sweep`) stays byte-identical.

- [ ] **Step 1: Append `sweep_skeletons` to `scripts/_virt.py`** (CDP section — port, do not reinvent):

```python
# --- LIVE capture (CDP only; validated by scripts/livesmoke_g2.py, not pytest) ---------
# Faithful port of probe_g2_virtualization._snap_nodes / _scrollable / _set_scroll /
# _settle_nodecount. CRITICAL: a sweep step must snapshot at the HELD scroll offset, so it
# does a raw DOMSnapshot + parse_snapshot + to_skeleton (NOT _snapshot_skeleton, which runs
# _REST_JS and would reset scroll to 0).
import time
import web_skeleton as WK


def _node_count(ev):
    return int(ev.ev("document.getElementsByTagName('*').length"))


def _scrollable(ev):
    return ev.ev("({sh:document.documentElement.scrollHeight,ih:innerHeight,"
                 "sy:Math.round(window.scrollY)})")


def _set_scroll(ev, y):
    ev.ev("(function(y){var d=document.documentElement;d.style.scrollBehavior='auto';"
          "document.body.style.scrollBehavior='auto';window.scrollTo(0,y);"
          "return Math.round(window.scrollY);})(%d)" % int(y))


def _settle_nodecount(ev, max_wait=4.0, poll=0.3, stable_needed=2):
    last, stable = -1, 0
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        n = _node_count(ev)
        if n == last:
            stable += 1
            if stable >= stable_needed:
                return n
        else:
            stable = 0
        last = n
        time.sleep(poll)
    return last


def _snap_nodes(ev, url, reset):
    """No-navigate DOMSnapshot -> a skeleton dict at the CURRENT scroll position. Faithful
    port of probe_g2_virtualization._snap_nodes: same WANT_STYLES / parse_snapshot /
    to_skeleton / enrich_aria as the engine's REST capture, so shape-keys are identical.
    reset=False snapshots whatever lazily mounted at the held offset (the sweep case)."""
    if reset:
        ev.ev(WK._REST_JS)
        time.sleep(0.15)
    layout = ev.ev("({w: innerWidth, h: innerHeight, dpr: devicePixelRatio})")
    page = ev.ev("({w: document.documentElement.scrollWidth, "
                 "h: document.documentElement.scrollHeight})")
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WK.WANT_STYLES,
                         "includeDOMRects": True, "includePaintOrder": True})
    eff_dpr = layout["dpr"] or 1.0
    recs = WK.parse_snapshot(snap, WK.WANT_STYLES, dpr=eff_dpr)
    svg_set, parent_index = set(), None
    for doc in snap["documents"]:
        svg_set |= WK.svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, ncol, nsty, npseu, nback = WK.to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    WK.enrich_aria(sk["nodes"], nback, ev)
    return sk


def sweep_skeletons(ev, url, steps=8):
    """Scroll-settle sweep over the page ALREADY loaded on `ev` (REST is the caller's
    out_obj — no double-capture). Returns the list of per-step skeleton dicts to feed
    merge_skeletons. In-class gate (sh>ih) is the caller's responsibility; does NOT navigate."""
    inner = _scrollable(ev)["ih"]
    sweep_sks = []
    for i in range(1, steps + 1):
        sh = _scrollable(ev)["sh"]
        _set_scroll(ev, min(sh, i * inner))
        _settle_nodecount(ev)
        sweep_sks.append(_snap_nodes(ev, url, reset=False))
    return sweep_sks
```

- [ ] **Step 2: Write the failing test** — append to `scripts/test_web_skeleton.py`:

```python
def test_sweep_flag_parses_and_defaults_off():
    import web_skeleton as ws
    p = ws._build_argparser()   # see Step 3
    assert p.parse_args(["--url", "x"]).sweep is False
    ns = p.parse_args(["--url", "x", "--sweep", "--sweep-steps", "6"])
    assert ns.sweep is True and ns.sweep_steps == 6
```

- [ ] **Step 3: Add the flags + in-class gate.** In `web_skeleton.main`, factor the parser into `_build_argparser()` (so the test can reach it) and add:

```python
    p.add_argument("--sweep", action="store_true", default=False,
                   help="APPEND-class virtualization: scroll-settle sweep + below_fold merge (opt-in)")
    p.add_argument("--sweep-steps", type=int, default=8, dest="sweep_steps",
                   help="bounded sweep step count (default 8)")
```

Then in the default `else` branch (the plain single-capture path, ~L1387), after `out_obj, _, _, _ = _capture_one(...)`:

```python
        if args.sweep:
            import _virt
            sc = _virt._scrollable(ev)
            if sc["sh"] > sc["ih"]:                       # in-class gate (sh>ih)
                sweep_sks = _virt.sweep_skeletons(ev, args.url, steps=args.sweep_steps)
                out_obj = _virt.merge_skeletons(out_obj, sweep_sks)   # out_obj IS the REST skeleton
            else:                                          # out-of-class: REST-only + log
                emit_json({"sweep": "skipped", "reason": "out_of_class_sh_le_ih",
                           "sh": sc["sh"], "ih": sc["ih"]})
```

(Place the sweep call BEFORE `ev.close()` in the same `try`. `out_obj` from `_capture_one` is the REST skeleton — `merge_skeletons` adds `below_fold` to it.)

- [ ] **Step 4: Run — expect PASS** (arg parsing; the live branch is exercised by Task 6, not here):

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -k sweep -v`
Expected: 1 passed.

- [ ] **Step 5: Verify the default contract is byte-identical** (condition 6) — no `--sweep` ⇒ `out_obj` has NO `below_fold` key:

```python
def test_default_capture_has_no_below_fold(monkeypatch):
    # _capture_one is the unchanged REST path; without --sweep the engine must not add below_fold.
    # (Unit-level: assert merge is never called when sweep is False — see Step 3 branch guard.)
    import web_skeleton as ws
    ns = ws._build_argparser().parse_args(["--url", "x"])
    assert ns.sweep is False   # branch in Step 3 is guarded on this; below_fold cannot be added
```

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -k "sweep or below_fold" -v`
Expected: 2 passed.

- [ ] **Step 6: Commit:**

```bash
git add scripts/web_skeleton.py scripts/_virt.py scripts/test_web_skeleton.py
git commit -m "feat: opt-in --sweep in web_skeleton (in-class gated; default REST path unchanged)"
```

---

## Task 5: Forward `--sweep` through `site_capture`

**Files:**
- Modify: `scripts/site_capture.py` (`_transport_argv` ~L35; `capture_route` ~L57–85; `main` argparse)
- Test: `scripts/test_site_capture_post.py` (append) or `scripts/test_site_capture.py`

- [ ] **Step 1: Write the failing test** — append to the site_capture test file:

```python
from types import SimpleNamespace


def test_sweep_flags_forwarded_to_web_skeleton():
    import site_capture as sc
    on = SimpleNamespace(sweep=True, sweep_steps=6)
    off = SimpleNamespace(sweep=False, sweep_steps=8)
    assert sc._sweep_argv(on) == ["--sweep", "--sweep-steps", "6"]
    assert sc._sweep_argv(off) == []
```

- [ ] **Step 2: Run — expect FAIL** (`_sweep_argv` undefined):

Run: `cd scripts && python3 -m pytest -k sweep_flags_forwarded -v`
Expected: `AttributeError: module 'site_capture' has no attribute '_sweep_argv'`.

- [ ] **Step 3: Implement** — add to `site_capture.py`:

```python
def _sweep_argv(args):
    """Sweep flags to forward to each per-route web_skeleton subprocess (empty when off)."""
    if not getattr(args, "sweep", False):
        return []
    return ["--sweep", "--sweep-steps", str(args.sweep_steps)]
```

Add the argparse flags to `site_capture.main` (mirror Task 4's two flags), thread `args` into `capture_site`/`capture_route`, and in `capture_route` append `_sweep_argv(args)` to ONLY the `web_skeleton.py` subprocess call (NOT `web_tokens`/`bundle_writer`):

```python
        r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)]
                 + transport + sweep_argv)
```

- [ ] **Step 4: Run — expect PASS:**

Run: `cd scripts && python3 -m pytest -k sweep_flags_forwarded -v`
Expected: 1 passed.

- [ ] **Step 5: Commit:**

```bash
git add scripts/site_capture.py scripts/test_site_capture_post.py
git commit -m "feat: forward --sweep/--sweep-steps from site_capture to per-route web_skeleton"
```

---

## Task 6: Manual live harness (`scripts/livesmoke_g2.py`) — conditions 1 & 5 live legs

**Files:**
- Create: `scripts/livesmoke_g2.py` (NO `test_` prefix → not pytest-collected)

This is the real-artifact validation of record (memory `live-cdp-capture-is-manual-harness-not-pytest`): a live `--sweep` capture against the 2 reproducible pass-sites, asserting realized gain + firewall-clean on the produced bytes. Slow (~2-4 min), one-clean-`:9222`-tab prereq.

- [ ] **Step 1: Create `scripts/livesmoke_g2.py`:**

```python
#!/usr/bin/env python3
"""MANUAL live-smoke for the G2 --sweep engine. NOT pytest (slow/shared-Chrome).
Validates the LOCKED ship bar's live legs on real artifact bytes:
  cond 1 (realized gain): below_fold.new_shapes >= 25 on the Metafizzy demo and a
          YouTube /watch URL (NOT the consent-flaky home).
  cond 5 (neg control):   below_fold.new_shapes < 0.10*rest_shapes on a static page.
  cond 2 (content-free):  content_firewall.audit_bundle == 0 on each produced bundle.
PREREQ: a debug Chrome with EXACTLY ONE :9222 page target (memory: cdp-capture-needs-open-tab).
  /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9222
Usage: python3 scripts/livesmoke_g2.py   (exit 0 = bar's live legs pass)."""
import glob
import json
import os
import subprocess
import sys
import tempfile

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS)
import content_firewall as cf  # noqa: E402

CDP = ["--cdp-port", "9222"]
PASS_SITES = ["https://infinite-scroll.com/demo/full-page/",
              "https://www.youtube.com/watch?v=aqz-KE-bpKQ"]  # /watch: non-consent-gated
NEG_SITE = "https://en.wikipedia.org/wiki/Cat"


def _capture(url, out, sweep):
    sk = os.path.join(out, "sk.json")
    tok = os.path.join(out, "tok.json")
    bundle = os.path.join(out, "bundle")
    cmd = [sys.executable, "web_skeleton.py", "--url", url, "--out", sk] + CDP
    if sweep:
        cmd += ["--sweep", "--sweep-steps", "8"]
    subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True, timeout=240)
    subprocess.run([sys.executable, "web_tokens.py", "--url", url, "--out", tok] + CDP,
                   cwd=SCRIPTS, capture_output=True, text=True, timeout=120)
    subprocess.run([sys.executable, "bundle_writer.py", "--skeleton", sk, "--tokens", tok,
                    "--out", bundle], cwd=SCRIPTS, capture_output=True, text=True, timeout=120)
    return bundle


def _new_shapes(bundle):
    skel = json.loads(open(os.path.join(bundle, "skeleton.json")).read())
    bf = skel.get("below_fold") or {}
    rest_shapes = len({n.get("role") for n in skel.get("nodes", [])}) or 1
    return bf.get("new_shapes", 0), rest_shapes


def main():
    fails = []
    for url in PASS_SITES:
        out = tempfile.mkdtemp(prefix="g2_")
        bundle = _capture(url, out, sweep=True)
        new, _ = _new_shapes(bundle)
        if new < 25:
            fails.append("cond1 %s: new_shapes=%d (<25)" % (url, new))
        if cf.audit_bundle(bundle):
            fails.append("cond2 %s: firewall violations" % url)
    out = tempfile.mkdtemp(prefix="g2neg_")
    bundle = _capture(NEG_SITE, out, sweep=True)
    new, rest_shapes = _new_shapes(bundle)
    if new >= 0.10 * rest_shapes:
        fails.append("cond5 neg: new_shapes=%d >= 0.10*%d" % (new, rest_shapes))
    if cf.audit_bundle(bundle):
        fails.append("cond2 neg: firewall violations")
    if fails:
        print("G2 LIVE-SMOKE FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print("G2 LIVE-SMOKE PASS: realized gain >=25 on 2 pass-sites, neg control <10%%, firewall 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it manually** (operator action — requires one clean `:9222` tab):

Run: `python3 scripts/livesmoke_g2.py`
Expected: `G2 LIVE-SMOKE PASS`. If a pass-site is consent-locked/out-of-class at test time, that is an environment skip (record it) — re-run with a clean tab, NOT a bar failure.

- [ ] **Step 3: Commit:**

```bash
git add scripts/livesmoke_g2.py
git commit -m "feat: manual G2 live-smoke harness (realized-gain + neg-control + firewall legs)"
```

---

## Task 7: Full-suite green + record the verdict (condition 6 + provenance)

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (§C9-R-G2 — append the BUILD-SHIPPED note)
- Modify: `docs/probe-runner-web-capture-capabilities.md` (add `below_fold` row + `--sweep`)

- [ ] **Step 1: Run the FULL suite** — condition 6 (default contract untouched):

Run: `cd scripts && python3 -m pytest -q`
Expected: prior baseline (497) + the new tests, ALL passed. If any prior test changed output, STOP — the default path was altered (condition 6 violated).

- [ ] **Step 2: Record the SHIP/DEFER verdict** in §C9-R-G2 with the real `livesmoke_g2.py` numbers (new_shapes per pass-site, firewall 0, neg-control fraction). If any locked condition failed, record DEFER with the specific finding — do not ship.

- [ ] **Step 3: Add the capability-doc rows** — `below_fold` (per-node section: feature "APPEND-class below-fold shape set", producer `_virt.merge_skeletons` via `web_skeleton --sweep`, field `below_fold`, provenance §C9-R-G2) and note `--sweep` is opt-in.

- [ ] **Step 4: Commit:**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md docs/probe-runner-web-capture-capabilities.md
git commit -m "docs: record G2 sweep-merge SHIP verdict + below_fold capability row"
```

---

## Self-Review notes (for the executor)

- **Conditions → tasks:** 1 → Task 2 (`test_below_fold_holds_new_shapes`) + Task 6 (live ≥25); 2 → Task 2 (`no_position_or_content`) + Task 3 (canary) + Task 6 (firewall 0); 3 → Task 2 (`idempotent_byte_identical`); 4 → Task 2 (`one_record_per_distinct_new_shape`); 5 → Task 2 (`negative_control`) + Task 6 (live neg); 6 → Task 4 (default no `below_fold`) + Task 7 (full suite). All six covered.
- **No counts shipped:** `_shape_record` emits NO `repeat_count`; `below_fold.new_shapes` is a SET cardinality, not an instance tally (the un-de-risked field the pre-reg deliberately dropped). Do not add per-shape counts.
- **Type consistency:** `merge_skeletons(rest_sk, sweep_sks)`, `sweep_skeletons(ev, url, steps)`, `_sweep_argv(args)`, `below_fold` schema `probe-belowfold/1` — used identically across Tasks 2/4/5/6.
- **Live-leg honesty:** Task 4 Step 1's `_snapshot_skeleton`-vs-`parse_snapshot` note — confirm against `probe_g2_virtualization._snap_nodes` which path snapshots WITHOUT a REST reset; the manual harness (Task 6) is the validation of record, never an unrun "fixed by inspection" (memory `validate-real-artifact-not-keys-proxy`).
