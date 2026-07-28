# G3b Cross-Route Token Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a separate pass that reads a G3a capture and emits one content-free unified design system (`design_system.json`).

**Architecture:** Pure core `scripts/_merge.py` (no I/O/CDP, unit-tested) consumes per-route `tokens.json` dicts; thin CLI `scripts/site_merge.py` loads a capture dir, calls the core, writes the artifact, and re-audits it through the unchanged `content_firewall.audit_bundle`. Grounded by the recurrence probe (gaps doc §C9-R-G3a-probe): merge on role keys, report palette exact AND clustered, frequency-annotated core+deltas, per-role.

**Tech Stack:** Python 3 (stdlib), pytest. Reuses `web_tokens.cluster_colors` / `parse_color`, `content_firewall.audit_bundle`, `_common.die`/`emit_json`. Spec: `docs/plans/cross-route-token-merge-g3b-design.md`.

---

## File Structure

- **Create `scripts/_merge.py`** — pure merge core. `_freq_entries`, `merge_scalars`, `_exact_role`, `_clustered_role`, `merge_palette`, `build_design_system`. No I/O, no CDP. Tasks 1–4.
- **Create `scripts/test_merge.py`** — pure-core units. Tasks 1–4.
- **Create `scripts/site_merge.py`** — CLI: load capture → build → write → firewall backstop. Task 5.
- **Create `scripts/test_site_merge.py`** — CLI units incl. firewall canary. Task 5.
- **Create `fixtures/site/validate_merge.py`** — host content-free real-site harness (NOT in unit suite). Task 6.
- **No existing file is modified.** `web_tokens.py`, `content_firewall.py`, `site_capture.py`, `_common.py` are imported, never changed.

Tests run from the `scripts/` directory: `cd scripts && python3 -m pytest -q`.

---

### Task 1: `_merge.py` core — frequency entries + scalar merge

**Files:**
- Create: `scripts/_merge.py`
- Test: `scripts/test_merge.py`

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_merge.py
"""Pure cross-route token-merge core units (G3b). No CDP."""


def test_freq_entries_core_and_sort():
    import _merge
    entries = _merge._freq_entries({"a": ["r00", "r01"], "b": ["r01"]}, n=2)
    assert entries[0] == {"value": "a", "routes": 2,
                          "route_ids": ["r00", "r01"], "core": True}
    assert entries[1] == {"value": "b", "routes": 1,
                          "route_ids": ["r01"], "core": False}


def test_freq_entries_dedups_route_ids():
    import _merge
    e = _merge._freq_entries({"a": ["r00", "r00", "r01"]}, n=2)
    assert e[0]["route_ids"] == ["r00", "r01"] and e[0]["routes"] == 2


def test_merge_scalars_freq_and_core():
    import _merge
    rows = [
        ("r00", {"type_scale": [16, 24], "weights": [400]}),
        ("r01", {"type_scale": [16], "weights": [400, 700]}),
    ]
    out = _merge.merge_scalars(rows)
    ts = {e["value"]: e for e in out["type_scale"]}
    assert ts[16]["core"] is True and ts[16]["routes"] == 2
    assert ts[24]["core"] is False and ts[24]["route_ids"] == ["r00"]
    # all six categories always present, even when empty
    assert set(out) == {"type_scale", "weights", "families",
                        "spacing", "radii", "shadows"}
    assert out["radii"] == []
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_merge'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_merge.py
"""Pure cross-route token-merge core (G3b). No I/O, no CDP — unit-testable in
isolation (mirrors _site.py / _theme.py). Consumes per-route tokens.json dicts and
produces a content-free unified design system (schema probe-runner/design-system@1).
Grounded by the recurrence probe (gaps doc §C9-R-G3a-probe): merge on role keys not
raw values; report palette exact AND clustered; frequency-annotated core + deltas;
measure value recurrence per role."""
import web_tokens as wt

DESIGN_SCHEMA = "probe-runner/design-system@1"
PALETTE_ROLES = ["background", "surface", "fg-primary", "fg-muted", "accent", "border"]
SCALAR_CATS = ["type_scale", "weights", "families", "spacing", "radii", "shadows"]


