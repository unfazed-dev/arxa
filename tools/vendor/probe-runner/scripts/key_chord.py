#!/usr/bin/env python3
"""Send a key chord (modifier+key) to the target app.

Examples:
  key_chord.py <owner> "cmd+shift+s"
  key_chord.py <owner> "ctrl+c"
  key_chord.py <owner> "return"
  key_chord.py <owner> "tab" --repeat 3
  key_chord.py <owner> "cmd+shift" --hold-ms 1500   # hold modifiers 1.5 s
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, secure_input_active, which_or_die

MOD_MAP = {
    "cmd": "command down", "command": "command down",
    "shift": "shift down",
    "opt": "option down", "alt": "option down", "option": "option down",
    "ctrl": "control down", "control": "control down",
    "fn": "function down",
}

CLICLICK_MOD_MAP = {
    "cmd": "cmd", "command": "cmd",
    "shift": "shift",
    "opt": "alt", "alt": "alt", "option": "alt",
    "ctrl": "ctrl", "control": "ctrl",
    "fn": "fn",
}

NAMED_KEYS = {
    "return": 36, "enter": 36,
    "tab": 48,
    "space": 49,
    "delete": 51, "backspace": 51,
    "escape": 53, "esc": 53,
    "right": 124, "left": 123, "up": 126, "down": 125,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
}


def _activate(owner: str) -> None:
    """Bring the target frontmost. Tries, in order:

    1. System Events `set frontmost of (first process whose unix id
       is <pid>) to true` — PID-based, works for bundle-less binaries
       (e.g. `cargo run --example` Dioxus apps) that Launch Services
       doesn't know about.
    2. `tell application "<owner>" to activate` — Launch Services
       path, the original behaviour. Preserved for bundled apps that
       expose a normal AppleScript dictionary.
    3. `cliclick` click on the window's centre point — last-resort
       focus by mouse click. Useful when both osascript paths fail
       on a wry/Tauri app whose AX role is non-standard.

    Dies loudly via `die()` on full failure rather than silently
    letting subsequent `keystroke` events leak to whatever app is
    currently frontmost (which is what the original name-only
    implementation did when `tell application "<owner>"` returned
    -1728 for a non-bundle target).
    """
    win = resolve_window(owner)
    pid = win["pid"]

    script = (
        'tell application "System Events" '
        f'to set frontmost of (first process whose unix id is {pid}) '
        'to true'
    )
    r = subprocess.run(
        ["osascript", "-e", script],
        check=False, capture_output=True, text=True,
    )
    if r.returncode == 0:
        return

    r2 = subprocess.run(
        ["osascript", "-e", f'tell application "{owner}" to activate'],
        check=False, capture_output=True, text=True,
    )
    if r2.returncode == 0:
        return

    try:
        cliclick = which_or_die("cliclick", "brew install cliclick")
    except SystemExit:
        die(
            f"could not focus '{owner}' (pid={pid}); both PID and "
            f"name-based osascript activate failed and cliclick is "
            f"not installed for a click fallback. "
            f"pid-path: {r.stderr.strip()!r}; "
            f"name-path: {r2.stderr.strip()!r}"
        )
    b = win["bounds"]
    cx = b["x"] + b["w"] // 2
    cy = b["y"] + b["h"] // 2
    r3 = subprocess.run(
        [cliclick, f"c:{cx},{cy}"],
        check=False, capture_output=True, text=True,
    )
    if r3.returncode != 0:
        die(
            f"could not focus '{owner}' (pid={pid}); pid-path, "
            f"name-path, and cliclick-click all failed. "
            f"pid-path: {r.stderr.strip()!r}; "
            f"name-path: {r2.stderr.strip()!r}; "
            f"cliclick: {r3.stderr.strip()!r}"
        )


def _build(chord: str) -> tuple[list[str], str]:
    parts = [p.strip().lower() for p in chord.split("+") if p.strip()]
    if not parts:
        die("empty chord")
    key = parts[-1]
    mods = parts[:-1]
    # If the trailing token is itself a modifier (e.g. "cmd+shift"), treat the
    # whole chord as modifier-only — no key to send, hold-only payload.
    if key in MOD_MAP and not mods:
        return [key], ""
    if key in MOD_MAP:
        return parts, ""
    return mods, key


def _run_osascript(script: str) -> None:
    subprocess.run(["osascript", "-e", script], check=True)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("chord")
    p.add_argument("--repeat", type=int, default=1)
    p.add_argument("--delay-ms", type=int, default=50)
    p.add_argument("--hold-ms", type=int, default=0,
                   help="hold the chord's modifier keys for N ms via cliclick "
                        "kd:/ku: (any non-modifier key is sent inside the hold window)")
    p.add_argument("--batch", action="store_true",
                   help="read additional chord lines from stdin, one per line, and "
                        "dispatch all of them inside a single osascript tell block")
    args = p.parse_args()

    if args.batch:
        if secure_input_active():
            die("Secure Input is active; synthetic key events are blocked")
        chords = [args.chord]
        for line in sys.stdin:
            line = line.strip()
            if line:
                chords.append(line)
        resolve_window(args.owner)
        _activate(args.owner)
        time.sleep(0.1)
        lines = ['tell application "System Events"']
        for chord in chords:
            mods, key = _build(chord)
            if not key:
                continue
            using_mods = [m for m in mods if m in MOD_MAP]
            using = ", ".join(MOD_MAP[m] for m in using_mods)
            suffix = f" using {{{using}}}" if using else ""
            if key in NAMED_KEYS:
                lines.append(f"\tkey code {NAMED_KEYS[key]}{suffix}")
            else:
                ch = key.replace('"', '\\"')
                lines.append(f'\tkeystroke "{ch}"{suffix}')
            if args.delay_ms > 0:
                lines.append(f"\tdelay {args.delay_ms / 1000.0}")
        lines.append("end tell")
        _run_osascript("\n".join(lines))
        print(f'{{"batch":true,"count":{len(chords)},"delay_ms":{args.delay_ms}}}')
        return 0

    if secure_input_active():
        die("Secure Input is active; synthetic key events are blocked")

    resolve_window(args.owner)
    _activate(args.owner)
    time.sleep(0.1)

    mods, key = _build(args.chord)
    using_mods = [m for m in mods if m in MOD_MAP]
    using = ", ".join(MOD_MAP[m] for m in using_mods)

    def _build_keystroke_script(skip_osascript_modifiers: bool = False) -> str | None:
        # When the chord's modifiers are already held via cliclick (the
        # --hold-ms path), don't ask osascript to also synthesize them with
        # `using {command down}` — that double-presses the modifier.
        suffix = "" if skip_osascript_modifiers or not using else f" using {{{using}}}"
        if not key:
            return None
        if key in NAMED_KEYS:
            code = NAMED_KEYS[key]
            return f'tell application "System Events" to key code {code}{suffix}'
        else:
            ch = key.replace('"', '\\"')
            return f'tell application "System Events" to keystroke "{ch}"{suffix}'

    if args.hold_ms > 0:
        cliclick = which_or_die("cliclick", "brew install cliclick")
        cli_mods = [CLICLICK_MOD_MAP[m] for m in using_mods if m in CLICLICK_MOD_MAP]
        if not cli_mods and not key:
            die("--hold-ms requires at least one modifier in the chord "
                "(cliclick kd:/ku: supports cmd/alt/shift/ctrl/fn only)")
        if cli_mods:
            subprocess.run([cliclick, f"kd:{','.join(cli_mods)}"], check=True)
        try:
            for i in range(args.repeat):
                script = _build_keystroke_script(skip_osascript_modifiers=bool(cli_mods))
                if script is not None:
                    _run_osascript(script)
                if i + 1 < args.repeat:
                    time.sleep(args.delay_ms / 1000.0)
            time.sleep(args.hold_ms / 1000.0)
        finally:
            if cli_mods:
                subprocess.run([cliclick, f"ku:{','.join(reversed(cli_mods))}"], check=False)
    else:
        if args.repeat <= 0:
            pass  # no-op: zero repetitions requested
        elif args.repeat == 1:
            script = _build_keystroke_script()
            if script is not None:
                _run_osascript(script)
        else:
            script = _build_keystroke_script()
            if script is None:
                pass  # empty key — nothing to send
            else:
                # Strip the single-line prefix so we can embed the statement
                # inside a block-form `tell` that holds modifiers across all N
                # keystrokes, preventing a foreground swap between iterations.
                _SINGLE_TELL_PREFIX = 'tell application "System Events" to '
                inner = script.removeprefix(_SINGLE_TELL_PREFIX)
                delay_s = args.delay_ms / 1000.0
                lines = ['tell application "System Events"']
                for i in range(args.repeat):
                    lines.append(f"\t{inner}")
                    if i + 1 < args.repeat:
                        lines.append(f"\tdelay {delay_s}")
                lines.append("end tell")
                _run_osascript("\n".join(lines))

    print(f'{{"chord":"{args.chord}","repeat":{args.repeat},"hold_ms":{args.hold_ms}}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
