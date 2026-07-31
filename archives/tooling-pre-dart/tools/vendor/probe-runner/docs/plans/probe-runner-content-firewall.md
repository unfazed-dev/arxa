# Content Firewall (Mode R) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a probe-runner `bundle/` content-free **by construction** — classify every skeleton node as mechanism (reproduce) vs content (redact to a typed slot), strip content from emitted nodes, and gate every bundle write with an unconditional audit that hard-fails on any IP leak.

**Architecture:** A new self-contained `content_firewall.py` (pure functions + a file-scan audit) and `slots.py` (typed slot schema), wired into `bundle_writer.write_bundle` so the audit runs on every write. This is the first of 7 sub-plans decomposed from `docs/plans/probe-runner-total-capture-tdd-plan.md`; it is the safety spine the other six depend on. Builds on the existing role classification (`image`/`text`/`svg`/`box`) and `derive_slots` already in `bundle_writer.py`.

**Tech Stack:** Python 3 (stdlib only: `json`, `re`, `pathlib`), pytest. Scripts live in `~/Developer/artificial_intelligence/skills/probe-runner/scripts/` (canonical); tests are siblings imported directly. Run tests from the `scripts/` dir.

**Conventions (carried from the parent plan):**
- TDD per task: failing test → run-fail → minimal code → run-pass → commit. Single-line commit, explicit staging, **no push**.
- Synthetic tests feed **varying** data across cases (synthetic-green-trap guard).
- Canonical first; propagation to engineering-pack + brainiac is a later cross-subsystem task (not in this plan).
- Path shorthand below: `PR = ~/Developer/artificial_intelligence/skills/probe-runner`.

---

## File Structure

- **Create** `PR/scripts/content_firewall.py` — classification, redaction, and the `audit_bundle` file-scan gate. One responsibility: the IP boundary.
- **Create** `PR/scripts/slots.py` — the typed `Slot` schema + `build_slots` (richer than `derive_slots`).
- **Create** `PR/scripts/test_content_firewall.py` — unit tests for classify/redact/audit.
- **Create** `PR/scripts/test_slots.py` — unit tests for the slot schema + index.
- **Modify** `PR/scripts/bundle_writer.py` — `write_bundle` calls `content_firewall.audit_bundle` after writing and raises on any violation; `assemble` uses `slots.build_slots` for the manifest.
- **Modify** `PR/scripts/test_bundle_writer.py` — add a test that a poisoned bundle fails the write.

---

## Task 1: Classify each node as mechanism vs content

**Files:**
- Create: `PR/scripts/content_firewall.py`
- Test: `PR/scripts/test_content_firewall.py`

- [ ] **Step 1: Write the failing test**

```python
# test_content_firewall.py
import content_firewall as cf


def _node(role, **extra):
    n = {"id": 1, "role": role, "bbox": {"x": 0, "y": 0, "w": 100, "h": 40}}
    n.update(extra)
    return n


def test_classify_separates_content_from_mechanism():
    # raster + text are content; box is mechanism. Vary inputs (no collapse).
    assert cf.classify_node(_node("image"))["klass"] == "content"
    assert cf.classify_node(_node("text", text_len=12))["klass"] == "content"
    assert cf.classify_node(_node("box"))["klass"] == "mechanism"
    assert cf.classify_node(_node("unknown_box"))["klass"] == "mechanism"


def test_classify_svg_is_kept_content_with_class():
    # svg geometry is KEPT (user decision) but tagged for swap by size heuristic.
    small = cf.classify_node(_node("svg", bbox={"x": 0, "y": 0, "w": 24, "h": 24}))
    big = cf.classify_node(_node("svg", bbox={"x": 0, "y": 0, "w": 600, "h": 400}))
    assert small["klass"] == "kept-content" and small["svg_class"] == "icon"
    assert big["klass"] == "kept-content" and big["svg_class"] == "illustration"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'content_firewall'`

