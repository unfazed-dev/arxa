# Nav-link → route_id annotation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a content-free `nav_edges` topology in `site.json` that resolves each captured route's in-page anchors to other captured routes' `route_id`s, keyed to the stable skeleton node id — turning the deduped G3d nav into a navigable structure.

**Architecture:** A new pure module `_nav.py` (normalize / resolve / chrome-classify) plus four small wiring changes: `web_skeleton.parse_snapshot` extracts each anchor's `href` (stored under the firewall `CONTENT_KEY` `href`, so existing redaction strips it from the shipped skeleton), `site_capture.capture_route` resolves anchors in-process against an upfront route_map and returns content-free edges, `site_capture.capture_site` aggregates, and `_site.build_site_manifest` writes `nav_edges`. Hrefs live only in the pre-redaction `_sk.json` scratch (outside the firewall-audited tree).

**Tech Stack:** Python 3.13, pytest, existing `scripts/web_skeleton.py` / `site_capture.py` / `_site.py` / `content_firewall.py` / `bundle_writer.py`, Chrome DevTools Protocol (live smoke only).

**Spec:** `docs/plans/nav-link-route-annotation-design.md`. **De-risk evidence:** `§C9-R-NG` in `docs/plans/probe-runner-engine-capture-gaps.md`.

**Test command (pure tasks):** `python3 -m pytest tests/test_nav.py -v` (and the noted existing suites).

---

## File Structure

- **Create** `scripts/_nav.py` — pure: `normalize_url`, `build_route_map`, `classify_chrome`, `resolve_edges`. No browser, no I/O.
- **Create** `tests/test_nav.py` — pure unit tests for `_nav` (no browser).
- **Modify** `scripts/web_skeleton.py` — `parse_snapshot` extracts anchor `href` from `nodes.attributes`.
- **Modify** `scripts/site_capture.py` — `capture_route` resolves anchors → edges; `capture_site` builds route_map + aggregates.
- **Modify** `scripts/_site.py` — `build_site_manifest` adds `nav_edges`.
- **Modify** `tests/` (existing site_capture / firewall tests) — integration + canary.
- **Modify** `research/capture-gap-probes/README.md` or the doc — live-smoke instructions; record build verdict in gaps doc.

CONVENTION: the chrome landmark set is `web_skeleton.LANDMARK_ROLES`-derived `CHROME_LANDMARKS = {"banner","navigation","contentinfo","complementary"}` (mirror the constant used in G3d / `probe_g3c_richness_gated`).

---

### Task 1: `_nav.normalize_url`

**Files:**
- Create: `scripts/_nav.py`
- Create: `tests/test_nav.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/test_nav.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import _nav


def test_normalize_url_canonicalizes_host_path_and_drops_query_fragment():
    assert _nav.normalize_url("https://www.Example.com/About/") == "example.com/about"
    assert _nav.normalize_url("http://example.com/about") == "example.com/about"
    assert _nav.normalize_url("https://example.com/") == "example.com/"
    assert _nav.normalize_url("https://example.com/x/?q=1#frag") == "example.com/x"
    assert _nav.normalize_url("mailto:a@b.com") is None
    assert _nav.normalize_url("javascript:void(0)") is None
    assert _nav.normalize_url("") is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_nav.py::test_normalize_url_canonicalizes_host_path_and_drops_query_fragment -v`
Expected: FAIL — `ModuleNotFoundError: No module named '_nav'` (or `AttributeError`).

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_nav.py
"""Pure content-free nav-edge resolution for the site-level capture (nav-link -> route_id
annotation). Resolves in-process; NEVER emits an href. Spec: docs/plans/nav-link-route-annotation-design.md."""
from urllib.parse import urlparse

CHROME_LANDMARKS = {"banner", "navigation", "contentinfo", "complementary"}


