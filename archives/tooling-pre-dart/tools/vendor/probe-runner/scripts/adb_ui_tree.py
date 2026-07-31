#!/usr/bin/env python3
"""Dump UI hierarchy via uiautomator + convert XML to JSON."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _adb import adb_cmd, adb_shell
from _common import OUTDIR, die, emit_path, out_path


def xml_to_json(el: ET.Element) -> dict:
    return {
        "tag": el.tag,
        "attrs": dict(el.attrib),
        "children": [xml_to_json(c) for c in list(el)],
    }


def main() -> int:
    argparse.ArgumentParser(description="Dump Android UI hierarchy as JSON.").parse_args()
    # Use /data/local/tmp (always adb-pullable on every Android >= 4) rather
    # than /sdcard (subject to scoped storage on Android 11+).
    remote = "/data/local/tmp/window_dump.xml"
    adb_shell(f"uiautomator dump {remote}")
    local = OUTDIR / "window_dump.xml"
    adb_cmd(["pull", remote, str(local)], stderr=subprocess.DEVNULL)
    tree = ET.parse(local)
    out = out_path("android", "json", kind="ui")
    out.write_text(json.dumps(xml_to_json(tree.getroot()), indent=2))
    emit_path(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