- [ ] **Step 3: Write minimal implementation**

```python
# content_firewall.py
#!/usr/bin/env python3
"""content_firewall — the IP boundary. Classifies every skeleton node as
mechanism (reproduce) vs content (redact to a typed slot), strips content from
emitted nodes, and audits a written bundle/ for any content leak. The bundle is
content-free BY CONSTRUCTION: audit_bundle() is the unconditional gate."""
from __future__ import annotations

ICON_MAX_PX = 48  # an inline svg whose largest side <= this is treated as a UI icon


def _svg_class(node):
    b = node.get("bbox") or {}
    longest = max(b.get("w") or 0, b.get("h") or 0)
    return "icon" if longest <= ICON_MAX_PX else "illustration"


def classify_node(node):
    """Classify a skeleton node. Returns {klass, type[, svg_class]}.
    klass: 'content' (redact->slot) | 'kept-content' (svg: keep geometry, tag) |
    'mechanism' (reproduce as-is)."""
    role = node.get("role")
    if role == "image":
        return {"klass": "content", "type": "image"}
    if role == "text":
        return {"klass": "content", "type": "text"}
    if role == "svg":
        return {"klass": "kept-content", "type": "svg",
                "svg_class": _svg_class(node)}
    return {"klass": "mechanism", "type": role}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/content_firewall.py scripts/test_content_firewall.py
git -C "$PR" commit -m "feat(content_firewall): classify nodes mechanism vs content (svg kept+classed)"
```

---

## Task 2: Redact content keys from emitted nodes

**Files:**
- Modify: `PR/scripts/content_firewall.py`
- Test: `PR/scripts/test_content_firewall.py`

- [ ] **Step 1: Write the failing test**

```python
# append to test_content_firewall.py
def test_redact_strips_all_content_keys_keeps_mechanism():
    node = {
        "id": 7, "role": "image",
        "bbox": {"x": 0, "y": 0, "w": 100, "h": 40},
        "token_ref": {"bg": "surface"}, "anim_ref": ["hero#tx"],
        # planted content that must NOT survive:
        "text": "Handcrafted with urushi lacquer",
        "src": "https://kasane.example/photo.jpg",
        "background_image": "url(https://kasane.example/bg.png)",
        "alt": "a hand lacquering a keyboard", "title": "kasane",
        "aria_label": "hero image", "placeholder": "type here", "value": "secret",
    }
    out = cf.redact_node(node)
    for k in cf.CONTENT_KEYS:
        assert k not in out, f"content key {k!r} leaked"
    # mechanism survives:
    assert out["bbox"] == node["bbox"]
    assert out["token_ref"] == {"bg": "surface"}
    assert out["anim_ref"] == ["hero#tx"]


def test_redact_text_node_keeps_only_length_class():
    node = {"id": 9, "role": "text", "bbox": {"x": 0, "y": 0, "w": 80, "h": 20},
            "text": "Buy now", "text_len": 7,
            "font": {"size": 16, "weight": 600, "line": 20, "family": "Inter"}}
    out = cf.redact_node(node)
    assert "text" not in out
    assert out["text_len"] == 7          # length kept (mechanism for sizing)
    assert out["font"]["family"] == "Inter"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py::test_redact_strips_all_content_keys_keeps_mechanism -v`
Expected: FAIL with `AttributeError: module 'content_firewall' has no attribute 'redact_node'`

- [ ] **Step 3: Write minimal implementation**

```python
# add to content_firewall.py (after classify_node)

# literal-content keys that must never survive onto an emitted node.
CONTENT_KEYS = ("text", "src", "href", "url", "background_image",
                "alt", "title", "aria_label", "placeholder", "value", "content")


def redact_node(node):
    """Return a copy of node with every CONTENT_KEYS entry removed. Mechanism
    keys (bbox, role, token_ref, anim_ref, font, text_len, sizing, layout, ...)
    are preserved. text_len is intentionally KEPT — it is a sizing input, not
    content."""
    return {k: v for k, v in node.items() if k not in CONTENT_KEYS}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py -v`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/content_firewall.py scripts/test_content_firewall.py
