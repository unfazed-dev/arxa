# Wire Cross-Route Post-Processors Into site_capture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `site_capture.py` optionally run the two shipped cross-route post-processors (`site_merge.py` → `design_system.json`, `site_chrome.py` → `chrome_dedup.json`) as opt-in steps after a capture, so one command produces routes + manifest + design-system + deduped-chrome.

**Architecture:** `capture_site()` stays **untouched** (minimal blast radius). A new I/O-thin `run_post_processors(site_dir, merge, dedup)` subprocess-invokes the real CLIs via the existing `_run()` helper — reusing their already-tested exit-code, firewall, and losslessness logic verbatim, and keeping their stdout out of context. `main()` gains `--merge`/`--dedup` flags (default OFF), resolves `--out` to an absolute path, calls `run_post_processors` after `capture_site`, and folds the result into the emitted JSON. Each post-processor runs its OWN `audit_bundle(out)` (rglobs the whole tree), so the firewall backstop has no gap.

**Tech Stack:** Python 3 stdlib (`argparse`, `subprocess`, `json`, `pathlib`), pytest. No new deps.

---

## Design decisions (read before implementing)

These were settled during design + advisor review. Do not silently re-decide them.

1. **Opt-in, default OFF.** `--merge` and `--dedup` are independent flags, both default `False`. Rationale: `site_capture`'s docstring frames `site.json` as "the merge contract for later rungs" — the rungs were deliberately separate passes. Opt-in flags make the value **available from the orchestrator** (the user's ask: "wire it in") with **zero behavior change** for existing callers/tests. Flipping a default to ON would change every existing `site_capture` invocation (extra artifacts, extra subprocess time, new failure surface). If the user later wants post-processing on by default, that is a one-line argparse change — call it out, don't bury it.

2. **Applicability gate decides SKIP; the child decides FAILURE.** The orchestrator owns *applicability* (does this capture have enough routes for this post-step?), read from `manifest["ok_count"]`: merge needs `ok_count >= 1`, dedup needs `ok_count >= 2`. When inapplicable → status `"skipped"`, **child NOT invoked**. This is NOT a DRY violation: the child still owns the authoritative check.

3. **Once invoked, ANY nonzero exit is a loud failure — never "skipped".** CRITICAL: `site_chrome.py` exits **2** on *losslessness failure* (round-trip not byte-identical), not only on too-few-routes. Mapping exit 2 → "skipped" would silently swallow a dedup correctness regression and report `ok=True`, defeating G3d's fail-closed signature property. Therefore: returncode `0`→`"ok"`, `3`→`"leak"`, any other nonzero→`"error"`. `"leak"` and `"error"` both make `site_capture` exit nonzero. Because applicability is gated *before* invoking, an invoked child can no longer hit its own route-count `die` for the expected-small-capture reason — so an invoked exit 2 is a genuine fault.

4. **Stop on first leak.** If a post-step returns `"leak"` (firewall exit 3), do not run the remaining post-step; return immediately with exit 3. The clean per-route bundles + `site.json` are preserved on disk (the child already unlinked only its own flagged artifact).

5. **Absolute `--out`.** `_run()` hardcodes `cwd=SCRIPTS`. A relative `--site`/`--out` handed to a child would resolve against `SCRIPTS`, not the user's cwd. `main()` MUST resolve `out` to absolute (`Path(args.out).resolve()`) before passing it to `run_post_processors`. Passing the same absolute path to `capture_site` is behavior-identical (its `mkdir`/`write_text` already work with any path).

---

## File Structure

- **Modify** `scripts/site_capture.py`:
  - Add `run_post_processors(site_dir, merge, dedup)` (new function).
  - Add `--merge`/`--dedup` flags + absolute-path resolve + result-fold in `main()`.
  - Update the module docstring (post-processing is now reachable from the orchestrator).
  - `capture_site()` / `capture_route()` / `_run()` / `_transport_argv()` are **unchanged**.
- **Create** `scripts/test_site_capture_post.py`: unit tests for `run_post_processors` + `main()` glue, all CDP-free (build fixture `site_out` dirs on disk; monkeypatch `capture_site` for the `main()` test).
- **Modify** `docs/plans/probe-runner-engine-capture-gaps.md`: append a short note that the post-processors are now wired (opt-in).

There is no existing `scripts/test_site_capture.py` to extend; the CDP capture path is host-gated elsewhere, so post-processing gets its own focused unit file.

---

## Shared test fixture helper (used by several tasks)

All tasks below assume this helper exists at the top of `scripts/test_site_capture_post.py`. Task 1 writes it; later tasks reuse it.

