#!/usr/bin/env python3
"""app-box-scaffolder — the scaffold engine.

THE CONTRACT
  The structure gate (gates/structure) asserts the authored layer
  (registry.json + ui/views/**) matches structure.json. This engine is the
  INVERSE: it reads a FROZEN structure.json + the target set and PRODUCES the
  per-surface Dart tree the coverage gate (gates/coverage) then asserts. It is
  the missing producer the P14 dogfood named (dogfood-report 14.8 / honest-bar
  #2): no tool turned D1 into the Flutter file set, so "scaffold D1" and
  "coverage of D1" had no target.

  Form factors FOLLOW TARGETS (architecture §16). --targets macos derives
  [desktop] -> three files/surface (_view.dart + _view.desktop.dart +
  _viewmodel.dart). --targets ios,android derives [mobile, tablet] -> four
  files/surface. The set is read from the derivation table + config viewports
  (P06), NEVER a per-surface literal. An empty .mobile/.tablet is never emitted
  to satisfy a counter — a file that exists, passes the check, and is never
  rendered is the stale-green pattern §16 exists to kill.

  The engine emits STRUCTURE. The widget bodies are the builder's job (plan 08):
  every file is a minimal valid Dart skeleton carrying the class name the
  builder implements, marked as a stub. It does not compile Dart; it produces
  the file set + the .shell-structure.json manifest the coverage gate reads.

  Directory naming is a scaffolder DECISION, recorded in the manifest (the
  coverage gate refuses to guess it). The decision here: dir = <tab>_<short>
  from the registry id — the stable key §18 says must never be reused — which is
  single-segment by construction and matches the existing app convention
  (projects_home/, settings_kits/) and the coverage gate's dir==file-prefix rule.

  Pure stdlib. Exit: 0 emitted / in-sync · 1 missing input, drift, wrong count.

Usage:
  scaffold.py --design-dir <d> --app-root <a> --targets macos [--check]
  scaffold.py --self-test
Env: KIT_DESIGN_DIR (default 'design'), KIT_APP (default '.'), APPBOX_TARGETS.
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # skills/app-box-scaffolder/ -> repo root
CONFIG = ROOT / "config" / "app-box.config.json"
DERIVATION = ROOT / "pipeline" / "state" / "targets.derivation.json"


# ----------------------------------------------------------------- derivation
def derive_factors(targets, derivation_path, config_path):
    """The P06 rule: union each target's viewports (resolving ``inherits``),
    ordered by the config viewports table. Widths live ONLY in config (R3) —
    names here reference config viewports; this returns names, never widths.

    Mirrors gates/coverage's resolve()+FACTORS exactly so the producer and the
    gate agree on what "derived form-factor set" means. Raises ValueError naming
    any unknown target (an operator may only pass a target the table declares)."""
    tbl = json.load(open(derivation_path))["targets"]
    cfg_vps = json.load(open(config_path))["viewports"]
    unknown = [t for t in targets if t not in tbl]
    if unknown:
        raise ValueError(
            f"unknown target(s): {', '.join(unknown)} — add an entry to "
            f"pipeline/state/targets.derivation.json (P06: targets are data, "
            f"never inferred)"
        )

    def vps_of(t, seen=None):
        seen = seen or set()
        if t in seen:
            return []
        seen.add(t)
        e = tbl[t]
        out = list(e.get("viewports", []))
        if e.get("inherits"):
            out = vps_of(e["inherits"], seen) + out
        return out

    union = []
    for t in targets:
        for v in vps_of(t):
            if v not in union:
                union.append(v)
    # config order; names the table forgot to put in config are dropped (R3).
    return [v for v in cfg_vps if v in union]


# ----------------------------------------------------------------- naming
def surface_dir(screen):
    """dir = <tab>_<short> from the screen id (the registry's stable key, §18).
    Single segment by construction; matches the existing app convention
    (projects_home/, settings_kits/) and the coverage gate's d==file-prefix
    contract (gates/coverage line ~211: f"{d}_view.dart")."""
    sid = screen["id"]
    parts = sid.split(".")
    if len(parts) != 2:
        raise ValueError(
            f"screen id '{sid}' is not <tab>.<short> — cannot derive a directory"
        )
    return f"{parts[0]}_{parts[1]}"


def _cap(s):
    return s[0].upper() + s[1:]  # desktop -> Desktop (no lowercasing of the tail)


# ----------------------------------------------------------------- dart stubs
def stub_view(screen, factors, targets):
    """The base _view.dart — the router's entry point. Declares <comp>View over
    its viewmodel. Does NOT wire the form-factor switch: that is the builder's
    job (plan 08), so the derived factors are recorded in the header, not
    faked with imports the stub does not yet use."""
    comp = screen["comp"]
    d = surface_dir(screen)
    fl = ", ".join(factors) if factors else "(none)"
    deps = screen.get("deps") or []
    deps_line = (f"//   deps (builder wires): {', '.join(deps)}\n"
                 if deps else "")
    return f"""// app-box-scaffolder: surface skeleton. STRUCTURE ONLY — the builder fills this.
//   surface:       {screen['surface']}
//   comp:          {comp}View
//   id:            {screen['id']}
//   shell:         {screen['shell']}
//   targets:       [{','.join(targets)}] -> derived form factors [{fl}]
{deps_line}// The widget tree and the form-factor switch are the builder's job (plan 08).
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import '{d}_viewmodel.dart';

class {comp}View extends StackedView<{comp}ViewModel> {{
  const {comp}View({{super.key}});

  @override
  Widget builder(context, viewModel, child) => const Scaffold(
        body: Center(child: Text('{screen['id']}')),
      );

  @override
  {comp}ViewModel viewModelBuilder(context) => {comp}ViewModel();
}}
"""


def stub_factor(screen, factor, targets):
    """One _view.<factor>.dart per DERIVED factor. macos derives desktop only,
    so no .mobile/.tablet is ever produced for a macos target (§16)."""
    comp = screen["comp"]
    d = surface_dir(screen)
    fc = _cap(factor)  # desktop -> Desktop
    return f"""// app-box-scaffolder: {factor} layout skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       {screen['surface']}
//   comp:          {comp}View{fc}
//   factor:        {factor}   (derived from targets=[{','.join(targets)}])
import 'package:flutter/material.dart';
import 'package:stacked/stacked.dart';

import '{d}_viewmodel.dart';

class {comp}View{fc} extends ViewModelWidget<{comp}ViewModel> {{
  const {comp}View{fc}({{super.key}});

  @override
  Widget build(context, viewModel) => const Scaffold(
        body: Center(child: Text('{screen['id']} · {factor}')),
      );
}}
"""


def stub_viewmodel(screen):
    """The <comp>ViewModel skeleton over BaseViewModel (stacked 3.x). The builder
    wires the services the structure recorded in `deps`."""
    comp = screen["comp"]
    deps = screen.get("deps") or []
    deps_line = (f"//   deps (builder wires): {', '.join(deps)}\n"
                 if deps else "")
    return f"""// app-box-scaffolder: view model skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       {screen['surface']}
//   comp:          {comp}ViewModel
{deps_line}// TODO(app-box-builder): wire services from the deps above.
import 'package:stacked/stacked.dart';

class {comp}ViewModel extends BaseViewModel {{}}
"""


def design_system_doc(screen, factors):
    """The design-system.md every surface dir must carry (the review gate's
    design_system_doc check). STRUCTURE ONLY — the builder fills the real intent
    (palette/type/spacing/motion/forbidden). The slot existing is the gate's
    contract; the content is the builder's job, same split as the view stubs."""
    return f"""# design-system — {screen['surface']}

> app-box-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.

- **surface:** `{screen['surface']}`  ({screen['id']})
- **shell:**  {screen['shell']}
- **derived form factors:** {', '.join(factors) if factors else '(none)'}

## Palette
<!-- builder: KitColors.* tokens this surface uses -->

## Type
<!-- builder: KitTypography.* roles -->

## Spacing
<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->

## Motion
<!-- builder: KitMotion.* curves/durations -->

## Forbidden
- `Icons.*` (use `KitGlyphs.*`)
- ad-hoc `Color(0x…)` (use `KitColors.*`)
- stock `ElevatedButton`/`FilledButton`/`TextButton` CTAs (use `KitNativeButton`)
"""


def _pascal(snake):
    """stage_shell -> StageShell (the shell's class-name convention)."""
    return "".join(_cap(p) for p in snake.split("_"))


def shell_design_system_doc(shell):
    """The shell-level design-system.md the scaffold gate (S4) requires at
    views/<shell>/design-system.md: a '## Palette' heading + a kit color
    reference (kc*/KitColors). STRUCTURE ONLY — the builder fills real intent.
    The per-surface docs (design_system_doc) carry the surface-level slot; this
    is the shell-wide one."""
    return f"""# design-system — {shell} (shell)

> app-box-scaffolder: STRUCTURE ONLY. The builder (plan 08) fills the real intent.

## Palette
- `KitColors` — the shell's palette source (builder: name the kc* tokens)

## Type
<!-- builder: KitTypography.* roles -->

## Spacing
<!-- builder: spacing tokens (no ad-hoc SizedBox gaps) -->

## Motion
<!-- builder: KitMotion.* curves/durations -->

## Forbidden
- `Icons.*` (use `KitGlyphs.*`)
- ad-hoc `Color(0x…)` (use `KitColors.*`)
- stock CTA buttons (use `KitNativeButton`)
"""


def shell_chrome(shell):
    """The *_chrome.dart every self-contained shell owns (scaffold gate S6 — a
    shell owns its widgets/chrome). STRUCTURE ONLY — the builder fills the real
    nav rail / tab bar / gate-badge layout."""
    comp = _pascal(shell)  # stage_shell -> StageShell
    return f"""// app-box-scaffolder: shell chrome skeleton. STRUCTURE ONLY — builder fills this.
//   shell:  {shell}
//   The chrome is the shell's persistent frame (nav rail / tabs / gate badge).
//   S6 (scaffold gate) requires every self-contained shell to own a chrome or a
//   widgets/ home; this stub satisfies ownership. The builder wires the layout.
import 'package:flutter/material.dart';

class {comp}Chrome {{
  const {comp}Chrome();
}}
"""


# ----------------------------------------------------------------- manifest
def build_manifest(frozen, factors, targets):
    """The .shell-structure.json the coverage gate reads: selfContained shells
    + the {shell: {surfaceId: dir}} map. The dir is the scaffolder's recorded
    decision (coverage.sh ~19-26: 'a directory name is a scaffolder DECISION,
    so it is recorded, not guessed')."""
    shells = sorted({s["shell"] for s in frozen})
    by_shell = {sh: {} for sh in shells}
    for s in frozen:
        by_shell[s["shell"]][s["surface"]] = surface_dir(s)
    fl = ", ".join(factors) if factors else "none"
    return {
        "selfContained": shells,
        "surfaces": by_shell,
        # the DERIVED form-factor set (§16): macos -> [desktop], never the full
        # mobile+tablet+desktop. The review gate (form_factor_files) reads this to
        # expect exactly these factor files — not the legacy 5-file set. §16/P14-14.8.
        "factors": factors,
        "targets": targets,
        "notes": (
            "scaffolded by app-box-scaffolder from a frozen structure.json; "
            f"targets=[{','.join(targets)}] -> form factors [{fl}]; "
            "dir=<tab>_<short> from the registry id (the stable key, §18). "
            "Widget bodies are the builder's job (plan 08)."
        ),
    }


# ----------------------------------------------------------------- io
def _fail(msg):
    print(f"FAIL: {msg}", file=sys.stderr)
    return None


def load_structure(design_root):
    """Read + sanity-check the frozen structure.json. Returns (data, None) on
    success or (None, errmsg) on failure (the caller prints errmsg). A missing
    structure.json is a HARD failure naming it (R5): a producer that cannot find
    its frozen input never passes quietly."""
    path = os.path.join(design_root, "structure.json")
    if not os.path.isfile(path):
        return None, (f"structure.json not found under {design_root} — scaffold "
                      f"needs a FROZEN structure.json. Run emit_structure first, "
                      f"or point KIT_DESIGN_DIR at the producer folder.")
    try:
        data = json.load(open(path))
    except ValueError as e:
        return None, f"structure.json does not parse as JSON — {e}"
    screens = data.get("screens")
    if not isinstance(screens, list):
        return None, "structure.json 'screens' is not a list — not a structure.json"
    return data, None


def _validate_frozen(frozen):
    """Every frozen surface must carry the keys the scaffold emits from. A
    surface with no viewmodel is the R5 negative: emit_structure should have
    failed first, but the scaffold defends anyway (never trust an invariant you
    do not re-check)."""
    for s in frozen:
        for req in ("id", "comp", "shell", "surface", "viewmodel"):
            if not s.get(req):
                who = s.get("id") or s.get("surface") or "?"
                return _fail(
                    f"screen '{who}' declares a surface '{s.get('surface')}' but "
                    f"has no '{req}' — structure.json is malformed (a frozen "
                    f"surface without a viewmodel is exactly what emit_structure "
                    f"refuses to produce; this one slipped through)"
                )
    return True


def expected_files(s, factors):
    """The exact file set one surface must carry: base _view.dart + one
    _view.<factor>.dart per DERIVED factor + _viewmodel.dart. This is the list
    the coverage gate (C1) walks, reproduced here so --check and the self-test
    assert the same contract."""
    d = surface_dir(s)
    return [f"{d}_view.dart"] + [f"{d}_view.{f}.dart" for f in factors] + \
        [f"{d}_viewmodel.dart"]


def scaffold(design_root, app_root, targets, derivation_path, config_path, check=False):
    data, err = load_structure(design_root)
    if err:
        _fail(err)
        return 1
    try:
        factors = derive_factors(targets, derivation_path, config_path)
    except ValueError as e:
        _fail(str(e))
        return 1

    frozen = [s for s in data["screens"] if s.get("surface")]
    if not frozen:
        _fail("structure.json declares no surfaces (surface:null everywhere) — "
              "nothing to scaffold; the design has nothing for the coverage gate")
        return 1
    if _validate_frozen(frozen) is not True:
        return 1

    views = os.path.join(app_root, "lib", "ui", "views")

    if check:
        return _check(views, frozen, factors, targets)

    per = 2 + len(factors)  # base + viewmodel + one per derived factor
    collisions = _dir_collisions(frozen)
    if collisions:
        return 1
    written = 0
    for s in frozen:
        d = surface_dir(s)
        base = os.path.join(views, s["shell"], d)
        os.makedirs(base, exist_ok=True)
        open(os.path.join(base, f"{d}_view.dart"), "w").write(
            stub_view(s, factors, targets))
        for f in factors:
            open(os.path.join(base, f"{d}_view.{f}.dart"), "w").write(
                stub_factor(s, f, targets))
        open(os.path.join(base, f"{d}_viewmodel.dart"), "w").write(
            stub_viewmodel(s))
        open(os.path.join(base, "design-system.md"), "w").write(
            design_system_doc(s, factors))
        written += 1

    # shell-level structure: each self-contained shell owns a design-system.md
    # (scaffold gate S4: ## Palette + KitColors) + a *_chrome.dart (S6). These
    # live at views/<shell>/ (the shell root); coverage ignores them (it counts
    # surface SUBDIRS, not shell-root files).
    for sh in sorted({s["shell"] for s in frozen}):
        sh_dir = os.path.join(views, sh)
        os.makedirs(sh_dir, exist_ok=True)
        open(os.path.join(sh_dir, "design-system.md"), "w").write(
            shell_design_system_doc(sh))
        open(os.path.join(sh_dir, f"{sh}_chrome.dart"), "w").write(
            shell_chrome(sh))

    manifest = build_manifest(frozen, factors, targets)
    os.makedirs(views, exist_ok=True)
    mf_path = os.path.join(views, ".shell-structure.json")
    open(mf_path, "w").write(json.dumps(manifest, indent=2) + "\n")

    fl = ", ".join(factors) if factors else "none"
    print(f"scaffold: {written} surface(s) x {per} file(s) = {written * per} files")
    print(f"  targets [{','.join(targets)}] -> form factors [{fl}]")
    print(f"  shells: {', '.join(sorted({s['shell'] for s in frozen}))}")
    print(f"  manifest -> {os.path.relpath(mf_path, app_root)}")
    return 0


def _dir_collisions(frozen):
    """Two surfaces deriving the same dir would be silently merged — the
    stale-green pattern. Detect and fail, naming both."""
    seen = {}
    for s in frozen:
        d = surface_dir(s)
        if d in seen:
            _fail(f"surfaces '{seen[d]}' and '{s['surface']}' both derive dir "
                  f"'{d}' (id collision) — the registry must give them distinct "
                  f"<tab>.<short> ids")
            return True
        seen[d] = s["surface"]
    return False


def _check(views, frozen, factors, targets):
    """Compare the on-disk tree against what structure.json + targets imply.
    Returns 0 if in sync, 1 naming every drift. Asserts the SAME file set the
    coverage gate (C1) walks, plus the manifest surfaces map / selfContained."""
    problems = []
    for s in frozen:
        d = surface_dir(s)
        base = os.path.join(views, s["shell"], d)
        for fn in expected_files(s, factors):
            if not os.path.isfile(os.path.join(base, fn)):
                problems.append(
                    f"lib/ui/views/{s['shell']}/{d}/{fn} missing — targets "
                    f"[{','.join(targets)}] derive form factors "
                    f"[{', '.join(factors) or 'none'}]")
    mf = os.path.join(views, ".shell-structure.json")
    want = build_manifest(frozen, factors, targets)
    if not os.path.isfile(mf):
        problems.append("lib/ui/views/.shell-structure.json missing — the "
                        "manifest the coverage gate reads")
    else:
        try:
            on_disk = json.load(open(mf))
        except ValueError as e:
            problems.append(f".shell-structure.json does not parse — {e}")
        else:
            if on_disk.get("surfaces") != want["surfaces"]:
                problems.append(".shell-structure.json surfaces drifted from "
                                "structure.json — re-run scaffold")
            if sorted(on_disk.get("selfContained") or []) != sorted(want["selfContained"]):
                problems.append(".shell-structure.json selfContained drifted "
                                "from structure.json — re-run scaffold")
    if problems:
        for p in problems:
            _fail(p)
        return 1
    fl = ", ".join(factors) if factors else "none"
    print(f"in-sync: {len(frozen)} surface(s), targets [{','.join(targets)}] "
          f"-> form factors [{fl}]")
    return 0


# ----------------------------------------------------------------- self-test
def _self_test():
    """Negative-case self-test (R5: a check that has never failed is not a
    check). Plants each defect and asserts the engine catches it, plus the
    §16 invariant: a macos target never emits an empty .mobile/.tablet."""
    P = [0]
    F = [0]

    def chk(cond, what):
        if cond:
            P[0] += 1
        else:
            F[0] += 1
            print(f"  FAIL: {what}")

    # a structure.json shaped like D1's stage_shell, but tiny (3 frozen + 1 excluded).
    STRUCT = {
        "$schema": "app-box/structure@1",
        "registry": "models/screens_model/registry.json",
        "tabRoots": {"projects": "/", "settings": "/settings"},
        "screens": [
            {"id": "stage.shell", "tab": "stage", "comp": "StageShell",
             "shell": "stage_shell", "surface": "stage_shell_view",
             "viewmodel": "ui/views/stage_shell/stage_shell_viewmodel.js",
             "deps": ["services/facades/shell_facade.js"]},
            {"id": "projects.home", "tab": "projects", "comp": "ProjectsHome",
             "shell": "stage_shell", "surface": "stage_shell_projects_home_view",
             "viewmodel": "ui/views/stage_shell/projects/home/home_viewmodel.js",
             "deps": ["services/facades/project_facade.js"]},
            {"id": "settings.kits", "tab": "settings", "comp": "SettingsKits",
             "shell": "stage_shell", "surface": "stage_shell_settings_kits_view",
             "viewmodel": "ui/views/stage_shell/settings/kits/kits_viewmodel.js",
             "deps": ["services/facades/shell_facade.js"]},
            {"id": "projects.splash", "tab": "projects", "comp": "ProjectsSplash",
             "shell": "stage_shell", "surface": None, "viewmodel": None, "deps": []},
        ],
    }

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        des = tmp / "design"
        des.mkdir()
        (des / "structure.json").write_text(json.dumps(STRUCT), encoding="utf-8")

        # 1. macos -> [desktop] -> exactly 3 files/surface, no empty factors.
        app1 = tmp / "app1"
        rc = scaffold(str(des), str(app1), ["macos"], str(DERIVATION), str(CONFIG))
        chk(rc == 0, "macos scaffold emits (exit 0)")
        chk(derive_factors(["macos"], str(DERIVATION), str(CONFIG)) == ["desktop"],
            "macos derives [desktop] only")
        # 3 frozen surfaces (splash is surface:null -> excluded) x 3 files
        for sid, d in [("stage.shell", "stage_shell"),
                       ("projects.home", "projects_home"),
                       ("settings.kits", "settings_kits")]:
            base = app1 / "lib" / "ui" / "views" / "stage_shell" / d
            chk((base / f"{d}_view.dart").is_file(), f"{d}: base _view.dart exists")
            chk((base / f"{d}_view.desktop.dart").is_file(), f"{d}: desktop factor exists")
            chk((base / f"{d}_viewmodel.dart").is_file(), f"{d}: viewmodel exists")
            # §16: NO empty .mobile/.tablet for a macos target
            chk(not (base / f"{d}_view.mobile.dart").exists(),
                f"{d}: no empty .mobile.dart (§16 stale-green guard)")
            chk(not (base / f"{d}_view.tablet.dart").exists(),
                f"{d}: no empty .tablet.dart (§16 stale-green guard)")
        # excluded surface (surface:null) is NOT scaffolded
        chk(not (app1 / "lib" / "ui" / "views" / "stage_shell" /
                 "projects_splash").exists(), "excluded surface (surface:null) not scaffolded")
        # manifest present and well-formed
        mf = json.load(open(app1 / "lib" / "ui" / "views" / ".shell-structure.json"))
        chk(mf["selfContained"] == ["stage_shell"], "manifest selfContained lists the shell")
        chk(mf["surfaces"]["stage_shell"]["stage_shell_projects_home_view"] == "projects_home",
            "manifest records the surface->dir decision")
        chk(len(mf["surfaces"]["stage_shell"]) == 3, "manifest maps exactly the 3 frozen surfaces")
        # shell-level structure: each self-contained shell owns a design-system.md
        # (scaffold gate S4: ## Palette + KitColors) + a *_chrome.dart (S6).
        sh = app1 / "lib" / "ui" / "views" / "stage_shell"
        chk((sh / "design-system.md").is_file(), "shell-level design-system.md emitted")
        ds = (sh / "design-system.md").read_text(encoding="utf-8")
        chk("## Palette" in ds and "KitColors" in ds,
            "shell design-system.md carries Palette heading + KitColors (S4)")
        chk((sh / "stage_shell_chrome.dart").is_file(),
            "shell *_chrome.dart emitted (S6)")

        # 2. ios,android -> [mobile, tablet] -> 4 files/surface, no desktop.
        chk(derive_factors(["ios", "android"], str(DERIVATION), str(CONFIG))
            == ["mobile", "tablet"], "ios,android derives [mobile, tablet]")
        app2 = tmp / "app2"
        rc = scaffold(str(des), str(app2), ["ios", "android"], str(DERIVATION), str(CONFIG))
        chk(rc == 0, "ios,android scaffold emits (exit 0)")
        base = app2 / "lib" / "ui" / "views" / "stage_shell" / "projects_home"
        chk((base / "projects_home_view.mobile.dart").is_file(), "ios,android: mobile factor exists")
        chk((base / "projects_home_view.tablet.dart").is_file(), "ios,android: tablet factor exists")
        chk(not (base / "projects_home_view.desktop.dart").exists(), "ios,android: no desktop factor")
        # 5 files: base + mobile + tablet + viewmodel + design-system.md (the
        # review gate's design_system_doc carrier; STRUCTURE ONLY, builder fills)
        got = sorted(p.name for p in base.iterdir())
        chk(len(got) == 5, f"ios,android: 5 files/surface (got {got})")
        chk((base / "design-system.md").is_file(), "design-system.md emitted per surface")

        # 3. web -> [mobile, tablet, desktop] -> 5 files/surface.
        chk(derive_factors(["web"], str(DERIVATION), str(CONFIG))
            == ["mobile", "tablet", "desktop"], "web derives [mobile, tablet, desktop]")

        # 4. NEGATIVE (R5): missing structure.json -> FAIL naming it.
        empty = tmp / "empty"; empty.mkdir()
        rc = scaffold(str(empty), str(tmp / "appE"), ["macos"], str(DERIVATION), str(CONFIG))
        chk(rc == 1, "missing structure.json -> exit 1")

        # 5. NEGATIVE (R5): a surface with no viewmodel -> FAIL naming it.
        bad = json.loads(json.dumps(STRUCT))
        bad["screens"][1]["viewmodel"] = None  # projects.home: surface set, vm null
        bdes = tmp / "bdesign"; bdes.mkdir()
        (bdes / "structure.json").write_text(json.dumps(bad), encoding="utf-8")
        rc = scaffold(str(bdes), str(tmp / "appB"), ["macos"], str(DERIVATION), str(CONFIG))
        chk(rc == 1, "surface with no viewmodel -> exit 1")

        # 6. NEGATIVE (R5): wrong file count -> --check FAILS naming the file.
        #    (macos scaffold from step 1, then delete one derived factor file.)
        missing = app1 / "lib" / "ui" / "views" / "stage_shell" / "projects_home" \
            / "projects_home_view.desktop.dart"
        missing.unlink()
        rc = scaffold(str(des), str(app1), ["macos"], str(DERIVATION), str(CONFIG), check=True)
        chk(rc == 1, "wrong file count -> --check exit 1")
        missing.write_text("// restored", encoding="utf-8")  # restore for the next check
        chk(scaffold(str(des), str(app1), ["macos"], str(DERIVATION), str(CONFIG), check=True) == 0,
            "--check green again after restoring the file")

        # 7. NEGATIVE: unknown target -> FAIL naming it.
        rc = scaffold(str(des), str(tmp / "appU"), ["zxspectrum"], str(DERIVATION), str(CONFIG))
        chk(rc == 1, "unknown target -> exit 1")

        # 8. NEGATIVE: two surfaces deriving the same dir (id collision) -> FAIL.
        coll = json.loads(json.dumps(STRUCT))
        # rename settings.kits -> projects.kits: same <tab>_<short> as nothing? no.
        # instead force a real collision: a second screen projects.home.
        coll["screens"].append({"id": "projects.home", "tab": "projects",
                                "comp": "ProjectsHome2", "shell": "stage_shell",
                                "surface": "stage_shell_projects_home_2_view",
                                "viewmodel": "ui/views/x.js", "deps": []})
        cdes = tmp / "cdesign"; cdes.mkdir()
        (cdes / "structure.json").write_text(json.dumps(coll), encoding="utf-8")
        rc = scaffold(str(cdes), str(tmp / "appC"), ["macos"], str(DERIVATION), str(CONFIG))
        chk(rc == 1, "dir collision (two surfaces, same <tab>_<short>) -> exit 1")

        # 9. derivation agrees with the coverage gate's own rule (macos -> desktop,
        #    ios,android -> mobile+tablet, web -> all three): the producer and the
        #    gate must never disagree on what "derived" means.
        chk(derive_factors(["pwa"], str(DERIVATION), str(CONFIG))
            == ["mobile", "tablet", "desktop"], "pwa inherits web -> all three factors")

        # 10. a scaffolded file carries the right class name (builder's hook).
        view = (app1 / "lib" / "ui" / "views" / "stage_shell" / "projects_home"
                / "projects_home_view.dart").read_text(encoding="utf-8")
        chk("class ProjectsHomeView extends StackedView<ProjectsHomeViewModel>" in view,
            "base view declares <comp>View over its viewmodel")
        vm = (app1 / "lib" / "ui" / "views" / "stage_shell" / "projects_home"
              / "projects_home_viewmodel.dart").read_text(encoding="utf-8")
        chk("class ProjectsHomeViewModel extends BaseViewModel" in vm,
            "viewmodel declares <comp>ViewModel over BaseViewModel")

    print(f"\nscaffold self-test: passed={P[0]} failed={F[0]}")
    if F[0]:
        return 1
    print("ALL GREEN")
    return 0


# ----------------------------------------------------------------- cli
def _targets_from(args, env):
    """Explicit --targets wins; APPBOX_TARGETS env is the deterministic fallback.
    Never reads ambient pipeline state silently — a reproducibility run that
    picked up whatever targets happen to be in state is the stale-green defect
    the coverage gate warns about (coverage.sh ~436-442)."""
    if args.targets:
        return [t for t in args.targets.split(",") if t]
    env_t = env.get("APPBOX_TARGETS", "")
    if env_t:
        return [t for t in env_t.split(",") if t]
    return []


def main(argv):
    p = argparse.ArgumentParser(
        prog="scaffold.py",
        description="scaffold per-surface Dart from a frozen structure.json + targets (§16)")
    p.add_argument("--self-test", action="store_true",
                   help="run the negative-case self-test (R5)")
    p.add_argument("--design-dir", default=os.environ.get("KIT_DESIGN_DIR", "design"),
                   help="frozen design root (app-root-relative; carries structure.json)")
    p.add_argument("--app-root", default=os.environ.get("KIT_APP", "."),
                   help="app root to scaffold lib/ui/views/ under")
    p.add_argument("--targets", default=None,
                   help="comma-separated targets (macos, ios, android, web, ...)")
    p.add_argument("--check", action="store_true",
                   help="compare the on-disk tree against structure.json + targets (drift)")
    args = p.parse_args(argv)

    if args.self_test:
        return _self_test()

    targets = _targets_from(args, os.environ)
    if not targets:
        _fail("no --targets given (and no APPBOX_TARGETS env) — pass --targets "
              "explicitly; a scaffold run that reads ambient state is the "
              "stale-green defect (§16)")
        return 1
    if os.path.isabs(args.design_dir):
        _fail("--design-dir must stay app-root-relative (R3: no absolute paths)")
        return 1

    design_root = os.path.abspath(os.path.join(args.app_root, args.design_dir))
    app_root = os.path.abspath(args.app_root)
    return scaffold(design_root, app_root, targets, str(DERIVATION), str(CONFIG),
                    check=args.check)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