git -C "$PR" commit -m "feat(content_firewall): redact literal-content keys, keep mechanism + text_len"
```

---

## Task 3: Typed Slot schema + build_slots

**Files:**
- Create: `PR/scripts/slots.py`
- Test: `PR/scripts/test_slots.py`

- [ ] **Step 1: Write the failing test**

```python
# test_slots.py
import slots


def _n(nid, role, **extra):
    n = {"id": nid, "role": role, "bbox": {"x": 0, "y": 0, "w": 120, "h": 60},
         "token_ref": {"bg": "surface", "border": None}, "anim_ref": ["a#tx"]}
    n.update(extra)
    return n


def test_build_slots_one_typed_slot_per_content_node_with_index():
    nodes = [
        _n(1, "image"),
        _n(2, "text", text_len=10,
           font={"size": 32, "weight": 700, "line": 40, "family": "Inter"}),
        _n(3, "svg", bbox={"x": 0, "y": 0, "w": 24, "h": 24}),
        _n(4, "box"),  # mechanism -> no slot
    ]
    out = slots.build_slots(nodes)
    kinds = {s["type"] for s in out["slots"]}
    assert kinds == {"image", "text", "svg"}           # box excluded
    assert out["index"] == [1, 2, 3]                    # node ids, ordered
    img = next(s for s in out["slots"] if s["type"] == "image")
    assert img["box"]["w"] == 120 and img["aspect_ratio"] == 2.0
    assert img["theme_ref"] == {"bg": "surface", "border": None}
    assert img["anim_ref"] == ["a#tx"]
    txt = next(s for s in out["slots"] if s["type"] == "text")
    assert txt["text_class"]["char_len_bucket"] == "short"   # 10 chars
    svg = next(s for s in out["slots"] if s["type"] == "svg")
    assert svg["svg_class"] == "icon" and svg["fill_hint"]


def test_text_len_buckets_vary():
    short = slots._char_bucket(8)
    medium = slots._char_bucket(60)
    long_ = slots._char_bucket(400)
    assert (short, medium, long_) == ("short", "medium", "long")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_slots.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'slots'`

- [ ] **Step 3: Write minimal implementation**

```python
# slots.py
#!/usr/bin/env python3
"""slots — the typed placeholder-slot schema the rebuilding agent fills.
One slot per content node (image/text/svg); mechanism nodes get none. Emits a
slots manifest {slots:[...], index:[node_id,...]} consumed by bundle_writer."""
from __future__ import annotations

import content_firewall as cf


def _aspect(b):
    return round(b["w"] / b["h"], 4) if b.get("h") else None


def _char_bucket(n):
    if n <= 24:
        return "short"
    if n <= 120:
        return "medium"
    return "long"


def _fill_hint(kind, node, info):
    if kind == "image":
        return f"{info.get('role','image')} image, aspect {_aspect(node['bbox'])}"
    if kind == "text":
        return f"{_char_bucket(node.get('text_len') or 0)} text"
    if kind == "svg":
        return f"{info.get('svg_class','svg')} svg ({'swap' if info.get('svg_class') in ('logo','illustration') else 'keep'})"
    return kind


def _slot(node, kind, info):
    b = node["bbox"]
    s = {
        "id": node["id"], "type": kind,
        "box": b, "aspect_ratio": _aspect(b),
        "theme_ref": node.get("token_ref"),
        "anim_ref": node.get("anim_ref"),
        "fill_hint": _fill_hint(kind, node, info),
    }
    if kind == "text":
        s["text_class"] = {"char_len_bucket": _char_bucket(node.get("text_len") or 0)}
    if kind == "svg":
        s["svg_class"] = info.get("svg_class")
    return s


