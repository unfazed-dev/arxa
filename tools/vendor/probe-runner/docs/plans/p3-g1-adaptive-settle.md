# P3-G1 Adaptive Settle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The CONTROLLER (not the subagent) runs every host CDP gate with the sandbox disabled; subagents do pure work + unit tests only.

**Goal:** Replace `navigate()`'s fixed `time.sleep(2.0)` with a content-blind adaptive settle (RSC-safe network-quiet + node-count stabilization + hard max-wait cap) that waits out a progressive DOM build, returns fast on already-quiet pages, and records honest `settled`/`capped` provenance.

**Architecture:** A pure control loop `_settle.adaptive_settle(read, sleep, clock, …)` with all I/O injected (unit-testable with a scripted browser). `_web_eval.navigate()` drives it via one engine-agnostic JS read expression (`performance.getEntriesByType('resource')` + node count + `readyState`), so the same settle runs on Chrome CDP, Safari/iOS WebDriver, and Android. `web_skeleton` exposes `--max-wait` and stamps the provenance onto `skeleton.json`.

**Tech Stack:** Python 3.13, CDP `Runtime.evaluate` / WebDriver `execute_script` (both via `ev.ev`), `pytest`, offline `http.server` host fixture.

---

## Empirical grounding (probe, 2026-05-30 — same de-risk playbook that caught P2's G11)

A throwaway probe (`fixtures/settle/probe_settle.py`) served a deterministic slow-hydrate fixture and recorded `(node_count, readyState, in-flight)` every 0.25s. Findings that fix this design:

1. **Shell-trap is real but narrow.** A pre-hydration shell that is *node-count-stable AND network-quiet* from ~1s, then hydrates by a silent timer at ~5s, is indistinguishable from a settled page — only the DOM mutation proves hydration happened, and you cannot know one is coming without waiting. **This is an irreducible ceiling**, not a bug to fix (waiting penalizes every fast page).
2. **Real slow-hydrate is catchable.** Cartier-class slow hydration (doc §C3/§C9: loader persists, DOM *builds* across ~26s) means node-count is *changing throughout* and never stabilizes until build-end. So **node-count-stabilization + max-wait catches progressive builds** — the motivating target — while the irreducible miss is only the narrow "stable shell → silent delayed mutation" class.
3. **Pure `networkidle0` hangs.** While a long-lived stream/beacon is open, in-flight floors at 1, never 0. Quiet MUST tolerate `in-flight ≤ K` (RSC-safe), never require 0.

**Locked definition (do not re-derive):**
- `quiet := in-flight ≤ K  AND  no new resource started within QUIET_MS`
- `settle := quiet AND node-count stable for STABLE_POLLS AND readyState complete AND elapsed ≥ MIN_FLOOR`
- else **cap** at `MAX_WAIT`.
- **Always** return provenance: `{settled, capped, waited_ms, n_nodes}`.

