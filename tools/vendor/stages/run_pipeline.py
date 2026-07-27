#!/usr/bin/env python3
"""run_pipeline.py — deterministic flutter_crew pipeline driver.

Pipeline:
    parse_html  (code)  html → nodes.json
    classify    (1 LLM) nodes.json + canonical → primitives.json
    map_all     (code)  primitives.json × catalogs → maps.json
    synthesize  (code)  join + validate + render

The ONLY LLM step is `classify` (analyze+extract merged). The other three are
pure functions → deterministic, bit-reproducible given the same inputs.

This driver runs the three code stages and shells out the classify stage.
Two modes:
  --primitives PATH   use a frozen primitives.json (skip the LLM) — for snapshot
                      testing and reproducible runs.
  (default)           print the exact classify subagent dispatch contract; the
                      orchestrator skill runs it as one Agent call, then this
                      script is re-invoked with --primitives to finish.

Usage:
    run_pipeline.py <design.html> <out-dir> [--primitives PATH] [--generated ISO8601]
"""
import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CAT_DIR = os.path.join(ROOT, "catalogs")
SCHEMA = os.path.join(ROOT, "schemas", "primitives.schema.json")
# .bak ships at 0.997; the non-reproducible run1/run2 drift to 0.58/0.42 — 0.95 passes the
# known-good freeze and rejects a silently-truncated classify with margin on both sides.
COVERAGE_FLOOR = 0.95
PY = sys.executable


def _run(script, *args):
    print(f"\n[stage] {os.path.basename(script)} {' '.join(str(a) for a in args)}")
    r = subprocess.run([PY, os.path.join(HERE, script), *map(str, args)])
    if r.returncode != 0:
        sys.exit(r.returncode)


def _covered_refs(prims):
    """Union of every ref a frozen primitives.json accounts for — primitive.ref,
    {page,component,shared}.sourceRef, screenFlow.sourceRef, and skipped.ref at every
    level. Mirrors the nesting the extract skill emits; the gate compares it to nodes.json."""
    cov = set()
    def skips(o):
        for s in o.get("skipped", []) or []:
            if s.get("ref"):
                cov.add(s["ref"])
    skips(prims)  # top-level: nodes belonging to no single page
    for pg in prims.get("pages", []) or []:
        if pg.get("sourceRef"):
            cov.add(pg["sourceRef"])
        skips(pg)
        for c in pg.get("components", []) or []:
            if c.get("sourceRef"):
                cov.add(c["sourceRef"])
            skips(c)
            for pr in c.get("primitives", []) or []:
                if pr.get("ref"):
                    cov.add(pr["ref"])
    for sc in prims.get("sharedComponents", []) or []:
        if sc.get("sourceRef"):
            cov.add(sc["sourceRef"])
        skips(sc)
        for pr in sc.get("primitives", []) or []:
            if pr.get("ref"):
                cov.add(pr["ref"])
    for sf in prims.get("screenFlow", []) or []:
        if sf.get("sourceRef"):
            cov.add(sf["sourceRef"])
    return cov


def _counts(prims):
    """(primitiveCount, skippedCount) for the best-of-N tiebreak: coverage counts skipped
    as covered, so a mass-skip run scores 1.0 — rank schema-valid candidates by MORE
    primitives / FEWER skipped. Walks the same nesting as _covered_refs."""
    prim = skip = 0
    skip += len(prims.get("skipped", []) or [])
    for pg in prims.get("pages", []) or []:
        skip += len(pg.get("skipped", []) or [])
        for c in pg.get("components", []) or []:
            skip += len(c.get("skipped", []) or [])
            prim += len(c.get("primitives", []) or [])
    for sc in prims.get("sharedComponents", []) or []:
        skip += len(sc.get("skipped", []) or [])
        prim += len(sc.get("primitives", []) or [])
    return prim, skip