def build_slots(nodes):
    """Return {'slots': [Slot,...], 'index': [node_id,...]} for every content or
    kept-content node. Mechanism nodes contribute nothing."""
    out = []
    for n in nodes:
        info = cf.classify_node(n)
        if info["klass"] == "mechanism":
            continue
        out.append(_slot(n, info["type"], info))
    return {"slots": out, "index": [s["id"] for s in out]}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_slots.py -v`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/slots.py scripts/test_slots.py
git -C "$PR" commit -m "feat(slots): typed placeholder-slot schema + build_slots index"
```

---

## Task 4: Audit gate — file scan that hard-fails on any leak

**Files:**
- Modify: `PR/scripts/content_firewall.py`
- Test: `PR/scripts/test_content_firewall.py`

- [ ] **Step 1: Write the failing test**

```python
# append to test_content_firewall.py
import json


def _clean_bundle(d):
    """Write a minimal clean bundle/ under directory d; return d. Recursive
    mkdir so callers may pass a not-yet-created subdir."""
    d.mkdir(parents=True, exist_ok=True)
    (d / "assets").mkdir(parents=True, exist_ok=True)
    (d / "skeleton.json").write_text(json.dumps(
        {"nodes": [{"id": 1, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}}]}))
    (d / "tokens.json").write_text(json.dumps({"palette": {"bg": "#fff"}}))
    (d / "motion.json").write_text(json.dumps([]))
    (d / "meta.json").write_text(json.dumps({"url": "x", "schema": 1}))
    return d


def test_audit_passes_clean_bundle(tmp_path):
    assert cf.audit_bundle(_clean_bundle(tmp_path)) == []


def test_audit_catches_each_leak_class(tmp_path):
    # one isolated clean bundle per class, then poison its skeleton.json.
    cases = {
        "datauri": json.dumps({"x": "data:image/png;base64,iVBORw0KGgo="}),
        "prose": json.dumps({"x": "Handcrafted with urushi lacquer by artisans"}),
        "url": json.dumps({"x": "https://kasane.example/hero.jpg"}),
    }
    for name, payload in cases.items():
        d = _clean_bundle(tmp_path / name)
        (d / "skeleton.json").write_text(payload)
        viol = cf.audit_bundle(d)
        assert viol, f"{name}: expected a violation"


def test_audit_catches_raster_magic_bytes(tmp_path):
    _clean_bundle(tmp_path)
    (tmp_path / "assets" / "leak.bin").write_bytes(b"\x89PNG\r\n\x1a\n rest")
    viol = cf.audit_bundle(tmp_path)
    assert any("magic" in v["kind"] for v in viol)


def test_audit_allows_real_font_stacks_and_page_url(tmp_path):
    # mechanism that MUST pass: full font stacks (kept) + a non-media page URL.
    # font families live under keys 'family'/'families' (web_tokens) and in
    # skeleton node font blocks; the prose scan must not flag them. This is the
    # discriminating test — the naive value-substring exemption fails it.
    d = _clean_bundle(tmp_path)
    (d / "tokens.json").write_text(json.dumps({
        "palette": {"background": "#0b0b0c"},
        "type_scale": {
            "families": ["Helvetica Neue, Arial, sans-serif",
                         "system-ui, -apple-system, Segoe UI, Roboto, sans-serif"],
            "sizes": [16, 24, 64], "weights": [400, 700]}}))
    (d / "skeleton.json").write_text(json.dumps({"nodes": [
        {"id": 1, "role": "text", "bbox": {"x": 0, "y": 0, "w": 80, "h": 20},
         "text_len": 7,
         "font": {"size": 16, "weight": 600,
                  "family": "Helvetica Neue, Arial, sans-serif"}}]}))
    (d / "meta.json").write_text(json.dumps(
        {"url": "https://kasane.example/products/keyboard", "schema": 1}))
    assert cf.audit_bundle(d) == []


def test_prose_exemption_is_key_based_not_value_based():
    # a font stack with NO generic font keyword (no sans-serif/serif/etc): it can
    # only be exempted via the JSON KEY, never a value-substring match. This is
    # the genuinely discriminating test — it FAILS under a naive value-substring
    # exemption (which flags it) and PASSES only with key-based exemption.
    stack = "Neue Haas Grotesk Display Pro, Trade Gothic Next Condensed"
    assert cf._prose_in_json({"family": stack}, "tokens.json") == []   # key-exempt
    flagged = cf._prose_in_json({"caption": stack}, "skeleton.json")   # not exempt
    assert flagged and flagged[0]["kind"] == "prose"                   # negative ctrl
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py -k audit -v`
Expected: FAIL with `AttributeError: module 'content_firewall' has no attribute 'audit_bundle'`

