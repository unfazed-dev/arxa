#!/usr/bin/env python3
"""Append the picker composer's reply key to all three ARBs, key-for-key.

Same contract as _add_scaffold_run_keys.py: en is the SSOT, pl is
hand-translated, qps-ploc is generated with the identical pseudolocalizer
([!! accented ~̷~ !!], ~30% expansion). Idempotent: re-running rewrites only
this key.

Copy tone note: the picker's agent has no reply corpus (unlike intake, which
owns replies/replyFallback in its repository). This is a fixed acknowledgement
and it must not promise an action the screen does not take — nothing is
applied by sending a message; the Continue CTA is what applies. The string
says exactly that, and matches the tone of thread.help, which already tells
the user nothing is locked in.
"""
import json
import math
import re
from collections import OrderedDict

EN = {
    "scaffold.picker.thread.reply": "Noted. Nothing is applied until you continue.",
}

PL = {
    "scaffold.picker.thread.reply": "Zanotowane. Nic nie zostaje zastosowane, dopóki nie przejdziesz dalej.",
}

ACCENT = str.maketrans({
    "a": "ä", "b": "ƀ", "c": "ç", "d": "ð", "e": "ë", "f": "ƒ", "g": "ğ", "h": "ĥ",
    "i": "ï", "j": "ĵ", "k": "ķ", "l": "ł", "m": "m", "n": "ñ", "o": "ö", "p": "þ",
    "q": "q", "r": "ř", "s": "š", "t": "ţ", "u": "ü", "v": "v", "w": "ŵ", "x": "x",
    "y": "ÿ", "z": "ž",
    "A": "Å", "B": "Ɓ", "C": "Ç", "D": "Ð", "E": "Ë", "F": "Ƒ", "G": "Ğ", "H": "Ĥ",
    "I": "Ï", "J": "Ĵ", "K": "Ķ", "L": "Ł", "M": "M", "N": "Ñ", "O": "Ö", "P": "Þ",
    "Q": "Q", "R": "Ř", "S": "Š", "T": "Ţ", "U": "Ü", "V": "V", "W": "Ŵ", "X": "X",
    "Y": "Ÿ", "Z": "Ž",
})

PLACEHOLDER = re.compile(r"\{[^}]*\}")


def pseudo(value: str) -> str:
    """Accent every letter outside {placeholders}, then pad ~30% and bracket."""
    out, last = [], 0
    for m in PLACEHOLDER.finditer(value):
        out.append(value[last:m.start()].translate(ACCENT))
        out.append(m.group(0))
        last = m.end()
    out.append(value[last:].translate(ACCENT))
    body = "".join(out)
    pad = "~̷~" * max(2, math.ceil(len(value) * 0.3 / 2))
    return f"[!! {body} {pad} !!]"


def merge(path: str, additions: dict) -> int:
    with open(path, encoding="utf-8") as fh:
        arb = json.load(fh, object_pairs_hook=OrderedDict)
    for key, value in additions.items():
        arb[key] = value
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(arb, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return len([k for k in arb if not k.startswith("@")])


if __name__ == "__main__":
    assert set(EN) == set(PL), f"en/pl key drift: {set(EN) ^ set(PL)}"
    ploc = {k: pseudo(v) for k, v in EN.items()}
    for path, adds in (("app_en.arb", EN), ("app_pl.arb", PL), ("app_qps-ploc.arb", ploc)):
        print(f"{path}: {merge(path, adds)} keys (+{len(adds)})")
