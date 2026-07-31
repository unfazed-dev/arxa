# ARIA landmark-role enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach a content-free, computed-ARIA **landmark** role (`aria_role`) to each skeleton node, sourced from CDP `Accessibility.getFullAXTree`, joined to the DOMSnapshot in one session — without touching the geometry `role`.

**Architecture:** Two pure cores (`landmark_roles` parses+filters the AX tree to a fixed allowlist; `apply_aria_roles` joins via the internal `backendNodeId`) plus one guarded I/O helper (`enrich_aria`) wired into `web_skeleton._snapshot_skeleton`. Additive optional node key (mirrors `substrate`/`pseudo`); geometry `role` and all its consumers untouched. Firewall unchanged — `aria_role` is a mechanism key and the allowlist guarantees short structural tokens.

**Tech Stack:** Python 3, Chrome DevTools Protocol (`Accessibility` domain), existing `web_skeleton` capture path, `content_firewall`, pytest.

**Spec:** `docs/plans/aria-landmark-role-enrichment-design.md`.

**Standing conventions (all tasks):** commits SINGLE-LINE, no trailers/body; stage EXPLICIT paths (never `git add -A`); ONE commit per task, a review-driven fix gets its own commit; do NOT push (all local on `master`). `backendNodeId` stays internal (never emitted). The host gate (Task 6) runs on host Bash with `dangerouslyDisableSandbox=true` (CDP unreachable from the ctx sandbox) and is **controller-run** — implementer subagents only WRITE the gate file and static-check it (`python3 -c "import ast; ast.parse(open(p).read())"`). Content firewall: failure/■diagnostic paths print categories/counts only, NEVER subprocess stderr or page bytes.

---

## File Structure

- `scripts/web_skeleton.py` — **modify**: add `LANDMARK_ROLES` constant, pure `landmark_roles()`, pure `apply_aria_roles()`, guarded `enrich_aria()`; call `enrich_aria` in `_snapshot_skeleton` before its return.
- `scripts/test_aria_roles.py` — **create**: pure-core + guard unit tests (no CDP).
- `scripts/content_firewall.py` — **modify**: `redact_node` docstring mention of `aria_role` (doc only; no logic change).
- `scripts/test_content_firewall.py` — **modify**: `aria_role` audits-clean assertion.
- `fixtures/aria/run_aria.py` — **create**: host CDP gate (controller-run); synthetic landmark page + capture + assert + audit + determinism.

---

### Task 1: `LANDMARK_ROLES` + pure `landmark_roles()`

**Files:**
- Modify: `scripts/web_skeleton.py` (add constant + function near `classify`, ~line 354)
- Create: `scripts/test_aria_roles.py`

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_aria_roles.py
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import web_skeleton as W  # noqa: E402


def test_landmark_roles_filters_to_allowlist():
    ax = {"nodes": [
        {"backendDOMNodeId": 10, "role": {"value": "navigation"}},
        {"backendDOMNodeId": 11, "role": {"value": "link"}},        # not a landmark
        {"backendDOMNodeId": 12, "role": {"value": "contentinfo"}},
    ]}
    assert W.landmark_roles(ax) == {10: "navigation", 12: "contentinfo"}


def test_landmark_roles_skips_ignored_and_missing():
    ax = {"nodes": [
        {"backendDOMNodeId": 1, "role": {"value": "main"}, "ignored": True},
        {"backendDOMNodeId": 2, "role": {"value": "main"}},
        {"role": {"value": "banner"}},                              # no backend id
        {"backendDOMNodeId": 3},                                    # no role
    ]}
    assert W.landmark_roles(ax) == {2: "main"}


def test_landmark_roles_drops_author_custom():
    ax = {"nodes": [{"backendDOMNodeId": 7,
                     "role": {"value": "totally custom marketing widget name"}}]}
    assert W.landmark_roles(ax) == {}