- [ ] **Step 3: Write minimal implementation**

```python
# add to content_firewall.py (top: add imports)
import json
import re
from pathlib import Path

# leak signatures
_DATA_URI = re.compile(r"data:[a-zA-Z0-9.+-]*/?[a-zA-Z0-9.+-]*;base64,", re.I)
_B64_BLOB = re.compile(r"[A-Za-z0-9+/]{200,}={0,2}")
_CONTENT_URL = re.compile(
    r"https?://[^\s\"')]+\.(?:png|jpe?g|gif|webp|avif|svg|mp4|webm|mov|woff2?|ttf|otf)",
    re.I)
# prose = a run with a space and mostly letters, longer than the theme noise floor.
_PROSE = re.compile(r"[A-Za-z][A-Za-z ,.'’\-]{24,}")
# binary magic numbers for raster/font/video.
_MAGIC = [b"\x89PNG", b"\xff\xd8\xff", b"GIF8", b"RIFF", b"wOFF", b"wOF2",
          b"\x00\x01\x00\x00", b"OTTO", b"\x1a\x45\xdf\xa3"]
# JSON keys whose string values are theme/spec (mechanism), exempt from prose.
# Font families are KEPT mechanism — they are prose-shaped but NOT content, so
# the prose scan must skip them. Exemption is keyed off the JSON KEY, never the
# value (a font stack like "Helvetica Neue, Arial" contains no key-word).
# NOTE: "url" is deliberately NOT exempt — a real page URL never trips _PROSE
# (colons/slashes break the run), and exempting it would let prose hide under a
# "url" key. data:/content-url checks already run on the whole text regardless.
_PROSE_EXEMPT_KEYS = {"family", "families", "font", "font_family", "fontFamily",
                      "easing", "cubic_bezier", "timing", "ease"}
# generic CSS font keywords — exempt prose runs that are clearly font stacks even
# in keyless text (css/svg) where the JSON-key signal is unavailable.
_FONT_KEYWORDS = ("sans-serif", "serif", "monospace", "system-ui",
                  "-apple-system", "ui-sans-serif", "ui-monospace", "cursive")


def _is_font_value(s):
    low = s.lower()
    return any(kw in low for kw in _FONT_KEYWORDS)


def _walk_strings(obj, key=None):
    """Yield (nearest_mapping_key, string) for every string in a nested JSON
    value. List items inherit their list's key."""
    if isinstance(obj, str):
        yield key, obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from _walk_strings(v, k)
    elif isinstance(obj, list):
        for v in obj:
            yield from _walk_strings(v, key)


def _prose_in_json(data, rel):
    for key, s in _walk_strings(data):
        if key in _PROSE_EXEMPT_KEYS or _is_font_value(s):
            continue
        if _PROSE.search(s):
            return [{"kind": "prose", "file": rel, "sample": s[:40]}]
    return []


def _prose_raw(txt, rel):
    for m in _PROSE.finditer(txt):
        s = m.group(0)
        if _is_font_value(s):
            continue
        return [{"kind": "prose", "file": rel, "sample": s[:40]}]
    return []


def _scan_text(path, rel):
    out = []
    txt = path.read_text(errors="replace")
    if _DATA_URI.search(txt):
        out.append({"kind": "data-uri", "file": rel})
    if _CONTENT_URL.search(txt):
        out.append({"kind": "content-url", "file": rel})
    if _B64_BLOB.search(txt):
        out.append({"kind": "base64-blob", "file": rel})
    # prose: key-aware for JSON (exempt font/theme keys), raw fallback otherwise.
    if path.suffix.lower() == ".json":
        try:
            out.extend(_prose_in_json(json.loads(txt), rel))
        except ValueError:
            out.extend(_prose_raw(txt, rel))
    else:
        out.extend(_prose_raw(txt, rel))
    return out


def audit_bundle(bundle_dir):
    """Scan every file under bundle_dir for content leaks. Returns a list of
    violations (empty == clean). Bias to false-positive on real content but
    exempts known mechanism (font stacks, theme/easing keys) so legitimate
    bundles pass: catches data: URIs, base64 blobs, retained content URLs,
    prose-like strings, and raster/font/video magic bytes. This is THE
    invariant — callers must treat a non-empty result as a hard failure."""
    root = Path(bundle_dir)
    viol = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(root))
        head = p.read_bytes()[:16]
        if any(head.startswith(m) for m in _MAGIC):
            viol.append({"kind": "magic-bytes", "file": rel})
            continue  # binary; don't also text-scan
        if p.suffix.lower() in (".json", ".txt", ".css", ".svg", ".html"):
            viol.extend(_scan_text(p, rel))
    return viol
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_content_firewall.py -v`
Expected: PASS (all tests; the audit cases green)

