"""G2 virtualization sweep-merge engine.

PURE CORE (this section): merge per-step skeletons into a content-free `below_fold`
addendum = the SET of distinct shape-keys present across the sweep but ABSENT from
REST. One record per distinct new shape (instances are deduped — a content-free engine
cannot and must not count identical items). Records are built by WHITELIST from
mechanism fields only, so no position (bbox) and no content can enter. Deterministic:
records sorted by shape-key. See docs/plans/g2-virtualization-build.md for the locked
contract; LIVE capture (sweep_skeletons) is in the second section, CDP-only."""
from _shape_key import _node_key

# Whitelist of mechanism fields copied into an addendum record. EXCLUDES every
# positional/volatile field (id/parent/bbox/z) and every content key -- content-free
# by construction (same IP-boundary discipline as aria_role).
_RECORD_FIELDS = ("role", "aria_role", "layout", "sizing", "token_ref", "font",
                  "text_len", "substrate")

BELOW_FOLD_SCHEMA = "probe-belowfold/1"


def shape_key(node):
    return _node_key(node)


def _shape_record(node, key):
    rec = {"key": key}
    for f in _RECORD_FIELDS:
        v = node.get(f)
        if v is not None:
            rec[f] = v
    if node.get("pseudo"):
        rec["pseudo"] = 1
    return rec


def new_shape_records(rest_nodes, sweep_node_lists):
    """Distinct shape records present across the sweep snapshots but ABSENT from REST,
    deduped to one per shape-key, sorted by key (deterministic)."""
    rest_keys = {shape_key(n) for n in rest_nodes}
    seen, recs = set(), []
    for nodes in sweep_node_lists:
        for n in nodes:
            k = shape_key(n)
            if k in rest_keys or k in seen:
                continue
            seen.add(k)
            recs.append(_shape_record(n, k))
    recs.sort(key=lambda r: r["key"])
    return recs


def merge_skeletons(rest_sk, sweep_sks):
    """Return a NEW skeleton = REST + a `below_fold` block of distinct new shapes.
    Does not mutate rest_sk; does not add per-instance nodes, counts, or positions."""
    rest_nodes = rest_sk.get("nodes", [])
    sweep_lists = [sk.get("nodes", []) for sk in sweep_sks]
    recs = new_shape_records(rest_nodes, sweep_lists)
    merged = dict(rest_sk)
    merged["below_fold"] = {
        "schema": BELOW_FOLD_SCHEMA,
        "step_count": len(sweep_sks),
        "new_shapes": len(recs),
        "shapes": recs,
    }
    return merged


# --- LIVE capture (CDP only; validated by scripts/livesmoke_g2.py, not pytest) ---------
# Faithful port of probe_g2_virtualization._snap_nodes / _scrollable / _set_scroll /
# _settle_nodecount. CRITICAL: a sweep step must snapshot at the HELD scroll offset, so it
# does a raw DOMSnapshot + parse_snapshot + to_skeleton (NOT _snapshot_skeleton, which runs
# _REST_JS and would reset scroll to 0).
import time


def _node_count(ev):
    return int(ev.ev("document.getElementsByTagName('*').length"))


def _scrollable(ev):
    return ev.ev("({sh:document.documentElement.scrollHeight,ih:innerHeight,"
                 "sy:Math.round(window.scrollY)})")


def _set_scroll(ev, y):
    ev.ev("(function(y){var d=document.documentElement;d.style.scrollBehavior='auto';"
          "document.body.style.scrollBehavior='auto';window.scrollTo(0,y);"
          "return Math.round(window.scrollY);})(%d)" % int(y))


def _settle_nodecount(ev, max_wait=4.0, poll=0.3, stable_needed=2):
    """Poll #nodes until stable between consecutive reads (lazy mount converged) or cap."""
    last, stable = -1, 0
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        n = _node_count(ev)
        if n == last:
            stable += 1
            if stable >= stable_needed:
                return n
        else:
            stable = 0
        last = n
        time.sleep(poll)
    return last


def _snap_nodes(ev, url, reset):
    """No-navigate DOMSnapshot -> a skeleton dict at the CURRENT scroll position. Faithful
    port of probe_g2_virtualization._snap_nodes. reset=False snapshots whatever lazily
    mounted at the held offset (the sweep case)."""
    import web_skeleton as WK  # function-local: keeps _virt's pure core importable
    if reset:
        ev.ev(WK._REST_JS)
        time.sleep(0.15)
    layout = ev.ev("({w: innerWidth, h: innerHeight, dpr: devicePixelRatio})")
    page = ev.ev("({w: document.documentElement.scrollWidth, "
                 "h: document.documentElement.scrollHeight})")
    ev.sess.send("DOMSnapshot.enable", {})
    snap = ev.sess.send("DOMSnapshot.captureSnapshot",
                        {"computedStyles": WK.WANT_STYLES,
                         "includeDOMRects": True, "includePaintOrder": True})
    eff_dpr = layout["dpr"] or 1.0
    recs = WK.parse_snapshot(snap, WK.WANT_STYLES, dpr=eff_dpr)
    svg_set, parent_index = set(), None
    for doc in snap["documents"]:
        svg_set |= WK.svg_descendants(doc, snap["strings"])
        if parent_index is None:
            parent_index = doc["nodes"]["parentIndex"]
    sk, ncol, nsty, npseu, nback = WK.to_skeleton(
        recs, svg_set, parent_index=parent_index, url=url,
        viewport={"w": layout["w"], "h": layout["h"], "dpr": eff_dpr},
        page={"w": page["w"], "h": page["h"]})
    # Sidecars carried faithfully from the probe's _snap_nodes (probe L125-127). merge_skeletons
    # reads only sk["nodes"]; sweep skeletons are discarded after merge, so these never reach
    # output -- kept for byte-fidelity with the de-risked reference.
    sk["_node_colors"] = {str(k): v for k, v in ncol.items()}
    sk["_node_style"] = {str(k): v for k, v in nsty.items()}
    sk["_node_pseudo"] = {str(k): v for k, v in npseu.items()}
    WK.enrich_aria(sk["nodes"], nback, ev)
    return sk


def sweep_skeletons(ev, url, steps=8):
    """Scroll-settle sweep over the page ALREADY loaded on `ev` (REST is the caller's
    out_obj -- no double-capture). Returns the list of per-step skeleton dicts to feed
    merge_skeletons. In-class gate (sh>ih) is the caller's responsibility; does NOT navigate."""
    inner = _scrollable(ev)["ih"]
    sweep_sks = []
    for i in range(1, steps + 1):
        sh = _scrollable(ev)["sh"]
        _set_scroll(ev, min(sh, i * inner))
        _settle_nodecount(ev)
        sweep_sks.append(_snap_nodes(ev, url, reset=False))
    return sweep_sks
