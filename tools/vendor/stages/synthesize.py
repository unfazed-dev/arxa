#!/usr/bin/env python3
"""synthesize.py — join primitives + maps → breakdown.json/mock.html. NO LLM.

Stage 4 of the deterministic pipeline. Pure functions:
  1. attach mapping{ios,android,web} to each primitive by `ref` (join with maps.json)
  2. extract design tokens from the HTML (regex on <style> + inline styles)
  3. validate the merged object against schemas/breakdown.schema.json
  4. render mock.html (neutral, completeness audit)
  5. count check: primitives in mock == primitives in breakdown

Determinism: identical inputs → identical breakdown.json and mock.html
(`generated` timestamp is passed in via --generated; snapshot hashes only
`pages`, which excludes it).

Usage:
    synthesize.py <primitives.json> <maps.json> <design.html> <catalog-dir> <out-dir>
                  [--generated ISO8601] [--config P] [--platforms a,b,c]

Platform scoping: `--platforms` > `--config` `platforms` > default all 3.
Resolved set drives mapping keys, meta.platforms, open-Q scan.
"""
import argparse
import json
import os
import re
import sys

CAT_FILES = {
    "ios": "ios-liquid-glass.json",
    "android": "android-m4-expressive.json",
    "web": "web-shadcn-ui.json",
}
ALL_PLATFORMS = ("ios", "android", "web")
CANON_FILE = "primitives-canonical.json"
SCHEMA_FILE = "schemas/breakdown.schema.json"


def _resolve_platforms(cli_platforms, config_path):
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


# ---------- token extraction ----------
def _extract_tokens(html):
    style_blob = []
    # <style> blocks
    for m in re.finditer(r"<style[^>]*>(.*?)</style>", html, re.S | re.I):
        style_blob.append(m.group(1))
    # inline style attrs
    for m in re.finditer(r'style="([^"]*)"', html, re.I):
        style_blob.append(m.group(1))
    css = "\n".join(style_blob)

    def grab(pat):
        # group-count-aware: 2-group → key/value dict; 1-group → deduped set of values
        # (radii/shadows are value-only patterns; a key would be fabricated).
        out = {}
        for m in re.finditer(pat, css, re.I):
            if m.lastindex is not None and m.lastindex >= 2:
                out.setdefault(m.group(1).strip(), m.group(2).strip())
            else:
                v = m.group(1).strip()
                out.setdefault(v, v)
        return out

    colors = {}
    for m in re.finditer(r"--([A-Za-z0-9_-]+)\s*:\s*([^;}]+)", css):
        val = m.group(2).strip()
        if val[:1] == "#" or val[:3] in ("rgb", "hsl"):
            colors[m.group(1)] = val
    radii = grab(r"border-radius\s*:\s*([^;}]+)")
    fonts = {}
    for m in re.finditer(r"font-(family|size|weight)\s*:\s*([^;}]+)", css):
        fonts[m.group(1)] = m.group(2).strip()
    shadows = grab(r"box-shadow\s*:\s*([^;}]+)")
    spacing = {}
    for m in re.finditer(r"(padding|margin|gap)\s*:\s*([^;}]+)", css):
        spacing[m.group(1)] = m.group(2).strip()
    return {
        "colors": colors,
        "radii": radii,
        "typography": fonts,
        "shadows": shadows,
        "spacing": spacing,
    }


# ---------- join ----------
_PRIM_KEYS = {"ref", "id", "variant", "props", "motion", "mapping", "sharedWith"}
# Page/Component are additionalProperties:false in the schema; classify may emit extra
# annotations (sourceRef, note). Strip to the allowed set — same intent as _PRIM_KEYS.
_PAGE_KEYS = {"id", "name", "route", "description", "components", "skipped"}
_COMP_KEYS = {"id", "name", "selector", "role", "primitives", "uses", "skipped"}


def _label_from_id(idval):
    """Derive a human label from a kebab/dotted id when classify omits `name`
    (pages/components require name; id is always present). 'workout-grid' → 'Workout Grid'."""
    if not idval:
        return "Untitled"
    seg = str(idval).split(".")[-1]
    return " ".join(w.capitalize() for w in re.split(r"[-_]+", seg) if w)