- [ ] **Step 5: Commit**

```bash
git -C "$PR" add scripts/content_firewall.py scripts/test_content_firewall.py
git -C "$PR" commit -m "feat(content_firewall): audit_bundle file-scan gate (data-uri/url/base64/prose/magic)"
```

---

## Task 5: Wire the audit into bundle_writer + use typed slots

**Files:**
- Modify: `PR/scripts/bundle_writer.py:128-163` (`assemble` + `write_bundle`)
- Test: `PR/scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing test**

```python
# append to test_bundle_writer.py
import json
import pytest
import bundle_writer as bw


def test_write_bundle_fails_on_content_leak(tmp_path):
    # a skeleton node carrying planted prose must not survive into a written
    # bundle: write_bundle audits and raises.
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "text",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20},
                           "leaked_prose": "Handcrafted with urushi lacquer here"}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    # force the leak past redaction to prove the audit is the backstop:
    bundle["skeleton"]["nodes"][0]["leaked_prose"] = \
        "Handcrafted with urushi lacquer applied by hand"
    with pytest.raises(bw.ContentLeak):
        bw.write_bundle(bundle, tmp_path)


def test_write_bundle_clean_passes(tmp_path):
    skeleton = {"url": "x", "schema": 1,
                "viewport": {"w": 1280, "h": 800, "dpr": 2}, "page": {"h": 1000},
                "nodes": [{"id": 1, "role": "box",
                           "bbox": {"x": 0, "y": 0, "w": 50, "h": 20}}]}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={})
    bw.write_bundle(bundle, tmp_path)   # no raise
    assert (tmp_path / "skeleton.json").exists()
    assert (tmp_path / "assets" / "manifest.json").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "$PR/scripts" && python3 -m pytest test_bundle_writer.py -k "leak or clean" -v`
Expected: FAIL with `AttributeError: module 'bundle_writer' has no attribute 'ContentLeak'`

- [ ] **Step 3: Write minimal implementation**

In `bundle_writer.py`, add the import and exception near the top (after line 14):

```python
import content_firewall as cf
import slots as _slots


class ContentLeak(RuntimeError):
    """Raised when audit_bundle finds content in a written bundle/."""
