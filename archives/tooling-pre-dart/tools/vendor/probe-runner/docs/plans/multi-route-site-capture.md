# Multi-Route Site Capture (G3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture an explicit list of site routes into one firewall-gated bundle per route plus a content-free `site.json` manifest that is the stable merge contract for later rungs (G3b/c/d).

**Architecture:** A new orchestrator `site_capture.py` loops the deduped route list and per route subprocess-chains the already-gated CLIs `web_skeleton` → `web_tokens` → `bundle_writer` into `routes/<id>/` (the existing `validate_realsite` subprocess pattern). A pure helper `_site.py` assembles the manifest from result rows (CDP-free, unit testable). The whole site tree is re-audited through the **unchanged** `content_firewall.audit_bundle` before the run is declared clean. `bundle_writer` gains a distinct audit-fire exit code (3) so the orchestrator can classify content-suspicious failures without reading stderr.

**Tech Stack:** Python 3 stdlib; CDP only via the existing `web_*` CLIs (no direct CDP in the orchestrator); `subprocess`; pytest for the pure core; a local `http.server` + host-Chrome integration gate for the browser path.

**Design spec:** `docs/plans/multi-route-site-capture-design.md` (read for the §-level rationale; this plan implements it).

---

## Standing constraints (apply to EVERY task)

- **Commits:** single line, no trailers, no `Co-Authored-By`, no body. ONE commit per task; a review-driven fix is its OWN commit.
- **Staging:** stage files EXPLICITLY by path. NEVER `git add -A` / `git add .`.
- **Do NOT push.** All work local on `master`.
- **Content firewall is the IP boundary.** Never persist or print copyrighted/third-party content. Content-free outputs carry only: prop/route NAMES, COUNTS, host netloc, positional IDs, booleans, categorical error kinds. Failure paths print returncode/category ONLY — NEVER subprocess stderr (a `ContentLeak` message can embed a content sample).
- **`backendNodeId` and transient CDP `nodeId` are internal** — never on disk.
- **CDP host gates run on host Bash with `dangerouslyDisableSandbox=true`** (CDP is unreachable from the ctx sandbox). Implementer subagents WRITE the gate/harness files and static-check them only (`python3 -c "import ast; ast.parse(open(PATH).read())"`); the CONTROLLER runs the CDP gate and the after-tasks.
- **macOS note:** the `timeout` command is NOT available on this host — do not wrap commands in `timeout`.
- **Test run convention:** unit tests live beside the scripts in `scripts/` and import siblings directly; run them from the `scripts/` directory.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/_site.py` (create) | Pure manifest core: `build_site_manifest(rows)`, `dedupe_preserve_order(urls)`. No I/O, no CDP. |
| `scripts/site_capture.py` (create) | Orchestrator CLI: parse routes → per-route subprocess chain → classify rows → write `site.json` → firewall backstop. |
| `scripts/bundle_writer.py` (modify, `main()` ~line 396) | Catch `ContentLeak` → exit 3 (distinct audit-fire code). |
| `scripts/test_site.py` (create) | Pure units for `_site` + `site_capture` (subprocess monkeypatched) + the `site.json` firewall canary. |
| `scripts/test_bundle_writer.py` (modify) | Add the exit-3-on-`ContentLeak` test. |
| `fixtures/site/run_site_capture.py` (create) | Host CDP integration gate (controller-run). |
| `.gitignore` (modify) | Ignore `fixtures/site/` runtime scratch. |

---

## Task 1: `bundle_writer` distinct audit-fire exit code

**Files:**
- Modify: `scripts/bundle_writer.py` (`main()`, the `write_bundle(bundle, args.out)` call ~line 396)
- Test: `scripts/test_bundle_writer.py`

- [ ] **Step 1: Write the failing test**

Add to `scripts/test_bundle_writer.py`:

```python
def test_bundle_writer_main_exits_3_on_content_leak(tmp_path, monkeypatch, capsys):
    """A ContentLeak from write_bundle must exit 3 (distinct audit-fire code), not 1,
    and the printed marker must stay content-free (no `sample`)."""
    import sys, json
    import bundle_writer

    sk = tmp_path / "sk.json"
    tok = tmp_path / "tok.json"
    sk.write_text(json.dumps({"url": "https://e.com", "nodes": []}))
    tok.write_text(json.dumps({"palette": {}}))

    # Isolate the except path: assemble returns a dummy bundle, write_bundle raises.
    monkeypatch.setattr(bundle_writer, "assemble", lambda *a, **k: {"skeleton": {"nodes": []}})

    def boom(bundle, out_dir):
        raise bundle_writer.ContentLeak(
            "content leak in bundle X: 1 violation(s); first 1: "
            "[{'kind': 'prose', 'file': 'skeleton.json'}]")

    monkeypatch.setattr(bundle_writer, "write_bundle", boom)
    monkeypatch.setattr(sys, "argv",
                        ["bundle_writer.py", "--skeleton", str(sk), "--tokens", str(tok),
                         "--out", str(tmp_path / "b")])

    assert bundle_writer.main() == 3
    assert "sample" not in capsys.readouterr().out
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py::test_bundle_writer_main_exits_3_on_content_leak -v`
Expected: FAIL — `main()` lets `ContentLeak` propagate (exit/traceback), so it does not return `3`.

- [ ] **Step 3: Implement the exit-3 handler**

In `scripts/bundle_writer.py`, `main()`, replace the bare call:

```python
    write_bundle(bundle, args.out)
    emit_json({"ok": True, "out": args.out, "nodes": len(skeleton["nodes"]),
               "motion_rows": len(bundle["motion"]),
               "slots": len(bundle["manifest"]["slots"])})
    return 0