def _freq_entries(value_to_route_ids, n):
    """value_to_route_ids: {value: [route_id, ...]}. Return frequency-annotated
    entries sorted by route count desc then value. `core` iff present in all N."""
    entries = []
    for value, ids in value_to_route_ids.items():
        sids = sorted(set(ids))
        entries.append({"value": value, "routes": len(sids),
                        "route_ids": sids, "core": len(sids) == n})
    entries.sort(key=lambda e: (-e["routes"], str(e["value"])))
    return entries


def merge_scalars(per_route_scalars):
    """per_route_scalars: [(route_id, tokens_dict)]. Exact frequency per category."""
    n = len(per_route_scalars)
    out = {}
    for cat in SCALAR_CATS:
        m = {}
        for rid, scalars in per_route_scalars:
            for v in (scalars.get(cat) or []):
                m.setdefault(v, []).append(rid)
        out[cat] = _freq_entries(m, n)
    return out
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_merge.py scripts/test_merge.py
git commit -m "feat: add G3b merge core frequency entries + scalar merge"
```

---

### Task 2: Palette exact merge

**Files:**
- Modify: `scripts/_merge.py`
- Test: `scripts/test_merge.py`

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_merge.py
def test_exact_role_groups_by_value():
    import _merge
    rows = [("r00", {"accent": "#3b82f6"}),
            ("r01", {"accent": "#3b82f6"}),
            ("r02", {"accent": "#ef4444"})]
    m = _merge._exact_role(rows, "accent")
    assert m == {"#3b82f6": ["r00", "r01"], "#ef4444": ["r02"]}


def test_exact_role_skips_null_and_missing():
    import _merge
    rows = [("r00", {"border": None}), ("r01", {})]
    assert _merge._exact_role(rows, "border") == {}


def test_merge_palette_exact_core_and_delta():
    import _merge
    rows = [("r00", {"background": "#fff", "accent": "#3b82f6"}),
            ("r01", {"background": "#fff", "accent": "#ef4444"})]
    pal = _merge.merge_palette(rows, cluster_tol=8)
    assert set(pal) == set(_merge.PALETTE_ROLES)        # all roles present
    bg = pal["background"]["exact"]
    assert len(bg) == 1 and bg[0]["value"] == "#fff" and bg[0]["core"] is True
    acc = {e["value"]: e for e in pal["accent"]["exact"]}
    assert acc["#3b82f6"]["core"] is False and acc["#ef4444"]["core"] is False
    assert pal["surface"]["exact"] == []                # absent role -> empty
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: FAIL — `AttributeError: module '_merge' has no attribute '_exact_role'`.

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/_merge.py`:

```python
def _exact_role(per_route_palettes, role):
    """{hex: [route_id, ...]} for one role over routes carrying a non-null value."""
    m = {}
    for rid, pal in per_route_palettes:
        v = pal.get(role)
        if v:
            m.setdefault(v, []).append(rid)
    return m


def merge_palette(per_route_palettes, cluster_tol):
    """per_route_palettes: [(route_id, {role: hex|None})]. Per role: exact + clustered
    frequency entries. (clustered filled in Task 3.)"""
    out = {}
    for role in PALETTE_ROLES:
        out[role] = {
            "exact": _freq_entries(_exact_role(per_route_palettes, role),
                                   len(per_route_palettes)),
            "clustered": [],
        }
    return out
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_merge.py scripts/test_merge.py
git commit -m "feat: add G3b exact per-role palette merge"
```

---

### Task 3: Palette clustered merge (reuse `cluster_colors`)

**Files:**
- Modify: `scripts/_merge.py`
- Test: `scripts/test_merge.py`

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_merge.py
def test_clustered_merges_within_tol():
    import _merge
    # #0b0b0b vs #0c0c0c differ by 1 per channel -> within tol 8 -> one cluster
    rows = [("r00", {"background": "#0b0b0b"}), ("r01", {"background": "#0c0c0c"})]
    cl = _merge.merge_palette(rows, cluster_tol=8)["background"]["clustered"]
    assert len(cl) == 1
    assert cl[0]["routes"] == 2 and cl[0]["core"] is True
    # exact view still distinguishes them
    assert len(_merge.merge_palette(rows, 8)["background"]["exact"]) == 2


