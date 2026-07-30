#!/usr/bin/env python3
"""emit_structure.py — derive <design-root>/structure.json from a design producer.

The FSM intake contract (tools/freeze_design.sh) asked for tokens, docs and flat
`surfaces/*.html` and *nothing structural*, so shell membership, surface identity
and coverage were re-invented downstream — shell parsed out of a filename prefix,
widget/overlay boundaries eyeballed off rendered HTML — and then policed by
shell_structure_gate.sh and review_checklist.sh. This emitter closes the loop at
the source: the producer already knows the structure, so it writes it down, and
freeze_design.sh check 4 asserts it.

Sibling of emit_playground/ and emit_htmx/, with one deliberate difference: those
extract `window.P2.registry` through a headless browser, so they cannot run under
EMIT_RENDER=skip. structure.json is pure data and must be emittable on a machine
with no playwright, so this reads `jsx/app.jsx` as text. That also makes it usable
as the pre-flight for a producer whose surfaces have not been emitted yet.

Two producer shapes, picked automatically:

  registry  — `jsx/app.jsx` carries P2_REGISTRY (id/shell/comp/surface) and
              P2_SHELL_ROOTS. EVERY entry is emitted, including `surface: null`.
              Those nulls ARE the exclusions — there is deliberately no second
              "excluded" list, because a list you maintain by hand is a list you
              pad to make a gate green.
  surfaces  — no registry: one screen per `surfaces/*.html`, id/comp derived from
              the filename, no shell roots. (The htmx producer's shape.)

`shell` comes from the `<shell>_shell_` filename prefix — the convention the
scaffolder has been parsing implicitly all along, now written down and checked.

Usage:
  emit_structure.py [--app <app-root>] [--design-dir design/new]   emit
  emit_structure.py --check ...                                    drift guard
  emit_structure.py --self-test                                    hermetic

$KIT_APP is the default app root; $KIT_DESIGN_DIR the default design segment.
Exit discipline (freeze_design.sh precedent): 0 = emitted / in sync,
1 = missing input or drift.
"""
import glob
import json
import os
import re
import sys
import tempfile

# The playground harness page, not a product surface. Hard-coded rather than
# author-supplied: a producer must not be able to declare its way out of the
# "every surface is claimed" check by calling everything harness chrome.
HARNESS = {"index"}

BANNER = "kit/design-structure@1"


def _entries(src):
    """(list[(id, shell, comp, surface)] | None, shellRoots) from an app.jsx text."""
    reg = re.search(r"const P2_REGISTRY\s*=\s*\[(.*?)\n\];", src, re.S)
    if not reg:
        return None, {}
    out = []
    for m in re.finditer(r"\{([^{}]*)\}", reg.group(1)):
        body = m.group(1)

        def f(key):
            mm = re.search(r"\b%s:\s*(null|'([^']*)')" % key, body)
            if not mm:
                return None
            return None if mm.group(1) == "null" else mm.group(2)

        if f("id"):
            out.append((f("id"), f("shell"), f("comp"), f("surface")))
    roots = re.search(r"const P2_SHELL_ROOTS\s*=\s*\{(.*?)\};", src, re.S)
    shell_roots = dict(re.findall(r"(\w+):\s*'([^']+)'", roots.group(1))) if roots else {}
    return out, shell_roots


def _shell_dir(surface):
    """train_shell_training_library_view -> train_shell"""
    if not surface or "_shell_" not in surface:
        return None
    return surface.split("_shell_", 1)[0] + "_shell"


def build(root):
    app_jsx = os.path.join(root, "jsx", "app.jsx")
    if os.path.isfile(app_jsx):
        entries, shell_roots = _entries(open(app_jsx).read())
        if entries is None:
            print(f"FAIL: {app_jsx} has no P2_REGISTRY", file=sys.stderr)
            return None
        screens = [
            {"id": i, "shell": t, "comp": c, "shellDir": _shell_dir(s), "surface": s}
            for (i, t, c, s) in entries
        ]
        registry = "jsx/app.jsx"
    else:
        registry, shell_roots, screens = None, {}, []
        for path in sorted(glob.glob(os.path.join(root, "surfaces", "*.html"))):
            name = os.path.basename(path)[:-5]
            if name in HARNESS:
                continue
            sh = _shell_dir(name)
            rest = name[len(sh) + 1:] if sh else name
            rest = rest[:-5] if rest.endswith("_view") else rest
            screens.append({
                "id": f"{sh[:-6]}.{rest}" if sh else rest,
                "shell": sh[:-6] if sh else None,
                "comp": "".join(p.title() for p in (rest or name).split("_")),
                "shellDir": sh,
                "surface": name,
            })

    return {"$schema": BANNER, "registry": registry,
            "shellRoots": shell_roots, "screens": screens}


