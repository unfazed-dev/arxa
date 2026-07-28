# G3d chrome-dedup — make losslessness truly by-construction

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix the G3d chrome-dedup so `reconstruct(dedup(skeletons))` is node-set identical to the input on REAL captures (not just synthetic fixtures), by charging EVERY non-template-derived field as a per-instance correction — honoring the module's own "lossless by construction" claim that `_diff_nonpositional` currently violates (it charges only id/parent/z/confidence, dropping `style` and any other unhandled field).

**Root cause + repro:** `docs/plans/g3d-losslessness-gap-found.md` (python.org home vs /about/, node 54/55, per-route `background-image` in `style` dropped).

**Architecture:** Factor a single `_reconstruct_node(...)` used by BOTH `dedup_chrome` (to simulate) and `reconstruct` (to build) — so the dedup-side patch is computed against the exact code path that ships, making losslessness provable. For each instance node: build the template-derived reconstruction `R`, diff `R` vs the real node over the union of keys → `exceptions` (set) for differing/instance-only fields + `drop` for template-only fields. This subsumes `_diff_nonpositional` (id/parent/z/confidence become automatic) and the now-redundant `_vol_presence` tripwire (presence mismatch is charged, not raised). Then fix the reconcile harness to assert real node-set equality (the same `_node_sets_equal` that ships) and recompute savings with the larger charge; re-measure 6 sites honestly against the pre-registered bar.

**Tech Stack:** Python 3 stdlib, pytest. Live re-measurement uses CDP :9222.

**Branch:** continue on `wire-post-processors` (already holds the wiring + both finding docs). The wiring merges together with this fix, per the user's "fix first, then merge both."

---

## Pre-registered honesty commitment (read first)

The original G3d bar (`§C9-R-G3d-dedup`): BUILD iff median per-site pct ≥ 12 ∧ ≥3 sites ≥ 15%. The "RECONCILED 15.5%" gate measured savings that are NOT losslessly achievable (it asserted only `reconstruct(...).keys() == routes.keys()`). After this fix charges the previously-dropped fields, realized savings will be ≤ the current numbers. **Do NOT tune the encoding to preserve the verdict.** If the honest byte-lossless median drops below the bar, record that the G3d BUILD verdict re-opens — a legitimate outcome (Task 5). Chasing the number un-pre-registers the build.

---

## File Structure

- **Modify** `scripts/_chrome_dedup.py`: add `_reconstruct_node` + `_node_patch`; rewrite the per-node charging in `dedup_chrome` and the per-node expansion in `reconstruct`; remove the `_vol_presence` raise and the now-dead `_diff_nonpositional`. Per-instance ref payload gains a `drop` map alongside `exceptions`.
- **Modify** `scripts/site_chrome.py`: `_jsonable` must carry the new `drop` map.
- **Modify** `scripts/test_chrome_dedup.py`: add the synthetic `style`-varies regression + a `drop` (template-only field) regression; confirm existing tests still pass.
- **Create** `scripts/fixtures/g3d_real_chrome.json`: the trimmed REAL failing landmark pair (2 routes), checked in as a regression fixture (already firewalled/content-free).
- **Modify** `scripts/test_chrome_dedup.py` (or a new `scripts/test_chrome_dedup_real.py`): byte-lossless round-trip over the real fixture via id-keyed node equality.
- **Modify** `research/capture-gap-probes/reconcile_g3d_chrome.py`: assert true per-route node-set equality (not `.keys()`); recompute realized savings charging `len(exceptions)+len(drop)`.
- **Modify** `docs/plans/g3d-structural-deltas-chrome-dedup-results.md` + `docs/plans/g3d-losslessness-gap-found.md`: record corrected byte-lossless numbers + verdict.

---

### Task 1: core fix — `_reconstruct_node` + simulate-and-diff charging (set + drop)

**Files:** Modify `scripts/_chrome_dedup.py`, `scripts/test_chrome_dedup.py`.