**Defaults:** `MAX_WAIT=10.0s`, `QUIET_MS=800`, `STABLE_POLLS=3`, `MIN_FLOOR_MS=500`, `POLL_MS=250`, `IDLE_K=2`. Fast pages quiet-exit in <1s (faster than today's flat 2.0s); builds wait up to the cap; Cartier-class 26s is an explicit `--max-wait 30` opt-in (documented, not default — a 26s default would tax every capture).

**Honest ceiling (architecture principle 4):** the timer/single-silent-request hydration class is captured pre-mutation and marked `capped` (or `settled` on the shell) — the bundle's `settle` provenance is honest that the snapshot may predate hydration. Documented; pinned by a unit test so a future "fix" that silently penalizes fast pages is caught.

---

## File Structure

- **Create** `scripts/_settle.py` — pure `adaptive_settle()` control loop. One responsibility: the settle decision, all I/O injected.
- **Create** `scripts/test_settle.py` — unit tests for the loop (scripted browser + fake clock).
- **Modify** `scripts/_web_eval.py` — add `_SETTLE_JS`, `DEFAULT_MAX_WAIT`; rewrite `navigate()` to call `adaptive_settle` and return provenance.
- **Modify** `scripts/test_web_skeleton.py` — add `navigate()`-integration + `_capture_one` settle-attach tests.
- **Modify** `scripts/web_skeleton.py` — add `--max-wait` arg; thread `max_wait` through `_capture_one`; attach `skeleton["settle"]`.
- **Create** `fixtures/settle/run_settle.py` — host gate: progressive-build fixture + fast-page fixture, served offline, asserts the build is waited out and a fast page settles quickly. (Folds in / supersedes `probe_settle.py`, which is deleted in Task 5.)
- **Modify** `docs/plans/probe-runner-engine-capture-gaps.md` — append §C9-R-P3 results; repoint the ladder "Next" to G6.

---

## Task 1: Pure settle core `_settle.py`

**Files:**
- Create: `scripts/_settle.py`
- Test: `scripts/test_settle.py`

- [ ] **Step 1: Write the failing tests**

```python
# scripts/test_settle.py
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _settle import adaptive_settle


class FakeClock:
    """Monotonic clock that only advances when sleep() is called — deterministic."""
    def __init__(self):
        self.t = 0.0
    def now(self):
        return self.t
    def sleep(self, s):
        self.t += s


def scripted(reads):
    """read() yields each scripted browser-signal in turn, then holds the last."""
    seq = list(reads)
    i = {"n": 0}
    def read():
        idx = min(i["n"], len(seq) - 1)
        i["n"] += 1
        return seq[idx]
    return read


def run(reads, **kw):
    c = FakeClock()
    return adaptive_settle(scripted(reads), c.sleep, c.now, **kw)


def test_quiet_page_settles_at_min_floor():
    s = {"n": 50, "ready": True, "inflight": 0, "since_start_ms": 1000}
    r = run([s] * 10, max_wait=10.0)
    assert r["settled"] is True and r["capped"] is False
    assert r["n_nodes"] == 50
    assert r["waited_ms"] == 500          # 3 stable polls land exactly at MIN_FLOOR


def test_progressive_build_is_waited_out():
    reads = [
        {"n": 10,  "ready": False, "inflight": 3, "since_start_ms": 50},
        {"n": 80,  "ready": False, "inflight": 4, "since_start_ms": 30},
        {"n": 200, "ready": True,  "inflight": 2, "since_start_ms": 100},
        {"n": 400, "ready": True,  "inflight": 1, "since_start_ms": 200},
        {"n": 610, "ready": True,  "inflight": 1, "since_start_ms": 900},
        {"n": 610, "ready": True,  "inflight": 1, "since_start_ms": 1000},
        {"n": 610, "ready": True,  "inflight": 1, "since_start_ms": 1100},
    ]
    r = run(reads, max_wait=10.0)
    assert r["settled"] is True
    assert r["n_nodes"] == 610            # captured the BUILT dom, not the shell
    assert r["waited_ms"] == 1500


def test_never_quiet_page_caps():
    busy = {"n": 300, "ready": True, "inflight": 5, "since_start_ms": 50}
    r = run([busy] * 100, max_wait=2.0)
    assert r["settled"] is False and r["capped"] is True
    assert r["waited_ms"] == 2000
    assert r["n_nodes"] == 300


def test_min_floor_is_respected():
    s = {"n": 20, "ready": True, "inflight": 0, "since_start_ms": 1000}
    r = run([s] * 100, max_wait=10.0, min_floor_ms=2000)
    assert r["settled"] is True
    assert r["waited_ms"] == 2000         # did NOT settle before the floor


def test_lone_long_lived_stream_does_not_hang():
    # RSC-safe: in-flight floored at 1 (a stream), nothing new starting -> quiet opens.
    s = {"n": 120, "ready": True, "inflight": 1, "since_start_ms": 1500}
    r = run([s] * 100, max_wait=10.0)
    assert r["settled"] is True
    assert r["waited_ms"] == 500


def test_shell_trap_is_the_documented_ceiling():
    # KNOWN IRREDUCIBLE LIMIT (probe 2026-05-30): a quiet+stable shell that will
    # hydrate later via a silent timer is captured pre-hydration. Settling on the
    # shell here is the documented honest ceiling, NOT a bug. This test pins it so
    # a future change that "fixes" it by penalizing fast pages is caught.
    shell = {"n": 10, "ready": True, "inflight": 1, "since_start_ms": 1500}
    r = run([shell] * 100, max_wait=10.0)
    assert r["settled"] is True
    assert r["n_nodes"] == 10
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest scripts/test_settle.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named '_settle'`.

- [ ] **Step 3: Write minimal implementation**

```python
# scripts/_settle.py
"""Pure adaptive post-navigation settle (§C9 P3-G1).

The decision loop only; ALL I/O is injected (read/sleep/clock) so it unit-tests
against a scripted browser with a fake clock. The browser-facing JS read and the
real clock live in _web_eval.navigate().

Quiet  := inflight <= idle_k AND since_start_ms >= quiet_ms  (RSC-safe: a lone
          long-lived stream keeps inflight at 1 but starts nothing new, so quiet
          still opens; a page mid-build keeps starting resources, so it does not).
Settle := quiet AND node-count stable for stable_polls AND ready AND
          elapsed >= min_floor.
Else cap at max_wait. ALWAYS returns provenance (settled vs capped).

Honest ceiling (probe 2026-05-30): a quiet+stable shell that hydrates later via a
silent timer is indistinguishable from a settled page and is captured pre-mutation
-- the provenance is honest about it; this is irreducible without penalizing every
fast page.
"""
from __future__ import annotations


def adaptive_settle(read, sleep, clock, *, max_wait,
                    quiet_ms=800, stable_polls=3, min_floor_ms=500,
                    poll_ms=250, idle_k=2):
    """read() -> {'n': int, 'ready': bool, 'inflight': int, 'since_start_ms': float}
    sleep(seconds) -> None ; clock() -> monotonic seconds (float).
    Returns {'settled': bool, 'capped': bool, 'waited_ms': int, 'n_nodes': int}."""
    start = clock()
    deadline = start + max_wait
    last_n = None
    stable_run = 0
    while True:
        s = read()
        n = s["n"]
        stable_run = stable_run + 1 if n == last_n else 1
        last_n = n
        elapsed_ms = (clock() - start) * 1000.0
        quiet = s["inflight"] <= idle_k and s["since_start_ms"] >= quiet_ms
        if (elapsed_ms >= min_floor_ms and s["ready"]
                and stable_run >= stable_polls and quiet):
            return {"settled": True, "capped": False,
                    "waited_ms": round(elapsed_ms), "n_nodes": n}
        if clock() >= deadline:
            return {"settled": False, "capped": True,
                    "waited_ms": round((clock() - start) * 1000.0), "n_nodes": n}
        sleep(poll_ms / 1000.0)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest scripts/test_settle.py -q`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add scripts/_settle.py scripts/test_settle.py
git commit -m "feat: add pure adaptive-settle core for capture navigation"
```

---

## Task 2: Engine-agnostic JS signal + `navigate()` integration

**Files:**
- Modify: `scripts/_web_eval.py:196-203` (the `navigate` function) + module constants
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing tests** (append to `scripts/test_web_skeleton.py`)

```python
def test_navigate_returns_settle_provenance_chrome():
    import _web_eval as WE

    class FakeEv:
        def __init__(self, signal):
            self.signal = signal
            self.exprs = []
        def ev(self, expr):
            self.exprs.append(expr)
            if "location.assign" in expr:
                return None
            return self.signal       # the _SETTLE_JS read

    quiet = {"n": 42, "ready": True, "inflight": 0, "since_start_ms": 1000}
    ev = FakeEv(quiet)
    r = WE.navigate(ev, "chrome", "http://x.test/", max_wait=5.0)
    assert r["settled"] is True and r["n_nodes"] == 42
    assert any("location.assign" in e for e in ev.exprs)   # it navigated


def test_navigate_returns_settle_provenance_safari():
    import _web_eval as WE

    class FakeDriver:
        def __init__(self):
            self.got = []
        def get(self, url):
            self.got.append(url)

    class FakeEv:
        def __init__(self, signal):
            self.driver = FakeDriver()
            self.signal = signal
        def ev(self, expr):
            return self.signal

    quiet = {"n": 7, "ready": True, "inflight": 1, "since_start_ms": 1000}
    ev = FakeEv(quiet)
    r = WE.navigate(ev, "safari", "http://x.test/", max_wait=5.0)
    assert r["settled"] is True and r["n_nodes"] == 7
    assert ev.driver.got == ["http://x.test/"]               # it navigated
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest scripts/test_web_skeleton.py -q -k navigate_returns_settle`
Expected: FAIL — `navigate()` currently returns `None` (no `max_wait` kwarg) → `TypeError`/`KeyError`.

- [ ] **Step 3: Write minimal implementation**

In `scripts/_web_eval.py`, add the import + constants near the top (after the existing imports, before the eval classes):

```python
from _settle import adaptive_settle

DEFAULT_MAX_WAIT = 10.0  # settle cap (s). Cartier-class 26s hydrate: pass --max-wait 30.

# Engine-agnostic settle read: node count + readyState + a network-activity proxy
# from Resource Timing. inflight = resources not yet finished (responseEnd === 0);
# since_start_ms = ms since the most recent resource STARTED (a lone long-lived
# stream stops bumping this, so quiet still opens -> RSC-safe). Works identically
# over CDP returnByValue and WebDriver execute_script (both marshal the object).
_SETTLE_JS = (
    "(function(){"
    "var rs=performance.getEntriesByType('resource');"
    "var inflight=0,lastStart=0;"
    "for(var i=0;i<rs.length;i++){var e=rs[i];"
    "if(e.responseEnd===0)inflight++;"
    "if(e.startTime>lastStart)lastStart=e.startTime;}"
    "return{n:document.getElementsByTagName('*').length,"
    "ready:document.readyState==='complete',"
    "inflight:inflight,"
    "since_start_ms:performance.now()-lastStart};"
    "})()"
)
```

Replace the body of `navigate` (currently `_web_eval.py:196-203`):

```python
def navigate(ev, engine, url, max_wait=DEFAULT_MAX_WAIT):
    """Load `url` (mandatory for the fresh WebDriver sessions, which start blank),
    then adaptively settle. Returns settle provenance
    {settled, capped, waited_ms, n_nodes}; callers may ignore it (they did before
    this gained a return value). Content-blind: the read carries only counts/flags.
    See `_settle.adaptive_settle` for the settle definition + the honest ceiling."""
    if engine == "safari":
        ev.driver.get(url)
    else:
        ev.ev("location.assign(%s)" % json.dumps(url))
    return adaptive_settle(lambda: ev.ev(_SETTLE_JS), time.sleep, time.monotonic,
                           max_wait=max_wait)
```

(The old `time.sleep(1.5)` / `time.sleep(2.0)` lines are deleted — the adaptive settle replaces both; `driver.get` already blocks until load, then the settle quiet-exits fast.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest scripts/test_web_skeleton.py -q -k navigate_returns_settle`
Expected: PASS (2 passed). These use the real `time.sleep`; each settles at ~`MIN_FLOOR` (~0.5–0.75s).

- [ ] **Step 5: Run the full suite (no regression in the 7 verbs that call navigate)**

Run: `python3 -m pytest scripts/ -q`
Expected: PASS (all prior tests + new ones). `navigate`'s new kwarg/return is backward-compatible — all 7 callers ignore the return.

- [ ] **Step 6: Commit**

```bash
git add scripts/_web_eval.py scripts/test_web_skeleton.py
git commit -m "feat: drive adaptive settle from navigate via engine-agnostic JS read"
```

---

## Task 3: `web_skeleton --max-wait` + settle provenance on the skeleton

**Files:**
- Modify: `scripts/web_skeleton.py` (`_capture_one` ~`399-409`; `main` arg parser ~`459-490`)
- Test: `scripts/test_web_skeleton.py`

- [ ] **Step 1: Write the failing test** (append to `scripts/test_web_skeleton.py`)

```python
def test_capture_one_attaches_settle_provenance(monkeypatch):
    import web_skeleton as W
    sentinel = {"settled": True, "capped": False, "waited_ms": 700, "n_nodes": 42}
    monkeypatch.setattr(W, "navigate",
                        lambda ev, eng, url, max_wait=10.0: sentinel)
    monkeypatch.setattr(W, "_snapshot_skeleton",
                        lambda ev, url, width=None: (
                            {"schema": "probe-skeleton/2", "url": url, "nodes": []},
                            None, None))
    sk, _, _ = W._capture_one(object(), "chrome", "http://x.test/", max_wait=8.0)
    assert sk["settle"] == sentinel


def test_capture_one_forwards_max_wait(monkeypatch):
    import web_skeleton as W
    seen = {}
    def fake_nav(ev, eng, url, max_wait=10.0):
        seen["max_wait"] = max_wait
        return {"settled": True, "capped": False, "waited_ms": 1, "n_nodes": 0}
    monkeypatch.setattr(W, "navigate", fake_nav)
    monkeypatch.setattr(W, "_snapshot_skeleton",
                        lambda ev, url, width=None: ({"nodes": []}, None, None))
    W._capture_one(object(), "chrome", "http://x.test/", max_wait=30.0)
    assert seen["max_wait"] == 30.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest scripts/test_web_skeleton.py -q -k "capture_one_attaches or capture_one_forwards"`
Expected: FAIL — `_capture_one` has no `max_wait` param and does not set `sk["settle"]`.

- [ ] **Step 3: Write minimal implementation**

Rewrite `_capture_one` in `scripts/web_skeleton.py` (currently lines ~399-409):

```python
def _capture_one(ev, engine, url, width=None, max_wait=DEFAULT_MAX_WAIT):
    """Navigate (with adaptive settle), force REST, capture one DOMSnapshot;
    return (skeleton, layout, page). Stamps the settle provenance onto the
    skeleton as `settle` (content-free: counts/flags only) so the bundle is honest
    about whether the snapshot likely caught a stabilized state.

    `width` (multi-breakpoint capture): override the layout-viewport width via
    CDP Emulation before snapshotting, so bboxes reflect that breakpoint. CDP
    reverts the override when the inspector session closes, so the caller's
    open tab is left untouched. No-op on non-CDP transports."""
    settle = navigate(ev, engine, url, max_wait=max_wait)
    sk, layout, page = _snapshot_skeleton(ev, url, width=width)
    sk["settle"] = settle
    return sk, layout, page
```

Add the import at the top of `web_skeleton.py` — extend the existing `_web_eval` import line:

```python
from _web_eval import add_transport_args, navigate, resolve_web_eval, DEFAULT_MAX_WAIT
```

Add the `--max-wait` arg in `main()` (right after the `--viewports` arg, before `add_transport_args(p)`):

```python
    p.add_argument("--max-wait", type=float, default=DEFAULT_MAX_WAIT, dest="max_wait",
                   help="adaptive-settle cap in seconds (default %(default)s; "
                        "raise for slow-hydrate targets, e.g. --max-wait 30)")
```

Thread `args.max_wait` into BOTH `_capture_one` call sites in `main()`:

```python
                sk, _, _ = _capture_one(ev, engine, args.url, width=w,
                                        max_wait=args.max_wait)
```

```python
            out_obj, _, _ = _capture_one(ev, engine, args.url,
                                         max_wait=args.max_wait)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest scripts/test_web_skeleton.py -q`
Expected: PASS (all web_skeleton tests, incl. the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add scripts/web_skeleton.py scripts/test_web_skeleton.py
git commit -m "feat: expose web_skeleton --max-wait and stamp settle provenance"
```

---

## Task 4: Host gate — progressive-build fixture (CONTROLLER runs this)

**Files:**
- Create: `fixtures/settle/run_settle.py`

> The implementer CREATES this file; the CONTROLLER runs it (real Chrome + sockets, sandbox disabled). It is a gate, not a `pytest` test.

- [ ] **Step 1: Write the gate**

```python
# fixtures/settle/run_settle.py
"""Host gate for §C9 P3-G1 adaptive settle. Offline, deterministic.

Serves two pages and runs web_skeleton against each:
  /build  a shell that PROGRESSIVELY builds its DOM over ~3s (network-driven
          batches) with a long-lived /stream open -> proves the settle WAITS the
          build out and captures the built DOM (the win vs the old flat 2.0s,
          which would have snapshotted the early shell).
  /fast   full content immediately, no stream -> proves a quiet page settles
          quickly (no latency regression vs the old 2.0s).
"""
from __future__ import annotations
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

BUILD = """<!doctype html><html lang=en><head><meta charset=utf-8>
<title>build</title><style>html,body{margin:0}.row{height:40px}</style></head>
<body><div id=root><p>shell</p></div><script>
fetch('/stream').catch(function(){});           // long-lived: in-flight floors at 1
var batch=0;
(function step(){
  if(batch>=6)return;                            // 6 batches over ~3s
  fetch('/chunk?b='+batch).then(function(){      // network churn during build
    var f=document.createDocumentFragment();
    for(var i=0;i<100;i++){var d=document.createElement('div');
      d.className='row';d.textContent='b'+batch+'-'+i;f.appendChild(d);}
    document.getElementById('root').appendChild(f);
    batch++; setTimeout(step,500);
  });
})();
</script></body></html>"""

FAST = ("<!doctype html><html lang=en><head><meta charset=utf-8><title>fast</title>"
        "</head><body>" + "".join("<p>row%d</p>" % i for i in range(120)) +
        "</body></html>")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def do_GET(self):
        if self.path.startswith("/build"):
            self._send(BUILD.encode(), "text/html; charset=utf-8")
        elif self.path.startswith("/fast"):
            self._send(FAST.encode(), "text/html; charset=utf-8")
        elif self.path.startswith("/chunk"):
            self._send(b"{}", "application/json")
        elif self.path.startswith("/stream"):
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.end_headers()
            try:
                time.sleep(40.0)                  # never finishes within the gate
            except Exception:
                pass
        else:
            self.send_response(404); self.end_headers()
    def _send(self, body, ct):
        self.send_response(200)
        self.send_header("Content-Type", ct)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def capture(url, max_wait):
    out = Path("/tmp/p3g1_skel.json")
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "web_skeleton.py"),
         "--url", url, "--out", str(out), "--max-wait", str(max_wait)],
        capture_output=True, text=True, cwd=str(SCRIPTS))
    if r.returncode != 0:
        raise SystemExit("web_skeleton failed: " + r.stderr[-800:])
    return json.loads(out.read_text())


