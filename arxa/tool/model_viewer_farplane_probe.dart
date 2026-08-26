// Does the model-viewer far-plane patch change what renders?
//
// The vendored model-viewer.min.js carries one local edit (see the
// `vendorPatches` registry in design_tools.dart): the far clipping-plane
// multiplier when no grounded skybox is set, 1x the model's bounding-sphere
// radius upstream and 60x patched. It was committed unverified in de28917a and
// has been flagged unverified twice since. This answers it by rendering.
//
// How the value is used, read from the minified source:
//
//     [Mb](t) { const e = Math.max(farRadius(), t), i = Math.abs(2 * e);
//               updateNearFar(0, i) }
//
// so far = 2 * max(farRadius(), cameraDistance). The `max` means the patch is
// INERT whenever the camera is farther from the target than farRadius — the
// camera distance wins and both variants get the same far plane. It can only
// bite when farRadius dominates: a close camera, or geometry sitting far
// beyond the model (an environment sphere).
//
// So a single default-camera render would prove nothing either way. This
// sweeps the orbit radius across both regimes and reports which cells differ.
//
// Run: cd arxa && dart run tool/model_viewer_farplane_probe.dart
import 'dart:convert';
import 'dart:io';

import 'package:arxa/cdp.dart';
import 'package:path/path.dart' as p;

const _repoVendor = '../skills/arxa-designer/runtime/vendor';
const _model = '../designs/arxa-studio/assets/media/boombox.glb';

/// The patch, in both directions — kept in the same shape as the registry
/// entry so a drift in one is visible against the other.
const _patched =
    'farRadius(){return this.boundingSphere.radius*(null!=this.groundedSkybox.parent?10:60)}';
const _upstream =
    'farRadius(){return this.boundingSphere.radius*(null!=this.groundedSkybox.parent?10:1)}';

/// Orbit radii to sweep. `%` is relative to model-viewer's auto-framed
/// distance, so 40% is a close camera (farRadius should dominate) and 400% is
/// far (camera distance should dominate and the patch should be inert).
const _orbits = ['40%', '75%', '100%', '200%', '400%'];

/// A 390x390 PNG of flat colour compresses to well under 2KB; a frame with the
/// boombox in it measured 50-130KB. Anything below this floor means the model
/// never rendered, and two blank frames must report VOID rather than "same".
const _renderedFloorBytes = 8000;

/// [maxOrbit] is the falsification lever, and it took reading the call site to
/// find it. `farRadius()`'s consumer is
///
///     [Vb](t) { applyOptions({..., maximumRadius: t[2]}), this[Mb](t[2]) }
///
/// so the `t` in `Math.max(farRadius(), t)` is the MAXIMUM camera-orbit radius
/// — the `max-camera-orbit` attribute — not the camera's current distance.
/// Whichever is larger sets the far plane, so the only way the 1x multiplier
/// can dominate is to hold `max-camera-orbit` down near or below the model's
/// bounding-sphere radius. Sweeping camera distance alone can never reach that
/// regime, which is why the first run of this probe could not have falsified
/// anything.
String _page(String orbit, {required bool skybox, String? maxOrbit}) => '''
<!doctype html><meta charset=utf-8><title>farplane</title>
<style>html,body{margin:0;height:100%;background:#202020}
model-viewer{width:390px;height:390px;--poster-color:transparent}</style>
<script type="module" src="/mv.js"></script>
<model-viewer id=mv src="/boombox.glb"
  camera-orbit="0deg 75deg $orbit"
  ${maxOrbit != null ? 'max-camera-orbit="auto auto $maxOrbit"' : ''}
  ${skybox ? 'skybox-image="/sky.png"' : ''}
  disable-zoom interaction-prompt=none exposure="1"
  camera-controls></model-viewer>
<script type="module">
  const mv = document.getElementById('mv');
  window.__ready = false;
  mv.addEventListener('load', () => { window.__ready = true; });
</script>
''';

/// A 2:1 equirectangular PNG, generated rather than vendored: a plain gradient
/// is enough, since the question is whether the environment renders AT ALL,
/// not what it looks like.
List<int> _skyPng() {
  // Minimal uncompressed-ish PNG via a canvas would need a browser; instead
  // build a tiny 2x1 image and let model-viewer stretch it.
  const b64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAFklEQVQIHWP8z8Dwn4EIwESEGrCS'
      'IdUAADYwAgdmXSJmAAAAAElFTkSuQmCC';
  return base64Decode(b64);
}

Future<(HttpServer, String)> _serve(String mvJs) async {
  final model = File(_model).readAsBytesSync();
  final sky = _skyPng();
  final js = utf8.encode(mvJs);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    final r = req.response;
    r.headers.set('cache-control', 'no-store');
    if (path == '/mv.js') {
      r.headers.contentType = ContentType('text', 'javascript');
      r.add(js);
    } else if (path == '/boombox.glb') {
      r.headers.contentType = ContentType('model', 'gltf-binary');
      r.add(model);
    } else if (path == '/sky.png') {
      r.headers.contentType = ContentType('image', 'png');
      r.add(sky);
    } else {
      r.headers.contentType = ContentType.html;
      r.write(_page(req.uri.queryParameters['orbit'] ?? '100%',
          skybox: req.uri.queryParameters['sky'] == '1',
          maxOrbit: req.uri.queryParameters['max']));
    }
    await r.close();
  });
  return (server, 'http://127.0.0.1:${server.port}');
}