```python
# scripts/test_site_capture_post.py
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def _nav(base, bg):
    # a 2-node navigation landmark (root + link) — dedup-eligible chrome
    return [
        {"id": base, "parent": None, "tag": "nav", "aria_role": "navigation", "z": 0,
         "confidence": 1.0, "token_ref": {"bg": bg, "fg": "f", "border": "b"}},
        {"id": base + 1, "parent": base, "tag": "a", "z": 0, "confidence": 1.0, "text_len": 4},
    ]


def _tokens(bg):
    # a minimal but valid tokens.json surface site_merge can merge (hex palette + counts)
    return {"palette": [{"role": "bg", "hex": bg, "count": 1}],
            "type_scale": [], "spacing": []}


def _build_site(tmp_path, n_ok, *, bg=("red", "blue", "green"), skeleton_override=None):
    """Build a capture dir with `n_ok` ok routes (each: skeleton.json + tokens.json),
    plus a content-free site.json manifest. `skeleton_override(i)` lets a test inject a
    malformed/leaky skeleton for route i. Returns the site dir Path."""
    site = tmp_path / "site_out"
    (site / "routes").mkdir(parents=True, exist_ok=True)
    routes = []
    for i in range(n_ok):
        rid = "r%02d" % i
        rd = site / "routes" / rid
        rd.mkdir(parents=True, exist_ok=True)
        skel = skeleton_override(i) if skeleton_override else {"nodes": _nav(i * 100, bg[i % len(bg)])}
        (rd / "skeleton.json").write_text(json.dumps(skel))
        (rd / "tokens.json").write_text(json.dumps(_tokens(bg[i % len(bg)])))
        routes.append({"route_id": rid, "url": "https://example.com/p%d" % i,
                       "bundle": "routes/" + rid, "ok": True, "node_count": 2})
    (site / "site.json").write_text(json.dumps(
        {"schema": "probe-runner/site-manifest@1", "routes": routes,
         "route_count": n_ok, "ok_count": n_ok, "hosts": ["example.com"]}))
    return site
```

> Note on `_tokens`: keep it minimal but real enough that `_merge.build_design_system` returns without error. If a later check shows `site_merge` needs additional keys, the implementer should read `scripts/_merge.py` `build_design_system` and extend `_tokens` to satisfy it — the design-system *content* is not what these tests assert (they assert wiring + status), only that merge exits 0.

---

### Task 1: `run_post_processors` happy path (both post-steps run, both succeed)

**Files:**
- Create: `scripts/test_site_capture_post.py` (fixture helper above + this test)
- Modify: `scripts/site_capture.py` (add `run_post_processors`)

- [ ] **Step 1: Write the failing test**

Append to `scripts/test_site_capture_post.py`:

```python
def test_post_processors_run_both_on_two_routes(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    result = S.run_post_processors(site, merge=True, dedup=True)
    assert result["merge"]["status"] == "ok", result
    assert result["dedup"]["status"] == "ok", result
    assert (site / "design_system.json").exists()
    assert (site / "chrome_dedup.json").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py::test_post_processors_run_both_on_two_routes -v`
Expected: FAIL — `AttributeError: module 'site_capture' has no attribute 'run_post_processors'`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/site_capture.py`, add this function (place it after `capture_site`, before `_parse_urls`):

```python
# Minimum ok-route count each post-processor needs to be APPLICABLE. The orchestrator
# decides applicability (skip without invoking); the child still owns the authoritative
# check once invoked. See docs/plans/wire-cross-route-post-processors.md design note 2-3.
_POST_MIN_OK = {"merge": 1, "dedup": 2}
_POST_SCRIPT = {"merge": "site_merge.py", "dedup": "site_chrome.py"}


def _ok_count(site_dir):
    """ok-route count from the just-written manifest (single source of truth = site.json)."""
    try:
        site = json.loads((Path(site_dir) / "site.json").read_text())
    except (OSError, ValueError):
        return 0
    return sum(1 for r in site.get("routes", []) if r.get("ok"))