def normalize_url(u):
    """Canonical key for intra-set matching: scheme must be http(s) (else None); host
    lowercased with a leading 'www.' stripped; path lowercased with one trailing slash
    removed (root stays '/'); query + fragment dropped. Lowercasing the path is a
    deliberate, documented match-tolerance (most route paths are case-insensitive in
    practice); it can only MERGE links, never invent edges."""
    if not u:
        return None
    try:
        p = urlparse(u)
    except ValueError:
        return None
    if p.scheme not in ("http", "https"):
        return None
    host = p.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    path = (p.path or "/").lower()
    if path != "/":
        path = path.rstrip("/") or "/"
    return host + path
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_nav.py -v`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add scripts/_nav.py tests/test_nav.py
git commit -m "feat: _nav.normalize_url (content-free intra-set URL key)"
```

---

### Task 2: `_nav.build_route_map` + `_nav.resolve_edges`

**Files:**
- Modify: `scripts/_nav.py`
- Modify: `tests/test_nav.py`

- [ ] **Step 1: Write the failing test**

```python
def test_build_route_map_first_wins():
    urls = ["https://x.com/", "https://x.com/a/", "https://www.x.com/a"]  # last collides with [1]
    rm = _nav.build_route_map(urls)
    assert rm == {"x.com/": 0, "x.com/a": 1}


def test_resolve_edges_keeps_other_route_drops_self_external_unresolved():
    rm = {"x.com/": 0, "x.com/a": 1, "x.com/b": 2}
    anchors = [
        {"node": 10, "href": "https://x.com/a", "chrome": True},    # -> route 1 (other)
        {"node": 11, "href": "https://x.com/",  "chrome": True},    # -> route 0 == src -> self, drop
        {"node": 12, "href": "https://other.com/z", "chrome": False},  # external, drop
        {"node": 13, "href": "mailto:a@b.com", "chrome": False},    # non-http, drop
        {"node": 14, "href": "https://x.com/b", "chrome": False},   # -> route 2 (content edge)
    ]
    edges = _nav.resolve_edges(anchors, rm, src_id=0)
    assert edges == [
        {"src": 0, "dst": 1, "src_node": 10, "chrome": True},
        {"src": 0, "dst": 2, "src_node": 14, "chrome": False},
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_nav.py -k "route_map or resolve_edges" -v`
Expected: FAIL — `AttributeError: module '_nav' has no attribute 'build_route_map'`.

- [ ] **Step 3: Write minimal implementation** (append to `scripts/_nav.py`)

```python
def build_route_map(urls):
    """{normalized_url: route_id}. route_id = index in `urls`; first occurrence wins on collision."""
    rm = {}
    for rid, u in enumerate(urls):
        n = normalize_url(u)
        if n is not None and n not in rm:
            rm[n] = rid
    return rm


def resolve_edges(anchors, route_map, src_id):
    """One content-free edge per anchor whose normalized href maps to a route != src_id.
    Drops self-links, external/unresolved, and non-http. Never returns an href.
    anchors: [{"node": <skeleton id>, "href": <str>, "chrome": <bool>}]."""
    edges = []
    for a in anchors:
        n = normalize_url(a.get("href"))
        if n is None:
            continue
        dst = route_map.get(n)
        if dst is None or dst == src_id:
            continue
        edges.append({"src": src_id, "dst": dst, "src_node": a["node"], "chrome": bool(a.get("chrome"))})
    return edges
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_nav.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_nav.py tests/test_nav.py
git commit -m "feat: _nav route-map + resolve_edges (per-route content-free topology)"
```

---

### Task 3: `_nav.classify_chrome` (anchor → nearest aria_role landmark ∈ CHROME_LANDMARKS)

**Files:**
- Modify: `scripts/_nav.py`
- Modify: `tests/test_nav.py`

- [ ] **Step 1: Write the failing test**

