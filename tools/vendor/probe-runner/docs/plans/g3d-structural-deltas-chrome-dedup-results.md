# G3d Structural+Deltas Chrome Dedup — Results (live run)

**Run:** 2026-06-02, host Bash, CDP Chrome :9222, 6 sites × 4 routes, all firewall-clean.
**Probe:** `research/capture-gap-probes/probe_g3d_structural.py`.
**Pre-registration:** `docs/plans/g3d-structural-deltas-chrome-dedup-design.md` (bar + accounting + DEFER
all committed before this run).

## Verdict: **BUILD** (exit 0)

`struct_median_pct = 17.5 ≥ 12` **AND** `sites ≥ 15% = 3/6 ≥ 3`. Bar met. No invariant violation,
no INCONCLUSIVE. `floor_a_determinism = True`.

**All percentages are GROSS** — positional fields (id/parent/bbox/z) are re-stored per instance and
**not** subtracted, identical to the exact-lossless 6.1% baseline and the 12% bar. So the
verdict comparison is gross-vs-gross and internally consistent. Net savings (after per-reference
positional restoration) is **lower and not quantified here** — a Phase-2 build detail.

| site | exact_pct | struct_pct | Δ | struct_noflag | flag/saved | dom_ok | ablation full/noTR/noTXT | ≥15% |
|---|---|---|---|---|---|---|---|---|
| python.org | 8.7 | 12.8 | +4.1 | 13.4 | 5.3% | ✓ | 3/3/3 | |
| iana.org | 0.0 | 22.2 | +22.2 | 23.4 | 5.7% | ✓ | **0/2/0** | ✓ |
| djangoproject.com | 0.0 | 12.0 | +12.0 | 12.6 | 5.6% | ✓ | **0/2/0** | |
| w3.org | 19.6 | 29.7 | +10.1 | 31.2 | 5.1% | ✓ | 5/5/6 | ✓ |
| gnu.org | 3.6 | 7.2 | +3.6 | 7.6 | 5.5% | ✓ | 3/3/4 | |
| apache.org | 15.7 | 28.2 | +12.5 | 29.8 | 5.7% | ✓ | 2/2/2 | ✓ |

In-run exact median ≈ **6.15%** (sorted 0,0,3.6,8.7,15.7,19.6) — reproduces the prior exact-lossless
DEFER (6.1%), confirming the only change is the key/cost, not capture drift. Structural lifts the
median to **17.5%**; every site has a strictly positive delta (+3.6 to +22.2).

## Invariants (all held on real data)