def test_clustered_separate_beyond_tol():
    import _merge
    rows = [("r00", {"accent": "#0b0b0b"}), ("r01", {"accent": "#f5f5f5"})]
    cl = _merge.merge_palette(rows, cluster_tol=8)["accent"]["clustered"]
    assert len(cl) == 2 and all(e["core"] is False for e in cl)


def test_clustered_per_role_isolation():
    import _merge
    # identical hex in different roles must never merge across roles
    rows = [("r00", {"accent": "#3b82f6", "border": "#3b82f6"})]
    pal = _merge.merge_palette(rows, cluster_tol=8)
    assert len(pal["accent"]["clustered"]) == 1
    assert len(pal["border"]["clustered"]) == 1
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: FAIL — clustered is `[]`, so `len(cl) == 1` fails.

- [ ] **Step 3: Write minimal implementation**

In `scripts/_merge.py`, add `_clustered_role` and use it in `merge_palette`:

```python
def _clustered_role(per_route_palettes, role, tol):
    """Reuse web_tokens.cluster_colors for representatives, then assign each route's
    value to the nearest representative within tol (Chebyshev) to recover route_ids
    and core. Per-role: only this role's values are clustered."""
    exact = _exact_role(per_route_palettes, role)          # {hex: [ids]}
    if not exact:
        return []
    # area = route-frequency so the most-frequent shade seeds (and represents) its
    # cluster, matching cluster_colors' deterministic largest-area-first order.
    samples = [(hexv, len(ids)) for hexv, ids in exact.items()]
    reps = [(rep, wt.parse_color(rep)) for rep, _area in wt.cluster_colors(samples, tol=tol)]
    cl = {}
    for hexv, ids in exact.items():
        rgb = wt.parse_color(hexv)
        best, best_d = None, None
        for rep, rrgb in reps:
            if rgb is None or rrgb is None:
                continue
            d = max(abs(rgb[i] - rrgb[i]) for i in range(3))
            if d <= tol and (best_d is None or d < best_d):
                best, best_d = rep, d
        key = best if best is not None else hexv
        cl.setdefault(key, []).extend(ids)
    return _freq_entries(cl, len(per_route_palettes))
```

Replace the `"clustered": []` line in `merge_palette` with:

```python
            "clustered": _clustered_role(per_route_palettes, role, cluster_tol),
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_merge.py scripts/test_merge.py
git commit -m "feat: add G3b clustered per-role palette merge"
```

---

### Task 4: `build_design_system` assembly

**Files:**
- Modify: `scripts/_merge.py`
- Test: `scripts/test_merge.py`

- [ ] **Step 1: Write the failing tests**