```python
def _sk(nodes):
    # nodes: list of {"id","parent","aria_role"}; returns by_id + by helper
    return {n["id"]: n for n in nodes}


def test_classify_chrome_true_under_navigation_false_under_main():
    nodes = [
        {"id": 0, "parent": None, "aria_role": None},
        {"id": 1, "parent": 0, "aria_role": "navigation"},
        {"id": 2, "parent": 1, "aria_role": None},        # anchor under navigation -> chrome
        {"id": 3, "parent": 0, "aria_role": "main"},
        {"id": 4, "parent": 3, "aria_role": None},        # anchor under main -> not chrome
    ]
    by_id = _sk(nodes)
    assert _nav.classify_chrome(2, by_id) is True
    assert _nav.classify_chrome(4, by_id) is False
    # a banner ancestor higher up also counts (nearest landmark wins; here only one on the path)
    assert _nav.classify_chrome(0, by_id) is False       # root, no landmark ancestor
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_nav.py -k classify_chrome -v`
Expected: FAIL — no `classify_chrome`.

- [ ] **Step 3: Write minimal implementation** (append to `scripts/_nav.py`)

```python
def classify_chrome(node_id, by_id):
    """True iff the node's NEAREST landmark ancestor (incl. itself) has aria_role in
    CHROME_LANDMARKS. Walks parent links in `by_id` (a {id: {parent, aria_role, ...}} map).
    A non-landmark anchor inherits the region of its closest landmark; no landmark on the
    path -> not chrome (treated as content/main)."""
    seen = set()
    cur = node_id
    while cur is not None and cur in by_id and cur not in seen:
        seen.add(cur)
        ar = by_id[cur].get("aria_role")
        if ar in CHROME_LANDMARKS:
            return True
        if ar is not None:          # a non-chrome landmark (main/region/...) -> nearest wins, stop
            return False
        cur = by_id[cur].get("parent")
    return False
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_nav.py -v`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_nav.py tests/test_nav.py
git commit -m "feat: _nav.classify_chrome (nearest aria_role landmark in CHROME_LANDMARKS)"
```

---

### Task 4: `web_skeleton` extracts anchor `href` in `parse_snapshot`

**Files:**
- Modify: `scripts/web_skeleton.py` (`parse_snapshot`, ~line 270-329)
- Test: `tests/test_web_skeleton_anchor_href.py` (create)

The verified DOMSnapshot shape: `documents[0].nodes.attributes` is a per-node list of alternating `[nameStrIdx, valueStrIdx, ...]`; `nodes.nodeName` gives the tag; `layout.nodeIndex` (`li_node`) maps each layout row to its node index `dom_i`. We extract `href` for `<a>` layout nodes and store it under the record key `href` — already a firewall `CONTENT_KEY`, so `redact_node` strips it from the shipped `skeleton.json` (default contract unchanged).

- [ ] **Step 1: Write the failing test** (synthetic DOMSnapshot fixture, no browser)

```python
# tests/test_web_skeleton_anchor_href.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import web_skeleton as WK


def _snap():
    # strings table; one <a href="https://t/x"> and one <div>
    strings = ["A", "DIV", "href", "https://t/x", "class", "nav"]
    nodes = {
        "nodeName": [0, 1],                 # node0=A, node1=DIV
        "attributes": [[2, 3, 4, 5], []],   # node0: href=https://t/x, class=nav ; node1: none
        "backendNodeId": [100, 101],
    }
    layout = {
        "nodeIndex": [0, 1],                # both rendered
        "bounds": [[0, 0, 10, 10], [0, 10, 10, 10]],
        "styles": [[], []],
        "text": [],
    }
    return {"strings": strings, "documents": [{"nodes": nodes, "layout": layout}]}


def test_parse_snapshot_extracts_anchor_href_only_for_anchors():
    recs = WK.parse_snapshot(_snap(), [], dpr=1.0)
    a = next(r for r in recs if r["tag"] == "A")
    d = next(r for r in recs if r["tag"] == "DIV")
    assert a["href"] == "https://t/x"
    assert d.get("href") is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_web_skeleton_anchor_href.py -v`
Expected: FAIL — `KeyError: 'href'` (or `a["href"]` missing).

- [ ] **Step 3: Write minimal implementation**

In `scripts/web_skeleton.py`, inside `parse_snapshot`, after the line `backend = nodes.get("backendNodeId") or []` add an attribute-index reader:

```python
        attributes = nodes.get("attributes") or []

        def _href_of(node_idx):
            row = attributes[node_idx] if node_idx < len(attributes) else []
            for k in range(0, len(row) - 1, 2):
                if s(row[k]) == "href":
                    return s(row[k + 1])
            return None