def _join(prims_doc, mappings, platforms):
    canonical_ids = set()

    def attach(container):
        """attach mapping{} to each primitive by (id,variant) + sanitize stray keys.
        Works for any primitive container (page Component OR SharedComponent)."""
        for prim in container.get("primitives", []):
            pid = prim.get("id")
            var = prim.get("variant") or ""
            key = f"{pid}.{var}" if var else pid
            mp = mappings.get(key)
            if mp is None:
                # join miss — fabricate a flagged mapping rather than dropping
                prim["mapping"] = {
                    p: {
                        "stack": "flutter", "bridge": "none", "symbol": None,
                        "nativeRef": None, "api": "", "params": [],
                        "availability": "", "experimental": False,
                        "notes": f"NO MAPPING for id '{key}'.", "unconfirmed": True,
                    } for p in platforms
                }
            else:
                prim["mapping"] = mp
            canonical_ids.add(prim.get("id"))
            # sanitize: drop stray keys classify may emit (e.g. a per-primitive
            # `skipped`); schema Primitive is additionalProperties:false
            for k in list(prim.keys()):
                if k not in _PRIM_KEYS:
                    del prim[k]

    pages = prims_doc.get("pages", [])
    for page in pages:
        page.setdefault("name", _label_from_id(page.get("id")))
        seen_cids = set()  # backfill component id from name when classify omits it (schema requires id)
        for comp in page.get("components", []):
            if not comp.get("id"):
                base = re.sub(r"[^a-z0-9]+", "", (comp.get("name") or "component").lower()) or "component"
                cid, n = base, 2
                while cid in seen_cids:  # two same-page names slugging equal → disambiguate
                    cid, n = f"{base}{n}", n + 1
                comp["id"] = cid
            seen_cids.add(comp["id"])
            comp.setdefault("name", _label_from_id(comp.get("id")))
            attach(comp)
            comp.setdefault("skipped", [])
            for k in [k for k in comp if k not in _COMP_KEYS]:
                del comp[k]
        for k in [k for k in page if k not in _PAGE_KEYS]:
            del page[k]
    shared = prims_doc.get("sharedComponents", [])
    for sc in shared:
        sc.setdefault("name", _label_from_id(sc.get("id")))
        # `uses` must be a positive int; LLMs sometimes emit a descriptive string
        # (e.g. "N (filtered.length)"). Coerce: leading digits, else 1 (conservative).
        u = sc.get("uses")
        if isinstance(u, bool) or not isinstance(u, int) or u < 1:
            if isinstance(u, str):
                m = re.search(r"\d+", u)
                sc["uses"] = int(m.group()) if m else 1
            else:
                sc["uses"] = 1
        attach(sc)
    return pages, shared, canonical_ids


# ---------- open questions ----------
def _open_questions(pages, shared, platforms):
    qs = []
    seen = set()

    def scan(owner_path, prims):
        for prim in prims:
            mp = prim.get("mapping", {})
            for plat in platforms:
                pm = mp.get(plat, {})
                if pm.get("unconfirmed"):
                    key = (owner_path, prim.get("ref"), plat)
                    if key in seen:
                        continue
                    seen.add(key)
                    qs.append(
                        f"{prim.get('ref')} @ {owner_path}: "
                        f"confirm {plat} symbol '{pm.get('symbol') or pm.get('nativeRef')}'"
                    )

    for page in pages:
        for comp in page.get("components", []):
            scan(f"{page.get('id')}/{comp.get('id')}", comp.get("primitives", []))
    for sc in shared:
        scan(f"shared/{sc.get('id')}", sc.get("primitives", []))
    return qs


# ---------- mock render ----------
def _mock_element(prim):
    # ponytail: one neutral chip per primitive. The mock is a completeness audit
    # (count + "nothing dropped"), not a styled preview. The prior 7-branch typing
    # keyed on id.split(".")[-1] and misclassified ~82% — canonical ids are
    # <category>.<name> (variants separate), and few names hit a keyword. Correct
    # typing would need a full 63-name map for no contractual value.
    variant = prim.get("variant")
    label = f"{prim.get('id')}" + (f".{variant}" if variant else "")
    return f'<div class="mc-box">{label}</div>'