def _each_primitive(prims):
    """Yield every primitive dict (page components + shared) — one walk, reused below."""
    for pg in prims.get("pages", []) or []:
        for c in pg.get("components", []) or []:
            yield from c.get("primitives", []) or []
    for sc in prims.get("sharedComponents", []) or []:
        yield from sc.get("primitives", []) or []


def _coherence(prims):
    """Structural self-consistency signals for best-of-N ranking (NOT a gate — a legit
    unusual design must not fail-fast). pageScreenSkew = |page ids △ full-screen ids|: the
    schema's drawn-screen↔page bijection means a coherent run has skew 0; a shattered
    hierarchy (sub-sections promoted to pages) skews high. This replaces the GAMEABLE
    primitiveCount as the primary tiebreak — you cannot inflate skew without contradicting
    your own screenFlow. distinctIds = primitive-vocabulary breadth (context, not a verdict)."""
    pages = prims.get("pages", []) or []
    flow = prims.get("screenFlow", []) or []
    page_ids = {p.get("id") for p in pages if p.get("id")}
    full_ids = {s.get("id") for s in flow if s.get("status") == "full" and s.get("id")}
    return {
        "pages": len(pages),
        "screensFull": sum(1 for s in flow if s.get("status") == "full"),
        "pageScreenSkew": len(page_ids ^ full_ids),
        "distinctIds": len({p.get("id") for p in _each_primitive(prims)}),
    }


_SURFACE_PROPS = ("background", "border", "box-shadow", "backdrop-filter", "border-radius")


def _surface_classes(css_text):
    """Class names appearing in any CSS rule that declares a surface property.
    ponytail: regex, no cascade/specificity — a class in a compound selector still earns
    surface credit (biases toward NOT crying over-promotion). Upgrade to a real CSS parser
    only if false credits appear."""
    import re
    out = set()
    for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", css_text):
        if any(p in body.lower() for p in _SURFACE_PROPS):
            out.update(re.findall(r"\.([\w-]+)", sel))
    return out


def _surface_coherence(prims, nodes, css_text):
    """SECONDARY over-promotion signal: fraction of surface.* primitives whose node carries
    surface CSS (bg/border/radius/shadow — inline or via class). LOW ⇒ bare wrappers promoted
    to surfaces to pad the count. overPromotedRefs names offenders (refine feedback).
    ponytail CEILING — biased LOW (false over-promotion) on two inputs it can't resolve:
    (a) surface nodes with NO class (styled via tag/compound/parent selector), and
    (b) JSX dynamic classNames. Class tokens are regex-pulled (recovers `workout-card` from
    a `{`...${}`}` expression) to blunt (b); (a) needs parser-side class resolution — until
    then trust pageScreenSkew as the primary coherence signal, this as a tiebreak only."""
    import re
    sc = _surface_classes(css_text)
    surf = [p["ref"] for p in _each_primitive(prims) if str(p.get("id", "")).startswith("surface.")]
    over = []
    for r in surf:
        n = nodes.get(r, {})
        classes = set(re.findall(r"[A-Za-z][\w-]*", n.get("class") or ""))
        style = str((n.get("attrs") or {}).get("style", "")).lower()
        if not ((classes & sc) or any(p in style for p in _SURFACE_PROPS)):
            over.append(r)
    tot = len(surf)
    return {"surfaceTotal": tot,
            "surfaceCssValidity": (tot - len(over)) / tot if tot else 1.0,
            "overPromotedRefs": sorted(over)}


_CANON_IDS = None


def _canonical_ids():
    """Closed canonical id enum from the catalog (memoized). The oracle checks membership so a
    non-canonical id (e.g. `display.chart` for `data.chart`) is caught during self-refine —
    `primitives.schema` allows any id string, so ONLY map_all enforced the enum, as a late
    hard-fail. Same source of truth as map_all (the catalog), never a duplicated list."""
    global _CANON_IDS
    if _CANON_IDS is None:
        cat = json.load(open(os.path.join(CAT_DIR, "primitives-canonical.json"), encoding="utf-8"))
        _CANON_IDS = {p["id"] for p in cat.get("primitives", []) or []}
    return _CANON_IDS


