# capture-engine — Final System Review

Branch `capture-engine` @ `~/Developer/artificial_intelligence/skills/probe-runner`
(12 files, ~1819 lines). All 40 unit tests pass. Reviewed as an integrated system,
boundary by boundary.

## Integration assessment: NO — the motion boundary does not compose

Four of five module boundaries compose cleanly (evidence below). The fifth — motion
ingestion (`web_anim`/`web_flipbook` → `bundle_writer --motion`) — has no working
contract: the row shape `match_motion` consumes is emitted by no producer in the
repo; it exists only in the consumer's own test fixture. The headline "portable
bundle carries motion" promise is non-functional end-to-end. Verdict: **FIX-FIRST**.

---

## Contract issues

### MUST-FIX 1 — motion-row contract is unfulfilled by any producer (CRITICAL)
- Consumer `match_motion` (`bundle_writer.py:23-37`) requires each row to be a FLAT
  dict, bracket-accessing `anchor, name, easing, cubic_bezier, amplitude, axis,
  window, klass, source, rms` (KeyError if any absent).
- Real `web_anim` output (`web_anim.py:225-233`) is a DICT:
  `{stack, engine, device, scrollRange, steps, settleMs, certifiedDeterministic,
  maxDriftPx, movers:[{sel, txt, absY, channels:{tx,ty,opacity,scale:{from,to,
  easing,…}}}], series}`. A nested, per-mover structure. `web_flipbook` output
  (`web_flipbook.py:163`) is similar (`channels` with `easing_a/b`, `amp_a/b`).
- `grep -c` over the producers: `web_anim.py` → `anchor`=0, `amplitude`=0,
  `klass`=0, `class`=0; `web_flipbook.py` → `amplitude`=0. None of the ten keys
  `match_motion` reads is produced by either named source. The only non-test file in
  `scripts/` containing `amplitude` AND `anchor` is `bundle_writer.py` itself. There
  is no adapter that reshapes `movers[].channels/easing/absY` into the flat rows.
- Run as documented in SKILL.md line 101
  (`web_anim --out motion.json … ; bundle_writer --motion motion.json …`):
  `bundle_writer.py:161-162` does `motion_rows = json.load(f)` — yielding the
  top-level DICT, not unwrapped to `movers`. `for row in motion_rows`
  (`bundle_writer.py:23`) then iterates the dict's KEYS (strings `"stack"`,
  `"engine"`, …) and `row["anchor"]` (`:24`) raises
  `TypeError: string indices must be integers`. Even if a caller hand-extracts the
  `movers` list, the first mover then raises `KeyError: 'anchor'`.
- Why tests miss it: `test_bundle_writer.py:11-19` hand-builds `SYN_MOTION` in the
  exact flat shape the consumer wants (`klass`/`anchor`/`amplitude`). It reads as a
  forward-spec for a motion-row format that was never implemented on the producer
  side. The unit test locks a contract nothing fulfils — the textbook
  integration-gap-masked-by-a-unit-test.
- Severity: CRITICAL. Fix: (a) add an adapter (verb or function) mapping
  `web_anim.movers[]`/`web_flipbook.channels` → motion rows
  (`anchor`←`absY`; `amplitude`/`axis`/`cubic_bezier`←`channels`+`easing`; `klass`
  from scroll-vs-time; `rms`←easing fit), OR (b) rewrite `match_motion` to consume
  the native `movers[]` shape. Then add an integration test feeding REAL
  `web_anim --out` JSON through `bundle_writer`.

### MUST-FIX 2 (subsumed by 1) — `klass` key produced nowhere
- `bundle_writer.py:36` reads `row["klass"]`; help text line 145-146 documents
  `…,klass,…`. No file in the repo emits `klass` (or `class`). Even with a flat
  adapter, this spelling is arbitrary and undefined at the source. Resolve while
  defining the real motion contract in fix 1.

### NON-BLOCKING 3 — palette role-name drift (docs only; code is name-agnostic)
- `web_tokens.assign_roles` emits keys `background, surface, fg-primary, fg-muted,
  accent, border` (`web_tokens.py:117-119`).
- SKILL.md line 99 advertises roles as `bg/surface/primary/accent/text/muted/border`
  — different spellings, 7 names listed.
- No functional break: `bundle_writer._nearest_role` iterates `palette.items()` over
  whatever keys exist (`bundle_writer.py:78`); the crate consumes opaque role names.
  Pure doc drift; tighten SKILL.md wording. Severity: LOW.

---

## The confidence-key question (reviewer's prime suspect): NON-ISSUE

The premise — "web_skeleton puts confidence INSIDE sizing only, so
`unmatched_src_high_conf` treats every unmatched node as high-conf" — is **false**.
`web_skeleton.to_skeleton` emits a **top-level** `confidence` on every node:
`web_skeleton.py:237` → `"confidence": "low" if role == "unknown_box" else "high"`.
`skeleton_diff.py:129` reads exactly that top-level key
(`n.get("confidence") != "low"`). The contract matches. `unknown_box` nodes are
correctly excluded from the high-conf-unmatched fail gate; everything else is
treated as high-conf — the intended conservative behavior. No bug.

(Aside: `sizing.confidence` is a separate, correctly-paired sub-contract —
`web_skeleton.py:241` producer ↔ `skeleton_diff._sizing_ok` consumer at line 29.)