def _render_mock(pages, shared):
    parts = [
        "<!doctype html><html><head><meta charset='utf-8'>",
        "<title>flutter_crew mock</title>",
        "<style>body{font:14px/1.4 system-ui;margin:24px}",
        ".page{margin-bottom:32px;border-top:2px solid #888;padding-top:8px}",
        ".comp{margin:12px 0;padding:8px;border:1px dashed #aaa;border-radius:6px}",
        ".prim{display:inline-block;margin:4px;padding:6px;background:#f4f4f5;border-radius:4px}",
        ".mc-box{padding:6px;background:#eee}",
        "</style></head><body>",
    ]
    count = 0
    for page in pages:
        parts.append(f'<section class="page"><h2>{page.get("name")}</h2>')
        for comp in page.get("components", []):
            parts.append(f'<div class="comp"><h3>{comp.get("name")}</h3>')
            for prim in comp.get("primitives", []):
                parts.append(f'<div class="prim">{_mock_element(prim)}</div>')
                count += 1
            parts.append("</div>")
        parts.append("</section>")
    if shared:
        parts.append('<section class="page"><h2>Shared components</h2>')
        for sc in shared:
            parts.append(f'<div class="comp"><h3>{sc.get("name")} ({sc.get("kind")})</h3>')
            for prim in sc.get("primitives", []):
                parts.append(f'<div class="prim">{_mock_element(prim)}</div>')
                count += 1
            parts.append("</div>")
        parts.append("</section>")
    parts.append("</body></html>")
    return "\n".join(parts), count


# ---------- primary nav (bottom tab bar) ----------
# The design's bottom-TabBar manifest. classify emits a `primaryNav` HINT in
# primitives.json when it sees a bottom tab bar whose setTab(id) drives top-level
# screen swaps — the ONE semantic step (design-tab-id → screenFlow-id, e.g.
# 'train'→'home') is the LLM's job, because it reads which screen each tab
# reveals. Everything else here is DETERMINISTIC: the design icon name → SF
# Symbol translation is a closed lookup table (a hallucinated sfSymbol breaks
# the iOS asset build), and the cart badge attaches to the shop tab. Returns
# the canonical {kind, tabs:[{id,label,sfSymbol,badgeField?}]} or None when the
# design declares no bottom nav (golden-stable: absent → no HomeShellView).
_ICON_TO_SFSYMBOL = {
    "bolt": "bolt.fill", "shop": "bag.fill", "heart": "heart.fill",
    "person": "person.fill", "bag": "bag.fill", "cart": "cart.fill",
    "home": "house.fill", "house": "house.fill", "gear": "gearshape.fill",
    "settings": "gearshape.fill", "search": "magnifyingglass.fill",
    "magnifyingglass": "magnifyingglass.fill", "user": "person.fill",
    "profile": "person.fill", "star": "star.fill", "bell": "bell.fill",
    "calendar": "calendar.fill", "clock": "clock.fill", "list": "list.bullet.fill",
    "menu": "line.3.horizontal.fill", "plus": "plus.circle.fill",
    "map": "map.fill", "location": "location.fill", "play": "play.fill",
}


