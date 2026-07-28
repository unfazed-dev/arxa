# Regime-1 CSS property coverage (cut 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture the remaining Regime-1 visual CSS (27 deferred props: background longhands, outline, text-shadow, overflow, aspect-ratio, object-fit/position, typography, transform-3d) into the existing content-free per-node `style` field, through the proven cut-1 pipeline.

**Architecture:** All 27 props resolve to content-free values and carry NO `url()` vector, so `_style.py` and `bundle_writer.py` are UNCHANGED — only `web_skeleton.py` grows (append-only whitelist + richer sparse-drop). Sparse-drop gains a per-prop default map (12 entries, populated from a host probe) plus an outline-group gate (Chrome defaults `outline-width` to `1.5px`, so the group is gated on `outline-style`, not zero-dropped).

**Tech Stack:** Python 3 stdlib, pytest, Chrome DevTools Protocol (`DOMSnapshot.captureSnapshot`).

**Spec:** `docs/plans/regime1-css-property-coverage-cut2-design.md` (approved + probe-amended 2026-05-31).

**De-risk already done (planning, host CDP):** all 27 props ACCEPTED by `captureSnapshot`; resolved defaults recorded; `_STYLE_DEFAULTS` populated. No probe task remains.

**Standing constraints:** single-line commits, no trailers; stage files explicitly by path (never `git add -A/.`); one commit per task; local on master, do NOT push; host gates run on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox); content-free invariant (never persist third-party content).

---

## File Structure

- `scripts/web_skeleton.py` — ONLY file with logic changes. Append 27 props to `WANT_STYLES` (append-only — parallel-index contract) and `STYLE_PROPS`; add `_STYLE_DEFAULTS` + `_OUTLINE_GATED`; extend `_collect_style`.
- `scripts/test_web_skeleton.py` — unit tests for default-map drop, non-default emission, outline-group gating. (Existing parallel-index pin + `STYLE_PROPS ⊆ WANT_STYLES` guard auto-cover the extension.)
- `scripts/test_content_firewall.py` — a cut-2-valued skeleton audits clean (no new url() vector → no new canary).
- `scripts/test_bundle_writer.py` — round-trip confirming the UNCHANGED prop-agnostic attach carries cut-2 props.
- `scripts/_style.py`, `scripts/bundle_writer.py` — **NO CHANGE** (stated so reviewers do not expect one).
- `fixtures/css_style/run_css_style.py` — extend the offline host gate with cut-2 nodes + default-suppression assertions.
- `fixtures/css_style/validate_realsite.py` — NEW one-off content-free real-site validation (not in the suite).
- `docs/plans/probe-runner-engine-capture-gaps.md`, `docs/research/css-capture-completeness.md`, `docs/plans/regime1-css-property-coverage-cut2-design.md` — results docs.

---

### Task 1: web_skeleton cut-2 capture (whitelist + default map + outline gate)

**Files:**
- Modify: `scripts/web_skeleton.py` (`WANT_STYLES`, `STYLE_PROPS`, add `_STYLE_DEFAULTS`/`_OUTLINE_GATED`, rewrite `_collect_style`)
- Test: `scripts/test_web_skeleton.py`

**Context:** `WANT_STYLES` is the column-order contract for `DOMSnapshot.captureSnapshot` `computedStyles` (`layout.styles[i]` rows are parallel). Append ONLY — never reorder. `STYLE_PROPS` is the subset `_collect_style` reads onto `node["style"]`; an existing guard test asserts `STYLE_PROPS ⊆ WANT_STYLES`. Both lists currently END with the same four `border-*-radius` lines — when editing, disambiguate by the text that FOLLOWS each list's `]` (the `# Per-node visual-style props` comment after `WANT_STYLES`; the `_STYLE_NOOP = ...` line after `STYLE_PROPS`).

- [ ] **Step 1: Write the failing tests**

Add to `scripts/test_web_skeleton.py`:

