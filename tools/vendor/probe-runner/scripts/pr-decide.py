#!/usr/bin/env python3
"""Route a goal-verb to the right target-class script — read-only resolver.

probe-runner ships ~100 target-prefixed verbs (ios_tap, adb_tap, flutter_tap,
web_click, click, …). At 100+ tools an agent blows past the tool-selection
accuracy sweet-spot (~10-20 tools) and starts guessing the wrong prefix/args.
This resolver is the reverse index: name a GOAL (one of 12 intents) + a TARGET
(one of 6 classes), get back the exact canonical command, its arg shape, the
fallback if it fails, and the edge-case notes. It NEVER executes anything —
copy the printed command and run it.

The manifest `verbs.json` (next to this file) is the single source of truth.

Usage:
  pr-decide.py <intent> [--target <class>]     # resolve one route
  pr-decide.py <intent>                         # all targets for that intent
  pr-decide.py --list                           # list intents + targets
  pr-decide.py                                  # print the full compact matrix
  pr-decide.py --self-test                      # offline logic check
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json  # noqa: E402

MANIFEST = Path(__file__).resolve().parent / "verbs.json"


# ─── manifest loading ────────────────────────────────────────────────────────

def _load() -> dict:
    """Load + structurally validate verbs.json. die() loud if broken/missing.

    A missing or malformed manifest is the top failure mode (manifest drift);
    making it loud rather than silent is the whole point. Never returns None.
    """
    if not MANIFEST.exists():
        die(f"routing manifest not found: {MANIFEST} (expected next to pr-decide.py)")
    try:
        m = json.loads(MANIFEST.read_text())
    except json.JSONDecodeError as e:
        die(f"routing manifest {MANIFEST} is not valid JSON: {e}")
    for key in ("intents", "targets", "routes"):
        if key not in m:
            die(f"routing manifest {MANIFEST} missing top-level key '{key}'")
    if set(m["routes"].keys()) != set(m["intents"]):
        die(
            "routing manifest routes drift from declared intents: "
            f"declared={sorted(m['intents'])} routes={sorted(m['routes'])}"
        )
    return m


# ─── formatting ──────────────────────────────────────────────────────────────

def _command(script: str | None, args: list[str]) -> str | None:
    """Assemble the copy-pasteable command line, or None for a null-script gap."""
    if script is None:
        return None
    return "python3 scripts/" + script + ((" " + " ".join(args)) if args else "")


def _route_row(intent: str, target: str, route: dict[str, Any]) -> dict[str, Any]:
    """Shape one route for emit_json: command + script + args + fallback + notes."""
    script = route.get("script")
    args = route.get("args", [])
    return {
        "intent": intent,
        "target": target,
        "command": _command(script, args),
        "script": script,
        "args": args,
        "fallback": route.get("fallback"),
        "notes": route.get("notes"),
    }


def _print_matrix(m: dict) -> None:
    """Print a compact human cheatsheet: 12 intent rows x 6 target columns.

    One script name (or '-') per cell. The always-loaded fast path; full arg
    shapes/fallbacks come from resolving a single route.
    """
    targets = m["targets"]
    intents = m["intents"]
    col = max([len(t) for t in targets] + [6])  # header col width
    width = 18                                   # script-name cell width
    header = "intent".ljust(col) + "  " + "  ".join(t.ljust(width) for t in targets)
    print(header)
    print("-" * len(header))
    for intent in intents:
        cells = []
        for t in targets:
            r = m["routes"][intent].get(t, {})
            s = r.get("script") or "-"
            if len(s) > width:
                s = s[: width - 1] + "…"
            cells.append(s.ljust(width))
        print(intent.ljust(col) + "  " + "  ".join(cells))
    print(
        "\n'-' = no dedicated verb (resolve the route for the alternative). "
        "Run: pr-decide.py <intent> --target <class>   for args + fallback + notes."
    )


def _print_list(m: dict) -> None:
    print("intents  :", ", ".join(m["intents"]))
    print("targets  :", ", ".join(m["targets"]))
    print(
        "\nusage    : pr-decide.py <intent> [--target <class>]\n"
      + "           pr-decide.py <intent>           (all targets)\n"
      + "           pr-decide.py                    (full matrix)\n"
      + "           pr-decide.py --list"
    )


# ─── self-test (offline, pure logic) ─────────────────────────────────────────

def _self_test(m: dict) -> int:
    """Verify the resolver's invariants offline. rc=0 pass, rc=1 fail."""
    ok = True

    def check(cond: bool, msg: str) -> None:
        nonlocal ok
        if not cond:
            print(f"FAIL {msg}", file=sys.stderr)
            ok = False

    # declared intents/targets match the route structure
    check(set(m["routes"].keys()) == set(m["intents"]), "route intents == declared")
    for intent, by_target in m["routes"].items():
        check(set(by_target.keys()) == set(m["targets"]), f"{intent}: all targets present")
        for tgt, r in by_target.items():
            check(all(k in r for k in ("script", "args", "fallback", "notes")),
                  f"{intent}/{tgt}: all keys present")
            if r["script"] is not None:
                # drift check: every non-null script exists on disk
                check((Path(__file__).resolve().parent / r["script"]).exists(),
                      f"{intent}/{tgt}: script {r['script']} exists on disk")
                check(isinstance(r["args"], list), f"{intent}/{tgt}: args is a list")
    print(json.dumps({"self_test": "pass" if ok else "FAIL"}))
    return 0 if ok else 1


# ─── main ────────────────────────────────────────────────────────────────────

def main() -> int:
    p = argparse.ArgumentParser(
        prog="pr-decide.py",
        description="Route a goal-verb to the right probe-runner target script (read-only).",
    )
    p.add_argument("intent", nargs="?", help="goal verb: one of the 12 intents (--list to see)")
    p.add_argument("--target", "-t", dest="target",
                   help="target class: one of the 6 targets (--list to see)")
    p.add_argument("--list", dest="list_", action="store_true",
                   help="list intents + targets, then exit")
    p.add_argument("--self-test", dest="self_test", action="store_true",
                   help="run offline invariant checks, then exit")
    args = p.parse_args()

    m = _load()

    if args.self_test:
        return _self_test(m)
    if args.list_:
        _print_list(m)
        return 0
    if args.intent is None:
        _print_matrix(m)
        return 0

    intent = args.intent
    if intent not in m["routes"]:
        die(f"unknown intent '{intent}'. Valid: {', '.join(m['intents'])} (--list)")
    if args.target is not None and args.target not in m["targets"]:
        die(f"unknown target '{args.target}'. Valid: {', '.join(m['targets'])} (--list)")

    by_target = m["routes"][intent]
    if args.target is None:
        rows = [_route_row(intent, t, by_target[t]) for t in m["targets"]]
        emit_json({"intent": intent, "targets": m["targets"], "routes": rows})
    else:
        emit_json(_route_row(intent, args.target, by_target[args.target]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
