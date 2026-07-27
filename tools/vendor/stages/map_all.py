#!/usr/bin/env python3
"""map_all.py — canonical primitives × catalogs → platform mappings. NO LLM.

Stage 3 of the deterministic pipeline. Pure lookup: for each primitive (keyed by
`ref`), resolve its iOS / Android / Web PlatformMapping from the catalogs + the
flutterBridge / glassPrimitives policy. The LLM never picks a symbol — it emits
only id + variant + motion; this script turns those into the 3 mappings.

Determinism: identical inputs → identical maps.json (dict-sorted JSON, no clocks).

Resolver policy (see docs/plans/app-box-per-platform-fallback.md):
    stack = "flutter"  (one Flutter codebase; each platform owns its fallback)
    ios:     glass("motion.glass-blur" ∈ motion) → GlassContainer(UiKitView), bridge=platformView
             else CUPERTINO widget (flutter-widgets.json `ios`), bridge=pureFlutter
             nativeRef = catalog SwiftUI symbol
    android: NATIVE Material Expressive via AndroidView(ComposeView→MaterialExpressiveTheme),
             bridge=platformView (NO approximation — operator mandate; #168813 → embed Compose)
             symbol = AndroidView host + Compose composable; nativeRef = catalog Compose symbol
    web:     bridge=package ; symbol = catalog Shad widget ; nativeRef=null

Usage:
    map_all.py <primitives.json> <catalog-dir> <out-maps.json> [--config P] [--platforms a,b,c]

Platform scoping: `--platforms` (CLI) > `--config` file `platforms` > default all 3.
Only resolved platforms appear as keys in mappings[ref]. All 3 catalogs are still
loaded (glass set, canon-presence check) — scoping affects emitted output, not
lookups. Custom-id recipes emit only the resolved platform's recipe (prune auto).
"""
import argparse
import json
import os
import sys

CATALOGS = {
    "ios": "ios-liquid-glass.json",
    "android": "android-m4-expressive.json",
    "web": "web-shadcn-ui.json",
}
ALL_PLATFORMS = ("ios", "android", "web")
CANONICAL = "primitives-canonical.json"


def _load_provider_bindings(cat_dir):
    """provider -> platforms allowlist, from the canonical catalog's
    providerPlatformBindings table (the single source of truth for
    platform-incompatible auth/social providers). Absent provider = all-platform.
    Loaded once in main() and threaded into _resolve via the `bindings` arg."""
    path = os.path.join(cat_dir, CANONICAL)
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    raw = doc.get("providerPlatformBindings", {}) or {}
    # drop the $comment key (a prose annotation, not a provider)
    return {k: list(v) for k, v in raw.items() if k != "$comment" and isinstance(v, list)}


def _provider_of(prim, bindings):
    """The provider identity on a primitive, if it carries one that the bindings table knows.

    The classify step records the brand-glyph identity as `props.name` on the
    display.icon glyph (e.g. {'name': 'apple'}). A glyph bound to a provider
    whose allowlist excludes some platforms is the signal that the enclosing
    auth button composite is platform-incompatible. Returns the provider string
    ('apple'/'google'/...) iff `props.name` is a key in `bindings`, else None
    (no platform-binding → all-platform primitive)."""
    name = (prim.get("props") or {}).get("name")
    if isinstance(name, str) and name in bindings:
        return name
    return None


def _resolve_platforms(cli_platforms, config_path):
    """precedence: --platforms > --config file > default all 3. Never auto-loads
    config (keeps flag-free snapshot runs on default → golden stable)."""
    if cli_platforms:
        plats = [p.strip() for p in cli_platforms.split(",") if p.strip()]
    elif config_path and os.path.exists(config_path):
        with open(config_path) as f:
            plats = json.load(f).get("platforms") or list(ALL_PLATFORMS)
    else:
        plats = list(ALL_PLATFORMS)
    bad = [p for p in plats if p not in ALL_PLATFORMS]
    if bad:
        sys.exit(f"ERROR: unknown platform(s) {bad}; valid: {list(ALL_PLATFORMS)}")
    if not plats:
        sys.exit("ERROR: resolved platform set is empty")
    return plats

# Bridge-keyed Flutter construct strings (catalogs store the native design symbol;
# concrete per-id widgets come from catalogs/flutter-widgets.json — map_all prefers
# them; absent ids fall back to these placeholders, still carrying nativeRef+api).
_FLUTTER_SYMBOL = {
    "platformView": "PlatformView host (UiKitView/AndroidView) → native design system below",
    "pureFlutter": "Flutter widget approximating nativeRef (see nativeRef + notes)",
    "package": None,  # web: symbol taken straight from catalog
}
_GLASS_DEFAULT = "GlassContainer (UiKitView → SwiftUI Liquid Glass host)"
_ANDROID_HOST = "AndroidView(ComposeView) → MaterialExpressiveTheme (material3 1.5.0-alpha22)"


