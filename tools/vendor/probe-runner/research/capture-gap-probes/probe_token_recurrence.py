#!/usr/bin/env python3
"""Cross-route recurrence probe (G3b de-risk). Empirical investigation, NOT a
gated CLI and NOT in the unit suite. Reads a G3a capture (routes/<id>/tokens.json
+ skeleton.json across N same-host routes) and measures whether design tokens
RECUR across routes, to ground G3b's merge model.

Plan: docs/plans/cross-route-recurrence-probe.md.

CONTENT-FREE: reads tokens.json (design tokens = probe-runner's legitimate persisted
extract) + skeleton.json (structural). REPORT emits counts / ratios / booleans and
HTML-tag / ARIA-role / palette-role-key NAMES only (probe-runner / web vocabulary, not
site content) — never a dump of hex values or font-size lists, never subprocess stderr.

Modes (run on host Bash; CDP Chrome must be reachable, default :9222):
  --site DIR                  analyse an already-captured site directory
  --capture URLS --label L    site_capture URLS (comma list) -> tempdir, audit, analyse
  --calibrate                 Floor B: capture two byte-identical-CSS / different-content
                              pages locally and analyse (the noise floor)
"""
import argparse
import importlib
import json
import shutil
import subprocess
import sys
import tempfile
from itertools import combinations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"

# ---- token categories pulled from tokens.json (flat shape, web_tokens spec §5.2) ----
# palette is role->hexstring; the rest are lists of scalar token values.
SCALAR_CATS = ["type_scale", "weights", "families", "spacing", "radii", "shadows"]


# ---------------------------- pure analysis core ----------------------------
def _jaccard(a, b):
    u = a | b
    return (len(a & b) / len(u)) if u else 1.0


def _mean_pairwise_jaccard(sets):
    pairs = list(combinations(range(len(sets)), 2))
    if not pairs:
        return 1.0
    return round(sum(_jaccard(sets[i], sets[j]) for i, j in pairs) / len(pairs), 4)


def recurrence(per_route_sets):
    """Content-free recurrence stats for one category given each route's value set."""
    n = len(per_route_sets)
    from collections import Counter
    freq = Counter()
    for s in per_route_sets:
        for v in s:
            freq[v] += 1
    distinct = len(freq)
    return {
        "routes": n,
        "distinct": distinct,
        "core": sum(1 for c in freq.values() if c == n),          # in ALL routes
        "shared_ge2": sum(1 for c in freq.values() if c >= 2),    # in >=2 routes
        "unique": sum(1 for c in freq.values() if c == 1),        # per-route delta
        "mean_pairwise_jaccard": _mean_pairwise_jaccard(per_route_sets),
    }


def _hex_to_rgb(s):
    s = str(s).strip()
    if s.startswith("#") and len(s) == 7:
        try:
            return (int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16))
        except ValueError:
            return None
    return None


def _cluster_values(all_values, tol=8):
    """Greedy Chebyshev (max abs channel diff) clustering of hex colors within tol.
    Approximates web_tokens cluster_colors (tol=8) for the near-match variant. Returns
    {value: cluster_id}; non-hex values are their own singleton cluster."""
    reps = []  # (rgb, id)
    mapping = {}
    for v in sorted(all_values):
        rgb = _hex_to_rgb(v)
        if rgb is None:
            mapping[v] = ("raw", v)
            continue
        hit = None
        for rrgb, rid in reps:
            if max(abs(rgb[k] - rrgb[k]) for k in range(3)) <= tol:
                hit = rid
                break
        if hit is None:
            hit = len(reps)
            reps.append((rgb, hit))
        mapping[v] = ("cl", hit)
    return mapping


def _palette_sets(tokens_list):
    """Three views of palette recurrence: by role KEY, by exact VALUE, by clustered
    value (ΔRGB<=8). Empty/null role values are dropped."""
    key_sets, val_sets = [], []
    all_vals = set()
    for t in tokens_list:
        pal = t.get("palette") or {}
        keys = {k for k, v in pal.items() if v}
        vals = {v for v in pal.values() if v}
        key_sets.append(keys)
        val_sets.append(vals)
        all_vals |= vals
    clmap = _cluster_values(all_vals)
    cl_sets = []
    for t in tokens_list:
        pal = t.get("palette") or {}
        cl_sets.append({clmap[v] for v in pal.values() if v})
    return {
        "by_role_key": recurrence(key_sets),
        "by_exact_value": recurrence(val_sets),
        "by_clustered_value": recurrence(cl_sets),
    }


def _structural_sets(skeletons):
    """Coarse structural recurrence hint: ARIA-role SET presence across routes (NOT
    multisets — node COUNTS are content-volume-sensitive). The content-free skeleton
    node carries `role`, not `tag` (raw tag is internal, stripped before emit), so role
    IS the structural axis. A G3c preview only, not component synthesis."""
    role_sets = []
    for sk in skeletons:
        nodes = sk.get("nodes") or []
        role_sets.append({n.get("role") for n in nodes if n.get("role")})
    return {
        "role_presence": recurrence(role_sets),
        "node_counts": [len(sk.get("nodes") or []) for sk in skeletons],
    }