def test_landmark_roles_empty_input():
    assert W.landmark_roles(None) == {}
    assert W.landmark_roles({}) == {}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: FAIL — `AttributeError: module 'web_skeleton' has no attribute 'landmark_roles'`.

- [ ] **Step 3: Add the constant + function**

Add near `classify` (after line ~373) in `scripts/web_skeleton.py`:

```python
# ARIA landmark + region-like composite roles -- the content-free allowlist for the
# additive aria_role field (design §3). A computed role outside this set yields NO
# aria_role; this fixed allowlist is the IP boundary (no author role= text reaches disk).
LANDMARK_ROLES = frozenset({
    "banner", "navigation", "main", "contentinfo", "complementary", "region", "search",
    "form", "article", "menubar", "tablist", "toolbar", "dialog",
})


def landmark_roles(ax_tree, allow=LANDMARK_ROLES):
    """{backendDOMNodeId: role_value} for non-ignored AX nodes whose role.value is in
    `allow`. Reads ONLY role.value -- never name/description/value (accessible-name =
    content). Pure: takes a getFullAXTree result dict, returns a plain dict."""
    out = {}
    for n in (ax_tree or {}).get("nodes", []):
        if n.get("ignored"):
            continue
        bk = n.get("backendDOMNodeId")
        role = (n.get("role") or {}).get("value")
        if bk is not None and role in allow:
            out[bk] = role
    return out
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_aria_roles.py
git commit -m "feat: add LANDMARK_ROLES allowlist + pure landmark_roles AX-tree filter"
```

---

### Task 2: pure `apply_aria_roles()`

**Files:**
- Modify: `scripts/web_skeleton.py` (add after `landmark_roles`)
- Test: `scripts/test_aria_roles.py` (append)

- [ ] **Step 1: Write the failing tests** (append to `scripts/test_aria_roles.py`)

```python
def test_apply_aria_roles_joins_by_backend():
    nodes = [{"id": 0}, {"id": 1}, {"id": 2}]
    node_backend = {0: 100, 1: 101, 2: 102}
    role_by_backend = {100: "navigation", 102: "contentinfo"}
    W.apply_aria_roles(nodes, node_backend, role_by_backend)
    assert nodes[0]["aria_role"] == "navigation"
    assert "aria_role" not in nodes[1]          # no landmark -> key ABSENT (not null)
    assert nodes[2]["aria_role"] == "contentinfo"


def test_apply_aria_roles_no_backend_for_node():
    nodes = [{"id": 0}]
    W.apply_aria_roles(nodes, {}, {100: "main"})   # node 0 has no backend mapping
    assert "aria_role" not in nodes[0]
```

- [ ] **Step 2: Run to verify fail**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: FAIL — `AttributeError: ... 'apply_aria_roles'`.

- [ ] **Step 3: Implement** (add after `landmark_roles` in `scripts/web_skeleton.py`)

```python
def apply_aria_roles(nodes, node_backend, role_by_backend):
    """Set node['aria_role'] for each node whose backendNodeId carries a landmark role.
    Mutates `nodes` in place; LEAVES THE KEY ABSENT when there is no landmark role
    (conditional, like substrate/pseudo). `node_backend` is {node_id: backendNodeId}."""
    for n in nodes:
        r = role_by_backend.get(node_backend.get(n["id"]))
        if r:
            n["aria_role"] = r
```

- [ ] **Step 4: Run to verify pass**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_aria_roles.py
git commit -m "feat: add apply_aria_roles backend-join attach helper"
```

---

### Task 3: guarded `enrich_aria()` (the only ev/CDP-touching code)

**Files:**
- Modify: `scripts/web_skeleton.py` (add after `apply_aria_roles`)
- Test: `scripts/test_aria_roles.py` (append)

- [ ] **Step 1: Write the failing tests** (append)

```python
def test_enrich_aria_noop_without_sess():
    class FakeEv:        # no .sess attribute -> non-CDP transport
        pass
    nodes = [{"id": 0}]
    W.enrich_aria(nodes, {0: 1}, FakeEv())     # must not raise
    assert "aria_role" not in nodes[0]