```python
# append to scripts/test_merge.py
def test_build_design_system_shape():
    import _merge
    per_route = [
        ("r00", {"palette": {"background": "#fff", "accent": "#3b82f6"},
                 "type_scale": [16, 24]}),
        ("r01", {"palette": {"background": "#fff", "accent": "#ef4444"},
                 "type_scale": [16]}),
    ]
    ds = _merge.build_design_system(per_route, hosts=["e.com"], cluster_tol=8)
    assert ds["schema"] == "probe-runner/design-system@1"
    assert ds["hosts"] == ["e.com"]
    assert ds["merged_route_count"] == 2
    assert ds["route_ids"] == ["r00", "r01"]
    assert ds["cluster_tol"] == 8
    assert set(ds["palette"]) == set(_merge.PALETTE_ROLES)
    assert set(ds["scalars"]) == set(_merge.SCALAR_CATS)
    bg = ds["palette"]["background"]["exact"]
    assert bg[0]["value"] == "#fff" and bg[0]["core"] is True


def test_build_design_system_n1_all_core():
    import _merge
    ds = _merge.build_design_system(
        [("r00", {"palette": {"accent": "#3b82f6"}, "spacing": [8]})],
        hosts=["e.com"], cluster_tol=8)
    assert ds["merged_route_count"] == 1
    assert ds["palette"]["accent"]["exact"][0]["core"] is True
    assert ds["scalars"]["spacing"][0]["core"] is True
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: FAIL — `AttributeError: module '_merge' has no attribute 'build_design_system'`.

- [ ] **Step 3: Write minimal implementation**

Append to `scripts/_merge.py`:

```python
def build_design_system(per_route, hosts, cluster_tol):
    """per_route: [(route_id, tokens_dict)] for the merged (ok, readable) routes.
    Returns the full content-free design-system dict (spec §3.4)."""
    palettes = [(rid, (t.get("palette") or {})) for rid, t in per_route]
    return {
        "schema": DESIGN_SCHEMA,
        "hosts": hosts,
        "merged_route_count": len(per_route),
        "route_ids": [rid for rid, _ in per_route],
        "cluster_tol": cluster_tol,
        "palette": merge_palette(palettes, cluster_tol),
        "scalars": merge_scalars(per_route),
    }
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_merge.py scripts/test_merge.py
git commit -m "feat: add G3b build_design_system assembly"
```

---

### Task 4b: Families exempt-key fix (content-free hardening)

**Why:** `design_system.json` nests each merged token in a freq-entry dict. `content_firewall._walk_strings` keys a string by its **immediate dict key**, and the firewall exempts `{family, families, font, font_family, fontFamily}` from prose detection (font stacks legitimately look like prose). With the value field named `"value"`, a long keyword-less font stack (e.g. `"Helvetica Neue, Arial, Liberation Sans"`, >24 chars, no `sans-serif`/`serif`/`monospace`) would FALSE-POSITIVE the audit (`exit 3`) — even though it passes in `tokens.json` (stored under the exempt `families` key). Fix: the `families` category emits its value under the exempt key `"family"`. Palette (hex) and numeric scalars are never prose-shaped, so they keep `"value"`. Firewall is UNCHANGED.

**Files:** Modify `scripts/_merge.py`; modify `scripts/test_merge.py`.

- [ ] **Step 1: Write the failing test** (append to `scripts/test_merge.py`):

```python
def test_merge_scalars_families_uses_family_key():
    import _merge
    stack = "Helvetica Neue, Arial, Liberation Sans"
    out = _merge.merge_scalars([("r00", {"families": [stack]}),
                                ("r01", {"families": [stack]})])
    fam = out["families"][0]
    assert "family" in fam and "value" not in fam
    assert fam["family"] == stack and fam["core"] is True
    # every other category keeps "value"
    ts = _merge.merge_scalars([("r00", {"type_scale": [16]})])["type_scale"][0]
    assert "value" in ts and "family" not in ts
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd scripts && python3 -m pytest test_merge.py::test_merge_scalars_families_uses_family_key -q`
Expected: FAIL — families entry has `"value"`, not `"family"`.

- [ ] **Step 3: Implementation.** In `scripts/_merge.py`, give `_freq_entries` a `key` parameter and have `merge_scalars` pass `"family"` for the families category.

Replace `_freq_entries` with:

```python
def _freq_entries(value_to_route_ids, n, key="value"):
    """value_to_route_ids: {value: [route_id, ...]}. Return frequency-annotated
    entries sorted by route count desc then value. `core` iff present in all N. `key`
    names the value field: "value" everywhere except the families scalar category, which
    uses "family" so font stacks stay under a content-firewall-exempt key (parity with
    how tokens.json stores them)."""
    entries = []
    for value, ids in value_to_route_ids.items():
        sids = sorted(set(ids))
        entries.append({key: value, "routes": len(sids),
                        "route_ids": sids, "core": len(sids) == n})
    entries.sort(key=lambda e: (-e["routes"], str(e[key])))
    return entries
```

In `merge_scalars`, replace the line `out[cat] = _freq_entries(m, n)` with:

```python
        out[cat] = _freq_entries(m, n, key="family" if cat == "families" else "value")
