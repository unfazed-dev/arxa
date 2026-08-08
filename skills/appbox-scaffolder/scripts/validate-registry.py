#!/usr/bin/env python3
"""Q7 check: validate kind-resolution.registry.json against its two ground truths.

Manual for now — nothing in CI executes this yet. Run it after any registry edit.

Ground truth 1 — VOCABULARY: skills/appbox-designer/starter-partials/widgets/_<kind>.tsx.
  The partials directory IS the kind vocabulary. Registry must cover it exactly.
Ground truth 2 — TARGETS: class names declared in kit/ui_library/lib/**.dart.
  Every widget/companion/composedFrom/presentation reference must be a real class.

Exit 0 = clean, 1 = violations. Prints every violation, never just the first.

Why this exists: the registry was twice given a DUPLICATE kind key ("modal", "tabs").
json.load() silently keeps the last one, so a carefully authored entry vanished with no
error and no diff conflict. Prose review did not catch it either time. Duplicate-key
detection is the main reason this script is mechanical rather than a checklist.
"""
import json, os, re, sys, collections, glob

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
REGISTRY = os.path.join(SKILL, "kind-resolution.registry.json")
PARTIALS = os.path.normpath(os.path.join(SKILL, "..", "appbox-designer", "starter-partials", "widgets"))
KIT_LIB = os.path.normpath(os.path.join(SKILL, "..", "..", "kit", "ui_library", "lib"))

# Entry shapes that legitimately resolve with widget:null. Each MUST also be named in
# resolution.order — an unlisted shape falls through to FAIL and breaks a designed kind.
SHAPES = ("widget", "variants", "composedFrom", "presentation")

def main():
    bad = []

    dups = []
    def hook(pairs):
        c = collections.Counter(k for k, _ in pairs)
        dups.extend(k for k, n in c.items() if n > 1)
        return dict(pairs)

    with open(REGISTRY) as f:
        reg = json.loads(f.read(), object_pairs_hook=hook)
    for d in sorted(set(dups)):
        bad.append(f"DUPLICATE KEY {d!r} — JSON keeps only the last; an entry is being silently discarded")

    kinds = reg.get("kinds", {})
    order = reg.get("resolution", {}).get("order", [])

    if not os.path.isdir(PARTIALS):
        bad.append(f"vocabulary source missing: {PARTIALS}")
        vocab = set()
    else:
        vocab = {f[1:-4] for f in os.listdir(PARTIALS)
                 if f.startswith("_") and f.endswith(".tsx")}

    for k in sorted(vocab - set(kinds)):
        bad.append(f"UNCOVERED KIND {k!r} — _{k}.tsx is authored but has no registry entry")
    for k in sorted(set(kinds) - vocab):
        bad.append(f"ORPHAN ENTRY {k!r} — registry maps a kind with no authored partial")

    classes = set()
    for p in glob.glob(os.path.join(KIT_LIB, "**", "*.dart"), recursive=True):
        with open(p, errors="ignore") as f:
            classes.update(re.findall(r"^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+)*class\s+(\w+)",
                                      f.read(), re.M))
    if not classes:
        bad.append(f"no Dart classes found under {KIT_LIB} — cannot verify targets")

    for shape in SHAPES:
        if not any(shape in str(o) for o in order):
            bad.append(f"SHAPE {shape!r} NOT IN resolution.order — entries using it fall through to FAIL")

    for kind in sorted(kinds):
        v = kinds[kind]
        if not isinstance(v, dict):
            bad.append(f"{kind}: entry is not an object")
            continue
        if not any(v.get(s) for s in SHAPES):
            bad.append(f"{kind}: UNRESOLVABLE — none of {SHAPES} present")
        refs = [v["widget"]] if v.get("widget") else []
        refs += v.get("composedFrom") or []
        refs += v.get("companions") or []
        refs += [x for x in (v.get("presentation") or {}).values()
                 if isinstance(x, str) and x.startswith("AppBoxKit")]
        refs += [x for x in (v.get("variants") or {}).values() if isinstance(x, str)]
        for r in refs:
            if classes and r not in classes:
                bad.append(f"{kind}: {r!r} is not a class in kit/ui_library/lib — invented placeholder?")
        esc = v.get("escape")
        if esc and not all(esc.get(x) for x in ("reason", "owner", "expires")):
            bad.append(f"{kind}: escape entry must carry reason, owner and expires")

    if bad:
        print(f"REGISTRY INVALID — {len(bad)} violation(s):")
        for b in bad:
            print("  x " + b)
        return 1
    print(f"registry OK — v{reg.get('registryVersion')}, {len(kinds)} kinds, "
          f"vocabulary matches {len(vocab)} partials, all targets real")
    return 0

if __name__ == "__main__":
    sys.exit(main())
