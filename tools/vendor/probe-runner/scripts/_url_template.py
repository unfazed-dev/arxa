# scripts/_url_template.py
"""Pure URL-structural same-template grouping for the §C9-R-T-ANCHOR de-risk.
No I/O, no network. Labels same-template pairs by URL SHAPE (pagination / siblings),
independent of the bag-Jaccard content fingerprint -> the HIGH-side anchor is non-circular
(spec §1). URLs are handled transiently; this module neither persists nor logs them."""
import re
from itertools import combinations
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode

_PAGE_QS = {"page", "p"}
_PATH_PAGE = re.compile(r"/(?:page|p)/(\d+)(?=/|$)")
_TRAIL_NUM = re.compile(r"/(\d+)/?$")


def _canon_host(netloc):
    h = netloc.lower()
    return h[4:] if h.startswith("www.") else h


def _rebuild(scheme, host, path, query_pairs):
    return urlunsplit((scheme, host, path, urlencode(sorted(query_pairs)), ""))


def paginate_key(url):
    """If `url` matches a pagination form, return (template, index): `template` is the URL
    with the page index replaced by a placeholder / removed, `index` the int page number.
    Else None. Forms (high-confidence same-template, different content): ?page=N / ?p=N (query);
    /page/N or /p/N (path); a trailing pure-integer path segment. Host is lowercased + www-
    stripped so the same list paginated under either host collapses to one template."""
    parts = urlsplit(url)
    host = _canon_host(parts.netloc)
    q = parse_qsl(parts.query, keep_blank_values=True)
    idx, rest = None, []
    for k, v in q:
        if k.lower() in _PAGE_QS and idx is None and v.isdigit():
            idx = int(v)
        else:
            rest.append((k, v))
    if idx is not None:
        return (_rebuild(parts.scheme, host, parts.path, rest), idx)
    m = _PATH_PAGE.search(parts.path)
    if m:
        tmpl_path = parts.path[:m.start()] + "/page/{}" + parts.path[m.end():]
        return (_rebuild(parts.scheme, host, tmpl_path, q), int(m.group(1)))
    m = _TRAIL_NUM.search(parts.path)
    if m:
        tmpl_path = parts.path[:m.start()] + "/{}"
        return (_rebuild(parts.scheme, host, tmpl_path, q), int(m.group(1)))
    return None


def sibling_key(url):
    """Tier-2 grouping key: scheme://host/<parent-path> (last path segment removed). Two
    distinct URLs sharing a sibling_key are same-parent siblings (medium-confidence same
    template; corroborative only)."""
    parts = urlsplit(url)
    host = _canon_host(parts.netloc)
    segs = [s for s in parts.path.split("/") if s]
    parent = "/".join(segs[:-1])
    return f"{parts.scheme}://{host}/{parent}"


def group_by_template(urls):
    """Partition URLs into same-template groups by URL shape (spec §1). A URL with a
    paginate_key goes to Tier 1 (grouped by template); otherwise to Tier 2 (grouped by
    sibling_key). URLs are deduped first; only groups with >=2 distinct members are kept
    (a singleton forms no pair). Returns {"tier1": {template: [urls]}, "tier2": {parent: [urls]}}."""
    urls = list(dict.fromkeys(urls))
    tier1, t2_pool = {}, []
    for u in urls:
        pk = paginate_key(u)
        if pk is not None:
            tier1.setdefault(pk[0], []).append(u)
        else:
            t2_pool.append(u)
    tier2 = {}
    for u in t2_pool:
        tier2.setdefault(sibling_key(u), []).append(u)
    tier1 = {k: v for k, v in tier1.items() if len(v) >= 2}
    tier2 = {k: v for k, v in tier2.items() if len(v) >= 2}
    return {"tier1": tier1, "tier2": tier2}


def within_group_pairs(groups):
    """All unordered within-group pairs for ONE tier's group dict (e.g. groups["tier1"]).
    Each group already has >=2 distinct members (group_by_template). HIGH side of the bar."""
    pairs = []
    for members in groups.values():
        pairs.extend(combinations(members, 2))
    return pairs


def _group_id(url):
    pk = paginate_key(url)
    return ("t1", pk[0]) if pk is not None else ("t2", sibling_key(url))


def across_group_pairs(urls):
    """All unordered pairs of distinct URLs whose template-group differs. Singletons each
    form their own group, so an ungrouped URL pairs across with everything that does not
    share its template key. Secondary (same-population) LOW cross-check; not in the bar."""
    urls = list(dict.fromkeys(urls))
    return [(a, b) for a, b in combinations(urls, 2) if _group_id(a) != _group_id(b)]