def test_enrich_aria_attaches_via_fake_session():
    class FakeSess:
        def send(self, method, params=None):
            if method == "Accessibility.getFullAXTree":
                return {"nodes": [{"backendDOMNodeId": 1, "role": {"value": "main"}},
                                  {"backendDOMNodeId": 2, "role": {"value": "link"}}]}
            return {}
    class FakeEv:
        sess = FakeSess()
    nodes = [{"id": 0}, {"id": 1}]
    W.enrich_aria(nodes, {0: 1, 1: 2}, FakeEv())
    assert nodes[0]["aria_role"] == "main"     # landmark joined
    assert "aria_role" not in nodes[1]         # link is not a landmark


def test_enrich_aria_survives_enable_failure():
    class FakeSess:
        def send(self, method, params=None):
            if method == "Accessibility.enable":
                raise RuntimeError("not supported")     # must be swallowed
            if method == "Accessibility.getFullAXTree":
                return {"nodes": [{"backendDOMNodeId": 9, "role": {"value": "banner"}}]}
            return {}
    class FakeEv:
        sess = FakeSess()
    nodes = [{"id": 0}]
    W.enrich_aria(nodes, {0: 9}, FakeEv())
    assert nodes[0]["aria_role"] == "banner"
```

- [ ] **Step 2: Run to verify fail**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: FAIL — `AttributeError: ... 'enrich_aria'`.

- [ ] **Step 3: Implement** (add after `apply_aria_roles` in `scripts/web_skeleton.py`)

```python
def enrich_aria(nodes, node_backend, ev):
    """Attach landmark aria_role to `nodes` when a CDP session is available; NO-OP on
    non-CDP transports (safari/android have no ev.sess). Captures getFullAXTree at the
    page's CURRENT (REST) state -- callers invoke this right after the DOMSnapshot.
    The ONLY new code that touches the transport (the pure cores stay I/O-free)."""
    if not hasattr(ev, "sess"):
        return
    try:
        ev.sess.send("Accessibility.enable", {})
    except Exception:  # noqa: BLE001  enable is best-effort; getFullAXTree often works alone
        pass
    ax = ev.sess.send("Accessibility.getFullAXTree", {})
    apply_aria_roles(nodes, node_backend, landmark_roles(ax))
```

- [ ] **Step 4: Run to verify pass**

Run: `cd scripts && python3 -m pytest test_aria_roles.py -q`
Expected: PASS (9 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_aria_roles.py
git commit -m "feat: add guarded enrich_aria CDP helper (getFullAXTree -> landmark aria_role)"
```

---

### Task 4: wire `enrich_aria` into `_snapshot_skeleton`

**Files:**
- Modify: `scripts/web_skeleton.py` (`_snapshot_skeleton`, immediately before its `return`)

**Context:** `_snapshot_skeleton(ev, url, width=None)` (≈ line 622) captures the DOMSnapshot, builds the skeleton via `to_skeleton(...)` into `sk`, gets `node_backend = {node_id: backendNodeId}`, and ends with `return sk, layout, page, node_backend`. The skeleton is at REST here — the correct join point. This is the base single-snapshot path that `site_capture`/G3a emit; multi-snapshot merge variants are out of scope (design §1).

- [ ] **Step 1: Add the call** — insert immediately BEFORE the final `return sk, layout, page, node_backend` in `_snapshot_skeleton`:

```python
    enrich_aria(sk["nodes"], node_backend, ev)
    return sk, layout, page, node_backend
```

(Find the existing `return sk, layout, page, node_backend` line in `_snapshot_skeleton` and add the `enrich_aria(...)` line directly above it. Do not change the signature or any other line.)

- [ ] **Step 2: Static-parse check**