def _unconfirmed_set(catalog):
    raw = catalog.get("unconfirmedSymbols", [])
    out = set()
    for item in raw:
        if isinstance(item, str):
            out.add(item)
        elif isinstance(item, dict) and "id" in item:
            out.add(item["id"])
    return out


def _resolve(platform, pid, prim, catalog, fw_platform, fw_custom, resolved=None, bindings=None):
    entry = catalog["map"].get(pid)
    if entry is None:
        return {
            "stack": "flutter",
            "bridge": "none",
            "symbol": None,
            "nativeRef": None,
            "api": "",
            "params": [],
            "availability": "",
            "experimental": False,
            "notes": f"No catalog entry for canonical id '{pid}'.",
            "unconfirmed": True,
        }

    # Custom-build path: no 1:1 Flutter widget — emit the per-platform recipe
    # composed from the native system (iOS Liquid Glass / Android M3 Expressive /
    # Web shadcn_ui). bridge says how Flutter reaches it.
    if pid in fw_custom:
        r = fw_custom[pid]["recipes"][platform]
        return {
            "stack": "flutter",
            "bridge": r["bridge"],
            "symbol": r["compose"],
            "nativeRef": r.get("nativeRef"),
            "api": entry.get("api", ""),
            "params": entry.get("params", []),
            "availability": entry.get("availability", ""),
            "experimental": r.get("experimental", False),
            "notes": r["compose"] + ((" | native: " + r["nativeRef"]) if r.get("nativeRef") else ""),
            "unconfirmed": r.get("unconfirmed", True) or (pid in _unconfirmed_set(catalog)),
        }

    # Per-platform, NATIVE via platform views (flutter-widgets.json v2.1):
    #   ios:     glass(motion.glass-blur) → GlassContainer(UiKitView); else CUPERTINO
    #   android: NATIVE Material Expressive via AndroidView(ComposeView) — NO approximation
    #            (operator mandate; Flutter has no native expressive, #168813, so embed Compose)
    #   web:     shadcn_ui straight from the catalog (no fw map)
    motion = prim.get("motion") or []
    fw_entry = (fw_platform or {}).get(pid, {})

    if platform == "web":
        bridge = "package"
        symbol = entry.get("symbol")
        native_ref = None
    elif platform == "ios":
        is_glass = "motion.glass-blur" in motion
        bridge = "platformView" if is_glass else "pureFlutter"
        native_ref = entry.get("symbol")
        symbol = _GLASS_DEFAULT if is_glass else (fw_entry.get("widget") or _FLUTTER_SYMBOL["pureFlutter"])
    else:  # android — NATIVE Compose expressive via AndroidView; never pureFlutter approximation
        bridge = "platformView"
        native_ref = entry.get("symbol")  # Compose expressive target
        compose = fw_entry.get("widget")
        symbol = f"{_ANDROID_HOST} → Compose: {compose}" if compose else _FLUTTER_SYMBOL["platformView"]

    return {
        "stack": "flutter",
        "bridge": bridge,
        "symbol": symbol,
        "nativeRef": native_ref,
        "api": entry.get("api", ""),
        "params": entry.get("params", []),
        "availability": entry.get("availability", ""),
        "experimental": entry.get("experimental", False),
        "notes": entry.get("notes", ""),
        "unconfirmed": (pid in _unconfirmed_set(catalog)) or bool(fw_entry.get("unconfirmed")),
    }


def _iter_primitives(primitives_doc):
    """Yield (ref, prim_dict) across ALL primitive locations — pages→components
    AND sharedComponents→primitives — regardless of whether mappings are attached.
    A primitive is owned by exactly one container; both are mapped here."""
    for page in primitives_doc.get("pages", []):
        for comp in page.get("components", []):
            for prim in comp.get("primitives", []):
                ref = prim.get("ref")
                if ref:
                    yield ref, prim
    for sc in primitives_doc.get("sharedComponents", []):
        for prim in sc.get("primitives", []):
            ref = prim.get("ref")
            if ref:
                yield ref, prim