- [ ] **Step 1: Write the failing tests** (append to `scripts/test_chrome_dedup.py`):

```python
def _styled_nav(base, bg, grad):
    # a nav landmark whose root carries a per-route `style` dict (NOT a keyed field, NOT volatile);
    # `grad` varies per route. Pre-fix: dropped on reconstruct -> lossy.
    n = _nav_route(base, bg)
    n[0]["style"] = {"border-top-width": "1px", "background-image": grad}
    return n


def test_roundtrip_lossless_when_unkeyed_style_varies():
    # two structurally-identical navs differing ONLY in style.background-image must round-trip
    # byte-identical (the bug: style was neither keyed, volatile, nor charged -> dropped).
    r0 = _styled_nav(0, "red", "linear-gradient(a)")
    r1 = _styled_nav(100, "red", "linear-gradient(b)")     # same struct key, different style
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    # the differing style is charged as an exception on the instance node (index 0)
    assert ref["exceptions"].get("0", {}).get("style", {}).get("background-image") == "linear-gradient(b)"
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)              # node-set identical
    assert _by_id(rebuilt["r0"]) == _by_id(r0)


def test_roundtrip_lossless_when_instance_lacks_a_template_field():
    # template (donor r0) node carries `style`; instance (r1) node has NONE -> reconstruct must
    # DROP the template's style, not inherit it. Exercises the `drop` path.
    r0 = _styled_nav(0, "red", "linear-gradient(a)")
    r1 = _nav_route(100, "red")                            # same struct key, NO style at all
    art = D.dedup_chrome({"r0": r0, "r1": r1})
    ref = art["routes"]["r1"]["refs"][0]
    assert "style" in ref["drop"].get("0", [])             # template-only field -> dropped
    rebuilt = D.reconstruct(art)
    assert _by_id(rebuilt["r1"]) == _by_id(r1)             # instance has no style -> rebuilt has none
```

- [ ] **Step 2: Run, verify FAIL**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -k "unkeyed_style or lacks_a_template" -v`
Expected: FAIL — `test_roundtrip_lossless_when_unkeyed_style_varies` rebuilds r1 with r0's gradient (KeyError on `ref["exceptions"]["0"]["style"]` or node-set mismatch); the `drop` test fails on `ref["drop"]` not existing.

- [ ] **Step 3: Implement the core fix** in `scripts/_chrome_dedup.py`.

(a) Add these two functions (place after `_apply_volatile`, before `_tile`):

```python
def _reconstruct_node(tmpl_node, new_id, new_parent, bbox_val, has_bbox, vdelta):
    """Build the template-derived instance node EXACTLY as reconstruct() will, BEFORE exceptions/drop.
    Single source of truth: dedup_chrome simulates with this to compute the lossless patch, and
    reconstruct calls it to build — so the patch is diffed against the real ship path (no drift).
    Re-bases id/parent, overrides bbox (or removes it), and applies the volatile delta."""
    n = copy.deepcopy(tmpl_node)
    n["id"] = new_id
    n["parent"] = new_parent
    if has_bbox:
        n["bbox"] = copy.deepcopy(bbox_val)
    elif "bbox" in n:
        del n["bbox"]
    _apply_volatile(n, tmpl_node, vdelta)
    return n


def _node_patch(recon, inst):
    """The minimal correction turning the template-derived `recon` into the real instance `inst`.
    set_ = {k: inst[k]} for every key whose value differs or is instance-only; drop = keys present in
    recon but absent on inst. Applying set_ then drop to recon yields inst EXACTLY -> lossless by
    construction (covers id/parent/z/confidence AND any unkeyed field: style, tag, extra token_ref
    subkeys, presence mismatches — both directions)."""
    set_ = {k: v for k, v in inst.items() if recon.get(k, _MISSING) != v}
    drop = [k for k in recon if k not in inst]
    return set_, drop
