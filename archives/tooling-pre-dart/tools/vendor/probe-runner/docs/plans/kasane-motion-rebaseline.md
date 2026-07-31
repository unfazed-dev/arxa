# Kasane motion re-baseline + producer→bundle adapter (task #33)

Closes the last gap in the probe-runner capture engine: `bundle_writer.match_motion`
consumes a defined `motion.json` row contract, but the motion **producers**
(`web_anim`, `web_flipbook`) emit a different shape. This plan builds the
**adapter** (pure, TDD) and then re-baselines **live kasane** motion through the
full pipeline to a real end-to-end bundle.

Repo: `~/Developer/artificial_intelligence/skills/probe-runner` (canonical,
`unfazed-dev/probe-runner`). Work on branch `motion-adapter` off `master`
(`c587160`). Do NOT push (outside authorized org). Single-line commits, no author
trailer. Stage explicit paths (never `git add -A`).

Run tests: `cd scripts && python3 -m pytest <files> -q`.

---

## Contract (target shape — `bundle_writer.match_motion` consumes this)

Each `motion.json` row:
```
{
  "name":        str,             # synthetic stable id, e.g. "h1.hero#ty"
  "anchor":      float,           # REST page-y of the animated element (px)
  "easing":      str,             # standard easing name, e.g. "easeOutCubic" / "custom"
  "cubic_bezier":[float,float,float,float],  # 4 control coords
  "amplitude":   float,           # motion magnitude in the channel's unit
  "axis":        str,             # x | y | scale-x | scale-y | rotate | opacity | <channel>
  "window":      [float, float],  # scroll:[y0,y1] px ; time:[t0,t1] (normalized or ms)
  "klass":       "scroll" | "time",
  "source":      str,             # "web_anim" | "web_flipbook"
  "rms":         float            # easing-fit residual (lower = tighter)
}
```
`bundle_writer` reads `row["klass"]` (NOT `class`) and renames it to `class` on
output. It also reads `name/anchor/easing/cubic_bezier/amplitude/axis/window/source/rms`.
Do NOT change the bundle_writer side — produce rows that match exactly.

---

## Producer shapes (verified 2026-05-29 from source)

### web_anim → top-level `movers` (scroll-scrubbed, klass=scroll)
Each mover = `{**meta, "dominant": <ch>, "channels": {ch: entry}}`:
- meta keys: `rank, sel, tag, absY, txt` — **`absY` = `round(getBoundingClientRect().top + scrollY)` = REST abs page-y = the contract `anchor`.** No skeleton join needed.
- channel `entry`: `{from, to, range, scrollDeterministic, activeScroll:[y0,y1],
  easing:{name, bezier:"cubic-bezier(a,b,c,d)", rms}, certified, reason?}`
  - `activeScroll` and `easing` are present ONLY when an active range resolved.
  - `certified` bool — only certified channels are deterministic enough to keep.
- CHANNELS = `["tx","ty","sx","sy","rot","op"]`.

### web_flipbook → top-level `recovery` (time/event, klass=time)
Top-level: `{engine, device, selector, mode, dpr, viewport, frames, recovery, reproducible}`.
`recovery` = `{frames, min_confidence, channels:{ch:{from, to, amp, easing(name),
bezier:"cubic-bezier(...)", rms, ...}}, ...}`.
- flipbook does **NOT** emit the element's rest page-y → `anchor` must be supplied
  by the caller (CLI `--flipbook-anchor`, derived from the skeleton node bbox.y of
  the tracked selector).
- amplitude lives in `amp` (web_anim uses `range`).
- easing name is `easing` (web_anim nests it under `easing.name`).

---

## Task 1 — `scripts/motion_adapter.py` (pure adapter, TDD)

**Goal:** convert raw `web_anim` / `web_flipbook` JSON output → contract rows, so
`bundle_writer --motion <adapter-output>` works end-to-end. No browser. Pure
functions unit-tested; a thin `main()` reads files and writes `motion.json`.

**TDD — write `scripts/test_motion_adapter.py` FIRST.** Use synthetic fixtures that
mirror the verified shapes above (include at least one CERTIFIED and one
UNCERTIFIED web_anim channel, a multi-channel mover, and a flipbook recovery with
two channels). Tests must cover:

1. `parse_bezier("cubic-bezier(0.33, 0.0, 0.67, 1.0)") -> [0.33, 0.0, 0.67, 1.0]`
   - tolerate spaces; return `None` (or a sentinel) for `"-"` / unparseable.
2. `axis_for_channel(ch)` map: `{tx:"x", ty:"y", sx:"scale-x", sy:"scale-y",
   rot:"rotate", op:"opacity"}`; unknown channel → the channel string itself.
