# Assets frontier — bespoke charts → assets.jsx + home_assets.dart (Tier 2)

> The Designer **authors the assets itself** — `design/assets.jsx` (the charts already in the JSX)
> **paired with a frozen `home_assets.dart`** that becomes the `reference/` source. Same
> freeze+replay pattern as `data_model.json`. This *closes* the frontier gap rather than *naming* it.

## What's "frontier" (what `generate_view` cannot emit)
`generate_view.py` translates parsed nodes → stock Flutter widgets. It cannot emit:
- **CustomPainter charts** — atlet's `TrendLine` (sparkline), `Heatmap` (calendar grid), `Dial`
  (radial progress), `StepStrip`.
- **Bespoke animated composites** — a countdown ring, a live-fill progress bar, a custom glyph drawn
  via `Canvas` (atlet's play glyph is `Canvas`-drawn to avoid the material-icons artifact).
- **Anything requiring hand-tuned `Path`/`Paint`/`ShaderMask`.**

These are the **frontier** — beyond what deterministic translation produces. Without the Designer
authoring them, the operator hand-writes `home_assets.dart` per app. The Designer removes that burden.

## The authoring pattern (freeze+replay)
1. **Author the chart in `design/assets.jsx`** as a real React component the design actually renders
   (so capture picks it up and `parity.py --all` can mount it). Don't fake it — a placeholder chart
   that isn't drawn won't be captured.
2. **Author the matching `home_assets.dart`** — the Flutter `CustomPainter`/widget that reproduces
   the JSX chart. This is the LLM-authored-once artifact; treat it as hand-authored SSOT.
3. **Freeze both.** The crew replays the frozen `home_assets.dart` as the `reference/` source
   (`generate_view.py`'s `import 'presentation/home_assets.dart';` stays valid — the crew stops
   hand-writing it).

`smoke_e2e.sh` clobbers `built/` from `reference/` every run. By making the Designer's frozen
`home_assets.dart` **the `reference/` source**, the clobber is *correct* — it propagates the
authored asset, not a stale hand-written one.

## The chart catalog (port from atlet's reference/)
| Chart | JSX (assets.jsx) | Dart (home_assets.dart) |
|---|---|---|
| **TrendLine** | an SVG polyline + gradient fill, data-driven | `CustomPainter` drawing `Path` from points, `Paint..shader` for the fill |
| **Heatmap** | a CSS grid of colored cells, intensity→hue | a `CustomPainter` or `Table` of `Container`s, `HSLColor.lerp` for intensity |
| **Dial** | an SVG arc (stroke-dasharray), radial labels | `CustomPainter` arc via `drawArc`, `Paint..strokeCap` |
| **StepStrip** | a row of segmented bars | a `Row` of `Flexible`/`Expanded` `Container`s |
| **Live countdown / progress** | a div that fills over `setInterval` | a `StatefulWidget` + `Ticker`/`AnimationController` |

Author the set your design actually uses; don't emit the whole catalog (one-detail-screen apps don't
need a Heatmap). **Every authored chart must appear in the JSX the design renders** — orphan Dart
that no JSX exercises is unverifiable.

## Forbidden
- ❌ Orphan `home_assets.dart` with no matching JSX chart (unverifiable — capture won't see it).
- ❌ Approximating a chart with stock widgets when the design drew it bespoke (loses the signature
  detail — atlet's `TrendLine` is the "screenshot-worthy" texture).
- ❌ Hand-rolling what `generate_view` already emits (the frontier is only what it *can't*).

## Coherence rules (the freeze gate)
- Every `home_assets.dart` symbol has a JSX counterpart in `assets.jsx` that the design renders.
- Every chart the design renders that `generate_view` can't emit has a `home_assets.dart` symbol.
- The Dart chart's data shape matches the JSX chart's props (the values come from `data.jsx` /
  `data_model.json`, same as any other primitive).
