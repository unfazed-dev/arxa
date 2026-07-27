#!/usr/bin/env python3
"""kit_registry — SSOT tooling for the stacked_kit capability registry.

kit-registry.json (validated by kit-registry.schema.json) is the single source
of truth for capability->kit routing and each kit's typed export vocabularies.
The two markdown routing tables (skills/_kit-system.md §4, kit_matrix.md §2/§3)
are GENERATED views of it (splice increment); this tool guards the seam:

  check-map <translation-map.json>   grammar-aware validation that every
                                      translation-map ".kit" token resolves to a
                                      real, registered kit export:
                                        widget            -> some kit.provides.widgets
                                        Service.method    -> some kit.provides.services[].methods
                                        motion:<preset>   -> some kit.provides.motion_presets
                                          [+ KitMotionSpec.<v> -> motion_specs]
  check-vocab                         GATE: every authored provides.* symbol must
                                      actually exist in that kit's source, so
                                      provides[] can never drift into fiction
                                      (the barrel/source is the truth).
  gen-vocab <kit-dir>                 best-effort: enumerate a kit's exported Kit*
                                      widget/service classes (authoring aid).
  check                              check-map (default translation-map) + check-vocab.

Stdlib only (mirrors translate_design.py). Non-zero exit on any failure.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))            # .../stacked_kit/tools/kit_registry
KIT_ROOT = os.path.abspath(os.path.join(ROOT, "..", ".."))   # .../stacked_kit
REGISTRY = os.path.join(ROOT, "kit-registry.json")
DEFAULT_TMAP = os.path.join(KIT_ROOT, "tools", "translate_design", "translation-map.json")
TRANSLATE_DESIGN = os.path.join(KIT_ROOT, "tools", "translate_design", "translate_design.py")
KIT_SYSTEM_MD = os.path.join(KIT_ROOT, "skills", "_kit-system.md")
KIT_MATRIX_MD = os.path.join(KIT_ROOT, "kit_matrix.md")

# Generated-region markers (HTML comments — invisible in rendered markdown).
GEN_BEGIN = "<!-- BEGIN GENERATED: {name} — SSOT tools/kit_registry/kit-registry.json; do not hand-edit, run kit_registry.py gen-md -->"
GEN_END = "<!-- END GENERATED: {name} -->"

# ---- token grammar (matches the 3 real translation-map forms) ---------------
WIDGET_RE = re.compile(r"^Kit[A-Za-z0-9]+$")
SERVICE_RE = re.compile(r"^(Kit[A-Za-z0-9]+)\.([A-Za-z][A-Za-z0-9]*)$")
MOTION_RE = re.compile(
    r"^motion:([a-z][a-z0-9-]*)(?:\s*\+\s*KitMotionSpec\.([a-zA-Z][a-zA-Z0-9]*))?$"
)


def load_registry(path=REGISTRY):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_index(reg):
    """Typed vocabularies unioned across kits: {widget->dir}, {service->(dir,methods)},
    {preset->dir}, {spec->dir}."""
    widgets, services, presets, specs = {}, {}, {}, {}
    for k in reg["kits"]:
        p = k.get("provides", {})
        for w in p.get("widgets", []):
            widgets[w] = k["dir"]
        for s in p.get("services", []):
            services[s["name"]] = (k["dir"], set(s["methods"]))
        for m in p.get("motion_presets", []):
            presets[m] = k["dir"]
        for v in p.get("motion_specs", []):
            specs[v] = k["dir"]
    return widgets, services, presets, specs


def check_map(reg, tmap_path):
    with open(tmap_path, encoding="utf-8") as f:
        tmap = json.load(f)
    widgets, services, presets, specs = build_index(reg)
    errors = []
    for idiom in tmap.get("idioms", []):
        tok = (idiom.get("kit") or "").strip()
        sel = idiom.get("selector", "?")
        mm = MOTION_RE.match(tok)
        if mm:
            preset, variant = mm.group(1), mm.group(2)
            if preset not in presets:
                errors.append(f"{sel}: motion preset '{preset}' not in any kit.provides.motion_presets")
            if variant and variant not in specs:
                errors.append(f"{sel}: KitMotionSpec.{variant} not in any kit.provides.motion_specs")
            continue
        sm = SERVICE_RE.match(tok)
        if sm:
            cls, meth = sm.group(1), sm.group(2)
            if cls not in services:
                errors.append(f"{sel}: service '{cls}' not in any kit.provides.services")
            elif meth not in services[cls][1]:
                have = sorted(services[cls][1])
                errors.append(f"{sel}: method '{cls}.{meth}' not declared (has: {have})")
            continue
        if WIDGET_RE.match(tok):
            if tok not in widgets:
                errors.append(f"{sel}: widget '{tok}' not in any kit.provides.widgets")
            continue
        errors.append(f"{sel}: unrecognized kit-token grammar: '{tok}'")
    return errors


# ---- vocab gate: authored provides must exist in source ---------------------
def _kit_lib(dirname):
    return os.path.join(KIT_ROOT, dirname, "lib")


def _grep_dir(root, pattern):
    rx = re.compile(pattern)
    for dp, _dirs, files in os.walk(root):
        for fn in files:
            if fn.endswith(".dart"):
                try:
                    with open(os.path.join(dp, fn), encoding="utf-8", errors="ignore") as f:
                        if rx.search(f.read()):
                            return True
                except OSError:
                    pass
    return False


def check_vocab(reg):
    errors = []
    td_src = ""
    if os.path.exists(TRANSLATE_DESIGN):
        with open(TRANSLATE_DESIGN, encoding="utf-8", errors="ignore") as f:
            td_src = f.read()
    for k in reg["kits"]:
        p = k.get("provides", {})
        if not (p.get("widgets") or p.get("services") or p.get("motion_presets") or p.get("motion_specs")):
            continue  # no seam-referenceable surface (service/controller/state kit) —
            #          terminal & correct, not "pending": a CSS idiom maps only to a
            #          widget | Service.method | motion token, so a kit exposing no
            #          UI native contributes nothing to the seam. Nothing to gate.
        lib = _kit_lib(k["dir"])
        if not os.path.isdir(lib):
            errors.append(f"{k['dir']}: declares provides but has no lib/ at {lib}")
            continue
        for w in p.get("widgets", []):
            if not _grep_dir(lib, r"\bclass\s+" + re.escape(w) + r"\b"):
                errors.append(f"{k['dir']}: provides.widget '{w}' — no `class {w}` in {k['dir']}/lib")
        for s in p.get("services", []):
            if not _grep_dir(lib, r"\bclass\s+" + re.escape(s["name"]) + r"\b"):
                errors.append(f"{k['dir']}: provides.service '{s['name']}' — no `class {s['name']}` in {k['dir']}/lib")
            else:
                for meth in s["methods"]:
                    if not _grep_dir(lib, r"\b" + re.escape(meth) + r"\s*\("):
                        errors.append(f"{k['dir']}: service '{s['name']}.{meth}' — no `{meth}(` in {k['dir']}/lib")
        for m in p.get("motion_presets", []):
            if ("'" + m + "'") not in td_src and ('"' + m + '"') not in td_src:
                errors.append(f"{k['dir']}: motion_preset '{m}' — not a sealed flag in translate_design.py")
        for v in p.get("motion_specs", []):
            if not _grep_dir(lib, r"KitMotionSpec\s+" + re.escape(v) + r"\b"):
                errors.append(f"{k['dir']}: motion_spec 'KitMotionSpec.{v}' — no `KitMotionSpec {v}` in {k['dir']}/lib")
    return errors


def gen_vocab(dirname):
    lib = _kit_lib(dirname)
    widgets, services = set(), set()
    if not os.path.isdir(lib):
        return [], []
    for dp, _dirs, files in os.walk(lib):
        for fn in files:
            if not fn.endswith(".dart"):
                continue
            with open(os.path.join(dp, fn), encoding="utf-8", errors="ignore") as f:
                src = f.read()
            for mo in re.finditer(r"\bclass\s+(Kit[A-Za-z0-9]+)\b([^\n{]*)", src):
                name, tail = mo.group(1), mo.group(2)
                if name.endswith("Service"):
                    services.add(name)
                elif "Widget" in tail:
                    widgets.add(name)
    return sorted(widgets), sorted(services)


def write_widgets(dirname, widgets):
    """Merge generated widgets into the kit's provides (write-on-diff).
    Regenerates ONLY provides.widgets from source; services (their methods) and
    motion_presets/motion_specs are hand-authored and preserved — gen-vocab
    cannot enumerate a service's methods or a motion preset. Never wipes on
    empty widgets, so a service/controller kit (real lib/, but no `*Widget`
    classes — e.g. security, analytics, wifi) keeps its {} untouched: a kit with
    no UI native is correctly absent from the CSS-idiom seam. Detected-but-
    unwritten services are surfaced by the caller, never silently dropped.
    Returns True iff the registry file changed; exits nonzero if dir unknown."""
    with open(REGISTRY, encoding="utf-8") as f:
        reg = json.load(f)
    entry = next((k for k in reg["kits"] if k["dir"] == dirname), None)
    if entry is None:
        print(f"gen-vocab --write: no kit with dir '{dirname}' in registry",
              file=sys.stderr)
        sys.exit(1)
    if not widgets:
        return False  # ponytail: no `*Widget` classes in source (service/controller
        #               kit) — never wipe hand-authored provides
    prov = entry.setdefault("provides", {})
    if prov.get("widgets") == widgets:
        return False
    prov["widgets"] = widgets
    with open(REGISTRY, "w", encoding="utf-8") as f:
        f.write(json.dumps(reg, indent=2, ensure_ascii=False) + "\n")
    return True


# ---- generated markdown view (the routing skeleton) -------------------------
def routing_table_md(reg):
    """The _kit-system.md §4 routing table, rendered from the registry. Excludes
    the app-integration surface (showcase_app is not a routing target)."""
    rows = ["| You need | Kit (dir → package) | Backing |", "|---|---|---|"]
    for k in reg["kits"]:
        if k.get("topology") == "app-integration":
            continue
        need = ", ".join(k.get("capabilities", []))
        rows.append(f"| {need} | `{k['dir']}` → `{k['package']}` | {k.get('backing', '')} |")
    return "\n".join(rows)


def splice_region(path, name, body):
    """Replace text between the BEGIN/END markers for `name` in `path`. Returns
    (changed, new_text); exits 2 if the markers are absent or malformed (so a
    missing region is a loud failure, never a silent no-op)."""
    begin, end = GEN_BEGIN.format(name=name), GEN_END.format(name=name)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    bi, ei = text.find(begin), text.find(end)
    if bi == -1 or ei == -1 or ei < bi:
        print(f"gen-md: markers for '{name}' not found (or malformed) in {path}",
              file=sys.stderr)
        sys.exit(2)
    new = text[:bi] + begin + "\n\n" + body + "\n\n" + end + text[ei + len(end):]
    return new != text, new


def gen_md(reg, check_mode):
    """Write (or --check) the generated §4 routing region in _kit-system.md."""
    changed, new = splice_region(KIT_SYSTEM_MD, "kit-routing", routing_table_md(reg))
    rel = os.path.relpath(KIT_SYSTEM_MD, KIT_ROOT)
    if check_mode:
        if changed:
            print(f"gen-md --check: DRIFT — {rel} §4 differs from registry; run `gen-md`",
                  file=sys.stderr)
            return 1
        print(f"gen-md --check: PASS ({rel} §4 matches registry)")
        return 0
    if changed:
        with open(KIT_SYSTEM_MD, "w", encoding="utf-8") as f:
            f.write(new)
        print(f"gen-md: wrote {rel} §4 routing table")
    else:
        print("gen-md: no change")
    return 0


def check_sync(reg):
    """Drift detector across registry <-> kit_matrix.md that PRESERVES its hand
    prose: every registry package must be named somewhere in kit_matrix.md
    (catches 'added a kit to the registry but not the matrix narrative').
    ponytail: presence check (substring), not membership — a removed kit whose
    name lingers in prose passes falsely; upgrade to a table-row parse if needed."""
    with open(KIT_MATRIX_MD, encoding="utf-8") as f:
        matrix = f.read()
    return [f"kit_matrix.md missing package '{k['package']}' (dir {k['dir']}) — "
            f"in registry, absent from the matrix narrative"
            for k in reg["kits"] if k["package"] not in matrix]


# ---- capability routing query (the conductor's kit-selection tool) ----------
def route(reg, query):
    """Return kits whose dir/package/capabilities contain `query` (case-insensitive),
    each with a one-line provides summary. This is the 'I need X -> kit Y'
    resolution, backed by the SSOT (so 'toast' resolves to ui_library, not the
    plural notifications kit)."""
    q = query.lower()
    hits = []
    for k in reg["kits"]:
        hay = " ".join([k["dir"], k["package"], " ".join(k.get("capabilities", []))]).lower()
        if q not in hay:
            continue
        p = k.get("provides", {})
        bits = []
        if p.get("widgets"):
            bits.append(f"{len(p['widgets'])} widget(s)")
        if p.get("services"):
            bits.append("services=" + ",".join(s["name"] for s in p["services"]))
        if p.get("motion_presets"):
            bits.append("motion=" + ",".join(p["motion_presets"]))
        hits.append((k, ", ".join(bits) or "(no provides declared yet)"))
    return hits


def main():
    ap = argparse.ArgumentParser(description="stacked_kit capability registry SSOT guard")
    sub = ap.add_subparsers(dest="cmd", required=True)
    cm = sub.add_parser("check-map", help="validate a translation-map.json against the registry")
    cm.add_argument("tmap")
    sub.add_parser("check-vocab", help="gate authored provides.* against kit source")
    gv = sub.add_parser("gen-vocab", help="enumerate a kit's exported Kit* classes")
    gv.add_argument("kit_dir")
    gv.add_argument("--write", action="store_true",
                    help="merge generated widgets into that kit's provides "
                         "(write-on-diff; preserves hand-authored services + motion vocab)")
    gm = sub.add_parser("gen-md", help="regenerate the _kit-system.md §4 routing table from the registry")
    gm.add_argument("--check", action="store_true",
                    help="fixity: fail if the §4 table drifts from the registry (never writes)")
    sub.add_parser("check-sync", help="assert kit_matrix.md names every registry kit (prose-preserving drift check)")
    rt = sub.add_parser("route", help="capability keyword → matching kit(s) + package + provides")
    rt.add_argument("query")
    sub.add_parser("check", help="check-map + check-vocab + check-sync + §4 fixity (the full seam gate)")
    args = ap.parse_args()

    reg = load_registry()

    if args.cmd == "gen-vocab":
        w, s = gen_vocab(args.kit_dir)
        if args.write:
            changed = write_widgets(args.kit_dir, w)
            print(f"gen-vocab --write {args.kit_dir}: "
                  + (f"provides.widgets = {len(w)} widget(s)" if changed
                     else "no change"))
            if s:
                # Surfaced, not silently dropped: gen-vocab finds service CLASSES
                # but can't enumerate their methods, so services are never
                # auto-written (a methods:[] entry would make check_map reject
                # every Service.method token). Hand-author these in the registry
                # with real method lists iff a CSS idiom actually maps to one.
                print(f"  note: {len(s)} service class(es) detected, NOT written "
                      f"(hand-author methods if seam-referenced): {', '.join(s)}",
                      file=sys.stderr)
            return 0
        print(json.dumps({"widgets": w, "services": s}, indent=2))
        return 0

    if args.cmd == "gen-md":
        return gen_md(reg, args.check)

    if args.cmd == "route":
        hits = route(reg, args.query)
        if not hits:
            print(f"route: no kit matches '{args.query}'", file=sys.stderr)
            return 1
        for k, summ in hits:
            print(f"{k['dir']} → {k['package']}  [{k.get('topology')}, {k.get('phase')}]")
            print(f"    caps:     {', '.join(k.get('capabilities', []))}")
            print(f"    provides: {summ}")
            print(f"    playbook: {k.get('playbook', '—')}")
        return 0

    errors = []
    if args.cmd in ("check-map", "check"):
        tmap = args.tmap if args.cmd == "check-map" else DEFAULT_TMAP
        errors += [f"[map] {e}" for e in check_map(reg, tmap)]
    if args.cmd in ("check-vocab", "check"):
        errors += [f"[vocab] {e}" for e in check_vocab(reg)]
    if args.cmd in ("check-sync", "check"):
        errors += [f"[sync] {e}" for e in check_sync(reg)]
    if args.cmd == "check" and gen_md(reg, check_mode=True) != 0:
        errors.append("[md] _kit-system.md §4 drifted from registry (run `gen-md`)")

    if errors:
        print("kit-registry check FAILED:", file=sys.stderr)
        for e in errors:
            print("  ✗ " + e, file=sys.stderr)
        return 1
    print("kit-registry check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
