"""Pure manifest core for multi-route site capture (G3a). No I/O, no CDP — unit
testable in isolation (mirrors the _theme/_style pure-core pattern)."""
from urllib.parse import urlparse

SITE_SCHEMA = "probe-runner/site-manifest@1"


def dedupe_preserve_order(urls):
    """Return urls with duplicates removed, preserving first-seen order."""
    seen = set()
    out = []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def build_site_manifest(rows, nav_edges=None):
    """Assemble the content-free site manifest (design spec §5) from per-route
    result rows. Each row: {route_id, url, bundle, ok, node_count?, error_kind?}.
    Rows pass through verbatim as `routes`; only hosts/counts are derived."""
    hosts = sorted({urlparse(r["url"]).netloc for r in rows if r.get("url")})
    return {
        "schema": SITE_SCHEMA,
        "hosts": hosts,
        "route_count": len(rows),
        "ok_count": sum(1 for r in rows if r.get("ok")),
        "routes": rows,
        "nav_edges": nav_edges or [],
    }
