# appbox lens — full probe-runner port + skills dartification

**Status:** planned, **not started**. Settled with the operator 2026-07-31.
**Sequencing:** execution starts only after
[`media-3d-animation-games.md`](media-3d-animation-games.md) completes. Its
outputs (`CdpSession.key()`/`click()` in `appboxd/lib/cdp.dart`,
`appboxd/tool/lens_check.dart`, `appboxd/test/lens_input_test.dart`) are
**inputs** to this plan — never re-implement them, never edit the files that
plan owns while it is in flight.
**Inputs:** [`appbox-dart-only-tooling.md`](appbox-dart-only-tooling.md)
(doctrine, COMPLETE for the pipeline spine) ·
[`../../skills/appbox-lens/SKILL.md`](../../skills/appbox-lens/SKILL.md) +
[`../../skills/appbox-lens/capability-map.md`](../../skills/appbox-lens/capability-map.md)
(evidence conventions + the verb-by-verb port inventory this plan turns green)
· `archives/tooling-pre-dart/tools/vendor/probe-runner/` (README, SKILL.md,
`scripts/verbs.json`, `docs/adr/0001-content-free-design-extractor.md`).

## Goal

Port the **entire** probe-runner verb surface (~130 scripts: web capture,
comparison engines, crawl, native adb/ios/flutter/macOS, workflow helpers)
into the appbox lens — improved for appbox, not transliterated — and dartify
the skills layer's remaining non-Dart runtimes (`.mjs`/`.py`/`.sh`). End
state: `skills/appbox-lens/capability-map.md` fully green (every verb
**ported** with a new name or **dropped with reason**), `appbox lens <verb>`
wired in `appboxd/bin/appbox.dart`, a real `lens` pipeline gate
(design-vs-built), every skill invoking Dart only, python/node/bash archived
out of `skills/` and grep-clean, `appboxd` tests green.

## Architecture

- **Lens subtree.** `appboxd/lib/lens/` becomes a package subtree:
  `pixels.dart` (decode/diff/SSIM/ΔE), `tokens.dart`, `dom.dart`, `a11y.dart`,
  `net.dart`, `motion.dart` (record/burst/anim/flipbook), `states.dart`,
  `skeleton.dart` (capture + diff), `crawl.dart`, `ocr.dart`,
  `native/adb.dart`, `native/simctl.dart`, `native/sck.dart`,
  `native/flutter_vm.dart`. The existing flat `appboxd/lib/lens.dart` stays
  the public facade — `captureGolden` / `compareGolden` / `runLensGate` and
  `LensMode`/`LensResult` keep their signatures (the media plan and
  `tool/lens_shot.dart` depend on them) — and re-exports the subtree.
  `appboxd/lib/cdp.dart` stays the transport; this plan adds domain helpers
  (screencast, Network, Accessibility, DOMSnapshot, Emulation media) to it
  additively, after the media plan's Task 6 lands.
- **One Chrome per invocation** (existing isolation doctrine), pure `dart:io`
  where probe-runner used subprocess plumbing, console/page errors auto-fail
  every capture verb, viewport ladder 390×844 / 744×1133 / 1280×832 (widths
  sourced from `config/appbox.config.json` / `ladder.json`, never hardcoded
  in app code — R3).
- **CLI.** `appbox lens <verb>` (new `case 'lens':` in
  `appboxd/bin/appbox.dart`, dispatch in new `appboxd/lib/lens_cli.dart`).
  Verb set: `shot check compare shoot tokens dom a11y net record burst anim
  flipbook states skeleton skeleton-diff crawl ocr text-diff color` plus
  `appbox lens native <adb|ios|macos|flutter> <verb>`. `tool/lens_shot.dart`
  and the media plan's `tool/lens_check.dart` remain as thin drivers
  delegating to the same lib calls.
- **The lens gate.** `appboxd/lib/gate_lens.dart` →
  `Future<GateResult> lensGate(GateContext ctx, {bool recaptureGoldens})`,
  wired into `gate_runner.dart` (`gateOrder`, `_tryDartGate`),
  `bin/appbox.dart` (`_dispatchGate`), and `phases.dart`
  (`build → [native_deps, lens]`). Compares design-rendered goldens against
  the built app (capture source per target: CDP render for web builds,
  `lens native flutter shot` / `macos shot` for desktop/mobile), pixel/SSIM +
  console-error auto-fail. Exit 2 (env/skip) when no `lens` config exists.
- **Native capture stays spawned external binaries driven from Dart**
  (doctrine rule): `adb`, `xcrun simctl`, `ffmpeg`, one small Swift helper
  CLI (ScreenCaptureKit + Vision OCR) compiled on demand, Flutter VM service
  over raw WebSocket JSON-RPC. Lens-named (`appbox lens native adb shot`),
  never "probe".
- **Design artifacts stay JavaScript; the server becomes Dart.** The designs
  (`designs/*/app.routes.js`, `*_viewmodel.js`, Nunjucks views) are authored
  ES modules — porting them to Dart would rewrite the designer skill's core
  contract and is out of scope. The Dart design server
  (`appboxd/lib/design_server.dart`) therefore executes artifact JS in a
  **headless-Chrome JS worker driven over CDP** (the substrate this plan
  already builds): Dart owns HTTP, routing-table match, sessions, prefs,
  timers, hot reload, pidfile registry, and exit codes; the worker tab owns
  viewmodel dispatch, Nunjucks rendering (vendored browser build), and l10n
  (`Intl.PluralRules` is native in Chrome). Chrome is already a spawned
  external binary in this architecture — this is the same doctrine as native
  capture, applied to JS execution. **Fallback** (documented, not taken
  preemptively): if the worker spike (Task 19 step 1) fails, `serve.mjs`
  stays as the single sanctioned node runtime, archived-not-deleted, and
  capability-map records it "dropped with reason: JS-artifact execution". The
  spike exists precisely so that decision costs ~200 lines, not the port.
- **probe-runner's extraction pipeline is NOT adopted.** ADR-0001's
  content-free bundle machinery (`bundle_writer`, `content_firewall`,
  `slots`, `motion_adapter`, `site_chrome`) served design *extraction* from
  third-party sites. appbox *authors* designs; nothing consumes bundles.
  These are dropped with reason, along with research cruft (`derisk_*`,
  `livesmoke_*`, `aw_probe`, sweep harnesses, fixture runners).

## Tech stack

Dart `appboxd` (SDK ^3.12) · **`image: ^4.5.4` — the one new runtime
dependency** (decision below) · raw CDP over `dart:io` WebSocket (existing
`cdp.dart`) · headless Chrome (`--headless=new`) as render engine and JS
worker · `Page.startScreencast` + `screencastFrameAck` → `ffmpeg
-f image2pipe` for web video · Flutter VM service over raw `dart:io`
WebSocket JSON-RPC (no `vm_service` package) · spawned `adb` / `xcrun simctl`
/ `ffmpeg` · Swift helper CLI (`SCScreenshotManager.captureImage` one-shot,
`VNRecognizeTextRequest`) compiled on demand with `swiftc` · Nunjucks
browser build vendored (SRI-pinned) for the design-server worker.

**Dependency-policy call (locked): `package:image` YES, everything else NO.**

- `image` is adopted as appboxd's second runtime dependency (after `path`).
  Reasoning: the comparison engines (pixel diff, SSIM, CIEDE2000 ΔE) need
  PNG decode/encode and pixel-buffer access. Hand-rolling PNG inflate/filter
  reconstruction is ~400 lines of exactly the code that pages someone at
  3am; `package:image` (4.x, actively maintained through 2025-2026, pure
  Dart) is the ecosystem standard, gives clean raw-pixel access
  (`getBytes(order:)`, `Image.fromBytes`), and ships verified RGB↔CIE-Lab
  primitives. SSIM and ΔE2000 themselves are **hand-rolled** (~150 lines) —
  no package provides them (`image_compare` has PixelMatching/Euclidean but
  no SSIM and is thinly maintained). Sources:
  <https://pub.dev/packages/image>,
  <https://github.com/nitinramadoss/image_compare>,
  <https://live.ece.utexas.edu/publications/2021/Hitchiker_SSIM_Access.pdf>
  (window/K1/K2 parameters).
- `vm_service` is rejected: the VM-service protocol is the same
  JSON-RPC-over-WebSocket shape as CDP, which `cdp.dart` already implements;
  a raw client is ~100 lines (`dart:io` `WebSocket`). Sources:
  <https://codebrowser.dev/flutter/flutter/packages/flutter_tools/lib/src/commands/screenshot.dart.html>
  (extension names incl. `ext.flutter.screenshot`).
- Screencast: `Page.startScreencast` (format/quality/maxWidth/maxHeight/
  everyNthFrame) with mandatory `Page.screencastFrameAck` per frame, frames
  piped to `ffmpeg -f image2pipe -framerate N`. `HeadlessExperimental.
  beginFrame` was removed in Chromium ~147 — do not build on it; screencast
  is real-time and non-deterministic (documented caveat, matches
  probe-runner's `web_record`). Sources:
  <https://chromedevtools.github.io/devtools-protocol/tot/Page/>,
  <https://www.browserless.io/blog/screencast>.
- simctl/adb: `xcrun simctl io booted screenshot|recordVideo` (`--codec`,
  `--mask`, `--type`, `--force`); `adb exec-out screencap -p`,
  `adb shell screenrecord --time-limit` + pull. scrcpy/minicap rejected as
  overkill. Physical iOS devices: out of scope (simulator + adb only);
  QuickTime-protocol capture (`go-ios`) noted as follow-up. Sources:
  <https://developer.apple.com/videos/play/wwdc2020/10647/>,
  <https://developer.android.com/tools/adb>.
- ScreenCaptureKit: `SCScreenshotManager.captureImage(contentFilter:
  configuration:)` one-shot (macOS 14+; `CGDisplayCreateImage` is
  deprecated). TCC Screen-Recording grant follows the *terminal*, not the
  binary — the helper preflights and prints remediation. Reference:
  <https://github.com/magarcia/snapwin>,
  <https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager>.

## Global constraints

- **No git commits, ever, in this plan.** All file changes are working-tree
  edits; committing is the operator's call (repo rule).
- **Media-plan files are inputs, not targets.** Do not edit
  `appboxd/lib/cdp.dart`'s `key()`/`click()`, `appboxd/tool/lens_check.dart`,
  `appboxd/test/lens_input_test.dart`, or any designer island file
  (`runtime/vendor/*_island.js`, the six smoke screens) — the media plan owns
  them. `cdp.dart` additions in this plan are appended *below* its code.
- **Public lens API is frozen.** `captureGolden`, `compareGolden`,
  `runLensGate`, `LensMode`, `LensResult`, and the `CdpClient`/`CdpSession`
  surface keep their signatures. `LensMode.pixel` gets a real implementation
  (it is today a byte fallback with a `kimitail:` note) and `LensMode.ssim`
  stops returning "not yet implemented" — behavioral upgrades behind the
  same signatures.
- **Skill edits are mirrored.** Canonical copy is `skills/` (git-tracked);
  the live copy is `.kimi-code/skills/`. Every task that edits a file under
  `skills/` ends by copying it to the same relative path under
  `.kimi-code/skills/`. Runtime commands invoke the `.kimi-code/` copy.
- **Archive policy: nothing deleted.** Retired skill runtimes
  (`.py`/`.mjs`/`.sh`) move to `archives/tooling-pre-dart/skills-pre-dart/`
  preserving relative paths. Done-criterion is "archived and grep-clean",
  never `rm`. Existing archive entries are untouched.
- **Historical documents stay untouched:** `archives/**` (except the new
  `skills-pre-dart/` additions), `docs/plans/*` other than this file,
  `docs/research/*`.
- **Console/page errors auto-fail** every lens capture and comparison
  (lens doctrine). A green exit with a blank canvas is a fail — evidence
  PNGs are read back (`ReadMediaFile`) before declaring done.
- **Evidence paths:** `designs/<design>/evidence/<topic>/<surface>-<width>.png`;
  goldens (frozen approvals) at `designs/<design>/goldens/`. Re-capture a
  golden only when the design itself changed — never to make a red check
  green.
- **Dropped means recorded.** Every probe-runner verb and every skill
  runtime file ends this plan either ported (new name in capability-map.md)
  or dropped with a one-line reason in capability-map.md. No silent omissions.
- **Tests:** `package:test`, one `test/<module>_test.dart` per lib module,
  ephemeral `HttpServer` on loopback port 0 for web fixtures (the
  `lens_test.dart` pattern). TDD where a behavior is ported: failing test
  first, then implementation. Native-wrapper tests use the
  `ProcessRunner`-style seam (`lib/process.dart`) with scripted fakes —
  tests never require a booted simulator/emulator.
- **Exit-code contracts are part of the port.** Where a legacy tool defined
  exit codes (`serve.mjs` 64/66/69/70/77, `lint.mjs` 0/1/2, `scaffold.py`
  0/1, `deploy.py` 0/1/2, `generate_story_map.py` 0/1), the Dart port keeps
  them and tests assert them.

---

## Task 1: Pixel substrate — decode, per-pixel diff, SSIM, CIEDE2000 (TDD)

Closes the documented `lens.dart` gap: `LensMode.pixel` becomes a true
per-pixel compare and `LensMode.ssim` gets a real implementation. This is
the substrate the comparison verbs (Task 3), the motion verbs (Task 4), and
the lens gate (Task 12) all consume.

**Interfaces**
- Consumes: existing `appboxd/lib/lens.dart` API; media plan's
  `cdp.dart`/`tool/lens_check.dart` untouched.
- Produces: `appboxd/lib/lens/pixels.dart`; `image: ^4.5.4` in
  `appboxd/pubspec.yaml`; rewired `compareGolden` internals (signatures
  unchanged); `appboxd/test/lens_pixels_test.dart`.

### Steps

- [ ] 1.1 Write the failing test — `appboxd/test/lens_pixels_test.dart`:
  ```dart
  // Pixel substrate: decode, per-pixel diff, SSIM, CIEDE2000.
  import 'dart:convert';
  import 'dart:io';

  import 'package:appboxd/lens/pixels.dart';
  import 'package:image/image.dart' as img;
  import 'package:test/test.dart';

  img.Image solid(int w, int h, int r, int g, int b) {
    final im = img.Image(width: w, height: h);
    for (final p in im) {
      p..r = r ..g = g ..b = b ..a = 255;
    }
    return im;
  }

  void main() {
    group('decodePng', () {
      test('round-trips bytes written by CDP screenshot', () {
        final png = img.encodePng(solid(8, 8, 10, 20, 30));
        final im = decodePng(png);
        expect(im.width, 8);
        expect(im.height, 8);
      });
      test('throws LensPixelException on non-PNG bytes', () {
        expect(() => decodePng(utf8.encode('not a png')),
            throwsA(isA<LensPixelException>()));
      });
    });

    group('pixelDiff', () {
      test('identical images: 0 diff pixels, similarity 1.0', () {
        final d = pixelDiff(solid(16, 16, 255, 0, 0), solid(16, 16, 255, 0, 0));
        expect(d.diffPixels, 0);
        expect(d.similarity, 1.0);
      });
      test('one changed pixel is counted; diff image marks it', () {
        final a = solid(16, 16, 0, 0, 0);
        final b = solid(16, 16, 0, 0, 0);
        b.setPixelRgb(3, 4, 255, 255, 255);
        final d = pixelDiff(a, b);
        expect(d.diffPixels, 1);
        expect(d.similarity, closeTo(255 / 256, 1e-9));
        expect(d.diffImage, isNotNull);
      });
      test('tolerance absorbs sub-threshold channel jitter', () {
        final a = solid(16, 16, 100, 100, 100);
        final b = solid(16, 16, 102, 100, 100);
        expect(pixelDiff(a, b, tolerance: 4).diffPixels, 0);
        expect(pixelDiff(a, b, tolerance: 1).diffPixels, 256);
      });
    });

    group('ssimSimilarity', () {
      test('identical images score 1.0', () {
        // Non-uniform content: SSIM is degenerate on flat fields by design.
        final a = img.Image(width: 64, height: 64);
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            a.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, ((x + y) * 2) % 256);
          }
        }
        expect(ssimSimilarity(a, a), closeTo(1.0, 1e-6));
      });
      test('blurred copy scores below 1 but above noise', () {
        final a = img.Image(width: 64, height: 64);
        for (var y = 0; y < 64; y++) {
          for (var x = 0; x < 64; x++) {
            a.setPixelRgb(x, y, (x * 4) % 256, (y * 4) % 256, 128);
          }
        }
        final blurred = img.gaussianBlur(a.clone(), radius: 4);
        final noise = img.Image(width: 64, height: 64);
        var seed = 7;
        for (final p in noise) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          p..r = seed % 256 ..g = (seed >> 8) % 256 ..b = (seed >> 16) % 256 ..a = 255;
        }
        final sBlur = ssimSimilarity(a, blurred);
        final sNoise = ssimSimilarity(a, noise);
        expect(sBlur, greaterThan(0.7));
        expect(sBlur, lessThan(1.0));
        expect(sNoise, lessThan(0.2));
      });
    });

    group('deltaE2000', () {
      // Sharma et al. reference pairs (CIEDE2000 test data).
      test('reference pair 1 = 2.0425', () {
        expect(deltaE2000Lab(50, 2.6772, -79.7751, 50, 0, -82.7485),
            closeTo(2.0425, 1e-3));
      });
      test('reference pair 2 = 2.8615', () {
        expect(deltaE2000Lab(50, 3.1571, -77.2803, 50, 0, -82.7485),
            closeTo(2.8615, 1e-3));
      });
      test('rgbToLab: white is L=100 a~0 b~0', () {
        final lab = rgbToLab(255, 255, 255);
        expect(lab[0], closeTo(100, 1e-3));
        expect(lab[1].abs(), lessThan(0.01));
        expect(lab[2].abs(), lessThan(0.01));
      });
      test('regionMeanLab of a solid field equals its point Lab', () {
        final lab = regionMeanLab(solid(8, 8, 200, 30, 60), 0, 0, 8, 8);
        final point = rgbToLab(200, 30, 60);
        expect(lab[0], closeTo(point[0], 1e-6));
        expect(lab[1], closeTo(point[1], 1e-6));
        expect(lab[2], closeTo(point[2], 1e-6));
      });
    });
  }
  ```
  Run `cd appboxd && dart test test/lens_pixels_test.dart` — expected:
  COMPILE ERROR (`package:appboxd/lens/pixels.dart` not found). Red
  confirmed.
- [ ] 1.2 Add the one sanctioned dependency to `appboxd/pubspec.yaml`
  (dependencies block, after `path: ^1.9.0`):
  ```yaml
    image: ^4.5.4
  ```
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd && dart pub get
  ```
  Expected: `Got dependencies!` with `image` resolved at 4.5.x.
- [ ] 1.3 Create `appboxd/lib/lens/pixels.dart` — complete file:
  ```dart
  /// Pixel substrate for the appbox lens: PNG decode, per-pixel diff,
  /// SSIM, and CIEDE2000 colour delta. The only place appboxd touches
  /// package:image; everything above this file works in decoded Image
  /// terms. SSIM parameters follow Wang et al.: 11x11 Gaussian window
  /// (sigma 1.5), K1=0.01, K2=0.03, luma channel.
  library;

  import 'dart:math' as math;
  import 'dart:typed_data';

  import 'package:image/image.dart' as img;

  class LensPixelException implements Exception {
    LensPixelException(this.message);
    final String message;
    @override
    String toString() => 'LensPixelException: $message';
  }

  /// Decode PNG bytes (as returned by CDP screenshots / simctl / adb).
  img.Image decodePng(List<int> bytes) {
    final im = img.decodePng(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    if (im == null) throw LensPixelException('not a decodable PNG (${bytes.length} bytes)');
    return im;
  }

  class PixelDiff {
    PixelDiff(this.diffPixels, this.totalPixels, this.diffImage);
    final int diffPixels;
    final int totalPixels;
    final img.Image? diffImage; // red where different, null when identical
    double get similarity => totalPixels == 0 ? 1.0 : 1 - diffPixels / totalPixels;
  }

  /// Per-pixel compare. A pixel differs when any channel delta exceeds
  /// [tolerance] (0 = exact). Dimension mismatch counts every pixel.
  PixelDiff pixelDiff(img.Image a, img.Image b, {int tolerance = 0}) {
    if (a.width != b.width || a.height != b.height) {
      return PixelDiff(a.width * a.height, a.width * a.height, null);
    }
    var diff = 0;
    img.Image? marks;
    void mark(int x, int y) {
      marks ??= a.clone();
      marks!.setPixelRgb(x, y, 255, 0, 0);
    }

    for (var y = 0; y < a.height; y++) {
      for (var x = 0; x < a.width; x++) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        if ((pa.r - pb.r).abs() > tolerance ||
            (pa.g - pb.g).abs() > tolerance ||
            (pa.b - pb.b).abs() > tolerance) {
          diff++;
          mark(x, y);
        }
      }
    }
    return PixelDiff(diff, a.width * a.height, diff == 0 ? null : marks);
  }

  /// Mean per-channel similarity in [0,1]; 1.0 = identical. Cheap mode.
  double meanSimilarity(img.Image a, img.Image b) {
    if (a.width != b.width || a.height != b.height) return 0.0;
    var acc = 0.0;
    final n = a.width * a.height;
    final ia = a.iterator, ib = b.iterator;
    while (ia.moveNext() && ib.moveNext()) {
      acc += (255 * 3 -
              ((ia.current.r - ib.current.r).abs() +
                  (ia.current.g - ib.current.g).abs() +
                  (ia.current.b - ib.current.b).abs())) /
          (255 * 3);
    }
    return n == 0 ? 1.0 : acc / n;
  }

  // --- SSIM (luma, 11x11 Gaussian sigma 1.5, C1/C2 for L=255) ---

  const double _c1 = 6.5025; // (0.01 * 255)^2
  const double _c2 = 58.5225; // (0.03 * 255)^2

  List<double> _gaussianKernel() {
    final k = List<double>.filled(11, 0);
    var sum = 0.0;
    for (var i = 0; i < 11; i++) {
      final d = i - 5;
      k[i] = math.exp(-(d * d) / (2 * 1.5 * 1.5));
      sum += k[i];
    }
    return [for (final v in k) v / sum];
  }

  Float64List _luma(img.Image im) {
    final out = Float64List(im.width * im.height);
    var i = 0;
    for (final p in im) {
      out[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
    return out;
  }

  /// Separable Gaussian convolution with edge clamping.
  Float64List _convolve(Float64List src, int w, int h, List<double> k) {
    final tmp = Float64List(w * h);
    final out = Float64List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var acc = 0.0;
        for (var i = -5; i <= 5; i++) {
          acc += src[y * w + (x + i).clamp(0, w - 1)] * k[i + 5];
        }
        tmp[y * w + x] = acc;
      }
    }
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var acc = 0.0;
        for (var i = -5; i <= 5; i++) {
          acc += tmp[(y + i).clamp(0, h - 1) * w + x] * k[i + 5];
        }
        out[y * w + x] = acc;
      }
    }
    return out;
  }

  /// Structural similarity in [0,1]; 1.0 = identical. Dimension mismatch
  /// scores 0. Degenerate flat fields: when both local variances and the
  /// covariance are ~0 the map term is 1 by construction.
  double ssimSimilarity(img.Image a, img.Image b) {
    if (a.width != b.width || a.height != b.height) return 0.0;
    final w = a.width, h = a.height, n = w * h;
    final k = _gaussianKernel();
    final la = _luma(a), lb = _luma(b);
    final la2 = Float64List(n), lb2 = Float64List(n), lab = Float64List(n);
    for (var i = 0; i < n; i++) {
      la2[i] = la[i] * la[i];
      lb2[i] = lb[i] * lb[i];
      lab[i] = la[i] * lb[i];
    }
    final mua = _convolve(la, w, h, k), mub = _convolve(lb, w, h, k);
    final va = _convolve(la2, w, h, k), vb = _convolve(lb2, w, h, k);
    final cab = _convolve(lab, w, h, k);
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final ma = mua[i], mb = mub[i];
      final sa = va[i] - ma * ma, sb = vb[i] - mb * mb, sc = cab[i] - ma * mb;
      sum += ((2 * ma * mb + _c1) * (2 * sc + _c2)) /
          ((ma * ma + mb * mb + _c1) * (sa + sb + _c2));
    }
    return sum / n;
  }

  // --- CIEDE2000 ---

  /// sRGB (0-255) -> CIE L*a*b* (D65/2°).
  List<double> rgbToLab(int r, int g, int b) {
    double lin(int c) {
      final v = c / 255.0;
      return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final rr = lin(r), gg = lin(g), bb = lin(b);
    var x = (rr * 0.4124 + gg * 0.3576 + bb * 0.1805) / 0.95047;
    var y = rr * 0.2126 + gg * 0.7152 + bb * 0.0722;
    var z = (rr * 0.0193 + gg * 0.1192 + bb * 0.9505) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    x = f(x);
    y = f(y);
    z = f(z);
    return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
  }

  /// Mean Lab over a pixel region (the color_assert region probe).
  List<double> regionMeanLab(img.Image im, int x, int y, int w, int h) {
    var l = 0.0, a = 0.0, b = 0.0, n = 0;
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        final p = im.getPixel(xx.clamp(0, im.width - 1), yy.clamp(0, im.height - 1));
        final lab = rgbToLab(p.r.toInt(), p.g.toInt(), p.b.toInt());
        l += lab[0];
        a += lab[1];
        b += lab[2];
        n++;
      }
    }
    return n == 0 ? [0, 0, 0] : [l / n, a / n, b / n];
  }

  /// CIEDE2000 between two Lab colours. Reference: Sharma et al. 2005.
  double deltaE2000Lab(num l1, num a1, num b1, num l2, num a2, num b2) {
    const deg = math.pi / 180;
    final c1 = math.sqrt(a1 * a1 + b1 * b1);
    final c2 = math.sqrt(a2 * a2 + b2 * b2);
    final cBar = (c1 + c2) / 2;
    final cBar7 = math.pow(cBar, 7);
    final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + math.pow(25, 7))));
    final a1p = a1 * (1 + g);
    final a2p = a2 * (1 + g);
    final c1p = math.sqrt(a1p * a1p + b1 * b1);
    final c2p = math.sqrt(a2p * a2p + b2 * b2);
    double hp(num a, num b) {
      if (a == 0 && b == 0) return 0;
      final h = math.atan2(b, a) / deg;
      return h >= 0 ? h : h + 360;
    }

    final h1p = hp(a1p, b1), h2p = hp(a2p, b2);
    final dLp = l2 - l1, dCp = c2p - c1p;
    double dHp;
    if (c1p * c2p == 0) {
      dHp = 0;
    } else if ((h2p - h1p).abs() <= 180) {
      dHp = h2p - h1p;
    } else if (h2p - h1p > 180) {
      dHp = h2p - h1p - 360;
    } else {
      dHp = h2p - h1p + 360;
    }
    final dHP = 2 * math.sqrt(c1p * c2p) * math.sin(dHp / 2 * deg);
    final lBarP = (l1 + l2) / 2, cBarP = (c1p + c2p) / 2;
    double hBarP;
    if (c1p * c2p == 0) {
      hBarP = h1p + h2p;
    } else if ((h1p - h2p).abs() <= 180) {
      hBarP = (h1p + h2p) / 2;
    } else if (h1p + h2p < 360) {
      hBarP = (h1p + h2p + 360) / 2;
    } else {
      hBarP = (h1p + h2p - 360) / 2;
    }
    final t = 1 -
        0.17 * math.cos((hBarP - 30) * deg) +
        0.24 * math.cos(2 * hBarP * deg) +
        0.32 * math.cos((3 * hBarP + 6) * deg) -
        0.20 * math.cos((4 * hBarP - 63) * deg);
    final dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2));
    final cBarP7 = math.pow(cBarP, 7);
    final rc = 2 * math.sqrt(cBarP7 / (cBarP7 + math.pow(25, 7)));
    final sl = 1 + (0.015 * math.pow(lBarP - 50, 2)) / math.sqrt(20 + math.pow(lBarP - 50, 2));
    final sc = 1 + 0.045 * cBarP;
    final sh = 1 + 0.015 * cBarP * t;
    final rt = -math.sin(2 * dTheta * deg) * rc;
    return math.sqrt(math.pow(dLp / sl, 2) +
        math.pow(dCp / sc, 2) +
        math.pow(dHP / sh, 2) +
        rt * (dCp / sc) * (dHP / sh));
  }
  ```
  Run `dart test test/lens_pixels_test.dart` — expected: all pass (13
  tests). If the SSIM blur/noise bounds fail, the kernel or variance
  computation is wrong — fix the code, never the expectations; the Sharma
  pairs pin ΔE to published reference data.
- [ ] 1.4 Rewire `compareGolden` in `appboxd/lib/lens.dart`. Keep the
  signature; change the internals: after capturing the fresh PNG, decode
  both images via `decodePng` and dispatch on mode — `LensMode.byte`: exact
  byte compare (unchanged); `LensMode.pixel`: `pixelDiff`, `similarity =
  diff.similarity`, `diffPixels = diff.diffPixels`, pass when
  `similarity >= threshold`; `LensMode.ssim`: `ssimSimilarity`, pass when
  `>= threshold`. Decode failure (dimension/type) = fail with `note`.
  Delete the `kimitail:` byte-fallback comment and the
  `ssim → not yet implemented` branch. Console/page errors still auto-fail
  before any pixel work. Add `export 'lens/pixels.dart';` at the bottom of
  `lens.dart` so consumers get the substrate from the facade.
- [ ] 1.5 Update the stale docs in `appboxd/lib/lens.dart`'s header comment
  ("per-pixel is a byte fallback" → describe the three real modes) and run:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd && dart test
  ```
  Expected: full suite green, including the 4 existing `lens_test.dart`
  round-trips (byte mode unchanged, pixel mode now real — its existing
  expectations still hold because identical captures diff to 0).