def _resolve_primary_nav(prims_doc, screen_flow):
    """Lift the classify `primaryNav` hint into the canonical breakdown manifest.

    classify provides {kind, tabs:[{screen, label, icon}]} — raw design data with
    the screenFlow id already reconciled. This function applies the deterministic
    translation: icon → sfSymbol (closed table, fail-loud on unmapped), badgeField
    detection (shop/cart tab → 'cartCount'), and shape validation. Returns None
    when the hint is absent (no bottom nav) so the breakdown omits primaryNav
    entirely — golden-stable for no-tab designs.
    """
    hint = prims_doc.get("primaryNav")
    if not hint or not isinstance(hint, dict):
        return None
    raw_tabs = hint.get("tabs")
    if not isinstance(raw_tabs, list) or len(raw_tabs) < 2:
        return None  # a single "tab" is not a nav shell
    flow_ids = {s.get("id") for s in (screen_flow or []) if s.get("id")}
    tabs = []
    for t in raw_tabs:
        if not isinstance(t, dict):
            continue
        tab_id = t.get("screen") or t.get("id")
        label = t.get("label")
        icon = (t.get("icon") or "").strip().lower()
        if not tab_id or not label or not icon:
            continue  # incomplete tab descriptor — skip, do not guess
        if flow_ids and tab_id not in flow_ids:
            # the tab targets a screen the LLM did not reconcile to a screenFlow
            # id — skip it rather than emit a dangling route (generate_views
            # _TAB_TARGETS would point nowhere).
            continue
        sf = _ICON_TO_SFSYMBOL.get(icon)
        if not sf:
            print(f"primaryNav: unmapped design icon {icon!r} — tab {tab_id!r} "
                  f"dropped (extend _ICON_TO_SFSYMBOL to render it)", file=sys.stderr)
            continue
        tab = {"id": tab_id, "label": label, "sfSymbol": sf}
        # The cart badge lives on the shopping tab — the design wires cartCount
        # to the shop tab's badge span. Detected by id/icon, not hardcoded label
        # (label is designer copy, not a stable key).
        if tab_id in ("shop", "cart") or icon in ("shop", "bag", "cart"):
            tab["badgeField"] = "cartCount"
        tabs.append(tab)
    if len(tabs) < 2:
        return None  # too few tabs survived translation — no nav shell
    return {"kind": "surface.tabbar", "tabs": tabs}


# ---------- validation ----------
def _validate(breakdown, root):
    schema_path = os.path.join(root, SCHEMA_FILE)
    try:
        import jsonschema  # type: ignore
        with open(schema_path) as f:
            schema = json.load(f)
        jsonschema.Draft202012Validator(schema).validate(breakdown)
        return True, "jsonschema OK"
    except ImportError:
        # fallback: check required top fields
        for req in ("meta", "pages"):
            assert req in breakdown, f"missing top field {req}"
        return True, "fallback required-check OK (jsonschema not installed)"
    except Exception as e:  # jsonschema.ValidationError
        return False, str(e)