def emit(root, check=False):
    if not os.path.isdir(os.path.join(root, "surfaces")):
        print(f"FAIL: {root}/surfaces/ missing — not a design root", file=sys.stderr)
        return 1
    data = build(root)
    if data is None:
        return 1
    text = json.dumps(data, indent=2) + "\n"
    out = os.path.join(root, "structure.json")

    if check:
        have = open(out).read() if os.path.isfile(out) else ""
        if have != text:
            print(f"FAIL: emit_structure --check: {out} drifted from the producer "
                  "(re-run emit_structure.py)", file=sys.stderr)
            return 1
        print(f"in-sync {out}")
        return 0

    if os.path.isfile(out) and open(out).read() == text:
        print(f"unchanged {out} (write-on-diff: content identical)")
    else:
        open(out, "w").write(text)
        print(f"wrote {out}")
    n = len(data["screens"])
    c = sum(1 for s in data["screens"] if s["surface"])
    shells = sorted({s["shellDir"] for s in data["screens"] if s["shellDir"]})
    print(f"  {n} screens, {c} with a surface, {n - c} without")
    print(f"  {len(shells)} shell(s): {', '.join(shells) or '(none)'}")
    return 0


# ---- hermetic self-test: fixtures that must DISCRIMINATE, not merely pass ----
def self_test():
    P = [0]
    F = [0]

    def chk(cond, what):
        if cond:
            P[0] += 1
        else:
            F[0] += 1
            print(f"  FAIL: {what}")

    def plant(d, app_jsx=None, surfaces=()):
        os.makedirs(os.path.join(d, "surfaces"), exist_ok=True)
        if app_jsx is not None:
            os.makedirs(os.path.join(d, "jsx"), exist_ok=True)
            open(os.path.join(d, "jsx", "app.jsx"), "w").write(app_jsx)
        for s in surfaces:
            open(os.path.join(d, "surfaces", s + ".html"), "w").write("<html></html>")

    JSX = """
const P2_REGISTRY = [
  { id: 'train.home',    label: 'x', shell: 'train', comp: 'TrainHome', surface: null },
  { id: 'train.library', label: 'x', shell: 'train', comp: 'TrainLib',
    surface: 'train_shell_library_view' },
];
const P2_SHELL_ROOTS = { train: 'train.home' };
"""

    with tempfile.TemporaryDirectory() as tmp:
        # 1. registry shape: nulls survive into the output (the whole point).
        a = os.path.join(tmp, "a")
        plant(a, JSX, ["train_shell_library_view", "index"])
        chk(emit(a) == 0, "registry root emits")
        d = json.load(open(os.path.join(a, "structure.json")))
        chk(len(d["screens"]) == 2, "both screens emitted (null NOT dropped)")
        chk(d["screens"][0]["surface"] is None, "surface:null preserved verbatim")
        chk(d["screens"][1]["shellDir"] == "train_shell", "shellDir derived from prefix")
        chk(d["shellRoots"] == {"train": "train.home"}, "shellRoots carried")
        chk(d["registry"] == "jsx/app.jsx", "registry path recorded")

        # 2. write-on-diff + --check drift guard.
        chk(emit(a, check=True) == 0, "--check green when in sync")
        open(os.path.join(a, "structure.json"), "w").write('{"screens":[]}\n')
        chk(emit(a, check=True) == 1, "--check RED on planted drift")

        # 3. surfaces-only producer: no jsx/, ids derived, harness page skipped.
        b = os.path.join(tmp, "b")
        plant(b, None, ["shop_shell_cart_view", "index"])
        chk(emit(b) == 0, "surfaces-only root emits")
        d = json.load(open(os.path.join(b, "structure.json")))
        chk(len(d["screens"]) == 1, "index.html excluded as harness, not a screen")
        chk(d["screens"][0]["id"] == "shop.cart", "id derived from filename")
        chk(d["screens"][0]["comp"] == "Cart", "comp derived from filename")
        chk(d["registry"] is None, "registry null for surfaces-only producer")

        # 4. bad inputs are exit 1, never a silent empty file.
        c = os.path.join(tmp, "c")
        os.makedirs(c)
        chk(emit(c) == 1, "no surfaces/ dir -> exit 1")
        e = os.path.join(tmp, "e")
        plant(e, "const NOT_THE_REGISTRY = [];\n", ["x_shell_y_view"])
        chk(emit(e) == 1, "jsx/app.jsx without P2_REGISTRY -> exit 1")
        chk(not os.path.isfile(os.path.join(e, "structure.json")),
            "failed run writes NO structure.json")

    print(f"\nemit_structure self-test: passed={P[0]} failed={F[0]}")
    if F[0]:
        return 1
    print("ALL GREEN")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    app = os.environ.get("KIT_APP") or "."
    dd = os.environ.get("KIT_DESIGN_DIR") or "design/new"
    check = "--check" in argv
    i = 1
    while i < len(argv):
        if argv[i] == "--app":
            i += 1
            app = argv[i]
        elif argv[i] == "--design-dir":
            i += 1
            dd = argv[i]
        i += 1
    if os.path.isabs(dd):
        print("FAIL: --design-dir must stay app-root-relative", file=sys.stderr)
        return 1
    return emit(os.path.abspath(os.path.join(app, dd)), check=check)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
