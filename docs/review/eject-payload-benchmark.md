# Ejected hello-hda — Payload/TTI Benchmark

Server-rendered htmx 4 app (Hono + hono/jsx) vs measured SPA framework baselines.

## Methodology

- **htmx side**: captured 2026-08-06 from the real ejected hello-hda node app by
  byte-counting each served resource (curl body size; `gzip -9`). Single-run sizes,
  not medians.
- **SPA side**: measured 2026-08-07 from pinned CDN builds: raw = `curl -s <url> | wc -c`,
  gzipped = `curl -s <url> | gzip -9 | wc -c`. Local `gzip -9` throughout — CDN-served
  gzip differs <1% and varies with the CDN's level; local gzip keeps rows comparable.
- React 19 ships **no minified UMD/browser build** (`react@19/production/react.production.min.js`
  → 404 on unpkg), so both are given: official unminified CJS production files, and
  esm.sh minified ESM (closest to what a bundled browser app ships). `cjs/react-dom.production.js`
  is a 6.6 KB shim over react-dom-client; only the client file is counted. Preact's old
  `dist/preact.min.js` is gone in 10.29.8; `preact.module.js` is the minified build.
- App-bundle, CSS and API-fetch rows are **assumptions, not measurements** — they
  cannot be measured without building a reference SPA, which was not done.

## htmx side (ejected node target, measured 2026-08-06)

| Resource          | Raw (B) | Gzipped (B) | Loaded     |
|-------------------|---------|-------------|------------|
| Rendered HTML     | 7,013   | 2,008       | immediate  |
| htmx4.min.js      | 36,282  | 12,933      | immediate  |
| app.css           | 10,714  | 3,018       | immediate  |
| islands.js        | 6,595   | 2,588       | immediate  |
| island-kit.js     | 3,246   | 1,321       | on interaction |
| alien-signals.min | 5,348   | 1,957       | with island-kit |
| toggle.js (island)| 315     | 246         | on interaction |
| **Initial total** | **60,604** | **20,547** |            |
| **Full (islands)**| **69,513** | **24,071** |            |

## SPA framework runtimes (measured 2026-08-07)

| Package (exact version, URL)                                    | Raw (B) | Gzipped (B) |
|-----------------------------------------------------------------|---------|-------------|
| react 19.2.8 — esm.sh/react@19.2.8/es2022/react.mjs             | 10,030  | 3,838       |
| react-dom 19.2.8 + scheduler 0.27.0 — esm.sh .../react-dom.mjs + client.mjs + scheduler.mjs | 189,318 | 60,452 |
| **React 19 runtime, minified ESM total**                        | **199,348** | **64,290** |
| react 19.2.8 — unpkg cjs/react.production.js (unminified)        | 17,217  | 4,442       |
| react-dom 19.2.8 — unpkg cjs/react-dom-client.production.js (unminified) | 536,016 | 94,733 |
| preact 10.29.8 — unpkg preact@10.29.8/dist/preact.module.js     | 11,693  | 4,855       |

## SPA page-load estimate (measured runtime + labeled assumptions)

| Resource                                   | Gzipped (B)      | Basis |
|--------------------------------------------|------------------|-------|
| Framework runtime                          | 64,290 react / 4,855 preact | measured above |
| App bundle (router + views) — assumption   | ~5,000–15,000    | minimal react-router + a few KB of app code; unmeasured |
| CSS — assumption                           | ~3,000–10,000    | comparable handcrafted stylesheet; unmeasured |
| API data fetch (JSON) — assumption         | ~2,000–5,000 + 1 RTT | same data the htmx HTML embeds; unmeasured |
| **SPA total**                              | **~74,000–94,000 react / ~15,000–35,000 preact** | |

## Key differences

1. **Payload**: htmx initial transfer is 20.5 KB gz. Against a React SPA (~74–94 KB gz)
   that is ~3.6–4.6× smaller; against a Preact SPA (~15–35 KB gz) it is comparable.
2. **Data round-trip**: htmx ships data in the HTML; an SPA fetches JSON after JS
   boots, paying one extra RTT (~150 ms on 3G) before first data.
3. **TTI (estimates, 3G ~400 KB/s, ~150 ms RTT)**: htmx is interactive after HTML +
   13 KB gz htmx download and parse — order of 100 ms. A React SPA is interactive after
   ~64 KB gz runtime download, parse/execute and the data fetch — order of 500 ms+.
   Arithmetic estimates from byte counts, not profiled timings.
4. **Islands**: the lazy island payload (3.5 KB gz) is request-scoped — loaded only
   on interaction; pages without islands ship zero island JS.