---

## Task 2: CDP domain extensions — screencast, Network, Accessibility, DOMSnapshot, Emulation (TDD)

Additive extensions to `appboxd/lib/cdp.dart`, appended below the media
plan's `key()`/`click()`. These are the transport for Tasks 3-6. Nothing
existing changes signature.

**Interfaces**
- Consumes: media plan Task 6 outputs (`CdpSession.key/click`).
- Produces: in `appboxd/lib/cdp.dart` — `CdpScreencast` +
  `CdpSession.screencast()`, `traceNetwork()`, `getFullAxTree()`,
  `captureDomSnapshot()`, `setEmulatedMedia()`, `elementScreenshot()`;
  `appboxd/test/cdp_domains_test.dart`.

### Steps

- [ ] 2.1 Write the failing test — `appboxd/test/cdp_domains_test.dart`.
  Fixture: ephemeral `HttpServer` (the `lens_input_test.dart` pattern)
  serving (a) a page with an animated element (`<div id=box>` +
  `requestAnimationFrame` background toggle) and a `fetch('/api/data')` on
  load, (b) `/api/data` returning `{}`. Tests:
  ```dart
  // CDP domain extensions: screencast, Network trace, AX tree,
  // DOMSnapshot, emulated media, element clip screenshot.
  import 'dart:async';
  import 'dart:io';

  import 'package:appboxd/cdp.dart';
  import 'package:test/test.dart';

  // bootFixtureServer() — same shape as lens_input_test.dart's
  // bootInputServer(): '/' serves the animated page above, '/api/data'
  // serves JSON. (Full listing in this test file, not shared.)

  void main() {
    group('CDP domains', () {
      late CdpClient client;
      late HttpServer server;
      late String baseUrl;

      setUp(() async {
        (server, baseUrl) = await bootFixtureServer();
        client = await CdpClient.launch();
      });
      tearDown(() async {
        await client.close();
        await server.close();
      });

      test('screencast delivers acked frames until stopped', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 844);
        await tab.navigateAndSettle(baseUrl, settleMs: 500);
        final cast = await tab.screencast(format: 'jpeg', quality: 60);
        final frames = <ScreencastFrame>[];
        final sub = cast.frames.listen(frames.add);
        await Future.delayed(const Duration(seconds: 2));
        await cast.stop();
        await sub.cancel();
        expect(frames.length, greaterThan(3)); // animated page keeps painting
        expect(frames.first.bytes.length, greaterThan(1000));
      });

      test('traceNetwork captures the page fetch', () async {
        final tab = await client.newTab();
        await tab.enable();
        final traceDone = tab.traceNetwork(const Duration(seconds: 3));
        await tab.navigateAndSettle(baseUrl, settleMs: 800);
        final events = await traceDone;
        final urls = events
            .where((e) => e['method'] == 'Network.requestWillBeSent')
            .map((e) => ((e['params'] as Map)['request'] as Map)['url'])
            .toList();
        expect(urls.any((u) => u == '$baseUrl/api/data'), isTrue);
      });

      test('getFullAxTree returns role/name nodes', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigateAndSettle(baseUrl, settleMs: 500);
        final nodes = await tab.getFullAxTree();
        expect(nodes, isNotEmpty);
        expect(nodes.any((n) => (n['role'] as Map?)?['value'] == 'StaticText' ||
            (n['role'] as Map?)?['value'] == 'text'), isTrue);
      });

      test('captureDomSnapshot returns documents with layout', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigateAndSettle(baseUrl, settleMs: 500);
        final snap = await tab.captureDomSnapshot(['display', 'color']);
        expect(snap['documents'], isA<List>());
        expect((snap['documents'] as List), isNotEmpty);
      });

      test('setEmulatedMedia flips prefers-color-scheme', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigateAndSettle(baseUrl, settleMs: 300);
        await tab.setEmulatedMedia(features: {
          'prefers-color-scheme': 'dark',
          'prefers-reduced-motion': 'reduce',
        });
        expect(
            await tab.evaluate(
                'matchMedia("(prefers-color-scheme: dark)").matches'),
            isTrue);
        expect(
            await tab.evaluate(
                'matchMedia("(prefers-reduced-motion: reduce)").matches'),
            isTrue);
      });

      test('elementScreenshot clips to the element box', () async {
        final tab = await client.newTab();
        await tab.enable();
        await tab.setViewport(390, 844);
        await tab.navigateAndSettle(baseUrl, settleMs: 500);
        final png = await tab.elementScreenshot('#box');
        expect(png.length, greaterThan(500));
        // Decode-free size check: a 100x100 clip PNG is far smaller than
        // a 390x844 viewport PNG.
        final full = await tab.screenshot();
        expect(png.length, lessThan(full.length));
      });
    });
  }
  ```
  Run `cd appboxd && dart test test/cdp_domains_test.dart` — expected:
  COMPILE ERROR (`screencast`, `traceNetwork`, … undefined). Red confirmed.
- [ ] 2.2 Add to `appboxd/lib/cdp.dart`, appended after the media plan's
  `click()` — the screencast collector (complete code; the ack flow is the
  part every implementer gets wrong):
  ```dart
  /// One screencast frame delivered by Chrome.
  class ScreencastFrame {
    ScreencastFrame(this.bytes, this.timestamp);
    final List<int> bytes; // jpeg or png, per the start() format
    final double? timestamp; // Page.screencastFrame metadata.timestamp
  }

  /// Handle for a running Page.startScreencast session. Chrome sends a
  /// frame only after the previous one is acked (Page.screencastFrameAck)
  /// and only when the page actually paints — an idle page produces no
  /// frames, by protocol design. Frames are real-time and non-deterministic.
  class CdpScreencast {
    CdpScreencast._(this._session);
    final CdpSession _session;
    final _controller = StreamController<ScreencastFrame>.broadcast();
    StreamSubscription<CdpEvent>? _sub;

    /// Frames as they arrive (already acked).
    Stream<ScreencastFrame> get frames => _controller.stream;

    Future<void> _start({String format, int quality, int? maxWidth,
        int? maxHeight, int everyNthFrame}) async {
      _sub = _session.on('Page.screencastFrame').listen((event) async {
        final p = event.params;
        _controller.add(ScreencastFrame(
          base64Decode(p['data'] as String),
          ((p['metadata'] as Map?)?['timestamp'] as num?)?.toDouble(),
        ));
        await _session.send('Page.screencastFrameAck',
            {'sessionId': p['sessionId']});
      });
      await _session.send('Page.startScreencast', {
        'format': format,
        'quality': quality,
        'everyNthFrame': everyNthFrame,
        if (maxWidth != null) 'maxWidth': maxWidth,
        if (maxHeight != null) 'maxHeight': maxHeight,
      });
    }

    /// Stop the screencast and close the frame stream.
    Future<void> stop() async {
      await _session.send('Page.stopScreencast');
      await _sub?.cancel();
      await _controller.close();
    }
  }
  ```
  Add `import 'dart:convert';` to `cdp.dart`'s imports if absent
  (`base64Decode`), then these methods to `CdpSession`:
  ```dart
  /// Start a screencast. Caller must stop() it; client.close() also ends it.
  Future<CdpScreencast> screencast({String format = 'jpeg', int quality = 80,
      int? maxWidth, int? maxHeight, int everyNthFrame = 1}) async {
    final cast = CdpScreencast._(this);
    await cast._start(format: format, quality: quality, maxWidth: maxWidth,
        maxHeight: maxHeight, everyNthFrame: everyNthFrame);
    return cast;
  }

  /// Collect Network domain events for [duration]. Enables Network,
  /// buffers requestWillBeSent/responseReceived/loadingFailed/loadingFinished
  /// events, disables, returns the raw event maps.
  Future<List<Map<String, dynamic>>> traceNetwork(Duration duration) async {
    await send('Network.enable');
    final events = <Map<String, dynamic>>[];
    final sub = on('Network.requestWillBeSent').listen(events.add);
    final subs = [
      sub,
      on('Network.responseReceived').listen(events.add),
      on('Network.loadingFailed').listen(events.add),
      on('Network.loadingFinished').listen(events.add),
    ];
    await Future.delayed(duration);
    for (final s in subs) {
      await s.cancel();
    }
    await send('Network.disable');
    return [for (final e in events) {'method': e.method, 'params': e.params}];
  }

  /// Full accessibility tree (Accessibility.getFullAXTree), raw node maps.
  Future<List<Map<String, dynamic>>> getFullAxTree() async {
    final r = await send('Accessibility.getFullAXTree');
    return [for (final n in r['nodes'] as List) Map<String, dynamic>.from(n as Map)];
  }

  /// DOMSnapshot.captureSnapshot with the given computed style names.
  Future<Map<String, dynamic>> captureDomSnapshot(List<String> computedStyles) async {
    return send('DOMSnapshot.captureSnapshot',
        {'computedStyles': computedStyles});
  }

  /// Emulation.setEmulatedMedia: media type and/or feature overrides
  /// (prefers-color-scheme, prefers-reduced-motion, color-gamut, …).
  Future<void> setEmulatedMedia({String? media, Map<String, String>? features}) async {
    await send('Emulation.setEmulatedMedia', {
      if (media != null) 'media': media,
      if (features != null)
        'features': [for (final e in features.entries) {'name': e.key, 'value': e.value}],
    });
  }

  /// Screenshot clipped to a CSS selector's border box
  /// (DOM.getDocument -> querySelector -> getBoxModel).
  Future<List<int>> elementScreenshot(String selector) async {
    final doc = await send('DOM.getDocument');
    final node = await send('DOM.querySelector', {
      'nodeId': doc['root']['nodeId'],
      'selector': selector,
    });
    if (node['nodeId'] == 0) {
      throw CdpException('elementScreenshot: no element matches $selector');
    }
    final box = await send('DOM.getBoxModel', {'nodeId': node['nodeId']});
    final border = box['model']['border'] as List;
    final xs = [border[0], border[2], border[4], border[6]].map((v) => (v as num).toDouble());
    final ys = [border[1], border[3], border[5], border[7]].map((v) => (v as num).toDouble());
    final x = xs.reduce((a, b) => a < b ? a : b);
    final y = ys.reduce((a, b) => a < b ? a : b);
    final r = await send('Page.captureScreenshot', {
      'format': 'png',
      'clip': {
        'x': x,
        'y': y,
        'width': xs.reduce((a, b) => a > b ? a : b) - x,
        'height': ys.reduce((a, b) => a > b ? a : b) - y,
        'scale': 1,
      },
    });
    return base64Decode(r['data'] as String);
  }
  ```
  (`CdpEvent.params` is typed per the existing class; adjust the
  `traceNetwork` listener bodies to the concrete event-map shape already in
  `cdp.dart` — the events list above assumes
  `{'method': e.method, 'params': e.params}` projection, keep whichever the
  file's `CdpEvent` exposes.)
- [ ] 2.3 Re-run `dart test test/cdp_domains_test.dart` — expected: 6
  passed. Then `dart test` — full suite green. Note: the screencast test
  asserts >3 frames in 2s against an *animating* page; if Chrome ever
  stalls on a static page, that is protocol-correct behavior, not a bug.

---

## Task 3: Extraction verbs — tokens, dom, a11y, net (TDD, exemplar + deltas)

Ports `web_tokens`, `web_dom`, `web_a11y`, `web_net` to
`appboxd/lib/lens/{tokens,dom,a11y,net}.dart`. `tokens.dart` is the fully
worked exemplar; the siblings follow its shape with the deltas enumerated
below. All four emit JSON to stdout or a file and share the lens
conventions (one Chrome per invocation, console/page errors auto-fail,
`certified`-style structured output — the lens emits observation JSON;
consumers assert).

**Interfaces**
- Consumes: Task 2's CDP extensions (`captureDomSnapshot`,
  `getFullAxTree`, `traceNetwork`), Task 1's pixels (token colour
  clustering reuses `rgbToLab`).