def main() -> int:
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{port}"

    build = capture(base + "/build", max_wait=10.0)
    fast = capture(base + "/fast", max_wait=10.0)
    srv.shutdown()

    bs, bn = build.get("settle", {}), len(build.get("nodes", []))
    fs, fn = fast.get("settle", {}), len(fast.get("nodes", []))
    print("BUILD:", {"nodes": bn, "settle": bs})
    print("FAST :", {"nodes": fn, "settle": fs})

    ok = True
    # progressive build was waited out + captured (not the early shell)
    if not (bn > 100 and bs.get("settled") is True and 2500 <= bs.get("waited_ms", 0) <= 9500):
        print("FAIL: build not waited out / not settled in band"); ok = False
    # fast page settled quickly -> no latency regression vs old flat 2.0s
    if not (fn > 50 and fs.get("settled") is True and fs.get("waited_ms", 99999) < 2000):
        print("FAIL: fast page did not settle quickly"); ok = False

    print("GATE", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Implementer commits the fixture (gate not yet run by the subagent)**

```bash
git add fixtures/settle/run_settle.py
git commit -m "test: add P3-G1 adaptive-settle host gate (progressive-build fixture)"
```

- [ ] **Step 3: CONTROLLER runs the gate** (host, sandbox disabled — NOT the subagent)

Run: `python3 fixtures/settle/run_settle.py`
Expected: `GATE PASS` — BUILD nodes>100, `settled:true`, `waited_ms` ≈ 3000–4000; FAST `settled:true`, `waited_ms` < 2000.

If it fails, the controller diagnoses (timing band too tight on a slow host → widen the band; signal wrong → fix `_SETTLE_JS`) and re-dispatches a fix subagent. Do not hand-edit the implementation.

---

## Task 5: Document results + remove the throwaway probe

**Files:**
- Modify: `docs/plans/probe-runner-engine-capture-gaps.md`
- Delete: `fixtures/settle/probe_settle.py`

- [ ] **Step 1: Append a `§C9-R-P3` results section** to `probe-runner-engine-capture-gaps.md` (after `§C9-R-P2`), recording: locked settle definition; the empirical findings (shell-trap narrow & irreducible; progressive builds catchable; `networkidle0` hangs on streams); defaults + Cartier `--max-wait 30` note; that `navigate()` now adaptively settles for ALL 7 web verbs; firewall note (settle = counts/flags, content-free); verification (unit suite + host gate `GATE PASS`).

- [ ] **Step 2: Repoint the ladder "Next"** line from `P3 — G1 settle … + G6` to: `**Next on the §C9 ladder:** G6 consent-dismiss — decided design: consent overlay = a web_states State, dismiss = a Transition (content-blind). See task queue / docs/plans/p3-g6-consent-state.md.`

- [ ] **Step 3: Delete the probe** (its server logic now lives in `run_settle.py`):

```bash
git rm fixtures/settle/probe_settle.py
```

- [ ] **Step 4: Commit**

```bash
git add docs/plans/probe-runner-engine-capture-gaps.md
git commit -m "docs: record P3-G1 adaptive-settle results and retire the probe"
```

---

## Self-Review

**Spec coverage:** locked definition → Task 1 (`adaptive_settle`); engine-agnostic JS read + RSC-safe quiet → Task 2 (`_SETTLE_JS`, `navigate`); `--max-wait` + provenance on skeleton → Task 3; progressive-build catch + no fast-page regression → Task 4 gate; honest-ceiling shell-trap → pinned by `test_shell_trap_is_the_documented_ceiling`; docs + probe retirement → Task 5. ✓

**Type consistency:** `adaptive_settle` returns `{settled, capped, waited_ms, n_nodes}` everywhere; `navigate(ev, engine, url, max_wait=DEFAULT_MAX_WAIT) -> that dict`; `_capture_one(…, max_wait=DEFAULT_MAX_WAIT)` attaches it as `sk["settle"]`; `read()` signal keys `{n, ready, inflight, since_start_ms}` match `_SETTLE_JS`'s returned object exactly. ✓

**Every commit GREEN:** Tasks 1-3 each end on a passing suite; Task 4 commits a fixture (no suite impact) then the controller runs the gate; Task 5 is docs + file removal. No red commits. ✓

**Backward-compat:** `navigate`'s added kwarg + return value don't break the 7 existing callers (all ignore the return). Skeleton schema stays `probe-skeleton/2` (`settle` is an additive top-level key, like P2's per-node `substrate`). ✓
