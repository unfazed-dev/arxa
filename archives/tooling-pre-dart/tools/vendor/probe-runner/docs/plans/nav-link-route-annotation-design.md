# Nav-link → route_id annotation (the buildable half of the nav/site graph) — DESIGN

**Status:** design / pre-build. Approved 2026-06-03.
**Lineage:** §A4 G3 named "shared-chrome dedup + a nav/site graph." The capture/dedup/merge rungs
landed (G3a `--urls`, `site.json`, G3b token-merge, G3d structural-deltas chrome-dedup); the nav/site
graph was the last unbuilt piece. A content-free characterization read (§C9-R-NG, recorded in the gaps
doc and §1 below) **scoped it before any spec**: the ambitious content-level site graph is empty by
construction on an intra-set capture, but the **nav-annotation floor is real**. This builds that floor.

---

## 0. One-paragraph what & why

Today a multi-route `site_capture` produces N route bundles whose in-page nav links point **nowhere** —
hrefs are content and the firewall strips them, so the captured (and G3d-deduped) shared nav is a dead
structure. This feature resolves each route's anchor hrefs to **route_ids within the captured set** at
capture time and ships a content-free `nav_edges` topology, turning the deduped nav into a navigable
structure for reproduction. It ships **no URLs** — only `route_id → route_id` edges keyed to the stable
skeleton node id.

## 1. De-risk evidence (the characterization IS the pre-build gate — already run)

Content-free read on the G3c cohorts (real, multi-route; MPA python/w3/django + SPA mui/stripe/vercel),
4 routes each: navigate, eval `a[href]`, resolve each href to the captured route set, classify by
whether the anchor sits in a chrome landmark. Only counts printed; hrefs never left the sandbox.

| site | anchors | resolved→other-route, **chrome (nav)** | resolved→other-route, **content** |
|---|---|---|---|
| python.org | 1610 | 45 | 0 |
| w3.org | 371 | 19 | 5 |
| djangoproject.com | 435 | 21 | 4 |
| mui.com (SPA) | 345 | 11 | 3 |
| stripe.com (SPA) | 1107 | 1 | 0 |
| vercel.com (SPA) | 489 | 12 | 0 |

Findings that fix the scope: **(a)** the nav-annotation floor is real and populated on every site,
incl. SPAs (SPA `<a href>` resolve fine — no href sparsity). **(b)** the content-level site graph is
empty *by construction* — intra-set is nav-dominated because users pick `--urls` = the nav destinations,
so nav links resolve circularly while content cross-links point to un-enumerated pages and drop as
external (content cell: 12 edges across 24 routes, 0.5/route). The raw chrome counts are per-route
*instances* (the same shared nav counted ~4×); the **distinct** nav-node→route edges (≈10–15/site for
python, fewer for the SPAs) are obtained by joining `src_node` to the existing G3d chrome template — a
derived view, stated here so value is not inflated, NOT new dedup machinery. The honest deliverable is
nav annotation, decided **before** the spec — not a content/site graph.

## 2. What ships (the product)

A content-free `nav_edges` array in `site.json`. Each edge:

```
{ "src": <src route_id>, "dst": <dst route_id>, "src_node": <skeleton node id in src route>, "chrome": true }
```

- `src_node` is the **skeleton node id** of the anchor in the source route, as it appears in the SHIPPED
  `routes/<src>/skeleton.json` (build must verify redaction preserves ids: `bundle_writer` strips per-node
  *content* — `text`/`href` — but not structure, so the raw `_sk.json` id == the shipped id). It is the
  join key — stable and reconstructable because G3d's structural-deltas dedup is LOSSLESS (it reconstructs
  each route's nodes with original ids; node-set identical — `_chrome_dedup`/`_node_key`/`_subtree`). A
  reproducer locates the nav link node by this id and wires it to `dst`. Edges ship **per route** (`src`
  explicit); the cross-route dedup to distinct nav→route edges is the derived G3d-template view (§1), not a
  shipped collapse.
- `chrome` = the anchor's nearest landmark ancestor has a computed `aria_role` ∈ `CHROME_LANDMARKS`
  (`banner / navigation / contentinfo / complementary`) — the SAME chrome definition G3d uses, NOT an
  ad-hoc tag selector. `chrome:false` edges (content cross-links) are emitted but are near-always absent
  (measured 0.5/route); no separate content-edge machinery is built for them.
- **No URLs, no anchor text, no ordinal.** (`idx` was rejected — an anchor's position among `a[href]` is
  unstable across loads and is not the reproduction key; the skeleton node id is.)

## 3. Architecture — units (well-bounded)

