#!/usr/bin/env python3
"""Shared Flutter / Dart VM-service helpers."""

from __future__ import annotations

import json
import os
import re
import time
import urllib.request
from pathlib import Path
from typing import Any, Optional


def cached_url_path() -> Path:
    return Path(os.environ.get("PROBE_RUNNER_OUTDIR", "/tmp/probe-runner")) / "flutter.url"


def _device_url_path(target: str) -> Path:
    """Per-device cache file (flutter.url.ios / flutter.url.adb). A device's VM
    URL is stable for the life of the app, so caching per-device lets a probe
    switch targets instantly without re-discovering (which only works right after
    launch — the URL line scrolls out of the log buffer)."""
    return Path(os.environ.get("PROBE_RUNNER_OUTDIR", "/tmp/probe-runner")) / f"flutter.url.{target}"


def cached_url(target: Optional[str] = None) -> Optional[str]:
    # When a target is given, prefer that device's per-device cache (the multi-
    # device fix); fall back to the legacy global cache for back-compat.
    if target:
        p = _device_url_path(target)
        if p.exists():
            return p.read_text().strip() or None
    p = cached_url_path()
    if p.exists():
        return p.read_text().strip() or None
    return os.environ.get("PROBE_RUNNER_FLUTTER_VM")


def save_url(url: str, target: Optional[str] = None) -> None:
    # Save to the global cache (back-compat) AND, when a target is known, to that
    # device's per-device cache so the next --target resolves instantly.
    p = cached_url_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(url + "\n")
    if target:
        _device_url_path(target).write_text(url + "\n")


def to_ws(url: str) -> str:
    """Convert http://host:port/<auth>/ to ws://host:port/<auth>/ws."""
    u = url
    if u.startswith("http://"):
        u = "ws://" + u[len("http://"):]
    elif u.startswith("https://"):
        u = "wss://" + u[len("https://"):]
    if not u.endswith("/ws"):
        if not u.endswith("/"):
            u += "/"
        u += "ws"
    return u


_AUTH_URL_RE = re.compile(r"(http://[^\s]+?=/)")
_BARE_URL_RE = re.compile(
    r"(?:Dart VM [Ss]ervice|Observatory)[^\n]*?"
    r"(?:listening|available)\s+(?:on|at:?)\s+(http://\S+)"
)


def _normalize_vm_url(url: str) -> str:
    """Preserve the Dart VM auth-code suffix (token ends in '=', followed by '/').

    `flutter run` (without --disable-service-auth-codes) prints URLs of the
    form `http://host:port/<TOKEN>=/`. Naive regexes strip the trailing `=`
    and the WS handshake then 403s. Re-attach the `=/` if it was lost.
    """
    url = url.rstrip(",.)\"'")
    # If the URL already has a trailing /, ensure any preceding '=' is preserved.
    # Common observed forms after stripping:
    #   http://127.0.0.1:51569/<TOKEN>=/   ← canonical, keep
    #   http://127.0.0.1:51569/<TOKEN>=    ← missing trailing slash, add it
    #   http://127.0.0.1:51569/<TOKEN>/    ← stripped '='; cannot recover, leave
    if url.endswith("="):
        url += "/"
    return url


def parse_url_from_text(text: str) -> Optional[str]:
    # Covers all observed shapes:
    #   "Dart VM service listening on http://..."                       (older)
    #   "Observatory listening on http://..."                           (legacy)
    #   "A Dart VM Service on iPhone ... is available at: http://..."   (modern)
    # Prefer the auth-suffixed form (`...=/`) so we don't lose the auth code.
    m = _AUTH_URL_RE.search(text)
    if m:
        return _normalize_vm_url(m.group(1))
    m = _BARE_URL_RE.search(text)
    if m:
        return _normalize_vm_url(m.group(1))
    return None


def rpc(method: str, params: Optional[dict] = None,
        url: Optional[str] = None, isolate: Optional[str] = None,
        timeout: float = 10.0) -> Any:
    try:
        from websocket import create_connection  # type: ignore
    except ImportError:
        raise RuntimeError("missing websocket-client: pip3 install websocket-client")

    url = url or cached_url()
    if not url:
        raise RuntimeError(
            "no Flutter VM service URL. run flutter_attach.py first, or set PROBE_RUNNER_FLUTTER_VM"
        )
    ws_url = to_ws(url)
    try:
        ws = create_connection(ws_url, timeout=timeout)
    except Exception as e:
        if type(e).__name__ == "WebSocketBadStatusException":
            raise RuntimeError(
                "Flutter VM service rejected the handshake (likely 403: "
                "missing or invalid auth code). The cached WS URL may have "
                "stripped the trailing '=' from the auth segment. Re-run "
                "flutter_attach.py with the full '<TOKEN>=/' suffix, or "
                "relaunch `flutter run --disable-service-auth-codes` to drop "
                "the token entirely. Underlying error: " + str(e)
            )
        raise
    try:
        params = dict(params or {})
        if isolate:
            params.setdefault("isolateId", isolate)
        ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}))
        while True:
            msg = json.loads(ws.recv())
            if msg.get("id") == 1:
                if "error" in msg:
                    raise RuntimeError(json.dumps(msg["error"]))
                return msg.get("result")
    finally:
        ws.close()


