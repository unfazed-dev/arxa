#!/usr/bin/env python3
"""Push or pull files to/from an iOS sim app container.

Usage:
  ios_files.py push <local> <bundle-id> <remote-path>
  ios_files.py pull <bundle-id> <remote-path> <local-dest>
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _ios import idb_bin
from _common import die, emit_json


# Phrases that indicate idb logged an error but still returned rc=0.
# idb emits these via its `Info: [...]` channel; we promote them to rc=2.
_ERROR_MARKERS = (
    "Error Domain=",
    "NSUnderlyingError",
    "Source path does not exist",
    "couldn't be opened because",
    "No such file or directory",
)


def _run_idb_file(verb: str, args: list[str]) -> None:
    """Run `idb file <verb> ... --application <bid>`, raising rc=2 if idb's
    own logs reveal a failure that it swallowed into rc=0.

    Modern idb (>=1.1) deprecated `--bundle-id` in favor of `--application`;
    using the old flag emits a deprecation warning but still works. We use
    the new flag.
    """
    cmd = [idb_bin(), "file", verb, *args]
    r = subprocess.run(cmd, capture_output=True, text=True, check=False)
    combined = (r.stdout or "") + "\n" + (r.stderr or "")
    if r.returncode != 0:
        die(f"idb file {verb} failed: {(r.stderr or r.stdout or '').strip()}",
            code=r.returncode or 2)
    for marker in _ERROR_MARKERS:
        if marker in combined:
            die(f"idb file {verb} logged an error but returned rc=0: "
                f"{combined.strip()}", code=2)


def main() -> int:
    p = argparse.ArgumentParser(prog="ios_files.py", description=__doc__)
    sub = p.add_subparsers(dest="verb", required=True)
    p_push = sub.add_parser("push")
    p_push.add_argument("local", metavar="<local>")
    p_push.add_argument("bundle_id", metavar="<bundle-id>")
    p_push.add_argument("remote", metavar="<remote-path>")
    p_pull = sub.add_parser("pull")
    p_pull.add_argument("bundle_id", metavar="<bundle-id>")
    p_pull.add_argument("remote", metavar="<remote-path>")
    p_pull.add_argument("local", metavar="<local-dest>")
    args = p.parse_args()

    if args.verb == "push":
        local, bid, remote = args.local, args.bundle_id, args.remote
        # With --application, the bundle-id is prefixed into the dest path
        # (per idb's deprecation warning when using --bundle-id directly).
        prefixed = f"{bid}/{remote.lstrip('/')}"
        _run_idb_file("push", [local, prefixed, "--application"])
        emit_json({"pushed": local, "to": prefixed, "bundle_id": bid})
    elif args.verb == "pull":
        bid, remote, local = args.bundle_id, args.remote, args.local
        prefixed = f"{bid}/{remote.lstrip('/')}"
        _run_idb_file("pull", [prefixed, local, "--application"])
        emit_json({"pulled": prefixed, "to": local, "bundle_id": bid})
    return 0


if __name__ == "__main__":
    sys.exit(main())
