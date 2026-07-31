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