```python
def test_collect_style_drops_chrome_defaults():
    # Every cut-2 prop at its Chrome resolved default -> no style emitted (sparse).
    st = {"background-size": "auto", "background-position": "0% 0%",
          "background-repeat": "repeat", "background-clip": "border-box",
          "background-origin": "padding-box", "background-attachment": "scroll",
          "background-blend-mode": "normal", "overflow-x": "visible",
          "overflow-y": "visible", "aspect-ratio": "auto", "object-fit": "fill",
          "object-position": "50% 50%", "text-transform": "none",
          "text-decoration-line": "none", "font-variant": "normal",
          "writing-mode": "horizontal-tb", "direction": "ltr",
          "perspective": "none", "transform-style": "flat", "rotate": "none",
          "scale": "none", "translate": "none", "text-shadow": "none",
          "outline-style": "none", "outline-width": "1.5px",
          "outline-color": "rgb(0, 0, 0)", "outline-offset": "0px"}
    assert ws._collect_style(st) == {}


def test_collect_style_keeps_non_default_cut2():
    st = {"background-repeat": "no-repeat", "overflow-x": "hidden",
          "object-fit": "cover", "object-position": "25% 75%",
          "writing-mode": "vertical-rl", "transform-style": "preserve-3d",
          "text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "perspective": "800px",
          "background-position": "10px 20px"}
    out = ws._collect_style(st)
    assert out["background-repeat"] == "no-repeat"
    assert out["overflow-x"] == "hidden"
    assert out["object-fit"] == "cover"
    assert out["object-position"] == "25% 75%"
    assert out["writing-mode"] == "vertical-rl"
    assert out["transform-style"] == "preserve-3d"
    assert out["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert out["perspective"] == "800px"
    assert out["background-position"] == "10px 20px"


def test_collect_style_outline_group_gated_on_style():
    # Chrome resolves outline-width:1.5px / outline-color:rgb(0,0,0) on EVERY node,
    # so the group must be dropped unless outline-style is set (not zero-dropped).
    st0 = {"outline-style": "none", "outline-width": "1.5px",
           "outline-color": "rgb(0, 0, 0)", "outline-offset": "0px"}
    assert ws._collect_style(st0) == {}
    st1 = {"outline-style": "solid", "outline-width": "2px",
           "outline-color": "rgb(1, 2, 3)", "outline-offset": "3px"}
    out = ws._collect_style(st1)
    assert out["outline-style"] == "solid"
    assert out["outline-width"] == "2px"
    assert out["outline-color"] == "rgb(1, 2, 3)"
    assert out["outline-offset"] == "3px"


def test_want_styles_includes_cut2_props():
    for k in ("background-size", "background-repeat", "background-clip",
              "outline-style", "outline-color", "text-shadow", "overflow-x",
              "aspect-ratio", "object-fit", "object-position", "writing-mode",
              "direction", "transform-style", "translate"):
        assert k in ws.WANT_STYLES
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -k "cut2 or chrome_defaults or outline_group" -v`
Expected at this stage (before `STYLE_PROPS`/`WANT_STYLES` are extended):
- `test_collect_style_keeps_non_default_cut2` → **FAIL** (`_collect_style` iterates the not-yet-extended `STYLE_PROPS`, ignores cut-2 keys, returns `{}` → `out["background-repeat"]` KeyError).
- `test_collect_style_outline_group_gated_on_style` → **FAIL** (same KeyError on the `st1` keep-case).
- `test_want_styles_includes_cut2_props` → **FAIL** (props absent from `WANT_STYLES`).
- `test_collect_style_drops_chrome_defaults` → **PASSES VACUOUSLY** here — the cut-2 keys are not read until `STYLE_PROPS` is extended (Step 4), so `_collect_style` returns `{}` and `assert == {}` trivially holds. It is a default-SUPPRESSION guard that only becomes load-bearing after Step 4; its genuine check is the full run in Step 7. Do NOT treat this pre-implementation pass as "already done."

- [ ] **Step 3: Append the 27 props to `WANT_STYLES`**

In `scripts/web_skeleton.py`, inside the `WANT_STYLES = [ ... ]` list, append AFTER the last cut-1 line `"border-bottom-right-radius", "border-bottom-left-radius",` and BEFORE that list's closing `]`:

```python
    # Regime-1 visual-style props (cut 2). APPENDED — keeps every existing index
    # stable (parallel-index contract). All 27 validated against captureSnapshot
    # (host probe 2026-05-31). Captured RAW; no new url() vector (redaction unchanged).
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
```

- [ ] **Step 4: Append the 27 props to `STYLE_PROPS`**

In the `STYLE_PROPS = [ ... ]` list, append AFTER its last cut-1 line `"border-bottom-right-radius", "border-bottom-left-radius",` and BEFORE that list's closing `]`:

```python
    # cut 2 (gating/defaults applied in _collect_style):
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
```

- [ ] **Step 5: Add `_STYLE_DEFAULTS` + `_OUTLINE_GATED`**

Immediately AFTER the existing `_STYLE_NOOP = {None, "", "none", "normal", "auto"}` line, add:

```python
# Cut-2 props whose Chrome RESOLVED DEFAULT is NOT in _STYLE_NOOP (host probe
# 2026-05-31). A prop is dropped when its resolved value equals its default — keeps
# the sidecar sparse (no default-valued prop lands on every node). Values are the
# verbatim probe output; default sets are lower-cased for comparison.
_STYLE_DEFAULTS = {
    "background-position": {"0% 0%"},
    "background-repeat": {"repeat"},
    "background-clip": {"border-box"},
    "background-origin": {"padding-box"},
    "background-attachment": {"scroll"},
    "overflow-x": {"visible"},
    "overflow-y": {"visible"},
    "object-fit": {"fill"},
    "object-position": {"50% 50%"},
    "writing-mode": {"horizontal-tb"},
    "direction": {"ltr"},
    "transform-style": {"flat"},
}
# Outline metrics/color resolve to NON-suppressible defaults on every node
# (outline-width:1.5px, outline-color:rgb(0,0,0), outline-offset:0px), so they are
# emitted ONLY when outline-style is set — gated, like transform-origin on transform.
_OUTLINE_GATED = ("outline-width", "outline-color", "outline-offset")
```

- [ ] **Step 6: Rewrite `_collect_style`**

Replace the entire existing `_collect_style` function with:

```python
def _collect_style(st):
    """Sparse per-node visual style from resolved CSS. Emits a prop only when it has
    visual effect: none/normal/auto/empty dropped; zero -width/-radius dropped; a
    cut-2 prop at its Chrome resolved default dropped (_STYLE_DEFAULTS). Two gated
    groups: transform-origin only when `transform` is set; the outline metrics/color
    (_OUTLINE_GATED) only when `outline-style` is set (else they resolve to defaults
    on every node). Values are RAW (url() redacted later at packaging). {} when nothing
    set."""
    out = {}
    for p in STYLE_PROPS:
        v = st.get(p)
        if v is None or (isinstance(v, str) and v.strip().lower() in _STYLE_NOOP):
            continue
        if p.endswith(("-width", "-radius")) and (_px(v) or 0.0) == 0.0:
            continue
        dflt = _STYLE_DEFAULTS.get(p)
        if dflt and isinstance(v, str) and v.strip().lower() in dflt:
            continue
        out[p] = v
    tr = st.get("transform")
    if tr and tr.strip().lower() not in ("none", ""):
        to = st.get("transform-origin")
        if to and to.strip():
            out["transform-origin"] = to
    o_style = st.get("outline-style")
    if not (o_style and o_style.strip().lower() not in _STYLE_NOOP):
        for k in _OUTLINE_GATED:
            out.pop(k, None)
    return out
```

- [ ] **Step 7: Run the full test file**

Run: `cd scripts && python3 -m pytest test_web_skeleton.py -v`
Expected: PASS — the 4 new tests green; `test_style_props_subset_of_want_styles` and `test_want_styles_parallel_index_stable_after_extension` STILL green (they auto-cover the extension).