```

with:

```python
    try:
        write_bundle(bundle, args.out)
    except ContentLeak:
        # Content audit fired. Exit with a distinct, reserved code (3) so orchestrators
        # (site_capture) can classify this as content-suspicious vs a generic failure
        # WITHOUT reading stderr. The ContentLeak message is already content-free
        # (kind+file only, no sample), but we surface only a category here.
        emit_json({"ok": False, "error": "content_audit_failed", "out": args.out})
        return 3
    emit_json({"ok": True, "out": args.out, "nodes": len(skeleton["nodes"]),
               "motion_rows": len(bundle["motion"]),
               "slots": len(bundle["manifest"]["slots"])})
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_bundle_writer.py -v`
Expected: PASS (new test + all existing `test_bundle_writer.py` tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle_writer.py scripts/test_bundle_writer.py
git commit -m "feat: bundle_writer exits 3 on content-audit fire for orchestrator classification"
```

---

## Task 2: `_site.py` pure manifest core

**Files:**
- Create: `scripts/_site.py`
- Test: `scripts/test_site.py`

- [ ] **Step 1: Write the failing test**

Create `scripts/test_site.py`:

```python
"""Pure-core + orchestrator units for multi-route site capture (G3a). No CDP."""
import json
from pathlib import Path

import pytest


# ---- _site pure core ----

def test_build_site_manifest_shape():
    import _site
    rows = [
        {"route_id": "r00", "url": "https://e.com/", "bundle": "routes/r00",
         "ok": True, "node_count": 10},
        {"route_id": "r01", "url": "https://e.com/p", "bundle": "routes/r01",
         "ok": False, "error_kind": "tokens_failed"},
    ]
    m = _site.build_site_manifest(rows)
    assert m["schema"] == "probe-runner/site-manifest@1"
    assert m["route_count"] == 2
    assert m["ok_count"] == 1
    assert m["hosts"] == ["e.com"]
    assert m["routes"] == rows


def test_build_site_manifest_multi_host_sorted():
    import _site
    rows = [
        {"route_id": "r00", "url": "https://b.com/", "bundle": "routes/r00",
         "ok": True, "node_count": 1},
        {"route_id": "r01", "url": "https://a.com/", "bundle": "routes/r01",
         "ok": True, "node_count": 2},
    ]
    assert _site.build_site_manifest(rows)["hosts"] == ["a.com", "b.com"]


def test_dedupe_preserve_order():
    import _site
    assert _site.dedupe_preserve_order(["a", "b", "a", "c", "b"]) == ["a", "b", "c"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd scripts && python3 -m pytest test_site.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named '_site'`.

- [ ] **Step 3: Implement `_site.py`**

Create `scripts/_site.py`:

