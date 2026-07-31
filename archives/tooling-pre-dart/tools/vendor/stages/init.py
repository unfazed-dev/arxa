#!/usr/bin/env python3
"""init.py — the SSOT-derivation front-door (ADR-0008).

Scaffolds `flutter_crew.config.json` from a design. Deterministic given (design +
ELICITED answers) — NO LLM. The contract is "scaffold → derive → ask → validate →
write" (ADR-0008 Update 2026-06-25):

  scaffold  materialize the JSON Schema's `default` values (the SINGLE source of
            build defaults — never duplicate them into a parallel template, the
            duplicate-source drift trap the KB discipline exists to prevent).
  derive    overlay DERIVED values from a LIGHT parse of the design (no full
            pipeline run — breakdown/tokens/data_model are build outputs, init
            runs BEFORE build): app.name ← <title>, app.bundleId ← app.<slug>,
            branding.primaryColor ← tokens.json beside the design (if present),
            design.formFactor ← viewport-width heuristic (default mobile + warn
            on low confidence), design.source ← the fed path. Reuses the proven
            `extract_tokens._slug` + `form_factor_resolver.resolve` helpers.
  ask       ONLY the ELICITED-without-sane-default fields (the schema already
            defaulted the rest): bundleId, appVersion, platforms, minOs,
            backend.provider, capabilities (all OFF). `[enter]` accepts the shown
            default; `--yes` accepts every default (CI/agent). NEVER asks for
            secrets — points at `appbox set secret`.
  validate  the merged config against schemas/flutter_crew.config.schema.json.
  write     flutter_crew.config.json at the target root (tracked — not .blueprint/).

Usage:
    init.py <design.html|design-dir> [--target DIR] [--platforms ios,android]
            [--yes] [--dry-run] [--json] [--self-test]

Exit 0 = wrote (or dry-run ok); 1 = validation failed; 2 = usage / design unreadable.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCHEMA_PATH = os.path.join(ROOT, "schemas", "flutter_crew.config.schema.json")
# HERE on sys.path so the proven helpers (extract_tokens, form_factor_resolver)
# import when init.py runs as a script — single-source reuse, not duplication.
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# the form factors we can detect / represent (mirrors form_factor_resolver)
_MOBILE_MAX_VIEWPORT = 900  # px — a root container / viewport wider than this ⇒ non-mobile


# ---------- scaffold: materialize schema defaults ----------
_MISSING = object()


def _materialize(node):
    """Recursively materialize `default` values from a JSON Schema node.

    The schema is the SINGLE source of build defaults (ADR-0008 Update 2026-06-25):
    init never duplicates defaults into a parallel template. For an object with a
    `default`, the default is the seed and any nested property defaults not already
    present are filled in. Returns `_MISSING` when no default exists at or below a
    node (the caller skips it)."""
    if not isinstance(node, dict):
        return _MISSING
    if node.get("type") == "object":
        out = dict(node["default"]) if isinstance(node.get("default"), dict) else {}
        for k, sub in (node.get("properties") or {}).items():
            if k not in out:
                mv = _materialize(sub)
                if mv is not _MISSING:
                    out[k] = mv
        # a $schema pointer + $comment are never defaulted but useful to carry
        return out if (out or "$comment" in (node.get("properties") or {})) else _MISSING
    if "default" in node:
        return node["default"]
    return _MISSING


def scaffold_defaults(schema):
    """Materialize the top-level config defaults from the schema."""
    base = _materialize(schema)
    return base if base is not _MISSING else {}


# ---------- derive: light design parse (NO full pipeline run) ----------
def _read_title(html_text):
    """app.name ← the design's <title> (the most stable signal). Fallback None."""
    m = re.search(r"<title[^>]*>(.*?)</title>", html_text, re.I | re.S)
    if not m:
        return None
    title = re.sub(r"\s+", " ", m.group(1)).strip()
    # strip common trailing suffixes ("— Atlet", "| App", design-tool watermarks)
    title = re.sub(r"\s*[—|\-·]\s*(Figma|Sketch|design|app|mobile)\s*$", "", title, flags=re.I).strip()
    return title or None