```

(b) In `dedup_chrome`, replace the per-node loop body (the `for i, (tn, inode) in enumerate(zip(...))` block) and the `refs.append(...)`:

```python
            per_node, exceptions, drops = [], {}, {}
            for i, (tn, inode) in enumerate(zip(tmpl_nodes, order)):
                vdelta = _encode_volatile(tn, inode)
                exp_id = base + i
                exp_parent = root.get("parent") if i == 0 else base + tmpl_idx[tn["parent"]]
                has_bbox = inode.get("bbox") is not None
                recon = _reconstruct_node(tn, exp_id, exp_parent, inode.get("bbox"), has_bbox, vdelta)
                set_, drop = _node_patch(recon, inode)
                per_node.append({"bbox": inode.get("bbox"), "vdelta": vdelta})
                if set_:
                    exceptions[str(i)] = set_       # charged corrections (JSON-stable str key)
                if drop:
                    drops[str(i)] = drop            # template-only fields to delete on rebuild
            refs.append({"template": key, "id_base": base,
                         "root_parent": root.get("parent"),
                         "nodes": per_node, "exceptions": exceptions, "drop": drops})
```

This REMOVES the `_vol_presence(tn) != _vol_presence(inode)` raise (now charged via the patch, not raised) and the `_diff_nonpositional` call. Keep the `assert len(tmpl_nodes) == len(order)` collision guard above the loop.

(c) Delete the now-dead `_diff_nonpositional` function (lines ~277-292) and the `_vol_presence` function IF nothing else uses it (grep first: `grep -n _vol_presence scripts/_chrome_dedup.py` — it is only called in the removed tripwire; remove it too). Keep `_vol_val`/`_vol_name` (used by `_encode_volatile`/`_apply_volatile`).

(d) In `reconstruct`, replace the per-ref expansion loop body with a `_reconstruct_node` call + set + drop:

```python
        for ref in route["refs"]:
            tmpl = templates[ref["template"]]
            base = ref["id_base"]
            id_of = [base + i for i in range(len(tmpl))]
            tmpl_idx = {tn["id"]: i for i, tn in enumerate(tmpl)}
            for i, tn in enumerate(tmpl):
                pn = ref["nodes"][i]
                new_parent = ref.get("root_parent") if i == 0 else id_of[tmpl_idx[tn["parent"]]]
                has_bbox = pn.get("bbox") is not None
                n = _reconstruct_node(tn, id_of[i], new_parent, pn.get("bbox"), has_bbox, pn["vdelta"])
                for f, v in ref.get("exceptions", {}).get(str(i), {}).items():
                    n[f] = v                          # restore charged field exactly
                for f in ref.get("drop", {}).get(str(i), []):
                    n.pop(f, None)                    # delete template-only field
                nodes.append(n)
```

- [ ] **Step 4: Run, verify PASS + no regressions**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py -v`
Expected: all PASS (the 2 new + the prior 16; the existing `test_dedup_charges_exception_when_positional_differs` still gets `exceptions["0"]=={"z":9}` because z differs from template → charged in `set_`; the clean-case test still sees `exceptions=={}`).

- [ ] **Step 5: Commit**

```bash
git add scripts/_chrome_dedup.py scripts/test_chrome_dedup.py
git commit -m "fix: G3d dedup charges all non-template fields (set+drop) — lossless by construction"
```

---

### Task 2: real-skeleton regression fixture

**Files:** Create `scripts/fixtures/g3d_real_chrome.json`; add a test to `scripts/test_chrome_dedup.py`.

The synthetic test is necessary but not sufficient — the bug survived BECAUSE fixtures were too clean. Check in the real failing pair.