```

Replace the manifest line in `assemble` (currently `slots = derive_slots(nodes)` then `"manifest": {"slots": slots}`) so the typed builder is used:

```python
    motion = match_motion(nodes, motion_rows)
    manifest = _slots.build_slots(nodes)   # typed slots + index (supersedes derive_slots)
```

and change the return's manifest entry to:

```python
        "manifest": manifest,
```

Append the audit to the end of `write_bundle` (after the `manifest.json` write; the output Path variable in `write_bundle` is `root`, the `out_dir` arg is the raw path):

```python
    viol = cf.audit_bundle(root)
    if viol:
        raise ContentLeak(f"content leak in bundle {out_dir}: {viol[:5]}")
```

**Also migrate the one existing assertion that reads the old slot schema.** `test_bundle_writer.py:186` (in `test_assemble_builds_all_five_documents`) asserts on `derive_slots`' field names; `build_slots` renames `node_id`→`id` and `kind`→`type`. Change:

```python
    # manifest slot for the image
    assert any(s["node_id"] == 0 and s["kind"] == "image" for s in bundle["manifest"]["slots"])
```

to:

```python
    # manifest slot for the image (build_slots schema: id/type, + index)
    assert any(s["id"] == 0 and s["type"] == "image" for s in bundle["manifest"]["slots"])
    assert bundle["manifest"]["index"] == [0]   # build_slots adds the id index
