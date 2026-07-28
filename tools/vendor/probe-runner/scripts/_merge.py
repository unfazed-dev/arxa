"""Pure cross-route token-merge core (G3b). No I/O, no CDP — unit-testable in
isolation (mirrors _site.py / _theme.py). Consumes per-route tokens.json dicts and
produces a content-free unified design system (schema probe-runner/design-system@1).
Grounded by the recurrence probe (gaps doc §C9-R-G3a-probe): merge on role keys not
raw values; report palette exact AND clustered; frequency-annotated core + deltas;
measure value recurrence per role."""
import web_tokens as wt

DESIGN_SCHEMA = "probe-runner/design-system@1"
PALETTE_ROLES = ["background", "surface", "fg-primary", "fg-muted", "accent", "border"]
SCALAR_CATS = ["type_scale", "weights", "families", "spacing", "radii", "shadows"]


def _freq_entries(value_to_route_ids, n, key="value"):
    """value_to_route_ids: {value: [route_id, ...]}. Return frequency-annotated
    entries sorted by route count desc then value. `core` iff present in all N. `key`
    names the value field: "value" everywhere except the families scalar category, which
    uses "family" so font stacks stay under a content-firewall-exempt key (parity with
    how tokens.json stores them)."""
    entries = []
    for value, ids in value_to_route_ids.items():
        sids = sorted(set(ids))
        entries.append({key: value, "routes": len(sids),
                        "route_ids": sids, "core": len(sids) == n})
    entries.sort(key=lambda e: (-e["routes"], str(e[key])))
    return entries


def merge_scalars(per_route_scalars):
    """per_route_scalars: [(route_id, tokens_dict)]. Exact frequency per category."""
    n = len(per_route_scalars)
    out = {}
    for cat in SCALAR_CATS:
        m = {}
        for rid, scalars in per_route_scalars:
            for v in (scalars.get(cat) or []):
                m.setdefault(v, []).append(rid)
        out[cat] = _freq_entries(m, n, key="family" if cat == "families" else "value")
    return out


def _exact_role(per_route_palettes, role):
    """{hex: [route_id, ...]} for one role over routes carrying a truthy (non-null,
    non-empty) value."""
    m = {}
    for rid, pal in per_route_palettes:
        v = pal.get(role)
        if v:
            m.setdefault(v, []).append(rid)
    return m


def _clustered_role(per_route_palettes, role, tol):
    """Reuse web_tokens.cluster_colors for representatives, then assign each route's
    value to the nearest representative within tol (Chebyshev) to recover route_ids
    and core. Per-role: only this role's values are clustered."""
    exact = _exact_role(per_route_palettes, role)          # {hex: [ids]}
    if not exact:
        return []
    # area = route-frequency so the most-frequent shade seeds (and represents) its
    # cluster, matching cluster_colors' deterministic largest-area-first order.
    samples = [(hexv, len(ids)) for hexv, ids in exact.items()]
    reps = [(rep, wt.parse_color(rep)) for rep, _area in wt.cluster_colors(samples, tol=tol)]
    # cluster_colors is greedy/largest-area-first, so two representatives are not
    # guaranteed to be pairwise > tol apart. If a value is within tol of more than one
    # rep, the strict `d < best_d` below keeps the FIRST (highest-frequency) rep, since
    # `reps` is area-desc — a deterministic tie-break toward the dominant shade. Under
    # normal tol values overlapping reps are uncommon.
    cl = {}
    for hexv, ids in exact.items():
        rgb = wt.parse_color(hexv)
        best, best_d = None, None
        for rep, rrgb in reps:
            # skip unparseable reps; if ALL reps fail to parse, fall back to self below
            if rgb is None or rrgb is None:
                continue
            d = max(abs(rgb[i] - rrgb[i]) for i in range(3))
            if d <= tol and (best_d is None or d < best_d):
                best, best_d = rep, d
        key = best if best is not None else hexv
        cl.setdefault(key, []).extend(ids)
    return _freq_entries(cl, len(per_route_palettes))


def merge_palette(per_route_palettes, cluster_tol):
    """per_route_palettes: [(route_id, {role: hex|None})]. Per role: exact + clustered
    frequency entries (spec §3.2)."""
    out = {}
    for role in PALETTE_ROLES:
        out[role] = {
            "exact": _freq_entries(_exact_role(per_route_palettes, role),
                                   len(per_route_palettes)),
            "clustered": _clustered_role(per_route_palettes, role, cluster_tol),
        }
    return out


def build_design_system(per_route, hosts, cluster_tol):
    """per_route: [(route_id, tokens_dict)] for the merged (ok, readable) routes.
    Returns the full content-free design-system dict (spec §3.4)."""
    palettes = [(rid, (t.get("palette") or {})) for rid, t in per_route]
    return {
        "schema": DESIGN_SCHEMA,
        "hosts": hosts,
        "merged_route_count": len(per_route),
        "route_ids": [rid for rid, _ in per_route],
        "cluster_tol": cluster_tol,
        "palette": merge_palette(palettes, cluster_tol),
        "scalars": merge_scalars(per_route),
    }