- **`scripts/_nav.py` (new, pure, fully unit-tested, no browser):**
  - `normalize_url(u) -> str|None` — canonical form: scheme∈{http,https} else None; host lowercased,
    leading `www.` stripped; path with one trailing slash removed (root stays `/`); query + fragment
    dropped.
  - `build_route_map(urls) -> {normalized_url: route_id}` (first occurrence wins on collision).
  - `resolve_edges(anchors, route_map, src_id) -> [edge,...]` where `anchors` is
    `[{"node": <skeleton id>, "href": <str>, "chrome": <bool>}]`. Emits one edge per anchor whose
    normalized href is in `route_map` AND maps to a route ≠ `src_id` (drops self-links, external,
    unresolved). Edge = `{src: src_id, dst, src_node, chrome}`. Pure; never returns an href. (No
    cross-route dedup here — that needs the G3d chrome template and is a derived view, §1/§2.)
- **`scripts/web_skeleton.py` — extract anchor hrefs in `parse_snapshot` (pre-redaction):** for each
  `<a>` layout node, read its `href` from the DOMSnapshot node attributes (the snapshot already carries
  `attributes`; `parse_snapshot` reads `nodeName`/`text` the same pre-redaction way) and attach it to the
  record under the `href` key (chosen over a custom `_href`: `href` is already a
  `content_firewall.CONTENT_KEY`, so `redact_node` strips it from the shipped skeleton automatically —
  a `_href` would NOT be in `CONTENT_KEYS` and could ship). This is content (like `text`) and lives ONLY
  in the raw `_sk.json` scratch that already sits in a system tempdir OUTSIDE the firewall-audited tree.
- **`scripts/site_capture.py` `capture_route` — resolve then strip:** `capture_site` builds the
  `route_map` upfront from `--urls` (known before the loop) and passes it down. After `web_skeleton`
  writes the raw `_sk.json` (with `href` + node ids + `aria_role`), `capture_route` reads the anchor
  rows, computes `chrome` from each anchor's nearest `aria_role`-landmark ancestor, calls
  `_nav.resolve_edges`, and returns content-free edges. The hrefs stay in the scratch `_sk.json` (outside
  the tree) and vanish when the scratch `TemporaryDirectory` closes; `bundle_writer` produces the
  redacted `skeleton.json` with no href (`href` is itself a `CONTENT_KEY`, dropped like `text`/`src`).
- **`scripts/_site.py` `build_site_manifest` — aggregate:** collect per-route edges, `dedupe_edges`, add
  `nav_edges` to the manifest written to `site.json`.

## 4. Content-free guarantee (non-negotiable)

- Hrefs are PRE-redaction scratch only (in `_sk.json` inside the system tempdir outside the site tree —
  the exact pattern `site_capture` already documents for `_sk.json`/`_tok.json`). They are resolved
  in-process to route_ids and never written into `route_dir` or `site.json`.
- `site.json` `nav_edges` carry only integers + a boolean (`src/dst/src_node/chrome`).
- `content_firewall.audit_bundle == 0` on the produced bundle including `site.json`.
- **Firewall canary (own test):** seed a resolvable fake href whose value also contains a banned token
  (e.g. a media URL) into the anchor path; assert (i) no href string appears anywhere under the site
  tree, and (ii) the audit trips if a raw href is forced into `site.json` — proving the new field path is
  gated, not exempt (mirrors the G2/scroll-region canary discipline, exercised on the `nav_edges` path
  specifically).

## 5. Testing

- **`_nav` pure unit tests (no browser):** `normalize_url` cases (trailing slash, `www.`, http==https
  treated as distinct hosts only if host differs, query/fragment dropped, non-http→None); `resolve_edges`
  drops self-links, external (unresolved), and same-href→same-route; chrome boolean passthrough; an anchor
  resolving to two routes is impossible (normalized href maps to ≤1 route_id).
- **Chrome-classification unit test:** a fixture skeleton with an anchor under a `navigation` landmark →
  `chrome:true`; an anchor under `main` → `chrome:false`. Uses the real `aria_role`-ancestor walk.
- **Firewall canary** (§4).
- **One manual live smoke** (HOST CDP, not pytest, per `live-cdp-capture-is-manual-harness-not-pytest`):
  re-capture one real multi-route site, assert `nav_edges` non-empty + chrome-dominated + audit clean +
  byte-identical default contract when the feature flag is off.

## 6. Scope cuts (YAGNI / honest)

- **Content-level site graph is OUT** — measured empty by construction (§1). `chrome:false` edges are
  emitted if they occur but no machinery is built around them.
- **Crawl-discovery is OUT** — a separate, larger project (unbounded scope + ships discovered URLs =
  content-free tension). Not this spec.
- **No ordinal / position key** — the skeleton node id is the identity.
- **Feature is additive + opt-in-safe:** `nav_edges` is a new `site.json` field; when anchor extraction
  finds nothing resolvable, it is an empty list. The single-route `web_skeleton` default contract stays
  byte-identical (href extraction only populates the transient scratch field; resolution happens only in
  the `site_capture` path).
