#!/usr/bin/env python3
"""Shared iOS / idb helpers — wrap idb invocations so missing-daemon
or missing-target failures exit gracefully instead of raising
CalledProcessError tracebacks at script callers.

Target resolution: PROBE_RUNNER_IOS_UDID pins the target explicitly
(mirrors _adb.py's PROBE_RUNNER_ADB_SERIAL) > the single booted simulator
> the first booted simulator (with a loud stderr warning naming the pick
and the env-var override). On the no-target / no-companion failure class,
idb_run attempts a single auto-recovery: connect the resolved target
(`idb connect <udid>`) and retry the original command once, pinned to that
UDID. If that still fails, the death message states the exact remediation
commands.

idb_popen is the streaming sibling (e.g. ios_log): same target resolution
and one-shot recovery against the process's early exit, then the live
handle is returned to the caller.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time

ENV_UDID = "PROBE_RUNNER_IOS_UDID"


def idb_bin() -> str:
    p = shutil.which("idb")
    if not p:
        print("probe-runner: missing 'idb'. install: brew tap facebook/fb && "
              "brew install idb-companion && pipx install fb-idb",
              file=sys.stderr)
        sys.exit(2)
    return p


def _booted_udids() -> list[str]:
    """UDIDs of currently booted simulators, via `xcrun simctl list devices --json`.

    Cheap and defensive: xcrun missing, non-macOS, simctl failure, or
    unparseable JSON all yield an empty list. Never raises; import-safe
    (only runs when called).
    """
    xc = shutil.which("xcrun")
    if not xc:
        return []
    try:
        r = subprocess.run(
            [xc, "simctl", "list", "devices", "--json"],
            check=False, capture_output=True, text=True, timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0 or not isinstance(r.stdout, str):
        return []
    try:
        data = json.loads(r.stdout)
    except ValueError:
        return []
    devices = data.get("devices")
    if not isinstance(devices, dict):
        return []
    out: list[str] = []
    for devs in devices.values():
        if not isinstance(devs, list):
            continue
        for d in devs:
            if (isinstance(d, dict) and d.get("state") == "Booted"
                    and isinstance(d.get("udid"), str)):
                out.append(d["udid"])
    return out


# idb's own wordings for "no usable target to run against" (matched
# case-insensitively against stderr+stdout):
#   "No udid provided and there no companions, unclear which target to run against"
#   "No Companion Connected" (idb list-targets / companion-not-connected)
#   "Failed to connect to companion at address ... Connection refused" (stale
#   companion socket — process died, file left behind)
_NO_TARGET_MARKERS = ("no udid provided", "no companions",
                      "no companion connected",
                      "failed to connect to companion")


def _is_no_target_failure(text: str) -> bool:
    t = text.lower()
    return any(m in t for m in _NO_TARGET_MARKERS)


def _target_env() -> str | None:
    """The operator's explicit pin (PROBE_RUNNER_IOS_UDID), or None.
    Empty/whitespace counts as unset."""
    v = os.environ.get(ENV_UDID, "").strip()
    return v or None


def _resolve_target_udid(*, warn: bool = False) -> str | None:
    """env pin > single booted sim > first booted sim > None.

    The multi-booted pick only ever fires on the recovery path (when WE must
    guess); it warns loudly, naming the pick and the env-var override."""
    env = _target_env()
    if env:
        return env
    udids = _booted_udids()
    if not udids:
        return None
    if len(udids) > 1 and warn:
        print(f"probe-runner: multiple booted sims ({', '.join(udids)}); "
              f"targeting {udids[0]} — override with {ENV_UDID}=<udid>",
              file=sys.stderr)
    return udids[0]


def _with_udid(args: list[str], udid: str | None) -> list[str]:
    """Append --udid unless the caller already passed one (ios_flipbook et al.
    embed it in args; an explicit caller flag always wins)."""
    if udid and "--udid" not in args:
        return [*args, "--udid", udid]
    return args


def _run(idb: str, args: list[str], *, capture: bool,
         stdout) -> subprocess.CompletedProcess:
    if stdout is not None:
        # Streaming stdout: PIPE stderr separately so the no-target failure
        # class stays detectable (and one-shot recovery possible). On success
        # the captured stderr is relayed so nothing is hidden; on failure it
        # is left for _die / the recovery classifier.
        r = subprocess.run([idb, *args], check=False, text=True,
                           stdout=stdout, stderr=subprocess.PIPE)
        if r.returncode == 0 and r.stderr:
            print(r.stderr, file=sys.stderr, end="")
        return r
    return subprocess.run([idb, *args], check=False,
                          capture_output=capture, text=True)


def _connect(idb: str, udid: str) -> None:
    subprocess.run([idb, "connect", udid],
                   check=False, capture_output=True, text=True)


def _maybe_recover_no_target(idb: str, args: list[str],
                             r: subprocess.CompletedProcess, *,
                             capture: bool,
                             stdout) -> subprocess.CompletedProcess:
    """One-shot auto-recovery for the no-target failure class.

    On a predicate match, connect the resolved target (env pin > single
    booted > first booted + loud warning) and rerun the original command
    ONCE, pinned to that UDID. Any other case returns r unchanged (no retry,
    never a loop). When stderr/stdout were not captured the class cannot be
    detected, so nothing is attempted.
    """
    text = " ".join(s for s in (r.stderr, r.stdout) if isinstance(s, str))
    if not _is_no_target_failure(text):
        return r
    udid = _resolve_target_udid(warn=True)
    if not udid:
        return r
    _connect(idb, udid)
    return _run(idb, _with_udid(args, udid), capture=capture, stdout=stdout)


def _remediation_hint() -> str:
    """Actionable fix-it text with concrete commands (UDID filled in when known)."""
    udids = _booted_udids()
    if len(udids) == 1:
        u = udids[0]
        return (f"(fix: idb_companion --udid {u} &  then  idb connect {u}  "
                f"— or pin the target with {ENV_UDID}={u})")
    if udids:
        return ("(multiple booted sims: " + ", ".join(udids) +
                f"; pin the target with {ENV_UDID}=<udid>, then run: "
                "idb_companion --udid <udid> &  followed by  idb connect <udid>)")
    return ("(no booted simulator found — boot one, then: "
            "idb_companion --udid <udid> &  then  idb connect <udid>)")


def _die(args: list[str], r: subprocess.CompletedProcess) -> None:
    msg = ""
    if isinstance(r.stderr, str) and r.stderr:
        msg = r.stderr.strip()
    if not msg and isinstance(r.stdout, str):
        msg = r.stdout.strip()
    if not msg:
        msg = f"idb {' '.join(args)} failed rc={r.returncode}"
    print(f"probe-runner: {msg} {_remediation_hint()}",
          file=sys.stderr)
    sys.exit(r.returncode or 2)


def idb_run(args: list[str], *, capture: bool = False,
            stdout=None) -> subprocess.CompletedProcess:
    idb = idb_bin()
    pin = _target_env()
    if pin:
        args = _with_udid(args, pin)
    r = _run(idb, args, capture=capture, stdout=stdout)
    if r.returncode != 0:
        r = _maybe_recover_no_target(idb, args, r,
                                     capture=capture, stdout=stdout)
    if r.returncode != 0:
        _die(args, r)
    return r


def idb_popen(args: list[str], *, grace: float = 1.5) -> subprocess.Popen:
    """Spawn a long-lived streaming idb command (e.g. `idb log`) with the
    same target resolution + one-shot no-target recovery as idb_run.

    Waits up to `grace` seconds for an early exit (the no-companion failure
    surfaces within ~1s). On that failure class: connect the resolved target
    and respawn ONCE. Returns the live Popen handle (stdout=PIPE,
    stderr=PIPE, text=True). Dies via _die on persistent early failure.
    """
    idb = idb_bin()

    def spawn(full_args: list[str]) -> subprocess.Popen:
        return subprocess.Popen([idb, *full_args], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)

    pin = _target_env()
    if pin:
        args = _with_udid(args, pin)
    proc = spawn(args)
    time.sleep(grace)
    if proc.poll() is None:
        return proc
    out, err = proc.communicate()
    early = subprocess.CompletedProcess(args, proc.returncode, out, err)
    if _is_no_target_failure(" ".join(s for s in (err, out) if s)):
        udid = _resolve_target_udid(warn=True)
        if udid:
            _connect(idb, udid)
            proc = spawn(_with_udid(args, udid))
            time.sleep(grace)
            if proc.poll() is None:
                return proc
            out, err = proc.communicate()
            early = subprocess.CompletedProcess(args, proc.returncode, out, err)
    _die(args, early)
    raise AssertionError("unreachable")  # _die never returns
