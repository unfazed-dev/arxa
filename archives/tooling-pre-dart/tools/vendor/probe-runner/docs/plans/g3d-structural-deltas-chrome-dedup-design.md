# G3d Structural+Deltas Chrome Dedup — Design / Pre-Registration

**Status:** PRE-REGISTERED (probe not yet run). Outcome (BUILD or DEFER) is bound by the bar
in §6 before any number is observed.

**Goal.** Exact-lossless G3d shared-chrome dedup was DEFERRED at gross median **6.1%** (bar:
median ≥ 12% ∧ ≥3 sites ≥ 15%). The block was that byte-identical-subtree dedup is broken by two
volatile fields — `token_ref.{bg,fg,border}` (a per-route assignment artifact) and `text_len`
(content drift). Re-key the dedup on the **structural fields only**, pay a **lossless delta** for
the volatile fields per instance, and measure whether the net saving now clears the **same bar,
in the same unit**.

**Prior rungs (this is 3rd straight DEFER territory — pre-register the honest DEFER):**
- G3d exact-lossless shared-chrome dedup → DEFER (gross median 6.1%, 5.9% below bar).
- `token_ref` cross-route stability → DEFERRED (G3c L2 collapse; no live cross-route consumer).
- This rung (structural+deltas) must not smuggle the deferred `token_ref`-stability rung back in
  (§7).

---

## 1. Structural key `S(n)`

Reuse the existing `_node_key` / `_subtree` machinery in
`research/capture-gap-probes/probe_g3d_dedup.py` with the **combined** ablation drop set as the
*verdict* key (not a diagnostic):

```
DROP_STRUCT = DROP_TR + DROP_TXT
            = ("token_ref.bg", "token_ref.fg", "token_ref.border", "text_len")

S(n)        = _node_key(n, drop=DROP_STRUCT)
S_subtree(n)= _subtree(n, by_parent, drop=DROP_STRUCT)   # recursive, full depth, emit order
```

The 20-field `_KEY_FIELDS` order is unchanged; the 4 volatile keys are blanked in `S`. Positional
fields (`id`, `parent`, `bbox`, `z`, `confidence`) are **already excluded** from `_KEY_FIELDS` —
they are re-stored per route in **both** the exact and the structural model, so they cancel and
never appear in either saving.

**Why combined, not one-at-a-time:** the two ablation hooks (`DROP_TR`, `DROP_TXT`) already exist
as *diagnostics*. Promoting their **union** to the verdict key is the whole intervention: a subtree
recurs structurally (`occ ≥ 2`) iff it matches on everything **except** the volatile fields. Per-node
delta accounting (§3) then *pays* any volatile field that actually differs — so coarsening the key
does not silently credit volatile instability as free saving.

---

## 2. Tiling — unchanged

Non-overlapping, outermost-wins, exactly as the exact-lossless probe:

- Chrome landmarks: `aria_role ∈ {banner, navigation, contentinfo, complementary}`.
- Pass 1: `occ[S_subtree(n)]` over **all** chrome-landmark subtrees across all routes.
- Pass 2 (`_tile`): walk roots-down; SELECT the outermost chrome landmark whose **structural** key
  recurs (`occ ≥ 2`) and do **not** descend into it (tile boundary — avoids the nested banner⊃nav
  double-count); descend through everything else.
- `m` = count of selected (tiled) instances of a key, **not** raw `occ`.

Only the key changes (structural vs exact). The tiling rule, the chrome set, and the
non-overlapping selection are identical — so any % movement is attributable to the key/cost change,
not the tiling.

---

## 3. Net-savings accounting — **node basis** (the bar's unit)

The denominator is **total nodes across routes** — identical to the exact-lossless probe and to the
6.1% baseline. Do **not** switch to a field-count denominator: the 12%/15% bar and the 6.1% are
node-fractions, and a field denominator would silently redefine the bar's unit post-hoc. The "field
counting" enters only as a **per-node fractional weight**, never as the denominator.

For a structural key `k` with `m ≥ 2` tiled instances, designate one instance as the template
`T_k`. The template is stored once (structural skeleton + its own volatile values). Each of the
`m−1` non-template instances stores, per node, only what differs. Walk the template subtree and the
instance subtree **in lock-step** (`S_subtree` traversal is isomorphic because the structural keys
match) to get node-to-node correspondence.

Per node `n` in a non-template instance `i`:

```
struct_leaves(n)   = # structural leaf scalars of n        (always equal — they ARE the key)
volatile_leaves(n) = # volatile leaf scalars present on n  (⊆ {tr.bg, tr.fg, tr.border, text_len}, ≤4)
D(n)               = struct_leaves(n) + volatile_leaves(n)  # dedup-eligible leaves (positional excluded)

matched_volatile(n,i) = # volatile leaves of n_i byte-equal to T_k's corresponding node
flag_overhead(n)      = volatile_leaves(n) / 64            # 1 equal/differ bit per volatile leaf,
                                                            # 64-bit leaf — PINNED, committed here

saved_node(n,i) = ( struct_leaves(n) + matched_volatile(n,i) − flag_overhead(n) ) / D(n)
```

- All structural leaves are shared (saved): they are the key, always equal.
- A volatile leaf equal to the template → 1-bit flag, value not re-stored → saved.
- A volatile leaf differing → store the value → **not** saved (paid as a lossless delta).
- The 1-bit-per-volatile-leaf flag is the honest cost of the delta scheme and is **subtracted**.

```
saved_key = Σ_{i=1..m−1} Σ_{n ∈ subtree} saved_node(n,i)     # a float in node-equivalents
saved     = Σ_k saved_key   over keys with m ≥ 2
total     = Σ_routes len(nodes)
pct       = 100 · saved / total
```

A **byte-identical** node (all volatile match) → `saved_node = 1 − flag_overhead/D(n) ≈ 1.0`,
recovering the exact-lossless saving (1.0/node) minus a negligible flag. A
**structurally-identical-but-volatile-differing** node → `saved_node = struct_leaves/D(n)` (≈ 0.81,
see §4), recovering only the structural fraction.

---

## 4. Pinned schema reference — committed pre-hoc, NOT tuned

Measured over **1983 real nodes** from `fixtures/**/_bundle/skeleton.json` (the live serialized
schema). These are committed here **before** the run as the source of `D(n)` and as sanity checks;
the probe computes `struct_leaves`, `volatile_leaves`, `D(n)` **per node** from the actual
serialized fields — it does **not** hard-code a scalar weight.

| Quantity | Value | Role |
|---|---|---|
| dedup-eligible leaves `D(n)` | median **15**, mean 16.94, range 15–35 | per-node denominator of `saved_node` |
| structural leaves / `D` (aggregate) | **0.808** | emergent average; **sanity check only**, not an input |
| volatile leaves / `D` (aggregate) | 0.192 | — |
| volatile leaves present per node | mean **3.25**, median 3 (max 4) | `token_ref.{bg,fg,border}` + `text_len` |
| nodes with any non-null `token_ref` color | 913 / 1983 | volatile-presence sanity |
| nodes with `text_len` | 502 / 1983 | volatile-presence sanity |

Positional/excluded leaves per node (re-stored in both models, cancelled): `id`, `parent`, `z`,
`confidence`, `bbox.{x,y,w,h}`, `sizing.confidence`. Volatile leaves (paid as deltas): exactly the
4 in `DROP_STRUCT`. Everything else dedup-eligible is structural.

**A global `w_struct=0.808` scalar must NOT be used as the per-node weight** — it would break the
pointwise-domination guarantee in §5 (it would over-credit nodes whose actual structural share is
lower and under-credit nodes whose volatile fields all match). Use per-node `D(n)`.

---

## 5. Pointwise domination — guarantees median ≥ exact baseline

**Claim.** Structural+deltas ≥ exact-lossless pointwise (modulo the pinned flag overhead), so its
median is ≥ the in-run exact median. The open question is only whether the **extra** structural
matches push it from ~6% to ≥ 12%.

**Argument.**
1. Every exact match is a structural match (byte-identical ⟹ structurally identical) with
   `saved_node ≈ 1.0` — equal saving minus the negligible flag.
2. Structural matching admits **strictly more** recurring keys: subtrees that differ *only* in
   volatile fields now recur (`occ ≥ 2`), contributing `struct_leaves/D ≈ 0.81` per node where exact
   contributed 0.
3. **Divergence case (must hold, verify in probe):** when structural tiling selects an *outer*
   banner that exact tiling did not, an inner byte-identical `nav` nested inside it still scores
   `≈ 1.0/node` *within* the structural tile. So expanding the tile boundary does not lose the inner
   exact saving — structural ≥ exact even on re-tiled regions.

**Flag drag is bounded relative to the saving, not to total.** Per saved node the flag is
`volatile_leaves/64 ≤ 4/64 = 0.0625` node-equiv against a per-node saving of `≥ struct_leaves/D ≈
0.81` — so flags shave `≤ ~8%` off the *structural saving*, i.e. `struct_pct` is within ~8% relative
of `struct_pct_noflag`. As a fraction of **total** nodes the flag is **not** a fixed 0.4% — it
scales with the dedup rate, so a high-saving site has a proportionally larger raw flag total. The
flag is already **subtracted inside** `saved_node`; the probe reports `struct_noflag` and
`flag/saved%` so the drag is transparent (§8). It is therefore **never a gating invariant** — gating
on a raw `flags/total` threshold would wrongly withhold a high-saving BUILD verdict.