def _self_test():
    """Behaviour tests for _join — the primitives×mappings join that produces the
    breakdown. Locks down: join hit (mapping attached), join MISS (a flagged
    bridge:none mapping fabricated, NOT dropped), variant keying, stray-key
    sanitization, shared `uses` coercion. NOT just 'same bytes' — the RIGHT bytes."""
    plat = ["ios", "android"]
    # a primitives doc with one page, one component, two primitives (one plain, one variant)
    prims_doc = {"pages": [{"id": "home", "components": [{"id": "c1", "name": "Card", "primitives": [
        {"ref": "r1", "id": "action.button", "variant": ""},
        {"ref": "r2", "id": "action.button", "variant": "outline"},
        {"ref": "r3", "id": "surface.card", "variant": ""},
    ]}]}], "sharedComponents": [], "screenFlow": [], "skipped": []}
    # mappings: action.button (plain) + action.button.outline (variant). NO entry
    # for surface.card → join miss path.
    mappings = {
        "action.button": {"ios": {"bridge": "platformView"}, "android": {"bridge": "platformView"}},
        "action.button.outline": {"ios": {"bridge": "pureFlutter"}, "android": {"bridge": "platformView"}},
    }
    pages, shared, cids = _join(prims_doc, mappings, plat)
    prims = pages[0]["components"][0]["primitives"]
    # 1. join HIT: plain action.button gets its mapping
    assert prims[0]["mapping"]["ios"]["bridge"] == "platformView", prims[0]
    # 2. variant keying: action.button.outline resolved via "id.variant"
    assert prims[1]["mapping"]["ios"]["bridge"] == "pureFlutter", prims[1]
    # 3. join MISS: surface.card (no mapping) → fabricated bridge:none, unconfirmed,
    #    NOT dropped — the count stays 3 and the miss is flagged
    assert prims[2]["mapping"]["ios"]["bridge"] == "none", prims[2]
    assert prims[2]["mapping"]["ios"]["unconfirmed"] is True, prims[2]
    assert "surface.card" in prims[2]["mapping"]["ios"]["notes"], prims[2]
    assert len(prims) == 3, "a join miss must NOT drop the primitive"
    # 4. canonical ids collected across all primitives
    assert cids == {"action.button", "surface.card"}, cids
    # 5. stray-key sanitization: a classify-emitted stray key is stripped
    #    (schema Primitive is additionalProperties:false)
    dirty = {"pages": [{"id": "p", "components": [{"id": "c", "primitives": [
        {"ref": "r", "id": "action.button", "stray": "should be deleted"}]}]}],
        "sharedComponents": [], "screenFlow": [], "skipped": []}
    pages2, _, _ = _join(dirty, mappings, plat)
    p = pages2[0]["components"][0]["primitives"][0]
    assert "stray" not in p, f"stray key not sanitized: {list(p.keys())}"
    # 6. shared `uses` coercion: a descriptive string → leading digits, else 1
    sh = {"pages": [], "sharedComponents": [{"id": "s", "name": "Chip", "uses": "12 (filtered)"}],
          "screenFlow": [], "skipped": []}
    _, shared3, _ = _join(sh, mappings, plat)
    assert shared3[0]["uses"] == 12, shared3[0]
    sh["sharedComponents"][0]["uses"] = "none-numeric"
    _, shared4, _ = _join(sh, mappings, plat)
    assert shared4[0]["uses"] == 1, "non-numeric uses → conservative 1"
    # 7. primaryNav: classify hint lifted to canonical manifest with sfSymbol
    #    translation (closed table) + cart badge on the shop tab.
    flow = [{"id": "home"}, {"id": "shop"}, {"id": "support"}, {"id": "account"}]
    hint = {"kind": "surface.tabbar", "tabs": [
        {"screen": "home", "label": "Train", "icon": "bolt"},
        {"screen": "shop", "label": "Shop", "icon": "shop"},
        {"screen": "support", "label": "Support", "icon": "heart"},
        {"screen": "account", "label": "Account", "icon": "person"},
    ]}
    pn = _resolve_primary_nav({"primaryNav": hint}, flow)
    assert pn is not None and pn["kind"] == "surface.tabbar", pn
    assert [t["sfSymbol"] for t in pn["tabs"]] == [
        "bolt.fill", "bag.fill", "heart.fill", "person.fill"], pn
    assert pn["tabs"][1].get("badgeField") == "cartCount", "shop tab carries the cart badge"
    assert "badgeField" not in pn["tabs"][0], "non-shop tab must not carry a badge"
    # 8. primaryNav: absent hint → None (golden-stable for no-tab designs)
    assert _resolve_primary_nav({}, flow) is None, "no hint → no primaryNav"
    assert _resolve_primary_nav({"primaryNav": {"tabs": []}}, flow) is None, "<2 tabs → None"
    # 9. primaryNav: unmapped icon → tab dropped (fail-loud, never an invalid sfSymbol)
    bad = {"primaryNav": {"tabs": [
        {"screen": "home", "label": "Train", "icon": "bolt"},
        {"screen": "x", "label": "X", "icon": "nonexistent-glyph"}]}}
    pn_bad = _resolve_primary_nav(bad, flow)
    assert pn_bad is None, "fewer than 2 tabs survive → no nav shell (not a partial bar)"
    # 10. primaryNav: a tab whose screen is NOT in screenFlow is dropped (no dangling route)
    dangling = {"primaryNav": {"tabs": [
        {"screen": "home", "label": "Train", "icon": "bolt"},
        {"screen": "nonexistent", "label": "Ghost", "icon": "heart"}]}}
    pn_d = _resolve_primary_nav(dangling, flow)
    assert pn_d is None, "a tab targeting a nonexistent screen → dropped → no nav shell"
    print("synthesize self-test: OK (join hit/miss, variant keying, miss-not-dropped, "
          "stray sanitize, uses coerce, primaryNav lift/drop/badge)")