def _score_primitives(prims_path, nodes_path):
    """Pure oracle (no exit, no side effects): the executable scorer best-of-N ranks
    candidates on and conditional-refine feeds back. Returns schema validity, the coverage
    fraction (the ranking key), droppedRefs + nonCanonicalIds (the named gaps to account
    for). The gate wraps this for the hard fail; the `score` CLI prints it for the agent."""
    prims = json.load(open(prims_path, encoding="utf-8"))
    schema_errors = None  # None = not checked (jsonschema absent — gate fails loud below)
    try:
        import jsonschema
        schema_errors = [f"{list(e.path)}: {e.message[:120]}" for e in sorted(
            jsonschema.Draft202012Validator(
                json.load(open(SCHEMA, encoding="utf-8"))).iter_errors(prims),
            key=lambda e: list(e.path))]
    except ImportError:
        # Schema validation is a contract gate (ADR-0009). A missing jsonschema
        # used to degrade silently to coverage-only — a false-pass machine (a
        # schema-invalid classify would pass). Fail loud instead: declare the dep
        # in requirements.txt and install it.
        print("[gate] FATAL: jsonschema not installed — cannot validate the primitives "
              "schema. Install deps:  python3 -m pip install -r requirements.txt",
              file=sys.stderr)
        sys.exit(3)
    all_refs = {n["ref"] for n in json.load(open(nodes_path, encoding="utf-8")).get("nodes", [])}
    dropped = sorted(all_refs - _covered_refs(prims))
    total = len(all_refs)
    hit = total - len(dropped)
    prim_n, skip_n = _counts(prims)
    canon = _canonical_ids()
    noncanon = sorted({p.get("id") for p in _each_primitive(prims)
                       if p.get("id") and p.get("id") not in canon})
    return {
        "schemaValid": (schema_errors == []) if schema_errors is not None else None,
        "schemaErrors": schema_errors or [],
        "nonCanonicalIds": noncanon,  # named gap: ids absent from the catalog enum → map_all hard-fails
        "coverage": hit / total if total else 1.0,
        "hit": hit, "total": total,
        "primitiveCount": prim_n, "skippedCount": skip_n,  # best-of-N tiebreak: more prim / fewer skip
        **_coherence(prims),  # pageScreenSkew (primary, non-gameable) + distinctIds
        "droppedRefs": dropped,
    }


def _gate_primitives(prims_path, nodes_path):
    """Fail-fast BEFORE the structure-only downstream gate: a frozen primitives.json must
    (1) satisfy the schema, (2) use only canonical ids, and (3) cover >=COVERAGE_FLOOR of
    parsed node refs. Catches a drifted/non-exhaustive classify that would otherwise ship as
    silently-missing widgets — guard/map_all/synthesize validate STRUCTURE, never COMPLETENESS.
    sys.exit(1) on failure."""
    s = _score_primitives(prims_path, nodes_path)
    if s["schemaErrors"]:
        print(f"[gate] primitives.json FAILS schema ({len(s['schemaErrors'])} errors):")
        for e in s["schemaErrors"][:8]:
            print(f"  - {e}")
        sys.exit(1)
    if s["nonCanonicalIds"]:
        print(f"[gate] primitives.json has {len(s['nonCanonicalIds'])} NON-CANONICAL id(s) — absent from "
              f"the catalog enum, so map_all WILL reject downstream: {s['nonCanonicalIds'][:8]}. "
              f"Re-map each to a catalog id (e.g. display.chart → data.chart) and re-freeze.")
        sys.exit(1)
    if s["schemaValid"] is None:
        # Unreachable in practice: _score_primitives now sys.exit(3) on ImportError
        # before returning a None schemaValid. Defensive: if a future caller scores
        # without gating, refuse to green a never-validated schema.
        print("[gate] FATAL: schema was never validated (jsonschema absent at score time). "
              "Install deps:  python3 -m pip install -r requirements.txt", file=sys.stderr)
        sys.exit(3)
    if s["coverage"] < COVERAGE_FLOOR:
        print(f"[gate] primitives.json NON-EXHAUSTIVE: covers {s['hit']}/{s['total']} parsed nodes "
              f"({s['coverage']:.1%} < {COVERAGE_FLOOR:.0%}). Classify dropped {len(s['droppedRefs'])} "
              f"nodes — they ship as missing widgets. Account for them in skipped[] and re-freeze.")
        sys.exit(1)
    print(f"[gate] primitives.json OK — schema valid, coverage {s['hit']}/{s['total']} ({s['coverage']:.1%})")


