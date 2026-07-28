#!/usr/bin/env python3
"""Enter text into a Flutter text field — the canonical keyboard path.

Routing text through `EditableTextState.updateEditingValue` (the same path
marionette_flutter uses) fires the field's full input pipeline — input
formatters, validation, AND `onChanged` — exactly like a real keystroke. This
matters because OS-level injection (`adb shell input text` / `idb ui text`)
injects into the IME and does NOT reliably fire Flutter's `onChanged`, so a
form's validity gate (e.g. a "Send code" button disabled until the email regex
passes) never enables during automated driving — a working feature looks broken.

Locate the field by `--type` (EditableText / TextField / CupertinoTextField /
an app-specific wrapper like AdaptiveTextField) or `--key`, OR target the
currently-focused field (`--focused`). The `EditableTextState` is found in the
matched element's subtree (or via `FocusManager.instance.primaryFocus` for
`--focused`).

Usage:
  flutter_set_text.py --focused --text "you@example.com"
  flutter_set_text.py --type AdaptiveTextField --text "you@example.com"
  flutter_set_text.py --key emailField --text "you@example.com"
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import die, emit_json
from _flutter import VMLib


def _predicate(type_: str | None, key: str | None) -> str:
    parts = []
    if type_:
        parts.append('rt=="%s"' % type_)
    if key:
        parts.append('(e.widget.key?.toString()??"").contains("%s")' % key)
    return "||".join(parts) if parts else "false"


# One closure: find the first EditableTextState (optionally under a matched
# widget), call updateEditingValue with the text, schedule a frame. Multi-line
# is fine — _flutter.ev collapses newlines (dart-lang/sdk#41671). Reads nothing
# private — EditableTextState + TextEditingValue are in package:flutter.
def _build_expr(type_: str | None, key: str | None, text: str) -> str:
    pred = _predicate(type_, key)
    safe = text.replace("\\", "\\\\").replace("'", "\\'")
    # The field's STATE is EditableTextState; its WIDGET is EditableText. The caller's
    # --type is usually a WRAPPER (e.g. AdaptiveTextField) whose subtree contains the
    # EditableTextState, so the locator predicate is tested against the matched element
    # AND its ancestors (walk up until the wrapper type/key matches). With no locator,
    # the first EditableTextState on screen wins.
    has_locator = bool(type_ or key)
    # Pre-build the ancestor-match block so the final expression is one clean concat.
    ancestor_block = (
        ' var ce=e;'
        ' while(ce!=null){'
        '  if((ce.widget.runtimeType.toString()=="%s")||(ce.widget.key?.toString()??"").contains("%s")){ match=true; break; }'
        '  ce=ce.parent;'
        ' }'
    ) % (type_ or "", key or "") if has_locator else ""
    match_set = "match=true;" if not has_locator else ancestor_block
    return (
        '(() {'
        ' var done="no field";'
        ' void apply(var ets) {'
        '  ets.updateEditingValue(TextEditingValue(text: "' + safe + '",'
        '   selection: TextSelection.collapsed(offset: ' + str(len(text)) + ')));'
        '  WidgetsBinding.instance.scheduleFrame();'
        '  done="ok";'
        ' }'
        ' void w(Element e) {'
        '  if (e is StatefulElement) {'
        '   var st=e.state;'
        '   if (st.runtimeType.toString()=="EditableTextState") {'
        '    var match=false;'
        + match_set +
        '    if(match){ apply(st); return; }'
        '   }'
        '  }'
        '  e.visitChildren((c)=>w(c));'
        ' }'
        ' var r=WidgetsBinding.instance.rootElement;'
        ' if(r!=null) w(r);'
        ' return done;'
        '})()'
    )


def _build_focused_expr(text: str) -> str:
    safe = text.replace("\\", "\\\\").replace("'", "\\'")
    return (
        '(() {'
        ' var fn=FocusManager.instance.primaryFocus;'
        ' if (fn==null||fn==FocusManager.instance.rootScope) return "no focus";'
        ' var ctx=fn.context;'
        ' if (ctx==null) return "no context";'
        ' var found=null;'
        ' ctx.visitAncestorElements((e){'
        '  if (e is StatefulElement && e.state.runtimeType.toString()=="EditableTextState") {'
        '   found=e.state; return false;'
        '  }'
        '  return true;'
        ' });'
        ' if (found==null) return "focused element not a field";'
        ' found.updateEditingValue(TextEditingValue(text: "' + safe + '",'
        '  selection: TextSelection.collapsed(offset: ' + str(len(text)) + ')));'
        ' WidgetsBinding.instance.scheduleFrame();'
        ' return "ok";'
        '})()'
    )


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--type", help="widget type to locate (EditableText, TextField, "
                                  "CupertinoTextField, AdaptiveTextField, …)")
    p.add_argument("--key", help="widget Key value to locate")
    p.add_argument("--focused", action="store_true",
                   help="target the currently-focused field (tap it first)")
    p.add_argument("--target", choices=["ios", "adb"],
                   help="which device's VM to drive (omit to use the cached URL). "
                        "REQUIRED when two devices are running — without it, the "
                        "global cache may hold the OTHER device's URL and the text "
                        "goes into the wrong app.")
    p.add_argument("--text", required=True, help="text to enter")
    args = p.parse_args()

    if not any([args.type, args.key, args.focused]):
        die("pass --focused, --type, or --key")

    from _flutter import with_target_url
    try:
        with with_target_url(args.target):
            lib = VMLib()
            expr = (_build_focused_expr(args.text) if args.focused
                    else _build_expr(args.type, args.key, args.text))
            result = lib.ev(expr)
    except Exception as e:
        die(str(e))

    ok = result == "ok"
    emit_json({"text": args.text, "locator": ("focused" if args.focused
                 else (args.type or args.key)), "entered": ok, "detail": result})
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