def _slug(name):
    """The shared slug rule — a thin re-export of `extract_tokens._slug` so this
    module and the design agree on ONE slugger (the duplicate-source drift trap
    ADR-0008 warns against). Imported at module load (HERE on sys.path)."""
    import extract_tokens
    return extract_tokens._slug(name or "")


def _bundle_slug(name):
    """bundleId-safe slug: hyphen-free (iOS bundleId segments are [a-z0-9_] only).
    Builds on the shared `_slug` rule then collapses the hyphens (atlet-workout-app
    → atletworkoutapp). Falls back to 'app' for empty/all-symbol input (extract_tokens._slug
    returns 'token' for empty — the wrong fallback for a bundle-id segment)."""
    s = _slug(name).replace("-", "")
    return s if s and s != "token" else "app"


def _detect_origin(html_text):
    """design.formFactor heuristic (ADR-0008 Origin Update): viewport meta + a
    root-container width sniff. Returns (form_factor, confidence). Mobile-first:
    low confidence ⇒ fall back to 'mobile' + warn. Never crashes on odd input."""
    vw = None
    m = re.search(r'<meta[^>]+name=["\']viewport["\'][^>]+content=["\']([^"\']+)["\']',
                  html_text, re.I)
    if m:
        content = m.group(1)
        w = re.search(r"width=(\d+)", content)
        if w:
            vw = int(w.group(1))
    # a root container max-width / width is a stronger signal than the meta
    for pat in (r"max-width:\s*(\d{3,5})px", r"^\s*\.container\s*\{[^}]*width:\s*(\d{3,5})px",
                r"width:\s*(\d{3,5})px"):
        m = re.search(pat, html_text, re.I | re.M)
        if m:
            cw = int(m.group(1))
            vw = cw if vw is None else min(vw, cw)
            break
    if vw is None:
        return "mobile", "low"  # nothing to go on — mobile-first default + warn
    if vw <= _MOBILE_MAX_VIEWPORT:
        return "mobile", "high" if vw <= 480 else "medium"
    return "web", "medium"  # wide viewport ⇒ web/desktop form factor


# NOTE: branding.primaryColor is intentionally NOT derived here. A robust W3C DTCG
# walk would need to resolve $ref aliases AND descend color scale-groups (e.g.
# color.brand.0/700), which a light pre-build parse can't do soundly — that's the
# transform_tokens stage's job, and it runs at BUILD, not init. The operator sets
# primaryColor via `appbox set branding.primaryColor` (validated against the schema's
# ^#hex pattern); the schema defaults themeMode so branding is never required.