def first_isolate() -> str:
    vm = rpc("getVM")
    isolates = vm.get("isolates") or []
    if not isolates:
        raise RuntimeError("no isolates")
    return isolates[0]["id"]


def resolve_vm_url(target: str) -> str:
    """Resolve the VM service URL for a SPECIFIC device, not the global cache.

    Order: (1) the per-device cache (a URL is stable for the app's life — a device
    attached once never needs re-discovery), (2) live discovery via flutter_attach
    --auto --source. The global cache (`flutter.url`) holds whatever URL was last
    attached — with two devices running, `--target adb` must NOT reuse the iOS URL
    it happens to hold (that mismatch made a probe sample the iOS tree against an
    Android screenshot). `target` is 'ios' or 'adb'."""
    cached = cached_url(target)
    if cached:
        return cached
    import subprocess
    from pathlib import Path
    script = Path(__file__).resolve().parent / "flutter_attach.py"
    src = "ios" if target == "ios" else "adb"
    r = subprocess.run(
        ["python3", str(script), "--auto", "--source", src, "--timeout", "12"],
        capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        hint = (r.stderr or r.stdout or "").strip().splitlines()
        raise RuntimeError(
            f"could not discover the {target} VM service URL ({src}): "
            + (hint[-1] if hint else "no output. Is the app running via "
               f"`flutter run -d <{target}> --disable-service-auth-codes`? "
               "(cold-launch does not expose the VM service — see SKILL.md)"))
    url = cached_url(target)
    if not url:
        raise RuntimeError(f"flutter_attach returned no URL for {target}")
    return url


def with_target_url(target: Optional[str]):
    """Context manager: ensure the cached VM URL is the one for `target` (if given).
    No-op when target is None (use the cache).

    This is the multi-device fix: a probe with --target adb resolves the Android
    VM URL (from the per-device cache, or live discovery) for the duration of its
    VM calls. The global cache is left untouched so an iOS probe running
    concurrently isn't disrupted."""
    from contextlib import contextmanager

    @contextmanager
    def _cm():
        if not target:
            yield
            return
        # Stash the current global cache, point it at this device's URL, restore after.
        global_path = cached_url_path()
        prev_global = global_path.read_text() if global_path.exists() else None
        url = resolve_vm_url(target)
        global_path.write_text(url + "\n")
        try:
            yield
        finally:
            if prev_global is not None:
                global_path.write_text(prev_global)
    return _cm()


class VMLib:
    """Evaluates Dart expressions against the isolate's root library.

    The inspector's `valueId` is NOT a valid VM `evaluate` targetId (VM rejects
    it with error 113), so we never use the inspector: we evaluate self-contained
    Dart expressions against `getIsolate().rootLib.id` (always a valid targetId).
    The root library imports flutter material, so `WidgetsBinding`, `Element`,
    `ScrollableState`, `RenderObject`, `Matrix4` etc. are all in scope. Shared by
    `flutter_anim` (scroll-easing measurement) and `flutter_eval` (one-shot eval),
    so both reach the VM identically. websocket import stays lazy (inside `rpc`),
    keeping importers dep-free until an actual eval runs."""

    def __init__(self):
        self.iso = first_isolate()
        iso = rpc("getIsolate", {"isolateId": self.iso})
        lib = (iso or {}).get("rootLib", {}).get("id")
        if not lib:
            raise RuntimeError("isolate has no rootLib")
        self.lib = lib

    def ev(self, expr: str):
        # The VM `evaluate` RPC mis-tokenizes literal newlines (dart-lang/sdk#41671):
        # a multi-line closure like `(() {\n return x;\n})()` fails to compile with
        # "Can't find '}' to match '{'" because the compiler front-end only parses the
        # first line. Collapsing newlines to spaces fixes it (statements separated by
        # spaces parse identically to newlines). This unblocks multi-line closures in
        # flutter_eval / flutter_skeleton / flutter_anim / flutter_flipbook.
        expr = expr.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
        r = rpc("evaluate",
                {"isolateId": self.iso, "targetId": self.lib, "expression": expr})
        if isinstance(r, dict):
            if r.get("type") == "@Error" or r.get("kind") == "Error":
                raise RuntimeError(r.get("valueAsString") or r.get("message")
                                   or json.dumps(r)[:200])
            # Large strings come back truncated (`valueAsStringIsTruncated=true`) — the
            # VM caps valueAsString at ~128 chars. For a 3000-row skeleton dump that loses
            # all but the first ~2 rows. When truncated, fetch the full value via getObject
            # on the returned object id (untruncated). ponytail: only the extra round-trip
            # when the flag is set, so short evals pay nothing.
            if r.get("valueAsStringIsTruncated"):
                oid = r.get("id")
                if oid:
                    o = rpc("getObject", {"objectId": oid, "isolateId": self.iso})
                    full = o.get("valueAsString")
                    if full is not None:
                        return full
            v = r.get("valueAsString")
            if v is not None:
                return v
        return r