def run_post_processors(site_dir, merge, dedup):
    """Optionally run the cross-route post-processors over a finished capture dir.

    Returns {"merge": {...}, "dedup": {...}} where each value is {"status": s, ...}:
      "disabled" — flag off
      "skipped"  — flag on but too few ok routes (NOT invoked)
      "ok"       — child exited 0
      "leak"     — child exited 3 (firewall) -> caller must fail loud; stops further steps
      "error"    — child exited any other nonzero (incl. site_chrome's exit-2 losslessness
                   failure) -> caller must fail loud. NEVER conflated with "skipped".

    site_dir MUST be absolute (children run with cwd=SCRIPTS; a relative path would resolve
    against SCRIPTS). main() resolves it; run_post_processors does not re-resolve."""
    site_dir = Path(site_dir)
    ok = _ok_count(site_dir)
    out = {}
    for name, enabled in (("merge", merge), ("dedup", dedup)):
        if not enabled:
            out[name] = {"status": "disabled"}
            continue
        if ok < _POST_MIN_OK[name]:
            out[name] = {"status": "skipped", "reason": "insufficient_routes",
                         "ok_count": ok, "need": _POST_MIN_OK[name]}
            continue
        r = _run([sys.executable, _POST_SCRIPT[name], "--site", str(site_dir)])
        if r.returncode == 0:
            out[name] = {"status": "ok"}
        elif r.returncode == 3:
            out[name] = {"status": "leak", "returncode": 3}
            break  # stop on first firewall trip; clean bundles already preserved on disk
        else:
            out[name] = {"status": "error", "returncode": r.returncode}
            break  # any other nonzero (incl. exit-2 losslessness failure) = loud fault
    return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py::test_post_processors_run_both_on_two_routes -v`
Expected: PASS. Both artifacts written; both statuses `"ok"`.

- [ ] **Step 5: Commit**

```bash
git add scripts/site_capture.py scripts/test_site_capture_post.py
git commit -m "feat: run_post_processors runs site_merge + site_chrome over a finished capture"
```

---

### Task 2: applicability gate — dedup skipped (not invoked) when <2 ok routes

**Files:**
- Modify: `scripts/test_site_capture_post.py` (add test)

This proves the gate skips *without invoking* the child — the precondition that keeps an invoked exit-2 (Task 3) unambiguously a fault.

- [ ] **Step 1: Write the failing test**

```python
def test_dedup_skipped_when_fewer_than_two_routes(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 1)               # 1 ok route: merge applicable, dedup not
    result = S.run_post_processors(site, merge=True, dedup=True)
    assert result["merge"]["status"] == "ok", result
    assert result["dedup"]["status"] == "skipped"
    assert result["dedup"]["reason"] == "insufficient_routes"
    assert not (site / "chrome_dedup.json").exists()   # child was never invoked -> no artifact
    assert (site / "design_system.json").exists()