def analyze_site(site_dir):
    site_dir = Path(site_dir)
    site = json.loads((site_dir / "site.json").read_text())
    ok_routes = [r for r in site.get("routes", []) if r.get("ok")]
    tokens_list, skeletons, used = [], [], []
    for r in ok_routes:
        rid = r["route_id"]
        bdir = site_dir / "routes" / rid
        tk, sk = bdir / "tokens.json", bdir / "skeleton.json"
        if not (tk.exists() and sk.exists()):
            continue
        try:
            tokens_list.append(json.loads(tk.read_text()))
            skeletons.append(json.loads(sk.read_text()))
            used.append(rid)
        except (OSError, ValueError):
            continue
    out = {
        "hosts": site.get("hosts"),
        "route_count": site.get("route_count"),
        "ok_count": site.get("ok_count"),
        "analysed_routes": used,
        "palette": _palette_sets(tokens_list) if tokens_list else None,
        "scalars": {c: recurrence([set(t.get(c) or []) for t in tokens_list])
                    for c in SCALAR_CATS} if tokens_list else None,
        "structural": _structural_sets(skeletons) if skeletons else None,
    }
    return out


# ---------------------------- capture helpers (host CDP) ----------------------------
def _audit_clean(site_dir):
    sys.path.insert(0, str(SCRIPTS))
    cf = importlib.import_module("content_firewall")
    viol = cf.audit_bundle(Path(site_dir))
    return (not viol), len(viol)  # never return/print the samples


def _site_capture(urls, out, cdp_port):
    """Run the gated site_capture orchestrator. Returns its return code only —
    never its stderr (content firewall: a leak message can embed a sample)."""
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "site_capture.py"),
         "--urls", ",".join(urls), "--out", str(out), "--cdp-port", str(cdp_port)],
        cwd=str(SCRIPTS), capture_output=True, text=True)
    return r.returncode


def _capture_and_analyze(urls, label, cdp_port):
    tmp = Path(tempfile.mkdtemp(prefix="recur_%s_" % label))
    try:
        rc = _site_capture(urls, tmp, cdp_port)
        if rc != 0:
            return {"label": label, "capture_rc": rc, "error": "site_capture_failed"}
        clean, nviol = _audit_clean(tmp)
        if not clean:
            return {"label": label, "audit": "DIRTY", "violations": nviol}
        res = analyze_site(tmp)
        res["label"] = label
        res["capture_rc"] = 0
        res["audit"] = "CLEAN"
        return res
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# Floor B: byte-identical CSS, different body content. Synthetic fixture markup
# (this repo's own), not third-party.
_CSS = (":root{--bg:#0b0b0b;--fg:#f5f5f5;--accent:#3b82f6}"
        "body{background:var(--bg);color:var(--fg);font-family:system-ui;margin:0}"
        "h1{font-size:32px;font-weight:700}p{font-size:16px;line-height:1.5}"
        "a{color:var(--accent)}.card{border:1px solid #222;border-radius:8px;padding:16px}")
_PAGES = {
    "/": "<!doctype html><html><head><style>%s</style></head><body><header><h1>Alpha</h1>"
         "</header><main><p>one two three</p><div class=card><a href=#>x</a></div></main></body></html>" % _CSS,
    "/two": "<!doctype html><html><head><style>%s</style></head><body><header><h1>Beta gamma</h1>"
            "</header><main><p>four five six seven eight nine</p><p>ten</p>"
            "<div class=card><a href=#>y</a></div></main></body></html>" % _CSS,
}


def _calibrate_floor_b(cdp_port):
    import http.server
    import socketserver
    import threading

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = _PAGES.get(self.path)
            if body is None:
                self.send_response(404); self.end_headers(); return
            b = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def log_message(self, *a):
            pass

    httpd = socketserver.TCPServer(("127.0.0.1", 0), H)
    port = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        base = "http://127.0.0.1:%d" % port
        return _capture_and_analyze([base + "/", base + "/two"], "floorB_sameCSS", cdp_port)
    finally:
        httpd.shutdown()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--site", help="analyse an already-captured site dir")
    ap.add_argument("--capture", help="comma URL list to site_capture then analyse")
    ap.add_argument("--label", default="capture")
    ap.add_argument("--calibrate", action="store_true", help="Floor B noise floor")
    ap.add_argument("--cdp-port", type=int, default=9222)
    args = ap.parse_args()

    if args.calibrate:
        res = _calibrate_floor_b(args.cdp_port)
    elif args.capture:
        urls = [u.strip() for u in args.capture.split(",") if u.strip()]
        res = _capture_and_analyze(urls, args.label, args.cdp_port)
    elif args.site:
        res = analyze_site(args.site)
    else:
        ap.error("one of --site / --capture / --calibrate required")
    print(json.dumps(res, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