```

Then in the per-node dict appended to `out`, add the `href` key (only meaningful for `<a>`; harmless None elsewhere):

```python
                "href": _href_of(dom_i) if tag == "A" else None,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_web_skeleton_anchor_href.py -v`
Expected: PASS.

- [ ] **Step 4b: Propagate `href` through `to_skeleton` (REQUIRED — `parse_snapshot` alone is insufficient)**

`to_skeleton` (`scripts/web_skeleton.py:537`) builds each final node from a WHITELIST dict literal (it does NOT pass arbitrary rec fields through), so the `href` from Step 3 is dropped unless added here. The final node carries `role` (an `<a>` classifies to `"link"` or, for wrapped media/text, `image`/`text`) — there is NO `tag` field downstream, which is why anchors are later identified by **href presence**, not tag. After the node dict is built (right after the `node = {...}` literal, near line 576, before the `if r.get("substrate")` block), add:

```python
        if r.get("href"):
            node["href"] = r["href"]      # CONTENT_KEY -> redact_node strips it from the shipped skeleton; survives in raw _sk.json for in-process resolution
```

This keeps `href` only on emitted nodes that actually had one. `redact_node` (a top-level CONTENT_KEYS filter) removes it on ship; the raw `_sk.json` (scratch, outside the audited tree) retains it for `site_capture` resolution.

- [ ] **Step 5: Verify the shipped skeleton stays href-free (redaction strips it)**

Run: `python3 -m pytest tests/ -k "firewall or redact or skeleton" -q`
Expected: existing suite still green (no `href` survives into a redacted bundle because `href` is a `CONTENT_KEY`). If any test asserts the exact key-set of a redacted node and now fails, that is the redaction proving it strips `href` — update that assertion only if it explicitly enumerates pre-redaction keys.

- [ ] **Step 6: Commit**

```bash
git add scripts/web_skeleton.py tests/test_web_skeleton_anchor_href.py
git commit -m "feat: web_skeleton parse_snapshot extracts anchor href (pre-redaction; CONTENT_KEY, stripped on ship)"
```

---

### Task 5: Verify redaction preserves node ids (`_sk.json` id == shipped `skeleton.json` id)

**Files:**
- Test: `tests/test_redact_preserves_ids.py` (create)

`src_node` references the SHIPPED skeleton id; the resolver reads ids from the pre-redaction `_sk.json`. This task proves redaction strips content per node WITHOUT re-indexing, so the two id spaces coincide. If it fails, STOP and report (the spec's join key assumption is broken).

- [ ] **Step 1: Write the failing/guard test** (uses the real redaction entrypoint)

```python
# tests/test_redact_preserves_ids.py
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import content_firewall as cf


def test_redact_node_preserves_id_and_parent_drops_href():
    node = {"id": 7, "parent": 3, "tag": "A", "href": "https://t/x", "text": "hello",
            "aria_role": "navigation", "bbox": {"x": 0, "y": 0, "w": 1, "h": 1}}
    red = cf.redact_node(dict(node))   # the real per-node redactor used by bundle_writer
    assert red["id"] == 7 and red["parent"] == 3
    assert "href" not in red and red.get("text") in (None, "")