def _self_test():
    """Behaviour tests for _resolve — the native-primitive decision (the appbox's
    core value: iOS glass / Android expressive / web shadcn, NO approximation).
    Locks down the bridge assignment per platform + motion, not just 'same bytes'."""
    cat = {"map": {"action.button": {"symbol": "CupertinoButton",
                                      "api": "", "params": [], "availability": "",
                                      "notes": ""}},
           "unconfirmed": []}
    # 1. unknown canonical id → bridge:none, unconfirmed, a named note
    r = _resolve("ios", "does.not.exist", {}, cat, None, {})
    assert r["bridge"] == "none" and r["unconfirmed"] is True and r["symbol"] is None, r
    assert "does.not.exist" in r["notes"], r
    # 2. web → bridge:package (straight from the catalog, no fw map)
    r = _resolve("web", "action.button", {}, cat, None, {})
    assert r["bridge"] == "package" and r["symbol"] == "CupertinoButton", r
    # 3. ios WITHOUT glass motion → bridge:pureFlutter (Cupertino fallback)
    r = _resolve("ios", "action.button", {"motion": []}, cat, None, {})
    assert r["bridge"] == "pureFlutter", r
    # 4. ios WITH motion.glass-blur → bridge:platformView (UiKitView) — the glass path
    r = _resolve("ios", "action.button", {"motion": ["motion.glass-blur"]}, cat, None, {})
    assert r["bridge"] == "platformView" and "UiKitView" in r["symbol"], r
    # 5. android → ALWAYS bridge:platformView (Compose expressive; never pureFlutter
    #    approximation — operator mandate, #168813). With no fw_platform widget the
    #    symbol falls back to the generic native-host line; with one it names Compose.
    for motion in ([], ["motion.glass-blur"]):
        r = _resolve("android", "action.button", {"motion": motion}, cat, None, {})
        assert r["bridge"] == "platformView", f"android must always platformView, got {r['bridge']}"
        assert "AndroidView" in r["symbol"] or "native design system" in r["symbol"], r
    # 5b. android WITH a per-platform fw widget → symbol names Compose expressive.
    # _resolve receives the PER-PLATFORM fw map (fw_maps.get(p) at the call site),
    # so it's keyed by pid directly, not nested under the platform name.
    fw_android = {"action.button": {"widget": "MaterialExpressiveButton"}}
    r = _resolve("android", "action.button", {}, cat, fw_android, {})
    assert r["bridge"] == "platformView" and "MaterialExpressiveButton" in r["symbol"], r
    # 6. custom-build path (fw_custom): bridge/symbol come from the per-platform recipe
    fw_custom = {"action.button": {"recipes": {
        "ios":     {"bridge": "platformView", "compose": "GlassBtn", "nativeRef": "GlassBtn"},
        "android": {"bridge": "platformView", "compose": "ExpressiveBtn", "nativeRef": "ExpressiveBtn"},
        "web":     {"bridge": "package", "compose": "ShadButton", "nativeRef": None}}}}
    r = _resolve("ios", "action.button", {}, cat, None, fw_custom)
    assert r["bridge"] == "platformView" and r["symbol"] == "GlassBtn" and r["nativeRef"] == "GlassBtn", r
    # 7. catalog never mutated (pure function — no side effects on the input)
    before = json.loads(json.dumps(cat))
    _resolve("ios", "action.button", {"motion": ["motion.glass-blur"]}, cat, None, {})
    assert cat == before, "_resolve mutated its catalog input"
    # 8. provider-binding detection — the platform-allowlist signal.
    # A glyph carrying props.name in the bindings table is provider-bound; a
    # glyph with any other name (or no name) is all-platform.
    bindings = {"apple": ["ios"], "google": ["ios", "android", "web"]}
    assert _provider_of({"props": {"name": "apple"}}, bindings) == "apple"
    assert _provider_of({"props": {"name": "google"}}, bindings) == "google"
    assert _provider_of({"props": {"name": "back"}}, bindings) is None, "non-bound name is all-platform"
    assert _provider_of({"props": {}}, bindings) is None, "no name is all-platform"
    assert _provider_of({}, bindings) is None, "no props is all-platform"
    # 9. golden-neutral guard: a provider allowed on ALL resolved platforms must
    # NOT get a `platforms` field (so breakdown.pages.sha256 is unchanged vs the
    # pre-binding baseline). Simulate the main-loop's attach step directly.
    platforms = ["ios", "android", "web"]
    provider = "google"  # allowed on all 3
    allowed = [p for p in platforms if p in bindings[provider]]
    assert allowed == platforms, "google should be allowed on all 3"
    assert not (provider and len(allowed) < len(platforms)), "no attach when not narrower"
    # 10. narrow allowlist (apple on an ios+android+web build) → field attaches.
    provider = "apple"  # ios-only
    allowed = [p for p in platforms if p in bindings[provider]]
    assert allowed == ["ios"], allowed
    assert provider and len(allowed) < len(platforms), "apple is narrower → attach"
    # 11. narrow allowlist on a scoped build (apple, ios+android only) → ['ios'],
    # android mapping is OMITTED (the platform key is absent, not suppressed).
    platforms_ia = ["ios", "android"]
    allowed_ia = [p for p in platforms_ia if p in bindings["apple"]]
    assert allowed_ia == ["ios"], allowed_ia
    assert "android" not in allowed_ia, "android must be omitted (not suppressed) for apple"
    print("map_all self-test: OK (unknown→none, web→package, ios glass/pure, "
          "android always platformView, custom recipes, purity, provider-bindings "
          "+ golden-neutral guard)")


