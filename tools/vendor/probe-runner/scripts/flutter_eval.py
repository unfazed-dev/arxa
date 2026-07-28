#!/usr/bin/env python3
"""Evaluate a Dart expression in a running Flutter app and print the result.

The Dart-VM-service sibling of `web_eval`: where web_eval runs JS over CDP /
WebDriver, this runs a self-contained Dart *expression* against the isolate's
root library over the VM service (`_flutter.VMLib`, shared with `flutter_anim`).
The root library imports flutter material, so `WidgetsBinding`, `Element`,
`ScrollableState`, `RenderObject`, `Matrix4` etc. are in scope.

Native (non-web) iOS/Android UIs have no JS engine — for those use
`adb_ui_tree` / `ios_ui_tree`. This verb is for Flutter only.

Usage:
  flutter_attach.py --url http://127.0.0.1:PORT/      # cache the VM service URL
  flutter_eval.py "1 + 2"
  flutter_eval.py "WidgetsBinding.instance.rootElement!.widget.runtimeType.toString()"
  flutter_eval.py "(() { var n=0; void r(Element e){n++; e.visitChildren(r);} \
      r(WidgetsBinding.instance.rootElement!); return n.toString(); })()"
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import VMLib

_RECIPE = (
    "no Flutter VM service. run `flutter_attach.py --url http://127.0.0.1:<PORT>/` "
    "first (PORT from `flutter run --disable-service-auth-codes` output), or set "
    "PROBE_RUNNER_FLUTTER_VM. The expression is evaluated against the root library; "
    "if a name is out of scope or a cast fails, the VM error is printed.")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("expr", help="a Dart expression returning a JSON-serialisable value")
    args = p.parse_args()

    try:
        lib = VMLib()
    except Exception as e:
        die("%s (%s)" % (_RECIPE, e))

    try:
        value = lib.ev(args.expr)
    except Exception as e:
        die("VM eval failed: %s" % e)

    emit_json({"engine": "flutter", "device": "vm-service", "value": value})
    return 0


if __name__ == "__main__":
    sys.exit(main())