```

- [ ] **Step 4: Run to verify all pass**

Run: `cd scripts && python3 -m pytest test_merge.py -q`
Expected: PASS (12 tests total — the new test plus the prior 11, which all use `"value"` and are unaffected).

- [ ] **Step 5: Commit**

```bash
git add scripts/_merge.py scripts/test_merge.py
git commit -m "fix: emit G3b families under firewall-exempt key to avoid false-positive audit"
```

---

### Task 5: `site_merge.py` CLI + firewall backstop

**Files:**
- Create: `scripts/site_merge.py`
- Test: `scripts/test_site_merge.py`

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_site_merge.py
"""CLI units for cross-route token merge (G3b). No CDP."""
import json
import sys
from pathlib import Path

import pytest


def _write_capture(root, routes):
    """routes: {route_id: tokens_dict_or_None}. None -> ok route with NO tokens.json
    (unreadable). Writes site.json + routes/<id>/tokens.json."""
    rows = []
    for rid, toks in routes.items():
        rdir = root / "routes" / rid
        rdir.mkdir(parents=True, exist_ok=True)
        if toks is not None:
            (rdir / "tokens.json").write_text(json.dumps(toks))
        rows.append({"route_id": rid, "url": "https://e.com/%s" % rid,
                     "bundle": "routes/%s" % rid, "ok": True})
    site = {"schema": "probe-runner/site-manifest@1", "hosts": ["e.com"],
            "route_count": len(rows), "ok_count": len(rows), "routes": rows}
    (root / "site.json").write_text(json.dumps(site))


def _run(monkeypatch, argv):
    import site_merge
    monkeypatch.setattr(sys, "argv", ["site_merge.py"] + argv)
    return site_merge.main()


def test_site_merge_writes_artifact(tmp_path, monkeypatch):
    _write_capture(tmp_path, {
        "r00": {"palette": {"background": "#fff", "accent": "#3b82f6"},
                "type_scale": [16, 24]},
        "r01": {"palette": {"background": "#fff", "accent": "#ef4444"},
                "type_scale": [16]},
    })
    rc = _run(monkeypatch, ["--site", str(tmp_path)])
    assert rc == 0
    ds = json.loads((tmp_path / "design_system.json").read_text())
    assert ds["schema"] == "probe-runner/design-system@1"
    assert ds["merged_route_count"] == 2
    bg = ds["palette"]["background"]["exact"]
    assert bg[0]["value"] == "#fff" and bg[0]["core"] is True


def test_site_merge_skips_unreadable_route(tmp_path, monkeypatch):
    _write_capture(tmp_path, {
        "r00": {"palette": {"accent": "#3b82f6"}},
        "r01": None,   # ok row but missing tokens.json -> skipped, not fatal
    })
    rc = _run(monkeypatch, ["--site", str(tmp_path)])
    assert rc == 0
    ds = json.loads((tmp_path / "design_system.json").read_text())
    assert ds["merged_route_count"] == 1 and ds["route_ids"] == ["r00"]


def test_site_merge_zero_mergeable_exits_2(tmp_path, monkeypatch):
    # all routes ok=False -> nothing to merge
    rows = [{"route_id": "r00", "url": "https://e.com/", "bundle": "routes/r00",
             "ok": False, "error_kind": "skeleton_failed"}]
    site = {"schema": "probe-runner/site-manifest@1", "hosts": ["e.com"],
            "route_count": 1, "ok_count": 0, "routes": rows}
    (tmp_path / "site.json").write_text(json.dumps(site))
    with pytest.raises(SystemExit) as ei:
        _run(monkeypatch, ["--site", str(tmp_path)])
    assert ei.value.code == 2


def test_site_merge_canary_palette_prose_trips_firewall(tmp_path, monkeypatch, capsys):
    # prose injected into a PALETTE value flows into design_system.json under a "value"
    # key (NOT firewall-exempt) -> the UNCHANGED content_firewall trips -> exit 3, no
    # sample printed. Written to an ISOLATED empty --out dir so the trip is attributable
    # to design_system.json itself, proving the NEW persistence surface is scanned.
    # (Families is deliberately NOT used here: it sits under the exempt "family" key, so
    # prose there is allowed -- same as tokens.json. See the regression test below.)
    prose = "The quick brown fox jumps over the lazy dog repeatedly in this paragraph."
    _write_capture(tmp_path, {
        "r00": {"palette": {"accent": prose}},
    })
    iso = tmp_path / "iso"
    iso.mkdir()
    out = iso / "design_system.json"
    rc = _run(monkeypatch, ["--site", str(tmp_path), "--out", str(out)])
    assert rc == 3
    captured = capsys.readouterr().out
    assert "content_audit_failed" in captured
    assert prose not in captured and "sample" not in captured


def test_site_merge_families_long_stack_clean(tmp_path, monkeypatch):
    # Regression: a long keyword-less font stack (>24 chars, no sans-serif/serif/etc.)
    # passes tokens.json audit under the exempt "families" key. In design_system.json it
    # must ALSO pass -- the merge emits it under the exempt "family" key (Task 4b). Without
    # that fix this stack would false-positive exit 3.
    stack = "Helvetica Neue, Arial, Liberation Sans"
    _write_capture(tmp_path, {"r00": {"families": [stack]}})
    iso = tmp_path / "iso"
    iso.mkdir()
    out = iso / "design_system.json"
    rc = _run(monkeypatch, ["--site", str(tmp_path), "--out", str(out)])
    assert rc == 0
    ds = json.loads(out.read_text())
    assert ds["scalars"]["families"][0]["family"] == stack
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd scripts && python3 -m pytest test_site_merge.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'site_merge'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/site_merge.py
#!/usr/bin/env python3
"""Cross-route token merge (G3b). Read a G3a capture (site.json + routes/<id>/
tokens.json across N routes) and emit a content-free unified design system
(design_system.json, schema probe-runner/design-system@1).

A SEPARATE pass over an existing capture — site_capture is unchanged, and the content
firewall is unchanged: the artifact is the same token surface tokens.json already
persists (hex values, numeric scales, role/category names, counts, positional route
ids), re-audited through content_firewall.audit_bundle as a backstop. Failure paths
print only error kind / violation count — never a content sample, never subprocess stderr.

    python3 scripts/site_merge.py --site site_out [--out design_system.json] [--cluster-tol 8]
"""
import argparse
import json
from pathlib import Path

import content_firewall as cf
import _merge
from _common import die, emit_json


def _load_routes(site_dir):
    """Return (per_route, hosts). per_route = [(route_id, tokens_dict)] for ok routes
    with a readable tokens.json. An unreadable route is skipped, not fatal (mirrors
    G3a per-route isolation)."""
    try:
        site = json.loads((site_dir / "site.json").read_text())
    except (OSError, ValueError):
        die("cannot read site.json under %s" % site_dir)
    hosts = site.get("hosts") or []
    per_route = []
    for r in site.get("routes", []):
        if not r.get("ok"):
            continue
        tok = site_dir / "routes" / r["route_id"] / "tokens.json"
        try:
            per_route.append((r["route_id"], json.loads(tok.read_text())))
        except (OSError, ValueError):
            continue
    return per_route, hosts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", required=True, help="G3a capture dir (contains site.json)")
    ap.add_argument("--out", help="output path (default <site>/design_system.json). The "
                    "firewall backstop audits the OUTPUT'S PARENT dir, so point --out at "
                    "the capture dir or an isolated/empty path -- a populated unrelated "
                    "dir would be over-scanned and could false-positive exit 3.")
    ap.add_argument("--cluster-tol", dest="cluster_tol", type=int, default=8,
                    help="Chebyshev ΔRGB tolerance for the clustered palette view")
    args = ap.parse_args()

    site_dir = Path(args.site)
    out = Path(args.out) if args.out else site_dir / "design_system.json"

    per_route, hosts = _load_routes(site_dir)
    if not per_route:
        die("no mergeable routes")

    ds = _merge.build_design_system(per_route, hosts, args.cluster_tol)
    out.write_text(json.dumps(ds, indent=2, ensure_ascii=False))

    # Backstop: re-audit through the UNCHANGED firewall. audit_bundle rglobs the dir
    # containing the artifact (and, when out is in the capture dir, the route bundles).
    viol = cf.audit_bundle(out.parent)
    if viol:
        emit_json({"ok": False, "error": "content_audit_failed",
                   "out": str(out), "violations": len(viol)})
        return 3
    emit_json({"ok": True, "out": str(out),
               "merged_route_count": ds["merged_route_count"]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run to verify they pass**

Run: `cd scripts && python3 -m pytest test_site_merge.py -q`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/site_merge.py scripts/test_site_merge.py
git commit -m "feat: add G3b site_merge CLI with firewall backstop"
```

