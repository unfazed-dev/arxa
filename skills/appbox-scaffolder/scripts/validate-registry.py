#!/usr/bin/env python3
"""Q7 check: validate kind-resolution.registry.json against its two ground truths.

SUPERSEDED 2026-08: promoted to a real gate — run `appbox gate kind_registry`
(appboxd/lib/gate_kind_registry.dart), which rides `gate --all` and CI. This
script stays as the port's reference implementation; behavior is parity-locked
by appboxd/test/gate_kind_registry_test.dart.

Manual for now — nothing in CI executes this yet. Run it after any registry edit.

Ground truth 1 — VOCABULARY: skills/appbox-designer/starter-partials/widgets/_<kind>.tsx.
  The partials directory IS the kind vocabulary. Registry must cover it exactly.
Ground truth 2 — TARGETS: class names declared in kit/ui_library/lib/**.dart.
  Every widget/companion/composedFrom/presentation reference must be a real class.
Ground truth 3 (Q12, registry v1.2.0) — INSPECT IDENTITY: the Dart shape named by
  designVocabulary.inspectAttrs must exist, declare the triple, and be exported from the
  kit-core barrel; and no anatomy-node id stamped anywhere in kit/ may sit outside the
  closed anatomyNodes vocabulary. The second half is the one that matters: a closed set
  nothing checks is prose. Note it deliberately does NOT require every declared id to be
  used — an unused id is harmless, an unregistered one is drift.

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
KIT_ROOT = os.path.normpath(os.path.join(SKILL, "..", "..", "kit"))

ANATOMY_ID_RE = re.compile(r"^anatomy:[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9]*)*$")
# Any 'anatomy:...' string literal stamped in Dart under kit/. Deliberately broad: it
# catches ids invented at the call site, which is exactly how a closed set rots.
ANATOMY_USE_RE = re.compile(r"['\"](anatomy:[^'\"]*)['\"]")

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

    # ---- Ground truth 3 (Q12): inspect identity ----------------------------------
    anat = reg.get("anatomyNodes") or {}
    declared = anat.get("vocabulary") or {}
    shape_pkg = (reg.get("designVocabulary") or {}).get("inspectAttrs")

    if not declared:
        bad.append("anatomyNodes.vocabulary is empty — the inspect triple's third slot has no closed set")
    for nid, desc in sorted(declared.items()):
        if not ANATOMY_ID_RE.match(nid):
            bad.append(f"MALFORMED anatomy id {nid!r} — expected anatomy:<dotted.lowerCamel> segments")
        if not (isinstance(desc, str) and desc.strip()):
            bad.append(f"anatomy id {nid!r} has no description — an id nobody can place is an id nobody can check")

    if not shape_pkg:
        bad.append("designVocabulary.inspectAttrs missing — the inspect shape has no declared single home")
    else:
        # package:appbox_kit_core/common/x.dart -> kit/core/lib/common/x.dart
        rel = shape_pkg.split("/", 1)[1] if "/" in shape_pkg else ""
        shape_path = os.path.join(KIT_ROOT, "core", "lib", rel)
        if not os.path.isfile(shape_path):
            bad.append(f"inspectAttrs shape {shape_pkg} does not exist on disk ({shape_path})")
        else:
            src = open(shape_path, errors="ignore").read()
            if "class AppBoxKitInspectAttrs" not in src:
                bad.append(f"{shape_pkg} does not declare class AppBoxKitInspectAttrs")
            for slot in ("screenId", "surfaceId", "anatomyNodeId"):
                if not re.search(rf"\b{slot}\b", src):
                    bad.append(f"{shape_pkg} does not carry triple slot {slot!r}")
            barrel = os.path.join(KIT_ROOT, "core", "lib", "appbox_kit_core.dart")
            if os.path.isfile(barrel) and os.path.basename(rel) not in open(barrel, errors="ignore").read():
                bad.append("inspectAttrs shape is not exported from appbox_kit_core.dart — importers cannot reach the single home")

    # The anti-drift half: every anatomy id stamped under kit/ must be registered.
    if declared:
        seen = collections.defaultdict(list)
        for p in glob.glob(os.path.join(KIT_ROOT, "**", "*.dart"), recursive=True):
            if f"{os.sep}.dart_tool{os.sep}" in p or f"{os.sep}build{os.sep}" in p:
                continue
            for m in ANATOMY_USE_RE.findall(open(p, errors="ignore").read()):
                if m not in declared:
                    seen[m].append(os.path.relpath(p, KIT_ROOT))
        for nid in sorted(seen):
            where = ", ".join(sorted(set(seen[nid]))[:3])
            bad.append(f"UNREGISTERED anatomy id {nid!r} stamped at {where} — not in anatomyNodes.vocabulary")

    if bad:
        print(f"REGISTRY INVALID — {len(bad)} violation(s):")
        for b in bad:
            print("  x " + b)
        return 1
    print(f"registry OK — v{reg.get('registryVersion')}, {len(kinds)} kinds, "
          f"vocabulary matches {len(vocab)} partials, all targets real, "
          f"{len(declared)} anatomy node id(s) closed and unviolated")
    return 0

if __name__ == "__main__":
    sys.exit(main())