_SCRIPT_SRC = re.compile(r'<script\b[^>]*\bsrc="([^"]+\.jsx)"[^>]*>\s*</script>', re.I)
_LINK_CSS = re.compile(r'<link\b[^>]*\bhref="([^"]+\.css)"[^>]*/?>', re.I)


def _inline_design(design, work):
    """Flatten a sharded design into ONE self-contained file the single-file parser
    (and synthesize's token extraction) can fully see: inline sibling `<script src=*.jsx>`
    shards (every screen lives there) and `<link href=*.css>` (tokens live there).
    Fires only when the entry references sibling shards — plain single-file designs
    (e.g. the golden sample) pass through untouched. Deterministic: pure str ops, doc order.
    ponytail: regex inline, not a JS bundler — designs are flat sibling shards, not a module graph.
    """
    if os.path.isdir(design):
        htmls = sorted(f for f in os.listdir(design) if f.endswith(".html"))
        if not htmls:
            return design  # let the parser raise a clear error
        base = os.path.basename(os.path.normpath(design)).lower()
        design = os.path.join(design, next((h for h in htmls if h.lower().startswith(base)), htmls[0]))
    d = os.path.dirname(os.path.abspath(design))
    with open(design, encoding="utf-8") as f:
        src = f.read()

    def _sibling(name):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            return None
        with open(p, encoding="utf-8") as f:
            return f.read()

    def _sub(open_tag, close_tag):
        def repl(m):
            body = _sibling(m.group(1))
            return f"{open_tag}\n{body}\n{close_tag}" if body is not None else m.group(0)
        return repl

    out = _SCRIPT_SRC.sub(_sub('<script type="text/babel">', "</script>"), src)
    out = _LINK_CSS.sub(_sub("<style>", "</style>"), out)
    if out == src:
        return design  # no shards to inline
    bundle = os.path.join(work, "bundle.html")
    with open(bundle, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"[inline] flattened {os.path.basename(design)} + shards → {bundle}")
    return bundle


def _default_out(design):
    """Where the blueprint lands when no out-dir is given: a `.blueprint/<name>/`
    co-located WITH the design (inside its fixture), never the cwd. Never placed inside
    a design *directory* — its own *.html outputs would be re-parsed as input on a re-run,
    so anchor to the sibling. ponytail: one path rule; pass an explicit out-dir to override."""
    design = os.path.abspath(design)
    if os.path.isdir(design):
        anchor = os.path.dirname(design)                  # sibling of the design dir
        name = os.path.basename(os.path.normpath(design))
        if name.lower() in ("design", "designs", "src", "app", "ui"):
            name = os.path.basename(anchor) or name        # generic shard dir → name by the app
    else:
        anchor = os.path.dirname(design)                  # next to the .html file
        name = os.path.splitext(os.path.basename(design))[0]
    return os.path.join(anchor, ".blueprint", name)


