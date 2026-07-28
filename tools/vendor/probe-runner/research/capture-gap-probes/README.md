# Capture-gap probes

Reusable harness + **full site manifest** for the probe-runner reproduction-gap research
(can we faithfully reproduce any site/app from a URL — pixel + tokens + animation, minus IP).
Findings write-up (this repo): `docs/plans/probe-runner-engine-capture-gaps.md`
(§A taxonomy · §B YouTube · §C awwwards sweep · §C6 arch-completeness · §C7 isolation · §C8 refs ·
§C9 corrected synthesis + fix priority).

> **Scripts + README + manifest are tracked; only `out/` is gitignored** (see repo `.gitignore`).
> All outputs are **content-free** — counts, ratios, and class-labels only (no copyrighted
> markup/text/pixels), per the probe-runner content firewall.

## Methodology
For each site, measure **TRUTH** (properly hydrated, consent dismissed, scroll-swept char probe) vs
**VERB-AS-IS** (the real `web_skeleton`/`web_tokens`/`bundle_writer` CLIs, fresh-nav) and score three
**independent** axes (never collapse): substrate-blindness · DOM-structure · motion-demand-vs-capturable.
`structure_capture_ratio` is **cross-pipeline** (parse_snapshot recs ÷ querySelectorAll) — NOT a capture
fraction; the same-pipeline isolation (`aw_iso.py`) is the firm test.

## Scripts
| Script | What it does | Run |
|---|---|---|
| `aw_probe.py` | full per-site TRUTH-vs-VERB scorecard → `out/<label>.json` | via `aw_run.sh` |
| `aw_run.sh URL LABEL` | launch isolated Chrome → `aw_probe.py` → kill | `./aw_run.sh https://… mylabel` |
| `aw_scan.py` | cheap arch-scanner (detection-only) over a hardcoded URL batch → `out/scan.json` | `./_launch.sh aw_scan.py` |
| `aw_iso.py` | **same-pipeline** 3-point isolation (timing vs consent) → `out/iso.json` | `./_launch.sh aw_iso.py` |
| `aw_ref.py` | shadow-DOM split test (shoelace) → `out/shadow_ref.json` | `./_launch.sh aw_ref.py` |
| `aw_ref2.py` | axes 2–3 refs (lottie/astro/flutter/xorigin) → `out/ref2.json` | `./_launch.sh aw_ref2.py` |
| `_launch.sh <py>` | generic: launch Chrome, run a no-arg probe script, kill Chrome | — |