- Produces: the four lib modules + `appboxd/test/lens_tokens_test.dart`,
  `lens_dom_test.dart`, `lens_a11y_test.dart`, `lens_net_test.dart`.
  CLI wiring is Task 7.

### Steps

- [ ] 3.1 Write the failing tests first (one file per module, ephemeral
  `HttpServer` fixture serving a styled page):
  - `lens_tokens_test.dart` — page with known palette (buttons `#1a73e8`,
    body `#ffffff`, text `#202124`), two font sizes (16/24px), spacing
    scale (4/8/16px paddings). Assert `extractTokens(url, 390, 844)`
    returns `{palette: [...], type: [...], spacing: [...]}` where palette
    contains entries within ΔE2000 < 3 of the three known colours
    (use `deltaE2000Lab` from `lens/pixels.dart` on `rgbToLab`-converted
    hexes), type scale contains 16 and 24, spacing contains 4/8/16, and
    `consoleErrors` is empty.
  - `lens_dom_test.dart` — page with nested list; assert
    `extractDom(url)` returns the `DOMSnapshot.captureSnapshot` envelope
    with `documents` non-empty and `strings` containing a known text node.
  - `lens_a11y_test.dart` — page with `<button aria-label="Save">`,
    `<img alt="Logo">`, heading; assert `extractA11y(url)` finds nodes
    with those names and roles.
  - `lens_net_test.dart` — page fetching `/api/data` + one 404 asset;
    assert `traceNet(url, settleMs:)` JSON has the request URL, the 200
    and the 404 response statuses, and a `failed` list.
  Run `dart test test/lens_tokens_test.dart` etc. — expected: COMPILE
  ERRORs. Red confirmed.
- [ ] 3.2 Create `appboxd/lib/lens/tokens.dart` (exemplar — the clustering
  core is the only non-obvious part):
  ```dart
  /// Design-token extraction (ports probe-runner web_tokens): computed-style
  /// sweep in the page, pure-Dart clustering into semantic palette / type /
  /// spacing scales. Observation JSON — the lens records, consumers assert.
  library;

  import 'dart:convert';

  import '../cdp.dart';

  /// The computed-style probe injected into the page. Returns flat samples:
  /// every element's colour, background, font size, padding/margin/radius.
  /// Kept as one evaluate() round-trip (probe-runner's _web_eval shape).
  const String tokenProbeJs = r'''
  (() => {
    const out = {colors: [], backgrounds: [], fontSizes: [], spaces: [], radii: []};
    for (const el of document.querySelectorAll('body, body *')) {
      const cs = getComputedStyle(el);
      if (cs.color) out.colors.push(cs.color);
      if (cs.backgroundColor && cs.backgroundColor !== 'rgba(0, 0, 0, 0)')
        out.backgrounds.push(cs.backgroundColor);
      out.fontSizes.push(parseFloat(cs.fontSize));
      for (const p of ['paddingTop','paddingRight','paddingBottom','paddingLeft',
                       'marginTop','marginRight','marginBottom','marginLeft']) {
        const v = parseFloat(cs[p]);
        if (v > 0) out.spaces.push(v);
      }
      const r = parseFloat(cs.borderRadius);
      if (r > 0) out.radii.push(r);
    }
    return out;
  })()
  ''';

  /// One colour occurrence: rgb + hit count.
  class ColorCluster {
    ColorCluster(this.r, this.g, this.b, this.count);
    final int r, g, b, count;
    String get hex =>
        '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
    Map<String, dynamic> toJson() => {'hex': hex, 'count': count};
  }

  /// Parse 'rgb(r, g, b)' / 'rgba(r, g, b, a)' -> [r,g,b]; null on miss.
  List<int>? parseCssColor(String s) {
    final m = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)').firstMatch(s);
    if (m == null) return null;
    return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)];
  }

  /// Frequency-cluster raw css colours: exact-rgb grouping, sorted by
  /// count desc. (probe-runner merged near-duplicates via numpy; exact
  /// grouping over getComputedStyle output is deterministic and sufficient
  /// because the browser already quantises to integers.)
  /// kimitail: exact-group only; ΔE-merge pass belongs here if palettes
  /// ever arrive from canvas/gradient sources with float noise.
  List<ColorCluster> clusterColors(Iterable<String> cssColors) {
    final counts = <String, int>{};
    for (final c in cssColors) {
      counts[c] = (counts[c] ?? 0) + 1;
    }
    final out = <ColorCluster>[];
    for (final e in counts.entries) {
      final rgb = parseCssColor(e.key);
      if (rgb != null) out.add(ColorCluster(rgb[0], rgb[1], rgb[2], e.value));
    }
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }

  /// Frequency-cluster a numeric scale, dropping zeros, sorted ascending
  /// with counts. Values within 0.5px are merged to their rounded int.
  List<Map<String, dynamic>> clusterScale(Iterable<num> values) {
    final counts = <int, int>{};
    for (final v in values) {
      if (v <= 0) continue;
      final k = v.round();
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort();
    return [for (final k in keys) {'value': k, 'count': counts[k]}];
  }

  /// Extract the token scales of [url] at [width]x[height]. Console/page
  /// errors fail the extraction (lens doctrine): they are returned in the
  /// result and the caller treats non-empty as a failure.
  Future<Map<String, dynamic>> extractTokens(String url, int width, int height,
      {int settleMs = 1500}) async {
    final client = await CdpClient.launch();
    try {
      final tab = await client.newTab();
      await tab.enable();
      await tab.setViewport(width, height);
      await tab.navigateAndSettle(url, settleMs: settleMs);
      final raw = await tab.evaluate(tokenProbeJs) as Map;
      final errors = [...tab.consoleErrors, ...tab.pageErrors];
      return {
        'url': url,
        'viewport': [width, height],
        'palette': [
          for (final c in clusterColors([
            ...?(raw['colors'] as List?)?.cast<String>(),
            ...?(raw['backgrounds'] as List?)?.cast<String>(),
          ]))
            c.toJson(),
        ],
        'type': clusterScale((raw['fontSizes'] as List).cast<num>()),
        'spacing': clusterScale((raw['spaces'] as List).cast<num>()),
        'radii': clusterScale((raw['radii'] as List).cast<num>()),
        'consoleErrors': errors,
        'certified': errors.isEmpty,
      };
    } finally {
      await client.close();
    }
  }

  /// CLI helper: extract and print/write JSON.
  Future<void> tokensToJson(String url, int width, int height, String? outPath,
      {int settleMs = 1500}) async {
    final result = await extractTokens(url, width, height, settleMs: settleMs);
    final json = const JsonEncoder.withIndent('  ').convert(result);
    if (outPath == null) {
      print(json);
    } else {
      writeLensJson(outPath, json);
    }
  }
  ```
  plus a tiny shared writer placed in `appboxd/lib/lens.dart` (facade, so
  every lens module reuses it — add it there, not per module):
  ```dart
  /// Write evidence JSON with parent dirs, lens convention.
  void writeLensJson(String path, String json) {
    final f = File(path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('$json\n');
  }
  ```
  (`dart:io` import already present in `lens.dart`.)
- [ ] 3.3 Create the three sibling modules — same shape as 3.2 (fixture →
  navigate → one CDP call → shape JSON → `certified` flag), with these
  exact deltas:
  - `appboxd/lib/lens/dom.dart` — `Future<Map<String, dynamic>>
    extractDom(String url, {int settleMs = 1500, List<String>
    computedStyles = const ['display', 'position', 'color',
    'background-color', 'font-size']})`: single
    `tab.captureDomSnapshot(computedStyles)` call; output envelope
    `{url, snapshot: <raw result>, consoleErrors, certified}`. Ported
    probe-runner `web_dom` (its DOMSnapshot path; the outerHTML path is
    covered by `evaluate('document.documentElement.outerHTML')` — add
    `Future<String> extractOuterHtml(String url)` for parity, one
    evaluate call).
  - `appboxd/lib/lens/a11y.dart` — `Future<Map<String, dynamic>>
    extractA11y(String url, {int settleMs = 1500})`: single
    `tab.getFullAxTree()`; flatten each node to
    `{role: n['role']['value'], name: n['name']?['value'], ignored:
    n['ignored'] ?? false}` dropping ignored subtrees' leaves (keep
    structure: emit `children` ids as-is from the raw node map); output
    `{url, nodes: [...], consoleErrors, certified}`. Ported `web_a11y`.
  - `appboxd/lib/lens/net.dart` — `Future<Map<String, dynamic>>
    traceNet(String url, {int settleMs = 1500, int traceMs = 3000})`:
    start `tab.traceNetwork(Duration(milliseconds: traceMs + settleMs))`,
    `navigateAndSettle`, await trace; fold events into
    `{url, requests: [{url, method, status, mimeType, failed}],
    consoleErrors, certified}` (`status` from `responseReceived`,
    `failed: true` from `loadingFailed`). Ported `web_net`.
- [ ] 3.4 Run the four test files — expected: all pass. Then `dart test`
  full suite green.

---

## Task 4: Motion — record, burst, scroll-anim, flipbook (TDD)

Ports `web_record` (screencast→mp4), `multishot` (burst stills),
`web_anim` (certified scroll-scrubbed easing), `web_flipbook` (time/event
motion + WAAPI oracle) to `appboxd/lib/lens/motion.dart`. probe-runner's
cv2 template tracking is replaced by the WAAPI oracle (primary, already
the reliable path in `_flipbook`) plus pixel-region diffing via
`lens/pixels.dart` — no OpenCV equivalent is introduced.

**Interfaces**
- Consumes: Task 2's `CdpScreencast`; Task 1's pixels; `ffmpeg` on PATH
  (host binary, spawned — same doctrine as Chrome).
- Produces: `appboxd/lib/lens/motion.dart`;
  `appboxd/test/lens_motion_test.dart`.

### Steps

- [ ] 4.1 Write the failing test — `appboxd/test/lens_motion_test.dart`.
  Fixture pages (ephemeral server): (a) a page whose background cycles
  via `requestAnimationFrame`; (b) a tall page with a scroll-scrubbed
  element (`transform: translateY()` driven by a scroll listener with
  known linear mapping `y = scrollY * 0.5`); (c) a page with a WAAPI
  animation (`el.animate([{opacity:0},{opacity:1}], {duration: 600,
  easing: 'ease-in-out'})`) triggered by a button click. Tests:
  - `burst` — `burstFrames(url, count: 4, intervalMs: 150)` returns 4
    PNG byte lists; consecutive frames of the animating page differ
    (`pixelDiff(...).diffPixels > 0`).
  - `recordVideo` — skip when `ffmpeg` missing (`which ffmpeg`); record
    1.5s of page (a) at 10fps, assert the mp4 exists, is >5 KB, and
    `ffprobe -v error -show_entries format=duration` reports ~1.5s±0.7.
  - `captureScrollAnim` — on page (b), assert the mover report has
    `channels.translateY.from == 0`, `.to` ≈ `maxScroll * 0.5`, easing
    certified `linear` with `rms < 0.05`.
  - `captureFlipbook` — on page (c), click the button, assert the
    recovery reports `opacity` from 0→1 over ~600ms with `reliable:
    true` (WAAPI oracle path).
  Run — expected: COMPILE ERROR (`lens/motion.dart` missing). Red
  confirmed.
- [ ] 4.2 Create `appboxd/lib/lens/motion.dart` with four public verbs:
  - `Future<List<List<int>>> burstFrames(String url, {int width = 390,
    int height = 844, int count = 5, int intervalMs = 100, int settleMs =
    1500})` — navigate, then `count` × (`tab.screenshot()` + sleep
    `intervalMs`). Console/page errors collected on the session; caller
    checks. (Ported `multishot`, web-side.)
  - `Future<void> recordVideo(String url, String outMp4, {int width =
    390, int height = 844, int seconds = 5, int fps = 15, int settleMs =
    1500})` — navigate, `tab.screencast(format: 'jpeg', quality: 85)`,
    collect frames for `seconds`, `stop()`, then assemble:
    ```dart
    /// Pipe jpeg frames to ffmpeg's image2pipe demuxer.
    Future<void> framesToMp4(List<List<int>> frames, String outMp4, int fps) async {
      final proc = await Process.start('ffmpeg', [
        '-y', '-f', 'image2pipe', '-framerate', '$fps',
        '-i', '-', // stdin
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
        outMp4,
      ]);
      for (final f in frames) {
        proc.stdin.add(f);
      }
      await proc.stdin.close();
      final code = await proc.exitCode;
      if (code != 0) {
        throw StateError('ffmpeg exited $code assembling $outMp4 '
            '(${frames.length} frames)');
      }
    }
    ```
    Zero frames → throw `StateError('screencast produced no frames — page
    never painted')` (protocol behavior, see Task 2 note). Preflight
    `ffmpeg` presence with `Process.runSync('which', ['ffmpeg'])` and a
    clear remediation message. (Ported `web_record`.)
  - `Future<Map<String, dynamic>> captureScrollAnim(String url, {int
    width = 390, int height = 844, int steps = 40, int settleMs =
    1500})` — the `web_anim` port. In-page probe (one `evaluateFunction`
    installing `window.__lensMover()` that samples
    `getComputedStyle(el).transform` + `el.getBoundingClientRect()` for
    every element where `getAnimations({subtree: true})` is empty but the
    transform changes across scroll — simpler and more deterministic than
    probe-runner's heuristic: sample **all** elements with a non-`none`
    transform at each step and keep those whose transform varies across
    the sweep). Sweep: set `scrollY = i * (maxScroll / (steps-1))` via
    `evaluate`, wait one rAF (`evaluate('new
    Promise(requestAnimationFrame)')`), sample; then a reproducibility
    revisit of step 0 (sample again; must match within 1px, else
    `certified: false, reason: 'non-deterministic'`). Analysis core (pure
    Dart, directly unit-tested): per mover/channel fit the value series
    against the standard curves — linear, ease-in (t²), ease-out
    (1-(1-t)²), ease-in-out (smoothstep) — least-squares RMS; certify the
    best curve only when `rms < 0.05` and the series is monotonic; else
    `certified: false` with reason (probe-runner's `_anim_core` rule,
    unchanged semantics). Output:
    `{url, maxScroll, movers: [{selector, channels: {translateY: {from,
    to, range, easing, rms, certified}}}], consoleErrors, certified}`.
  - `Future<Map<String, dynamic>> captureFlipbook(String url, {required
    String triggerSelector, int width = 390, int height = 844, int
    watchMs = 2000, int settleMs = 1500})` — navigate; snapshot
    `getAnimations()` via `evaluateFunction`; `tab.click()` the trigger
    via `elementScreenshot`-style box center (reuse
    `DOM.getBoxModel`→center→`tab.click(x,y)`); poll `getAnimations()`
    every 100ms for `watchMs`; recover from the WAAPI oracle: for each
    animation read `effect.getKeyframes()`, `effect.getTiming()`
    (duration/easing) and `playState`. Output `{url, animations:
    [{target, keyframes, duration, easing, playState}], reliable: true,
    consoleErrors, certified}` — `reliable: false` when the oracle sees
    no animations (caller may fall back to `burstFrames` + `pixelDiff`
    region tracking; that fallback is **not** built — kimitail: WAAPI
    covers appbox's own designs; add frame recovery when a design
    animates outside WAAPI). (Ported `web_flipbook`, oracle path.)
- [ ] 4.3 Unit-test the pure easing-fit core directly (table-driven:
  synthetic perfect linear/ease-in/ease-out/ease-in-out series certify to
  their curve with rms≈0; a noisy series is `certified: false`; a
  non-monotonic series is `certified: false` with reason
  `'non-monotonic'`). These cases live in `lens_motion_test.dart`
  alongside the CDP tests.
- [ ] 4.4 Run `dart test test/lens_motion_test.dart` — all pass; `dart
  test` full suite green.

---

## Task 5: Skeleton capture + diff, and interaction states (TDD)

Ports `web_skeleton` + `skeleton_diff` (structural compare) and
`web_states` (interaction-state capture). The content-free **format** is
kept (renamed `lens-skeleton/1` — never "probe" in emitted identifiers);
the content-free **pipeline** (firewall, slots, bundles) is not — see
Architecture.

**Interfaces**
- Consumes: Task 2's `captureDomSnapshot`/`setEmulatedMedia`, Task 1's
  pixels (state diffs).
- Produces: `appboxd/lib/lens/skeleton.dart`, `appboxd/lib/lens/states.dart`;
  `appboxd/test/lens_skeleton_test.dart`, `lens_states_test.dart`.

### Steps

- [ ] 5.1 Write the failing tests:
  - `lens_skeleton_test.dart` — fixture page with a header/nav/main/
    button structure. `captureSkeleton(url)` returns `{format:
    'lens-skeleton/1', nodes: [...]}` where each node has
    `{role, bbox: [x,y,w,h], z, fontSize, sizing}`; a known button's bbox
    matches its CSS geometry ±1px. `diffSkeleton(a, b)`: self-diff of the
    same capture is `{certified: true, deltas: []}`; a capture after
    changing one button's width reports a `size` delta naming that node;
    a capture after inserting a node reports a `tree` delta.
  - `lens_states_test.dart` — fixture page with a disclosure (`<details>`-
    like div toggled by a button) and a hover-reveal (`:hover` rule).
    `captureStates(url, triggers: [{'selector': '#toggle', 'action':
    'click'}, {'selector': '#reveal', 'action': 'hover'}])` returns per
    trigger `{before: <png bytes hash>, after: ..., changed: true,
    transition: {...}|null}` and the before/after screenshots differ
    (`pixelDiff`); the hover trigger uses
    `CSS.forcePseudoState`/`Input.dispatchMouseEvent mouseMoved` (media
    plan's click + a `mouseMoved` dispatch — add a thin
    `CdpSession.hover(int x, int y)` alongside the media plan's
    `click()`, same shape, three lines: `Input.dispatchMouseEvent` type
    `mouseMoved`).
  Run — expected: COMPILE ERRORs. Red confirmed.
- [ ] 5.2 Create `appboxd/lib/lens/skeleton.dart`:
  - `Future<Map<String, dynamic>> captureSkeleton(String url, {int width
    = 390, int height = 844, int settleMs = 1500})` — one
    `captureDomSnapshot(['display','position','z-index','font-size',
    'width','height','color','background-color'])` + one
    `evaluateFunction` walking `document.elementsFromPoint`-free plain
    DOM order to collect per-element `getBoundingClientRect()` +
    `getComputedStyle` role inference (`tag` + `role` attr + landmark
    roles). Emit `{format: 'lens-skeleton/1', url, viewport: [w,h],
    nodes: [{id, role, bbox, z, fontSize, sizing}], consoleErrors,
    certified}`. Keep it observation-only — no content strings, matching
    ADR-0001's spirit (the skeleton is the diffable artifact; text never
    enters it).
  - `Map<String, dynamic> diffSkeleton(Map<String, dynamic> a,
    Map<String, dynamic> b)` — pure function: match nodes by `id`;
    classify deltas `tree` (added/removed ids), `pos` (bbox origin moved
    >2px), `size` (bbox extent changed >2px), `z` (z-rank order changed);
    `certified: true` when `deltas` is empty. (probe-runner calibrated
    IoU gates against same-dpr self-diff noise; the 2px floor here is the
    self-diff floor observed on `lens-skeleton/1` captures — assert it in
    the self-diff test.)
- [ ] 5.3 Create `appboxd/lib/lens/states.dart`:
  `Future<Map<String, dynamic>> captureStates(String url, {required
  List<StateTrigger> triggers, int width = 390, int height = 844, int
  settleMs = 1500, int settleAfterMs = 600})` with
  ```dart
  class StateTrigger {
    const StateTrigger(this.selector, this.action);
    final String selector;
    final String action; // 'click' | 'hover' | 'focus'
  }
  ```
  Per trigger: screenshot before → dispatch (`click` via box-center +
  `tab.click`; `hover` via box-center + new `tab.hover`; `focus` via
  `evaluate('document.querySelector(s).focus()')`) → wait
  `settleAfterMs` → screenshot after → `getAnimations()` probe for
  transition metadata (reuse Task 4's WAAPI read) → `pixelDiff` the two
  screenshots. Emit `{url, states: [{selector, action, changed,
  diffPixels, transition, consoleErrors}], certified}` — `changed: false`
  is an observation, not a failure; `certified` rides on console errors
  only (lens doctrine). Add `CdpSession.hover` to `cdp.dart` next to the
  media plan's `click()` (do not modify `click()` itself).
- [ ] 5.4 Run both test files — all pass; full suite green.

---

## Task 6: Crawl — multi-route capture + token merge (TDD)

Ports `site_capture`'s flow (per-route skeleton + tokens + manifest,
one-hop same-origin crawl with robots.txt fail-closed) and `site_merge`
(cross-route palette clustering → `design_system.json`). Drops
`site_chrome` (structural-template chrome dedup — extraction-pipeline
machinery, no appbox consumer; recorded in capability-map). This is the
moodboard-at-scale capability the appbox-moodboarder skill fans out
manually today.