CLASSIFY_CONTRACT = """\
CLASSIFY (analyze + extract, ONE LLM call) — dispatch as a single Agent:
  skill:   skills/extract/SKILL.md  (exhaustive discipline)
  input:   {nodes}
  catalog: catalogs/primitives-canonical.json  (closed id enum)
  schema:  schemas/primitives.schema.json  (Draft 2020-12 — validate output with jsonschema BEFORE returning; fix every violation)
  emit:    primitives.json with FOUR sections (decoupled):
    pages[]            drawn screens → components[] → primitives[] each {{ref,id,variant,props,motion}}
    screenFlow[]       EVERY screen (drawn OR stub): {{id,name,sourceRef,route?,guard?{{state,value}},status:"full"|"stub",note?}}
    sharedComponents[] reusable units (build once): {{id,name,sourceRef,kind:"widget"|"bottomSheet"|"dialog"|"overlay",uses:int,props?,usedBy?,primitives[],status,note?}}
    skipped[]          EXACTLY {{ref,reason}} — no note/extra keys (schema + downstream gate reject them). Top-level for nodes
                       belonging to no page (app-shell, router host, app-wide wrappers); per-page/per-component for in-scope
                       decorative nodes. NEVER inside a primitive.
  rules:
    — EXCLUSION FIRST: design-time tooling (tweak panels, EDITMODE controls, */tweak|inspector|devtools/*,
      setTweak*/tweakState) → skipped[] reason "design-tool"; NEVER a primitive or sharedComponent.
      OS chrome / device frame / annotations → skipped[] (os-chrome/device-frame/annotation).
    — SCREEN: PascalCase tag ending View/Screen/Page, OR under a router conditional ({{state === 'x' && }}).
      Drawn (def body present) → status "full" + a page; invocation-only → status "stub", no page.
    — SHARED: reusable unit (used ≥2 screens, or convention-named atom/overlay Button/Card/Toast/Sheet/Dialog)
      → sharedComponents; primitives live THERE once. Pages reference via component.uses[].
    — INVARIANT: a primitive is owned by exactly ONE container (page Component OR SharedComponent) — never duplicated.
    — refs MUST be the code-assigned selectors from {nodes} (do not invent anchors).
    — id MUST be a canonical id (enum); variant a canonical variant or null; motion[] from the closed enum
      {{motion.glass-blur, motion.spring-press, motion.morph, motion.rise-in, motion.parallax}}.
    — EXHAUSTIVENESS (checked, not aspirational): the union of every primitive.ref + screenFlow.sourceRef +
      sharedComponent.sourceRef + skipped.ref (all levels) MUST cover every parsed node ref in {nodes}. Report
      coverage = covered/total; if <100% you dropped nodes — the downstream gate validates STRUCTURE not COMPLETENESS,
      so omissions ship silently as missing widgets. Go back and account for them in skipped[].
    — SELF-VALIDATE: run jsonschema.Draft202012Validator(schema).validate(primitives) before returning; fix all errors.
  out:     {prims}
  return:  path + 1-line summary (pages, screens, shared, primitives, skipped counts) AND coverage fraction
  REPRODUCIBILITY (best-of-N — dispatcher orchestration):
    Classify is the one non-deterministic stage; runs disagree even at temp 0 (batch-variance,
    no seed on hosted Claude). Don't trust a single run: dispatch this Agent N≈4 times
    INDEPENDENTLY (no run sees another's output), then pick by the executable oracle —
      run_pipeline.py score <each candidate primitives.json> {nodes} <design>/styles.css
    ELIGIBLE = candidates whose `schemaErrors` AND `nonCanonicalIds` are empty AND `coverage` clears the
    floor (a non-canonical id is a downstream hard-fail — map_all rejects it — so it disqualifies, it does
    not merely rank low). Among the eligible, RANK (in order):
      1. `pageScreenSkew` ASC — |page ids △ full-screen ids|; the schema's drawn-screen↔page bijection
         means a coherent run is 0. High skew = a shattered hierarchy (39 pages for 7 screens). Non-gameable.
      2. `surfaceCssValidity` DESC — fraction of surface.* primitives on nodes with real surface CSS;
         low = wrappers over-promoted to surfaces (`overPromotedRefs` names them). CAVEAT: reliable only
         when classes resolve to the design's CSS — biased low on class-less or JSX-dynamic-className nodes,
         so use only to separate candidates already tied on skew, never to override it.
      3. `distinctIds` DESC — vocabulary completeness. THE decider for the common all-tied-at-skew-0 case:
         a run that collapses distinct primitives into a coarse bucket (icon-button→button, stat→text) WINS
         primitiveCount while LOSING distinctIds. Cross-candidate agreement on a count (two runs independently
         emit 21 icon-buttons) ≈ ground truth; a third run's 0 is a mislabel, not economy. Harder to game than
         count — ids are a closed enum, you cannot invent vocabulary.
      4. then `primitiveCount` DESC / `skippedCount` ASC — LAST, because primitiveCount is GAMEABLE
         (a run can split one widget into many primitives to win it). The winner becomes {prims}.
    Selection improves the artifact's QUALITY; cross-run IDENTITY comes from freezing the winner
    in .blueprint/ and replaying via --primitives. ONE coherent winner — never merge N structures.
Then re-run: run_pipeline.py {html} {out} --primitives {prims}
"""


