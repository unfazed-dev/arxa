#!/usr/bin/env python3
"""Type a string into the focused field of the target app.

Usage:
  type_text.py <owner> <text>          # focuses + cliclick t:
  type_text.py <owner> <text> --paste  # pasteboard + cmd+v (handles Unicode reliably)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, resolve_window, run, secure_input_active, which_or_die


def _activate(owner: str) -> None:
    subprocess.run(
        ["osascript", "-e", f'tell application "{owner}" to activate'],
        check=False, capture_output=True,
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("owner")
    p.add_argument("text")
    p.add_argument("--paste", action="store_true")
    args = p.parse_args()

    if secure_input_active():
        die("Secure Input is active; synthetic typing is blocked")

    resolve_window(args.owner)  # validate
    _activate(args.owner)
    time.sleep(0.1)

    if args.paste:
        pbcopy = which_or_die("pbcopy", "bundled with macOS")
        subprocess.run([pbcopy], input=args.text, text=True, check=True)
        subprocess.run(
            ["osascript", "-e",
             f'tell application "System Events" to keystroke "v" using {{command down}}'],
            check=True,
        )
    else:
        cliclick = which_or_die("cliclick", "brew install cliclick")
        run([cliclick, f"t:{args.text}"])

    print(f'{{"typed":{len(args.text)}}}')
    return 0


if __name__ == "__main__":
    sys.exit(main())