def test_flags_off_are_disabled_not_run(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    result = S.run_post_processors(site, merge=False, dedup=False)
    assert result["merge"]["status"] == "disabled"
    assert result["dedup"]["status"] == "disabled"
    assert not (site / "design_system.json").exists()
    assert not (site / "chrome_dedup.json").exists()
```

- [ ] **Step 2: Run tests to verify they pass (gate already implemented in Task 1)**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py -k "skipped or disabled" -v`
Expected: PASS — the Task 1 implementation already encodes the gate; these lock it in. (If either fails, the Task 1 gate is wrong — fix `run_post_processors`, not the test.)

- [ ] **Step 3: Commit**

```bash
git add scripts/test_site_capture_post.py
git commit -m "test: lock applicability gate — dedup skipped (not invoked) below 2 routes"
```

---

### Task 3: invoked child nonzero is a LOUD fault — never swallowed

**Files:**
- Modify: `scripts/test_site_capture_post.py` (add tests)

Guards the advisor-flagged blocker: an *invoked* child returning nonzero (firewall exit 3, or site_chrome's exit-2 losslessness/route-collapse) must surface as `"leak"`/`"error"`, never `"skipped"`/`"ok"`.

- [ ] **Step 1: Write the failing test**

```python
def _leaky_skeleton(i):
    # a content URL the firewall must catch -> child exits 3
    return {"nodes": [
        {"id": i * 100, "parent": None, "tag": "nav", "aria_role": "navigation",
         "z": 0, "confidence": 1.0, "token_ref": {"bg": "red", "fg": "f", "border": "b"},
         "href": "https://example.com/secret-photo.jpg"},
        {"id": i * 100 + 1, "parent": i * 100, "tag": "a", "z": 0, "confidence": 1.0,
         "text_len": 4}]}


def test_firewall_leak_reports_leak_and_stops(tmp_path):
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=_leaky_skeleton)
    result = S.run_post_processors(site, merge=False, dedup=True)
    assert result["dedup"]["status"] == "leak", result
    assert result["dedup"]["returncode"] == 3
    assert not (site / "chrome_dedup.json").exists()   # child unlinked its flagged artifact


def test_invoked_child_nonzero_is_error_not_skipped(tmp_path):
    # site.json says 2 ok routes (gate passes -> dedup IS invoked), but both skeletons are
    # malformed (not node lists) so site_chrome drops to <2 readable and dies exit 2.
    # That invoked exit-2 MUST map to "error", proving exit-2 is never silently "skipped".
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=lambda i: {"nodes": "not-a-list"})
    result = S.run_post_processors(site, merge=False, dedup=True)
    assert result["dedup"]["status"] == "error", result
    assert result["dedup"]["returncode"] != 0
    assert not (site / "chrome_dedup.json").exists()
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py -k "leak or nonzero" -v`
Expected: PASS — Task 1's `elif r.returncode == 3` / `else` branches already implement this. These tests are the regression guard for the design's central correctness property. (If `test_invoked_child_nonzero_is_error_not_skipped` fails, re-read design note 3 — the bug is back.)

> Implementer note: confirm empirically that `site_chrome.py` exits **3** on the leak fixture and a **nonzero != 0** on the malformed-list fixture *before* trusting the asserts — run each child directly once: `python3 site_chrome.py --site <fixture>` and read the exit code. If `--out` defaulting under `cwd=SCRIPTS` writes the artifact somewhere unexpected, that surfaces here.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_site_capture_post.py
git commit -m "test: invoked post-processor nonzero exit is loud (leak/error), never swallowed"
```

---

### Task 4: `main()` flags, absolute-path resolve, JSON fold, exit code

**Files:**
- Modify: `scripts/site_capture.py` (`main()` only)
- Modify: `scripts/test_site_capture_post.py` (add `main()` glue test)

- [ ] **Step 1: Write the failing test**

```python
def test_main_folds_post_status_and_exit_code(tmp_path, monkeypatch, capsys):
    import site_capture as S
    site = _build_site(tmp_path, 2)
    manifest = json.loads((site / "site.json").read_text())
    # bypass the CDP capture path: capture_site returns the prebuilt manifest, writes nothing
    monkeypatch.setattr(S, "capture_site", lambda urls, out, transport: manifest)
    monkeypatch.setattr(sys, "argv",
        ["site_capture.py", "--urls", "https://example.com/p0", "--out", str(site),
         "--merge", "--dedup"])
    rc = S.main()
    payload = json.loads(capsys.readouterr().out)
    assert rc == 0
    assert payload["ok"] is True
    assert payload["post"]["merge"]["status"] == "ok"
    assert payload["post"]["dedup"]["status"] == "ok"


def test_main_returns_nonzero_when_post_step_leaks(tmp_path, monkeypatch, capsys):
    import site_capture as S
    site = _build_site(tmp_path, 2, skeleton_override=_leaky_skeleton)
    manifest = json.loads((site / "site.json").read_text())
    monkeypatch.setattr(S, "capture_site", lambda urls, out, transport: manifest)
    monkeypatch.setattr(sys, "argv",
        ["site_capture.py", "--urls", "https://example.com/p0", "--out", str(site),
         "--dedup"])
    rc = S.main()
    payload = json.loads(capsys.readouterr().out)
    assert rc == 3
    assert payload["ok"] is False
    assert payload["post"]["dedup"]["status"] == "leak"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py -k main -v`
Expected: FAIL — `main()` does not yet accept `--merge`/`--dedup` (argparse `SystemExit: 2`) and emits no `post` key.

- [ ] **Step 3: Write minimal implementation**

In `scripts/site_capture.py` `main()`, add the two flags and the post-processing fold. Replace the current body from the flag block through `return 0`:

```python
    p.add_argument("--serial", default=None)
    p.add_argument("--merge", action="store_true",
                   help="after capture, run site_merge.py -> design_system.json (needs >=1 ok route)")
    p.add_argument("--dedup", action="store_true",
                   help="after capture, run site_chrome.py -> chrome_dedup.json (needs >=2 ok routes)")
    args = p.parse_args()

    urls = _parse_urls(args)
    if not urls:
        die("site_capture needs at least one route (--urls-file or --urls).")

    out_dir = Path(args.out).resolve()   # absolute: children run cwd=SCRIPTS (design note 5)
    manifest = capture_site(urls, str(out_dir), _transport_argv(args))

    payload = {"ok": True, "out": str(out_dir),
               "route_count": manifest["route_count"], "ok_count": manifest["ok_count"]}
    if args.merge or args.dedup:
        post = run_post_processors(out_dir, args.merge, args.dedup)
        payload["post"] = post
        if any(v.get("status") in ("leak", "error") for v in post.values()):
            payload["ok"] = False
            emit_json(payload)
            return 3 if any(v.get("status") == "leak" for v in post.values()) else 1
    emit_json(payload)
    return 0
```

(Leave the `--android`/`--ios` lines above `--serial` as they are; only `--serial` is shown for anchor context. Append the two new `add_argument` calls immediately after the existing `--serial` line.)

- [ ] **Step 4: Run the full file to verify it passes**

Run: `cd scripts && python3 -m pytest test_site_capture_post.py -v`
Expected: PASS — all tasks' tests green (8 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/site_capture.py scripts/test_site_capture_post.py
git commit -m "feat: site_capture --merge/--dedup flags run post-processors and fail loud on leak"
```

---

### Task 5: docstring + roadmap note

**Files:**
- Modify: `scripts/site_capture.py` (module docstring)
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md` (append note)

- [ ] **Step 1: Update the module docstring**

In `scripts/site_capture.py`, replace the parenthetical in the first docstring sentence so it reflects that post-processing is now reachable. Change:

```
emit one firewall-gated bundle per route plus a content-free site.json manifest
(the merge contract for later rungs G3b/c/d).
```
to:
```
emit one firewall-gated bundle per route plus a content-free site.json manifest
(the merge contract for later rungs G3b/c/d). With --merge and/or --dedup, the
post-processors (site_merge -> design_system.json, site_chrome -> chrome_dedup.json)
run over the finished capture; each re-audits the whole tree through the unchanged
firewall, and any post-step leak/fault fails the run loudly.
```

And extend the usage block:
```
Host Bash (CDP):
    python3 scripts/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222
    python3 scripts/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222 --merge --dedup
```

- [ ] **Step 2: Append the roadmap note**

Append to `docs/plans/probe-runner-engine-capture-gaps.md`:

```markdown
## §C9-R-G3-wire — Cross-route post-processors wired into site_capture (opt-in) (2026-06-02)

`site_capture.py` gains `--merge` / `--dedup` (default OFF): after the capture + site-root
firewall backstop, it subprocess-invokes the shipped `site_merge.py` (→ design_system.json)
and/or `site_chrome.py` (→ chrome_dedup.json) over the finished dir. Applicability is gated on
`ok_count` (merge ≥1, dedup ≥2) — too-few-routes → `skipped` WITHOUT invoking; once invoked,
ANY nonzero child exit is loud (`leak` exit-3 firewall, `error` otherwise — incl. site_chrome's
exit-2 losslessness gate, which must never be swallowed). Stops on first leak; clean route
bundles + site.json are preserved. `capture_site()` is unchanged; each post-processor's own
`audit_bundle` re-covers the whole tree (no firewall gap). Realizes the value of the G3b/G3d
CLIs from the orchestrator without changing default behavior. Tests: `scripts/test_site_capture_post.py`.
```

- [ ] **Step 3: Commit**

```bash
git add scripts/site_capture.py docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: note cross-route post-processors wired into site_capture (opt-in)"
```

---

## Self-Review (run before dispatch)

1. **Spec coverage:** flags (`--merge`/`--dedup`, Task 4) ✓; subprocess invocation reusing tested CLIs (Task 1) ✓; applicability skip-without-invoke (Task 2) ✓; loud-on-nonzero incl. exit-2 losslessness guard (Task 3) ✓; absolute-path resolve (Task 4 `main`) ✓; stop-on-leak (Task 1 `break` + Task 3 test) ✓; firewall coverage preserved (capture_site untouched + child backstops, design note) ✓; docstring + roadmap (Task 5) ✓.
2. **Placeholder scan:** none — every step has concrete code/commands/expected output.
3. **Type consistency:** `run_post_processors(site_dir, merge, dedup)` signature and `{"status": ...}` shape used identically across Tasks 1–4; `_POST_MIN_OK`/`_POST_SCRIPT`/`_ok_count`/`_run` names consistent; `main()` reads `args.merge`/`args.dedup` matching the `add_argument` dests.

## Risks / open checks for the implementer

- **`_tokens` sufficiency:** if `site_merge` needs more token keys than the minimal fixture provides, read `_merge.build_design_system` and extend `_tokens` (Task 1 note). The tests assert *status*, not design-system content.
- **`site_chrome --out` default under `cwd=SCRIPTS`:** the children default `--out` to `<site>/<artifact>.json`; with an absolute `--site` this lands inside the capture dir as intended. Task 3's implementer note verifies this empirically.
- **Exit-code contract:** confirm `site_merge`/`site_chrome` exit `3` on firewall and `2` on their `die` paths (matches the read source). If a future edit changes those codes, Task 3's tests catch it.