Run: `cd scripts && python3 -c "import ast; ast.parse(open('web_skeleton.py').read()); print('PARSE_OK')"`
Expected: `PARSE_OK`.

- [ ] **Step 3: Full unit suite — no regression**

Run: `cd scripts && python3 -m pytest -q`
Expected: PASS — all existing tests + the 9 new `test_aria_roles.py` tests green. (The CDP call itself is exercised by the host gate in Task 6, not unit tests — `_snapshot_skeleton` needs a live snapshot; the extracted `enrich_aria` is unit-tested in Task 3.)

- [ ] **Step 4: Commit**

```bash
git add scripts/web_skeleton.py
git commit -m "feat: wire enrich_aria into _snapshot_skeleton base capture path"
```

---

### Task 5: firewall — `aria_role` audits clean + docstring note

**Files:**
- Modify: `scripts/content_firewall.py` (`redact_node` docstring only — no logic change)
- Test: `scripts/test_content_firewall.py` (append)

**Context:** `content_firewall.redact_node` keeps any key not in `CONTENT_KEYS` (mechanism keys), and `classify_node` buckets any non-image/text/svg `role` as `mechanism`. `aria_role` is a new mechanism key — preserved automatically; no logic change needed. Landmark role tokens (≤13 chars) are far under the `_PROSE` ≥25-char threshold, so they never trip the prose scan. This task pins that with a test + documents the new key.

- [ ] **Step 1: Write the failing test** (append to `scripts/test_content_firewall.py`)

```python
def test_aria_role_landmark_audits_clean(tmp_path):
    import json
    import content_firewall as cf
    node = {"id": 0, "role": "box", "aria_role": "navigation",
            "bbox": {"x": 0, "y": 0, "w": 10, "h": 10}}
    (tmp_path / "skeleton.json").write_text(json.dumps({"nodes": [node]}))
    assert cf.audit_bundle(tmp_path) == []
```

