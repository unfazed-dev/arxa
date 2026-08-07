// Probe for gate_freeze_test.dart — runs the freeze gate against synthetic
// design fixtures. It must run as a subprocess: the render pass is skipped via
// FREEZE_RENDER=skip and Platform.environment is unmodifiable in-process.
//
// Prints one JSON array of {name, passed, details} scenarios to stdout.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gate_freeze.dart';
import 'package:appboxd/gates.dart';

Future<void> main() async {
  final tmp = Directory.systemTemp.createTempSync('freeze-tsx-probe-');
  final out = <Map<String, Object?>>[];
  try {
    final repo = Directory('${tmp.path}/repo')..createSync(recursive: true);
    Directory('${repo.path}/pipeline/state').createSync(recursive: true);
    Directory('${repo.path}/config').createSync(recursive: true);
    File('${repo.path}/pipeline/state/targets.derivation.json')
        .writeAsStringSync(jsonEncode({
      'targets': {
        'macos': {
          'viewports': ['desktop']
        }
      }
    }));
    File('${repo.path}/config/appbox.config.json').writeAsStringSync(
        jsonEncode({
      'viewports': {
        'desktop': {'width': 1280, 'height': 800}
      }
    }));

    final design = Directory('${repo.path}/app/designs/appbox-studio')
      ..createSync(recursive: true);
    File('${design.path}/app.routes.js').writeAsStringSync('// routes\n');
    File('${design.path}/structure.json')
        .writeAsStringSync(jsonEncode({'registry': 'registry.json'}));
    File('${design.path}/registry.json').writeAsStringSync('{}');
    final views = Directory('${design.path}/ui/views/x')
      ..createSync(recursive: true);

    final ctx = GateContext(repoRoot: repo.path, appRoot: '${repo.path}/app');

    Future<GateResult> run({bool approve = false}) =>
        freezeGate(ctx, targets: ['macos'], approve: approve);

    void record(String name, GateResult r) => out.add(
        {'name': name, 'passed': r.passed, 'details': r.details.join('\n')});

    // 1. tsx-only views: shape passes and the stamp mints.
    File('${views.path}/a_view.tsx').writeAsStringSync('// v1\n');
    record('tsx-only approve', await run(approve: true));

    // 2. editing the tsx view invalidates the stamp (tsx bytes in inputsHash).
    File('${views.path}/a_view.tsx').writeAsStringSync('// v2\n');
    record('tsx edit invalidates', await run());

    // 3. an html view alongside the tsx one is still folded into the hash.
    File('${views.path}/b_view.html').writeAsStringSync('<!-- b -->\n');
    record('html+tsx changes hash', await run());

    // 4. no view files at all: shape fails naming both extensions.
    File('${views.path}/a_view.tsx').deleteSync();
    File('${views.path}/b_view.html').deleteSync();
    File('${design.path}/approval.lock').deleteSync();
    record('no views', await run());

    // 5. html-only views still pass (pre-migration behavior kept).
    File('${views.path}/b_view.html').writeAsStringSync('<!-- b -->\n');
    record('html-only', await run(approve: true));
  } finally {
    tmp.deleteSync(recursive: true);
  }
  stdout.write(jsonEncode(out));
}