def main(argv):
    if argv[1:2] == ["score"]:
        # best-of-N oracle: `run_pipeline.py score <primitives.json> <nodes.json> [styles.css]` → JSON.
        # Ranking keys: pageScreenSkew (coherence) → surfaceCssValidity (over-promotion, needs css) →
        # distinctIds (vocabulary, the skew-0 decider); extract's refine reads droppedRefs +
        # schemaErrors + nonCanonicalIds + overPromotedRefs.
        out = _score_primitives(argv[2], argv[3])
        if len(argv) > 4:  # optional design css → surface over-promotion signal
            nodes = {n["ref"]: n for n in json.load(open(argv[3], encoding="utf-8")).get("nodes", [])}
            prims = json.load(open(argv[2], encoding="utf-8"))
            out.update(_surface_coherence(prims, nodes, open(argv[4], encoding="utf-8").read()))
        print(json.dumps(out, indent=2))
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("design_html")
    ap.add_argument("out_dir", nargs="?", default=None,
                    help="output dir (default: a .blueprint/<name>/ co-located with the design, not the cwd)")
    ap.add_argument("--primitives", help="frozen primitives.json (skip LLM classify)")
    ap.add_argument("--tokens", help="Designer-authored tokens.json (overrides the CSS scrape; "
                                     "auto-detected beside the design if omitted)")
    ap.add_argument("--generated", default="2026-06-20T00:00:00Z")
    ap.add_argument("--config", default=os.path.join(ROOT, "flutter_crew.config.json"),
                    help="config json with `platforms` (default: shipped crew config)")
    ap.add_argument("--platforms", help="comma list, e.g. ios,android (beats --config)")
    args = ap.parse_args(argv[1:])

    work = args.out_dir or _default_out(args.design_html)
    if not args.out_dir:
        print(f"[out] no out-dir given → {work}")
    os.makedirs(work, exist_ok=True)
    design = _inline_design(args.design_html, work)
    # Format gate (ADR-0001/0012): reject a non-conformant design at PARSE with an
    # actionable message, before any stage consumes it. Makes the design-format
    # contract (schemas/design.schema.json) machine-enforced, not implicit. A design
    # dir is validated against its breakdown (if one exists beside the out-dir from a
    # prior freeze) — the assets.jsx-if-frontier + screen-shard-resolves checks need
    # the breakdown. A single .html design (no dir) skips the gate (no shards to check).
    if os.path.isdir(args.design_html):
        import validate_design as _vd
        bd = os.path.join(work, "breakdown.json")
        ok_v, _inst, verrs = _vd.validate(args.design_html,
                                          bd if os.path.exists(bd) else None)
        if not ok_v:
            print("[gate] design-format FAIL — fix before the pipeline runs:", file=sys.stderr)
            for e in verrs:
                print(f"  ✗ {e['check']}: {e['message']}", file=sys.stderr)
            sys.exit(1)
        notes = [n for n in [_inst.get("data", {}).get("dataModelNote")] if n]
        for n in notes:
            print(f"[gate] design-format note: {n}")
    nodes = os.path.join(work, "nodes.json")
    prims = args.primitives or os.path.join(work, "primitives.json")
    maps = os.path.join(work, "maps.json")

    # platform scope flags forwarded to map_all + synthesize (children resolve;
    # precedence: --platforms > --config > default all-3)
    scope = []
    if args.platforms:
        scope += ["--platforms", args.platforms]
    elif args.config and os.path.exists(args.config):
        scope += ["--config", args.config]

    # sniff JSX vs HTML — JSX designs (component tags, className, =>) need parse_jsx
    with open(design, encoding="utf-8") as f:
        _head = f.read()
    is_jsx = any(m in _head for m in ("className=", "=>", "import ", "export default", "{/*"))
    parser = "parse_jsx.py" if is_jsx else "parse_html.py"
    print(f"[sniff] parser={parser}")
    _run(parser, os.path.abspath(design), nodes)

    if args.primitives:
        _gate_primitives(prims, nodes)  # schema + exhaustiveness before the structure-only gate
        guarded = os.path.join(work, "primitives.guarded.json")
        excl = os.path.join(work, "exclusions.json")
        _run("guard.py", nodes, prims, os.path.join(CAT_DIR, "exclusions.json"), guarded, excl)
        _run("map_all.py", guarded, CAT_DIR, maps, *scope)
        synth_args = [guarded, maps, os.path.abspath(design), CAT_DIR,
                      work, "--exclusions", excl, "--generated", args.generated, *scope]
        _run("synthesize.py", *synth_args)
        # token layer (deterministic). PRECEDENCE (ADR-0011 #4 — the token seam):
        #   1. --tokens PATH (explicit operator override — mirrors --primitives)
        #   2. a Designer-authored tokens.json committed BESIDE the design (sibling of
        #      the design dir; the Designer's Tier-1 output layout). This carries the
        #      platform $extensions the CSS scrape cannot produce, so it is AUTHORITATIVE.
        #   3. else: scrape the design's CSS via extract_tokens (the legacy path — same
        #      design bytes ⇒ same tokens.json; ADR-0002 reproducibility holds).
        # A Designer tokens.json wins over the scrape because it carries Liquid Glass tint /
        # M3 Expressive scheme / shadcn oklch $extensions the lossy scrape drops.
        tokens_out = os.path.join(work, "tokens.json")
        authored = None
        if args.tokens:
            authored = args.tokens if os.path.exists(args.tokens) else None
            if not authored:
                print(f"[gate] --tokens {args.tokens} not found — falling back to scrape")
        else:
            # resolve the design dir from the ORIGINAL entry (not the inlined bundle):
            entry = os.path.abspath(args.design_html)
            ddir = entry if os.path.isdir(entry) else os.path.dirname(entry)
            for cand in (os.path.join(ddir, "tokens.json"),
                         os.path.join(os.path.dirname(ddir), "tokens.json")):
                if os.path.exists(cand):
                    authored = cand
                    break
        if authored:
            import shutil as _sh
            _sh.copyfile(authored, tokens_out)
            print(f"[tokens] used Designer-authored {os.path.basename(authored)} "
                  f"(authoritative — carries platform $extensions)")
        else:
            _run("extract_tokens.py", os.path.abspath(design), tokens_out)
        # blueprint orientation doc — part of the flow: regenerated every run,
        # emitted by the same named view /flutter-crew:viz blueprint hosts.
        _run("viz.py", work, "--view", "blueprint", "--report")
        print(f"\nDONE (deterministic, no LLM) → {work}")
    else:
        print(CLASSIFY_CONTRACT.format(
            nodes=nodes, prims=prims, html=args.design_html, out=work))
        print("Re-run with --primitives <path> after the classify agent writes primitives.json.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
