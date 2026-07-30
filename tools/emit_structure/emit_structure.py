#!/usr/bin/env python3
"""emit_structure.py — derive <design-root>/structure.json from the authored layer.

The authored layer is the source of truth for structure: the producer's
``models/screens_model/registry.json`` (id/shell/comp/surface per screen) and its
``app.routes.js`` (the exported ``shellRoots`` map). This emitter joins each
declared surface to its viewmodel on the viewmodel's **exported surfaceId** —
not filename similarity — and writes the shell/surface map that the structure
gate drift-checks against.

Two facts that used to be invented downstream now move to where they are known:

* ``surface: null`` in the registry **IS** the exclusion. There is deliberately
  no second "excluded" list — two ways to express one fact is the drift this
  architecture exists to prevent.
* every shell group (the registry's ``shell`` field) lands in exactly one shell
  dir, so the shell dir is *derived* from the surface prefix, never
  hand-maintained.

Pure data: no browser, no render. Emittable on a machine with only python3.

Exit discipline: 0 = emitted / in sync, 1 = missing input or drift.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

BANNER = "app-box/structure@1"

# A viewmodel declares which screen it renders via `export const surfaceId = ...`.
# The join to the registry is on that token (== the registry entry's `id`), never
# on filename similarity — `giftcards` vs `gift_cards` is a lexical trap.
_SURFACEID = re.compile(r"export\s+const\s+surfaceId\s*=\s*['\"]([^'\"]+)['\"]")

# shellRoots is an ES module export: `export const shellRoots = { shell: '/path', ... };`.
# app.routes.js is JavaScript, not JSON, so the export is lifted out by matching
# the object body — the registry itself is read as JSON (no regex on data).
_SHELLROOTS = re.compile(r"export\s+const\s+shellRoots\s*=\s*\{([^}]*)\}", re.S)
_PAIR = re.compile(r"([A-Za-z_][\w-]*)\s*:\s*['\"]([^'\"]+)['\"]")

# Declared dependencies: facades and repositories the viewmodel imports. Anything
# else (the htmx helper, other viewmodels) is not a data dependency.
_DEP = re.compile(r"from\s+['\"]([^'\"]*(?:services/facades|services/repositories)/[^'\"]+)['\"]")


def _fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    return None


def _load_registry(root):
    """list of registry entries from models/screens_model/registry.json (JSON)."""
    path = os.path.join(root, "models", "screens_model", "registry.json")
    if not os.path.isfile(path):
        return _fail(f"no registry at models/screens_model/registry.json "
                     f"— not a design root, or the producer has no authored layer")
    try:
        data = json.load(open(path))
    except ValueError as e:
        return _fail(f"registry.json does not parse as JSON — {e}")
    if not isinstance(data, list) or not data:
        return _fail("registry.json must be a non-empty list of screen entries")
    return data


def _shell_roots(root):
    """{shell: '/route'} from app.routes.js's exported shellRoots map.

    Empty/absent is a hard failure: a producer with no shellRoots has no idea
    where its shells land, and an empty object must no longer pass vacuously.
    """
    path = os.path.join(root, "app.routes.js")
    if not os.path.isfile(path):
        return _fail("no app.routes.js — cannot read the shellRoots map")
    src = open(path).read()
    m = _SHELLROOTS.search(src)
    if not m:
        return _fail("app.routes.js exports no `shellRoots` map")
    roots = dict(_PAIR.findall(m.group(1)))
    if not roots:
        return _fail("shellRoots is empty — every shell needs a landing route")
    return roots


def _shell_dir(surface):
    """stage_shell_projects_home_view -> stage_shell (the <shell>_shell prefix)."""
    if not surface or "_shell_" not in surface:
        return None
    return surface.split("_shell_", 1)[0] + "_shell"


def _viewmodels(root):
    """{surfaceId: {'path', 'deps'}} for every ui/views/**/*_viewmodel.js.

    A viewmodel with no surfaceId is a HARD failure naming the file — the join
    has nothing to bind to, and guessing would be the normalizer this plan
    refuses to write.
    """
    out = {}
    for path in sorted(glob.glob(os.path.join(root, "ui", "views", "**", "*_viewmodel.js"),
                                 recursive=True)):
        rel = os.path.relpath(path, root)
        src = open(path).read()
        m = _SURFACEID.search(src)
        if not m:
            return _fail(f"{rel} exports no surfaceId — the registry join needs one")
        sid = m.group(1)
        if sid in out:
            return _fail(f"surfaceId '{sid}' declared twice "
                         f"({out[sid]['path']} and {rel})")
        deps = set()
        for dm in _DEP.finditer(src):
            deps.add(os.path.relpath(os.path.normpath(
                os.path.join(os.path.dirname(path), dm.group(1))), root))
        out[sid] = {"path": rel, "deps": sorted(deps)}
    return out


def build(root):
    """Assemble the structure dict, or return None on a hard failure."""
    registry_entries = _load_registry(root)
    if registry_entries is None:
        return None
    shell_roots = _shell_roots(root)
    if shell_roots is None:
        return None
    vms = _viewmodels(root)
    if vms is None:
        return None

    # First pass: derive the shell dir from every entry that carries a surface,
    # and learn the shell-group -> shell-dir table from those (the mapping is
    # pure: one shell dir per shell group).
    group_to_dir = {}
    for e in registry_entries:
        if e.get("surface"):
            sd = _shell_dir(e["surface"])
            if sd is None:
                return _fail(f"screen '{e.get('id')}' has surface '{e['surface']}' "
                             f"with no <shell>_shell_ prefix")
            group = e.get("shell")
            if group in group_to_dir and group_to_dir[group] != sd:
                return _fail(f"shell group '{group}' maps to two shell dirs "
                             f"({group_to_dir[group]} and {sd}) — group->dir must be pure")
            group_to_dir.setdefault(group, sd)

    screens = []
    for e in registry_entries:
        sid = e.get("id")
        surface = e.get("surface")
        if surface:
            vm = vms.get(sid)
            if vm is None:
                # The join failed on the DECLARED surfaceId, not filename gist.
                return _fail(f"screen '{sid}' declares a surface but no viewmodel "
                             f"exports surfaceId '{sid}'")
            shell_dir = _shell_dir(surface)
            screens.append({
                "id": sid,
                "shell": e.get("shell"),
                "comp": e.get("comp"),
                "shellDir": shell_dir,
                "surface": surface,
                "viewmodel": vm["path"],
                "deps": vm["deps"],
            })
        else:
            # surface:null IS the exclusion — preserved verbatim, never dropped.
            group = e.get("shell")
            shell_dir = group_to_dir.get(group)
            screens.append({
                "id": sid,
                "shell": group,
                "comp": e.get("comp"),
                "shellDir": shell_dir,
                "surface": None,
                "viewmodel": None,
                "deps": [],
            })

    # Orphan viewmodels: a file on disk whose surfaceId the registry never claims.
    claimed = {s["id"] for s in screens if s["surface"]}
    orphans = sorted(s for s in vms if s not in claimed)
    if orphans:
        one = orphans[0]
        return _fail(f"viewmodel {vms[one]['path']} exports surfaceId '{one}' "
                     f"but the registry declares no such screen")

    return {
        "$schema": BANNER,
        "registry": "models/screens_model/registry.json",
        "shellRoots": shell_roots,
        "screens": screens,
    }


def _serialize(data):
    return json.dumps(data, indent=2) + "\n"


def emit(root, check=False):
    data = build(root)
    if data is None:
        return 1
    text = _serialize(data)
    out = os.path.join(root, "structure.json")

    if check:
        # In-memory compare: regenerate without writing, then diff against the
        # on-disk file. Catches a hand-edit or a stale registry. The tracking
        # dimension (untracked / uncommitted) is the gate's porcelain concern —
        # `git diff` cannot see a new file, but an in-memory compare can.
        have = open(out).read() if os.path.isfile(out) else ""
        if have != text:
            print(f"FAIL: emit_structure --check: {out} drifted from the authored "
                  f"layer (re-run emit_structure.py)", file=sys.stderr)
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
    excl = [s["id"] for s in data["screens"] if not s["surface"]]
    print(f"  {n} screens, {c} with a surface, {n - c} excluded (surface:null)")
    if excl:
        print(f"  exclusions: {', '.join(excl)}")
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

    def plant(d, registry, routes, viewmodels):
        os.makedirs(os.path.join(d, "models", "screens_model"), exist_ok=True)
        open(os.path.join(d, "models", "screens_model", "registry.json"), "w").write(registry)
        open(os.path.join(d, "app.routes.js"), "w").write(routes)
        for rel, body in viewmodels.items():
            p = os.path.join(d, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").write(body)

    REG = json.dumps([
        {"id": "stage.shell", "shell": "stage", "comp": "StageShell",
         "surface": "stage_shell_view"},
        {"id": "proj.home", "shell": "proj", "comp": "ProjHome",
         "surface": "stage_shell_proj_home_view"},
        {"id": "proj.splash", "shell": "proj", "comp": "ProjSplash",
         "surface": None},
    ])
    ROUTES = (
        "export default [['GET','/',home.page]];\n"
        "export const shellRoots = { proj: '/', stage: '/' };\n"
    )
    # viewmodels live 3 and 5 dirs deep; imports resolve back to the design root.
    SHELL_VM = "export const surfaceId = 'stage.shell';\nimport {chrome} from '../../../services/facades/shell_facade.js';\n"
    HOME_VM = "export const surfaceId = 'proj.home';\nimport {list} from '../../../../../services/facades/project_facade.js';\n"

    with tempfile.TemporaryDirectory() as tmp:
        # 1. happy path: join on surfaceId, exclusions preserved, deps captured.
        a = os.path.join(tmp, "a")
        plant(a, REG, ROUTES, {
            "ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM,
            "ui/views/stage_shell/proj/home/home_viewmodel.js": HOME_VM,
        })
        chk(emit(a) == 0, "registry root emits")
        d = json.load(open(os.path.join(a, "structure.json")))
        chk(len(d["screens"]) == 3, "all three screens emitted (null NOT dropped)")
        splash = [s for s in d["screens"] if s["id"] == "proj.splash"][0]
        chk(splash["surface"] is None, "surface:null preserved as the exclusion")
        chk(splash["viewmodel"] is None, "excluded screen has no viewmodel")
        chk(splash["shellDir"] == "stage_shell", "excluded screen derives shellDir from group->dir")
        home = [s for s in d["screens"] if s["id"] == "proj.home"][0]
        chk(home["viewmodel"].endswith("home_viewmodel.js"), "viewmodel path resolved via surfaceId")
        chk("services/facades/project_facade.js" in home["deps"], "facade dep captured, design-root-relative")
        chk(d["shellRoots"] == {"proj": "/", "stage": "/"}, "shellRoots lifted from app.routes.js")
        chk(d["registry"] == "models/screens_model/registry.json", "registry source recorded")

        # 2. --check green in sync, RED on a one-char hand-edit.
        chk(emit(a, check=True) == 0, "--check green when in sync")
        body = open(os.path.join(a, "structure.json")).read()
        open(os.path.join(a, "structure.json"), "w").write(body.replace("StageShell", "StageShellX"))
        chk(emit(a, check=True) == 1, "--check RED on a one-char hand-edit")

        # 3. missing surfaceId: a declared surface with no viewmodel -> HARD fail.
        b = os.path.join(tmp, "b")
        plant(b, REG, ROUTES, {"ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM})
        rc = emit(b)
        chk(rc == 1, "missing surfaceId fails")
        # restore the home viewmodel so the only failure is the dangling join
        plant(b, REG, ROUTES, {
            "ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM,
            "ui/views/stage_shell/proj/home/home_viewmodel.js": HOME_VM,
        })

        # 4. orphan viewmodel: a surfaceId the registry never claims -> HARD fail.
        c = os.path.join(tmp, "c")
        plant(c, REG, ROUTES, {
            "ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM,
            "ui/views/stage_shell/proj/home/home_viewmodel.js": HOME_VM,
            "ui/views/stage_shell/ghost/ghost_viewmodel.js":
                "export const surfaceId = 'proj.ghost';\n",
        })
        chk(emit(c) == 1, "orphan viewmodel (unclaimed surfaceId) fails")

        # 5. empty shellRoots -> HARD fail (no longer passes vacuously).
        e = os.path.join(tmp, "e")
        plant(e, REG, "export const shellRoots = {};\nexport default [];", {
            "ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM,
            "ui/views/stage_shell/proj/home/home_viewmodel.js": HOME_VM,
        })
        chk(emit(e) == 1, "empty shellRoots fails")

        # 6. a viewmodel with no surfaceId export -> HARD fail naming the file.
        g = os.path.join(tmp, "g")
        plant(g, REG, ROUTES, {
            "ui/views/stage_shell/stage_shell_viewmodel.js": SHELL_VM,
            "ui/views/stage_shell/proj/home/home_viewmodel.js":
                "export const page = () => {};\n",
        })
        chk(emit(g) == 1, "viewmodel with no surfaceId fails")

        # 7. a failed run writes NO structure.json.
        chk(not os.path.isfile(os.path.join(c, "structure.json")),
            "failed run leaves no structure.json behind")

    print(f"\nemit_structure self-test: passed={P[0]} failed={F[0]}")
    if F[0]:
        return 1
    print("ALL GREEN")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    app = os.environ.get("KIT_APP") or "."
    dd = os.environ.get("KIT_DESIGN_DIR") or "design"
    check = "--check" in argv
    i = 1
    while i < len(argv):
        if argv[i] == "--app" and i + 1 < len(argv):
            i += 1
            app = argv[i]
        elif argv[i] == "--design-dir" and i + 1 < len(argv):
            i += 1
            dd = argv[i]
        i += 1
    if os.path.isabs(dd):
        print("FAIL: --design-dir must stay app-root-relative", file=sys.stderr)
        return 1
    root = os.path.abspath(os.path.join(app, dd))
    rc = emit(root, check=check)
    # Post-emit hook (P1 provenance/watermark). ON by default — the free tier
    # ships watermarked provenance; set APPBOX_WATERMARK=0 to opt out (paid
    # builds get clean provenance via the licence status the hook reads).
    # Never blocks the emit: hook failure is reported, rc is unchanged.
    if rc == 0 and not check and os.environ.get("APPBOX_WATERMARK", "1") != "0":
        hook = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            "watermark", "watermark.mjs")
        r = subprocess.run(["node", hook, root], check=False)
        if r.returncode != 0:
            print(f"WARN: watermark hook exited {r.returncode}", file=sys.stderr)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