```

- [ ] **Step 2: Run test to verify behavior**

Run: `python3 -m pytest tests/test_redact_preserves_ids.py -v`
Expected: PASS. CONFIRMED FACT (verified against the codebase): `content_firewall.redact_node(node)` (`content_firewall.py:41`) returns `{k: v for k, v in node.items() if k not in CONTENT_KEYS}` — it filters ONLY top-level CONTENT_KEYS (`text`/`src`/`href`/`url`/…), so `id`/`parent`/`aria_role` pass through unchanged and `href` is dropped. The test asserts exactly that. This is a guard test (proves the join-key assumption), not a behavior change.

- [ ] **Step 3: (no code change expected)** — `href` is already in `content_firewall.CONTENT_KEYS` and `redact_node` strips it; ids are preserved. If this test somehow fails, STOP and report — the spec's `src_node` join-key assumption is broken and the design must be revisited before continuing.

- [ ] **Step 4: Commit**

```bash
git add tests/test_redact_preserves_ids.py
git commit -m "test: redaction preserves node ids + strips anchor href (src_node join-key guard)"
```

---

### Task 6: `site_capture` — resolve per route, aggregate

**Files:**
- Modify: `scripts/site_capture.py` (`capture_route`, `capture_site`)
- Test: `tests/test_site_capture_nav.py` (create — logic test with synthetic `_sk.json`, no browser)

- [ ] **Step 1: Write the failing test** — extract the resolution step into a pure, testable helper and test it

```python
# tests/test_site_capture_nav.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import site_capture as SC