Host-only (CDP needs the host browser; the ctx sandbox can't reach host `localhost:9334`).
Each wait loop is self-bounded (macOS has no `timeout`). Edit the URL lists inside `aw_scan.py` /
`aw_iso.py` / `aw_ref2.py` to retarget.

### G3c richness-gated de-risk · `probe_g3c_richness_gated.py`
Pre-registration: `docs/plans/richness-gated-g3c-design.md`. HOST CDP only.
- Unit suite (no browser): `python3 -m pytest research/capture-gap-probes/test_g3c_richness_gated.py -v`
- Floor-A:   `python3 research/capture-gap-probes/probe_g3c_richness_gated.py --floor-a https://mui.com/`
- Full run:  `python3 research/capture-gap-probes/probe_g3c_richness_gated.py` (launch Chrome `:9222` first; open a blank tab — see memory `cdp-capture-needs-open-tab`)
Emits BUILD/DEFER per the §6 bar. Content-free: counts/jaccard/role-names/netloc only.

## Site manifest — everything probed so far

### Deep-probe — full pipeline (awwwards, 2026-05-30) · `out/<label>.json`
| label | URL | arch (detected) | substrate | headline gap |
|---|---|---|---|---|
| cartier | https://www.cartier.com/en-fr/watchesandwonders | Nuxt (SSR-rehydrate) | WebGL hero (area 1.0) | G5 |
| air | https://aircenter.space/ | MPA/static (no router) | DOM/SVG, custom cursor | **near-miss** (G4 only) |
| cdiscount | https://jumpingmax.cdiscount.com/ | client-SPA (custom) | WebGL game (167-node DOM) | G5 |
| razorpay | https://razorpay.com/sprint/26 | MPA/static | 44 WebGL (area 7.73×) | G5 + G7 |
| detroit | https://www.detroit.paris/ | client-SPA (custom) | 6 background videos | G9 + G7 |
| sowieso | https://sowieso.wero-wallet.eu/nl-en/merchant | MPA (server) | 3 2D canvas + 6948-node DOM | G5(2D) + G4 |
| ashley | https://ashleybrookecs.com/ | MPA/static | DOM | G7 (80 ScrollTriggers) |

### Arch-scan — detection only (awwwards, 2026-05-30) · `out/scan.json`
| label | URL | arch | note |
|---|---|---|---|
| unseen | https://2025.unseen.co/ | MPA/static | WebGL canvas |
| lookback | https://tlb.betteroff.studio/ | Nuxt | canvas |
| corentin | https://corentinbernadou.com/ | MPA/static | WebGL canvas |
| shed | https://shed.design/ | Nuxt | DOM |
| gqlab | https://www.gq.com/sponsored/story/the-extraordinary-lab | Nuxt | WebGL canvas |
| offmenu | https://www.offmenu.design/ | **Next App Router / RSC** | tell = next-route-announcer |
| donmol | https://www.donmolinico.es/ | Nuxt | DOM |
| wildweek | https://week.wild.plus/athens-26 | Framer | 10 2D canvases |

### Reference probes — close axes 2–3 (known refs, awwwards lacks these) · `out/shadow_ref.json`, `out/ref2.json`
| label | URL | arch/axis | result |
|---|---|---|---|
| shoelace | https://shoelace.style/ | web-component / shadow-DOM (Lit) | **G10** split (skeleton pierces, tokens blind) |
| lottiefiles | https://lottiefiles.com/ | Lottie motion | rAF/canvas → G7/G5-class (partial; not `<lottie-player>`) |
| astro | https://astro.build/ | Astro islands | DOM-captured, capture-equivalent |
| flutter | https://gallery.flutter.dev/ | Flutter/CanvasKit | **test failed** (redirected to GitHub); CanvasKit = extreme-G5 by other evidence |
| xorigin | example.com + iana.org + same-origin (controlled inject) | cross-origin iframe | **G11** (cross-origin document absent from snapshot) |

### Baselines — earlier sessions (not re-run this exercise)
| label | URL | arch | role |
|---|---|---|---|
| kasane | craftanddesign (Framer) | Framer SPA | WAAPI-motion baseline ✓ (full capture) |
| youtube | https://www.youtube.com/watch?v=41MGDo-GNnc | slow client SPA | **G1** (settle) + **G2** (virtualization) |
| rive | https://rive.app/login/?redirect=https%3A%2F%2Feditor.rive.app | Next.js SPA | shell ✓ + 1 canvas (G5 miniature) |
| wikipedia | https://en.wikipedia.org/wiki/Cat | server MPA | full capture ✓ (16992 nodes) |

## Gap legend
G1 hydration-settle (slow-SPA only) · G2 virtualization · G3 multi-route · G4 non-URL state ·
**G5 canvas/WebGL substrate (dominant)** · G6 consent (does NOT block capture — overlays cover) ·
**G7 GSAP scroll-motion invisible to WAAPI** · G8 scroll-driven-motion model · G9 video-bg ·
**G10 web_tokens shadow-DOM blindness** · G11 cross-origin iframe opaque.

Fix priority (§C9): **P0** G7/G8 scroll-motion · **P1** G10 shadow-walk + G4 triggers ·
**P2** G5/G9/G11 substrate-honesty · **P3** G1 settle (RSC-safe) + G6 dismiss.