**Interfaces**
- Consumes: Task 3's tokens, Task 5's skeleton.
- Produces: `appboxd/lib/lens/crawl.dart`;
  `appboxd/test/lens_crawl_test.dart`.

### Steps

- [ ] 6.1 Write the failing test — `appboxd/test/lens_crawl_test.dart`.
  Fixture: ephemeral server with three routes `/a`, `/b`, `/c` sharing a
  palette, `/a` linking `/b` and an external URL, plus `/robots.txt`
  disallowing `/c`. Assert `crawlSite(baseUrl, routes: ['/a'], crawl:
  true)` produces `site.json` listing `/a` + `/b` (discovered, same
  origin), **not** `/c` (robots-disallowed), not the external URL; each
  route dir has `tokens.json` + `skeleton.json` + `shot.png`;
  `design_system.json` merges the shared palette into one cluster list.
  Robots parsing: probe-runner used `urllib.robotparser`; implement the
  `User-agent: *` / `Disallow:` prefix subset directly (20 lines — the
  fixture and appbox's own surfaces never use Allow/Crawl-delay;
  kimitail: Allow/rules-precedence unsupported, fail-closed treats
  unparsable robots.txt as disallow-all).
- [ ] 6.2 Create `appboxd/lib/lens/crawl.dart`:
  - `class CrawlResult { final List<String> routes; final String outDir;
    final List<String> skipped; }`
  - `Future<CrawlResult> crawlSite(String baseUrl, {List<String> routes =
    const ['/'], bool crawl = false, int crawlMax = 20, String? outDir,
    int width = 390, int height = 844, int settleMs = 1500, int delayMs =
    2000})` — outDir defaults to
    `designs/<detected-or-tmp>/evidence/crawl-<ts>/` under cwd when null;
    per route: `captureGolden` → `<outDir>/routes/rNN/shot.png`,
    `extractTokens` → `tokens.json`, `captureSkeleton` → `skeleton.json`;
    crawl expansion: collect same-origin links from each captured route's
    DOM (`evaluate` harvesting `a[href]`), dedup by URL fingerprint
    (path sans query hash), respect robots.txt (fail-closed), cap at
    `crawlMax`, politeness delay `delayMs` between route captures
    (probe-runner's 2s rule); write `site.json` manifest `{base, routes:
    [{route, dir, discovered}], skipped: [{url, reason}]}`.
  - `Future<Map<String, dynamic>> mergeDesignSystem(String siteDir)` —
    read every `routes/*/tokens.json`, cluster palettes by ΔE2000 < 6
    (single-linkage, pure Dart using `rgbToLab`/`deltaE2000Lab`), union
    type/spacing scales by value, write `design_system.json` `{palette:
    [{hex, routes: [...], count}], type: [...], spacing: [...]}`.
    (Ported `site_merge`; probe-runner's `_merge.py` semantics, ΔE
    clustering replacing its numpy path.)
  - Robots helper `Future<bool> robotsAllows(String baseUrl, String
    path)` — fetch `/robots.txt` via `HttpClient`, 404 → allow, parse
    `User-agent: *` group `Disallow:` prefixes, unparsable → disallow
    (fail-closed).
- [ ] 6.3 Run `dart test test/lens_crawl_test.dart` — pass; full suite
  green.

---

## Task 7: Wire `appbox lens <verb>` in the CLI

`appboxd/bin/appbox.dart` currently lists `lens` as future and falls
through to `unknown command`. This task adds the dispatch. All verbs are
thin argv→lib adapters; the lib functions are Tasks 1-6.

**Interfaces**
- Consumes: Tasks 1-6 lib modules; existing `_runEmit`/`_runServe` argv
  style in `bin/appbox.dart`.
- Produces: `appboxd/lib/lens_cli.dart` (`Future<int> runLens(List<String>
  args)`), `case 'lens':` in `bin/appbox.dart`, usage text;
  `appboxd/test/lens_cli_test.dart`; `tool/lens_shot.dart` unchanged
  (still valid).

### Steps

- [ ] 7.1 Write the failing test — `appboxd/test/lens_cli_test.dart`:
  drive `runLens([...])` against an ephemeral server, asserting exit
  codes and output files per verb: `shot` writes a PNG (exit 0);
  `compare` identical → 0, tampered golden → 1; `tokens` writes JSON with
  `certified: true`; `compare` with console errors on the page → 1
  regardless of pixels; unknown verb → 2 with usage on stderr.
- [ ] 7.2 Create `appboxd/lib/lens_cli.dart`. Verb table (each verb maps
  to one lib call; argv parsing follows `_runEmit`'s manual style —
  positional args then `--flag=value`):
  ```
  appbox lens shot <url> <out.png> [width] [height] [settleMs] [--full]
                                   → captureGolden
  appbox lens check <url> <out.png> [w] [h] [settle] [--selector=..] [--press=..] [--expect=..]
                                   → media plan's lens_check logic, moved
                                     verbatim into a lib function it and
                                     tool/lens_check.dart both call
  appbox lens compare <url> <golden.png> [w] [h] [--mode=byte|pixel|ssim] [--threshold=0.95]
                                   → compareGolden; exit 1 on fail
  appbox lens shoot <url> [--rungs=compact,medium,expanded] [--out=dir] [--artifact=dir]
                                   → ladder pass: captureGolden per rung
                                     (rung widths from
                                     skills/appbox-designer/runtime/ladder.json
                                     — the file ladder.json already is;
                                     --artifact/_d_meta.json .ladder
                                     override, then $APPBOX_LADDER, then
                                     --rungs, like shoot.mjs); per-rung
                                     console/request-failure collection;
                                     horizontal-overflow check via
                                     evaluate(scrollWidth>clientWidth);
                                     exit 1 if any rung has problems.
                                     (Supersedes designer shoot.mjs.)
  appbox lens tokens <url> [w] [h] [--out=path]     → extractTokens
  appbox lens dom <url> [--out=path] [--html]       → extractDom / extractOuterHtml
  appbox lens a11y <url> [--out=path]               → extractA11y
  appbox lens net <url> [--traceMs=3000] [--out=path] → traceNet
  appbox lens record <url> <out.mp4> [seconds] [fps] [w] [h] → recordVideo
  appbox lens burst <url> <out-dir> [count] [intervalMs] [w] [h] → burstFrames
  appbox lens anim <url> [w] [h] [--out=path]       → captureScrollAnim
  appbox lens flipbook <url> --trigger=<css> [--out=path] → captureFlipbook
  appbox lens skeleton <url> [--out=path] [w] [h]   → captureSkeleton
  appbox lens skeleton-diff <a.json> <b.json>       → diffSkeleton; exit 1 when deltas
  appbox lens states <url> --trigger=<css>:<click|hover|focus> [--trigger=..] [--out=path]
                                   → captureStates
  appbox lens crawl <baseUrl> [--routes=/a,/b] [--crawl] [--crawl-max=20] [--out=dir]
                                   → crawlSite + mergeDesignSystem
  ```
  `native` is dispatched to `runLensNative` (Tasks 8-11 add its cases; for
  this task, `native` prints `native verbs land in Tasks 8-11` and exits
  2 — the case exists so the wiring is tested once).
- [ ] 7.3 Edit `appboxd/bin/appbox.dart`: add `case 'lens':
  exitCode = await runLens(rest); break;` (check the file's actual
  main-loop convention — `_runGate` returns void + exits; match whatever
  shape neighboring cases use), import `lens_cli.dart`, replace the
  `lens  Visual gate (appbox lens — future)` usage line with the verb
  table summary, and delete `lens` from the header's "future" comment.
- [ ] 7.4 Move the media plan's `tool/lens_check.dart` logic: create
  `Future<int> lensCheck(List<String> args)` inside `lens_cli.dart`
  containing the driver body verbatim, re-point `tool/lens_check.dart` to
  `exit(await lensCheck(args));` (keep its header comment, add "logic
  lives in lib/lens_cli.dart"). The media plan owns that file until it
  completes — do this sub-step only if the media plan has landed; if it
  hasn't, land `lensCheck` and leave `tool/lens_check.dart` untouched
  (its creation supersedes this).
- [ ] 7.5 Run `dart test test/lens_cli_test.dart` — pass; full suite
  green. Smoke:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  node designs/appbox-studio/serve.mjs --port 4399 --no-watch &
  sleep 2
  cd appboxd && dart run bin/appbox.dart lens shot http://localhost:4399/dashboard /tmp/lens-cli-dash.png 390 844 2000
  dart run bin/appbox.dart lens tokens http://localhost:4399/dashboard 390 844 --out=/tmp/lens-cli-tokens.json
  cd .. && kill %1
  ```
  Expected: shot line printed, PNG > 10 KB; tokens JSON `certified:
  true`. (Node serve is still the design server until Task 19 — that is
  expected at this point in the plan.)

---

## Task 8: Native — adb wrappers (TDD with faked runner)

Ports the capture-relevant `adb_*` verbs to
`appboxd/lib/lens/native/adb.dart`, driven through the `ProcessRunner`
seam (`appboxd/lib/process.dart`) so tests use scripted fakes — no
emulator required. Interaction verbs are dropped with reason (Patrol /
native-E2E owns interaction truth; see capability-map Task 13).

**Interfaces**
- Consumes: `lib/process.dart` `ProcessRunner`/`RealProcessRunner`.
- Produces: `appboxd/lib/lens/native/adb.dart`;
  `appboxd/test/lens_adb_test.dart`; `native adb` cases in
  `lens_cli.dart`'s `runLensNative`.

### Steps

- [ ] 8.1 Write the failing test — `appboxd/test/lens_adb_test.dart`:
  a `ScriptedRunner` fake (same pattern as `deploy.py`'s ScriptedRunner,
  already mirrored by `lib/tier1.dart` tests): preloaded
  argv-prefix → `RunnerResult` expectations, asserting order. Cases:
  - `adbShot` runs `adb -s <serial> exec-out screencap -p`, writes PNG
    bytes to out path; non-zero exit → `LensNativeException` carrying the
    stderr remediation line.
  - `adbRecord` runs `shell screenrecord --time-limit 5 /sdcard/lens.mp4`
    then `pull`, then `shell rm`; missing pulled file → exception.
  - `adbDevices` parses `List of devices attached\nemulator-5554\tdevice\n`
    into `[{serial: emulator-5554, state: device}]`, skipping
    `offline`/`unauthorized` with a warning field.
  - `adbOpenUrl` runs `shell am start -a android.intent.action.VIEW -d
    <url>`.
  - `adbUiTree` runs `shell uiautomator dump /sdcard/lens-ui.xml` + pull,
    converts the XML bounds attributes (`[x1,y1][x2,y2]`) into JSON nodes
    `{class, text, bounds: [x,y,w,h]}` (parse with `RegExp` over the
    dumped XML — no XML dependency; the uiautomator schema is flat
    `<node>` nesting, one attribute pattern).
  - serial resolution: explicit arg > `$APPBOX_ADB_SERIAL` env >
    single-connected-device auto-pick > error listing devices.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 8.2 Create `appboxd/lib/lens/native/adb.dart`:
  ```dart
  /// Android capture verbs (ports probe-runner adb_shot/adb_record/
  /// adb_list/adb_url/adb_ui_tree/adb_log). Thin ProcessRunner wrappers —
  /// capture and observation only; interaction belongs to Patrol.
  library;

  import 'dart:io';

  import '../../process.dart';

  class LensNativeException implements Exception {
    LensNativeException(this.message);
    final String message;
    @override
    String toString() => 'LensNativeException: $message';
  }

  class LensAdb {
    LensAdb({String? serial, ProcessRunner? runner})
        : _serial = serial ?? Platform.environment['APPBOX_ADB_SERIAL'],
          _runner = runner ?? const RealProcessRunner();

    final String? _serial;
    final ProcessRunner _runner;

    List<String> _base(String serial) => ['-s', serial];

    Future<String> _requireSerial() async {
      if (_serial != null) return _serial;
      final devices = await devices();
      final up = devices.where((d) => d['state'] == 'device').toList();
      if (up.length == 1) return up.first['serial']!;
      throw LensNativeException(up.isEmpty
          ? 'no adb device in state "device" — boot an emulator or pass --serial'
          : 'multiple adb devices — pass --serial (${up.map((d) => d['serial']).join(', ')})');
    }

    Future<List<Map<String, String>>> devices() async {
      final r = await _runner.run('adb', ['devices']);
      final out = <Map<String, String>>[];
      for (final line in (r.stdout as String).split('\n').skip(1)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 && parts[0].isNotEmpty) {
          out.add({'serial': parts[0], 'state': parts[1]});
        }
      }
      return out;
    }

    /// exec-out screencap: exact bytes, no sdcard roundtrip.
    Future<void> shot(String outPng) async {
      final serial = await _requireSerial();
      final r = await _runner.run('adb', [..._base(serial), 'exec-out', 'screencap', '-p']);
      if (r.exitCode != 0) {
        throw LensNativeException('adb screencap failed: ${r.stderr}');
      }
      final f = File(outPng);
      f.parent.createSync(recursive: true);
      await f.writeAsBytes(r.stdoutBytes ?? const []);
    }

    /// screenrecord to sdcard then pull (<=180s platform cap).
    Future<void> record(String outMp4, {int seconds = 10}) async {
      if (seconds > 180) {
        throw LensNativeException('screenrecord caps at 180s (got $seconds)');
      }
      final serial = await _requireSerial();
      const remote = '/sdcard/lens-record.mp4';
      final r = await _runner.run('adb', [..._base(serial), 'shell',
          'screenrecord', '--time-limit', '$seconds', remote]);
      if (r.exitCode != 0) {
        throw LensNativeException('adb screenrecord failed: ${r.stderr}');
      }
      await _runner.run('adb', [..._base(serial), 'pull', remote, outMp4]);
      await _runner.run('adb', [..._base(serial), 'shell', 'rm', remote]);
      if (!File(outMp4).existsSync()) {
        throw LensNativeException('screenrecord pull produced no file at $outMp4');
      }
    }

    Future<void> openUrl(String url) async {
      final serial = await _requireSerial();
      final r = await _runner.run('adb', [..._base(serial), 'shell', 'am',
          'start', '-a', 'android.intent.action.VIEW', '-d', url]);
      if (r.exitCode != 0) {
        throw LensNativeException('adb am start failed: ${r.stderr}');
      }
    }

    /// uiautomator dump -> JSON node list (device-pixel bounds).
    Future<List<Map<String, dynamic>>> uiTree() async {
      final serial = await _requireSerial();
      const remote = '/sdcard/lens-ui.xml';
      await _runner.run('adb', [..._base(serial), 'shell', 'uiautomator', 'dump', remote]);
      final pulled = await _runner.run('adb', [..._base(serial), 'shell', 'cat', remote]);
      final xml = pulled.stdout as String;
      final nodes = <Map<String, dynamic>>[];
      final re = RegExp(
          '<node[^>]*class="([^"]*)"[^>]*text="([^"]*)"[^>]*bounds="\\[(\\d+),(\\d+)\\]\\[(\\d+),(\\d+)\\]"');
      for (final m in re.allMatches(xml)) {
        final x1 = int.parse(m[3]!), y1 = int.parse(m[4]!);
        nodes.add({
          'class': m[1],
          'text': m[2],
          'bounds': [x1, y1, int.parse(m[5]!) - x1, int.parse(m[6]!) - y1],
        });
      }
      return nodes;
    }
  }
  ```
  Note: `ProcessRunner`/`RunnerResult` in `lib/process.dart` — check its
  exact field names (`stdout` type, whether raw bytes are exposed for
  `exec-out`; if `RunnerResult` is String-only, add a
  `Future<RunnerResult> runBytes(...)` to the interface alongside the
  existing method rather than changing it). Adjust the code above to the
  real seam; the tests pin the behavior either way.
- [ ] 8.3 Add `native adb` cases to `runLensNative` in
  `appboxd/lib/lens_cli.dart`: `shot <out.png> [--serial=]`, `record
  <out.mp4> [seconds] [--serial=]`, `list`, `url <url>`, `ui-tree
  [--out=path]`. Run the tests — pass; full suite green.

---

## Task 9: Native — simctl wrappers (TDD with faked runner)

Ports the capture-relevant `ios_*` verbs to
`appboxd/lib/lens/native/simctl.dart`. All `idb`-dependent verbs are
dropped with reason (external dependency, Patrol owns interaction).

**Interfaces**
- Consumes: `lib/process.dart` seam; Task 8's exception + test pattern.
- Produces: `appboxd/lib/lens/native/simctl.dart`;
  `appboxd/test/lens_simctl_test.dart`; `native ios` cases in
  `runLensNative`.

### Steps

- [ ] 9.1 Write the failing test — `appboxd/test/lens_simctl_test.dart`
  (ScriptedRunner pattern as Task 8). Cases:
  - `iosShot` runs `xcrun simctl io booted screenshot --type png
    <out>`; exit≠0 → `LensNativeException` with stderr.
  - `iosRecord` starts `xcrun simctl io booted recordVideo --codec h264
    <out>` as a background process, waits `seconds`, sends SIGINT
    (simctl finalizes the mp4 on interrupt), asserts the file exists.
    With the fake runner, assert the argv prefix and that `stop()` was
    issued.
  - `iosDevices` parses `xcrun simctl list devices --json` into
    `[{udid, name, state, runtime}]`, booted first.
  - `iosStatusBar` runs `xcrun simctl status_bar booted override --time
    9:41 --batteryLevel 100 --cellularBars 4 --wifiBars 3` (the golden
    capture convention — deterministic chrome for evidence shots);
    `iosStatusBarClear` runs `... clear`.
  - `iosAppearance` runs `xcrun simctl ui booted appearance dark|light`.
  - `iosOpenUrl` runs `xcrun simctl openurl booted <url>`.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 9.2 Create `appboxd/lib/lens/native/simctl.dart` — same class shape
  as `LensAdb`:
  ```dart
  /// iOS simulator capture verbs (ports probe-runner ios_shot/ios_record/
  /// ios_list/ios_url/ios_status_bar/ios_appearance). Capture and
  /// deterministic-chrome only; idb-dependent interaction is dropped
  /// (Patrol owns it). xcrun is spawned; tests fake the runner.
  library;

  class LensSimctl {
    LensSimctl({String udid = 'booted', ProcessRunner? runner})
        : _udid = udid, _runner = runner ?? const RealProcessRunner();
    final String _udid;
    final ProcessRunner _runner;

    /// Run `xcrun <args>`; throw LensNativeException on exit != 0 with
    /// stderr attached.
    Future<void> _checked(List<String> args) async {
      final r = await _runner.run('xcrun', args);
      if (r.exitCode != 0) {
        throw LensNativeException('xcrun ${args.join(' ')} failed: ${r.stderr}');
      }
    }

    /// Injectable process starter for recordVideo (tests fake it).
    Future<Process> Function(List<String> args) _start =
        (args) => Process.start('xcrun', args);

    Future<void> shot(String outPng) async {
      File(outPng).parent.createSync(recursive: true);
      await _checked(
          ['simctl', 'io', _udid, 'screenshot', '--type', 'png', outPng]);
    }

    Future<void> statusBarOverride() => _checked([
        'simctl', 'status_bar', _udid, 'override',
        '--time', '9:41', '--batteryLevel', '100',
        '--cellularBars', '4', '--wifiBars', '3']);
    Future<void> statusBarClear() =>
        _checked(['simctl', 'status_bar', _udid, 'clear']);
    Future<void> appearance(String mode) { // 'dark' | 'light'
      if (mode != 'dark' && mode != 'light') {
        throw LensNativeException('appearance must be dark|light (got $mode)');
      }
      return _checked(['simctl', 'ui', _udid, 'appearance', mode]);
    }
    Future<void> openUrl(String url) =>
        _checked(['simctl', 'openurl', _udid, url]);

    Future<List<Map<String, String?>>> devices() async {
      final r = await _runner.run('xcrun', ['simctl', 'list', 'devices', '--json']);
      final parsed = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      final out = <Map<String, String?>>[];
      for (final e in (parsed['devices'] as Map).entries) {
        for (final d in e.value as List) {
          out.add({
            'udid': d['udid'], 'name': d['name'],
            'state': d['state'], 'runtime': e.key,
          });
        }
      }
      out.sort((a, b) => (b['state'] == 'Booted' ? 1 : 0)
          .compareTo(a['state'] == 'Booted' ? 1 : 0));
      return out;
    }

    /// recordVideo runs until SIGINT; simctl finalizes the mp4 on
    /// interrupt. Uses a live Process (not the RunnerResult seam) — the
    /// seam gets a startProcess addition or this method takes an
    /// injectable starter; tests inject a fake that records argv and
    /// fakes the file landing.
    Future<void> record(String outMp4, {int seconds = 10}) async {
      File(outMp4).parent.createSync(recursive: true);
      final proc = await _start([
        'simctl', 'io', _udid, 'recordVideo', '--codec', 'h264', outMp4]);
      await Future.delayed(Duration(seconds: seconds));
      proc.kill(ProcessSignal.sigint);
      final code = await proc.exitCode;
      if (code != 0 && !File(outMp4).existsSync()) {
        throw LensNativeException('simctl recordVideo exited $code, no file');
      }
    }
  }
  ```
  The full file adds the imports (`dart:convert`, `dart:io`,
  `../../process.dart`) and the `LensNativeException` import from
  `adb.dart`; every other member is above and behavior is pinned by
  9.1's tests.
- [ ] 9.3 Add `native ios` cases to `runLensNative`: `shot <out.png>
  [--udid=]`, `record <out.mp4> [seconds] [--udid=]`, `list`, `url
  <url>`, `status-bar [--clear]`, `appearance <dark|light>`. Run tests —
  pass; full suite green.

---

## Task 10: Native — macOS SCK shot + Vision OCR (Swift helper CLI)

Ports `shot.py` (ScreenCaptureKit window/screen capture) and `ocr.py` +
`text_diff.py` (macOS Vision text recognition + diff) as one small Swift
CLI compiled on demand, plus `appboxd/lib/lens/native/sck.dart` and
`appboxd/lib/lens/ocr.dart` Dart wrappers. `vision_probe` (face/body/
rect/barcode/saliency detectors) is dropped with reason (no gate
consumer; re-add from archive when one appears).

**Interfaces**
- Consumes: research (SCScreenshotManager one-shot, TCC preflight);
  `lib/process.dart` seam.
- Produces: `appboxd/tool/native/lens_macos.swift` (single-file CLI);
  `appboxd/lib/lens/native/sck.dart`; `appboxd/lib/lens/ocr.dart`;
  `appboxd/test/lens_sck_test.dart`, `lens_ocr_test.dart`; `native macos
  shot` + lens `ocr`/`text-diff` CLI cases.

### Steps

- [ ] 10.1 Write the failing tests:
  - `lens_sck_test.dart` — compile-on-demand: `ensureLensMacosBinary()`
    returns a path; if the cached binary at
    `~/.appbox/bin/lens_macos` (or `.dart_tool/` — pick
    `.dart_tool/appboxd/lens_macos`, repo-local, gitignored) is missing
    or older than the .swift source, it runs `swiftc -O
    tool/native/lens_macos.swift -o <cache>`; `swiftc` absent →
    `LensNativeException` with remediation ("install Xcode CLT:
    xcode-select --install"). Runner faked; assert argv.
  - `lens_ocr_test.dart` — `ocrText(pngPath)` spawns `<bin> ocr <png>`,
    parses JSON `{text: [...], observations: [{text, confidence,
    bbox}]}`; `textDiffPngs(a, b)` runs OCR on both and returns a
    line-level diff (Dart `diff` — implement the simple LCS over lines,
    40 lines; probe-runner used difflib, same family). Faked runner
    returns canned JSON.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 10.2 Create `appboxd/tool/native/lens_macos.swift` — complete CLI
  (macOS 14+; ~120 lines):
  ```swift
  // lens_macos — appbox lens macOS helper: ScreenCaptureKit one-shot
  // capture + Vision OCR. Single file, no packages.
  // Usage: lens_macos shot <out.png> [--window-id N] [--display]
  //        lens_macos ocr <image.png>
  //        lens_macos tcc-check
  import Foundation
  import ScreenCaptureKit
  import Vision
  import CoreGraphics
  import ImageIO
  import UniformTypeIdentifiers

  let args = CommandLine.arguments
  guard args.count >= 2 else {
      FileHandle.standardError.write("usage: lens_macos shot|ocr|tcc-check ...\n".data(using: .utf8)!)
      exit(64)
  }

  func writePng(_ image: CGImage, to path: String) throws {
      let url = URL(fileURLWithPath: path)
      guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
      else { throw NSError(domain: "lens", code: 1) }
      CGImageDestinationAddImage(dest, image, nil)
      if !CGImageDestinationFinalize(dest) { throw NSError(domain: "lens", code: 2) }
  }

  switch args[1] {
  case "tcc-check":
      // Screen Recording grant follows the responsible terminal process.
      exit(CGPreflightScreenCaptureAccess() ? 0 : 3)
  case "shot":
      guard args.count >= 3 else { exit(64) }
      let out = args[2]
      let sem = DispatchSemaphore(value: 0)
      var code: Int32 = 0
      Task {
          do {
              let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
              let filter: SCContentFilter
              if let wi = args.firstIndex(of: "--window-id"), let id = Int(args[wi + 1]),
                 let win = content.windows.first(where: { $0.windowID == CGWindowID(id) }) {
                  filter = SCContentFilter(desktopIndependentWindow: win)
              } else if let display = content.displays.first {
                  filter = SCContentFilter(display: display, excludingWindows: [])
              } else {
                  FileHandle.standardError.write("no capturable target\n".data(using: .utf8)!); exit(2)
              }
              let config = SCStreamConfiguration()
              config.showsCursor = false
              let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
              try writePng(image, to: out)
          } catch {
              FileHandle.standardError.write("shot failed: \(error.localizedDescription)\n".data(using: .utf8)!)
              code = 1
          }
          sem.signal()
      }
      sem.wait()
      exit(code)
  case "ocr":
      guard args.count >= 3 else { exit(64) }
      let url = URL(fileURLWithPath: args[2])
      guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
      else { FileHandle.standardError.write("unreadable image\n".data(using: .utf8)!); exit(2) }
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      let handler = VNImageRequestHandler(cgImage: image)
      try handler.perform([request])
      var observations: [[String: Any]] = []
      var texts: [String] = []
      for obs in request.results ?? [] {
          guard let top = obs.topCandidates(1).first else { continue }
          texts.append(top.string)
          observations.append([
              "text": top.string,
              "confidence": top.confidence,
              "bbox": [obs.boundingBox.origin.x, obs.boundingBox.origin.y,
                       obs.boundingBox.size.width, obs.boundingBox.size.height],
          ])
      }
      let json: [String: Any] = ["text": texts, "observations": observations]
      let data = try JSONSerialization.data(withJSONObject: json)
      FileHandle.standardOutput.write(data)
      exit(0)
  default:
      exit(64)
  }
  ```
- [ ] 10.3 Create `appboxd/lib/lens/native/sck.dart`:
  `Future<String> ensureLensMacosBinary({ProcessRunner? runner})` —
  compile-on-demand with mtime check into
  `.dart_tool/appboxd/lens_macos`; `class LensSck { LensSck({ProcessRunner?
  runner}); Future<void> shot(String outPng, {int? windowId});
  Future<bool> tccOk(); }` — `shot` preflights `tcc-check` and on rc=3
  throws with remediation ("grant Screen Recording to your terminal in
  System Settings → Privacy & Security"). `lens_ocr.dart`:
  `Future<Map<String, dynamic>> ocrText(String pngPath)` and
  `List<String> textDiffLines(List<String> a, List<String> b)` (LCS over
  lines, `+`/`-` prefixed output).
- [ ] 10.4 Wire CLI: `appbox lens native macos shot <out.png>
  [--window-id=N]`; `appbox lens ocr <image.png> [--out=path]`;
  `appbox lens text-diff <a.png> <b.png>` (exit 1 when text differs).
  Compile check (real, on this Mac):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  swiftc -O tool/native/lens_macos.swift -o /tmp/lens_macos_check && /tmp/lens_macos_check tcc-check; echo "rc=$?"
  ```
  Expected: compiles clean; `rc=0` or `rc=3` depending on the terminal's
  TCC grant (both are success here — the preflight works). Then `dart
  test` full suite green.

---

## Task 11: Native — Flutter VM service (TDD)

Ports the capture/inspect core of probe-runner's `flutter_*` block to
`appboxd/lib/lens/native/flutter_vm.dart`: attach/URL discovery, generic
RPC, `ext.flutter.screenshot`, tree dumps, Dart eval, semantics toggle,
perf diagnostics. Raw `dart:io` WebSocket JSON-RPC (no `vm_service`
package — the protocol is CDP-shaped and `cdp.dart` proves the pattern).
Dropped with reason: `flutter_tap`/`flutter_set_text`/`flutter_reload`/
`flutter_flipbook`/`flutter_anim`/`flutter_inspect`/`flutter_find`
(interaction + app-coupled probes — Patrol/flutter_test own them).

**Interfaces**
- Consumes: nothing from earlier tasks (pure transport; may run parallel
  to Tasks 8-10).
- Produces: `appboxd/lib/lens/native/flutter_vm.dart`;
  `appboxd/test/lens_flutter_vm_test.dart` (fake WebSocket server via
  `dart:io`); `native flutter` cases in `runLensNative`.

### Steps

- [ ] 11.1 Write the failing test —
  `appboxd/test/lens_flutter_vm_test.dart`: stand up a real
  `HttpServer` + `WebSocketTransformer.upgrade` fake VM service that
  answers JSON-RPC: `getVM` → `{isolates: [{id: 'isolates/1'}]}`,
  `ext.flutter.screenshot` → `{screenshot: '<base64 png 1x1>'}`,
  `ext.flutter.debugDumpRenderTree` → `{value: 'RenderView…'}`,
  `getRootLibrary`/`evaluate` canned. Assert: `FlutterVm.connect`
  upgrades `http://…/token=/` → `ws://…/token=/ws` and matches responses
  by id; `mainIsolateId` returns `isolates/1`; `screenshot()` decodes
  base64; `callServiceExtension` passes `isolateId`; a JSON-RPC `error`
  response throws `LensVmException` with the message; unsolicited
  `streamNotify` events land on `events`. Also test
  `parseVmServiceUri('The Dart VM service is listening on
  http://127.0.0.1:50123/abc=/')` → the URI, and the `flutter run
  --machine` JSON-line form (`{"event":"app.debugPort","params":
  {"wsUri":"ws://…/ws"}}`).
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 11.2 Create `appboxd/lib/lens/native/flutter_vm.dart` — the RPC
  core, complete (this is the tricky part):
  ```dart
  /// Flutter VM service client (ports probe-runner _flutter/flutter_vm/
  /// flutter_attach/flutter_shot/flutter_tree/flutter_eval/
  /// flutter_semantics/flutter_diag). Raw dart:io WebSocket JSON-RPC —
  /// same protocol shape as CDP, no vm_service dependency.
  library;

  import 'dart:async';
  import 'dart:convert';
  import 'dart:io';

  class LensVmException implements Exception {
    LensVmException(this.message);
    final String message;
    @override
    String toString() => 'LensVmException: $message';
  }

  /// Extract a VM service URI from tool output. Handles the interactive
  /// form ('The Dart VM service is listening on http://…/') and the
  /// --machine JSON event form.
  static String? parseVmServiceUri(String text) {
    final plain = RegExp(r'https?://\S+?/\S*/').firstMatch(text);
    if (plain != null && text.contains('VM service')) return plain.group(0);
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('{')) continue;
      try {
        final ev = jsonDecode(line) as Map;
        if (ev['event'] == 'app.debugPort') {
          return (ev['params'] as Map)['wsUri'] as String?;
        }
      } catch (_) {/* not a json line */}
    }
    return null;
  }

  class FlutterVm {
    FlutterVm._(this._ws);
    final WebSocket _ws;
    var _id = 0;
    final _pending = <int, Completer<Map<String, dynamic>>>{};
    final _events = StreamController<Map<String, dynamic>>.broadcast();
    StreamSubscription? _sub;

    /// VM service stream events (Extension, Debug, Isolate, …).
    Stream<Map<String, dynamic>> get events => _events.stream;

    /// Connect to a VM service URI in http(s) or ws(s) form. DDS proxy
    /// URIs (flutter run default) work unchanged.
    static Future<FlutterVm> connect(String uri) {
      var ws = uri;
      if (ws.startsWith('http://')) ws = 'ws://${ws.substring(7)}';
      if (ws.startsWith('https://')) ws = 'wss://${ws.substring(8)}';
      if (!ws.endsWith('/ws')) ws = '${ws.endsWith('/') ? ws : '$ws/'}ws';
      return WebSocket.connect(ws).then(FlutterVm._);
    }

    void _listen() {
      _sub = _ws.listen((data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        final id = msg['id'];
        if (id != null && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(msg);
        } else {
          _events.add(msg);
        }
      });
    }

    /// Start listening (call once after connect).
    void start() => _listen();

    /// Generic JSON-RPC call. Throws LensVmException on a protocol error.
    Future<Map<String, dynamic>> rpc(String method,
        [Map<String, dynamic>? params]) {
      final id = ++_id;
      final c = Completer<Map<String, dynamic>>();
      _pending[id] = c;
      _ws.add(jsonEncode({
        'jsonrpc': '2.0', 'id': id, 'method': method,
        if (params != null) 'params': params,
      }));
      return c.future.timeout(const Duration(seconds: 30), onTimeout: () {
        _pending.remove(id);
        throw LensVmException('VM service timeout on $method');
      }).then((msg) {
        final err = msg['error'];
        if (err != null) {
          throw LensVmException('$method: ${(err as Map)['message']}');
        }
        return (msg['result'] as Map?)?.cast<String, dynamic>() ?? {};
      });
    }

    Future<String> mainIsolateId() async {
      final vm = await rpc('getVM');
      final isolates = vm['isolates'] as List?;
      if (isolates == null || isolates.isEmpty) {
        throw LensVmException('no isolates — is a Flutter app attached?');
      }
      return (isolates.first as Map)['id'] as String;
    }

    /// Call a service extension (ext.flutter.*) against an isolate.
    Future<Map<String, dynamic>> callServiceExtension(String method,
        {String? isolateId, Map<String, dynamic>? args}) async {
      return rpc(method, {
        'isolateId': isolateId ?? await mainIsolateId(),
        if (args != null) 'args': args,
      });
    }

    /// ext.flutter.screenshot (debug/profile builds only) -> PNG bytes.
    Future<List<int>> screenshot() async {
      final r = await callServiceExtension('ext.flutter.screenshot');
      final b64 = r['screenshot'] as String?;
      if (b64 == null) {
        throw LensVmException('ext.flutter.screenshot unavailable — '
            'release build or pre-2.x Flutter? (extension exists in '
            'debug/profile only)');
      }
      return base64Decode(b64);
    }

    Future<String> dumpRenderTree() async =>
        (await callServiceExtension('ext.flutter.debugDumpRenderTree'))['value'] as String;
    Future<String> dumpWidgetTree() async =>
        (await callServiceExtension('ext.flutter.debugDumpApp'))['value'] as String;
    Future<String> dumpSemanticsTree() async =>
        (await callServiceExtension('ext.flutter.debugDumpSemanticsTreeInTraversalOrder'))['value'] as String;

    /// Toggle a boolean debug extension (debugPaint, repaintRainbow,
    /// performanceOverlay, …).
    Future<void> setFlag(String ext, bool enabled) =>
        callServiceExtension(ext, args: {'enabled': '$enabled'});

    /// Evaluate a Dart expression in the isolate's root library
    /// (probe-runner's VMLib path).
    Future<dynamic> evalDart(String expression) async {
      final isolate = await mainIsolateId();
      final iso = await rpc('getIsolate', {'isolateId': isolate});
      final rootLib = ((iso['rootLib'] ?? iso['libraries']?[0]) as Map)['id'];
      final r = await rpc('evaluate', {
        'isolateId': isolate,
        'targetId': rootLib,
        'expression': expression,
      });
      return r['valueAsString'] ?? r;
    }

    Future<void> dispose() async {
      await _sub?.cancel();
      await _events.close();
      await _ws.close();
    }
  }
  ```
  (probe-runner's newline-collapse and truncated-value `getObject`
  workaround: port the `getObject` fallback in `evalDart` only if the
  fixture tests show truncation — kimitail: added on evidence, not
  preemptively.)
- [ ] 11.3 Add `native flutter` cases to `runLensNative`: `shot <out.png>
  [--uri=]` (uri or `$APPBOX_FLUTTER_VM`, else read
  `pipeline/state/flutter-vm.uri` cache file written by the runner),
  `attach [--from-log=path]` (prints the discovered URI and caches it),
  `tree [--kind=render|widget|semantics] [--out=]`, `eval <expr>`,
  `semantics <on|off>` (`ext.flutter.showSemantics`), `diag
  <debugPaint|repaintRainbow|performanceOverlay> <on|off>`, `vm <method>
  [--params=<json>]` (generic RPC — the `flutter_vm.py` escape hatch).
- [ ] 11.4 Run `dart test test/lens_flutter_vm_test.dart` — pass; full
  suite green.

---

## Task 12: The lens gate — design-vs-built as a pipeline gate

The point of the whole port (dart-only plan §6): pixel (SSIM), skeleton,
and colour (ΔE) against the frozen golden, console-error auto-fail, as a
first-class gate in the framework of `appboxd/lib/gates.dart`.

**Interfaces**
- Consumes: Tasks 1 (pixels), 3 (tokens), 5 (skeleton), 7 (CLI);
  `gates.dart` framework; `phases.dart`/`gate_runner.dart` wiring points.
- Produces: `appboxd/lib/gate_lens.dart` (`lensGate(GateContext ctx,
  {bool recaptureGoldens = false})`); wiring in `gate_runner.dart`
  (`gateOrder` + `_tryDartGate` case), `bin/appbox.dart`
  (`_dispatchGate`), `phases.dart` (`phaseGates`);
  `appboxd/test/gate_lens_test.dart`; config schema note.

### Steps

- [ ] 12.1 Write the failing test — `appboxd/test/gate_lens_test.dart`
  (follow `tool/_scaffold_smoke.dart`'s GateContext construction and the
  gate tests' temp-repo pattern): build a temp repo root with
  `config/appbox.config.json` carrying a `lens` block:
  ```json
  {
    "targets": ["web"],
    "viewports": {"mobile": {"width": 390, "height": 844}},
    "lens": {
      "goldens": "designs/appbox-studio/goldens",
      "surfaces": {"home": "/"},
      "serve": {"kind": "url", "base": "http://127.0.0.1:PORT"},
      "capture": {"kind": "same"},
      "modes": {"compare": "ssim", "threshold": 0.98}
    }
  }
  ```
  Assert: (a) with goldens captured from the fixture server, the gate
  passes and writes evidence PNGs + SARIF-clean details; (b) after
  changing the fixture page's colour, the gate fails with `✗` details
  naming the surface and its SSIM score; (c) a page with a console error
  fails regardless of pixels; (d) no `lens` config block →
  `GateResult.env` (exit 2, skipped not failed); (e)
  `recaptureGoldens: true` rewrites the goldens (the frozen-approval
  flow).
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 12.2 Create `appboxd/lib/gate_lens.dart`. Contract (match
  `gate_freeze.dart`'s shape): top-level
  ```dart
  Future<GateResult> lensGate(GateContext ctx,
      {bool recaptureGoldens = false}) async
  ```
  Behavior: read `lens` block from `ctx.configFile` (absent →
  `GateResult.env('no lens config — gate skipped')`); resolve surfaces
  name→path; per surface × per configured viewport rung: capture via
  `captureGolden`/`compareGolden` with `LensMode` from config
  (`ssim` default, `threshold` default 0.98), console/page errors
  auto-fail; `serve.kind: url` compares against a live base URL,
  `serve.kind: static` boots a `_bindStaticServer`-style server over
  `designRoot` (reuse `gate_freeze.dart`'s pattern), `capture.kind:
  same` uses CDP for both sides (v1: design-rendered goldens vs current
  render — determinism + console gate); `capture.kind: flutter-vm` /
  `macos-sck` capture the built side via Tasks 10-11 (wire the call,
  `GateResult.env` when the tool is unavailable). Evidence to
  `<design>/evidence/lens-gate/<surface>-<width>.png`; goldens at the
  configured dir; recapture only via `recaptureGoldens` (the
  freeze-gate approval pattern — print the recaptured list loudly).
  Details accumulate `✓ surface@width SSIM 0.997` / `✗ surface@width
  SSIM 0.81 (< 0.98)`; findings to `ctx.sarif`.
- [ ] 12.3 Wire it: add `'lens'` to `gateOrder` in
  `appboxd/lib/gate_runner.dart` after `'native_deps'` (before
  `'deploy'`); add the case in `_tryDartGate`; add `case 'lens': return
  lensGate(ctx);` in `_dispatchGate` (`bin/appbox.dart`); add `lens` to
  the usage gate list (`bin/appbox.dart:132`); in
  `appboxd/lib/phases.dart` change the `build` entry to `[native_deps,
  lens]`. Add the selftest path: `appbox gate lens --self-test` builds
  the temp fixture repo (same code as the test) and prints PASS/FAIL
  lines including a `# NEGATIVE:` case (tampered surface must fail) —
  the gates-must-be-able-to-fail contract.