def main(argv):
    if "--self-test" in argv:
        _self_test()
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("primitives")
    ap.add_argument("maps")
    ap.add_argument("design_html")
    ap.add_argument("catalog_dir")
    ap.add_argument("out_dir")
    ap.add_argument("--generated", default="2026-06-20T00:00:00Z")
    ap.add_argument("--exclusions", help="exclusions.json from guard.py (optional)")
    ap.add_argument("--config", help="config json with `platforms`")
    ap.add_argument("--platforms", help="comma list, e.g. ios,android (beats --config)")
    args = ap.parse_args(argv[1:])
    platforms = _resolve_platforms(args.platforms, args.config)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    with open(args.primitives) as f:
        prims_doc = json.load(f)
    with open(args.maps) as f:
        maps_doc = json.load(f)
    with open(args.design_html, encoding="utf-8") as f:
        html = f.read()

    catalogs = {}
    for plat, fn in CAT_FILES.items():
        with open(os.path.join(args.catalog_dir, fn)) as f:
            catalogs[plat] = json.load(f)
    with open(os.path.join(args.catalog_dir, CANON_FILE)) as f:
        canon = json.load(f)

    pages, shared, canonical_ids = _join(prims_doc, maps_doc.get("mappings", {}), platforms)
    screen_flow = prims_doc.get("screenFlow", [])
    for s in screen_flow:  # guard.value must be a string; a null value = unconditional → drop guard
        g = s.get("guard")
        if isinstance(g, dict):
            v = g.get("value")
            if v is None:
                s.pop("guard", None)
            elif not isinstance(v, str):
                g["value"] = str(v).lower() if isinstance(v, bool) else str(v)

    # assert every primitive id is canonical
    canon_ids = {p["id"] for p in canon["primitives"]}
    hallucinated = sorted(canonical_ids - canon_ids)
    if hallucinated:
        print(f"ERROR: non-canonical ids: {hallucinated}", file=sys.stderr)
        return 3

    tokens = _extract_tokens(html)
    open_qs = _open_questions(pages, shared, platforms)
    primary_nav = _resolve_primary_nav(prims_doc, screen_flow)

    exclusions = []
    if args.exclusions and os.path.exists(args.exclusions):
        with open(args.exclusions) as f:
            ed = json.load(f)
        exclusions = ed.get("excluded", [])
        for e in exclusions:
            if e.get("severity") == "warn":
                open_qs.append(
                    f"{e.get('ref')}: excluded-artifact kept as warn ({e.get('kind')}): {e.get('reason')}")

    breakdown = {
        "meta": {
            "source": args.design_html,
            "crewVersion": "flutter_crew-deterministic",
            "platforms": platforms,
            "generated": args.generated,
            "canonicalVersion": canon.get("version", ""),
            "catalogVersions": {p: catalogs[p].get("version", "") for p in platforms},
        },
        "tokens": tokens,
        "pages": pages,
        "openQuestions": open_qs,
        "exclusions": exclusions,
        "screenFlow": screen_flow,
        "sharedComponents": shared,
        "skipped": prims_doc.get("skipped", []),
    }
    # primaryNav is emitted ONLY when the design declares a bottom tab bar —
    # omit when None so no-tab designs stay byte-identical (golden-neutral).
    if primary_nav is not None:
        breakdown["primaryNav"] = primary_nav

    ok, msg = _validate(breakdown, root)
    if not ok:
        print(f"SCHEMA INVALID: {msg}", file=sys.stderr)
        return 4
    print(f"schema: {msg}")

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "breakdown.json"), "w", encoding="utf-8") as f:
        json.dump(breakdown, f, ensure_ascii=False, indent=2, sort_keys=True)
    mock, mock_count = _render_mock(pages, shared)
    with open(os.path.join(args.out_dir, "mock.html"), "w", encoding="utf-8") as f:
        f.write(mock)

    prim_total = sum(len(c.get("primitives", [])) for p in pages for c in p.get("components", []))
    prim_total += sum(len(sc.get("primitives", [])) for sc in shared)
    if mock_count != prim_total:
        print(f"ERROR: mock={mock_count} breakdown={prim_total} (dropped primitive)", file=sys.stderr)
        return 5
    print(f"wrote breakdown.json/mock.html → {args.out_dir} "
          f"(platforms={platforms} pages={len(pages)} prims={prim_total} "
          f"openQs={len(open_qs)} excluded={len(exclusions)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