---

## Boundaries that DO compose (evidence)

- **skeleton schema ↔ skeleton_diff**: every key diff reads (`bbox{x,y,w,h}`,
  `role`, `z`, `parent`, `id`, top-level `confidence`, `sizing{w,h,confidence}`,
  `font.size`) is emitted by `to_skeleton` (`web_skeleton.py:234-256`). Match.
- **`_node_colors` round-trip**: producer writes string keys
  (`web_skeleton.py:331` `{str(k): v …}`); consumer pops + int-keys them
  (`bundle_writer.py:156-157` `{int(k): v …}`). Round-trips cleanly. Shape
  `{node_id: {bg,fg,border}}` matches `apply_token_refs` (`bundle_writer.py:92-96`).
- **tokens palette ↔ bundle_writer**: flat `{"palette": {…}, **scales}`
  (`web_tokens.py:219`); bundle reads `tokens.get("palette", {})`
  (`bundle_writer.py:105`). Match.
- **meta keys**: `viewport`/`page`/`url`/`schema`/`dpr` present on skeleton
  (`web_skeleton.py:273-278`), read by `assemble` meta block
  (`bundle_writer.py:109-115`). Match.
- **web_vectors ↔ manifest**: reads `bundle/assets/manifest.json` slots, flips
  `vec_ref` on `kind=="svg"` slots (`web_vectors.py:91-93`); `derive_slots` seeds
  those slots with `vec_ref: None` (`bundle_writer.py:65`). Match.
- **multi-breakpoint**: `--viewports` drives
  `Emulation.setDeviceMetricsOverride` per width (`web_skeleton.py:301-305`), merges
  low-confidence sizing via cross-breakpoint bbox-delta inference
  (`merge_breakpoints`/`infer_sizing_from_breakpoints`, lines 335-379), preserving
  high-confidence DOM reads. Coherent.

---

## Overstated claims

- **SKILL.md line 102 (web_vectors): `cargo install vtracer` is wrong.** The code
  imports the **Python library** (`import vtracer`; `web_vectors.py:16,37`
  `vtracer.convert_image_to_svg_py`); the docstring line 4 explicitly says
  "(Python API) … no CLI binary exists." `cargo install vtracer` installs a PATH
  binary the code never uses; the module hard-`import`s `vtracer`, so a user who
  follows the documented install hits `ImportError`. Should read `pip install
  vtracer`. Severity: LOW but a real user-facing setup error.
- **SKILL.md line 102 (web_vectors): "for `<img>` / `<svg>` nodes."** Code traces
  only `role == "svg"` (`web_vectors.py:30` `svg_nodes`). `<img>` (role `image`)
  nodes are NOT traced. Overstates coverage. Severity: LOW.
- **SKILL.md line 101 (bundle_writer): "Motion is read from an existing `web_anim`
  or `web_flipbook` capture file."** Overstated — see MUST-FIX 1. No code path
  consumes either tool's actual output shape; the claim describes a bridge that does
  not exist. Severity: HIGH (load-bearing claim for the whole motion leg).
- Accurately implemented, no overstatement: multi-breakpoint (SKILL line 98);
  motion-not-baked / read-from-external-file (the *mechanism* is genuinely external —
  only the consumed *shape* is wrong); vtracer non-certified and excluded from
  `skeleton_diff`.

---

## VERDICT: FIX-FIRST

Must-fix before merge:
1. **Define and implement the real motion contract** (the only true blocker).
   `match_motion` (`bundle_writer.py:23-37`) consumes a flat row shape
   (`anchor, amplitude, axis, cubic_bezier, klass, …`) that NO producer emits —
   `web_anim` outputs nested `movers:[{sel,txt,absY,channels,…}]`, `web_flipbook`
   similar. Add an adapter that reshapes real captures, or rewrite `match_motion`
   to consume `movers[]` natively. Then add an integration test feeding real
   `web_anim --out` JSON through `bundle_writer`; delete/replace the fabricated
   `SYN_MOTION` fixture (`test_bundle_writer.py:11-19`).
2. As part of (1), resolve the `klass` key (produced nowhere) and use `.get(...)`
   for any row keys optional across motion sources.

Strongly recommended (non-blocking, docs/correctness):
3. SKILL.md line 102: `pip install vtracer` (not cargo); drop `<img>` from the
   web_vectors coverage claim (only svg is traced).
4. SKILL.md line 101: soften the "read from web_anim/web_flipbook" claim until the
   contract in (1) exists.
5. SKILL.md line 99: reconcile advertised palette roles
   (`bg/surface/primary/accent/text/muted/border`) with `web_tokens` actual keys
   (`background/surface/fg-primary/fg-muted/accent/border`) — doc-only.

The static-capture half (web_skeleton / web_tokens / skeleton_diff / bundle
assembly / token-ref round-trip / vectors / multi-breakpoint) is coherent and
composes — confirmed boundary-by-boundary. The confidence-key concern is a
non-issue (top-level `confidence` is emitted and read correctly). The lone
system-level defect is real but contained: the motion ingestion contract is
unfulfilled by any producer, and an integration test feeding a real web_anim
payload (instead of the hand-built `SYN_MOTION`) would have caught it. Fix the
motion contract + add that test, and the engine ships.