def test_edges_from_skeleton_resolves_chrome_and_content():
    # raw _sk.json node-list (REAL post-to_skeleton/enrich_aria shape: `role` + `aria_role` +
    # `parent` + `href`; NO `tag`). Anchors are identified by HREF PRESENCE, not tag/role.
    sk_nodes = [
        {"id": 0, "parent": None, "role": "unknown_box", "aria_role": None},
        {"id": 1, "parent": 0, "role": "unknown_box", "aria_role": "navigation"},
        {"id": 2, "parent": 1, "role": "link", "aria_role": None, "href": "https://x.com/a"},  # chrome -> route1
        {"id": 3, "parent": 0, "role": "unknown_box", "aria_role": "main"},
        {"id": 4, "parent": 3, "role": "link", "aria_role": None, "href": "https://x.com/b"},   # content -> route2
        {"id": 5, "parent": 3, "role": "link", "aria_role": None, "href": "https://x.com/"},    # self -> drop
    ]
    route_map = {"x.com/": 0, "x.com/a": 1, "x.com/b": 2}
    edges = SC._edges_from_skeleton(sk_nodes, route_map, src_id=0)
    assert edges == [
        {"src": 0, "dst": 1, "src_node": 2, "chrome": True},
        {"src": 0, "dst": 2, "src_node": 4, "chrome": False},
    ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_site_capture_nav.py -v`
Expected: FAIL — `AttributeError: module 'site_capture' has no attribute '_edges_from_skeleton'`.

- [ ] **Step 3: Add the helper + wire it in** to `scripts/site_capture.py`

Add the import near the top (with the other `_site`/scripts imports):

```python
import _nav
```

Add the pure helper:

```python
def _edges_from_skeleton(sk_nodes, route_map, src_id):
    """Resolve a route's raw (pre-redaction) skeleton anchors to content-free nav edges.
    Anchors are identified by HREF PRESENCE (only links carry an href; robust to how role
    classification labels them). Reads href + aria_role/parent from the raw node-list;
    never returns an href."""
    by_id = {n["id"]: n for n in sk_nodes}
    anchors = [{"node": n["id"], "href": n.get("href"),
                "chrome": _nav.classify_chrome(n["id"], by_id)}
               for n in sk_nodes if n.get("href")]
    return _nav.resolve_edges(anchors, route_map, src_id)
```

In `capture_route`, after `web_skeleton` writes `sk` and BEFORE the scratch closes, read the raw skeleton and resolve. Change the signature to accept `route_map` + `src_id` and return edges. Concretely, replace the success `return (True, len(skel.get("nodes", [])), None)` path so the function also returns edges, and read the RAW `_sk.json` (which still carries `href`):

```python
def capture_route(url, route_dir, transport, sweep=None, route_map=None, src_id=None):
    # ... unchanged until after bundle_writer success and skeleton.json read ...
        edges = []
        if route_map is not None and src_id is not None:
            try:
                raw = json.loads(sk.read_text())          # raw _sk.json (pre-redaction, has href)
                edges = _edges_from_skeleton(raw.get("nodes", []), route_map, src_id)
            except (OSError, ValueError, KeyError):
                edges = []
        return (True, len(skel.get("nodes", [])), None, edges)
```

Update every `capture_route` failure `return` to the 4-tuple `(False, None, "<kind>", [])`.

In `capture_site`, build the route_map upfront and thread src_id + collect edges:

```python
def capture_site(urls, out_dir, transport, sweep=None):
    # ... existing setup ...
    route_map = _nav.build_route_map(urls)
    rows, all_edges = [], []
    for src_id, url in enumerate(urls):
        rid = "r%d" % src_id            # keep the existing route-id-string scheme
        ok, node_count, error_kind, edges = capture_route(
            url, out / "routes" / rid, transport, sweep, route_map=route_map, src_id=src_id)
        row = {"route_id": rid, "url": url, "bundle": "routes/" + rid, "ok": ok}
        if node_count is not None:
            row["node_count"] = node_count
        if error_kind:
            row["error_kind"] = error_kind
        rows.append(row)
        # _nav uses integer route indices (pure, scheme-agnostic); convert to the route_id
        # STRINGS site.json uses ("r%d"), so nav_edges reference routes[].route_id directly.
        for e in edges:
            all_edges.append({"src": "r%d" % e["src"], "dst": "r%d" % e["dst"],
                              "src_node": e["src_node"], "chrome": e["chrome"]})
    manifest = _site.build_site_manifest(rows, nav_edges=all_edges)
    # ... unchanged write + audit ...
```

(Match the EXISTING `rid` / row construction in the file — the snippet shows the shape; preserve any fields the current loop already sets. `src_node` stays an integer skeleton node id; `src`/`dst` become `route_id` strings matching `routes[].route_id`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_site_capture_nav.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/site_capture.py tests/test_site_capture_nav.py
git commit -m "feat: site_capture resolves per-route nav edges (route_map upfront, content-free)"
```

---

### Task 7: `_site.build_site_manifest` emits `nav_edges`

**Files:**
- Modify: `scripts/_site.py` (`build_site_manifest`, ~line 19)
- Test: `tests/test_site_manifest_nav.py` (create)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_site_manifest_nav.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import _site


def test_build_site_manifest_includes_nav_edges():
    rows = [{"route_id": "r0", "url": "https://x.com/", "bundle": "routes/r0", "ok": True},
            {"route_id": "r1", "url": "https://x.com/a", "bundle": "routes/r1", "ok": True}]
    edges = [{"src": "r0", "dst": "r1", "src_node": 5, "chrome": True}]   # route_id strings, as capture_site emits
    m = _site.build_site_manifest(rows, nav_edges=edges)
    assert m["nav_edges"] == edges
    # back-compat: default arg keeps callers that pass no edges working, emits []
    assert _site.build_site_manifest(rows)["nav_edges"] == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/test_site_manifest_nav.py -v`
Expected: FAIL — `build_site_manifest()` takes no `nav_edges` kwarg, or `KeyError: 'nav_edges'`.

- [ ] **Step 3: Implement** — add the `nav_edges` parameter and field. The current function (`scripts/_site.py:19`) RETURNS A DICT LITERAL directly:

```python
def build_site_manifest(rows):
    hosts = sorted({urlparse(r["url"]).netloc for r in rows if r.get("url")})
    return {
        "schema": SITE_SCHEMA,
        "hosts": hosts,
        "route_count": len(rows),
        "ok_count": sum(1 for r in rows if r.get("ok")),
        "routes": rows,
    }
```

Change it to (add the `nav_edges` param + one key in the literal — leave every other field untouched):

```python
def build_site_manifest(rows, nav_edges=None):
    hosts = sorted({urlparse(r["url"]).netloc for r in rows if r.get("url")})
    return {
        "schema": SITE_SCHEMA,
        "hosts": hosts,
        "route_count": len(rows),
        "ok_count": sum(1 for r in rows if r.get("ok")),
        "routes": rows,
        "nav_edges": nav_edges or [],
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/test_site_manifest_nav.py -v && python3 -m pytest tests/ -k site -q`
Expected: new test PASS; existing site tests still green.

- [ ] **Step 5: Commit**

```bash
git add scripts/_site.py tests/test_site_manifest_nav.py
git commit -m "feat: site.json carries content-free nav_edges (default [])"
```

---

### Task 8: Firewall canary — the `nav_edges` path is gated, ships no href

**Files:**
- Test: `tests/test_nav_firewall_canary.py` (create)

- [ ] **Step 1: Write the failing test**

```python
# tests/test_nav_firewall_canary.py
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import content_firewall as cf


def test_seeded_href_in_site_json_trips_audit(tmp_path):
    # A site.json whose nav_edges illegitimately carries an href media value must trip the audit,
    # proving the new field is NOT exempt from the content-url scan.
    site = tmp_path / "site.json"
    site.write_text(json.dumps({
        "routes": [{"route_id": "r0", "url": "https://x.com/", "ok": True}],
        "nav_edges": [{"src": 0, "dst": 1, "src_node": 5, "chrome": True,
                       "leak": "https://cdn.example.com/secret.png"}],   # seeded banned URL
    }))
    viol = cf.audit_bundle(str(tmp_path))
    assert viol, "audit must flag a media URL seeded into nav_edges"


def test_clean_nav_edges_pass_audit(tmp_path):
    site = tmp_path / "site.json"
    site.write_text(json.dumps({
        "routes": [{"route_id": "r0", "url": "https://x.com/", "ok": True}],
        "nav_edges": [{"src": "r0", "dst": "r1", "src_node": 5, "chrome": True}],
    }))
    assert cf.audit_bundle(str(tmp_path)) == []
```

- [ ] **Step 2: Run test to verify it passes (audit already rglobs site.json)**

Run: `python3 -m pytest tests/test_nav_firewall_canary.py -v`
Expected: BOTH pass — the existing `audit_bundle` content-url scan already covers `site.json` (it rglobs the tree); the clean topology (ints + bool) has no URL, the seeded media URL trips it. If `test_clean_nav_edges_pass_audit` fails, the manifest's own `url` fields are tripping the audit (a pre-existing behavior) — investigate before proceeding; the nav feature must not newly trip on legitimate manifest urls.

- [ ] **Step 3: Commit**

```bash
git add tests/test_nav_firewall_canary.py
git commit -m "test: firewall canary proves nav_edges path is content-gated"
```

---

### Task 9: Live smoke + record build verdict (manual HOST leg)

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (append a `§C9-R-NG-build` results note)

Manual HOST leg (env-skip in CI per memory `live-cdp-capture-is-manual-harness-not-pytest`). Subagents cannot run this (no `:9222`).

- [ ] **Step 1: Launch Chrome on the host with an open tab**

Run (host, via `!`): `/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/ng-smoke about:blank &`

- [ ] **Step 2: Capture a real multi-route site**

Run: `python3 scripts/site_capture.py --urls "https://www.djangoproject.com/,https://www.djangoproject.com/start/,https://www.djangoproject.com/download/,https://www.djangoproject.com/community/" --out /tmp/ng_site --cdp-port 9222`
Expected: exit 0, `/tmp/ng_site/site.json` written.

- [ ] **Step 3: Assert the artifact (content-free + populated)**

Run: `python3 -c "import json; m=json.load(open('/tmp/ng_site/site.json')); e=m['nav_edges']; print('edges',len(e),'chrome',sum(x['chrome'] for x in e)); assert all(set(x)=={'src','dst','src_node','chrome'} for x in e), 'extra keys'; assert all(isinstance(x['src'],str) and x['src'][0]=='r' and isinstance(x['src_node'],int) for x in e), 'src/dst must be route_id strings, src_node an int'; print('keys OK (no url/text); src/dst are route_ids')"`
Expected: non-zero edges, chrome-dominated, key-set exactly `{src,dst,src_node,chrome}`, `src`/`dst` are `"r#"` strings.
Run: `python3 -c "import sys; sys.path.insert(0,'scripts'); import content_firewall as cf; print('audit', cf.audit_bundle('/tmp/ng_site'))"`
Expected: `audit []`.

- [ ] **Step 4: Default-contract guard (single-route web_skeleton unchanged)**

Run: `python3 -m pytest tests/ -q`
Expected: full suite green (the href extraction must not alter any shipped-skeleton assertion).

- [ ] **Step 5: Record `§C9-R-NG-build`** (append to the gaps doc: edge count, chrome/content split, `src_node`→skeleton-id join confirmed, audit clean, default contract byte-identical). Commit.

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record nav-link route-annotation build verdict (§C9-R-NG-build)"
```

---

## Self-Review

**1. Spec coverage:** §2 product (`nav_edges {src,dst,src_node,chrome}`) → Tasks 6–7. §3 `_nav` unit → Tasks 1–3. §3 `web_skeleton` href → Task 4. §3 `site_capture` resolve+aggregate → Task 6. §3 `_site` → Task 7. §4 content-free (scratch-confined href, redaction strips, canary) → Tasks 4/5/8. §4 node-id join key → Task 5. §5 testing (pure units, canary, manual smoke) → Tasks 1–3,8,9. §6 scope cuts (no idx, chrome-bool only, content rare) → encoded in Task 2/6 (no ordinal; chrome boolean). ✓

**2. Placeholder scan:** No TBD/TODO; each code step shows complete code. Tasks 6 notes "match existing rid/row construction" — this references the real file's current loop (concrete), with the full edge/route_map threading shown. Task 5 instructs grepping for the real redactor name rather than inventing one (honest about an unverified symbol name).

**3. Type consistency:** edge dict `{src,dst,src_node,chrome}` identical across Tasks 2/6/7/8/9. `resolve_edges(anchors, route_map, src_id)`, `classify_chrome(node_id, by_id)`, `build_route_map(urls)`, `_edges_from_skeleton(sk_nodes, route_map, src_id)` signatures consistent across tasks. `capture_route` 4-tuple `(ok, node_count, error_kind, edges)` consistent. `build_site_manifest(rows, nav_edges=None)` consistent (Task 6 caller ↔ Task 7 def). ✓

**4. Real-shape pinned (verified against the codebase + live, per `validate-real-artifact-not-keys-proxy`):**
- DOMSnapshot `nodes.attributes` carries `href` for every anchor — verified live (71/71 on djangoproject.com).
- `to_skeleton` (`web_skeleton.py:537`) builds nodes from a WHITELIST literal, so `href` is propagated explicitly in BOTH `parse_snapshot` and `to_skeleton` (Task 4 + 4b) — without 4b the pipeline silently yields zero edges.
- Final skeleton nodes carry `role` (anchors → `link`/`image`/`text`), `parent`, and `aria_role` (via `enrich_aria`) — NO `tag`; so anchors are identified by **href presence** (Task 6) and `classify_chrome` walks `parent`/`aria_role`.
- `content_firewall.redact_node` (`content_firewall.py:41`) filters top-level `CONTENT_KEYS` (incl. `href`) and preserves `id`/`parent` — so `src_node` (the shipped skeleton id) survives and href is stripped (Task 5 guard).
- Edges carry `route_id` STRINGS (`"r0"`) matching `routes[].route_id`; `_nav` uses integer indices internally, `capture_site` converts (Task 6). `src_node` stays an integer node id.

**Remaining live-only confirmation (Task 9, manual):** end-to-end non-zero edges on a real site + audit clean + byte-identical default contract. Subagents cannot run it (`:9222`); it is the integration gate.
