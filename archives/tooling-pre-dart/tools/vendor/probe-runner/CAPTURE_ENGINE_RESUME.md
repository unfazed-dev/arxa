# Capture-engine build — RESUME checkpoint

Branch: `capture-engine` (off `master`). Do NOT work on `master`.
Plan: `~/Developer/nebula/docs/plans/probe-runner-capture-engine.md` (7 phases A–G).
Spec: `~/Developer/nebula/docs/superpowers/specs/2026-05-28-landing-sketch-design.md`.
Sibling crate plan: `~/Developer/nebula/docs/plans/landing-sketch-crate.md` (consumes the bundle; not started).

Engine tip: `327d8d5`. 40 pure tests pass:
`cd scripts && python3 -m pytest test_web_skeleton.py test_web_tokens.py test_skeleton_diff.py test_bundle_writer.py test_web_vectors.py -q`

## DONE — all 7 engine phases (A–G) committed + reviewed
- **A `web_skeleton.py`** — CDP DOMSnapshot → content-free nodes (id/role/z/bbox/parent/
  font/text_len/sizing/layout/token_ref/anim_ref) + `_node_colors` sidecar; REST capture;
  `--viewports` multi-breakpoint sizing inference via `Emulation.setDeviceMetricsOverride`
  (live-proven 390→max-node 780 vs 1440→2880). 13 tests.
- **B `web_tokens.py`** — palette (6 roles, saturation-based fg-muted/accent) + flat
  type/space/radii/shadow scales → tokens.json. 11 tests.
- **C `skeleton_diff.py`** — iou/node_delta/align/tree_agreement/diff + CLI; tight
  geometry+sizing+parent-tree gates; self-diff floor perfect (min_iou 1.0, tree 1.0). 7 tests.
- **D `bundle_writer.py`** — match_motion/derive_slots/apply_token_refs/assemble/write_bundle
  + generic `--motion <file>` CLI. NO baked KASANE_MOTION (re-baseline decision). 7 tests.
- **E `web_vectors.py`** — opt-in vtracer (Python API `convert_image_to_svg_py`, NOT a CLI
  binary) raster→SVG reference traces; temp-PNG cleanup. 2 tests.
- **F** multi-breakpoint (folded into web_skeleton, above).
- **G** propagated all 5 scripts+tests to engineering-pack (`a965b13`) + brainiac (`30edb79`),
  SKILL.md targeted-edited in all 3, brainiac dioxus templates left unstaged. 40/40 in each copy.

## ⚠ KNOWN GAP — motion producer→bundle adapter (this is task #33's real scope)
`bundle_writer.match_motion` consumes a motion.json row contract:
`{name, anchor(REST page-y), easing, cubic_bezier:[4], amplitude, axis, window:[2], klass:"scroll|time", source, rms}`.
The actual motion producers DO NOT emit this shape:
- `web_anim` emits `{easing, amplitude, axis, rms, window, cubic(?)}` — **no `anchor`, no `klass`,
  no `cubic_bezier` (named `cubic`?), no `name`.**
- `web_flipbook` similarly lacks anchor/klass.
So `bundle_writer --motion <raw web_anim output>` would KeyError. The 7 D-tests pass only because
they feed a synthetic `SYN_MOTION` fixture already in the contract shape.
**This is NOT a Phase-D bug** — bundle_writer correctly consumes a defined contract. The missing
piece is the ADAPTER: convert web_anim/web_flipbook raw output → contract rows. Building it needs:
(a) rename `cubic`→`cubic_bezier`; (b) set `klass` from source (web_anim=scroll, flipbook=time);
(c) derive `anchor` = the animated element's REST page-y (join with the skeleton, OR have web_anim
emit the element bbox.y); (d) synth a `name`. This is exactly task #33 (re-baseline kasane motion),
which was DEFERRED by user decision (memory `kasane-page-epoch`). #33 = capture live kasane motion
AND build this adapter, then emit a real kasane motion.json that bundle_writer can consume.

## NOT DONE
- **Task #33** — re-baseline kasane motion to LIVE page (page redesigned; §3 anchors stale) AND
  build the web_anim/flipbook→motion.json adapter above. BLOCKS a real end-to-end kasane bundle.
  Re-verify kasane menu selectors (`.Header_el__lSXpJ`, cubic-bezier(0.76,0,0.24,1) 1000ms) — page
  changed. (Memories: `kasane-page-epoch`, `flipbook-motion-recovery`.)
- **Crate plan** (landing-sketch-crate.md, 14 tasks) — consumes the bundle; not started. Can TDD
  against a synthetic bundle fixture now (Phase D defines the bundle shape).

## ENVIRONMENT HAZARDS (still in effect this session)
1. **Never dispatch parallel subagents that WRITE the same files** (race → corrupted git blob hit
   earlier). Read-only reviewers in parallel are fine; writers strictly serial.
   (Memory: `feedback-no-parallel-same-file-agents`.)
2. **Reviewer subagents must NOT edit code** — the final reviewer Wrote a /tmp scratch file
   (harmless, tracked source untouched) but a reviewer touching repo files would violate SDD.
   Reviewers report; the controller adjudicates + edits.
3. Verify committed blobs parse after any commit/amend:
   `git cat-file -p HEAD:scripts/<f>.py | python3 -c "import sys,ast; ast.parse(sys.stdin.read())"`.
4. `git add` EXPLICIT paths only (never -A); single-line commits no author trailer; do NOT push
   (probe-runner is unfazed-dev, outside the authorized push org).