```

(`test_derive_slots_per_role` exercises `derive_slots` directly and is untouched — the function still exists.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd "$PR/scripts" && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (existing bundle_writer tests + the 2 new ones)

- [ ] **Step 5: Run the full canonical suite (no regressions)**

Run: `cd "$PR/scripts" && python3 -m pytest -q`
Expected: all green (the prior 154 + the new firewall/slots tests)

- [ ] **Step 6: Commit**

```bash
git -C "$PR" add scripts/bundle_writer.py scripts/test_bundle_writer.py
git -C "$PR" commit -m "feat(bundle_writer): audit every write (ContentLeak) + emit typed slots"
```

---

## Self-Review

**1. Spec coverage** (against Mode R in `probe-runner-total-capture-tdd-plan.md`):
- R1 detect → Task 1 `classify_node` (role-based detection of image/text/svg). ✓
- R2 classify → Task 1 (`svg_class` icon/illustration; klass mechanism/content/kept-content). ✓
- R3 redact → Task 2 `redact_node` (strips CONTENT_KEYS incl. alt/title/aria/placeholder/value; keeps text_len). ✓
- R4 typed slot + index → Task 3 `slots.build_slots` (typed Slot + index manifest). ✓
- R5 audit gate (hard fail) → Task 4 `audit_bundle` + Task 5 `ContentLeak` raised in `write_bundle`, unconditional on every write. ✓
  - **False-positive guard:** the prose scanner exempts font stacks (kept mechanism) by JSON **key** (`family`/`families`/`font`/`easing`/…) — not by value substring, which fails on real stacks like `"Helvetica Neue, Arial, sans-serif"` — plus a generic-keyword fallback for keyless css/svg. `test_audit_allows_real_font_stacks_and_page_url` is the discriminating test; without the key-aware fix the gate would reject every legitimate bundle (skeleton `font.family` + tokens `families`). Verified: no existing `write_bundle` test feeds font stacks, so the 154-suite stays green either way — the bug only bites real bundles.
- **Gap noted (deferred, by design):** logo-class detection (vs illustration) is a size heuristic only here; richer logo classification + the `--mode replica`/owned-content interlock are separate sub-plans, not Mode R. `url()`-bearing CSS-var redaction lands with the Mode A6 authored-CSS sub-plan (no var capture exists yet to leak). Both are correctly out of this plan's scope.

**2. Placeholder scan:** No TBD/TODO; every code step has complete runnable code; every test has real assertions; every command has expected output. ✓

**3. Type consistency:** `classify_node` returns `klass`/`type`/`svg_class` — used identically in `slots.build_slots` (`info["klass"]`, `info["type"]`, `info.get("svg_class")`). `CONTENT_KEYS` defined in Task 2, referenced in the Task 2 test. `audit_bundle` returns a list of `{kind,file,...}` dicts — Task 5 slices `viol[:5]`. `build_slots` returns `{slots, index}` — `assemble` assigns it straight to `manifest` and `main()`'s `len(bundle["manifest"]["slots"])` still resolves. ✓

---

## Post-Review Hardening (applied during execution)

Two issues surfaced by review that the original 5 tasks missed — both fixed, with tests, before the branch was declared done:

**H1 — `url` prose-exempt hole (commit `fe6a760`).** `"url"` was in `_PROSE_EXEMPT_KEYS`, so prose could hide under a `"url"` key. A real page URL never trips `_PROSE` (colons/slashes break the run), so the exemption bought nothing and only opened a hole. Removed it; added `test_prose_exemption_is_key_based_not_value_based` (a keyword-free font stack — exempt only via the JSON key, flagged under any other key) as a genuinely discriminating test.

**H2 — CRITICAL: non-ASCII (CJK) prose evaded the audit (commit `6df49ae`).** `_PROSE` is ASCII-letter-only; on a Japanese site (kasane) real product copy decodes via `json.loads` to CJK the regex can't see, and shipped into `bundle/skeleton.json` with **no** `ContentLeak` (reproduced empirically). Fix: added `_NONASCII_PROSE` — a run of ≥4 letters from spaceless / non-Latin scripts (CJK, kana, Hangul, Greek, Cyrillic, Hebrew, Arabic, Thai, precomposed Latin-ext) — wired into `_prose_in_json` and `_prose_raw`. Japanese font families stay clean (exempt by the `family`/`families` key, checked before any scan). Also tightened `_PROSE_EXEMPT_KEYS` to **font-only** `{family, families, font, font_family, fontFamily}` (dropped `easing`/`cubic_bezier`/`timing`/`ease` — their values never trip `_PROSE`, so exempting them only widened H1's hole class).

**H3 — R3 redaction wired into the emit path (commit `f7250e5`).** `redact_node` existed but was never called — the audit was the *sole* barrier. Wired `skeleton["nodes"] = [cf.redact_node(n) for n in nodes]` into `assemble` (after `build_slots`/`match_motion`, which read the pre-redaction node), giving defense-in-depth: redaction strips known content keys at emit, the audit backstops the unknown. Test injects content pre-`assemble` and asserts the emitted node lacks it.

### Documented residuals (do NOT claim bare "content-free by construction" — say "modulo documented residuals")
- **Scattered-diacritic Latin / Vietnamese** (e.g. `Tiếng Việt`): base letters are ASCII with sparse combining marks, so neither `_PROSE` (broken by the diacritic) nor `_NONASCII_PROSE` (no 4-run of non-ASCII letters) reliably catches it. `_NONASCII_PROSE` is non-ASCII-**alpha** detection, not full prose.
- **Sub-4-char non-ASCII content** (e.g. a 2–3 glyph CJK label) is below the detector floor.
- **Extensionless content URLs** (CDN/hash style, `https://img.example/asset/9f8a3b…`) pass `_CONTENT_URL` (no media extension). The data:/prose/base64 checks do not cover them. → owed to a later hardening pass: whitelist `meta.url`, flag all other external http(s) URLs.
- **Chunked base64 below the 200-char `_B64_BLOB` floor.**
These are acceptable for the foundation sub-plan; the next hardening sub-plan should close the URL gap and consider full-prose (not just non-ASCII-alpha) detection.

---

## Execution Handoff

Plan complete and saved to `docs/plans/probe-runner-content-firewall.md` (per the device's mandatory `docs/plans/<kebab-title>.md` rule, which overrides the skill's default location). Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, two-stage review (spec then quality) between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session via executing-plans, batch with checkpoints.

Which approach?