```python
"""Pure manifest core for multi-route site capture (G3a). No I/O, no CDP — unit
testable in isolation (mirrors the _theme/_style pure-core pattern)."""
from urllib.parse import urlparse

SITE_SCHEMA = "probe-runner/site-manifest@1"


def dedupe_preserve_order(urls):
    """Return urls with duplicates removed, preserving first-seen order."""
    seen = set()
    out = []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def build_site_manifest(rows):
    """Assemble the content-free site manifest (design spec §5) from per-route
    result rows. Each row: {route_id, url, bundle, ok, node_count?, error_kind?}.
    Rows pass through verbatim as `routes`; only hosts/counts are derived."""
    hosts = sorted({urlparse(r["url"]).netloc for r in rows if r.get("url")})
    return {
        "schema": SITE_SCHEMA,
        "hosts": hosts,
        "route_count": len(rows),
        "ok_count": sum(1 for r in rows if r.get("ok")),
        "routes": rows,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd scripts && python3 -m pytest test_site.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/_site.py scripts/test_site.py
git commit -m "feat: add _site pure core for multi-route site manifest"
```

---

## Task 3: `site.json` firewall canary (proof, no CDP)

**Files:**
- Test: `scripts/test_site.py` (append)
- (No implementation — `content_firewall.py` stays UNCHANGED; this proves it.)

- [ ] **Step 1: Write the canary test**

Append to `scripts/test_site.py`:

```python
# ---- firewall canary: site.json is inside the firewall (P14 lesson) ----

def test_site_json_prose_trips_firewall(tmp_path):
    """audit_bundle rglobs every file under a dir, so calling it on the site ROOT
    audits site.json too. Prove unredacted prose in a manifest field trips the
    UNCHANGED firewall — don't assert site.json is content-free, prove it."""
    import content_firewall as cf
    (tmp_path / "site.json").write_text(json.dumps({
        "schema": "probe-runner/site-manifest@1",
        "routes": [{
            "route_id": "r00",
            "url": "https://e.com/",
            "note": "The quick brown fox jumps over the lazy dog repeatedly today.",
        }],
    }))
    viol = cf.audit_bundle(tmp_path)
    assert any(v["kind"] == "prose" for v in viol)
```

- [ ] **Step 2: Run test to verify it passes (against the unchanged firewall)**

Run: `cd scripts && python3 -m pytest test_site.py::test_site_json_prose_trips_firewall -v`
Expected: PASS — the existing key-aware prose walker flags the sentence (the `note` key is not prose-exempt). If it FAILS, stop: it means the firewall does not cover the site-root path and the design's backstop assumption is wrong — escalate.

- [ ] **Step 3: Commit**

```bash
git add scripts/test_site.py
git commit -m "test: canary proving site.json prose trips the unchanged firewall"
```

---

## Task 4: `site_capture.py` orchestrator

**Files:**
- Create: `scripts/site_capture.py`
- Test: `scripts/test_site.py` (append)

- [ ] **Step 1: Write the failing tests**

Append to `scripts/test_site.py`:

```python
# ---- site_capture orchestrator (subprocess monkeypatched; no CDP) ----

def _fake_run_factory(broken_substr=None, bundle_rc=0):
    """Build a subprocess.run replacement that materializes the expected output
    files for the skeleton/tokens/bundle steps. A url containing broken_substr
    makes web_skeleton fail. bundle_writer returns bundle_rc."""
    def fake_run(cmd, **kw):
        class R:
            pass
        r = R()
        r.stdout = ""
        r.stderr = "SECRET-STDERR-MUST-NOT-PERSIST"
        url = cmd[cmd.index("--url") + 1] if "--url" in cmd else ""
        if cmd[1].endswith("web_skeleton.py"):
            if broken_substr and broken_substr in url:
                r.returncode = 2
                return r
            Path(cmd[cmd.index("--out") + 1]).write_text(
                json.dumps({"url": url, "nodes": [1, 2, 3]}))
            r.returncode = 0
        elif cmd[1].endswith("web_tokens.py"):
            Path(cmd[cmd.index("--out") + 1]).write_text(json.dumps({"palette": {}}))
            r.returncode = 0
        elif cmd[1].endswith("bundle_writer.py"):
            if bundle_rc == 0:
                Path(cmd[cmd.index("--out") + 1], "skeleton.json").write_text(
                    json.dumps({"nodes": [1, 2, 3]}))
            r.returncode = bundle_rc
        else:
            r.returncode = 0
        return r
    return fake_run


def test_transport_argv_forwards_flags():
    import argparse, site_capture
    ns = argparse.Namespace(cdp_port=9222, browser="chrome",
                            android=False, ios=False, serial=None)
    assert site_capture._transport_argv(ns) == ["--cdp-port", "9222",
                                                "--browser", "chrome"]


def test_transport_argv_omits_defaults():
    import argparse, site_capture
    ns = argparse.Namespace(cdp_port=None, browser="auto",
                            android=False, ios=False, serial=None)
    assert site_capture._transport_argv(ns) == []


def test_capture_site_rows_and_manifest(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory())
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/", "https://e.com/p"], str(tmp_path), [])
    assert m["route_count"] == 2 and m["ok_count"] == 2
    assert m["routes"][0]["route_id"] == "r00"
    assert m["routes"][0]["node_count"] == 3
    assert m["routes"][0]["bundle"] == "routes/r00"
    assert m["hosts"] == ["e.com"]
    assert (tmp_path / "site.json").exists()


def test_capture_site_isolates_failed_route(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(broken_substr="broken"))
    monkeypatch.setattr(site_capture.cf, "audit_bundle", lambda d: [])
    m = site_capture.capture_site(
        ["https://e.com/ok", "https://e.com/broken"], str(tmp_path), [])
    assert m["ok_count"] == 1
    r1 = m["routes"][1]
    assert r1["ok"] is False and r1["error_kind"] == "skeleton_failed"
    assert "node_count" not in r1
    # subprocess stderr must never reach disk
    assert "SECRET-STDERR" not in (tmp_path / "site.json").read_text()


def test_capture_route_maps_exit_3_to_audit(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_rc=3))
    ok, n, err = site_capture.capture_route(
        "https://e.com/x", tmp_path / "r00", [])
    assert ok is False and err == "bundle_audit_failed" and n is None


def test_capture_route_maps_generic_bundle_failure(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run",
                        _fake_run_factory(bundle_rc=1))
    ok, n, err = site_capture.capture_route(
        "https://e.com/x", tmp_path / "r00", [])
    assert ok is False and err == "bundle_failed"


def test_capture_site_dies_on_audit_violation(tmp_path, monkeypatch):
    import site_capture
    monkeypatch.setattr(site_capture.subprocess, "run", _fake_run_factory())
    monkeypatch.setattr(site_capture.cf, "audit_bundle",
                        lambda d: [{"kind": "prose", "file": "site.json",
                                    "sample": "LEAKED"}])
    with pytest.raises(SystemExit):
        site_capture.capture_site(["https://e.com/"], str(tmp_path), [])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd scripts && python3 -m pytest test_site.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'site_capture'`.

- [ ] **Step 3: Implement `site_capture.py`**

Create `scripts/site_capture.py`:

