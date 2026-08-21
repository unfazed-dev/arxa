# Third-party notices

appbox incorporates third-party software. Their licence terms are reproduced
below and continue to apply to the incorporated portions.

---

## `skills/appbox-designer`

`skills/appbox-designer` is a fork of an MIT-licensed design skill. The
upstream copyright notice and permission notice are reproduced here in full, as
the licence requires. The same `LICENSE` file is also retained inside
`skills/appbox-designer/`.

> MIT License
>
> Copyright (c) 2026 Jim Liu 宝玉
>
> Port note: `kimi-design` is a Kimi-Code-only port of
> https://github.com/JimLiu/baoyu-design (MIT), itself an independent community
> repackaging of a hosted design product's skill. This port is likewise an
> independent community effort.
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

**What was changed in the fork.** Deck, document, PDF and PPTX capabilities were
removed; the skill was renamed and re-scoped to application design; a viewport
ladder, an app-architecture contract and a structure-declaration discipline were
added; harness-specific tool references were generalised. The lineage decision
records are kept at
[`docs/research/upstream-lineage/`](docs/research/upstream-lineage/) for
historical reference.

---

## `skills/appbox-designer/runtime/vendor/`

Client libraries served to prototypes, vendored and SRI-pinned. Packages and
versions below are read from
[`runtime/vendor/manifest.json`](skills/appbox-designer/runtime/vendor/manifest.json),
which also carries the SRI hashes.

| file | package | version | licence |
|---|---|---|---|
| `htmx.min.js` | `htmx.org` | 2.0.10 | — |
| `preload.min.js` | `htmx-ext-preload` | 2.1.2 | — |
| `head-support.js` | `htmx-ext-head-support` | 2.0.5 | — |
| `sse.js` | `htmx-ext-sse` | 2.2.4 | — |
| `client-side-templates.js` | `htmx-ext-client-side-templates` | 2.0.2 | — |
| `mustache.min.js` | `mustache` | 4.2.0 | — |
| `model-viewer.min.js` | `@google/model-viewer` | 4.3.1 | Apache-2.0 |
| `dotlottie-wc.js` | `@lottiefiles/dotlottie-wc` | 0.9.24 | MIT |
| `dotlottie-player.wasm` | `@lottiefiles/dotlottie-web` | 0.78.2 | MIT |
| `lottie-player.js` | `@lottiefiles/lottie-player` | 2.0.12 | MIT |
| `rive.js` | `@rive-app/canvas-single` | 2.39.1 | MIT |
| `three.module.min.js` | `three` | 0.185.1 | MIT |
| `three.core.min.js` | `three` | 0.185.1 | MIT |

### Modified files

`model-viewer.min.js` **is not the unmodified `@google/model-viewer` 4.3.1
release.** It carries one local change — the far clipping-plane multiplier in
`farRadius()`, 1× the model's bounding-sphere radius upstream and 60× here.
model-viewer is Apache-2.0, whose §4(b) requires modified files to carry
prominent notice that they were changed; this is that notice.

The change itself, both integrity hashes, and the reasoning live in
[`runtime/vendor/SRI.md`](skills/appbox-designer/runtime/vendor/SRI.md) under
"Local patches", generated from the `vendorPatches` registry in
`appboxd/lib/design_tools.dart`. The manifest row records the on-disk hash as
`integrity` and the pristine 4.3.1 hash as `upstreamIntegrity`. A test fails if
a patched file stops being named in this section, so the list above cannot go
stale silently.

**Licence terms are those published by each package at the pinned version.** The
vendored files are minified bundles carrying no licence header, so the terms
cannot be read from the artifacts on disk. Before any distribution, resolve them
from the registry rather than from memory. The `licence` column records values
resolved via the script below; `—` marks legacy entries not cached there:

```sh
cd skills/appbox-designer/runtime/vendor
python3 -c "import json;[print(e['package'], e['version']) for e in json.load(open('manifest.json'))]" \
  | while read -r p v; do echo "$p@$v: $(npm view "$p@$v" license 2>/dev/null)"; done
```

---

## Runtime dependencies

Installed from npm at setup, not vendored. See
`skills/appbox-designer/runtime/package.json`.

Licences below were **read from each installed package's `package.json`** on
2026-07-27, not recalled:

| package | version | licence |
|---|---|---|
| `hono` | 4.12.31 | MIT |
| `@hono/node-server` | 2.0.11 | MIT |
| `playwright` (dev only) | 1.61.1 | Apache-2.0 |

---

## Lexend fonts (`designs/appbox-studio/assets/fonts/`)

The Lexend superfamily (Lexend, Lexend Giga, Lexend Deca) by Thomas Jockin /
Font Bureau, vendored as woff2 from fonts.gstatic.com on 2026-07-28. Published
under the **SIL Open Font License 1.1** — free to use, embed, and redistribute.
License text: https://openfontlicense.org. Per-file inventory:
`designs/appbox-studio/assets/fonts/FONTS.md`.

---

## `skills/appbox-story-mapper`

`skills/appbox-story-mapper` is an MIT-licensed story-mapping skill, adapted
for appbox. The upstream copyright notice and permission notice are reproduced
here in full, as the licence requires. The same `LICENSE.txt` file is also
retained inside `skills/appbox-story-mapper/`.

> MIT License
>
> Copyright (c) 2026
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

**What was changed in the adaptation.** The skill was renamed
(`story-map-builder` → `appbox-story-mapper`) and scoped into the pipeline as
the pre-design elicitation step feeding `appbox-designer` directly.
`generate_story_map.py` gained `--data-out`, `--brief-out` and `--self-test`:
the brief emission (Epic → shell, Feature → surface, all-`wont` → out-of-scope,
per-surface MoSCoW/release rollups as table columns) produces the surface table
the intake traceability gate (plan 10.6; since ported to pure Dart —
`appbox gate intake`, `appboxd/lib/gate_intake.dart`) traces against. The HTML
story map and all original features are unchanged.

---

## Example media assets (`designs/appbox-studio/assets/media/`)

One example asset per island runtime, each free for commercial use.
Per-file inventory with source URLs and sha256 hashes:
`designs/appbox-studio/assets/media/MEDIA.md`.

| file | source | licence |
|---|---|---|
| `boombox.glb` | Khronos glTF-Sample-Models (Microsoft) | CC0 1.0 |
| `off_road_car.riv` | rive-app/rive-flutter example assets | MIT |
| `lottie_logo.json` | airbnb/lottie-ios test samples | Apache-2.0 |
| `dotlottie-demo.lottie` | dotlottie/player-component test asset | MIT |
| `kenney/` tiles | Kenney.nl "Tiny Dungeon" | CC0 1.0 |
