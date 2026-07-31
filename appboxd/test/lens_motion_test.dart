// Motion capture tests — burst, record, scroll-anim, flipbook + the pure
// easing-fit core. CDP tests boot ephemeral fixture pages and drive a real
// headless Chrome; the ffmpeg encode path goes through a fake ProcessRunner
// so the record test never hard-requires a real video.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appboxd/lens/motion.dart';
import 'package:appboxd/lens/pixels.dart';
import 'package:appboxd/process.dart';
import 'package:test/test.dart';

// ── fixture pages ─────────────────────────────────────────────────────

/// (a) A page that keeps painting: a box whose background toggles between two
/// gradients every animation frame. This is the same repaint pattern Task 2's
/// screencast test uses (cdp_domains_test.dart) — known to drive
/// Page.startScreencast frames reliably, and to make burst screenshots differ.
Future<(HttpServer, String)> bootAnimServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
html,body { margin:0; padding:0; }
body { width:390px; height:844px; }
#box { width:300px; height:300px;
       background:linear-gradient(135deg,red,orange,yellow); }
</style></head><body>
<div id="box"></div>
<script>
(function () {
  var box = document.getElementById('box');
  var t0 = 0;
  function tick(now) {
    if (!t0) t0 = now;
    var h = ((now - t0) / 10) % 360;
    box.style.background = 'linear-gradient(135deg, hsl(' + h + ',100%,50%),'
      + ' hsl(' + ((h + 120) % 360) + ',100%,50%))';
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
})();
</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

/// (b) A tall page with a scroll-scrubbed element: translateY = scrollY * 0.5.
Future<(HttpServer, String)> bootScrollServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
html,body { margin:0; padding:0; }
body { height: 2000px; }
#mover { position:absolute; top:100px; left:100px; width:80px; height:80px;
         background:steelblue; transform: translateY(0px); }
</style></head><body>
<div id="mover"></div>
<script>
window.addEventListener('scroll', function () {
  var y = window.scrollY * 0.5;
  document.getElementById('mover').style.transform = 'translateY(' + y + 'px)';
});
</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

/// (c) A WAAPI flipbook: clicking #go animates #target opacity 0→1 over 600ms.
Future<(HttpServer, String)> bootFlipbookServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final base = 'http://${server.address.address}:${server.port}';
  server.listen((req) {
    req.response.headers.contentType = ContentType.html;
    req.response.write('''
<!DOCTYPE html><html><head><style>
html,body { margin:0; padding:0; }
body { width:390px; height:844px; }
#target { width:100px; height:100px; background:#e11; opacity:1; }
#go { position:absolute; top:200px; left:20px; width:120px; height:44px; }
</style></head><body>
<div id="target"></div>
<button id="go">animate</button>
<script>
document.getElementById('go').addEventListener('click', function () {
  document.getElementById('target').animate(
    [{opacity:0},{opacity:1}],
    {duration:600, easing:'ease-in-out'});
});
</script>
</body></html>
''');
    req.response.close();
  });
  return (server, base);
}

/// Counts staged frame files inside the temp dir ffmpeg was pointed at, and
/// materialises the output the real encode would have. Lets the encode test
/// verify the staging logic (numbered jpegs) with no real ffmpeg.
class _CountingFfmpeg implements ProcessRunner {
  List<String>? lastCall;
  int stagedFiles = 0;
  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    if (executable == 'ffmpeg') {
      lastCall = args;
      final iIdx = args.indexOf('-i');
      if (iIdx > 0) {
        final dir = File(args[iIdx + 1]).parent;
        stagedFiles =
            dir.listSync().where((e) => e.path.endsWith('.jpg')).length;
      }
      File(args.last).writeAsBytesSync(List<int>.filled(8192, 0));
      return const RunnerResult(0, '', '');
    }
    return const RunnerResult(0, '/usr/local/bin/ffmpeg\n', '');
  }
}

/// Always reports ffmpeg absent — proves the preflight guards the pipeline.
class _MissingFfmpeg implements ProcessRunner {
  final List<List<String>> calls = [];
  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    calls.add([executable, ...args]);
    return const RunnerResult(1, '', 'not found');
  }
}

/// Fakes a failing ffmpeg encode (non-zero exit).
class _FailingFfmpeg implements ProcessRunner {
  @override
  Future<RunnerResult> run(
    String executable,
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) async {
    if (executable == 'which') {
      return const RunnerResult(0, '/usr/local/bin/ffmpeg\n', '');
    }
    return const RunnerResult(1, 'encode failed', 'bad frame');
  }
}

List<double> _curveSeries(double Function(double) fn, int n) =>
    [for (var i = 0; i < n; i++) fn(i / (n - 1))];

