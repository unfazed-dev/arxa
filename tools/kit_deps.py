#!/usr/bin/env python3
"""kit_deps.py — derive an app's stacked_kit dependency set and emit pubspec lines
through the dependencyMode switch (plan 03.9–03.14).

The kit is PRIVATE. A buyer cannot `flutter pub get` a git ref to it. So every kit
reference in a generated pubspec.yaml routes through config/app-box.config.json
`dependencyMode`:

  vendored (default) → path deps into <app>/packages/<dir>/  (no network, no kit
                       repo access at build time; the kits are copied in).
  hosted              → ordinary version constraints (unusable until the kit
                       publishes; implemented now so publishing is a config flip).

The kit set is derived PER APP from targets + selected capabilities (architecture
§11), never "all 23": a phone-only app with no maps gets no stacked_kit_maps.

CLI:
  kit_deps.py derive [--capabilities a,b,...]              list the seed kit set
  kit_deps.py pubspec [--mode vendored|hosted]             emit pubspec dep lines
  kit_deps.py copy  --app <dir> [--capabilities ...]       copy closure into <app>/packages/
Env:
  KIT_REPO  — stacked_kit checkout path (the copy source). Defaults to config kit.repo.
"""
import json, os, re, shutil, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(REPO, "config", "app-box.config.json")
REGISTRY = os.path.join(REPO, "tools", "vendor", "kit_registry", "kit-registry.json")

# Kits every app needs regardless of capabilities (the spine).
CORE_TOPOLOGY = {"core", "core-coupled"}


def load_cfg():
    with open(CONFIG) as f:
        return json.load(f)


def load_kits():
    with open(REGISTRY) as f:
        return json.load(f)["kits"]


def kit_source():
    """Where the stacked_kit checkout lives (copy source). Env wins (R3: not
    hardcoded). Required for the vendored copy + transitive-closure discovery."""
    return os.environ.get("KIT_REPO") or load_cfg().get("kit", {}).get("repo", "")


def derive_kits(capabilities=None, kits=None):
    """Seed kit set for an app: the core spine + any kit whose capabilities
    intersect the app's selected capabilities (§11). Returns registry-order list.
    Smaller than the full registry for any app that does not use every capability."""
    kits = kits or load_kits()
    capset = set(capabilities or [])
    chosen = []
    for k in kits:
        if k.get("topology") in CORE_TOPOLOGY or (set(k.get("capabilities", [])) & capset):
            chosen.append(k)
    return chosen


def _kit_path_deps(kit_dir, src):
    """Sibling kit dirs a kit points at via `path: ../<dir>` in its pubspec."""
    p = os.path.join(src, kit_dir, "pubspec.yaml")
    if not os.path.isfile(p):
        return []
    return re.findall(r'path:\s*\.\./([a-z0-9_]+)', open(p).read())


def transitive_closure(seed_dirs, src, kits=None):
    """Full set of kit dirs that must be present for the seed kits' internal path
    deps to resolve. Discovered by reading each kit's pubspec — never assumed."""
    kits = kits or load_kits()
    by_dir = {k["dir"]: k for k in kits}
    closure, stack = set(), list(seed_dirs)
    while stack:
        d = stack.pop()
        if d in closure:
            continue
        closure.add(d)
        for dep in _kit_path_deps(d, src):
            if dep in by_dir and dep not in closure:
                stack.append(dep)
    order = [k["dir"] for k in kits]
    return [d for d in order if d in closure]


def emit_pubspec_deps(seed, mode):
    """YAML dependency lines for each seed kit, routed through dependencyMode."""
    lines = []
    for k in seed:
        if mode == "vendored":
            lines.append(f"  {k['package']}:\n    path: packages/{k['dir']}")
        else:  # hosted
            lines.append(f"  {k['package']}: ^0.1.0")
    return "\n".join(lines)


def copy_kits(closure_dirs, src, packages_dir):
    """Copy each kit dir (transitive closure) into <app>/packages/. Idempotent:
    overwrites a stale copy so a re-run is a fresh vendor, not a merge."""
    if not src or not os.path.isdir(src):
        raise SystemExit(f"kit_deps: KIT_REPO not set or not a dir (got {src!r}) — "
                         f"set KIT_REPO to the stacked_kit checkout for vendored mode")
    os.makedirs(packages_dir, exist_ok=True)
    copied = []
    for d in closure_dirs:
        s = os.path.join(src, d)
        dst = os.path.join(packages_dir, d)
        if not os.path.isdir(s):
            print(f"  skip {d}: not in kit source", file=sys.stderr)
            continue
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        ignore = shutil.ignore_patterns(".git", ".dart_tool", "build", "__pycache__")
        shutil.copytree(s, dst, ignore=ignore)
        copied.append(d)
    return copied


