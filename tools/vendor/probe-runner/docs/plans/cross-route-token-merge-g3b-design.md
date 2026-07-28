# G3b — cross-route token merge — design spec

**Goal:** from a G3a capture (`site.json` + `routes/<id>/tokens.json` across N routes),
emit one content-free **unified design system** — per-role palette + per-category
scalars, each as frequency-annotated distinct tokens. Descriptive, not prescriptive.

**Grounding:** recurrence probe `§C9-R-G3a-probe`. Merge on **role keys**, not raw
values (keys recur ≈1.0, values drift); **report exact AND clustered** palette values
(clustering is a tunable, not a baked-in correction); **core + per-route deltas with
frequency**; measure value recurrence **per role**.

---

## §1 — Architecture / surface

- **Pure core `scripts/_merge.py`** — no I/O, no CDP, unit-tested in isolation (mirrors
  `_site.py` / `_theme.py` / `_style.py`).
- **Thin CLI `scripts/site_merge.py`** — reads a captured site dir, calls the core,
  writes the artifact, runs the firewall backstop.
- **Input:** `--site <capture dir>`. Reads `<dir>/site.json`; for each route with
  `ok == true`, reads `<dir>/routes/<route_id>/tokens.json`.
- **Output:** `design_system.json`, default `<dir>/design_system.json`; `--out` override.
  Schema id `probe-runner/design-system@1`.
- **`--cluster-tol N`** (default 8) — Chebyshev ΔRGB tolerance for the clustered palette
  view; reuses the real `web_tokens.cluster_colors`.
- **`site_capture.py` is UNCHANGED.** Merge is a separate pass, re-runnable on any
  existing capture without re-launching the browser.

## §2 — Per-route inputs

`tokens.json` (flat shape, web_tokens spec §5.2):
- `palette`: `{role: hexstring}` over the six roles `background`, `surface`,
  `fg-primary`, `fg-muted`, `accent`, `border`. A role may be absent or its value `null`.
- scalar lists: `type_scale`, `weights`, `families`, `spacing`, `radii`, `shadows`.

A route contributes a value to a role/category only when present and non-null.

## §3 — Merge model (`_merge.py`)

### §3.1 Frequency entries (shared helper)
`_freq_entries(value_to_route_ids: dict, n: int, key: str = "value") -> list` — given a
map of value → sorted list of route_ids that carry it, return entries
`{key: value, "routes": len(ids), "route_ids": sorted(set(ids)), "core": len(ids) == n}`,
sorted by `routes` desc then `str(value)`. `core` is true iff present in **all N** merged
routes. The `key` parameter names the value field: **`"value"` everywhere except the
`families` scalar category, which uses `"family"`** (see §3.3 / §6 for why — it keeps font
stacks under a content-firewall-exempt key, exactly as `tokens.json` stores them).