(If `test_content_firewall.py` is not pytest-`tmp_path`-style, mirror the file's existing temp-dir idiom instead; the assertion — a node carrying `aria_role:"navigation"` yields an empty `audit_bundle` — is the contract.)

- [ ] **Step 2: Run to verify it passes immediately** (no firewall logic change — the field is already mechanism-safe)

Run: `cd scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS. (This is a characterization test confirming the additive field is firewall-clean. The complementary negative — a non-landmark/garbage role never reaches `aria_role` — is enforced upstream by `landmark_roles` and pinned by `test_landmark_roles_drops_author_custom` in Task 1.)

- [ ] **Step 3: Document the new mechanism key** — in `scripts/content_firewall.py`, update the `redact_node` docstring's mechanism-keys list to include `aria_role`:

Find: `Mechanism keys (bbox, role, token_ref, anim_ref, font, text_len, sizing, layout, ...)`
Replace with: `Mechanism keys (bbox, role, aria_role, token_ref, anim_ref, font, text_len, sizing, layout, ...)`

- [ ] **Step 4: Re-run firewall tests**

Run: `cd scripts && python3 -m pytest test_content_firewall.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/content_firewall.py scripts/test_content_firewall.py
git commit -m "test: pin aria_role audits clean; note aria_role in redact_node mechanism keys"
```

---

### Task 6: host CDP gate `fixtures/aria/run_aria.py` (controller-run)

**Files:**
- Create: `fixtures/aria/run_aria.py`

**Context:** Implementer WRITES this file and static-checks it (`ast.parse`); it is **NOT run by the implementer** — the CONTROLLER runs it on host Bash with `dangerouslyDisableSandbox=true` after Task 6 commits (CDP `:9222` is unreachable from the ctx sandbox). It serves its OWN synthetic landmark markup (content-free, this repo's own bytes), runs the **full `site_capture` pipeline** on it, and asserts the landmark `aria_role`s landed **in the bundled, redacted per-route `routes/<id>/skeleton.json`** (the exact composed artifact a future G3c consumer reads — this is what verifies `redact_node` + the bundle pipeline preserve the additive key, beyond Task 5's isolated `redact_node` test), the site tree audits CLEAN, and capture is deterministic. Never echoes subprocess stderr or page bytes.

- [ ] **Step 1: Write the gate**

```python
#!/usr/bin/env python3
"""Host CDP gate for ARIA landmark-role enrichment. Serves a synthetic landmark page
(own markup, content-free) and runs the FULL site_capture pipeline on it
(web_skeleton -> web_tokens -> bundle_writer -> redact_node -> routes/<id>/skeleton.json)
-- the exact composed per-route artifact a future G3c consumer reads, NOT web_skeleton in
isolation. Asserts:
  - aria_role lands on the landmark elements (nav->navigation, header->banner,
    footer->contentinfo, main->main) IN THE BUNDLED skeleton (proves redact_node + the
    bundle pipeline preserve the additive key through the composed path),
  - the captured site tree audits CLEAN (content_firewall),
  - capture is deterministic (two runs -> identical aria_role set).
Runs on host Bash (CDP :9222), dangerouslyDisableSandbox=true. Prints PASS/FAIL +
content-free counts only; NEVER subprocess stderr or page bytes.
NOTE: <section> exposes role=region only when accessibly named -> the fixture names it
with aria-label (OUR fixture markup, never captured; only the role is read; aria_label is
itself a CONTENT_KEYS entry stripped by redact_node).
"""
import argparse
import http.server
import json
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"

_PAGE = (
    "<!doctype html><html><head><meta charset=utf-8>"
    "<style>body{margin:0}nav,header,footer,main,section{display:block;padding:8px}</style>"
    "</head><body>"
    "<header>alpha</header>"
    "<nav>one two three</nav>"
    "<main><section aria-label='r'>body copy here</section></main>"
    "<footer>four five</footer>"
    "</body></html>"
)


def _serve():
    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            b = _PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def log_message(self, *a):
            pass

    httpd = socketserver.TCPServer(("127.0.0.1", 0), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, "http://127.0.0.1:%d/" % httpd.server_address[1]


def _site_capture(url, out, port):
    """Run the gated site_capture orchestrator on a 1-route list -> returncode ONLY
    (never stderr -- a leak message can embed a content sample)."""
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "site_capture.py"),
         "--urls", url, "--out", str(out), "--cdp-port", str(port)],
        cwd=str(SCRIPTS), capture_output=True, text=True)
    return r.returncode


def _route_nodes(out):
    """Nodes of the first ok route's BUNDLED, redacted skeleton.json under a site_capture
    --out dir (the artifact a G3c consumer reads). None if no ok route."""
    site = json.loads((out / "site.json").read_text())
    for row in site.get("routes", []):
        if row.get("ok"):
            sk = out / "routes" / row["route_id"] / "skeleton.json"
            return json.loads(sk.read_text()).get("nodes") or []
    return None


def _aria_set(nodes):
    return {n["aria_role"] for n in nodes if n.get("aria_role")}