def _kit_sha(src):
    """The stacked_kit commit the vendored copy was taken from. git rev-parse of
    the source checkout; falls back to config kit.sha, then 'unknown'."""
    if src and os.path.isdir(os.path.join(src, ".git")):
        import subprocess
        try:
            return subprocess.run(["git", "-C", src, "rev-parse", "HEAD"],
                                  capture_output=True, text=True).stdout.strip()
        except Exception:
            pass
    return load_cfg().get("kit", {}).get("sha", "") or "unknown"


def write_app_lock(app_dir, closure_dirs, src):
    """Record the vendored kit SHA + copied dirs in <app>/packages/.vendor.lock
    (plan 03.14) so check_freshness can cover app deps, not just tooling."""
    pkgs = os.path.join(app_dir, "packages")
    os.makedirs(pkgs, exist_ok=True)
    rec = {
        "kitSha": _kit_sha(src),
        "kitRepo": os.environ.get("KIT_REPO", "") or load_cfg().get("kit", {}).get("repo", ""),
        "kits": closure_dirs,
        "mode": "vendored",
    }
    import datetime
    rec["copiedAt"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    with open(os.path.join(pkgs, ".vendor.lock"), "w") as f:
        json.dump(rec, f, indent=2, sort_keys=True)
        f.write("\n")
    return rec


def _strip_kit_deps(text, kit_pkgs):
    """Remove existing kit dependency entries (path-dep or version) from pubspec
    text. A kit entry is `  <pkg>:` + optional following indented `    path:` line,
    or `  <pkg>: ^x.y.z`."""
    out = text
    for pkg in kit_pkgs:
        # multi-line: "  pkg:\n    path: ...\n"
        out = re.sub(r'\n  ' + re.escape(pkg) + r':\n    path: [^\n]+\n', '\n', out)
        # single-line: "  pkg: ^...\n"  (only if not already a multi-line head)
        out = re.sub(r'\n  ' + re.escape(pkg) + r': \^[^\n]+\n', '\n', out)
    return out


def rewrite_pubspec(app_dir, seed, mode):
    """Rewrite an app's pubspec.yaml so its kit deps reflect `mode`. Idempotent.
    Returns True if the file changed."""
    p = os.path.join(app_dir, "pubspec.yaml")
    text = open(p).read()
    kit_pkgs = [k["package"] for k in load_kits()]
    cleaned = _strip_kit_deps(text, kit_pkgs)
    block = emit_pubspec_deps(seed, mode)
    if "dependencies:" not in cleaned:
        cleaned = cleaned.rstrip() + "\n\ndependencies:\n"
    # insert the kit block immediately under the first `dependencies:` header
    out = re.sub(r'(dependencies:\n)', r'\1' + block + '\n', cleaned, count=1)
    if out != text:
        open(p, "w").write(out)
        return True
    return False


def _parse_caps(arg):
    return [c.strip() for c in arg.split(",") if c.strip()] if arg else []


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    caps = None
    app_dir = None
    mode = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--capabilities" and i + 1 < len(argv):
            caps = _parse_caps(argv[i + 1]); i += 2
        elif a == "--app" and i + 1 < len(argv):
            app_dir = argv[i + 1]; i += 2
        elif a == "--mode" and i + 1 < len(argv):
            mode = argv[i + 1]; i += 2
        else:
            i += 1
    cfg = load_cfg()
    mode = mode or cfg.get("dependencyMode", "vendored")
    seed = derive_kits(caps)
    seed_dirs = [k["dir"] for k in seed]

    if cmd == "derive":
        print(f"# seed kit set ({len(seed)} of {len(load_kits())}, mode={mode})")
        for k in seed:
            print(f"{k['package']}\t{k['dir']}\t{k.get('topology')}")
        return 0
    if cmd == "pubspec":
        print(f"# dependencyMode: {mode}")
        print(emit_pubspec_deps(seed, mode))
        return 0
    if cmd == "copy":
        if not app_dir:
            print("kit_deps copy: --app <dir> required", file=sys.stderr); return 2
        src = kit_source()
        closure = transitive_closure(seed_dirs, src)
        pkgs = os.path.join(app_dir, "packages")
        copied = copy_kits(closure, src, pkgs)
        rec = write_app_lock(app_dir, closure, src)   # 3.14: app-level vendor lock
        print(f"copied {len(copied)} kit(s) → {pkgs}: {', '.join(copied)}")
        print(f"vendor.lock: kitSha={rec['kitSha'][:12]}…")
        return 0
    if cmd == "lock":
        if not app_dir:
            print("kit_deps lock: --app <dir> required", file=sys.stderr); return 2
        src = kit_source()
        closure = transitive_closure(seed_dirs, src)
        rec = write_app_lock(app_dir, closure, src)
        print(f"vendor.lock written: kitSha={rec['kitSha'][:12]}… kits={len(rec['kits'])}")
        return 0
    if cmd == "rewrite":
        if not app_dir:
            print("kit_deps rewrite: --app <dir> required", file=sys.stderr); return 2
        changed = rewrite_pubspec(app_dir, seed, mode)
        print(f"rewrite → {mode} ({'changed' if changed else 'already'})")
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
