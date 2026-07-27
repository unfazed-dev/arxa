# Third-party notices

app_box incorporates third-party software. Their licence terms are reproduced
below and continue to apply to the incorporated portions.

---

## `skills/app-box-designer`

`skills/app-box-designer` is a fork of an MIT-licensed design skill. The
upstream copyright notice and permission notice are reproduced here in full, as
the licence requires. The same `LICENSE` file is also retained inside
`skills/app-box-designer/`.

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

## `skills/app-box-designer/runtime/vendor/`

Client libraries served to prototypes, vendored and SRI-pinned. See
[`skills/app-box-designer/runtime/vendor/SRI.md`](skills/app-box-designer/runtime/vendor/SRI.md)
for the pinned hashes.

| library | licence |
|---|---|
| htmx (`htmx.min.js`) and extensions (`head-support.js`, `preload.min.js`, `sse.js`, `client-side-templates.js`) | Zero-Clause BSD |
| mustache.js (`mustache.min.js`) | MIT |

---

## Runtime dependencies

Installed from npm at setup, not vendored. See
`skills/app-box-designer/runtime/package.json`.

| package | licence |
|---|---|
| `hono`, `@hono/node-server` | MIT |
| `nunjucks` | BSD-2-Clause |
| `playwright` (dev only) | Apache-2.0 |