---

## 6. Pre-registered bar — identical to exact-lossless (continuity)

```
BAR = { median: 12.0, site_pct: 15.0, min_sites_at: 3, min_data: 4 }   # node-fraction unit
```

**BUILD G3d structural+deltas dedup** iff structural **net** median pct ≥ 12 **AND** ≥ 3 sites with
pct ≥ 15%. Otherwise **DEFER**.

Same 6 sites (`python.org`, `iana.org`, `djangoproject.com`, `w3.org`, `gnu.org`, `apache.org`),
4 routes each, content-firewall-clean only, ≥ 4 sites must yield data or the run is INCONCLUSIVE
(re-run). Same unit (node-fraction) and same thresholds as the exact-lossless rung — so the two
verdicts are directly comparable.

---

## 7. Coherence position (advisor pin #2) — honesty on iana / django

On `iana.org` and `djangoproject.com` the only structural-over-exact gain is the `token_ref`
per-route artifact subtrees (exact 3/3/3 on python proved the L2 collapse is real specificity, not
noise). Under per-node delta accounting their differing `token_ref` leaves are **paid as deltas,
not credited free** — those subtrees recover only `struct_leaves/D ≈ 0.81` per node, never 1.0.

Therefore structural+deltas does **not** re-admit the DEFERRED `token_ref`-cross-route-stability
rung: the artifact is paid for honestly, per node, every instance. iana/django are expected to stay
**modest** (≈ structural fraction of ~2 small keys). If that drives the overall DEFER, the DEFER is
the correct, coherent outcome — not a flaw to tune away.

---

## 8. Probe mechanics

**File:** create `research/capture-gap-probes/probe_g3d_structural.py`, a sibling that imports and
reuses the exact-lossless probe's primitives (`_capture`, `C._children`, `_node_key`, `_subtree`,
`_tile`, `_roots`, `_median`, `SITES`, `CHROME`, `cf.audit_bundle`). No edit to
`probe_g3d_dedup.py` — keep the exact-lossless verdict frozen.

**Both metrics on the same in-run capture.** Captures are ephemeral tempdirs; absolute % may drift
slightly from the 2026-06-02 run. So for each site, on the **same** captured route lists, compute:
- `exact_pct` — recompute the existing exact-lossless `_site_savings` (saved = `(m−1)·size`, node
  basis). This is the **in-run baseline**; drift vs 6.1% is re-capture only, the unit is unchanged.
- `struct_pct` — the §3 per-node delta accounting on `S`-keyed tiles.

Reporting `struct_pct − exact_pct` per site makes the domination (§5) visible and isolates the
key/cost change from capture drift.

**Per-node leaf classification** (drives `struct_leaves` / `volatile_leaves` / `D`): walk each
node's serialized leaf scalars; `bbox.*`, `id`, `parent`, `z`, `confidence`, `sizing.confidence` →
positional (excluded); `token_ref.{bg,fg,border}`, `text_len` → volatile; all else → structural.

**Retain the field-ablation diagnostic** (`_recurring_under(lists, DROP_TR/DROP_TXT)`) to keep
attributing which volatile field drives the recurrence delta.

**Verify in-run:**
- **Hard invariant (the only gate):** `struct_pct ≥ exact_pct − 0.5` per site (pointwise domination
  modulo the pinned flag). A violation means the accounting has a bug → the probe prints
  `!! INVARIANT DOMINATION` and **WITHHOLDS** the verdict (exit 3); the bar is not read until the
  accounting is fixed.
- **Reported, never gated:** `struct_noflag` and `flag/saved%` (flag drag as a fraction of the
  saving, ≤ ~8% per §5). Do **not** gate on `flags/total` — it scales with the dedup rate, so gating
  it would wrongly withhold a high-saving BUILD.

---

## 9. Pre-registered outcomes

- **BUILD** iff §6 bar met. Then: implement structural-template + per-route lossless-delta chrome
  dedup before core-file build.
- **DEFER** (the honest, pre-committed default given 3-straight-DEFER territory): structural net
  savings below 12% / fewer than 3 sites ≥ 15%. Record the verdict, the per-site
  `exact_pct` / `struct_pct` / delta table, and the iana/django coherence note (§7). Do **not**
  re-key or re-tile to chase the bar post-hoc — that would un-pre-register the probe.
- **INCONCLUSIVE** — < 4 sites with firewall-clean data. Re-run, no verdict.
