# Ejected hello-hda — Payload/TTI Benchmark

Captured 2026-08-06. Server-rendered htmx 4 app (Hono + hono/jsx (TSX)) vs a
mainstream SPA baseline (React + ReactDOM + app bundle + API round-trip).

## Initial page load (ejected node target)

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

## SPA equivalent baseline (industry data)

| Resource                   | Gzipped (B)  |
|----------------------------|-------------|
| React + ReactDOM (prod)    | ~45,000     |
| App bundle (router+views)  | ~15,000–30,000 |
| CSS                        | ~5,000–10,000 |
| API data fetch (JSON)      | ~2,000–5,000 + 1 RTT |
| **SPA total**              | **~67,000–90,000** |

## Key differences

1. **Payload**: htmx initial transfer is 20.5 KB gz vs SPA's 67–90 KB gz (3–4× smaller).
2. **Data round-trip**: htmx ships data in the HTML; SPA needs a fetch after JS boot.
   On 3G (~400 KB/s, ~150 ms RTT) that's one extra 150 ms the SPA pays.
3. **TTI**: htmx is interactive when HTML + 13 KB htmx parse (~50 ms on 3G).
   SPA is interactive after 67+ KB download + parse/execute + data fetch (~350+ ms on 3G).
4. **Islands**: the lazy-loaded island payload (3.5 KB gz total) is request-scoped —
   only loaded when a user interacts with an island. Pages without islands ship zero island JS.