```python
#!/usr/bin/env python3
"""Multi-route site capture (G3a). Drive the existing per-route capture pipeline
(web_skeleton -> web_tokens -> bundle_writer) across an EXPLICIT list of routes and
emit one firewall-gated bundle per route plus a content-free site.json manifest
(the merge contract for later rungs G3b/c/d).

This orchestrator captures NOTHING itself: every page-derived byte is produced by
the already-gated web_*/bundle_writer tools. site.json adds only positional ids,
input urls, netlocs, integer counts, booleans, and categorical error kinds. The
whole site tree is re-audited through the unchanged content_firewall.audit_bundle
before the run is declared clean. Failure paths NEVER echo subprocess stderr.

Host Bash (CDP):
    python3 scripts/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

import content_firewall as cf
import _site
from _common import die, emit_json

SCRIPTS = Path(__file__).resolve().parent


def _transport_argv(args):
    """Reconstruct the transport flags to forward to each per-route subprocess.
    --url is supplied per route, so it is NOT forwarded here."""
    argv = []
    if args.cdp_port is not None:
        argv += ["--cdp-port", str(args.cdp_port)]
    if args.browser and args.browser != "auto":
        argv += ["--browser", args.browser]
    if args.android:
        argv += ["--android"]
    if args.ios:
        argv += ["--ios"]
    if args.serial:
        argv += ["--serial", args.serial]
    return argv


def _run(cmd):
    # capture_output keeps subprocess stdout/stderr OUT of our stdout and off disk.
    return subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True)


def capture_route(url, route_dir, transport):
    """Run skeleton -> tokens -> bundle into route_dir. Return
    (ok: bool, node_count: int|None, error_kind: str|None). error_kind is a fixed
    category, never subprocess stderr."""
    route_dir = Path(route_dir)
    route_dir.mkdir(parents=True, exist_ok=True)
    sk = route_dir / "_sk.json"
    tok = route_dir / "_tok.json"

    r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)] + transport)
    if r.returncode != 0:
        return (False, None, "skeleton_failed")

    r = _run([sys.executable, "web_tokens.py", "--url", url, "--out", str(tok)] + transport)
    if r.returncode != 0:
        return (False, None, "tokens_failed")

    r = _run([sys.executable, "bundle_writer.py",
              "--skeleton", str(sk), "--tokens", str(tok), "--out", str(route_dir)])
    if r.returncode == 3:
        return (False, None, "bundle_audit_failed")
    if r.returncode != 0:
        return (False, None, "bundle_failed")

    skel = json.loads((route_dir / "skeleton.json").read_text())
    return (True, len(skel.get("nodes", [])), None)


def capture_site(urls, out_dir, transport):
    """Capture every route, write site.json, and run the site-root firewall
    backstop. Returns the manifest dict. dies (nonzero) if the audit trips."""
    out = Path(out_dir)
    (out / "routes").mkdir(parents=True, exist_ok=True)
    rows = []
    for i, url in enumerate(urls):
        rid = "r%02d" % i
        ok, node_count, error_kind = capture_route(url, out / "routes" / rid, transport)
        row = {"route_id": rid, "url": url, "bundle": "routes/" + rid, "ok": ok}
        if ok:
            row["node_count"] = node_count
        else:
            row["error_kind"] = error_kind
        rows.append(row)

    manifest = _site.build_site_manifest(rows)
    (out / "site.json").write_text(json.dumps(manifest, indent=2))

    # Backstop: audit_bundle rglobs the whole tree -> covers site.json AND every
    # per-route bundle. Content-free failure: kind+file only, never the `sample`.
    viol = cf.audit_bundle(out)
    if viol:
        safe = [{"kind": v.get("kind"), "file": v.get("file")} for v in viol[:5]]
        die("content leak in site %s: %d violation(s); first %d: %s"
            % (out_dir, len(viol), len(safe), safe), code=3)
    return manifest


def _parse_urls(args):
    urls = []
    if args.urls_file:
        for line in Path(args.urls_file).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)
    if args.urls:
        urls += [u.strip() for u in args.urls.split(",") if u.strip()]
    return _site.dedupe_preserve_order(urls)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--urls-file", dest="urls_file", default=None,
                   help="file with one URL per line; blank/# lines ignored")
    p.add_argument("--urls", default=None, help="comma-separated URLs")
    p.add_argument("--out", required=True, help="site output directory")
    p.add_argument("--cdp-port", dest="cdp_port", type=int, default=None)
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    p.add_argument("--android", action="store_true")
    p.add_argument("--ios", action="store_true")
    p.add_argument("--serial", default=None)
    args = p.parse_args()

    urls = _parse_urls(args)
    if not urls:
        die("site_capture needs at least one route (--urls-file or --urls).")

    manifest = capture_site(urls, args.out, _transport_argv(args))
    emit_json({"ok": True, "out": args.out,
               "route_count": manifest["route_count"],
               "ok_count": manifest["ok_count"]})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd scripts && python3 -m pytest test_site.py -v`
Expected: PASS (all `_site` + canary + `site_capture` tests).

- [ ] **Step 5: Commit**

```bash
git add scripts/site_capture.py scripts/test_site.py
git commit -m "feat: add site_capture multi-route orchestrator with firewall backstop"
```

---

## Task 5: Host CDP integration gate

**Files:**
- Create: `fixtures/site/run_site_capture.py`

**Implementer:** WRITE the file and static-check only (`python3 -c "import ast; ast.parse(open('fixtures/site/run_site_capture.py').read())"`). Do NOT run it — it needs host Chrome CDP, which the sandbox cannot reach. The CONTROLLER runs it.

- [ ] **Step 1: Write the gate**

Create `fixtures/site/run_site_capture.py`:

```python
#!/usr/bin/env python3
"""Host CDP integration gate for multi-route site capture (G3a). Serves a synthetic
3-route mini-site from a local http.server (two real routes sharing a palette plus
one deliberately-unreachable route to force failure isolation), runs site_capture
against host Chrome, and asserts the content-free contract. NOT in the unit suite
(needs a browser). Run on host Bash with CDP reachable:

    python3 fixtures/site/run_site_capture.py --cdp-port 9222
"""
import argparse
import http.server
import json
import socketserver
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

# Two real routes share one palette; the page content is synthetic (this repo's own
# fixture markup), not third-party.
_PAGES = {
    "/": "<!doctype html><html><head><style>:root{--bg:#0b0b0b;--fg:#f5f5f5}"
         "body{background:var(--bg);color:var(--fg);font-family:system-ui}</style></head>"
         "<body><header><h1>Home</h1></header><main><p>alpha</p></main></body></html>",
    "/pricing": "<!doctype html><html><head><style>:root{--bg:#0b0b0b;--fg:#f5f5f5}"
                "body{background:var(--bg);color:var(--fg);font-family:system-ui}</style></head>"
                "<body><header><h1>Pricing</h1></header><main><p>beta</p></main></body></html>",
}


class _Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = _PAGES.get(self.path)
        if body is None:
            self.send_response(404)
            self.end_headers()
            return
        b = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def log_message(self, *a):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cdp-port", dest="cdp_port", type=int, default=9222)
    args = ap.parse_args()

    httpd = socketserver.TCPServer(("127.0.0.1", 0), _Handler)
    port = httpd.server_address[1]
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        base = "http://127.0.0.1:%d" % port
        # r00, r01 = real routes; r02 = unreachable port -> deterministic skeleton_failed.
        urls = [base + "/", base + "/pricing", "http://127.0.0.1:1/"]
        out = Path(__file__).resolve().parent / "_out"
        if out.exists():
            import shutil
            shutil.rmtree(out)

        r = subprocess.run(
            [sys.executable, str(SCRIPTS / "site_capture.py"),
             "--urls", ",".join(urls), "--out", str(out),
             "--cdp-port", str(args.cdp_port)],
            cwd=str(SCRIPTS), capture_output=True, text=True)

        # Content-free: print returncode only, never subprocess stderr.
        if r.returncode != 0:
            print("FAIL: site_capture exited rc=%d" % r.returncode)
            return 1

        site = json.loads((out / "site.json").read_text())
        ok = True

        if site.get("schema") != "probe-runner/site-manifest@1":
            print("FAIL: bad schema"); ok = False
        if site.get("route_count") != 3:
            print("FAIL: route_count != 3 (got %r)" % site.get("route_count")); ok = False
        if site.get("ok_count") != 2:
            print("FAIL: ok_count != 2 (got %r)" % site.get("ok_count")); ok = False

        routes = {r_["route_id"]: r_ for r_ in site.get("routes", [])}
        for rid in ("r00", "r01"):
            rr = routes.get(rid, {})
            if not rr.get("ok"):
                print("FAIL: %s not ok" % rid); ok = False
            bdir = out / "routes" / rid
            if not (bdir / "skeleton.json").exists() or not (bdir / "tokens.json").exists():
                print("FAIL: %s bundle incomplete" % rid); ok = False

        r02 = routes.get("r02", {})
        if r02.get("ok") is not False or r02.get("error_kind") != "skeleton_failed":
            print("FAIL: r02 not isolated as skeleton_failed (got %r)" % r02); ok = False

        # No subprocess stderr may have reached site.json.
        if "Traceback" in (out / "site.json").read_text():
            print("FAIL: stderr/traceback leaked into site.json"); ok = False

        # site-root firewall backstop must be clean on this synthetic content.
        import importlib
        sys.path.insert(0, str(SCRIPTS))
        cf = importlib.import_module("content_firewall")
        viol = cf.audit_bundle(out)
        if viol:
            print("FAIL: site-root audit found %d violation(s)" % len(viol)); ok = False

        print("GATE PASS" if ok else "GATE FAIL")
        return 0 if ok else 1
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Static-check the gate (implementer)**

Run: `python3 -c "import ast; ast.parse(open('fixtures/site/run_site_capture.py').read())"`
Expected: no output (parses clean). Do NOT run the gate itself.

- [ ] **Step 3: Commit**

```bash
git add fixtures/site/run_site_capture.py
git commit -m "test: add multi-route site capture host CDP gate"
```

---

## After-tasks (CONTROLLER only — run after all 5 tasks land)

These need host CDP and/or whole-suite runs; the controller performs them, each as its own commit where it changes files.

- [ ] **A1 — Run the host CDP gate.** Host Bash, `dangerouslyDisableSandbox=true`, with Chrome listening on `--cdp-port 9222`:
  `python3 fixtures/site/run_site_capture.py --cdp-port 9222` → expect `GATE PASS`.
- [ ] **A2 — Full unit suite (regression).** From `scripts/`: `python3 -m pytest -q` → expect all pass (prior baseline + the new `_site`/`site_capture`/`bundle_writer` tests). The only shared-path change is `bundle_writer.main()`'s try/except; confirm existing `test_bundle_writer.py` and any bundle-consuming tests are green.
- [ ] **A3 — Sibling fixture-gate spot check.** Confirm the `bundle_writer` change did not regress a representative existing bundle gate (e.g. `fixtures/container-query/run_container_query.py`, `fixtures/css_style/`) — run one on host CDP → expect its prior PASS.
- [ ] **A4 — `.gitignore`.** Append and commit:
  ```
  fixtures/site/_out/
  fixtures/site/routes/
  fixtures/site/_sk.json
  fixtures/site/_tok.json
  ```
  Commit: `chore: gitignore multi-route site capture runtime artifacts`
- [ ] **A5 — Content-free real-site harness (optional but recommended).** Create `fixtures/site/validate_realsite.py` mirroring `fixtures/container-query/validate_realsite.py`: take `--urls`/`--urls-file`, run `site_capture`, and print ONLY content-free signal (host netlocs, `route_count`, `ok_count`, per-route `node_count`, per-`error_kind` counts, site-root audit verdict). Failure paths print returncode only. Run it against a small real multi-route site to corroborate on real data and seed the eventual recurrence probe. Commit: `test: add content-free multi-route real-site validation harness`.
- [ ] **A6 — Docs.** Add a `## §C9-R-G3a — Results: Multi-route site capture LANDED` section to `docs/plans/probe-runner-engine-capture-gaps.md` and update the roadmap footer (G3a landed; G3 remaining = recurrence probe + G3b token merge + G3c component synthesis + G3d layout reconciliation). Commit: `docs: record multi-route site capture (G3a) landed`.
- [ ] **A7 — Final whole-feature review + advisor done-gate**, then report DONE and await a go-signal for the recurrence probe / G3b. Do NOT auto-start the next rung. Do NOT push.