---

### Task 6: Host real-site validation harness (write + static-check only)

**Files:**
- Create: `fixtures/site/validate_merge.py`

> This harness needs a CDP browser; the implementer WRITES it and static-checks it
> only (`python3 -c "import ast; ast.parse(open(PATH).read())"`). The CONTROLLER runs
> it on host Bash against real sites in the after-tasks. There is no unit test.

- [ ] **Step 1: Write the harness**

```python
# fixtures/site/validate_merge.py
#!/usr/bin/env python3
"""Content-free real-site validation harness for G3b cross-route token merge. Captures
a real multi-route site with site_capture (host CDP) into a tempdir, runs site_merge,
asserts the firewall backstop is CLEAN, and prints content-free merge stats (per-role
core/exact/clustered COUNTS, per-scalar core/distinct COUNTS). NEVER echoes token
values, page content, or subprocess stderr. NOT in the unit suite (needs a browser).

    python3 fixtures/site/validate_merge.py --urls "https://www.python.org/,https://www.python.org/about/" --cdp-port 9222
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def _run(cmd):
    # Content-free: return rc only; never surface subprocess stderr.
    return subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True).returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--urls", help="comma-separated route URLs")
    ap.add_argument("--urls-file")
    ap.add_argument("--cdp-port", dest="cdp_port", type=int, default=9222)
    ap.add_argument("--cluster-tol", dest="cluster_tol", type=int, default=8)
    args = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="g3b_merge_"))
    try:
        cap = [sys.executable, str(SCRIPTS / "site_capture.py"),
               "--out", str(tmp / "site"), "--cdp-port", str(args.cdp_port)]
        if args.urls_file:
            cap += ["--urls-file", args.urls_file]
        elif args.urls:
            cap += ["--urls", args.urls]
        else:
            print("FAIL: need --urls or --urls-file"); return 1
        rc = _run(cap)
        print("site_capture rc:", rc)
        if rc != 0:
            print("FAIL: capture failed"); return 1

        site_dir = tmp / "site"
        rc = _run([sys.executable, str(SCRIPTS / "site_merge.py"),
                   "--site", str(site_dir), "--cluster-tol", str(args.cluster_tol)])
        print("site_merge rc:", rc)
        if rc != 0:
            print("FAIL: merge failed (rc %d)" % rc); return 1

        ds = json.loads((site_dir / "design_system.json").read_text())
        print("hosts:", ds["hosts"], " merged_route_count:", ds["merged_route_count"])
        for role in ds["palette"]:
            ex, cl = ds["palette"][role]["exact"], ds["palette"][role]["clustered"]
            print("  palette.%-11s exact=%d (core %d) | clustered=%d (core %d)" % (
                role, len(ex), sum(e["core"] for e in ex),
                len(cl), sum(e["core"] for e in cl)))
        for cat, entries in ds["scalars"].items():
            print("  scalar.%-12s distinct=%d (core %d)" % (
                cat, len(entries), sum(e["core"] for e in entries)))

        # consistency: clustered distinct <= exact distinct per role
        for role in ds["palette"]:
            assert len(ds["palette"][role]["clustered"]) <= len(ds["palette"][role]["exact"]), role

        sys.path.insert(0, str(SCRIPTS))
        import importlib
        cf = importlib.import_module("content_firewall")
        viol = cf.audit_bundle(site_dir)
        print("site-root firewall audit:", "CLEAN" if not viol else "DIRTY (%d)" % len(viol))
        ok = not viol
        print("GATE PASS" if ok else "GATE FAIL")
        return 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Static-check it parses**

Run: `python3 -c "import ast; ast.parse(open('fixtures/site/validate_merge.py').read()); print('parse OK')"`
Expected: `parse OK`.

- [ ] **Step 3: Commit**

```bash
git add fixtures/site/validate_merge.py
git commit -m "test: add G3b real-site merge validation harness"
```

---

## Controller after-tasks (run after all 6 tasks; NOT for implementer subagents)

The controller runs these on host Bash; implementer subagents do not.

1. **Full unit suite green.** `cd scripts && python3 -m pytest -q` — expect prior 433 + the new `_merge`/`site_merge` tests, all passing. No existing test regresses (no existing file was modified).
2. **Host real-site validation (CDP).** Confirm Chrome is on `:9222` (G3a left one; else `python3 scripts/web_launch.py --status`). Run `python3 fixtures/site/validate_merge.py --urls "https://www.python.org/,https://www.python.org/about/,https://www.python.org/downloads/,https://www.python.org/community/" --cdp-port 9222` and again for `https://www.iana.org/,https://www.iana.org/about,https://www.iana.org/help/example-domains`. Expect `GATE PASS`, site-root audit `CLEAN`, clustered ≤ exact per role.
3. **Container-query / sibling regression.** None expected (web_tokens/content_firewall unchanged), but run any existing host sibling gate the controller used for G3a to confirm no behavioral drift.
4. **Results doc.** Append `## §C9-R-G3b — Results: Cross-route token merge LANDED (<date>)` to `docs/plans/probe-runner-engine-capture-gaps.md` with the real-site merge stats (counts only), and update the roadmap footer (G3b → landed; G3c next).
5. **Final whole-feature review.** Dispatch the final code reviewer over the full G3b diff.
6. **Advisor done-gate**, then report DONE and await a go-signal naming the next rung (G3c). Flag if Chrome `:9222` is still running. **Do not push.**