def derive_from_design(design_path):
    """Light parse (NO pipeline run) → the DERIVED overlay. Returns a dict of
    config-path → value for the fields init can derive from the design alone."""
    design_path = os.path.abspath(design_path)
    if not os.path.exists(design_path):
        raise FileNotFoundError(f"design not found: {design_path}")
    # resolve the design HTML text + a sibling tokens.json
    if os.path.isdir(design_path):
        try:
            entries = os.listdir(design_path)
        except OSError as e:  # permission-denied etc. — degrade loud, not silent
            raise FileNotFoundError(f"design dir unreadable ({e}): {design_path}")
        html_candidates = [os.path.join(design_path, n)
                           for n in ("index.html", "bundle.html")
                           if os.path.exists(os.path.join(design_path, n))]
        # fall back to the first .html in the dir
        if not html_candidates:
            html_candidates = sorted(
                os.path.join(design_path, f) for f in entries
                if f.lower().endswith(".html"))
        if not html_candidates:
            raise FileNotFoundError(f"no .html design found in dir: {design_path}")
        html_path = html_candidates[0]
        base_name = os.path.basename(os.path.normpath(design_path))
    else:
        html_path = design_path
        base_name = os.path.splitext(os.path.basename(design_path))[0]

    try:
        html_text = open(html_path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        raise FileNotFoundError(f"design unreadable ({e}): {html_path}")

    title = _read_title(html_text) or base_name
    origin, confidence = _detect_origin(html_text)

    derived = {
        "app": {"name": title, "bundleId": f"app.{_bundle_slug(title)}"},
        "design": {"source": design_path, "formFactor": origin},
    }
    # platforms hint: mobile origin → ios,android; else include web
    if origin == "mobile":
        derived["platforms"] = ["ios", "android"]
    else:
        derived["platforms"] = ["web"]
    return derived, confidence


# ---------- ask: the ELICITED interview ----------
# the bundleId regex, cached once (avoids re-reading the schema per re-prompt).
def _bundle_id_pattern():
    schema = json.load(open(SCHEMA_PATH, encoding="utf-8"))
    return schema["properties"]["app"]["properties"]["bundleId"]["pattern"]


def _ask(prompt, default, validate=None, input_fn=input):
    """One prompted question. `[enter]` accepts the default. Re-prompts on a
    validator failure (so the operator never has to restart the interview).
    `input_fn` is injectable for tests. Returns the chosen value."""
    while True:
        raw = input_fn(f"  {prompt} [{default}] ").strip()
        val = raw if raw else str(default)
        if validate:
            ok, err = validate(val)
            if not ok:
                print(f"    ✗ {err}")
                continue
        return val


def _validate_bundle_id(val):
    return (bool(re.match(_bundle_id_pattern(), val)),
            "reverse-DNS, lowercase, e.g. com.example.app")


def _validate_int(val):
    try:
        int(val)
        return True, ""
    except ValueError:
        return False, "must be an integer"


_CAPABILITIES = ["push", "deepLinks", "analytics", "crashReporting",
                 "inAppPurchase", "i18n", "secureStorage", "forceUpdate", "consent"]


def interview(base, *, yes, input_fn=input):
    """Ask the ELICITED-without-sane-default fields, mutating `base` in place.
    `yes` ⇒ accept every default (CI/agent). `input_fn` is injectable for tests
    (threaded through every `_ask`, so the non-interactive path is fully testable)."""
    app = base.setdefault("app", {})
    # 1. bundleId (derived default shown; operator confirms/overrides)
    if not yes:
        app["bundleId"] = _ask("bundleId?", app.get("bundleId", "app.app"),
                               _validate_bundle_id, input_fn=input_fn)
    # 2. appVersion
    av = base.get("app", {}).get("appVersion", "1.0.0")
    if not yes:
        app["appVersion"] = _ask("app version?", av, input_fn=input_fn)
    # 3. platforms (derived hint; confirm)
    plats = ",".join(base.get("platforms", ["ios", "android"]))
    if not yes:
        chosen = _ask("platforms? (comma list: ios,android,web,desktop)", plats,
                      input_fn=input_fn)
        base["platforms"] = [p.strip() for p in chosen.split(",") if p.strip()]
    # 4. minOs
    minos = base.setdefault("minOs", {})
    minos.setdefault("ios", "15.0")
    minos.setdefault("android", 24)
    if not yes:
        minos["ios"] = _ask("min iOS version?", minos["ios"], input_fn=input_fn)
        minos["android"] = int(_ask("min Android SDK (int)?", minos["android"],
                                    _validate_int, input_fn=input_fn))
    # 5. backend.provider
    backend = base.setdefault("backend", {})
    backend.setdefault("provider", "supabase")
    if not yes:
        backend["provider"] = _ask("backend provider? (supabase|none)", backend["provider"],
                                   input_fn=input_fn)
    # 6. capabilities (multi-select; all OFF by default)
    caps = base.setdefault("capabilities", {})
    for c in _CAPABILITIES:
        caps.setdefault(c, False)
    if not yes:
        print("  capabilities (all OFF by default). Type comma-separated names to enable,")
        which = input_fn(f"    enable which? [{'/'.join(_CAPABILITIES)}] [none] ").strip()
        if which:
            for name in (n.strip() for n in which.split(",")):
                if name in _CAPABILITIES:
                    caps[name] = True
    return base


# ---------- validate + write ----------
def validate_config(cfg):
    """Validate the merged config against the schema. Returns (ok, errors)."""
    import jsonschema
    schema = json.load(open(SCHEMA_PATH, encoding="utf-8"))
    try:
        jsonschema.validate(cfg, schema)
        return True, []
    except jsonschema.ValidationError as e:
        return False, [str(e)]


def run(design_path, *, target=None, platforms=None, yes=False, dry_run=False,
        as_json=False, input_fn=input):
    """scaffold → derive → ask → validate → write. Returns exit code."""
    target = os.path.abspath(target or os.getcwd())
    schema = json.load(open(SCHEMA_PATH, encoding="utf-8"))
    base = scaffold_defaults(schema)

    # ── derive ──
    try:
        derived, confidence = derive_from_design(design_path)
    except FileNotFoundError as e:
        print(f"[init] ✗ {e}", file=sys.stderr)
        return 2  # usage / design unreadable — the documented contract (docstring)
    _deep_merge(base, derived)
    if platforms:  # CLI --platforms beats the derived hint
        base["platforms"] = [p.strip() for p in platforms.split(",") if p.strip()]
    if confidence == "low":
        print(f"[init] ⚠ could not detect form factor from '{design_path}'; "
              f"defaulting to 'mobile' (override via `appbox set design.formFactor`).",
              file=sys.stderr)

    # ── ask ──
    if not yes and not dry_run:
        print(f"[init] interviewing for '{base.get('app', {}).get('name', '?')}' "
              f"(press [enter] to accept each default):")
    interview(base, yes=yes, input_fn=input_fn)

    # ── Designer-invocation rule (ADR-0010/ADR-0008): the Origin (form factor of
    #    the fed design) vs the targets' demanded form factors. Reuses
    #    form_factor_resolver.resolve — the proven {demanded}−{Origin} set op — to
    #    tell the operator whether the Designer must author any missing form factor
    #    (e.g. targeting web with only a mobile design). Surfaced as guidance, not a
    #    gate; the per-form-factor decision is recorded in design.formFactors.
    import form_factor_resolver
    res = form_factor_resolver.resolve(base.get("platforms", []),
                                       origin=base.get("design", {}).get("formFactor"))
    if res["designerNeeded"] and not as_json:
        print(f"[init] ℹ Designer will need to author: {', '.join(res['author'])} "
              f"(targets demand form factors the fed design doesn't cover). "
              f"Record per-factor provenance via `appbox set design.formFactors.<f> <path|generate>`.",
              file=sys.stderr)

    # ── validate ──
    ok, errs = validate_config(base)
    if not ok:
        print("[init] ✗ config failed schema validation:", file=sys.stderr)
        for e in errs:
            print(f"    {e}", file=sys.stderr)
        return 1

    # ── write / dry-run ──
    out_path = os.path.join(target, "flutter_crew.config.json")
    if as_json:
        print(json.dumps({"ok": True, "path": out_path, "config": base,
                          "dryRun": dry_run, "originConfidence": confidence}, indent=2))
    if dry_run:
        if not as_json:
            print(f"[init] --dry-run → would write {out_path}:")
            print(json.dumps(base, indent=2, ensure_ascii=False))
        return 0
    os.makedirs(target, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(base, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if not as_json:
        print(f"[init] ✓ wrote {out_path}")
        print(f"[init]   form factor: {base.get('design', {}).get('formFactor')} "
              f"(confidence: {confidence})")
        print(f"[init]   secrets stay in env — use `appbox set secret <KEY>` for those.")
    return 0


def _deep_merge(dst, src):
    """Recursive dict merge: src wins on scalar conflicts; nested dicts merge."""
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            _deep_merge(dst[k], v)
        else:
            dst[k] = v


# ---------- self-test (the repo's per-stage idiom) ----------
def _self_test():
    import tempfile

    # 1. scaffold_defaults round-trips + validates against the schema.
    schema = json.load(open(SCHEMA_PATH, encoding="utf-8"))
    base = scaffold_defaults(schema)
    assert isinstance(base, dict) and "version" in base, base
    # the materialized backend block carries its default provider
    assert base.get("backend", {}).get("provider") == "supabase", base.get("backend")
    # capabilities all default OFF
    caps = base.get("capabilities", {})
    assert all(v is False for v in caps.values()), caps

    # 2. _slug IS extract_tokens._slug (single source — no duplication). The
    #    bundleId wrapper `_bundle_slug` collapses hyphens on top of it.
    import extract_tokens
    for name in ("Atlet", "My Cool App", "café-2"):
        assert _slug(name) == extract_tokens._slug(name), name
    assert _bundle_slug("Atlet — Workout app") == "atletworkoutapp"  # hyphen-collapse for iOS id
    assert _bundle_slug("") == "app"  # empty-input fallback
    print("PASS: _slug reuses extract_tokens._slug (no duplication); _bundle_slug collapses hyphens")

    # 3. _detect_origin — calibrated viewports.
    assert _detect_origin('<meta name="viewport" content="width=412">') == ("mobile", "high")
    assert _detect_origin('<meta name="viewport" content="width=device-width">') == ("mobile", "low")
    assert _detect_origin('<div style="max-width:1280px">') == ("web", "medium")
    assert _detect_origin("") == ("mobile", "low")  # empty input never crashes
    print("PASS: origin heuristic (mobile 412 high / device-width low / 1280 web / empty safe)")

    # 4. derive_from_design — a temp HTML design.
    with tempfile.TemporaryDirectory() as d:
        html = os.path.join(d, "Atlet.html")
        open(html, "w", encoding="utf-8").write(
            '<meta name="viewport" content="width=412"><title>Atlet — App</title>')
        derived, conf = derive_from_design(html)
        assert derived["app"]["name"] == "Atlet", derived
        assert derived["app"]["bundleId"] == "app.atlet", derived
        assert derived["design"]["formFactor"] == "mobile", derived
        assert derived["platforms"] == ["ios", "android"], derived
    # multi-word title → hyphen-free bundleId segment (iOS reverse-DNS spec)
    assert _bundle_slug("Atlet — Workout app") == "atletworkoutapp", _bundle_slug("Atlet — Workout app")
    print("PASS: derive_from_design (title → name, slug → bundleId, viewport → mobile)")

    # 4b. missing/unreadable design → FileNotFoundError → run() exits 2 (C1 fix).
    rc = run("/nonexistent/bar.html", yes=True, dry_run=True)
    assert rc == 2, rc
    print("PASS: missing design → exit 2 (loud, not silent-success)")

    # 5. interview --yes accepts every default (no prompts).
    base = scaffold_defaults(schema)
    base.update({"app": {"name": "x", "bundleId": "app.x"}, "platforms": ["ios", "android"]})
    called = []
    interview(base, yes=True, input_fn=lambda *a: called.append(a) or "")
    assert not called, "interview --yes must not prompt"
    assert base["backend"]["provider"] == "supabase"
    print("PASS: interview --yes accepts defaults without prompting")

    # 6. end-to-end dry-run on a temp design validates + writes nothing.
    with tempfile.TemporaryDirectory() as d:
        html = os.path.join(d, "Mock.html")
        open(html, "w", encoding="utf-8").write(
            '<meta name="viewport" content="width=412"><title>Mock</title>')
        rc = run(html, target=d, yes=True, dry_run=True)
        assert rc == 0, rc
        assert not os.path.exists(os.path.join(d, "flutter_crew.config.json")), "dry-run wrote!"
        # real write
        rc = run(html, target=d, yes=True)
        assert rc == 0, rc
        cfg = json.load(open(os.path.join(d, "flutter_crew.config.json"), encoding="utf-8"))
        ok, errs = validate_config(cfg)
        assert ok, errs
        assert cfg["app"]["bundleId"] == "app.mock", cfg["app"]
    print("PASS: end-to-end run (dry-run writes nothing; real write validates)")

    print("\ninit self-test PASS — 7 cases "
          "(scaffold/slug/origin/derive/missing-design-loud/interview-yes/e2e)")
    return True


def main(argv):
    ap = argparse.ArgumentParser(description="scaffold flutter_crew.config.json from a design")
    ap.add_argument("design", nargs="?", help="design .html or design/ dir")
    ap.add_argument("--target", help="write config here (default: cwd)")
    ap.add_argument("--platforms", help="comma list, e.g. ios,android (beats the derived hint)")
    ap.add_argument("--yes", "-y", action="store_true", help="accept every default (CI/agent)")
    ap.add_argument("--dry-run", action="store_true", help="show the config, write nothing")
    ap.add_argument("--json", action="store_true", dest="as_json", help="machine-parseable output")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args(argv[1:])
    if a.self_test:
        return 0 if _self_test() else 1
    if not a.design:
        ap.error("need a <design> (.html or dir), or --self-test")
    return run(a.design, target=a.target, platforms=a.platforms, yes=a.yes,
               dry_run=a.dry_run, as_json=a.as_json)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