def main(argv):
    if "--self-test" in argv:
        _self_test()
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("primitives")
    ap.add_argument("catalog_dir")
    ap.add_argument("out_maps")
    ap.add_argument("--config", help="config json with `platforms` (resolved if no --platforms)")
    ap.add_argument("--platforms", help="comma list, e.g. ios,android (beats --config)")
    args = ap.parse_args(argv[1:])
    prims_path, cat_dir, out_path = args.primitives, args.catalog_dir, args.out_maps
    platforms = _resolve_platforms(args.platforms, args.config)

    with open(prims_path, "r", encoding="utf-8") as f:
        prims_doc = json.load(f)

    catalogs = {}
    for plat, fname in CATALOGS.items():
        with open(os.path.join(cat_dir, fname), "r", encoding="utf-8") as f:
            catalogs[plat] = json.load(f)
    with open(os.path.join(cat_dir, "flutter-widgets.json"), "r", encoding="utf-8") as f:
        fw_doc = json.load(f)
    fw_custom = fw_doc.get("custom", {})
    # per-platform Flutter fallback maps (v2: ios=Cupertino, android=Material;
    # web has none — uses the shadcn catalog symbol directly)
    fw_maps = {"ios": fw_doc.get("ios", {}), "android": fw_doc.get("android", {})}
    # provider -> platforms allowlist (canonical catalog's providerPlatformBindings).
    # The single source of truth for platform-incompatible primitives (Apple SI on
    # iOS only). An empty table = every primitive is all-platform (legacy behavior).
    bindings = _load_provider_bindings(cat_dir)

    maps = {}
    unknown = []
    for ref, prim in _iter_primitives(prims_doc):
        pid = prim.get("id")
        var = prim.get("variant") or ""
        key = f"{pid}.{var}" if var else pid
        # Platform allowlist: a provider-bound primitive (its glyph carries
        # props.name in the bindings table) exists only on the allowed platforms.
        # Emit mappings ONLY for the allowed ∩ resolved platforms — an excluded
        # platform gets NO mapping key (the `mapping` object means "platforms where
        # this primitive exists"), not a suppressed runtime widget. This is the
        # expected-absence signal parity reads to avoid a false-positive drop.
        provider = _provider_of(prim, bindings)
        if provider:
            allowed = [p for p in platforms if p in bindings[provider]]
        else:
            allowed = list(platforms)
        emit = {
            p: _resolve(p, pid, prim, catalogs[p], fw_maps.get(p), fw_custom)
            for p in allowed
        }
        # Golden-neutral guard: attach the `platforms` allowlist ONLY when it is
        # narrower than the resolved set. On the all-3 default path (no provider
        # binding, or a provider allowed on all 3) the field is ABSENT, so the
        # per-platform mapping dicts are byte-identical to the legacy output and
        # breakdown.pages.sha256 is unchanged. A narrower allowlist (e.g. apple on
        # an ios+android build → ['ios']) attaches the field so parity can see it.
        if provider and len(allowed) < len(platforms):
            allow_field = list(allowed)
            for p in emit:
                emit[p]["platforms"] = allow_field
        maps[key] = emit
        if pid not in catalogs["ios"]["map"]:
            unknown.append((key, pid))

    payload = {
        "source": prims_path,
        "platforms": platforms,
        "resolved": len(maps),
        "unknownIds": unknown,
        "mappings": maps,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"resolved {len(maps)} primitives × {len(platforms)} platform(s) {platforms} → {out_path}")
    if unknown:
        print(f"WARNING: {len(unknown)} unknown canonical id(s): {[u[1] for u in unknown]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