- [ ] **Step 1: Build the fixture from a real capture.** A capture already exists at `/tmp/wire-smoke/routes/{r00,r01}/skeleton.json` (python.org home + /about/). If absent, recapture: `python3 scripts/site_capture.py --urls "https://www.python.org/,https://www.python.org/about/" --out /tmp/wire-smoke --cdp-port 9222` (needs Chrome on :9222 with an open tab). Extract the recurring chrome landmark subtree from BOTH routes (the nav landmark whose `style` differs) into one JSON file. Keep it small but REAL — trim to the deduping landmark + enough siblings that `_tile` selects it (occ≥2). Write a throwaway extraction script (in the sandbox) that loads both skeletons, finds the chrome landmark subtree present in both, and writes `{"r0": [...nodes...], "r1": [...nodes...]}` to `scripts/fixtures/g3d_real_chrome.json`. The nodes are already firewalled (content-free); do NOT hand-edit values.

  Verify the fixture actually reproduces the original bug against the PRE-fix code path conceptually: it must contain at least one node where the two routes share a structural key but differ in an unkeyed field (e.g. `style`). Print a one-line confirmation (count of such nodes) when building — do not paste node content into context.

- [ ] **Step 2: Write the test** (append to `scripts/test_chrome_dedup.py`):

```python
def test_roundtrip_lossless_on_real_skeleton_fixture():
    # the REAL python.org chrome pair that exposed the bug (style varies per route). Pre-fix this
    # round-trip was NOT byte-identical; post-fix it must be node-set identical for every route.
    import json, pathlib
    data = json.loads((pathlib.Path(__file__).resolve().parent / "fixtures" / "g3d_real_chrome.json").read_text())
    art = D.dedup_chrome(data)
    rebuilt = D.reconstruct(art)
    for rid, original in data.items():
        assert _by_id(rebuilt[rid]) == _by_id(original), rid
```

- [ ] **Step 3: Run, verify PASS**

Run: `cd scripts && python3 -m pytest test_chrome_dedup.py::test_roundtrip_lossless_on_real_skeleton_fixture -v`
Expected: PASS post-fix. (Sanity: `git stash` the Task 1 change, run this test, confirm it FAILS on the real fixture — proving the fixture reproduces the bug — then `git stash pop`. Report the stash-check result.)

- [ ] **Step 4: Commit**

```bash
git add scripts/fixtures/g3d_real_chrome.json scripts/test_chrome_dedup.py
git commit -m "test: real python.org chrome pair as G3d losslessness regression fixture"
```

---

### Task 3: serialize `drop` + on-disk round-trip

**Files:** Modify `scripts/site_chrome.py` (`_jsonable`); add a test to `scripts/test_site_chrome.py`.

- [ ] **Step 1: Write the failing test** (append to `scripts/test_site_chrome.py`):

```python
def test_on_disk_roundtrip_preserves_unkeyed_style(tmp_path):
    # the WRITTEN artifact (post _jsonable) must reconstruct an unkeyed-style difference losslessly,
    # i.e. `drop`/`exceptions` survive serialization. Guards _jsonable dropping the new `drop` map.
    import _chrome_dedup as D
    site = tmp_path / "site_out"
    site.mkdir()
    (site / "site.json").write_text(json.dumps({"routes": [
        {"route_id": "r0", "ok": True}, {"route_id": "r1", "ok": True}]}))
    def styled(base, grad):
        return [
            {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
             "confidence": 1.0, "token_ref": {"bg": "b", "fg": "f", "border": "b"},
             "style": {"background-image": grad}},
            {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4}]
    _write_route(site, "r0", styled(0, "grad-a"))
    _write_route(site, "r1", styled(100, "grad-b"))
    out = site / "chrome_dedup.json"
    r = subprocess.run([sys.executable, str(HERE / "site_chrome.py"),
                        "--site", str(site), "--out", str(out)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr + r.stdout       # lossless self-check passes post-fix
    loaded = json.loads(out.read_text())
    rebuilt = D.reconstruct(loaded)
    originals = {"r0": styled(0, "grad-a"), "r1": styled(100, "grad-b")}
    for rid, orig in originals.items():
        assert {n["id"]: n for n in rebuilt[rid]} == {n["id"]: n for n in orig}, rid
```

- [ ] **Step 2: Run, verify FAIL**

