"""Pure content-free nav-edge resolution for the site-level capture (nav-link -> route_id
annotation). Resolves in-process; NEVER emits an href. Spec: docs/plans/nav-link-route-annotation-design.md."""
from urllib.parse import urlparse

CHROME_LANDMARKS = {"banner", "navigation", "contentinfo", "complementary"}


def normalize_url(u):
    """Canonical key for intra-set matching: scheme must be http(s) (else None); host
    lowercased with a leading 'www.' stripped; path lowercased with one trailing slash
    removed (root stays '/'); query + fragment dropped. Lowercasing the path is a
    deliberate, documented match-tolerance (most route paths are case-insensitive in
    practice); it can only MERGE links, never invent edges."""
    if not u:
        return None
    try:
        p = urlparse(u)
    except ValueError:
        return None
    if p.scheme not in ("http", "https"):
        return None
    host = p.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    path = (p.path or "/").lower()
    if path != "/":
        path = path.rstrip("/") or "/"
    return host + path


def build_route_map(urls):
    """{normalized_url: route_id}. route_id = index in `urls`; first occurrence wins on collision."""
    rm = {}
    for rid, u in enumerate(urls):
        n = normalize_url(u)
        if n is not None and n not in rm:
            rm[n] = rid
    return rm


def resolve_edges(anchors, route_map, src_id):
    """One content-free edge per anchor whose normalized href maps to a route != src_id.
    Drops self-links, external/unresolved, and non-http. Never returns an href.
    anchors: [{"node": <skeleton id>, "href": <str>, "chrome": <bool>}]."""
    edges = []
    for a in anchors:
        n = normalize_url(a.get("href"))
        if n is None:
            continue
        dst = route_map.get(n)
        if dst is None or dst == src_id:
            continue
        edges.append({"src": src_id, "dst": dst, "src_node": a["node"], "chrome": bool(a.get("chrome"))})
    return edges


def classify_chrome(node_id, by_id):
    """True iff the node's NEAREST landmark ancestor (incl. itself) has aria_role in
    CHROME_LANDMARKS. Walks parent links in `by_id` (a {id: {parent, aria_role, ...}} map).
    A non-landmark anchor inherits the region of its closest landmark; no landmark on the
    path -> not chrome (treated as content/main)."""
    seen = set()
    cur = node_id
    while cur is not None and cur in by_id and cur not in seen:
        seen.add(cur)
        ar = by_id[cur].get("aria_role")
        if ar in CHROME_LANDMARKS:
            return True
        if ar is not None:          # a non-chrome landmark (main/region/...) -> nearest wins, stop
            return False
        cur = by_id[cur].get("parent")
    return False
