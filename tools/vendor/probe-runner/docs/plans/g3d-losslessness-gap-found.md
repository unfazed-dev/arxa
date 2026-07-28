# G3d chrome-dedup is NOT lossless on real captures — finding (2026-06-02)

> **STATUS: RESOLVED (2026-06-02, branch `wire-post-processors`).** Fixed by the by-construction
> charge (`_reconstruct_node` + `_node_patch` → `exceptions`+`drop`) per
> `docs/plans/g3d-losslessness-fix.md`. Commits: `6c5f023` (core), `0b9d11d` (real-skeleton
> regression fixture), `e0df4aa` (serialize `drop`), `2f39342` (reconcile asserts node bytes +
> charges `drop`). Live re-measurement: all 6 sites now node-set lossless, realized median 15.5%
> (BUILD verdict stands — the dropped data was 2 `style` fields on python.org, negligible). See the
> "Lossless re-measurement" section of `docs/plans/g3d-structural-deltas-chrome-dedup-results.md`.

**How found:** live end-to-end smoke of the `site_capture --merge --dedup` wiring (branch
`wire-post-processors`) against a real 2-route python.org capture on CDP :9222. The wiring behaved
correctly — capture ok (2/2 routes), `--merge` → `design_system.json` ok, `--dedup` → **error,
exit 2**, folded loud to `site_capture` exit 1 (`ok:false`). Running `site_chrome.py` directly:
`probe-runner: round-trip not byte-identical — dedup would be lossy; refusing to write` (exit 2).
The fail-closed self-check worked: **no data was corrupted**; the artifact was simply refused.

## Root cause (verified)

`scripts/_chrome_dedup.py` claims (module docstring, line 7-8): *"Lossless by construction: any field
that does not derive from the template is stored as a per-instance exception (charged), never
dropped."* The implementation does **not** honor this. `_diff_nonpositional` (line 277) charges only
**four** fields as exceptions: `id`, `parent`, `z`, `confidence`. Any node field that is:

- NOT one of the 20 `_KEY_FIELDS` (so it doesn't affect the structural key), **and**
- NOT a volatile leaf (`token_ref.bg/fg/border`, `text_len`), **and**
- NOT positional (`id/parent/z/confidence`), **and**
- NOT `bbox` (overridden per-instance)

...is taken verbatim from the template on `reconstruct()` and **silently dropped** if the instance's
value differs.

**Concrete instance:** python.org home vs `/about/`, route r01 nodes id 54/55. Both routes' nav
landmark keys identically (structural key excludes `style`), so they collapse to one template. The
home node's `style` lacks `background-image`; the `/about/` node's `style` carries
`background-image: linear-gradient(rgb(43,91,132) 10%, rgb(36,78,113) 90%)`. Reconstruct emits the
template's `style` → the gradient is lost → round-trip not byte-identical. `style` is legitimate
firewalled design data (computed CSS), not page content.

The bug is **general**: `tag` is also un-keyed (per `test_chrome_dedup` comments) and would be lost
the same way if it varied between structurally-identical instances. Any non-handled field varying
across instances triggers it.

## Why the test suite + reconcile missed it

- `scripts/test_chrome_dedup.py` proves byte-identity, but only on **synthetic** fixtures
  (`_nav_route` etc.) whose nodes carry no `style`/extra fields — so no un-handled field ever varies.
- `research/capture-gap-probes/reconcile_g3d_chrome.py` (the "RECONCILED 15.5%" gate) asserts only
  `D.reconstruct(art).keys() == routes.keys()` — **route-id keys, not node bytes**. It never
  round-tripped real node content. So the "RECONCILED 2026-06-02" verdict in
  `docs/plans/g3d-structural-deltas-chrome-dedup-results.md` measured a savings number that is **not
  losslessly achievable** on real captures as the encoder stands.

## Impact / magnitude (honest, under-measured)

- The `wire-post-processors` branch is **correct and unaffected** — it does not introduce this bug; it
  exposed it, and handles it exactly right (fails loud, default-OFF, `--merge` works on real sites).
- On python.org the lossless residual looks **small** (one node pair, one CSS property) → charging
  the residual `style` diff as an exception would likely keep savings well above the floor. But this
  is **one site**; the other 5 reconcile sites were never byte-round-tripped. Magnitude across sites
  is **unknown** until re-measured.

## Fix direction (for whoever takes the G3d correction — NOT done here)

Make `_diff_nonpositional` (or a new pass) honor the docstring's contract: for each instance node,
charge into `exceptions` **every** top-level key whose reconstructed-from-template value would differ
from the instance value, excluding only the keys `reconstruct` already overrides (id, parent via
re-basing; bbox; the volatile leaves). Handle whole-key add/remove, not just value changes. Then
re-run a **byte-level** reconcile (fix the harness to compare node-sets, not `.keys()`) across all 6
sites and record the real lossless savings — which will be ≤ the current bbox-only numbers. If it
drops below the pre-registered bar, that re-opens the G3d BUILD verdict (a separately-registered
decision, the user's call).

## Provenance

- Repro capture: `/tmp/wire-smoke` (python.org home + /about/, CDP :9222).
- Core: `scripts/_chrome_dedup.py:277` (`_diff_nonpositional`), docstring claim at lines 7-8.
- Self-check that correctly caught it: `scripts/site_chrome.py:68-73`.