- **Pointwise domination:** `dom_ok = True` on all 6 sites — the occ-monotonicity lemma (structural
  occ ≥ exact occ ⟹ tile boundary at-or-outside exact's ⟹ struct ≥ exact) holds empirically. The
  design §5 claim is confirmed, not just argued.
- **Flag drag:** `flag/saved` 5.1–5.7% everywhere (≤ ~8% per §5). `struct_pct` is net of flags; the
  bar is cleared on the net number.

## §7 honesty reconciliation (iana / django)

The design pre-registered that on iana/django the structural-over-exact gain is the `token_ref`
per-route artifact, and that its differing `token_ref` must be **paid as a delta, not credited
free**. The ablation confirms the mechanism exactly: both sites are `full=0` (zero recurrence on the
exact key) and recur **only** under `noTR=2` (drop `token_ref`), with `noTXT=0` (`text_len` is not
the driver). So the savings are token_ref-artifact subtrees — and the per-node accounting paid them
honestly: `struct_pct < struct_noflag` and each such node scored the **structural fraction
(~0.81/node)**, never 1.0. This is legitimate lossless saving (store the structural skeleton once,
pay `token_ref` deltas per route); it does **not** re-admit the DEFERRED `token_ref`-cross-route-
stability rung (which would claim `token_ref` itself dedups).

One deviation from the design's *prediction*: §7 guessed iana/django would stay "modest." iana came
in **high (22.2%)**, django at the bar (12.0%). The pre-registration bound the **method** (pay
deltas honestly) — which was honored — not the predicted magnitude. The conservative guess was wrong;
the honesty constraint was not bent.

**Load-bearing check for the verdict:** the `≥3 sites ≥15%` condition is met by iana (22.2,
artifact-driven), w3 (29.7, `full=5` — genuine full-key recurrence), apache (28.2, `full=2` — genuine
byte-identical). Two of the three qualifiers (w3, apache) are real full-key recurrence; iana is the
artifact-driven third and is load-bearing for the count. The median (17.5) is comfortably clear
regardless. The verdict rests on legitimate structural savings, with iana's contribution paid
honestly as deltas.

## Capture-setup note (not a probe issue)

First live run returned `ok_routes=0` / `skeleton_failed` on every site: the CDP Chrome on :9222 had
**zero page targets** (`_web.cdp_target` → "no Chrome page targets"). Fix: open one blank page target
(`PUT http://127.0.0.1:9222/json/new?about:blank`); `web_skeleton` navigates that single target per
route, so one tab suffices for all routes. Re-run succeeded. This is an environment precondition for
any `--cdp-port` capture, not a defect in the probe or the accounting.

## Next (design §9 BUILD path)

Implement structural-template + per-route lossless-delta chrome dedup before the core-file build:
store one structural-keyed chrome template per recurring landmark; per route, store positional
fields (id/parent/bbox/z) + the lossless `token_ref`/`text_len` deltas (equal→1-bit flag,
differ→value).

**Gross chrome saving ≈ measured `struct_pct` (median ~17.5%). NET is lower** — the per-route
positional restoration (id/parent/bbox/z, re-stored per instance) is not subtracted in `struct_pct`,
exactly as in the exact baseline.

## NET measured (Phase-2 gate — RESOLVED 2026-06-02)

`probe_g3d_net.py` charges positional per node and reports **two bounds** (the encoding choice
straddles the bar, so a single number would be misleading):
- **FLOOR** — every positional leaf re-stored per node, even internal structure (pessimistic):
  `net_floor_node = (struct + matched_vol − flag)/F`, F = all leaves.
- **BBOX-ONLY** — `id` re-baseable, `parent`/`z`/`confidence`/`sizing.confidence` are structure → in
  the template; only `bbox` varies per node (realistic): `net_bbox_node = (struct + nonbbox_pos +
  matched_vol − flag)/F`. Same tiling, same volatile-matching, same node-count denominator as gross.

| site | gross | net FLOOR | net BBOX-ONLY |
|---|---|---|---|
| python.org | 12.8 | 8.8 | 11.1 |
| iana.org | 22.2 | 15.3 | 19.6 |
| djangoproject.com | 13.7 | 9.5 | 12.0 |
| w3.org | 29.7 | 20.8 | 25.8 |
| gnu.org | 7.2 | 5.1 | 6.3 |
| apache.org | 28.2 | 19.5 | 24.9 |

**FLOOR median = 12.4%, 3/6 sites ≥15% (iana 15.3, w3 20.8, apache 19.5). BBOX-ONLY median = 15.8%,
3/6 ≥15%.** Both clear the pre-registered bar (median ≥12 ∧ ≥3 sites ≥15).

**Verdict: BUILD survives on NET.** Lead with the realistic **bbox-only median 15.8%** — it clears
the 12% bar comfortably under the expected encoding (template internal structure, re-base `id`, charge
only `bbox`). The **floor** (charge *every* positional leaf per node) is the worst case and still
clears, but only by **0.4 pt (12.4 vs 12.0)** — so the honest statement is **net ∈ [12.4%, 15.8%]
median, clears under any reasonable encoding, with thin margin at the pessimistic extreme**, not
"robustly." Gross→net erosion ~31% (floor) / ~11% (bbox-only), matching the schema pin D/F=0.65 and
(F−bbox)/F≈0.85.

**Load-bearing site (mirror of the gross §7 caveat):** the `≥3 sites ≥15%` leg depends on
**iana.org** at both bounds — drop iana and only w3 + apache clear 15%, failing the leg; iana (floor
15.3) is also one of the two median-determining sites. iana is the **token_ref-artifact** site
flagged in §7: its structural recurrence is paid honestly as per-node deltas (~0.81/node, ablation
`0/2/0`), so the savings are legitimate lossless dedup, not the deferred token_ref-stability rung —
the same adjudication that licensed it for gross licenses it for net. The verdict is therefore as
sound as that §7 position, no more and no less. (gnu.org, net floor 5.1, is the weak site as at
gross and is *not* load-bearing.)

## Next (design §9 BUILD path)

Net gate cleared — proceed to implement structural-template + per-route lossless-delta chrome dedup
before the core-file build: store one structural-keyed chrome template per recurring landmark; per
route, store positional fields + the lossless `token_ref`/`text_len` deltas (equal→1-bit flag,
differ→value). **Pin the positional encoding** when building: templating internal structure
(`parent`/`z`/`confidence`) and re-basing `id` puts realized net at the bbox-only ~15.8%, not the
floor — but even the floor is above the bar, so the build is justified under any reasonable encoding.

## Reconcile (shipped build vs probe band — RECONCILED 2026-06-02)

> ⚠️ **This gate asserted route-IDs only (`reconstruct(...).keys() == routes.keys()`), NOT node
> bytes — so its "byte-identical / validated end-to-end" wording below OVERSTATES what was checked.
> A real losslessness defect (unkeyed `style` dropped) slipped past it. Superseded by the "Lossless
> re-measurement" section below, which asserts true per-route node-set equality. Read that first.**

The G3d dedup is now BUILT (`scripts/_chrome_dedup.py` pure core + `scripts/site_chrome.py` CLI,
plan `docs/plans/g3d-structural-deltas-chrome-dedup.md`, branch `g3d-chrome-dedup-build`). The
acceptance gate — does the **shipped** encoder's realized saving track the probe's net bbox-only
prediction? — is measured by `research/capture-gap-probes/reconcile_g3d_chrome.py`, which captures
the same 6 sites, runs the real `dedup_chrome`, and computes realized node-fraction saving on the
**identical** `probe_g3d_net` F-basis (`F = pos+struct+vol`; credit `struct + (pos-bbox) + matched -
flag`; subtract any positional leaf actually charged as an exception). This reads the artifact, so
encoder slippage (z/parent escaping to exceptions, flag overhead) erodes the number honestly.

| site | realized | probe bbox-only | Δ |
|---|---|---|---|
| python.org | 10.8 | 11.1 | −0.3 |
| iana.org | 19.6 | 19.6 | 0.0 |
| djangoproject.com | 11.5 | 12.0 | −0.5 |
| w3.org | 25.2 | 25.8 | −0.6 |
| gnu.org | 6.3 | 6.3 | 0.0 |
| apache.org | 24.8 | 24.9 | −0.1 |

**Realized median = 15.5% (probe bbox-only 15.8%, floor 12.4%). VERDICT: RECONCILED** — every site
within ≤0.6 pt of its probe value (no `INVESTIGATE` rows), median 0.3 pt under the probe bbox-only
and comfortably above the floor. The uniform small undershoot is the expected per-instance flag
overhead (`vol/64`) the bbox-only model omitted; **no site slipped toward the floor**, so the
encoding pin held — `parent`/`z`/`confidence` templated and `id` re-based produced ~zero positional
exceptions on real captures (consistent with `web_skeleton`'s `id=len(emitted)` pre-order making a
tiled landmark a contiguous subtree). Losslessness is enforced absolutely: `site_chrome.py` fails
closed if `reconstruct` is not byte-identical, and the firewall backstop unlinks any flagged
artifact.

**Bottom line:** gross 18% → net-modelled [12.4, 15.8] → **realized 15.5% median**, validated
end-to-end. The build delivers what the gate promised; no encoding tuning was applied post-hoc.

## Lossless re-measurement — corrects the `.keys()`-only reconcile (2026-06-02)

**Why this section exists.** The "RECONCILED 2026-06-02" gate above asserted only
`D.reconstruct(art).keys() == routes.keys()` — route-IDs, **not node bytes**. It therefore never
verified byte-losslessness on real captures, and it missed a real defect: `_chrome_dedup` charged
only `id/parent/z/confidence` as exceptions, so any **unkeyed** field that varied between
structurally-identical instances (e.g. a per-route `style` CSS gradient) was taken from the template
on reconstruct and silently dropped. Surfaced by the `site_capture --merge --dedup` wiring smoke
(python.org home vs /about/, nodes 54/55); root cause in `docs/plans/g3d-losslessness-gap-found.md`.

**Fix (branch `wire-post-processors`).** `_chrome_dedup` now charges EVERY non-template-derived field
by construction: a shared `_reconstruct_node` builds the exact ship-path reconstruction, `_node_patch`
diffs it against the real node → `exceptions` (set: any differing/instance-only field) + `drop`
(template-only fields removed on rebuild). The `_vol_presence` tripwire and `_diff_nonpositional` are
gone (subsumed). `site_chrome._jsonable` serializes `drop`; the reconcile asserts true per-route
node-set equality and charges `len(exceptions)+len(drop)` per node.

**Corrected live re-measurement** (`reconcile_g3d_chrome.py`, 6 sites × 4 routes, :9222, all
**node-set lossless** — zero `NOT LOSSLESS` rows):

| site | realized | probe bbox-only |
|---|---|---|
| python.org | 10.8 | 11.1 |
| iana.org | 19.6 | 19.6 |
| djangoproject.com | 11.5 | 12.0 |
| w3.org | 25.2 | 25.8 |
| gnu.org | 6.3 | 6.3 |
| apache.org | 24.8 | 24.9 |

**Realized median = 15.5%** (≥3 sites ≥15%: iana, w3, apache). **VERDICT: BUILD STANDS — now on a
genuinely node-set-lossless encoder.** The savings are essentially unchanged because the
previously-dropped data was tiny: on the python.org pair the fix charges exactly **2 `style` fields**
(nodes 54/55) out of 296 ref nodes, `drop`=0 — a real correctness defect, but a negligible
node-fraction cost. Caveat on basis: `_realized_bbox_pct` is the pre-registered **node-fraction**
proxy and counts each exception/drop *field* as one leaf, so a multi-property `style` exception is
undercounted in byte terms — a byte-level savings would be modestly lower. The bar was pre-registered
on the node-fraction basis and is NOT moved here; the headline result of this re-measurement is
**correctness** (true losslessness, now attested by the real node-set gate across all 6 sites), with
the savings verdict surviving as a secondary finding.
