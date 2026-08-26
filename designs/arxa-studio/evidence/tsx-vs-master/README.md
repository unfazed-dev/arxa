# tsx-vs-master — regenerated 2026-08-07 (post-review fix pass)

Pixel evidence for the nunjucks→tsx migration, re-captured after the
consolidated-review fix pass (htmx 4 migration, numeric-guard fix, worker
minors). `master-*.png` are the pre-migration goldens (kept as captured);
`tsx-*.png` are fresh captures of the current TSX build.

## Capture

Studio served with the portalo project mounted (the `~/.arxa/current`
marker), never touching the user's server on 4319:

```sh
dart run arxa/bin/arxa.dart design serve designs/arxa-studio --port 4422
dart run arxa/tool/lens_shot.dart http://127.0.0.1:4422/<route> <out.png> <w> <h> <settleMs>
```

Routes, sizes, settles (1280×832 matches the master goldens' dimensions;
390×844 and 744×1133 are the config ladder's mobile/tablet rungs):

| file | route | w×h | settle |
|---|---|---|---|
| splash | /splash | 1280×832, 390×844, 744×1133 | 2500 |
| auth | /auth | 1280×832, 390×844, 744×1133 | 2500 |
| dashboard | /dashboard | 1280×832, 390×844, 744×1133 | 2500 |
| intake | /intake | 1280×832, 390×844, 744×1133 | 3000 |
| design | /design | 1280×832, 390×844, 744×1133 | 5000 |
| plans | /workspace/plans | 1280×832, 390×844, 744×1133 | 2500 |
| settings | /settings (a 404 surface on BOTH builds — no such route) | 1280×832 | 2000 |
| product | /build/screens/product?embed=1 | 390×844, 744×1133, 1280×832 | 3000 |

`tsx-design-final.png` is the same canonical /design capture as
`tsx-design-1280.png`: on master the v1/v2/v3/final series were iterative
working captures of one surface (v1–v3 byte-identical; final differed by 19
px). The intermediate `tsx-design-1280-v2/v3.png` files were dropped as
superseded working captures.

Diff metric: exact-pixel diff, `dart run arxa/tool/png_diff.dart a.png b.png`
(tolerance 0).

## Per-pair deltas (master vs this tsx capture)

| pair | delta | reading |
|---|---|---|
| splash-1280 | 0.00% (4/1064960 px) | 4 stray px — sub-pixel text AA |
| auth-1280 | 0.00% (0 px) | identical |
| dashboard-1280 | 0.01% (116 px) | live-project counts shift under the dashboard |
| intake-1280 | 0.00% (0 px) | identical |
| design-1280 | 0.00% (0 px) | identical |
| design-final | 0.00% (19 px) | same 19 px the master series itself carried |
| plans-1280 | 0.00% (0 px) | identical |
| settings-1280 | 0.00% (0 px) | identical (both render the 404 surface) |
| product-390 | 6.85% (22538/329160 px) | turntable frame timing — see below |

## The product-390 delta (review: "2.58%, cause UNKNOWN") — RESOLVED

**Cause: capture-timing nondeterminism in the auto-rotating `<model-viewer>`
turntable — not a render bug, not live-project state drift.**

The product surface's hero is `<model-viewer src="boombox.glb">` with
auto-rotate; the canvas angle is wall-clock-dependent, so any two captures
differ inside the canvas and nowhere else. Evidence:

1. The master↔tsx diff image is red ONLY inside the 3D canvas; every other
   pixel is identical (diff images were regenerated during this pass).
2. Same build, same URL, same settle → two back-to-back captures are
   byte-identical (0.00%). Same build, settle 3000ms vs 800ms → 4.26%.
   Settle time alone reproduces a delta of the same magnitude.
3. The live-project-state hypothesis fails (2): with drift, identical settle
   would still differ.

To compare product shots, compare with the canvas masked out, or pin
`auto-rotate` off for evidence captures.

## hello-hda #tick fragment byte-compare (plan Phase A gate)

Old = nunjucks build at the branch point (`a78a79e`), served from a throwaway
git worktree on :4425. New = current TSX build on :4426. Same request
sequence: GET /timer (starts the 30s timer), then the fragment routes.

| fragment | old bytes | new bytes | result |
|---|---|---|---|
| POST /timer/skip (done) | 63 | 59 | identical modulo nunjucks' blank lines |
| GET /timer/tick (live) | 111 | 107 | identical modulo nunjucks' blank lines |

Both builds returned the live tick as `30s` (same wall second). The only
difference is nunjucks' macro emission wrapping the fragment in blank lines
(`\n\n<div …></div>\n\n` vs `<div …></div>`): markup, attributes, and text
are byte-identical after stripping newlines (`cmp` on `tr -d '\n'` passes for
both fragments).

## Note: htmx 4

This capture pass runs the post-migration studio: htmx 4.0.0-beta6
(`htmx4.min.js`), `outerMorph` swap style, `hx-status:*` response rules, and
the design-time eager island loader injected by the design server. The
goldens predate that; the near-zero deltas above include the htmx 4 runtime.
