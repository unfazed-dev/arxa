# Motion — the closed enum + 3 rise tokens (lean — do NOT reinvent)

> The crew's motion system is **MATURE and device-verified**. The Designer does NOT build a parallel
> token system. It emits motion as **flags from the closed enum** per primitive + the 3 rise-in
> timing tokens. Everything else (`motion.dart`, `RiseIn`, `parity.py`, `motion_device.py`) is the
> crew's. Rebuilding it would be strictly worse. See ADR-0012.

## The closed 5-item motion enum (the ONLY flags you may emit)
Authoritative source: `stages/run_pipeline.py` (the classify dispatch contract).
```
motion.glass-blur     # the surface is a Liquid Glass navigation/functional layer (iOS GlassContainer)
motion.spring-press   # the element has a spring press-response (button morph)
motion.morph          # the element morphs on interaction (shape/family change)
motion.rise-in        # the element animates an entrance rise (RiseIn)
motion.parallax       # the element has parallax depth (scroll-linked transform)
```
`classify` emits these flags on each primitive; `map_all` resolves them per platform
(`motion.glass-blur` → `GlassContainer(UiKitView)` on iOS). **Never invent a sixth flag.** A
`motion[]` value outside this set fails the dispatch contract.

## The 3 rise-in tokens (ride the Token layer, see `tokens.md`)
Captured from the design's own CSS entrance animation by `capture_design.entrance_styles`:
- `kRiseMs` (int) — entrance duration per element.
- `kRiseCurve` (`Cubic`) — the captured `cubic-bezier`.
- `kRiseDy` (double) — the captured `translateY` rise distance.

These land in `motion.dart` (`generate_views.py` emits the file). `RiseIn` reads them:
`RiseIn(delayMs: <captured>, durationMs: kRiseMs, curve: kRiseCurve, dy: kRiseDy, …child)`. The
per-element `delayMs` is the captured `animation-delay` → a **true staggered start**, not duration-inflation.

**A miss is honest:** if no entrance is captured in any screen, the gate emits `kRiseMs=0` (NO
animation) and **warns loudly** — it never silently substitutes Atlet's 550ms. A foreign design must
not inherit Atlet's timing.

## How the Designer authors motion
1. **Animate entrances in the CSS** (the `.rise` class + `animation`/`animation-delay` per element).
   `capture_design` reads computed styles; the staggering must be visible at `getComputedStyle` time
   (the parity gate measures live). atlet's home uses a `.rise` stagger (delays 20→460ms).
2. **Mark glass surfaces** with the glass-blur flag (in the primitive's intent, or a class the
   classify step reads). Do NOT glass content/list rows.
3. **Emit the 3 rise tokens in `tokens.json`** only if you actually animate an entrance. Omitting is
   correct (`kRiseMs=0`, no animation); emitting a partial set (e.g. duration without curve) is a
   freeze-gate error.
4. **Flag spring-press / morph / parallax** on the primitives that need them. The crew resolves the
   platform mechanism (iOS spring, M3 Expressive press-morph via `shapes` overload, scroll parallax).

Bespoke motion the pipeline can't generate (atlet's animated `Dial`/`TrendLine` painter, a custom
countdown) is hand-authored CustomPainter Dart, frozen+replayed as a Tier-2 frontier asset
(`home_assets.dart`, see `assets-frontier.md`) — it is NOT part of the motion-token system.

## Forbidden
- ❌ A GSAP/anime/`motion-*` token tree (the crew's enum + `motion.dart` + device gates win).
- ❌ A sixth motion enum value (the dispatch contract is closed).
- ❌ Emitting rise tokens without an actual CSS entrance to capture from (produces a lying `kRiseMs>0`).
- ❌ Glassing content/list rows (over-glassing is a documented crew mistake).

## The device-verified gates (what "done" means)
- `parity.py` motion check: compares the **live design measurement** (`getComputedStyle`) against the
  **emitted stagger** parsed from generated Dart (`RiseIn` delays + `kRiseMs`/`kRiseCurve`).
  Non-circular; never silently passes.
- `motion_device.py`: a **device-observed** entrance gate (runs on a real/simulated device, not just
  headless). This is the final say — if the device doesn't see the rise, it's not done.

Author motion so these gates pass: the CSS stagger must be measurable live, and the flags must match
what the platform actually renders.