Run: `cd scripts && python3 -m pytest test_site_chrome.py::test_on_disk_roundtrip_preserves_unkeyed_style -v`
Expected: FAIL — `_jsonable` drops the `drop` map, so the on-disk reconstruct loses the style (or the self-check `die`s exit 2 if `drop` is missing entirely from the serialized refs).

- [ ] **Step 3: Implement** — in `scripts/site_chrome.py` `_jsonable`, carry `drop` alongside `exceptions`. In the per-ref dict construction, add `"drop": ref.get("drop", {})` to the `r = dict(ref)` result (it is already JSON-native: `{str: [str,...]}`). Confirm `exceptions` is likewise passed through unchanged (it already is, since `r = dict(ref)` copies it; the per-node rewrite only replaces `nodes`).

- [ ] **Step 4: Run, verify PASS** (and full site_chrome suite)

Run: `cd scripts && python3 -m pytest test_site_chrome.py -v`
Expected: all PASS (new + the prior 4).

- [ ] **Step 5: Commit**

```bash
git add scripts/site_chrome.py scripts/test_site_chrome.py
git commit -m "fix: site_chrome serializes G3d drop map so on-disk reconstruct stays lossless"
```

---

### Task 4: reconcile harness — assert real node-set equality + recompute savings

**Files:** Modify `research/capture-gap-probes/reconcile_g3d_chrome.py`.

- [ ] **Step 1: Replace the `.keys()` smoke with true per-route node-set equality.** In `main()`, replace:

```python
        assert D.reconstruct(art).keys() == routes.keys()  # losslessness smoke
```
with a real id-keyed node-set check over every route (the SAME contract site_chrome enforces):

```python
        rebuilt = D.reconstruct(art)
        for rid, orig in routes.items():
            if {n["id"]: n for n in rebuilt.get(rid, [])} != {n["id"]: n for n in orig}:
                print("  %-20s !! NOT LOSSLESS (node-set mismatch) — skipping" % netloc)
                break
        else:
            ... # proceed to compute pct (existing body, now inside the else)
```
(Restructure so a non-lossless site is reported and excluded, not silently averaged. A site that is NOT lossless after the fix is itself a finding — the fix is wrong; STOP and report.)

- [ ] **Step 2: Charge `drop` in the realized-savings formula.** In `_realized_bbox_pct`, the per-node positional charge currently is `charged_pos = len(excs.get(str(i), {}))`. Update to also charge dropped fields and any newly-charged exception fields:

```python
        excs = ref.get("exceptions", {})
        drops = ref.get("drop", {})
        ...
        for i, pn in enumerate(ref["nodes"]):
            ...
            charged = len(excs.get(str(i), {})) + len(drops.get(str(i), []))
            node_saved = (struct + (pos - bbox) - charged + matched - flag) / F
```
The previously-dropped `style` etc. now land in `excs`, so `charged` rises and realized savings fall HONESTLY. (This is a node-fraction proxy; exact charge weighting is secondary — the point is savings no longer over-count the un-achievable.)

- [ ] **Step 3: Commit (harness only — live run is Task 5, controller-run)**

```bash
git add research/capture-gap-probes/reconcile_g3d_chrome.py
git commit -m "fix: G3d reconcile asserts true node-set losslessness + charges drop in realized savings"
```

---

### Task 5: live re-measurement + honest verdict + docs (CONTROLLER-RUN — not a subagent)

This task needs CDP :9222 and judgment; the controller runs it after Tasks 1-4 land.

- [ ] **Step 1: Run the corrected reconcile live.** `cd research/capture-gap-probes && PROBE_RUNNER_CDP_TIMEOUT=90 python3 reconcile_g3d_chrome.py --cdp-port 9222`. Confirm: every site reports lossless (no `NOT LOSSLESS` row — if any appears, the fix is incomplete; STOP, root-cause, do not proceed). Record per-site realized pct + median.