3. `adapt_web_anim(anim_out, *, certified_only=True)`:
   - one row **per certified channel** (fidelity-first: keep ALL certified
     channels, not just `dominant`). `certified_only=False` keeps uncertified too.
   - row.anchor = `float(mover["absY"])`; klass="scroll"; source="web_anim".
   - row.easing = `ch["easing"]["name"]`; rms = `ch["easing"]["rms"]`;
     cubic_bezier = parse_bezier(`ch["easing"]["bezier"]`).
   - row.amplitude = `abs(ch["to"] - ch["from"])` (fall back to `ch["range"]`).
   - row.window = `ch["activeScroll"]`.
   - row.axis = axis_for_channel(channel key); row.name = `f'{mover["sel"]}#{ch}'`.
   - skip channels with no `easing`/`activeScroll` (no resolvable range), and
     (when certified_only) skip `certified=False`.
4. `adapt_flipbook(fb_out, anchor, *, window=None)`:
   - one row per channel that has a non-null `easing`.
   - klass="time"; source="web_flipbook"; anchor = `float(anchor)`.
   - easing = `ch["easing"]`; rms = `ch["rms"]`; cubic_bezier = parse_bezier(`ch["bezier"]`).
   - amplitude = `abs(ch["amp"])`.
   - window = supplied `window` or `[0.0, 1.0]`.
   - axis = axis_for_channel(channel key); name = `f'{fb_out["selector"]}#{ch}'`.
   - read channels from `fb_out["recovery"]["channels"]`.
5. `combine(anim_rows, flipbook_rows) -> list` (concat; stable order: anim then flipbook).
6. Rows validate against the contract: every required key present, cubic_bezier is a
   4-float list, klass in {scroll,time}. Add an `assert_contract(row)` helper the
   tests call on every produced row.

**CLI `main() -> int`:**
```
motion_adapter.py [--anim anim.json] [--flipbook fb.json]
                  [--flipbook-anchor FLOAT] [--keep-uncertified]
                  --out motion.json
```
- at least one of `--anim`/`--flipbook` required; `--flipbook` requires
  `--flipbook-anchor` (die with a clear message otherwise).
- `with open(...) as f: json.load(f)` (file-handle, not `json.load(open())`).
- emit a summary via `_common.emit_json` (`{ok, rows, anim_rows, flipbook_rows, out}`).
- guard `if __name__ == "__main__": raise SystemExit(main())`.

Match the house style of the sibling scripts (`bundle_writer.py`, `skeleton_diff.py`):
`from __future__ import annotations`, top-level imports, module docstring stating
what's unit-tested vs live-only.

**Commit** (single line): `feat(probe): motion_adapter — web_anim/flipbook raw -> bundle motion.json contract`.

---

## Task 2 — Live kasane re-baseline → real end-to-end bundle (controller-run)

Live browser (Chrome remote-debug 127.0.0.1:9222, confirmed up). Page redesigned
since wildwood §3 — selectors/anchors are stale, RE-VERIFY everything against the
live DOM. URL: `https://kasane-keyboard.com/craftanddesign`, viewport 1440×887 dpr2.
Memories: `kasane-page-epoch`, `flipbook-motion-recovery`.

Steps:
1. Confirm transport: `web_skeleton`/`web_anim` connect to 9222.
2. Re-verify the menu trigger selector (was `.Header_el__lSXpJ`,
   cubic-bezier(0.76,0,0.24,1) 1000ms) against the LIVE DOM — it likely changed.
3. Capture: `web_skeleton` → skeleton.json (+`_node_colors`); `web_tokens` → tokens.json.
4. Capture motion: `web_anim` (scroll movers) and `web_flipbook` (menu reveal, time)
   on the verified selector.
5. `motion_adapter`: anim.json + fb.json (+ `--flipbook-anchor` = the menu element's
   skeleton bbox.y) → `kasane/motion.json`.
6. `bundle_writer --skeleton --tokens --motion kasane/motion.json --out kasane-bundle/`.
7. Sanity-check the bundle: motion rows non-empty, each row passes `assert_contract`,
   anim_ref set on the matched nodes, `class` (not `klass`) present on output rows.
8. Update memories `kasane-page-epoch` (live-baselined) + the resume doc; mark #33
   complete; #36 unblocks.

No copyrighted kasane prose/images in the bundle — content-independent only
(skeleton/tokens/motion are structural). Animation fidelity is the goal: keep all
certified channels.

---

## Order
Task 1 (adapter, pure, SDD: implementer → spec review → quality review) → Task 2
(live, controller-run, depends on Task 1's adapter). Final whole-change review,
then `finishing-a-development-branch`.
