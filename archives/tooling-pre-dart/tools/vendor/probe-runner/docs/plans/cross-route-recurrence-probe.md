# Cross-route recurrence probe — plan

**Type:** empirical investigation (NOT a feature build). No production code, no new
gated CLI. Throwaway probe script + a findings section. De-risks **G3b** (cross-route
token merge) before its spec is written, per design §1.2 ("the real unknown is
recurrence, and it is deferred — runs on G3a's output after G3a lands, before G3b").

## Question

Given G3a output (`routes/<id>/tokens.json` + `skeleton.json` across N same-host
routes), **do design tokens actually recur across routes, and in what shape?** The
answer dictates G3b's merge model:

- **High shared core, low per-route delta** → merge = *intersection-as-core + deltas*.
- **Mostly union, little overlap** → routes are near-independent; "merge" is a union
  with provenance, not a unified system.
- **Role keys stable but VALUES drift** (likely — colors rarely byte-identical across
  captures/routes) → merge must operate on *clustered* values, not exact match.

## Scope

- **Primary: token recurrence** (directly feeds G3b, the immediate next build).
  Per category — `palette` (by role key AND by value), `type_scale`, `families`,
  `weights`, `spacing`, `radii`.
- **Secondary: a coarse STRUCTURAL recurrence hint** from `skeleton.json` (tag/role
  **set** presence overlap across routes — NOT multisets, which are content-volume
  sensitive: more body text → more nodes → lower Jaccard for non-design reasons) — a
  cheap G3c preview, not component synthesis.
- **Out of scope:** building any merge; layout reconciliation; component signatures.

## Metrics (per token category, across the N ok-routes)

- `distinct` — count of distinct values seen anywhere.
- `core` — count present in **all** N routes (the mergeable shared system).
- `shared_ge2` — count present in **≥2** routes.
- `unique` — count present in exactly **1** route (per-route delta).
- `mean_pairwise_jaccard` — mean over route pairs of |A∩B| / |A∪B|.
- For `palette`: measure twice — by **role key** (background/accent/…) and by **value**
  — to expose the key-stable / value-drift case explicitly. Also report a
  **near-match** variant: cluster palette values within the existing `web_tokens`
  color tolerance (ΔRGB ≤ 8, the `cluster_colors` tol) before overlap, since exact-hex
  recurrence will undercount a real shared palette.

## Calibration — the noise floor (FIRST, blocking)

**Critical confound (advisor):** this measures recurrence of `web_tokens` *output*, not
site design-system recurrence. `web_tokens` samples *rendered* colors and clusters them
(`assign_roles`, tol=8) — different page CONTENT on identical CSS can still perturb which
values get sampled/clustered. So a low real-site score could be extraction noise, not
real divergence — and that confound would flow straight into a wrong G3b call. **Measure
the floor before interpreting any real number.**

Two floors, both cheap:

- **Floor A — extraction determinism:** capture one real URL **twice** → recurrence
  should be ≈ 1.0. Any gap is pure capture nondeterminism.
- **Floor B — content-perturbation on identical CSS (the real-route confound):** serve
  two pages with byte-identical `:root`/`body` CSS but different body content (the
  synthetic `/` + `/pricing` fixture already in `run_site_capture.py` is exactly this),
  capture both, measure. Score < 1.0 here means different-content-same-CSS perturbs
  `web_tokens` — the floor every real-site number is read against.

Real-site recurrence is only interpretable as *design* recurrence **above** Floor B.

## Targets

Capture via existing `site_capture.py` (host CDP; Chrome on :9222 already up) into
tempdirs OUTSIDE the repo tree. Keep it cheap — **one** rich site + the control + iana:

1. **Control:** Floor A + Floor B captures (above).
2. A docs/marketing site with ≥4 same-host routes sharing an obvious design system
   (primary real signal).
3. `www.iana.org` 3 routes (a real target, already proven to capture clean — **not** a
   control; it has no ground truth).

Explicit URL lists only (G3a's contract). Same-host, no-login, cacheable. Record which
host; never persist third-party page content.

## Content-free posture

- The probe READS `tokens.json` (design tokens are probe-runner's legitimate persisted
  extract) and `skeleton.json` (structural, already content-free).
- The probe REPORT emits **counts / ratios / booleans / role-key names only** — never a
  dump of hex values or font-size lists. Role KEY names (background/accent/…) are
  probe-runner's own vocabulary, not site content.
- Never echo `site_capture` subprocess stderr. After capture, run
  `content_firewall.audit_bundle(site_root)` and assert CLEAN before analysing.
- Probe runs against tempdir captures; nothing third-party committed.

## Cross-route state-bleed control

Documented G3a ceiling: the reused browser's cookies/localStorage persist across
routes, which can skew recurrence. The probe must **note** whether this plausibly
affected a target (e.g., a consent overlay appearing only on r00). Not fixing it here;
flagging it as a confound in the findings so G3b's design accounts for it.

## Deliverables

1. `research/capture-gap-probes/probe_token_recurrence.py` — pure analysis over a
   captured site dir; prints content-free recurrence metrics. (Investigation artifact;
   committed alongside findings per the existing `research/capture-gap-probes/` pattern.)
2. A **findings** section appended to `docs/plans/probe-runner-engine-capture-gaps.md`
   (`§C9-R-G3a-probe`) recording the empirical recurrence shape per target + the
   resulting **G3b merge-model recommendation** (intersection-core vs union; exact vs
   clustered; key-stable/value-drift handling).

## Verification (this is empirical, not TDD)

- Ran on ≥2 real same-host multi-route sites; per-target on-disk capture audit CLEAN.
- Metrics internally consistent (`core ≤ shared_ge2 ≤ distinct`; jaccard ∈ [0,1]).
- iana control shows expected high recurrence (sanity floor on the metric).
- Findings name a concrete G3b merge model, with the value-drift / clustering decision
  made on evidence.

## Commits

Single-line, no trailers. One commit for the probe script + plan; one for the findings
section. Stage explicit paths only. No push.