---

## Self-Review

**1. Spec coverage:**
- §1 architecture (separate pass, `_merge.py`+`site_merge.py`, `--site`/`--out`/`--cluster-tol`, site_capture unchanged) → Tasks 1–5.
- §3.1 `_freq_entries` → Task 1; §3.3 scalars → Task 1; §3.2 exact → Task 2, clustered → Task 3; §3.4 assembly → Task 4.
- §4 CLI (load ok routes, 0→die 2, write, audit backstop exit 3) → Task 5.
- §5 scope (tokens only, descriptive, N=1 valid, N=0 exit 2) → Tasks 4–5 + tests.
- §6 content-free (same surface, unchanged firewall, canary, no sample) → Task 5 canary test + Task 6 audit.
- §7 error codes (die 2 / exit 3 / exit 0) → Task 5.
- §8 testing (all listed unit + canary + harness) → Tasks 1–6.
- §9 verification, §10 ceilings → controller after-tasks 1–2.

**2. Placeholder scan:** No TBD/TODO; every code step shows full code; every command shows expected output. Clear.

**3. Type consistency:** `_freq_entries(value_to_route_ids, n)`, `merge_scalars(per_route_scalars)`, `_exact_role(per_route_palettes, role)`, `_clustered_role(per_route_palettes, role, tol)`, `merge_palette(per_route_palettes, cluster_tol)`, `build_design_system(per_route, hosts, cluster_tol)` — signatures consistent across tasks and matched by tests. Entry shape `{value, routes, route_ids, core}` is uniform. Constants `PALETTE_ROLES` (6), `SCALAR_CATS` (6), `DESIGN_SCHEMA` defined Task 1, reused throughout. CLI `_load_routes`/`main` match Task 5 tests. Harness calls the real `site_capture`/`site_merge` CLIs.

**Standing constraints:** single-line commits, no trailers; stage explicit paths; one commit/task (review fixes their own); no push; all artifacts content-free; plans in `docs/plans/`.