- [ ] 12.4 Run `dart test test/gate_lens_test.dart` — pass; `dart test`
  full suite green; `dart run bin/appbox.dart gate lens --self-test`
  prints its checks ending in pass.

---

## Task 13: Capability map — full audit to green + lens skill docs

Rewrite `skills/appbox-lens/capability-map.md` so every probe-runner
verb is **ported** (with its new name) or **dropped with reason**, and
refresh `skills/appbox-lens/SKILL.md` to the `appbox lens` CLI. This is
the plan's scoreboard.

**Interfaces**
- Consumes: Tasks 1-12 (everything the map points at).
- Produces: rewritten `skills/appbox-lens/capability-map.md` +
  `skills/appbox-lens/SKILL.md` (+ mirrors); `docs/VOCABULARY.md` lens
  entry refreshed if it names verbs.

### Steps

- [ ] 13.1 Rewrite `skills/appbox-lens/capability-map.md` with three
  tables. Web block — ported rows:
  `web_open/web_launch → navigateAndSettle (ported)`;
  `web_shot → lens shot / captureGolden (ported)`;
  `web_emu → setViewport + lens shoot ladder (ported)`;
  `web_scroll → evaluate + screenshot(fullPage) (ported)`;
  `web_eval → evaluate/evaluateFunction + lens check --expect (ported)`;
  `web_console → consoleErrors auto-fail (ported)`;
  `web_click/web_key → CdpSession.click/key (ported, media plan)`;
  `web_type → evaluate value-set via lens check --expect / JS (ported)`;
  `web_hover → CdpSession.hover (ported, Task 5)`;
  `web_tokens → lens tokens (ported, Task 3)`;
  `web_dom → lens dom (ported, Task 3)`;
  `web_a11y → lens a11y (ported, Task 3)`;
  `web_net → lens net (ported, Task 3)`;
  `web_anim → lens anim (ported, Task 4)`;
  `web_flipbook → lens flipbook (ported, Task 4)`;
  `web_record → lens record (ported, Task 4)`;
  `multishot → lens burst (ported, Task 4)`;
  `web_states → lens states (ported, Task 5)`;
  `web_skeleton → lens skeleton (lens-skeleton/1) (ported, Task 5)`;
  `skeleton_diff → lens skeleton-diff (ported, Task 5)`;
  `pixdiff → lens compare --mode=ssim|pixel|byte (ported, Task 1)`;
  `color_assert → deltaE2000Lab/regionMeanLab in lens/pixels (ported, Task 1)`;
  `text_diff + ocr → lens text-diff / lens ocr (ported, Task 10)`;
  `site_capture/crawl_* → lens crawl (ported, Task 6)`;
  `site_merge → mergeDesignSystem (ported, Task 6)`;
  `design_golden → gate_lens (ported, Task 12)`.
  Web block — dropped rows: `web_vectors` (vtracer external binary,
  non-certified research output — no consumer); `vision_probe`
  (face/body/rect/barcode/saliency — no gate consumer; Swift Vision CLI
  from Task 10 is the re-entry point); Safari/selenium fallback paths in
  `_web/_web_eval/web_click/web_type/web_dom/ios_safari` (Chrome-only
  doctrine — one render engine, the one appbox gates on);
  `content_firewall/slots/bundle_writer/motion_adapter/site_chrome`
  (ADR-0001 extraction-pipeline machinery — appbox authors designs,
  nothing consumes content-free bundles);
  `web_states`' consent/keyframes sub-cores `_consent/_keyframes`
  (consent-banner detection + keyframe extraction — research machinery,
  no consumer; `getAnimations()` oracle covers keyframes).
  Native — ported: `adb_list/adb_shot/adb_record/adb_url/adb_ui_tree →
  lens native adb … (Task 8)`; `ios_list/ios_shot/ios_record/ios_url/
  ios_status_bar/ios_appearance → lens native ios … (Task 9)`;
  `shot.py (SCK) → lens native macos shot (Task 10)`;
  `flutter_attach/flutter_vm/flutter_shot/flutter_tree/flutter_eval/
  flutter_semantics/flutter_diag → lens native flutter … (Task 11)`.
  Native — dropped: all `adb` interaction verbs (tap/swipe/type/key/
  intent/push/files/boot/settings/perm/location/app) and `adb_cdp/
  adb_flipbook` (Patrol / native-E2E owns interaction; `adb_cdp`'s
  forward+CDP trick re-addable from archive when an Android-web gate
  asks); all `idb`-dependent ios verbs (tap/swipe/type/key/ui_tree/log/
  safari/privacy/location/files/boot/app/push/entrance/flipbook)
  (external `idb` dependency + Patrol owns interaction);
  `ios_sweep`/`android_sweep` (app-specific harnesses, hardcoded
  coords); `flutter_tap/flutter_set_text/flutter_reload/flutter_find/
  flutter_inspect/flutter_flipbook/flutter_anim/flutter_skeleton/
  flutter_log` (flutter_test + Patrol own; VM block is capture/inspect);
  macOS desktop automation (`ax_tree/ax_text/ax_click/ax_observe`,
  `click/drag/hover/key_chord/type_text/context_menu/gesture/scroll`
  host versions, `focus/reposition/window_state/menu/drop_file/
  clipboard/find_window/wait_window`, `record.py/multishot/wait_pixel`
  host versions) (operator-machine automation, never app verification —
  capability-map's original "out of scope" call stands);
  diagnostics (`sample/mem/nettrace/tail_log/headless/fswatch/
  tcc_check` — operator diagnostics; TCC preflight folded into Task
  10's helper).
  Workflow — ported: none beyond the above. Dropped: `pr-decide` +
  `verbs.json` (tool-routing manifest for a retired tool — the `appbox`
  CLI dispatch replaces it); `derisk_*` (7), `livesmoke_*`,
  `crawl_expander_smoke`, `research/capture-gap-probes/*` (research
  spikes, archived); fixture `run_*.py` harnesses (superseded by
  appboxd's ephemeral-server tests); `templates/dioxus_debug_probe.rs`
  + `dom.py/console.py` (Dioxus/wry — appbox doesn't ship Dioxus);
  `wait_pixel` host version (CDP `evaluate` polling covers the web
  case; no host-screen consumer).
  The 56 `test_*.py` files: noted as "behavior specs mined for Tasks
  1-6 (anim_core, crawl, merge, skeleton calibration); the rest
  archived with the tool".
- [ ] 13.2 Update `skills/appbox-lens/SKILL.md`: replace the two-entry-
  points section with the `appbox lens` verb table (keep the
  `tool/lens_shot.dart` line as the one-off driver), delete the "Known
  gaps" bullets that Tasks 1-7 closed (SSIM, CLI subcommand), keep the
  Patrol boundary paragraph and the viewport-ladder/settle/evidence
  conventions verbatim.
- [ ] 13.3 Mirror:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  cp skills/appbox-lens/capability-map.md .kimi-code/skills/appbox-lens/capability-map.md
  cp skills/appbox-lens/SKILL.md .kimi-code/skills/appbox-lens/SKILL.md
  ```
- [ ] 13.4 Audit pass — every script name in
  `archives/tooling-pre-dart/tools/vendor/probe-runner/scripts/*.py`
  appears in the new map:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  for f in archives/tooling-pre-dart/tools/vendor/probe-runner/scripts/*.py; do
    b=$(basename "$f" .py)
    grep -q "$b" skills/appbox-lens/capability-map.md || echo "MISSING: $b"
  done
  ```
  Expected: no `MISSING` lines (`_*.py` shared cores are covered by
  naming them in the ported/dropped rows' parentheticals — add any
  stragglers to the nearest row's reason).

---

## Task 14: Dartify story-map generator (`appbox emit story-map`)

Ports `skills/appbox-story-mapper/scripts/generate_story_map.py` (495
lines, pure stdlib) to `appboxd/lib/story_map.dart`. Golden rule
(dart-only plan rule 4): byte-identical HTML/brief/data output against
the Python original on a captured fixture.

**Interfaces**
- Consumes: the archived-at-Task-23 Python script (still live during
  this task); `bin/appbox.dart` `_runEmit` pattern.
- Produces: `appboxd/lib/story_map.dart`; `appbox emit story-map`
  dispatch; `appboxd/test/story_map_test.dart` + golden fixture
  `appboxd/test/fixtures/story_map_sample.json`.

### Steps

- [ ] 14.1 Capture the golden baseline from the Python original:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  python3 skills/appbox-story-mapper/scripts/generate_story_map.py --self-test
  mkdir -p appboxd/test/fixtures
  # reuse the self-test's sample shape; write appboxd/test/fixtures/story_map_sample.json
  # (project + 2 releases + 2 epics incl. one CJK-named feature and one all-wont feature)
  python3 skills/appbox-story-mapper/scripts/generate_story_map.py \
    -i appboxd/test/fixtures/story_map_sample.json \
    -o appboxd/test/fixtures/story_map_sample.html \
    --data-out appboxd/test/fixtures/story_map_sample.data.json \
    --brief-out appboxd/test/fixtures/story_map_sample.brief.md
  ```
  Expected: `self-test OK`; three golden artifacts written. These files
  are the byte-compare baseline — commit them with the task's working
  tree (they are test fixtures, not design artifacts).
- [ ] 14.2 Write the failing test — `appboxd/test/story_map_test.dart`:
  `generateStoryMap(inputJson)` produces HTML **byte-identical** to
  `story_map_sample.html`; `--data-out` JSON byte-identical; brief.md
  byte-identical; validation errors enumerate every defect with the
  same path strings (`'Feature' story[i] 'name': invalid priority
  'x'`) and exit-1 semantics; surface ids match
  `^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$`, are unique (digit-suffix on
  collision), CJK-only feature slugs → `s`; all-wont features land in
  Out-of-scope; rollup = strongest live priority + earliest live
  release; storyless feature → blank rollup. (These are the Python
  self-test's assertions, restated.)
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 14.3 Create `appboxd/lib/story_map.dart`: `class StoryMap {
  static ValidationResult validate(Map json); static String
  renderHtml(Map json); static String renderBrief(Map json); static
  List<Surface> deriveSurfaces(Map json); }` — port the Python module
  function-for-function (8-colour epic palette cycle, 210px columns,
  `lang="zh-CN"`, A3-landscape print CSS, stats bar, slug rules,
  rollup rules). The HTML template is a string built in the same
  emission order as the Python — that is what makes byte-identity
  achievable; do not "improve" markup in this task.
- [ ] 14.4 Wire `appbox emit story-map` into `_runEmit`
  (`bin/appbox.dart`): flags `-i/--input` (or stdin), `-o/--output`,
  `--data-out`, `--brief-out`, `--self-test`; exit 1 with `Validation
  error: …` lines on stderr. Run `dart test test/story_map_test.dart`
  — pass; full suite green.

---

## Task 15: Dartify the scaffolder emitter (`appbox emit scaffold`)

Ports `skills/appbox-scaffolder/scaffold.py` (860 lines, pure stdlib) to
`appboxd/lib/scaffold.dart`. Note the split that already exists:
`appboxd/lib/gate_scaffold.dart` is the *coverage gate*; this task ports
the *file emitter*. Golden: the Python `--self-test`'s ~50 assertions
become the Dart test suite, plus a differential run on
`designs/appbox-studio/structure.json`.

**Interfaces**
- Consumes: `pipeline/state/targets.derivation.json` +
  `config/appbox.config.json` (target→form-factor derivation — the same
  inputs the Python reads); `bin/appbox.dart` `_runEmit`.
- Produces: `appboxd/lib/scaffold.dart`; `appbox emit scaffold` +
  `--check`; `appboxd/test/scaffold_test.dart`.

### Steps

- [ ] 15.1 Write the failing test — `appboxd/test/scaffold_test.dart`:
  port the Python self-test's ~50 assertions to `package:test` in a
  temp app root: macos→[desktop] 3 files/surface (never
  `.mobile`/`.tablet`); ios,android→[mobile,tablet] 4 dart files +
  design-system.md; web→all three (6 files); android alone→
  [mobile,tablet]; pwa inherits web; `surface: null` not scaffolded;
  manifest shape (`selfContained`, `surfaces`, `factors`, `targets`);
  shell-level `design-system.md` + `<shellDir>_chrome.dart`; class-name
  contents (`StackedView<<Comp>ViewModel>` etc.); negatives: missing
  structure.json, surface without viewmodel, wrong file count under
  `--check`, unknown target (names it, exit 1), dir collision across
  surfaces; l10n: arb copy + fixed `l10n.yaml` + manifest l10n block,
  negatives (deleted catalog, missing `app_en.arb`, non-matching arb
  name).
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 15.2 Create `appboxd/lib/scaffold.dart`: `class ScaffoldEmitter {
  ScaffoldEmitter({required String appRoot, required String designDir,
  required List<String> targets}); EmitResult emit(); CheckResult
  check(); }` — port module-for-module: structure.json parsing (screens
  with truthy `surface`, required keys `id, comp, shellDir, surface,
  viewmodel`), 2-part id enforcement, `<shell>_<short>` dir derivation,
  per-surface file emission (header comment with surface/comp/id/shell/
  targets/factors/deps — byte-match the Python's comment format),
  `pipeline/state/targets.derivation.json` viewports+inherits
  resolution with cycle guard, `config/appbox.config.json` viewports
  ordering, `.shell-structure.json` manifest, l10n copy + `l10n.yaml`,
  `--check` drift mode (fresh-manifest compare + on-disk catalog
  compare, `FAIL:` lines to stderr), stdout summary format. Reuse
  `lib/process.dart`? No — pure file I/O; no processes.
- [ ] 15.3 Wire `appbox emit scaffold --design-dir <d> --app-root <a>
  --targets <t1,t2> [--check] [--self-test]` into `_runEmit` (env
  fallbacks `KIT_DESIGN_DIR`/`APPBOX_APP`/`APPBOX_TARGETS` preserved;
  `--design-dir` must be relative — R3).
- [ ] 15.4 Differential run against the real design (read-only check
  mode — the app surfaces were scaffolded by the Python):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  python3 skills/appbox-scaffolder/scaffold.py --design-dir designs/appbox-studio \
    --app-root appbox-studio --targets macos --check
  cd appboxd && dart run bin/appbox.dart emit scaffold \
    --design-dir designs/appbox-studio --app-root ../appbox-studio \
    --targets macos --check
  ```
  Expected: both `in-sync` (exit 0). Then `dart test` full suite green.

---

## Task 16: Dartify the deployer (`appbox deploy`)

Ports `skills/appbox-deployer/deploy.py` (486 lines, pure stdlib) to
`appboxd/lib/deploy.dart`, reusing the existing
`lib/process.dart` `ProcessRunner` seam (the Python's
`RealRunner`/`ScriptedRunner` maps 1:1). Distinct from
`gate_deploy.dart` (the gate) — this is the deploy runtime the gate
wraps.

**Interfaces**
- Consumes: `lib/process.dart`; `bin/appbox.dart` dispatch pattern.
- Produces: `appboxd/lib/deploy.dart`; `appbox deploy doctor|deploy`;
  `appboxd/test/deploy_test.dart`.

### Steps

- [ ] 16.1 Write the failing test — `appboxd/test/deploy_test.dart`:
  the Python self-test's 11 cases with a scripted `ProcessRunner`:
  exact argv shapes per target (`fastlane-ios`: `fastlane run gym
  --version <v>` → `match` → `upload_to_testflight`; `fastlane-android`:
  `flutter build appbundle --build-name <v>` → `upload_to_play_store
  --track internal`; `shorebird-release`/`shorebird-patch`;
  `cloudflare-pages`: `wrangler pages deploy --commit-dirty --version
  <v>`); `vercel` is a stub, NOT in the offered set (assert the exact
  sorted OFFERED list); halt-without-approval records a halted ledger
  row with `approver: null` and raises naming every missing field;
  full ledger row on ship (`target, version, account, approver,
  timestamp UTC-Z, artefact_id, status: shipped`); unknown target halts
  even with approval; doctor report shape `{offered,
  stub_not_offered, configured_targets, ready}`.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 16.2 Create `appboxd/lib/deploy.dart`: `class Deployer {
  Deployer({ProcessRunner? runner, String? ledgerPath}); DeployResult
  deploy({required String target, required String version, required
  String account, required String approval}); DoctorReport doctor();
  }` — ledger append semantics (every attempt incl. halts), ledger
  default `pipeline/state/deploy-ledger.json` or
  `$APPBOX_DEPLOY_LEDGER`, `DeployHalted` exception. Port
  function-for-function; do not add targets.
- [ ] 16.3 Wire top-level `appbox deploy doctor [--config f]` /
  `appbox deploy deploy --target T --version V --account A --approval
  <tok> [--ledger f]` in `bin/appbox.dart` (new `case 'deploy':`,
  exit codes 0 ok / 1 halt / 2 usage; HALT lines to stderr). Note in
  the usage text that `appbox gate deploy` remains the gate.
- [ ] 16.4 Run tests — pass; full suite green.

---

## Task 17: Fold KB lint into `appbox docs`; retire lint_kb.py

`skills/appbox-lint/lint_kb.py` (121 lines) overlaps the already-Dart
`appboxd/lib/validate_docs.dart` (docs/INDEX.md dead-link + unindexed
validator). The lazy port: extend `validate_docs.dart` with the three
checks it lacks, and retire the script as superseded.

**Interfaces**
- Consumes: `appboxd/lib/validate_docs.dart` and its test.
- Produces: extended `validate_docs.dart` + `validate_docs_test.dart`;
  updated `skills/appbox-lint/SKILL.md` (+ mirror). No new module, no
  new CLI.

### Steps

- [ ] 17.1 Diff the check lists and write failing tests for the gaps in
  `appboxd/test/validate_docs_test.dart` (synthetic fixture tempdir,
  the lint_kb.py self-test's cases): (a) **orphans** — doc with no
  inbound link and absent from the index → `WARN`; (b) **supersede
  consistency** — `docs/changelog.md` containing `supersed*` without a
  `SUPERSEDED` back-pointer → `WARN`; (c) **wikilink integrity** —
  `[[slug]]` in `memory/**/*.md` must resolve to a memory file stem →
  `WARN` (point at this repo's `memory/`, NOT lint_kb.py's hardcoded
  `~/.claude/projects/...` path — that machine-specific path is a bug
  being fixed by the port). Keep severity split: index coverage and
  link integrity stay ERROR (exit 1), the three new checks WARN.
  Run — expected: failures. Red confirmed.
- [ ] 17.2 Extend `appboxd/lib/validate_docs.dart` with the three
  checks, keeping the existing function shape and output format (`WARN
  …` / `ERROR …` + summary line). Run tests — pass; full suite green.
- [ ] 17.3 Update `skills/appbox-lint/SKILL.md`: replace the `python
  skills/appbox-lint/lint_kb.py` invocation lines (and fix the stale
  `skills/lint/` path on line 53) with `appbox docs` (or `dart run
  appboxd/bin/appbox.dart docs` from repo root — match the invocation
  style neighboring skills use for appboxd), noting lint_kb.py is
  archived and its checks merged into the Dart validator. Mirror:
  `cp skills/appbox-lint/SKILL.md .kimi-code/skills/appbox-lint/SKILL.md`.

---

## Task 18: Port the intake engine (`appbox intake`)

**Briefing gap found during planning:** `appboxd/lib/intake.dart` is NOT
a port — its own header says it "drives the elicitation engine
(`skills/appbox-intake/intake.py`) headless" by shelling out. The 669-
line `intake.py` is live, referenced by two skills, and missing from the
dartification list. This task ports it for real and rewrites
`lib/intake.dart`.

**Interfaces**
- Consumes: `skills/appbox-intake/intake.py` +
  `skills/appbox-intake/intake.schema.json` (the provenance schema);
  `bin/appbox.dart` dispatch.
- Produces: rewritten `appboxd/lib/intake.dart` (`IntakeEngine` —
  validate/emit/seed, pure Dart; the old `IntakeRunner` shell-out
  class deleted and its callers repointed); `appbox intake
  emit|seed|validate|--self-test`; `appboxd/test/intake_test.dart`.

### Steps

- [ ] 18.1 Find `IntakeRunner`'s callers before touching it:
  `grep -rn 'IntakeRunner' appboxd/ skills/ .kimi-code/skills/`.
  Repoint every caller to the new in-process API in this task.
- [ ] 18.2 Write the failing test — `appboxd/test/intake_test.dart`:
  the Python self-test's cases plus goldens captured from the Python
  on a sample answers file: `emit` produces a **byte-identical**
  `brief.md` (incl. the blockquote marking of `inferred` fields) and
  byte-identical seeded `registry.json` (surface always null);
  `validate` enforces the schema (every field has provenance
  client|founder|inferred) with the same error strings; `seed` parses
  a hand-written brief's surface table; exit codes 0/1/2; nothing
  written on invalid input (no partial artefacts).
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 18.3 Rewrite `appboxd/lib/intake.dart`: `class IntakeEngine {
  ValidationResult validate(Map answers); EmitResult emit(Map answers,
  {String? briefOut, String? registryOut}); SeedResult seed(String
  briefPath, {String? registryOut}); }` — pure Dart, pure function of
  input (the Python's emit-purity rule), env fallbacks
  `INTAKE_BRIEF_OUT`/`INTAKE_REGISTRY_OUT` preserved. Delete
  `IntakeRunner`; `lib/intake.dart`'s header comment updated (it no
  longer shells out). Keep `gate_intake.dart` untouched (it is the
  gate, already Dart).
- [ ] 18.4 Wire `appbox intake emit --answers <f> [--brief-out p]
  [--registry-out p]` / `seed --brief <f>` / `validate <f>` /
  `--self-test` into `bin/appbox.dart` (new `case 'intake':` — check
  for collision with `gate intake`: the gate is `appbox gate intake`,
  no collision).
- [ ] 18.5 Update `skills/appbox-intake/SKILL.md:87,91,101,117` and
  `skills/appbox-story-mapper/SKILL.md`'s intake reference to the Dart
  invocation; mirror both files. Run tests — pass; full suite green.

---

## Task 19: Dartify the designer's small runtimes (`appbox design …`)

Ports the designer runtime's zero/low-dependency scripts to
`appboxd/lib/design_tools.dart` behind a new `appbox design <verb>`
dispatch: `lint`, `check-ladder`, `check-wiring`, `pseudolocalize`,
`vendor-fetch`, `doctor`. `shoot.mjs` and `console-check.mjs` are NOT
ported — they are superseded by `appbox lens shoot` / `appbox lens
check` (Task 7) and recorded as such in the skill docs (Task 22).
`verify-*.mjs` are dropped with reason (artifact-specific debug scripts
with hardcoded localhost URLs; `lens check` covers the behavior).
`design_lint` is the worked exemplar below; siblings follow with the
enumerated deltas.

**Interfaces**
- Consumes: Task 7's `lens shoot`/`lens check` (doc replacements);
  `bin/appbox.dart` dispatch.
- Produces: `appboxd/lib/design_tools.dart`; `appbox design` dispatch;
  `appboxd/test/design_tools_test.dart`.

### Steps

- [ ] 19.1 Write the failing test —
  `appboxd/test/design_tools_test.dart`. Fixture: a temp artifact dir
  with two html files (one clean, one carrying each violation), a
  `ladder.json` + `references/viewport-ladder.md` pair (in-sync and
  drifted variants), `app.routes.js` + views + viewmodels for the
  wiring checks, and an `l10n/app_en.arb` + seed json for
  pseudolocalize. Cases per verb (each asserts stdout/stderr text AND
  exit code — the legacy contracts):
  - `lint`: clean dir → `lint clean: no custom client-side JS in <dir>`,
    exit 0; each of the 4 rules (non-vendor `<script>`, `hx-on:`,
    `js:`-prefixed `hx-vals`/`hx-headers`, `[expr]` in `hx-trigger`)
    → `client-JS lint failed:\n<file>: <msg>` on stderr, exit 1;
    HTML/Nunjucks comments stripped (a `{# hx-on:click #}` comment must
    NOT fire — the selftest's commented-js inverse case); missing arg →
    usage, exit 2.
  - `check-ladder`: in-sync pair → `ladder ok: compact=390 medium=744
    expanded=1280`, exit 0; config rung missing from doc / doc rung
    missing from config / rung width equal to a boundary → stderr, exit
    1.
  - `check-wiring`: all four properties (`fragments`,
    `mutations-posted`, `urls-resolve`, `targets-exist`) green on the
    fixture → `<property>: ok`; one planted violation per property →
    stderr one-per-line, exit 1; bad args → usage, exit 2.
  - `pseudolocalize`: output `app_qps-ploc.arb` byte-equal to a golden
    produced by the .mjs on the fixture (capture it in step 19.2);
    `{var}` placeholders byte-preserved; plural option bodies
    transformed with keywords/braces intact; `@`-keys skipped,
    `@@locale: qps-ploc` forced; seed json transformed except ENUM_KEYS
    and `_`-prefixed keys; neither source → exit 66.
  - `vendor-fetch`: network-gated test (mark `skip:` when offline —
    pattern: attempt the fetch, skip on SocketException); asserts SRI
    mismatch hard-fails (serve a tampered file from a local
    `HttpServer` fixture pointed at by an injectable base URL) and
    manifest shape `{file, package, version, integrity}`.
  - `doctor`: with a faked environment map returns the ok/MISS rows and
    exit 1 on any miss.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 19.2 Capture the pseudolocalize golden from the .mjs original:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  # build the fixture (arb + one seed json), then:
  node skills/appbox-designer/runtime/pseudolocalize.mjs appboxd/test/fixtures/ploc_artifact
  cp appboxd/test/fixtures/ploc_artifact/l10n/app_qps-ploc.arb appboxd/test/fixtures/ploc_golden.arb
  git checkout -- appboxd/test/fixtures/ploc_artifact 2>/dev/null || true
  ```
- [ ] 19.3 Create `appboxd/lib/design_tools.dart` — exemplar, the lint
  port (complete):
  ```dart
  /// Designer-skill tools ported to Dart: client-JS lint (ADR-0002),
  /// ladder check, wiring checks, pseudolocalize, vendor fetch, doctor.
  /// Exit-code contracts preserved from the .mjs originals.
  library;

  import 'dart:io';

  class LintFinding {
    LintFinding(this.file, this.message);
    final String file;
    final String message;
  }

  /// Strip <!-- --> and {# #} comments before scanning (the commented-js
  /// inverse case: commented code is not a violation).
  String stripComments(String html) => html
      .replaceAll(RegExp('<!--[\\s\\S]*?-->'), '')
      .replaceAll(RegExp('\\{#[\\s\\S]*?#\\}'), '');

  /// The four ADR-0002 rules, ported rule-for-rule from lint.mjs.
  List<LintFinding> lintArtifact(String artifactDir) {
    final findings = <LintFinding>[];
    final dir = Directory(artifactDir);
    if (!dir.existsSync()) {
      throw ArgumentError('artifact not found: $artifactDir');
    }
    for (final f in dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.html'))) {
      final src = stripComments(f.readAsStringSync());
      for (final m in RegExp('<script\\b[^>]*>').allMatches(src)) {
        final tag = m[0]!;
        if (!tag.contains('/assets/vendor/') &&
            !tag.contains('type="application/json"')) {
          findings.add(LintFinding(f.path, 'script tag outside /assets/vendor/: $tag'));
        }
      }
      if (src.contains('hx-on:')) {
        findings.add(LintFinding(f.path, 'hx-on: handler (inline JS)'));
      }
      final jsAttr = RegExp('''hx-(vals|headers)=["'][^"']*js:''');
      if (jsAttr.hasMatch(src)) {
        findings.add(LintFinding(f.path, 'hx-vals/hx-headers with js: prefix'));
      }
      if (RegExp('hx-trigger=["\'][^"\']*\\[').hasMatch(src)) {
        findings.add(LintFinding(f.path, 'hx-trigger [expr] filter (inline JS)'));
      }
    }
    return findings;
  }

  /// appbox design lint <artifact-dir> — exit 0 clean / 1 findings / 2 usage.
  int designLint(List<String> args) {
    if (args.isEmpty) {
      stderr.writeln('usage: appbox design lint <artifact-dir>');
      return 2;
    }
    final findings = lintArtifact(args.first);
    if (findings.isNotEmpty) {
      stderr.writeln('client-JS lint failed:');
      for (final f in findings) {
        stderr.writeln('${f.file}: ${f.message}');
      }
      return 1;
    }
    stdout.writeln('lint clean: no custom client-side JS in ${args.first}');
    return 0;
  }
  ```
  Sibling deltas (same file, one function per verb, tests from 19.1
  pin behavior):
  - `check-ladder`: read `runtime/ladder.json` (path resolution: the
    skill's runtime dir — pass as arg default
    `skills/appbox-designer/runtime/ladder.json`) +
    `references/viewport-ladder.md`; the two-way rung/width cross-check
    + boundary-equality rule from check_ladder.mjs; exit 0/1 with the
    same summary line format.
  - `check-wiring <artifact-dir> <property>`: routes parsed from
    `app.routes.js` with the same regex
    (`\[\s*'(GET|POST|PUT|PATCH|DELETE)'\s*,\s*'([^']+)'`); the four
    property walkers from check_wiring.mjs (VIEW const or co-located
    `_view.html`, `#macro` refs → `{% macro name(`, non-GET routes must
    be hx-posted, static hx-*/href URLs must resolve, hx-target ids
    must exist); exit 2/1/0 contracts.
  - `pseudolocalize <artifact-dir>`: the fixed lookalike table (copy it
    verbatim from pseudolocalize.mjs — it is data), `\x00N\x00`
    sentinel placeholder preservation, `~̷~` padding formula `max(2,
    ceil(len*0.35/3))`, comment-tolerant arb parse (drop `//` lines),
    ICU plural option-body transform via the ported `parsePlural`
    (port lib/l10n.mjs's brace-walker — create
    `appboxd/lib/design_server/l10n.dart` in THIS task with the
    brace-walker and comment-tolerant arb parse; Task 20 extends that
    file with the full createT/resolveLocale port), seed-json recursion with ENUM_KEYS =
    `{id,status,state,severity,stage,priority,kind,tone,badge,from}`;
    exit 64 usage / 66 nothing-to-do.
  - `vendor-fetch`: allowlisted pins from vendor/fetch.mjs (htmx.org
    2.0.10 with its recorded sha384 — copy the constant), jsdelivr/npm
    fetch via `HttpClient`, sha384 SRI verify (dart:convert +
    `crypto`? — appboxd has no crypto package; compute SHA-384 via
    `Process.run('openssl', ['dgst','-sha384','-binary'])` spawned —
    openssl is a macOS base tool, and `crypto_aead.dart` only has
    SHA-256; document the spawn choice in the header), minimal ustar
    parser for the lucide tarball (port fetch.mjs's parser — it is
    already a no-GNU-longname subset), manifest.json + SRI.md emission;
    injectable base URL for tests.
  - `doctor`: post-port semantics — checks the DART toolchain (`dart
    --version` ≥ 3.12, Chrome present via
    `CdpClient.defaultChromePath()`, `ffmpeg` on PATH, vendored
    `runtime/vendor/htmx.min.js` + `ladder.json` present) instead of
    node/playwright; same ok/MISS row format, exit 1 on miss. This is
    the one verb whose *meaning* changes — the .mjs checked node deps
    that no longer exist; record that in the skill doc update (Task
    22).
- [ ] 19.4 Wire `appbox design <verb>` into `bin/appbox.dart` (new
  `case 'design':` → `runDesign(rest)` in
  `appboxd/lib/design_cli.dart` — sibling to `lens_cli.dart`; `serve`
  prints `lands in Task 20` + exit 2 for now). Run tests — pass; full
  suite green.

---

## Task 20: The Dart design server (`appbox design serve`) + eject

The biggest skills-side port: `serve.mjs` (387 lines) + `lib/router.mjs`,
`lib/helpers.mjs`, `lib/state.mjs`, `lib/l10n.mjs`, `lib/templates.mjs`,
`lib/timers.mjs` (~810 lines total) → `appboxd/lib/design_server.dart` +
`appboxd/lib/design_server/` subtree. Golden spec: `serve.test.mjs`'s 15
behaviors, restated as a Dart test. Architecture per the header: **Dart
owns the process; a headless-Chrome JS worker (CDP) owns artifact JS
execution** — viewmodels and Nunjucks run in the worker, which the Dart
server drives with the `cdp.dart` substrate. The worker JS shim
(`h`/`c` Hono-equivalents, nunjucks browser build) is vendored into
`skills/appbox-designer/runtime/vendor/` like every other island.

**Interfaces**
- Consumes: `cdp.dart` (worker transport); Task 19's l10n `parsePlural`
  port; `lib/server.dart`'s if-chain dispatch precedent; serve.test.mjs
  (the behavior spec).
- Produces: `appboxd/lib/design_server.dart` (process: target
  resolution, ports, supervisor, hot reload, pidfile registry, state
  restore, exit codes); `appboxd/lib/design_server/worker.dart` (CDP
  bridge); `appboxd/lib/design_server/router.dart` (route-table match);
  `appboxd/lib/design_server/state.dart` (sessions/prefs/timers);
  `appboxd/lib/design_server/l10n.dart` (started in Task 19);
  `skills/appbox-designer/runtime/vendor/worker_page.html` +
  `worker_shim.js` + `nunjucks-slim.min.js` (SRI-pinned) (+ mirrors);
  `appboxd/test/design_server_test.dart`; `appbox design serve` wired;
  `appbox design eject` (port of eject.mjs).

### Steps

- [ ] 20.1 **Worker spike first** (the risk gate; ~200 lines, throwaway
  if it fails): `appboxd/tool/_worker_spike.dart` — boot the Dart
  static-file `_bindStaticServer`-pattern server over
  `designs/appbox-studio`, launch `CdpClient`, load a page that
  `import()`s `app.routes.js` from that origin, and
  `evaluateFunction('(m) => globalThis.__routes(m)')` to pull the route
  table back as JSON; then dispatch `mainShell.page` for `GET /` via a
  second evaluate and assert the returned string contains `<html`.
  Expected: route table JSON + rendered HTML. **If the spike fails:**
  stop this task, record "serve.mjs stays as the single sanctioned node
  runtime (JS-artifact execution has no zero-dep Dart host)" in
  capability-map.md + the dart-only plan's follow-up, and skip to Task
  21 — the rest of the plan stands. Do not retry the spike more than
  twice.
- [ ] 20.2 Vendor the worker assets (SRI-pinned, the vendor/ contract):
  download `nunjucks@3.2.4` browser slim build:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/skills/appbox-designer/runtime/vendor
  curl -sfL -o nunjucks-slim.min.js https://unpkg.com/nunjucks@3.2.4/browser/nunjucks-slim.min.js
  openssl dgst -sha384 -binary nunjucks-slim.min.js | openssl base64 -A
  ```
  Record in `manifest.json` + `SRI.md` + `THIRD-PARTY-NOTICES.md`
  (nunjucks is BSD-2-Clause — verify via `npm view nunjucks@3.2.4
  license`). Author `worker_page.html` (loads nunjucks-slim +
  `worker_shim.js`) and `worker_shim.js`: the Hono-equivalent shim —
  `__boot(artifactBase)`: dynamic-import `<base>/app.routes.js`,
  register nunjucks env rooted at the artifact origin (fetch loader),
  expose `__routes()` → JSON `[method, path]` and `__dispatch(method,
  path, headers, body)` → JSON `{status, headers, body}` implementing
  the helpers contract from lib/helpers.mjs (`render` with
  `file.html#macro` fragment syntax, `form`, `session`, `prefs`,
  `locale`, `t`, `noContent` 204, `stopPolling` 286, `refresh`
  HX-Refresh, `location` HX-Location) and the icon() global (fetch the
  vendored lucide SVG, same attribute rules as lib/templates.mjs). The
  shim is a *port of the lib/*.mjs semantics into the worker* — keep
  function shapes identical so viewmodels cannot tell the difference.
  Mirror all three files to `.kimi-code/skills/.../vendor/`.
- [ ] 20.3 Write the failing test —
  `appboxd/test/design_server_test.dart`: serve.test.mjs's 15 behaviors,
  verbatim semantics:
  1. bare design name `appbox-studio` resolves (walk-up +
     `designs/<name>` candidates) → record `artifact` ends with
     `designs/appbox-studio`;
  2. `--port 0` reports the OS-bound port;
  3. ready record carries `url, port, host, pid, artifact, workerPid`;
  4. `pid` == supervisor pid, `workerPid` != `pid`;
  5. record URL answers HTTP 200;
  6. not reachable from LAN IP by default (loopback bind);
  7. port collision → exit 69, stderr matches `already in use`, no
     stack trace, stdout empty;
  8. SIGTERM releases the port;
  9. unknown design name → exit non-zero, stderr mentions
     `app.routes.js`, >3 lines (tried-paths list);
  10. legacy positional path + `--port N` works (200);
  11. `--host 0.0.0.0` prints the every-interface warning;
  12. hot reload: edit a served view in a temp copy → same port serves
     the edit; revert picked up;
  13. server-side timers survive a reload (`/timer` keeps counting —
     timers live in DART state, restored into the worker on reboot —
     this is why the port keeps timers out of the JS side);
  14. kill semantics: SIGTERM stops one instance; SIGINT stops every
     instance of the same artifact (pidfile registry +
     `ps -p <pid> -o command=` guard — port the "command contains the
     serve marker" check to look for `appbox`/`design_server` instead
     of `serve.mjs`);
  15. pidfiles swept from the registry dir after exit.
  Drive the server as a spawned `dart run bin/appbox.dart design serve
  …` process (the test spawns, like serve.test.mjs spawns node).
  Run — expected: COMPILE ERROR / spawn failures. Red confirmed.
- [ ] 20.4 Create the Dart server. `design_server.dart` public entry:
  ```dart
  /// The appbox design server (ports skills/appbox-designer/runtime/serve.mjs
  /// + lib/*.mjs). Dart owns the process contract — target resolution,
  /// ports, supervisor/hot-reload, pidfile registry, session/pref/timer
  /// state, exit codes 64/66/69/70/77. Artifact JS (app.routes.js
  /// viewmodels, Nunjucks views) executes in a headless-Chrome worker
  /// over CDP: the designs stay ES modules, the toolchain stays Dart.
  library;

  Future<int> designServe(List<String> args); // the CLI entry
  ```
  Components:
  - **Target resolution** — port serve.mjs's candidate walk exactly:
    positional path wins; else `path.resolve(target)`, `<cwd>/designs/
    <target>`, then walk up from the skill dir trying `<dir>/designs/
    <target>`; first containing `app.routes.js` wins; failure → stderr
    tried-paths list, exit 66. Port/host parse: `--port` int 0-65535
    else 64; default 4319 or `$PORT`; `--host` default 127.0.0.1 or
    `$HOST`; unknown flag 64; `--json` / `--no-watch` / `--worker`.
  - **Router** (`design_server/router.dart`) — at boot, ask the worker
    for `__routes()`; match incoming requests with a tiny pattern
    matcher (`/build/panel/size/:side/:size` → named params, port of
    Hono's `:param` segments only — no wildcards in appbox routes;
    kimitail: `:param` segments only, add wildcard support if a design
    ever uses one). Unmatched → `404 — no route for M P`. Built-in
    routes stay Dart-side: `GET|POST /prefs/lang` (cookie + HX-Refresh/
    302 semantics from lib/router.mjs), static `/assets/vendor/*` →
    runtime vendor dir (path rewrite + traversal guard per
    `server.dart`'s `_serveStatic`), `/assets/*` and `/_ds/*` →
    artifact dir.
  - **Worker bridge** (`design_server/worker.dart`) — complete core:
    ```dart
    class JsWorker {
      JsWorker._(this._tab, this._client, this._artifactBase);
      final CdpSession _tab;
      final CdpClient _client;
      final String _artifactBase;

      /// Boot a worker against the artifact served at [artifactBase]
      /// (the Dart server's own origin). Loads the vendored worker page
      /// and imports the artifact's routes module.
      static Future<JsWorker> boot(String workerPageUrl, String artifactBase) async {
        final client = await CdpClient.launch();
        final tab = await client.newTab();
        await tab.enable();
        await tab.navigateAndSettle(workerPageUrl, settleMs: 800);
        final ok = await tab.evaluateFunction(
            '(base) => globalThis.__boot(base).then(() => true)', artifactBase);
        if (ok != true) {
          await client.close();
          throw StateError('worker boot failed for $artifactBase');
        }
        return JsWorker._(tab, client, artifactBase);
      }

      Future<List<List<String>>> routes() async {
        final raw = await _tab
            .evaluate('JSON.stringify(globalThis.__routes())') as String;
        return [
          for (final r in jsonDecode(raw) as List)
            [r[0] as String, r[1] as String]
        ];
      }

      /// Dispatch one request through the artifact's viewmodel layer.
      Future<WorkerResponse> dispatch(String method, String path,
          Map<String, String> headers, String? body, Map<String, dynamic> serverState) async {
        final raw = await _tab.evaluateFunction(
            '(req) => globalThis.__dispatch(req.method, req.path, req.headers, req.body, req.state)',
            {
              'method': method, 'path': path, 'headers': headers,
              'body': body, 'state': serverState,
            });
        final map = jsonDecode(raw as String) as Map<String, dynamic>;
        return WorkerResponse(
          status: map['status'] as int,
          headers: (map['headers'] as Map).cast<String, String>(),
          body: map['body'] as String?,
        );
      }

      /// Hot reload: re-import the artifact modules cache-busted.
      Future<void> reload() async {
        await _tab.evaluateFunction(
            '(base) => globalThis.__boot(base + "?reload=" + Date.now()).then(() => true)',
            _artifactBase);
      }

      Future<void> dispose() => _client.close();
    }
    ```
    The `state` bag carries sessions/prefs/timers snapshots so the JS
    side stays stateless across reloads (behavior 13).
  - **State** (`design_server/state.dart`) — port lib/state.mjs +
    lib/timers.mjs to Dart: session map keyed by `kdh_sid` cookie
    (randomUUID, httpOnly, sameSite=Lax, path=/), prefs JSON cookie
    `kdh_prefs` (<4 KB, 1yr), timers `Map<id, deadline>` with
    start/extend/remaining/stop; snapshot/restore to
    `${tmp}/appbox-serve-state-<sha1(artifactDir)[:12]>.json` on
    SIGINT/SIGTERM (SHA-1: appboxd has SHA-256 in crypto_aead — a 12-
    char sha256 prefix serves the same uniqueness purpose; use it and
    note the divergence from serve.mjs's sha1 in the header comment).
  - **Supervisor** — port serve.mjs's two modes: `--worker`/`--no-watch`
    = the server itself; default = supervisor spawning the worker
    process (`Process.start(Platform.resolvedExecutable, [...run,
    bin/appbox.dart, design, serve, dir, --worker, --port, P, --json])`),
    first-`{`-line ready record, hot reload on artifact-tree change
    (recursive watch via `Directory.watch(recursive: true)` — Dart
    covers macOS/Linux without serve.mjs's per-subdir walk; ignore
    regex `(^|[/\\])(node_modules|\.git|build|\.dart_tool)([/\\]|$)|
    \.DS_Store$`, 200ms debounce), SIGTERM-child/SIGKILL-after-2s
    reload, crash-respawn only after first boot, 3-crashes-in-10s
    circuit breaker, pidfile registry at
    `${tmp}/appbox-designer-serve/<pid>.json` with the SIGINT
    sweep-every-sibling semantics (behavior 14). Error mapping:
    EADDRINUSE → exit 69 with the "port N is already in use on H —
    pass --port 0" line; EACCES → 77; else 70.
  - **Request flow** — HttpServer on loopback: static/built-in routes
    Dart-side; dynamic routes matched against the worker's table →
    `worker.dispatch(...)` → write status/headers/body. `Vary:
    HX-Request` always, `Vary: Accept-Language` for HTML (port of the
    locale middleware). onError → log + `500 — <message>`.
- [ ] 20.5 Port `eject.mjs` → `appbox design eject <artifact-dir>
  <out-dir>` in `design_tools.dart`: same steps as the .mjs (copy
  artifact; narrow `vendor/` to referenced libs with the
  htmx-required hard fail; write narrowed manifest) but the ejected
  `package.json`+node-runtime step becomes a `README` + a checked
  `appbox design serve . --no-watch` invocation line — ejected
  artifacts run on the same Dart server, no node anywhere. Smoke test
  in `design_tools_test.dart`: eject the hello-hda fixture, serve the
  ejected copy in-process, `GET /` → 200 + `<html`, `GET
  /assets/vendor/htmx.min.js` → 200.
- [ ] 20.6 Run the 15-behavior test — all pass; full suite green. Then
  the real-design smoke:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  dart run bin/appbox.dart design serve appbox-studio --port 4399 &
  sleep 6
  curl -sf -o /dev/null -w '%{http_code}\n' http://localhost:4399/dashboard
  curl -sf http://localhost:4399/assets/vendor/htmx.min.js -o /dev/null -w '%{http_code}\n'
  kill %1
  ```
  Expected: `200` twice. Then lens-verify one surface renders
  identically to the node server's output (Task 7's
  `compare --mode=ssim` against a golden captured from the node server
  — capture that golden in this step, store under
  `appboxd/test/fixtures/serve_golden_dashboard.png`).

---

## Task 21: Dartify the designer selftest (`appbox design selftest`)

Ports `skills/appbox-designer/selftest.sh` (468 lines bash, ~25 labeled
checks + 25-row negative-mutation table) to Dart. The checks' inline
node scripts (registry parse, shellRoots dynamic import, route-200
render pass) become Dart + the Task 20 worker.

**Interfaces**
- Consumes: Tasks 19 (wiring/ladder checks as library calls), 20
  (serve/worker for the render section).
- Produces: `appboxd/lib/design_selftest.dart`; `appbox design selftest
  [artifact-dir] [--negative]`; `appboxd/test/design_selftest_test.dart`.

### Steps

- [ ] 21.1 Write the failing test —
  `appboxd/test/design_selftest_test.dart`: run the selftest against a
  known-good fixture artifact (the hello-hda example copied to a temp
  dir) → `passed N, failed 0`, exit 0; then one planted violation per
  check family flips exactly its labeled check (a compact 6-row subset
  of the mutation table: registry-key, surface-id, orphan-post,
  dead-url, emoji-icon, client-js) — full 25-row proof stays in
  `--negative` mode below.
  Run — expected: COMPILE ERROR. Red confirmed.
- [ ] 21.2 Create `appboxd/lib/design_selftest.dart`: port the ~25
  checks in selftest.sh's order, keeping the labels and the `ok`/`FAIL
  <label>` / `passed N, failed M` output contract:
  registry parses (keys `id,label,surface,shell,comp`) · no
  `exclusions.json` · every `*_viewmodel.js` declares `export const
  surfaceId` · surfaceId↔registry join both directions ·
  `app.routes.js` exports non-empty `shellRoots` (regex-extract the
  object literal — the worker is overkill here; evaluate via worker
  only if the literal form proves insufficient) · no viewmodel imports
  `repositories/` · fixtures carry `_generated_from` · arb key parity
  (comment-tolerant parse — reuse Task 19's) · ladder doc/config
  consistency (call Task 19's check-ladder as a function) + hardcoded
  390/744/1280 grep with `ladder-exempt:` escape · no upstream identity
  tokens · `h.refresh(` proximity rule with `refresh-exempt:` · the
  four wiring properties (Task 19 functions) · widget/macros
  composition · icon emoji/unicode ranges + `icon('` usage · git
  tracking check (skipped visibly outside a work tree) · render section
  (boot the Task 20 server in-process, every GET route → 200).
  `--negative`: port the 25-row MUTATIONS table (registry-key,
  exclusions-file, surface-id, orphan-id, uncovered-entry,
  empty-shellroots, repo-import, fixture-provenance, arb-parity,
  ladder-doc/config/drift/hardcode, upstream-leak, full-reload,
  fragment-typo, orphan-post, dead-url, dangling-target, emoji-icon,
  widget-partials, untracked-file, client-js, broken-route, and the
  inverse `commented-js` row) — each row mutates a throwaway copy in a
  temp dir, asserts the named check FAILs; `proven N, unproven M`
  summary; the /tmp guard from the .sh (mutations refusing to run
  outside temp dirs) becomes: the mutation runner *only ever operates
  on its own temp copy*, so the guard is structural, not a check.
  Exit codes: 64 usage/unknown flag, 65 baseline-red or unclaimed
  labels, non-zero on any failure.
- [ ] 21.3 Wire `appbox design selftest [artifact-dir] [--negative]`
  into `design_cli.dart`. Run against the real skill:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  dart run bin/appbox.dart design selftest ../skills/appbox-designer/examples/hello-hda
  ```
  Expected: `passed N, failed 0`. Full suite green.

---

## Task 22: Designer agents/ disposition + all skill doc updates

Dispositions for `skills/appbox-designer/agents/*.mjs` (found during
planning — the briefing's runtime list covered runtime/ but agents/ is
also non-Dart skill runtime) and the enumerated SKILL.md invocation
updates for Tasks 14-16 + 19-21.

**Interfaces**
- Consumes: Tasks 14-21 (the Dart replacements the docs point at).
- Produces: updated SKILL.md/system-prompt/reference docs across six
  skills (+ mirrors); agents/ archived (Task 23 does the move; this
  task records the dispositions).

### Steps

- [ ] 22.1 Dispositions for `skills/appbox-designer/agents/` — verify
  each claim, then record in a new **`## Skills runtimes`** section
  appended to `skills/appbox-lens/capability-map.md` (created in this
  task, below the probe-runner tables — it is the audit trail for the
  whole dartification, one row per retired runtime file, ported or
  dropped-with-reason; Task 23's archive moves are the mechanical half):
  - `import-figma.mjs` — **dropped with reason**: statically imports
    `./vendor/fig-materialize.mjs`, which does not exist in either
    skills tree — it crashes on load at HEAD. Verify:
    `node skills/appbox-designer/agents/import-figma.mjs 2>&1 | head -3`
    → module-not-found. Archived, restorable if Figma import returns.
  - `compile-design-system.mjs` — **dropped with reason**: lazily
    requires `agents/vendor/babel.min.js` (absent; fails with a fetch
    hint). JSX/TSX compilation is a babel concern, not a Dart port —
    archived with its fetch hint intact.
  - `build-preview.mjs` (1919 lines), `ds-core.mjs` (750), `ds-prompt.mjs`
    (290), `asset-store.mjs` (177) — **dropped with reason**: the
    design-system preview compiler; no pipeline gate consumes it and it
    is a self-contained ~3k-line subsystem — port on demand (the
    capability-map convention) when a gate or the designer's DS flow
    asks for it, not preemptively.
  - `check-design-system.mjs` (110), `record-asset.mjs` (187),
    `import-design-system.mjs` (274) — **port** (small, pure-logic,
    part of the DS intake flow): three functions in
    `appboxd/lib/design_tools.dart` — `dsCheck(projectDir)` (read-only
    validator, exit 64 usage contract), `recordAsset(...)` (append the
    deliverable record into `_d_meta.json` — port its JSON shape
    exactly), `dsImport(projectDir, slug)` (sync compiled DS into
    `<project>/_ds/<slug>/` + `_d_meta.json` note). Tests in
    `design_tools_test.dart` with fixture dirs. Wire as `appbox design
    ds-check|record-asset|ds-import`.
- [ ] 22.2 Update every skill doc invocation line (enumerated —
  canonical `skills/` then mirror each):
  - `skills/appbox-story-mapper/SKILL.md:170,177,262` → `appbox emit
    story-map -i … -o … --data-out … --brief-out …` and `--self-test`.
  - `skills/appbox-scaffolder/SKILL.md:84,94,109` → `appbox emit
    scaffold --design-dir … --app-root … --targets … [--check]
    [--self-test]`.
  - `skills/appbox-deployer/SKILL.md:83-84` → `appbox deploy doctor` /
    `appbox deploy deploy …` / `--self-test`.
  - `skills/appbox-designer/SKILL.md:97-103,110,135` → serve/lint/
    console-check/shoot/eject/doctor lines become `appbox design
    serve|lint|eject|doctor` and `appbox lens check|shoot`;
    pseudolocalize line → `appbox design pseudolocalize`.
  - `skills/appbox-designer/system-prompt.md`,
    `references/harness-tools.md`, `runtime/README.md`, and any
    `built-in-skills/*.md` carrying `node <skill>/runtime/*.mjs` or
    `agents/*.mjs` lines → the Dart equivalents from Tasks 19-22.1
    (grep the skill dir for `node ` and `python` to catch every one —
    the grep, not this list, is the completeness check).
  - `skills/appbox-intake/SKILL.md` (done in Task 18.5 — verify).
- [ ] 22.3 Mirror every file touched:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  for f in appbox-story-mapper/SKILL.md appbox-scaffolder/SKILL.md \
           appbox-deployer/SKILL.md appbox-designer/SKILL.md \
           appbox-designer/system-prompt.md; do
    cp "skills/$f" ".kimi-code/skills/$f"
  done
  # plus any further files the 22.2 grep caught
  ```

---

## Task 23: Archive the retired runtimes; grep-clean

The dart-only plan's done-criterion: archived and grep-clean, nothing
deleted. Moves `skills/`'s `.py`/`.mjs`/`.sh` runtimes to
`archives/tooling-pre-dart/skills-pre-dart/` preserving relative paths,
and rewrites `appbox-lens`'s "extend, don't route around" doc lines that
reference the old runtimes.

**Interfaces**
- Consumes: Tasks 14-22 (every replacement green).
- Produces: `archives/tooling-pre-dart/skills-pre-dart/**`; `skills/`
  free of python/node/bash runtimes; grep-clean proof.

### Steps

- [ ] 23.1 Move (preserve relative paths):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  A=archives/tooling-pre-dart/skills-pre-dart
  mkdir -p $A/appbox-scaffolder $A/appbox-deployer $A/appbox-lint \
           $A/appbox-story-mapper/scripts $A/appbox-intake \
           $A/appbox-designer/runtime/vendor $A/appbox-designer/agents
  git mv skills/appbox-scaffolder/scaffold.py $A/appbox-scaffolder/
  git mv skills/appbox-story-mapper/scripts/generate_story_map.py $A/appbox-story-mapper/scripts/
  git mv skills/appbox-deployer/deploy.py $A/appbox-deployer/
  git mv skills/appbox-lint/lint_kb.py $A/appbox-lint/
  git mv skills/appbox-intake/intake.py $A/appbox-intake/
  git mv skills/appbox-designer/selftest.sh $A/appbox-designer/
  git mv skills/appbox-designer/runtime/serve.mjs skills/appbox-designer/runtime/serve.test.mjs \
         skills/appbox-designer/runtime/lint.mjs skills/appbox-designer/runtime/doctor.mjs \
         skills/appbox-designer/runtime/shoot.mjs skills/appbox-designer/runtime/console-check.mjs \
         skills/appbox-designer/runtime/pseudolocalize.mjs skills/appbox-designer/runtime/eject.mjs \
         skills/appbox-designer/runtime/check_ladder.mjs skills/appbox-designer/runtime/check_wiring.mjs \
         skills/appbox-designer/runtime/verify-interact.mjs skills/appbox-designer/runtime/verify-shots.mjs \
         skills/appbox-designer/runtime/verify-timeline.mjs $A/appbox-designer/runtime/
  git mv skills/appbox-designer/runtime/vendor/fetch.mjs $A/appbox-designer/runtime/vendor/
  git mv skills/appbox-designer/runtime/lib $A/appbox-designer/runtime/lib
  git mv skills/appbox-designer/agents $A/appbox-designer/agents
  ```
  Note: `git mv` stages but never commits (global constraint). If a
  file is untracked, plain `mv`. Keep `runtime/vendor/*.js` (htmx,
  lucide, islands, nunjucks-slim) in place — those are served assets,
  not runtimes. Keep `runtime/package.json`? No — move it too (it
  describes the retired node runtime); the ladder stays
  (`runtime/ladder.json` is data, consumed by Task 19).
  Also archive the mirror-only scratch scripts:
  `mv .kimi-code/skills/appbox-designer/runtime/_*.mjs
  $A/appbox-designer/runtime/` (untracked debug one-offs — archived,
  not deleted).
  And the two per-artifact example scripts (they are node runtimes
  inside `skills/` — the end-state rule covers them):
  ```sh
  git mv skills/appbox-designer/examples/hello-hda/serve.mjs \
    $A/appbox-designer/examples-hello-hda-serve.mjs
  git mv skills/appbox-designer/examples/hello-hda/models/greeting_model/generate.mjs \
    $A/appbox-designer/examples-hello-hda-generate.mjs
  ```
  Replace both with a 5-line note in
  `skills/appbox-designer/examples/hello-hda/README.md` (create if
  absent): serving is `appbox design serve <dir>` (Task 20); the
  fixture-generator pattern (`*_seed.<locale>.json` →
  `*_fixtures.<locale>.json` with `_generated_from`) is now the
  designer's own authoring step documented in the skill, and the
  archived `generate.mjs` is the reference if a generator is ever
  re-added as Dart. Mirror the README.
- [ ] 23.2 Apply the same moves under `.kimi-code/skills/` (the live
  mirror) with plain `mv` (untracked tree), same target structure.
- [ ] 23.3 Grep-clean proof — no python/node/bash runtime invocations
  left in skills:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box
  grep -rn -E '\b(node|python3?|bash)\b[^ ]*\.(mjs|py|sh)' skills/ .kimi-code/skills/ \
    | grep -v -E '(archives|\.md:.*(archiv|retired|dropped|was |formerly))' || echo CLEAN
  find skills .kimi-code/skills -name '*.py' -o -name '*.sh' | grep -v archives || echo "no py/sh"
  find skills .kimi-code/skills -name '*.mjs' | grep -v archives || echo "no mjs"
  ```
  Expected: `CLEAN`, `no py/sh`, `no mjs` (skill `.md` files may
  *mention* the archived paths in dropped-with-reason sentences — the
  grep filter above allows exactly that; eyeball the filtered output
  before declaring clean).
- [ ] 23.4 Fix stragglers the grep catches: any skill doc still
  instructing a retired invocation gets the Task 22 treatment on the
  spot (+ mirror).

---

## Task 24: Final verification + close-out

**Interfaces**
- Consumes: everything.
- Produces: the green matrix below; `docs/INDEX.md` entry for this
  plan's outcome if INDEX tracks plans (check its convention first).

### Steps

- [ ] 24.1 Full appboxd suite + analyzer:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  dart analyze && dart test
  ```
  Expected: no issues; all tests pass (the suite should now include
  lens_pixels, cdp_domains, lens_tokens/dom/a11y/net, lens_motion,
  lens_skeleton, lens_states, lens_crawl, lens_cli, lens_adb,
  lens_simctl, lens_sck, lens_ocr, lens_flutter_vm, gate_lens,
  story_map, scaffold, deploy, validate_docs, intake, design_tools,
  design_server, design_selftest).
- [ ] 24.2 Gate wiring smoke:
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  dart run bin/appbox.dart gate lens --self-test
  dart run bin/appbox.dart lens --help 2>&1 | head -5 || true
  dart run bin/appbox.dart design 2>&1 | head -3 || true
  ```
  Expected: selftest PASS lines incl. the `# NEGATIVE:` case; usage
  tables print, exit 2.
- [ ] 24.3 End-to-end lens smoke at the ladder against the Dart design
  server (node is gone by now — this also proves Task 20):
  ```sh
  cd /Volumes/developer_ssd/Developer/totem_labs/app-box/appboxd
  dart run bin/appbox.dart design serve appbox-studio --port 4399 &
  sleep 6
  for r in 390:844 744:1133 1280:832; do
    w=${r%%:*}; h=${r##*:}
    dart run bin/appbox.dart lens shot http://localhost:4399/dashboard \
      ../designs/appbox-studio/evidence/lens-full-port/dashboard-$w.png $w $h 2500
  done
  dart run bin/appbox.dart lens tokens http://localhost:4399/dashboard 390 844 \
    --out=../designs/appbox-studio/evidence/lens-full-port/tokens-390.json
  kill %1
  ```
  Expected: three shots + tokens JSON, all clean; **read each PNG back
  (ReadMediaFile)** — a green exit with a blank canvas is a fail.
- [ ] 24.4 Capability-map audit (rerun Task 13.4's loop): no `MISSING`
  lines; every row reads `ported` or `dropped` with a reason.
- [ ] 24.5 Re-run the grep-clean proof from Task 23.3 — `CLEAN`.
- [ ] 24.6 Update the lens SKILL.md's remaining "future" lines if any
  survived Task 13, mirror, and hand back: the working tree is the
  deliverable; committing is the operator's call.

---

## Follow-up work (NOT this plan)

- Physical iOS device capture (QuickTime protocol via `go-ios` /
  pymobiledevice3) — simulator + adb only in this plan.
- `adb_cdp` (adb-forwarded CDP for Android Chrome) — re-add from the
  archive when an Android-web gate asks.
- Frame-recovery flipbook fallback for non-WAAPI animation (canvas/CSS
  transitions invisible to `getAnimations()`), and the numpy-grade
  `_flipbook` template tracking — kimitail-noted in Task 4.
- `vision_probe` detectors (face/body/rect/barcode/saliency) on the
  Task 10 Swift CLI — one VNRequest per kind when a gate asks.
- `design-system preview compiler` (agents/build-preview.mjs + ds-*.mjs)
  Dart port — on demand, per Task 22.1.
- `web_states` consent/keyframes sub-cores, `site_chrome` chrome-dedup —
  extraction-pipeline machinery; archive remains the source if appbox
  ever extracts third-party designs.
- `dart compile exe bin/appbox.dart` distribution (the header comment's
  "Planned" line) + CI matrix — separate program per the dart-only
  plan's derived constraints.