- [ ] **Step 8: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: capture cut-2 Regime-1 CSS props with default-map + outline gating"
```

---

### Task 2: firewall clean on cut-2 style values

**Files:**
- Test: `scripts/test_content_firewall.py`

**Context:** `cf.audit_bundle(dir)` scans the whole `skeleton.json` as raw text (key-agnostic) and returns a list of violations (`[]` == clean). Cut-2 adds NO new content vector (no `url()`), so this confirms the new value classes (text-shadow, outline color, background longhands, object-position, `background-clip:text`, transform-style) carry no content signature. No new canary needed — the cut-1 external-url canary already guards redaction.

- [ ] **Step 1: Write the test**

Add to `scripts/test_content_firewall.py` (uses the existing `_clean_bundle` helper + `import content_firewall as cf`):

```python
def test_audit_passes_skeleton_with_cut2_style(tmp_path):
    # Cut-2 resolved values (text-shadow, outline, background longhands, object-position,
    # background-clip:text, transform-style) are content-free -> audit clean. No url().
    d = _clean_bundle(tmp_path)
    sk = {"schema": "probe-skeleton/2", "url": "u",
          "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                     "style": {
                         "text-shadow": "rgb(0, 0, 0) 1px 1px 2px",
                         "outline-style": "solid",
                         "outline-width": "2px",
                         "outline-color": "rgb(1, 2, 3)",
                         "outline-offset": "3px",
                         "background-repeat": "no-repeat",
                         "background-position": "10px 20px",
                         "background-clip": "text",
                         "object-fit": "cover",
                         "object-position": "25% 75%",
                         "overflow-x": "hidden",
                         "transform-style": "preserve-3d",
                         "perspective": "800px",
                         "writing-mode": "vertical-rl"}}]}
    (d / "skeleton.json").write_text(json.dumps(sk, indent=2))
    assert cf.audit_bundle(d) == []
```

- [ ] **Step 2: Run the test**

Run: `cd scripts && python3 -m pytest test_content_firewall.py::test_audit_passes_skeleton_with_cut2_style -v`
Expected: PASS (`audit_bundle` returns `[]`).

- [ ] **Step 3: Commit**

```bash
git add scripts/test_content_firewall.py
git commit -m "test: firewall passes a cut-2-valued skeleton style (no new content vector)"
```

---

### Task 3: bundle_writer round-trip carries cut-2 props

**Files:**
- Test: `scripts/test_bundle_writer.py`

**Context:** `bundle_writer.py` is UNCHANGED — `apply_node_style` is prop-agnostic (it redacts via `_style.redact_node_styles` and attaches the whole dict). This test confirms cut-2 props survive `assemble` (which runs `cf.redact_node`'s content-key blacklist) and reach the bundle intact. `assemble(skeleton, tokens, node_colors, motion_rows, meta_extra, states=None, node_style=None)` returns `{"skeleton": {...}, ...}`; node style is at `bundle["skeleton"]["nodes"][i]["style"]`. Uses `import bundle_writer as bw`.

- [ ] **Step 1: Write the test**

Add to `scripts/test_bundle_writer.py`:

```python
def test_assemble_attaches_cut2_style_surviving_redact_node():
    # Cut-2 props (no url()) survive assemble's redact_node + reach the bundle intact.
    skeleton = {"schema": "probe-skeleton/2", "url": "u",
                "viewport": {"w": 100, "h": 100, "dpr": 1}, "page": {"w": 100, "h": 100},
                "nodes": [{"id": 0, "role": "box", "bbox": {"x": 0, "y": 0, "w": 10, "h": 10},
                           "token_ref": {"bg": None, "fg": None, "border": None},
                           "anim_ref": None}]}
    node_style = {0: {"text-shadow": "rgb(0, 0, 0) 1px 1px 2px", "object-fit": "cover",
                      "outline-style": "solid", "background-repeat": "no-repeat",
                      "transform-style": "preserve-3d"}}
    bundle = bw.assemble(skeleton, {"palette": {}}, {}, [], meta_extra={}, node_style=node_style)
    style = bundle["skeleton"]["nodes"][0]["style"]
    assert style["text-shadow"] == "rgb(0, 0, 0) 1px 1px 2px"
    assert style["object-fit"] == "cover"
    assert style["outline-style"] == "solid"
    assert style["background-repeat"] == "no-repeat"
    assert style["transform-style"] == "preserve-3d"
