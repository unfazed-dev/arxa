#!/usr/bin/env python3
"""Multi-route site capture (G3a). Drive the existing per-route capture pipeline
(web_skeleton -> web_tokens -> bundle_writer) across an EXPLICIT list of routes and
emit one firewall-gated bundle per route plus a content-free site.json manifest
(the merge contract for later rungs G3b/c/d). With --merge and/or --dedup, the
post-processors (site_merge -> design_system.json, site_chrome -> chrome_dedup.json)
run over the finished capture; each re-audits the whole tree through the unchanged
firewall, and any post-step leak/fault fails the run loudly.

This orchestrator captures NOTHING itself: every page-derived byte is produced by
the already-gated web_*/bundle_writer tools. site.json adds only positional ids,
input urls, netlocs, integer counts, booleans, and categorical error kinds. The
whole site tree is re-audited through the unchanged content_firewall.audit_bundle
before the run is declared clean. Failure paths NEVER echo subprocess stderr.

Host Bash (CDP):
    python3 scripts/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222
    python3 scripts/site_capture.py --urls-file routes.txt --out site_out --cdp-port 9222 --merge --dedup
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.robotparser
from pathlib import Path
from urllib.parse import urlparse

import content_firewall as cf
import _site
import _nav
from _common import die, emit_json

SCRIPTS = Path(__file__).resolve().parent

CRAWL_FLOOR = 20   # min content-region nodes for a discovered capture to be VALID (spec §3, pinned)


def _sweep_argv(args):
    """Sweep flags to forward to each per-route web_skeleton subprocess (empty when off)."""
    if not getattr(args, "sweep", False):
        return []
    return ["--sweep", "--sweep-steps", str(args.sweep_steps)]


def _transport_argv(args):
    """Reconstruct the transport flags to forward to each per-route subprocess.
    --url is supplied per route, so it is NOT forwarded here."""
    argv = []
    if args.cdp_port is not None:
        argv += ["--cdp-port", str(args.cdp_port)]
    if args.browser and args.browser != "auto":
        argv += ["--browser", args.browser]
    if args.android:
        argv += ["--android"]
    if args.ios:
        argv += ["--ios"]
    if args.serial:
        argv += ["--serial", args.serial]
    return argv


def _run(cmd):
    # capture_output keeps subprocess stdout/stderr OUT of our stdout and off disk.
    return subprocess.run(cmd, cwd=str(SCRIPTS), capture_output=True, text=True)


def _edges_from_skeleton(sk_nodes, route_map, src_id):
    """Resolve a route's raw (pre-redaction) skeleton anchors to content-free nav edges.
    Anchors are identified by HREF PRESENCE (only links carry an href; robust to how role
    classification labels them). Reads href + aria_role/parent from the raw node-list;
    never returns an href."""
    by_id = {n["id"]: n for n in sk_nodes}
    anchors = [{"node": n["id"], "href": n.get("href"),
                "chrome": _nav.classify_chrome(n["id"], by_id)}
               for n in sk_nodes if n.get("href")]
    return _nav.resolve_edges(anchors, route_map, src_id)


def capture_route(url, route_dir, transport, sweep=None, route_map=None, src_id=None):
    """Run skeleton -> tokens -> bundle into route_dir. Return
    (ok: bool, node_count: int|None, error_kind: str|None, edges: list, raw_nodes: list).
    error_kind is a fixed category, never subprocess stderr. edges is a list of nav-edge
    dicts (empty when route_map/src_id are not provided or on an edge-resolution error).
    raw_nodes is the in-memory pre-redaction node-list from _sk.json (hrefs intact, never
    persisted to disk); [] only when the raw _sk.json is unreadable — an edge-resolution
    error does NOT null it.

    The raw web_skeleton/web_tokens handoff (_sk.json/_tok.json) is PRE-redaction
    content and must NOT live in route_dir: bundle_writer audits its whole --out dir,
    and the site-root backstop rglobs the whole site tree -- either would trip on the
    raw scratch. So the scratch lives in a system tempdir OUTSIDE the site tree, and on
    ANY failure route_dir is removed so no partial/flagged files persist (content-free
    on disk + the failure stays isolated to this route).

    sweep: optional list of --sweep/--sweep-steps flags forwarded ONLY to web_skeleton."""
    if sweep is None:
        sweep = []
    route_dir = Path(route_dir)
    route_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        sk = Path(scratch) / "_sk.json"
        tok = Path(scratch) / "_tok.json"

        r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)] + transport + sweep)
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "skeleton_failed", [], [])

        r = _run([sys.executable, "web_tokens.py", "--url", url, "--out", str(tok)] + transport)
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "tokens_failed", [], [])

        r = _run([sys.executable, "bundle_writer.py",
                  "--skeleton", str(sk), "--tokens", str(tok), "--out", str(route_dir)])
        if r.returncode == 3:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "bundle_audit_failed", [], [])
        if r.returncode != 0:
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "bundle_failed", [], [])

        try:
            skel = json.loads((route_dir / "skeleton.json").read_text())
        except (OSError, ValueError):
            # bundle_writer exited 0 but its skeleton.json is missing/invalid (partial
            # write, fs race, regression). Isolate to THIS route — never abort the run.
            shutil.rmtree(route_dir, ignore_errors=True)
            return (False, None, "skeleton_unreadable", [], [])

        raw_nodes = []
        try:
            raw_nodes = json.loads(sk.read_text()).get("nodes", [])   # raw _sk.json (pre-redaction, has href)
        except (OSError, ValueError):
            raw_nodes = []
        edges = []
        if route_map is not None and src_id is not None:
            try:
                edges = _edges_from_skeleton(raw_nodes, route_map, src_id)
            except (KeyError, TypeError):
                edges = []
        return (True, len(skel.get("nodes", [])), None, edges, raw_nodes)


def _skeleton_nodes(url, transport):
    """Selection fetch: run web_skeleton ONLY and return its raw node-list (pre-redaction,
    href intact, IN-MEMORY) or None on any failure. The scratch lives OUTSIDE any audited
    tree and is discarded; no bundle is written. The hrefs are used transiently for one-hop
    discovery and are NEVER persisted."""
    with tempfile.TemporaryDirectory() as scratch:
        sk = Path(scratch) / "_sk.json"
        r = _run([sys.executable, "web_skeleton.py", "--url", url, "--out", str(sk)] + transport)
        if r.returncode != 0 or not sk.exists():
            return None
        try:
            return json.loads(sk.read_text()).get("nodes", [])
        except (OSError, ValueError):
            return None


def crawl_expand(frontier, seed_fps, routes_dir, start_idx, transport, *,
                 T, floor, robots_allow, skeleton_nodes=_skeleton_nodes,
                 capture_page=None, sleep=time.sleep, delay=2.0):
    """One-hop expander loop (spec §1 step 3). `frontier` is a list of (norm, href, src_idx)
    already same-origin-filtered and capped. For each: robots-check -> selection skeleton ->
    fingerprint -> reject_reason? On capture (reason is None) fully capture the page via
    `capture_page` into routes_dir/rNN and keep it. All network is behind the injected
    `skeleton_nodes(href, transport)` / `capture_page(href, route_dir)` callables (real
    defaults below; tests inject fakes).

    Returns (discovered_rows, raw_by_rid, norm_by_rid, ledger, next_idx):
      discovered_rows: content-free site.json rows -- NO url; carry discovered=True + via.
      raw_by_rid:      {rid: raw node-list} for the combined edge-resolution pass (in-memory).
      norm_by_rid:     {rid: normalized_url} for the combined route_map (in-memory, transient).
      ledger:          drop counts (no URLs): subfloor/not_novel/dup/robots_blocked/failed.
      next_idx:        the next free route index (== start_idx + number kept).
    """
    routes_dir = Path(routes_dir)
    if capture_page is None:
        def capture_page(href, route_dir):
            ok, node_count, _ek, _edges, raw = capture_route(href, route_dir, transport)
            return ok, node_count, raw
    import _crawl as cw
    kept_fps = []
    rows, raw_by_rid, norm_by_rid = [], {}, {}
    ledger = {"subfloor": 0, "not_novel": 0, "dup": 0, "robots_blocked": 0, "failed": 0}
    idx = start_idx
    for norm, href, src_idx in frontier:
        if not robots_allow(href):
            ledger["robots_blocked"] += 1
            continue
        nodes = skeleton_nodes(href, transport)
        sleep(delay)
        if nodes is None:
            ledger["failed"] += 1
            continue
        fp = cw.content_fingerprint(nodes)
        reason = cw.reject_reason(fp, seed_fps, kept_fps, T, floor)
        if reason is not None:
            ledger[reason] += 1
            continue
        rid = "r%02d" % idx
        ok, node_count, raw = capture_page(href, routes_dir / rid)
        sleep(delay)
        if not ok:
            ledger["failed"] += 1
            continue
        kept_fps.append(fp)
        rows.append({"route_id": rid, "bundle": "routes/" + rid, "ok": True,
                     "node_count": node_count, "discovered": True,
                     "via": "r%02d" % src_idx})
        raw_by_rid[rid] = raw
        norm_by_rid[rid] = norm
        idx += 1
    return rows, raw_by_rid, norm_by_rid, ledger, idx


def _resolve_combined_edges(routes_raw, urls, norm_by_rid):
    """Resolve nav-edges for EVERY captured route (seed + discovered) against the COMBINED
    route_map (seed urls + discovered norms), so seed->discovered and discovered->seed links
    both resolve (spec §1 step 4). routes_raw: {route_index:int -> raw node-list}.
    norm_by_rid: {'rNN' -> normalized_url} for discovered routes. Returns formatted edges
    ({src,dst,src_node,chrome} with rNN ids). Content-free; never an href."""
    route_map = dict(_nav.build_route_map(urls))
    for rid, norm in norm_by_rid.items():
        route_map[norm] = int(rid[1:])
    all_edges = []
    for idx, raw in sorted(routes_raw.items()):
        for e in _edges_from_skeleton(raw, route_map, idx):
            all_edges.append({"src": "r%02d" % e["src"], "dst": "r%02d" % e["dst"],
                              "src_node": e["src_node"], "chrome": e["chrome"]})
    return all_edges


def _make_robots_allow(ua):
    """Per-origin robots.txt gate (fetched/cached once per host). UA is the crawler's
    declared name. Fail-CLOSED: an unreadable robots.txt -> skip that origin (stricter than
    the de-risk's fail-open, because this ships)."""
    cache = {}

    def allow(href):
        p = urlparse(href)
        origin = "%s://%s" % (p.scheme, p.netloc)
        rp = cache.get(origin)
        if rp is None:
            rp = urllib.robotparser.RobotFileParser()
            rp.set_url(origin + "/robots.txt")
            try:
                rp.read()
            except Exception:
                cache[origin] = False    # fail-closed sentinel
                return False
            cache[origin] = rp
        if rp is False:
            return False
        return rp.can_fetch(ua, href)

    return allow


def capture_site(urls, out_dir, transport, sweep=None, crawl=None):
    """Capture every seed route, optionally expand one-hop (crawl), write site.json, and run
    the site-root firewall backstop. Returns the manifest dict. dies (nonzero) if the audit
    trips.

    crawl: None -> default behavior (unchanged). Else a params dict:
      {T, floor, max, delay, ua, robots_allow?, sleep?, skeleton_nodes?, capture_page?} --
      one-hop route-expander (spec §1)."""
    if sweep is None:
        sweep = []
    out = Path(out_dir)
    (out / "routes").mkdir(parents=True, exist_ok=True)
    route_map = _nav.build_route_map(urls)
    rows, all_edges = [], []
    seed_raw = {}     # src_id -> raw node-list (crawl only)
    for src_id, url in enumerate(urls):
        rid = "r%02d" % src_id
        # In crawl mode, defer edge resolution to the combined pass (route_map=None here).
        rm = None if crawl else route_map
        ok, node_count, error_kind, edges, raw = capture_route(
            url, out / "routes" / rid, transport, sweep, route_map=rm, src_id=src_id)
        row = {"route_id": rid, "url": url, "bundle": "routes/" + rid, "ok": ok}
        if ok:
            row["node_count"] = node_count
        else:
            row["error_kind"] = error_kind
        rows.append(row)
        if crawl:
            seed_raw[src_id] = raw if ok else []
        else:
            for e in edges:
                all_edges.append({"src": "r%02d" % e["src"], "dst": "r%02d" % e["dst"],
                                  "src_node": e["src_node"], "chrome": e["chrome"]})

    crawl_stats = None
    if crawl:
        import _crawl as cw
        seed_node_lists = [seed_raw.get(i, []) for i in range(len(urls))]
        seed_fps = [cw.content_fingerprint(seed_raw[i]) for i in sorted(seed_raw) if seed_raw[i]]
        frontier, n_cross = cw.frontier_targets(seed_node_lists, urls)
        frontier, n_over = cw.cap_frontier(frontier, crawl.get("max"))
        robots_allow = crawl.get("robots_allow") or _make_robots_allow(crawl.get("ua", "probe-runner/1.0"))
        sleep = crawl.get("sleep", time.sleep)
        disc_rows, raw_by_rid, norm_by_rid, ledger, _nxt = crawl_expand(
            frontier, seed_fps, out / "routes", len(urls), transport,
            T=crawl.get("T", 0.5), floor=crawl.get("floor", CRAWL_FLOOR),
            robots_allow=robots_allow, sleep=sleep, delay=crawl.get("delay", 2.0),
            skeleton_nodes=crawl.get("skeleton_nodes", _skeleton_nodes),
            capture_page=crawl.get("capture_page"))
        rows.extend(disc_rows)
        routes_raw = dict(seed_raw)
        for rid, raw in raw_by_rid.items():
            routes_raw[int(rid[1:])] = raw
        all_edges = _resolve_combined_edges(routes_raw, urls, norm_by_rid)
        # counts only (no URLs); total same-origin discovered = frontier_attempted + over_cap_dropped
        crawl_stats = {"frontier_attempted": len(frontier), "cross_origin_dropped": n_cross,
                       "over_cap_dropped": n_over, "kept": len(disc_rows), **ledger}

    manifest = _site.build_site_manifest(rows, nav_edges=all_edges)
    if crawl_stats is not None:
        manifest["crawl"] = crawl_stats    # counts only (no URLs) -- spec §5 no-silent-caps
    (out / "site.json").write_text(json.dumps(manifest, indent=2))

    # Backstop: audit_bundle rglobs the whole tree -> covers site.json AND every per-route
    # bundle. Content-free failure: kind+file only, never the `sample`.
    viol = cf.audit_bundle(out)
    if viol:
        safe = [{"kind": v.get("kind"), "file": v.get("file")} for v in viol[:5]]
        die("content leak in site %s: %d violation(s); first %d: %s"
            % (out_dir, len(viol), len(safe), safe), code=3)
    return manifest


# Minimum ok-route count each post-processor needs to be APPLICABLE. The orchestrator
# decides applicability (skip without invoking); the child still owns the authoritative
# check once invoked. See docs/plans/wire-cross-route-post-processors.md design note 2-3.
_POST_MIN_OK = {"merge": 1, "dedup": 2}
_POST_SCRIPT = {"merge": "site_merge.py", "dedup": "site_chrome.py"}


def _ok_count(site_dir):
    """ok-route count from the just-written manifest (single source of truth = site.json)."""
    try:
        site = json.loads((Path(site_dir) / "site.json").read_text())
    except (OSError, ValueError):
        return 0
    return sum(1 for r in site.get("routes", []) if r.get("ok"))


def run_post_processors(site_dir, merge, dedup):
    """Optionally run the cross-route post-processors over a finished capture dir.

    Returns {"merge": {...}, "dedup": {...}} where each value is {"status": s, ...}:
      "disabled" — flag off
      "skipped"  — flag on but too few ok routes (NOT invoked)
      "ok"       — child exited 0
      "leak"     — child exited 3 (firewall) -> caller must fail loud; stops further steps
      "error"    — child exited any other nonzero (incl. site_chrome's exit-2 losslessness
                   failure) -> caller must fail loud. NEVER conflated with "skipped".

    On a leak/error the loop stops, so a later step's key may be ABSENT — callers must use
    .get() or iterate .values(), not assume both keys.

    site_dir is resolved to an absolute path internally (children run with cwd=SCRIPTS, so a
    relative path would otherwise resolve against the scripts dir, not the caller's cwd)."""
    site_dir = Path(site_dir).resolve()
    ok = _ok_count(site_dir)
    out = {}
    for name, enabled in (("merge", merge), ("dedup", dedup)):
        if not enabled:
            out[name] = {"status": "disabled"}
            continue
        if ok < _POST_MIN_OK[name]:
            out[name] = {"status": "skipped", "reason": "insufficient_routes",
                         "ok_count": ok, "need": _POST_MIN_OK[name]}
            continue
        r = _run([sys.executable, _POST_SCRIPT[name], "--site", str(site_dir)])
        if r.returncode == 0:
            out[name] = {"status": "ok"}
        elif r.returncode == 3:
            out[name] = {"status": "leak", "returncode": 3}
            break  # stop on first firewall trip; clean bundles already preserved on disk
        else:
            out[name] = {"status": "error", "returncode": r.returncode}
            break  # any other nonzero (incl. exit-2 losslessness failure) = loud fault
    return out


def _parse_urls(args):
    urls = []
    if args.urls_file:
        for line in Path(args.urls_file).read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)
    if args.urls:
        urls += [u.strip() for u in args.urls.split(",") if u.strip()]
    return _site.dedupe_preserve_order(urls)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--urls-file", dest="urls_file", default=None,
                   help="file with one URL per line; blank/# lines ignored")
    p.add_argument("--urls", default=None, help="comma-separated URLs")
    p.add_argument("--out", required=True, help="site output directory")
    p.add_argument("--cdp-port", dest="cdp_port", type=int, default=None)
    p.add_argument("--browser", default="auto", choices=["chrome", "safari", "auto"])
    p.add_argument("--android", action="store_true")
    p.add_argument("--ios", action="store_true")
    p.add_argument("--serial", default=None)
    p.add_argument("--merge", action="store_true",
                   help="after capture, run site_merge.py -> design_system.json (needs >=1 ok route)")
    p.add_argument("--dedup", action="store_true",
                   help="after capture, run site_chrome.py -> chrome_dedup.json (needs >=2 ok routes)")
    p.add_argument("--sweep", action="store_true", default=False,
                   help="forward scroll-sweep to per-route web_skeleton (G2 append-class sites)")
    p.add_argument("--sweep-steps", type=int, default=8, dest="sweep_steps",
                   help="number of sweep steps forwarded to web_skeleton (default: 8)")
    p.add_argument("--crawl", action="store_true", default=False,
                   help="one-hop same-origin discovery: capture novel un-enumerated pages (off by default)")
    p.add_argument("--crawl-max", type=int, default=40, dest="crawl_max",
                   help="hard cap on frontier pages attempted per run (default: 40)")
    p.add_argument("--crawl-threshold", type=float, default=0.5, dest="crawl_threshold",
                   help="novelty/dedup bag-Jaccard threshold T (default: 0.5)")
    p.add_argument("--crawl-delay", type=float, default=2.0, dest="crawl_delay",
                   help="inter-fetch rate-limit seconds (default: 2.0)")
    args = p.parse_args()

    urls = _parse_urls(args)
    if not urls:
        die("site_capture needs at least one route (--urls-file or --urls).")

    out_dir = Path(args.out).resolve()   # absolute: children run cwd=SCRIPTS (design note 5)
    crawl = None
    if args.crawl:
        crawl = {"T": args.crawl_threshold, "floor": CRAWL_FLOOR, "max": args.crawl_max,
                 "delay": args.crawl_delay, "ua": "probe-runner/1.0"}
    manifest = capture_site(urls, str(out_dir), _transport_argv(args), _sweep_argv(args), crawl=crawl)

    payload = {"ok": True, "out": str(out_dir),
               "route_count": manifest["route_count"], "ok_count": manifest["ok_count"]}
    if "crawl" in manifest:
        payload["crawl"] = manifest["crawl"]
    if args.merge or args.dedup:
        post = run_post_processors(out_dir, args.merge, args.dedup)
        payload["post"] = post
        if any(v.get("status") in ("leak", "error") for v in post.values()):
            payload["ok"] = False
            emit_json(payload)
            return 3 if any(v.get("status") == "leak" for v in post.values()) else 1
    emit_json(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
