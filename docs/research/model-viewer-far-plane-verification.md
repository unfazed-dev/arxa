# model-viewer far-plane patch — verified, and the premise is wrong

**Verdict: the 60× multiplier does not fix clipping, because clipping cannot
happen. In the one camera regime where the value has any effect at all, 60×
makes rendering visibly WORSE than upstream's 1×.**

**REVERTED 2026-08-21** — the vendored file is back at the pristine 4.3.1
bytes (verified against the recorded upstream hash and the originally
committed blob at `d327c60d`, which agree), the `vendorPatches` registry is
empty, and a test pins the file to the release hash. The origin investigation
closed the last open question: the file was vendored PRISTINE at `d327c60d`,
the 60 appeared later as an uncommitted working-tree edit, no symptom is
recorded anywhere in the repo, and nothing the repo ships sets
`camera-orbit`, `max-camera-orbit`, or `skybox-image` — so no reachable scene
even enters the regime where the value acts.

Reproduce: `cd appboxd && dart run tool/model_viewer_farplane_probe.dart`
(works from either disk state — it derives the missing arm).

## What was claimed

`skills/appbox-designer/runtime/vendor/model-viewer.min.js` carries one local
edit, found uncommitted on 2026-08-21 and preserved in `de28917a`:

```js
// upstream 4.3.1
farRadius(){ ... * (null != this.groundedSkybox.parent ? 10 : 1) }
// patched
farRadius(){ ... * (null != this.groundedSkybox.parent ? 10 : 60) }
```

The recorded rationale was that 1× "puts the far plane barely past the model
itself" and that the symptom is "geometry vanishing when no grounded skybox is
set." Neither the author nor the two sessions that preserved it re-verified the
rendering. This is that verification.

## How the value is actually used

From the minified source, the only consumer:

```js
[Mb](t) { const e = Math.max(this[pE].farRadius(), t), i = Math.abs(2 * e);
          this[bb].updateNearFar(0, i) }
```

and its only call site:

```js
[Vb](t) { this[bb].applyOptions({ ..., maximumRadius: t[2] }), this[Mb](t[2]) }
```

So `far = 2 × max(farRadius(), maximumRadius)`, where `maximumRadius` is the
**`max-camera-orbit` radius** — not the camera's current distance. That detail
is load-bearing and cost a call-site read to find: the first version of the
probe swept camera distance only, which can never reach the regime where
`farRadius` wins the `max()`, so it could not have falsified anything.

### The model can never be clipped — proof

Let `r` = bounding-sphere radius, `d` = camera distance, `M` = maximumRadius.
The camera cannot exceed its own limit, so `d ≤ M`. The model's furthest
geometry from the camera is at `d + r`. The far plane is at `2·max(r, M)`.

- If `M ≥ r`: `d + r ≤ M + r ≤ M + M = 2M = 2·max(r, M)`. No clip.
- If `M < r`: `d + r ≤ M + r < r + r = 2r = 2·max(r, M)`. No clip.

Equality is only reachable at `M = r`, and only exactly at the silhouette. The
multiplier can therefore never rescue model geometry from the far plane — under
either value. What it *can* do is stretch the depth range, which costs depth
precision.

## Measurement

`boombox.glb` (11 MB, `designs/appbox-studio/assets/media/`), 390×390, both
arms rendered from the same vendored bundle with only the multiplier swapped,
each captured through `settleForCapture`. Pixel diff against 152,100 pixels:

| cell | differing px | max channel delta |
|---|---|---|
| `camera-orbit 40%` | 4 | 16 |
| `camera-orbit 75%` | 7 | 53 |
| `camera-orbit 100%` | 3 | 9 |
| `camera-orbit 200%` | 0 | 0 |
| `camera-orbit 400%` | 0 | 0 |
| `max-camera-orbit 105%` | 2 | 58 |
| `max-camera-orbit 60%` | 6 | 16 |
| **`max-camera-orbit 30%`** | **3,561** | **221** |

The first seven rows are sub-pixel depth noise — the two arms render the same
picture. The last row is the regime the proof predicts: `max-camera-orbit` held
near the bounding radius is the only way `farRadius` wins the `max()`.

### And in that regime, the patch is the worse one

`docs/research/assets/model-viewer-far-plane/`:

- `handle-1x-upstream.png` — the carry handle is one clean solid arc; the
  antenna is a clean solid line.
- `handle-60x-patched.png` — a dark seam cuts through the handle where its far
  edge bleeds through, and the antenna breaks into dashes.
- `diff-max30.png` — every differing pixel, amplified. It is exactly the handle
  arc and the antenna: the thinnest geometry, and the parts furthest from the
  camera target.

That is textbook z-fighting from a stretched depth range. Pushing the far plane
60× out spends depth precision, and thin geometry is what pays first.

## What this does not rule out

One model, one viewport, default `shadow-intensity`, no environment. The
skybox arm of the first probe run came back blank in **both** arms (1,764-byte
flat frames — the model never rendered) and was dropped rather than reported as
"no difference"; the probe now fails such cells VOID instead of "same". So a
scene with a real `skybox-image`, or a model whose geometry sits outside its
own bounding sphere, is untested. The proof above does not depend on the model,
but it does assume `d ≤ M`, which `camera-controls` enforces.

## Recommendation

Revert to upstream `1`. The patch has no mechanism by which it can prevent the
symptom recorded for it, and the only measured effect is a rendering
regression. It is a one-line change to `vendorPatches` in
`appboxd/lib/design_tools.dart` plus `dart run tool/regen_vendor_docs.dart`.

Not done unilaterally: someone applied this deliberately, and the possibility
that they were looking at a scene this probe cannot construct is worth one
question more than it is worth a silent revert.