### §3.2 Palette (per role)
`merge_palette(per_route_palettes, cluster_tol) -> {role: {"exact":[...], "clustered":[...]}}`
- `per_route_palettes`: list of `(route_id, {role: hex|None})`.
- For each of the six roles, gather `{route_id: value}` over routes that have it.
- **`exact`:** `_freq_entries` over distinct exact hex values for that role.
- **`clustered`:** reuse `web_tokens.cluster_colors`:
  1. Build samples `[(hex, freq)]` where `freq` = number of routes carrying that hex
     for this role (area = frequency, so the most-frequent shade seeds its cluster,
     matching cluster_colors' deterministic largest-first order).
  2. `cluster_colors(samples, tol=cluster_tol)` → representative hexes.
  3. Assign each route's role value to the nearest representative within `cluster_tol`
     (Chebyshev); accumulate route_ids per representative.
  4. `_freq_entries` over `{rep_hex: route_ids}`.
- Per-role by construction (finding #4b): values are aligned within the same role slot
  before any clustering; a `#3b82f6` in `accent` never merges with a `#3b82f6` in `border`.

### §3.3 Scalars (per category)
`merge_scalars(per_route_scalars) -> {category: [freq entries]}`
- `per_route_scalars`: list of `(route_id, {category: [values]})`.
- For each of the six categories, map value → route_ids over routes that list it,
  then `_freq_entries`. **Exact only** — no clustering (numbers/strings; the probe showed
  scalar cores are genuine, not jitter).
- **`families` uses `key="family"`; all other categories use `key="value"`.** Font stacks
  are the one prose-shaped token value (e.g. `"Helvetica Neue, Arial, Liberation Sans"`).
  The content firewall exempts the keys `{family, families, font, font_family, fontFamily}`
  from prose detection (font stacks legitimately look like prose). `tokens.json` stores
  families under the exempt `families` key. In the merged artifact the value sits inside a
  freq-entry dict, and `content_firewall._walk_strings` keys a string by its **immediate
  dict key** — so a `"value"` key would lose the exemption and a long keyword-less stack
  would FALSE-POSITIVE the audit (`exit 3`) even though it passed at capture time. Using
  `"family"` keeps the exemption and restores exact clean-in→clean-out parity. Palette
  values (hex) and the numeric scalars are never prose-shaped, so they keep `"value"`.

### §3.4 Top-level assembly
`build_design_system(per_route, hosts, cluster_tol) -> dict`
- `per_route`: list of `(route_id, tokens_dict)` for the merged (ok, readable) routes.
- Returns:
```json
{
  "schema": "probe-runner/design-system@1",
  "hosts": ["www.python.org"],
  "merged_route_count": 4,
  "route_ids": ["r00", "r01", "r02", "r03"],
  "cluster_tol": 8,
  "palette": {
    "background": {
      "exact": [
        {"value": "#ffffff", "routes": 4, "route_ids": ["r00","r01","r02","r03"], "core": true},
        {"value": "#0b0b0b", "routes": 1, "route_ids": ["r02"], "core": false}
      ],
      "clustered": [
        {"value": "#ffffff", "routes": 4, "route_ids": ["r00","r01","r02","r03"], "core": true}
      ]
    },
    "surface": {"exact": [], "clustered": []},
    "fg-primary": {"...": "..."}, "fg-muted": {"...": "..."},
    "accent": {"...": "..."}, "border": {"...": "..."}
  },
  "scalars": {
    "type_scale": [
      {"value": 16, "routes": 4, "route_ids": ["r00","r01","r02","r03"], "core": true},
      {"value": 48, "routes": 1, "route_ids": ["r02"], "core": false}
    ],
    "families": [
      {"family": "system-ui, sans-serif", "routes": 4, "route_ids": ["r00","r01","r02","r03"], "core": true}
    ],
    "weights": [], "spacing": [], "radii": [], "shadows": []
  }
}
```
- `hosts` and `route_ids` come from `site.json` (ok routes only). All six palette roles
  and all six scalar categories are ALWAYS present as keys (empty list when no route
  contributed) — stable shape for consumers. NOTE the deliberate asymmetry: `families`
  entries name their value field `"family"` (firewall-exempt key, §3.3); every other
  category uses `"value"`.

## §4 — CLI (`site_merge.py`)

1. Parse `--site` (required), `--out` (default `<site>/design_system.json`),
   `--cluster-tol` (default 8).
2. Load `<site>/site.json`; collect ok routes whose `routes/<id>/tokens.json` exists and
   parses. Track `merged_route_count`, `route_ids`, `hosts`.
3. If **0** mergeable routes → `die("no mergeable routes", 2)`.
4. `build_design_system(...)`; write JSON to `--out`.
5. **Firewall backstop:** `content_firewall.audit_bundle(Path(out).parent)` — re-audits
   the output (and, when out is in the site dir, the route bundles). On any violation:
   `emit_json({"ok": False, "error": "content_audit_failed", "out": out})` and **exit 3**
   (mirrors `bundle_writer`); print violation **kind + count only**, never the sample.
   NOTE: the backstop scans the output's PARENT dir, so `--out` must be the capture dir
   or an isolated/empty path — a populated unrelated dir would be over-scanned (false
   positive). The canary test exploits this deliberately: it writes to an isolated empty
   dir so the trip is attributable to `design_system.json` itself, proving the new
   persistence surface is actually audited.
6. Success: `emit_json({"ok": True, "out": out, "merged_route_count": n})`, exit 0.

## §5 — Scope (YAGNI; decided)

- **Tokens only.** No structural/component section — that is G3c. The probe's role-set
  finding stays documented, not built.
- **Descriptive, not prescriptive** — frequencies only; no single "winner" value chosen.
  The consumer (a future generator, G3c, G3d) thresholds.
- **N = 1** is valid (every token `core`, freq 1). **N = 0** mergeable → exit 2.
- Clustering applies to the **palette only**; scalars are exact.
- `motion.json` / `substrate.json` / `states.json` do **not** merge (per-route, per the
  G3a design ceiling).

## §6 — Content-free posture (PRIME)

- `design_system.json` carries hex values + numeric sizes + role/category **names** +
  counts + positional route_ids — **the same token surface `tokens.json` already
  persists**. No new content class is introduced; the content firewall is **unchanged**.
- Backstop proves (not asserts) it: §4 step 5 audits the emitted file via the existing
  `audit_bundle`. Two tests pin it:
  - **Canary** — prose injected into a **palette** value flows into `design_system.json`
    under a `"value"` key (NOT exempt) → the unchanged firewall trips → `exit 3`, no sample
    printed. (The canary must target palette, not families: families now sits under the
    exempt `"family"` key per §3.3, so prose there is intentionally allowed — same as
    `tokens.json`.) Writing to an isolated empty `--out` dir makes the trip attributable to
    `design_system.json` itself, proving the new surface is scanned.
  - **Families regression** — a long keyword-less stack `"Helvetica Neue, Arial, Liberation
    Sans"` in `families` → `exit 0` (CLEAN), locking the §3.3 exempt-key fix so the
    false-positive bug cannot regress.
- Failure paths print returncode / error kind / violation count **only** — never a
  content sample, never subprocess stderr.

## §7 — Error handling / exit codes

| Condition | Behaviour |
|-----------|-----------|
| `--site` missing / `site.json` absent or invalid | `die(msg, 2)`, content-free |
| 0 mergeable ok routes | `die("no mergeable routes", 2)` |
| firewall violation on output | `emit_json` error + **exit 3**, kind+count only |
| success | `emit_json` ok, exit 0 |

A single route's unreadable `tokens.json` is **skipped**, not fatal (mirrors G3a's
per-route isolation) — it simply does not contribute to the merge.

## §8 — Testing

**Pure `_merge.py` units (`test_merge.py`):**
- `_freq_entries`: counts, `core` true only at all-N, sort order.
- `merge_palette` exact: two routes, same role different hex → 2 distinct exact entries,
  neither core; same hex in both → 1 entry, core.
- `merge_palette` clustered: two near hexes within tol → merge to one clustered entry
  spanning both routes (`core`); two hexes beyond tol → stay separate.
- per-role isolation: identical hex in different roles never merges.
- `merge_scalars`: frequency + core; exact only; **`families` entries carry the `"family"`
  key (firewall-exempt), every other category carries `"value"`**.
- `build_design_system`: all six roles + six categories always present; N=1 degenerate
  (all core); top-level fields correct.

**CLI (`test_site_merge.py`):**
- Synthetic capture dir (hand-written site.json + routes/r00,r01 tokens.json) → run
  `site_merge`, assert schema, shape, a known core/delta split.
- Skips an unreadable route's tokens.json without aborting.
- 0 mergeable routes → exit 2.
- **Canary (palette):** prose in a synthetic `tokens.json` **palette** value → firewall
  trips → exit 3, no sample in stdout/stderr (artifact written to an isolated `--out` dir).
- **Families regression:** a long keyword-less stack `"Helvetica Neue, Arial, Liberation
  Sans"` in `families` → exit 0 (CLEAN), proving the exempt-key fix.

**Real-site validation harness `fixtures/site/validate_merge.py`** (host, content-free):
- Given `--site <real capture>` (e.g. a python.org / iana G3a capture), run `site_merge`,
  assert `audit_bundle` CLEAN, print content-free merge stats (per-role core/exact/
  clustered counts, per-scalar core/distinct counts) — never echo values or stderr.

## §9 — Verification

- Full unit suite green (existing 433 + new).
- Firewall canary trips (exit 3, no sample leaked).
- Real-site merge on ≥1 host: `audit_bundle` CLEAN, stats internally consistent
  (`core ≤ distinct`; clustered distinct ≤ exact distinct per role).

## §10 — Ceilings

- Clustered assignment maps each route value to the nearest cluster representative; in
  rare greedy-order ties this can differ marginally from `cluster_colors`' own internal
  membership. Deterministic and documented; exact view is always reported alongside.
- Cross-route cookie/storage bleed (G3a ceiling) can shift a route's captured tokens
  (e.g. a consent overlay) — the merge faithfully reflects whatever was captured; it does
  not correct for it.
- `route_id` is positional (G3a) — `route_ids` in the artifact are stable within one
  capture, not across re-captures with a reordered URL list.
- Two-host empirical grounding only (the probe); merge model is descriptive, so it does
  not over-fit, but population-scale validation is future work.
- **Schema asymmetry:** `families` freq-entries use the value field `"family"` while every
  other category uses `"value"` (§3.3) — required to keep font stacks under a
  content-firewall-exempt key (else a long keyword-less stack would false-positive the
  audit). Consumers must read `entry.get("family") or entry.get("value")` for families.

## §11 — Commits

Single-line, no trailers. One commit per task; review-driven fixes their own commit.
Stage explicit paths; never `git add -A`. No push. Plans/specs live in `docs/plans/`.
