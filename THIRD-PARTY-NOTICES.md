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

| file | package | version |
|---|---|---|
| `htmx.min.js` | `htmx.org` | 2.0.10 |
| `preload.min.js` | `htmx-ext-preload` | 2.1.2 |
| `head-support.js` | `htmx-ext-head-support` | 2.0.5 |
| `sse.js` | `htmx-ext-sse` | 2.2.4 |
| `client-side-templates.js` | `htmx-ext-client-side-templates` | 2.0.2 |
| `mustache.min.js` | `mustache` | 4.2.0 |

**Licence terms are those published by each package at the pinned version.** The
vendored files are minified bundles carrying no licence header, so the terms
cannot be read from the artifacts on disk. Before any distribution, resolve them
from the registry rather than from memory:

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
| `nunjucks` | 3.2.4 | BSD-2-Clause |
| `playwright` (dev only) | 1.61.1 | Apache-2.0 |

---

## Lexend fonts (`designs/appbox/assets/fonts/`)

The Lexend superfamily (Lexend, Lexend Giga, Lexend Deca) by Thomas Jockin /
Font Bureau, vendored as woff2 from fonts.gstatic.com on 2026-07-28. Published
under the **SIL Open Font License 1.1** — free to use, embed, and redistribute.
License text: https://openfontlicense.org. Per-file inventory:
`designs/appbox/assets/fonts/FONTS.md`.

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
`gates/intake` (plan 10.7) traces against. The HTML story map and all original
features are unchanged.