```

- [ ] **Step 2: Run the test**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_assemble_attaches_cut2_style_surviving_redact_node -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_bundle_writer.py
git commit -m "test: bundle_writer round-trips cut-2 style props through redact_node"
```

---

### Task 4: extend the offline host gate with cut-2 nodes

**Files:**
- Modify: `fixtures/css_style/run_css_style.py` (`_PAGE` + `_check`)

**Context:** This is the deterministic offline gate (one local server serves page + a same-host "external" PNG). It is run on host Bash by the controller (`dangerouslyDisableSandbox=true`), NOT in pytest. The existing `#mark`/`#ext` nodes + their cut-1 assertions MUST be left intact. Add cut-2 nodes and assert (a) non-default cut-2 props populate, AND (b) default-valued props are suppressed (no node carries a Chrome default; the outline group never appears without `outline-style`).

- [ ] **Step 1: Add cut-2 nodes to `_PAGE`**

In `fixtures/css_style/run_css_style.py`, in the `_PAGE` `<style>` block, add these rules after the `#ext { ... }` rule:

```css
  #cut2 { width: 120px; height: 120px;
          outline: 3px solid rgb(7,8,9); outline-offset: 2px;
          text-shadow: rgb(0,0,0) 2px 2px 4px;
          background-image: linear-gradient(90deg, rgb(1,1,1), rgb(2,2,2));
          background-repeat: no-repeat; background-position: 10px 20px;
          overflow: hidden; transform-style: preserve-3d; perspective: 600px;
          writing-mode: vertical-rl; }
  #img2 { width: 80px; height: 80px; object-fit: cover; object-position: 25% 75%; }
  #plain { width: 50px; height: 50px; }
```

And add these elements to the page body (after `<div id=ext></div>`):

```html
<div id=cut2></div>
<img id=img2 src="/ext.png">
<div id=plain></div>
```

