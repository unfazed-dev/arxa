---
name: appbox-lens
description: Use whenever anything regarding appbox needs to be seen — capturing a screenshot of a design surface or built app, comparing design-vs-built against a golden, gathering visual evidence at the viewport ladder (390/744/1280), or verifying a surface renders without console/page errors. The appbox lens is the promoted probe-runner port (appboxd/lib/lens.dart over appboxd/lib/cdp.dart); never use the archived probe-runner. Trigger on "screenshot", "capture", "visual gate", "golden", "lens", "evidence shots", "does it render".
---

# appbox-lens — see appbox with appbox's own eyes

> Per-skill playbook (the folded canon for this phase): [`LENS_playbook.mdx`](LENS_playbook.mdx)

Standing doctrine: **for anything regarding appbox, appbox's own tools come
first** (the `appbox` CLI and this lens) before any external or archived
tooling. If a capture verb is missing, extend `appboxd/lib/lens.dart` /
`appboxd/lib/cdp.dart` — never reach for `archives/tooling-pre-dart/`.

## Pipeline position

Cross-cutting stage 8 — capture/verification, valid wherever a rendered surface exists. The stage chain: `appbox-orchestrator` (Ø, front door) → `appbox-story-mapper / appbox-moodboarder` (0, optional) → `appbox-intake` (1) → `appbox-designer` (2) → `appbox-scaffolder` (3) → `appbox-builder` (4) → `appbox-tester` (5) → `appbox-reviewer` (6) → `appbox-deployer` (9) — cross-cutting: `appbox-lint` (7), `appbox-lens` (8), `appbox-cicd` (10, day-zero frame wrapping all stages). Stage numbers and every stage's input/output artifacts: `docs/research/pipeline-map.md` §1; the visual map: `docs/appbox-system-map.md`; the CLI FSM phases: `appboxd/lib/phases.dart`.

- **Used by:** `appbox-moodboarder` (reference-app shots), the build phase (design-vs-built goldens over `appbox-builder` output), `appbox-tester` (visual + smoke layers), `appbox-reviewer` (visual evidence for the verdict).
- **Fixed upstream/downstream:** none — any skill with a surface feeds it; its PNGs + `LensResult` feed whichever gate asked for evidence.

## What the lens is

`appboxd/lib/lens.dart` over the CDP client `appboxd/lib/cdp.dart`: launches
its own headless Chrome (`--headless=new`, throwaway temp profile, ephemeral
port), navigates, settles, screenshots via `Page.captureScreenshot`, and
collects console/page errors. **Console/page errors always fail the lens**,
regardless of pixel match — a surface with a runtime bug is red even when it
looks right.

Isolation is built in: every invocation owns its Chrome, so parallel capture
slices need no port or profile juggling, and the user's browser is never
touched.

## The lens capability surface (verb table)

The probe-runner is fully ported (or dropped with reason) — the verb-by-verb
audit lives in [`capability-map.md`](capability-map.md). The lens is a **Dart
library** first; these are the verbs and where each lives:

| intent | lens verb | Dart entry point |
|---|---|---|
| golden capture / compare | `lens shot` / `lens compare` | `captureGolden` / `compareGolden(mode: byte\|pixel\|ssim)` (`lens.dart`); `runLensGate` for a surface map |
| navigate / viewport / scroll | `lens open` / `lens emu` / `lens scroll` | `CdpSession.navigateAndSettle` / `setViewport` / `screenshot(fullPage:)` (`cdp.dart`) |
| console check | `lens console` | `consoleErrors` / `pageErrors` auto-fail (`cdp.dart`) |
| drive input | `lens click` / `lens key` / `lens hover` / `lens type` | `CdpSession.click` / `key` (`cdp.dart`); hover+type inlined in `captureStates` (`lens/states.dart`); assert via `tool/lens_check.dart --expect` |
| design tokens | `lens tokens` | `extractTokens` (`lens/tokens.dart`) |
| DOM / a11y / net | `lens dom` / `lens a11y` / `lens net` | `extractDom` / `extractA11y` / `traceNet` (`lens/dom.dart`, `a11y.dart`, `net.dart`) |
| motion | `lens anim` / `lens flipbook` / `lens record` / `lens burst` | `captureScrollAnim`+`fitEasing` / `captureFlipbook` / `recordVideo` / `burstFrames` (`lens/motion.dart`) |
| structure | `lens skeleton` / `lens skeleton-diff` / `lens states` | `captureSkeleton` / `diffSkeleton` (`lens/skeleton.dart`); `captureStates` (`lens/states.dart`) |
| pixel asserts | `lens compare` / color assert | `pixelDiff` / `ssimSimilarity` / `deltaE2000Lab` / `regionMeanLab` (`lens/pixels.dart`) |
| text / ocr | `lens text-diff` / `lens ocr` | `textDiffLines` / `ocrText` (`lens/ocr.dart`) |
| crawl / merge | `lens crawl` / `lens merge` | `crawlSite` / `mergeDesignSystem` (`lens/crawl.dart`) |
| native capture | `lens native adb\|ios\|macos\|flutter …` | `LensAdb` / `LensSimctl` / `LensSck` / `FlutterVm` (`lens/native/*.dart`) |

Native *interaction* (tap/swipe/type/press) is **not** in the lens — Patrol and
`flutter_test` own that layer; the lens is capture + inspect only.

## Entry points today

**CLI** (the primary surface — `appbox lens <verb>`, dispatched in
`appboxd/bin/appbox.dart` → `lens_cli.dart`):

```sh
appbox lens check <url> <out.png> [w h settle] [--selector=<css>] [--expect=<js>]
appbox lens shoot <url> [--rungs=compact,medium,expanded] [--out=dir] [--artifact=dir]
appbox lens --help     # every verb
```

`check` is the navigate + assert path (golden capture, console-clean, optional
`--expect`/`--selector`/`--press`); `shoot` is the viewport-ladder capture pass.

**Shell driver** (one-off captures — moodboards, evidence, smoke shots):

```sh
dart run appboxd/tool/lens_shot.dart <url> <out.png> [width] [height] [settleMs] [--full]
# defaults: 1280x800, 1500ms settle; --full captures the whole scroll height
```

`tool/lens_check.dart` is the input-driving companion (`--expect <js>` asserts).

**Dart API** (gates and comparisons) — the primary surface:

- `captureGolden(url, width, height, goldenPath:, settleMs:)` — save a golden.
- `compareGolden(url, goldenPath, width, height, mode:, threshold:)` —
  `LensMode.byte` (strictest), `LensMode.pixel` (per-pixel diff percentage),
  or `LensMode.ssim` (structural similarity, luma 11×11 Gaussian). Returns
  `LensResult` (`passed`, `similarity`, `diffPixels`, `note`).
- `runLensGate(surfaces, goldenDir, width, height, ...)` — compare a
  name→URL map, one `LensResult` per surface.

## Wiring status

Every probe-runner verb is ported to the library above or dropped with reason
(see the map). The `appbox lens <verb>` CLI dispatch is **live**
(`appboxd/bin/appbox.dart` `case 'lens'` → `lens_cli.dart`, Task 7) — call it
directly, the Dart API, or the `tool/lens_*.dart` drivers. Two partials are
recorded (not gaps): `adb_shot` round-trips bytes through `latin1`
(String-only `ProcessRunner` seam), and `captureFlipbook` ships the WAAPI
oracle only (non-WAAPI frame-recovery deferred). Both carry `kimitail:` notes
naming the upgrade path.

## Conventions

- **Viewport ladder**: 390×844 (compact), 744×1133 (medium), 1280×832
  (expanded). Evidence that claims "responsive" covers all three.
- **Settle for async media**: WASM, GLB, fonts and animation runtimes need
  3000–3500ms, not the 1500ms default.
- **Evidence paths**: `designs/<design>/evidence/<topic>/<surface>-<width>.png`,
  semantic lowercase names. A green exit code with a blank canvas is a fail —
  read the PNG back (ReadMediaFile) before declaring done.
- **Goldens** are frozen approvals: capture once, compare after. Re-capture a
  golden only when the design itself changed — never to make a red check
  green.
