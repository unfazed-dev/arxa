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