Future<String> _shoot(CdpSession tab, String url) async {
  await tab.navigate(url);
  // model-viewer decodes an 11MB glb and compiles shaders; the settle loop
  // alone can converge on the empty poster before the model appears, so wait
  // for the component's own load event first.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final ready = await tab.evaluate('window.__ready === true');
    if (ready == true) break;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await tab.settleForCapture(minWaitMs: 600);
  return base64Encode(await tab.screenshot());
}

Future<Map<String, String>> _run(String variant, String mvJs) async {
  final (server, base) = await _serve(mvJs);
  final shots = <String, String>{};
  final client = await CdpClient.launch();
  try {
    final tab = await client.newTab();
    await tab.enable();
    await tab.setViewport(390, 390);
    // The skybox arm was dropped after its first run: every cell came back at
    // 1764 b64 chars — a flat 390x390 fill, i.e. the model never rendered, so
    // both arms were blank and compared "same". That is a did-not-run outcome
    // reading as a pass, the exact shape this repo keeps getting bitten by.
    // Reporting it as evidence of "no difference under a skybox" would have
    // been a lie; the honest statement is that the skybox regime is untested.
    // The floor check below is what turns a repeat into a loud VOID.
    // Camera-distance sweep, plus the max-camera-orbit cells that are the only
    // regime where the 1x multiplier can win the Math.max at all.
    final cells = <(String, String, String?)>[
      for (final o in _orbits) ('orbit $o', o, null),
      ('max 105% @105%', '105%', '105%'),
      ('max 60% @60%', '60%', '60%'),
      ('max 30% @30%', '30%', '30%'),
    ];
    for (final (key, orbit, max) in cells) {
      shots[key] = await _shoot(
          tab,
          '$base/?orbit=${Uri.encodeComponent(orbit)}'
          '${max == null ? '' : '&max=${Uri.encodeComponent(max)}'}');
      final bytes = base64Decode(shots[key]!).length;
      stdout.writeln('  $variant $key: $bytes bytes'
          '${bytes < _renderedFloorBytes ? '  <-- VOID, nothing rendered' : ''}');
    }
  } finally {
    await client.close();
    await server.close(force: true);
  }
  return shots;
}

Future<void> main() async {
  // Either disk state works: whichever form is present anchors the swap and
  // the other arm is derived from it. Refusing both is the only failure —
  // identical arms would report "no difference" for the wrong reason. (The
  // committed file is pristine since the 2026-08-21 revert; the probe stays
  // runnable so the verdict stays reproducible.)
  final onDisk =
      File(p.join(_repoVendor, 'model-viewer.min.js')).readAsStringSync();
  final String patchedJs, upstreamJs;
  if (onDisk.contains(_patched)) {
    patchedJs = onDisk;
    upstreamJs = onDisk.replaceFirst(_patched, _upstream);
  } else if (onDisk.contains(_upstream)) {
    upstreamJs = onDisk;
    patchedJs = onDisk.replaceFirst(_upstream, _patched);
  } else {
    stderr.writeln('neither the upstream nor the patched farRadius anchor is '
        'present — upstream drifted past this probe; re-derive the anchors.');
    exit(1);
  }

  stdout.writeln('PATCHED (60x):');
  final patched = await _run('60x', patchedJs);
  stdout.writeln('UPSTREAM (1x):');
  final upstream = await _run(' 1x', upstreamJs);

  final outDir = Directory('../logs/farplane')..createSync(recursive: true);
  stdout.writeln('');
  stdout.writeln('cell              | verdict');
  stdout.writeln('------------------|------------');
  var differing = 0, void_ = 0;
  for (final key in patched.keys) {
    final a = base64Decode(patched[key]!), b = base64Decode(upstream[key]!);
    final slug = key.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    File(p.join(outDir.path, '60x_$slug.png')).writeAsBytesSync(a);
    File(p.join(outDir.path, '01x_$slug.png')).writeAsBytesSync(b);
    // A blank frame is NOT agreement. Without this, "both arms rendered
    // nothing" and "both arms rendered the same thing" print the same word.
    if (a.length < _renderedFloorBytes || b.length < _renderedFloorBytes) {
      void_++;
      stdout.writeln('${key.padRight(17)} | VOID (nothing rendered)');
      continue;
    }
    final same = patched[key] == upstream[key];
    if (!same) differing++;
    stdout.writeln('${key.padRight(17)} | ${same ? 'same' : 'DIFFERENT'}');
  }
  stdout.writeln('');
  stdout.writeln('images written to ${outDir.path}/  (60x_* vs 01x_*)');
  if (void_ > 0) {
    stdout.writeln('$void_ cell(s) VOID — those rows are not evidence of '
        'anything and must not be read as agreement.');
  }
  stdout.writeln('');
  // A control, and a real one: if NOTHING differs anywhere, the honest
  // readings are "the patch is inert for every case tested" OR "the probe
  // never varied the thing it thinks it varied". Distinguish them by checking
  // the two arms actually rendered different BUILDS — the sweep must contain
  // at least one cell where the far plane could matter at all.
  if (differing == 0) {
    stdout.writeln('NO CELL DIFFERS. Either the patch is inert across this '
        'sweep, or the arms are not really different builds. The `_patched` '
        'guard above rules out the second, so: inert here.');
  } else {
    stdout.writeln('$differing of ${patched.length} cells differ — the patch '
        'changes what renders in those camera/environment regimes.');
  }
  exitCode = 0;
}