---

## Self-Review

**Spec coverage** (design spec §-by-§):
- §2 route source (explicit list, dedupe, `#`/blank skip, empty→die) → Task 4 `_parse_urls` + Task 2 `dedupe_preserve_order`. ✓
- §3 per-route chain skeleton+tokens+bundle, transport passthrough (minus `--url`) → Task 4 `capture_route`/`_transport_argv`. ✓
- §4 layout + positional `route_id` (`r%02d`) → Task 4 `capture_site`. ✓
- §5 manifest schema (hosts/counts/routes, node_count on ok, error_kind on fail) → Task 2 `build_site_manifest` + Task 4 row build. ✓
- §6 firewall backstop via `audit_bundle` on site root + canary → Task 4 backstop + Task 3 canary. ✓
- §7 failure isolation + error_kind taxonomy → Task 4 (`skeleton_failed`/`tokens_failed`/`bundle_audit_failed`/`bundle_failed`; review-driven `skeleton_unreadable` added for the rc-0-but-no-skeleton case). ✓
- §7.1 `bundle_writer` exit-3 → Task 1. ✓
- §8 code surface (`_site.py`, `site_capture.py`, `bundle_writer` modify, tests, gate) → Tasks 1–5. ✓
- §9 ceilings → documented in design spec; no code (correct). ✓
- §10 test plan (pure units, bundle exit-3, canary, host gate) → Tasks 1–5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every run step shows the command + expected result. ✓

**Type consistency:** `capture_route` returns `(ok, node_count, error_kind)` everywhere; `build_site_manifest(rows)` consumes the exact row dict Task 4 builds; `_transport_argv` reads `cdp_port`/`browser`/`android`/`ios`/`serial` matching the `argparse` dests in `main()`; `error_kind` values match between `capture_route`, the §7 taxonomy, and the gate assertion. ✓