(Note: the existing `_PAGE` keeps its `-webkit-backdrop-filter` declaration — that is the PAGE's own CSS; cut 1 dropped only its CAPTURE.)

- [ ] **Step 2: Add cut-2 assertions to `_check`**

In `_check`, AFTER the existing external-bg `ext` block and BEFORE the final `print("style ok: ...")` + `return True`, insert:

```python
    # cut-2: the #cut2 node (outline-style:solid is its fingerprint) carries the new props
    c2 = next((n for n in styled if n["style"].get("outline-style") == "solid"), None)
    if c2 is None:
        print("GATE FAIL: no cut-2 node carried outline-style:solid")
        return False
    s2 = c2["style"]
    ok2 = (s2.get("outline-width") == "3px"
           and "rgb" in (s2.get("outline-color") or "")
           and s2.get("outline-offset") == "2px"
           and "rgb" in (s2.get("text-shadow") or "")
           and s2.get("background-repeat") == "no-repeat"
           and s2.get("background-position") == "10px 20px"
           and s2.get("overflow-x") == "hidden" and s2.get("overflow-y") == "hidden"
           and s2.get("transform-style") == "preserve-3d"
           and s2.get("perspective") == "600px"
           and s2.get("writing-mode") == "vertical-rl")
    if not ok2:
        print("GATE FAIL: cut-2 style incomplete:", json.dumps(s2))
        return False
    # object-fit/position on the replaced img
    im = next((n for n in styled if n["style"].get("object-fit") == "cover"), None)
    if im is None or im["style"].get("object-position") != "25% 75%":
        print("GATE FAIL: object-fit/object-position not captured")
        return False
    # default-suppression: NO node may carry a Chrome-default value, and the outline
    # group must never appear without outline-style (proves the gate/map are load-bearing).
    for n in styled:
        sd = n["style"]
        for prop, dval in (("background-repeat", "repeat"), ("writing-mode", "horizontal-tb"),
                           ("transform-style", "flat"), ("overflow-x", "visible"),
                           ("object-fit", "fill"), ("direction", "ltr")):
            if sd.get(prop) == dval:
                print(f"GATE FAIL: default value leaked: {prop}={dval}")
                return False
        if "outline-style" not in sd and ("outline-width" in sd or "outline-color" in sd):
            print("GATE FAIL: outline group present without outline-style:", json.dumps(sd))
            return False
    print("cut-2 ok: outline group + text-shadow + bg longhands + object-fit + 3d kept; defaults suppressed")
```

- [ ] **Step 3: Controller runs the gate (host Bash)**

Run: `cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/css_style/run_css_style.py`
(host Bash, `dangerouslyDisableSandbox=true`)
Expected: stdout ends `GATE PASS: ...`; exit code 0. If FAIL, fix the implementation (not the assertion) and re-run.

- [ ] **Step 4: Commit**

```bash
git add fixtures/css_style/run_css_style.py
git commit -m "test: extend css-style host gate with cut-2 props + default-suppression checks"
```

---

### Task 5: real-site validation tool + one-off run

**Files:**
- Create: `fixtures/css_style/validate_realsite.py`

**Context:** Flag 2 from cut 1 — end-to-end coverage was synthetic-only. This adds a one-off real-site validation, run by the controller on host CDP. It is NOT in the committed suite (nondeterministic). It MUST be content-free: print ONLY prop NAMES, occurrence COUNTS, node counts, and the audit verdict — never resolved values, text, or full URLs. `bundle_writer.write_bundle` raises on any content leak (subprocess returncode != 0), so a clean run proves the firewall passed on real data.

- [ ] **Step 1: Create the validation tool**

Create `fixtures/css_style/validate_realsite.py`:

```python
#!/usr/bin/env python3
"""One-off real-site validation for Regime-1 CSS cut-2 (NOT in the committed suite —
nondeterministic). Drives the full pipeline (web_skeleton -> bundle_writer) against a
public --url and prints ONLY content-free signal: which cut-2 props populated (NAMES +
occurrence COUNTS), node counts, and the bundle audit verdict. NO page content, NO
resolved values, NO full URL is printed or persisted (host only) — IP firewall +
content-free invariant. bundle_writer.write_bundle RAISES on any leak, so a clean exit
proves the firewall passed on real data. Host Bash (CDP):
    python3 fixtures/css_style/validate_realsite.py --url https://example.com"""
import argparse
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
CUT2 = [
    "background-size", "background-position", "background-repeat", "background-clip",
    "background-origin", "background-attachment", "background-blend-mode",
    "outline-style", "outline-width", "outline-color", "outline-offset",
    "text-shadow", "overflow-x", "overflow-y", "aspect-ratio",
    "object-fit", "object-position",
    "text-transform", "text-decoration-line", "font-variant", "writing-mode", "direction",
    "perspective", "transform-style", "rotate", "scale", "translate",
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    args = ap.parse_args()
    host = args.url.split("/")[2] if "//" in args.url else args.url
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        sk, tok, bundle = td / "sk.json", td / "tokens.json", td / "bundle"
        tok.write_text(json.dumps({"palette": {}}))
        r = subprocess.run([sys.executable, str(SCRIPTS / "web_skeleton.py"),
                            "--url", args.url, "--out", str(sk)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=150)
        if r.returncode != 0:
            print("web_skeleton FAILED:", r.stderr[-300:])
            return 1
        r = subprocess.run([sys.executable, str(SCRIPTS / "bundle_writer.py"),
                            "--skeleton", str(sk), "--tokens", str(tok), "--out", str(bundle)],
                           cwd=str(SCRIPTS), capture_output=True, text=True, timeout=150)
        audit_ok = r.returncode == 0
        disk = json.loads((bundle / "skeleton.json").read_text()) if audit_ok else {}
        nodes = disk.get("nodes") or []
        cnt = Counter()
        for n in nodes:
            for p in (n.get("style") or {}):
                if p in CUT2:
                    cnt[p] += 1
        print(f"host: {host}")
        print(f"nodes: {len(nodes)}  styled: {sum(1 for n in nodes if n.get('style'))}")
        print(f"bundle audit: {'CLEAN (write_bundle did not raise)' if audit_ok else 'FAILED'}")
        print("cut-2 props populated (name: node-count):")
        for p in CUT2:
            if cnt[p]:
                print(f"  {p}: {cnt[p]}")
        if not audit_ok:
            print("bundle_writer stderr tail:", r.stderr[-300:])
    return 0 if audit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Controller runs the validation once (host Bash)**

Run (host Bash, `dangerouslyDisableSandbox=true`): pick one public, non-login, CSS-rich page (e.g. a documentation or marketing page) and run
`cd /Users/unfazed-mac/Developer/artificial_intelligence/skills/probe-runner && python3 fixtures/css_style/validate_realsite.py --url <chosen-public-url>`
Expected: `bundle audit: CLEAN`, exit 0, and several cut-2 props with non-zero node counts. Capture the content-free summary (host + counts + verdict) for the §C9-R-P7 results doc. If `web_skeleton` fails on the chosen site (e.g. canvas-substrate site), pick a different DOM-tier page.

- [ ] **Step 3: Commit**

```bash
git add fixtures/css_style/validate_realsite.py
git commit -m "test: add content-free real-site validation tool for cut-2 props"
```

---

### Task 6: results docs

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (add `## §C9-R-P7` results)
- Modify: `docs/research/css-capture-completeness.md` (top-of-file update note)
- Modify: `docs/plans/regime1-css-property-coverage-cut2-design.md` (status → landed)

**Context:** Record the landing honestly, including the real-site validation summary (content-free) from Task 5.

- [ ] **Step 1: Add the §C9-R-P7 results section**

Append to `docs/plans/probe-runner-engine-capture-gaps.md` a new section mirroring the §C9-R-P6 format. Include: the 27 props landed; the 12-entry default map + outline-group gate (with the `outline-width:1.5px` probe finding); `_style.py`/`bundle_writer.py` unchanged (no new url() vector); verification (unit + firewall + round-trip + extended synthetic gate GATE PASS + the real-site validation summary: host, node counts, which cut-2 props populated, audit CLEAN); honest ceilings (resolved-but-unparsed; single-engine defaults); and the remaining roadmap (Regime 2 pseudo-elements; Regime 3 responsive/theme/interactive; native).

- [ ] **Step 2: Update the research checklist note**

At the top of `docs/research/css-capture-completeness.md`, add a `> **Update 2026-05-31 — Regime-1 cut 2 LANDED**` note listing the new prop families now captured and pointing to §C9-R-P7.

- [ ] **Step 3: Flip the design-spec status**

In `docs/plans/regime1-css-property-coverage-cut2-design.md`, change the `**Status:**` line to `landed (2026-05-31) — see capture-gaps §C9-R-P7.`

- [ ] **Step 4: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md docs/research/css-capture-completeness.md docs/plans/regime1-css-property-coverage-cut2-design.md
git commit -m "docs: record Regime-1 CSS cut-2 landing (§C9-R-P7) + research/spec status"
```

---

## Self-Review

**Spec coverage:** 27-prop set → Task 1 (WANT_STYLES/STYLE_PROPS). Default map + outline gate → Task 1 (`_STYLE_DEFAULTS`/`_OUTLINE_GATED`/`_collect_style`). `_style`/`bundle_writer` unchanged → asserted by Tasks 2/3 (test-only). Firewall clean → Task 2. Round-trip → Task 3. Synthetic host gate → Task 4. Real-site validation (Flag 2) → Task 5. Parallel-index pin + subset guard → auto-covered (Task 1 Step 7). Docs/§C9-R-P7 → Task 6. No gaps.

**Placeholder scan:** every code step shows complete code; the one `<chosen-public-url>` in Task 5 Step 2 is a deliberate human-choice runtime arg (a real site, picked at run time), not a code placeholder.

**Type consistency:** `_collect_style`, `_STYLE_DEFAULTS`, `_OUTLINE_GATED`, `STYLE_PROPS`, `WANT_STYLES` names match across Task 1. `cf.audit_bundle(d)` and `bundle["skeleton"]["nodes"][i]["style"]` match the existing cut-1 test patterns. `assemble(... node_style=...)` signature matches `bundle_writer.py`.