- [ ] **Step 2: Compare to the pre-registered bar** (`§C9-R-G3d-dedup`: median ≥12 ∧ ≥3 sites ≥15%). Do NOT tune to clear it.

- [ ] **Step 3: Correct the results doc.** In `docs/plans/g3d-structural-deltas-chrome-dedup-results.md`, append a `## Lossless re-measurement (corrects the .keys()-only reconcile — <date>)` section: state that the prior "RECONCILED 15.5%" asserted only route-id keys (not node bytes) so it over-counted; give the corrected byte-lossless per-site table + median; and the verdict — either "still clears the bar (build stands)" or "drops below the bar → G3d BUILD verdict RE-OPENS (the dedup is correct/lossless but the savings no longer justify it; document as a DEFER-on-honest-re-measurement)". Whichever the numbers say.

- [ ] **Step 4: Update the finding doc.** Mark `docs/plans/g3d-losslessness-gap-found.md` RESOLVED with a pointer to the fix commits + the re-measurement verdict.

- [ ] **Step 5: Commit**

```bash
git add docs/plans/g3d-structural-deltas-chrome-dedup-results.md docs/plans/g3d-losslessness-gap-found.md
git commit -m "docs: G3d lossless re-measurement — corrected savings + verdict (<outcome>)"
```

---

### Task 6: re-run the wiring smoke + finish (CONTROLLER-RUN)

- [ ] **Step 1:** `rm -rf /tmp/wire-smoke2 && PROBE_RUNNER_CDP_TIMEOUT=90 python3 scripts/site_capture.py --urls "https://www.python.org/,https://www.python.org/about/" --out /tmp/wire-smoke2 --cdp-port 9222 --merge --dedup`. Expected NOW: `ok:true`, exit 0, both `design_system.json` + `chrome_dedup.json` present, firewall clean. (If `--dedup` still errors, the fix is incomplete — STOP.)
- [ ] **Step 2:** Full suite green: `cd scripts && python3 -m pytest test_chrome_dedup.py test_site_chrome.py test_site_capture_post.py test_site.py test_site_merge.py test_merge.py -q`.
- [ ] **Step 3:** Dispatch a final whole-branch review, then `superpowers:finishing-a-development-branch` (the wiring + the G3d fix merge together).

---

## Self-Review

1. **Spec coverage:** core fix charges all non-template fields incl. drop (Task 1) ✓; `_vol_presence` raise removed (Task 1c) ✓; `_diff_nonpositional` removed (Task 1c) ✓; real-fixture regression (Task 2) ✓; serialization of `drop` (Task 3) ✓; reconcile asserts true node-set equality + charges drop (Task 4) ✓; honest re-measurement + verdict re-open path (Task 5) ✓; wiring smoke now green (Task 6) ✓.
2. **Placeholder scan:** none — all code steps carry concrete code; the only `<outcome>`/`<date>` placeholders are commit-message/heading fill-ins the controller resolves from the actual run.
3. **Type consistency:** `_reconstruct_node(tmpl_node, new_id, new_parent, bbox_val, has_bbox, vdelta)` signature identical in dedup-sim and reconstruct calls; `exceptions` = `{str(i): {field: value}}`, `drop` = `{str(i): [field,...]}` consistent across dedup, reconstruct, `_jsonable`, and the reconcile charge.

## Risks / checks for the implementer
- **bbox in the patch:** `_reconstruct_node` sets `recon["bbox"] = inst.bbox`, so `_node_patch` never charges bbox (it's the per-node payload, not an exception). Confirm a clean case still yields `exceptions=={}` + `drop=={}`.
- **token_ref redundancy:** when `vdelta` already fixes `token_ref`, `_node_patch` charges nothing for it; when presence/extra-subkeys differ, it charges the whole `token_ref` (lossless, slightly redundant). Acceptable.
- **Existing tests:** `test_dedup_charges_exception_when_positional_differs` and the clean-case test must still pass unchanged (z still charged via set_; clean case still empty). If they break, the patch logic is wrong — fix the code, not the test.