def _run_once(url, port):
    """One full site_capture run -> (bundled route nodes | None, audit_clean bool).
    Cleans its own dir."""
    import content_firewall as cf
    out = Path(tempfile.mkdtemp(prefix="aria_gate_"))
    try:
        rc = _site_capture(url, out, port)
        if rc != 0:
            print("  site_capture rc=%d" % rc)
            return None, False
        clean = not cf.audit_bundle(out)
        return _route_nodes(out), clean
    finally:
        shutil.rmtree(out, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", type=int, default=9222)
    args = ap.parse_args()

    httpd, url = _serve()
    try:
        nodes, clean = _run_once(url, args.cdp_port)
        if nodes is None:
            print("GATE FAIL — capture failed")
            return 1
        got = _aria_set(nodes)
        want = {"navigation", "banner", "contentinfo", "main"}
        print("  bundled route nodes=%d ; with aria_role=%d ; roles seen=%s"
              % (len(nodes), sum(1 for n in nodes if n.get("aria_role")), sorted(got)))
        nodes2, _ = _run_once(url, args.cdp_port)
        det = nodes2 is not None and _aria_set(nodes2) == got
        print("  audit CLEAN=%s ; determinism=%s" % (clean, det))
        ok = want.issubset(got) and clean and det
        print("GATE %s" % ("PASS" if ok else "FAIL"))
        return 0 if ok else 1
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Static-parse check (implementer does NOT run the gate)**

Run: `cd "$(git rev-parse --show-toplevel)" && python3 -c "import ast; ast.parse(open('fixtures/aria/run_aria.py').read()); print('PARSE_OK')"`
Expected: `PARSE_OK`.

- [ ] **Step 3: Commit**

```bash
git add fixtures/aria/run_aria.py
git commit -m "test: add ARIA landmark-role host CDP gate (controller-run)"
```

---

## Controller after-tasks (NOT implementer steps)

After all six tasks commit, the controller (not an implementer subagent) runs:

1. **Full unit suite** at the shipping commit:
   `cd scripts && python3 -m pytest -q` → expect all green (existing + 9 new aria + 1 firewall).
2. **Host gate** (CDP `:9222` up — `python3 scripts/web_launch.py --url about:blank` if not):
   `python3 fixtures/aria/run_aria.py --cdp-port 9222` on host Bash, `dangerouslyDisableSandbox=true` → expect `GATE PASS`, `audit CLEAN=True`, `determinism=True`, aria roles seen ⊇ {navigation, banner, contentinfo, main}.
3. **Final whole-feature review** (opus subagent) over the full diff.
4. **Advisor done-gate**, then the DONE report. Record results in `docs/plans/probe-runner-engine-capture-gaps.md` (`§C9-R-aria` results entry) + update the ladder-status footer. Single-line commit. No push.

---

## Self-Review

**1. Spec coverage:**
- §2 additive `aria_role` field, conditional emit → Tasks 2, 4 (apply omits key when absent).
- §3 LANDMARK_ROLES (13) → Task 1 constant (8 landmarks + article + menubar/tablist/toolbar/dialog = 13).
- §4 capture & join in `_snapshot_skeleton`, ev.sess guard, REST, backendNodeId join, role.value only → Tasks 3 (helper + guard + role.value) & 4 (wiring at REST).
- §5 pure cores → Tasks 1 (`landmark_roles`) & 2 (`apply_aria_roles`).
- §6 content-free: allowlist drops author text (Task 1 test), firewall unchanged + mechanism key + canary/clean (Task 5), docstring note (Task 5).
- §7 consumers untouched → Task 4 Step 3 full-suite no-regression.
- §8 determinism → Task 6 gate determinism assertion (two `site_capture` runs, identical aria set).
- §9 testing → Tasks 1–3 units, Task 5 firewall, Task 6 host gate (region-naming caveat honored: fixture `<section aria-label>`).
- §1 path scoping → Task 4 targets `_snapshot_skeleton` base path; merge variants untouched/unverified by design. **Task 6 verifies the COMPOSED path** (`site_capture → bundle_writer → redact_node → routes/<id>/skeleton.json`) carries `aria_role` — closing the inference gap that Task 5 only pins in isolation.
- §10 files → all five files have tasks.

**2. Placeholder scan:** No `TBD`/`add error handling`/`similar to`/scaffolding. All code blocks are complete, runnable content.

**3. Type consistency:** `landmark_roles(ax_tree, allow)`→dict, `apply_aria_roles(nodes, node_backend, role_by_backend)`→None (mutates), `enrich_aria(nodes, node_backend, ev)`→None. `node_backend` = `{node_id: backendNodeId}` (matches `to_skeleton`/`_snapshot_skeleton` return). `aria_role` key spelled identically everywhere. `LANDMARK_ROLES` referenced as the default `allow`.