void main() {
  group('fitEasing (pure core)', () {
    test('perfect linear certifies to linear with ~0 rms', () {
      final fit = fitEasing(_curveSeries((t) => t, 21));
      expect(fit.certified, isTrue);
      expect(fit.easing, 'linear');
      expect(fit.rms, lessThan(1e-6));
    });

    test('perfect ease-in (t²) certifies to ease-in', () {
      final fit = fitEasing(_curveSeries((t) => t * t, 21));
      expect(fit.certified, isTrue);
      expect(fit.easing, 'ease-in');
      expect(fit.rms, lessThan(1e-6));
    });

    test('perfect ease-out (1-(1-t)²) certifies to ease-out', () {
      final fit = fitEasing(_curveSeries((t) => 1 - (1 - t) * (1 - t), 21));
      expect(fit.certified, isTrue);
      expect(fit.easing, 'ease-out');
      expect(fit.rms, lessThan(1e-6));
    });

    test('perfect ease-in-out (smoothstep) certifies to ease-in-out', () {
      final fit = fitEasing(_curveSeries((t) => t * t * (3 - 2 * t), 21));
      expect(fit.certified, isTrue);
      expect(fit.easing, 'ease-in-out');
      expect(fit.rms, lessThan(1e-6));
    });

    test('certifies decreasing (reversed) linear series', () {
      final fit = fitEasing(_curveSeries((t) => 1 - t, 21));
      expect(fit.certified, isTrue);
      expect(fit.easing, 'linear');
    });

    test('noisy series does not certify', () {
      // Linear base + a deterministic oscillation no standard curve matches.
      final v = [
        for (var i = 0; i < 21; i++) (i / 20) + 0.12 * math.sin(i * 1.3),
      ];
      expect(fitEasing(v).certified, isFalse);
    });

    test('non-monotonic series → non-monotonic', () {
      final fit = fitEasing([0, 10, 5, 20, 15, 30]);
      expect(fit.certified, isFalse);
      expect(fit.reason, 'non-monotonic');
    });
  });

  group('motion (CDP)', () {
    test('burstFrames returns N frames that differ on an animating page',
        () async {
      final (server, base) = await bootAnimServer();
      try {
        final frames = await burstFrames(base,
            count: 4, intervalMs: 150, settleMs: 400);
        expect(frames.length, 4);
        for (final f in frames) {
          expect(f.length, greaterThan(100));
        }
        // Consecutive frames of the hue-cycling page must differ.
        for (var i = 1; i < frames.length; i++) {
          final diff = pixelDiff(decodePng(frames[i - 1]), decodePng(frames[i]));
          expect(diff.diffPixels, greaterThan(0),
              reason: 'burst frames $i-1 and $i were identical');
        }
      } finally {
        await server.close();
      }
    });

    test('framesToMp4 stages frames and invokes ffmpeg image2 via the seam',
        () async {
      // The encode path is pure Dart over the seam — no Chrome, no real
      // screencast, fully deterministic (screencast delivery is Task 2's
      // concern and is non-deterministic per the plan).
      final fake = _CountingFfmpeg();
      final outDir = Directory.systemTemp.createTempSync('motion-enc-');
      final outMp4 = '${outDir.path}/out.mp4';
      final frames = [for (var i = 0; i < 5; i++) List<int>.filled(1024, i)];
      try {
        await framesToMp4(frames, outMp4, 10, runner: fake);
        final args = fake.lastCall!;
        expect(args, containsAll(['-f', 'image2', '-framerate', '10', '-c:v']));
        expect(args, contains('libx264'));
        expect(args, contains('-pix_fmt'));
        expect(args, contains('yuv420p'));
        expect(args.last, outMp4);
        // Every frame was staged as a numbered jpeg before the encode call.
        expect(fake.stagedFiles, 5,
            reason: 'frames must be staged as numbered jpegs');
        expect(File(outMp4).existsSync(), isTrue);
      } finally {
        outDir.deleteSync(recursive: true);
      }
    });

    test('framesToMp4 surfaces a non-zero ffmpeg exit', () {
      expect(
        framesToMp4([List<int>.filled(10, 0)], '/tmp/nope.mp4', 10,
            runner: _FailingFfmpeg()),
        throwsA(isA<StateError>()),
      );
    });

    test('recordVideo throws a clear message when ffmpeg is missing',
        () async {
      final missing = _MissingFfmpeg();
      expect(
        recordVideo('about:blank', '/tmp/nope.mp4', seconds: 1, runner: missing),
        throwsA(isA<StateError>()),
      );
      // The preflight must fire before any Chrome launch / screencast.
      expect(missing.calls.any((a) => a.first == 'which'), isTrue);
    });

    test('captureScrollAnim certifies linear translateY = scrollY * 0.5',
        () async {
      final (server, base) = await bootScrollServer();
      try {
        final report = await captureScrollAnim(base, steps: 20, settleMs: 400);
        expect(report['consoleErrors'], isEmpty);
        expect(report['certified'], isTrue, reason: 'scroll anim not certified');
        final maxScroll = (report['maxScroll'] as num).toDouble();
        final movers = report['movers'] as List;
        expect(movers.length, 1);
        final ch = (movers[0]['channels'] as Map)['translateY'] as Map;
        expect((ch['from'] as num).toDouble(), closeTo(0, 1));
        expect((ch['to'] as num).toDouble(), closeTo(maxScroll * 0.5, 2));
        expect(ch['easing'], 'linear');
        expect((ch['rms'] as num).toDouble(), lessThan(0.05));
      } finally {
        await server.close();
      }
    });

    test('captureFlipbook recovers opacity 0→1 via the WAAPI oracle',
        () async {
      final (server, base) = await bootFlipbookServer();
      try {
        final report = await captureFlipbook(base,
            triggerSelector: '#go', watchMs: 1500, settleMs: 400);
        expect(report['reliable'], isTrue, reason: 'WAAPI oracle saw nothing');
        expect(report['consoleErrors'], isEmpty);
        final anims = report['animations'] as List;
        expect(anims.length, greaterThanOrEqualTo(1));
        final kf = (anims[0]['keyframes'] as List)
            .where((k) => (k as Map)['opacity'] != null)
            .toList();
        final ops = kf
            .map((k) => ((k as Map)['opacity'] as num).toDouble())
            .toList();
        expect(ops.first, closeTo(0, 0.01));
        expect(ops.last, closeTo(1, 0.01));
        expect((anims[0]['duration'] as num).toDouble(), closeTo(600, 10));
      } finally {
        await server.close();
      }
    });
  });
}
