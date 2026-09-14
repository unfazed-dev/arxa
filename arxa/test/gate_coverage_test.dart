// Coverage gate test — the palette plane's C6 drift check (Q8): the frozen
// default palette's color vocabulary is re-rendered from structure.json's
// palettes block and byte-diffed against disk, naming the file on
// mismatch. The fixture app is built by the real scaffold — the producer
// and the gate meet here exactly as they do in the pipeline.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/gate_coverage.dart';
import 'package:arxa/gates.dart';
import 'package:arxa/scaffold.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String repoRoot;
  late String appRoot;
  late String designDir;

  const derivationJson = r'''
{
  "targets": {
    "macos":   { "viewports": ["desktop"], "ceremonies": [] }
  }
}
''';
  const configJson = r'''
{
  "version": "1.0.0",
  "targets": ["macos"],
  "viewports": {
    "desktop": { "width": 1280, "height": 800 }
  }
}
''';

  Map<String, dynamic> struct({bool plane = true}) => {
        r'$schema': 'arxa/structure@2',
        'registry': 'models/screens_model/registry.json',
        'shellRoots': {'stage': '/'},
        'screens': [
          {
            'id': 'stage.shell',
            'shell': 'stage',
            'comp': 'StageShell',
            'shellDir': 'stage_shell',
            'surface': 'stage_shell_view',
            'viewmodel': 'ui/views/stage_shell/stage_shell_viewmodel.js',
            'deps': <String>[],
          },
          {
            'id': 'projects.home',
            'shell': 'projects',
            'comp': 'ProjectsHome',
            'shellDir': 'stage_shell',
            'surface': 'stage_shell_projects_home_view',
            'viewmodel': 'ui/views/stage_shell/projects/home/home_viewmodel.js',
            'deps': <String>[],
          },
        ],
        if (plane)
          'palettes': {
            'default': 'marine',
            'palettes': [
              {
                'id': 'marine',
                'name': 'Marine Blue',
                'swatch': ['#ccdbdc', '#9ad1d4', '#80ced7', '#007ea7', '#003249'],
                'themeColor': '#007EA7',
                'seeded': true,
              },
            ],
          },
      };

  /// Write structure.json into the fixture design dir and run the real
  /// scaffold over it, so the gate reads exactly what the pipeline emits.
  void plantApp({bool plane = true}) {
    File('$designDir/structure.json')
        .writeAsStringSync(jsonEncode(struct(plane: plane)));
    final rc = scaffold(
        designDir,
        appRoot,
        ['macos'],
        '$repoRoot/pipeline/state/targets.derivation.json',
        '$repoRoot/config/arxa.config.json');
    if (rc != 0) throw StateError('fixture scaffold failed');
  }

  GateResult runGate() =>
      coverageGate(GateContext(repoRoot: repoRoot, appRoot: appRoot));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('coverage-test-');
    repoRoot = '${tmp.path}/repo';
    appRoot = '${tmp.path}/app';
    designDir = '$appRoot/design';
    Directory('$repoRoot/pipeline/state').createSync(recursive: true);
    Directory('$repoRoot/config').createSync(recursive: true);
    File('$repoRoot/pipeline/state/targets.derivation.json')
        .writeAsStringSync(derivationJson);
    File('$repoRoot/config/arxa.config.json').writeAsStringSync(configJson);
    // The ambient targets (6.2): no arxa.json marker above the fixture
    // app, so ctx.targets reads pipeline state.
    File('$repoRoot/pipeline/state/default.state.json')
        .writeAsStringSync(jsonEncode({
      'targets': ['macos'],
    }));
    Directory(designDir).createSync(recursive: true);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('green tree: the vocabulary is asserted (C6) inside a passing gate', () {
    plantApp();
    final r = runGate();
    expect(r.passed, isTrue, reason: r.details.join('\n'));
    expect(r.details.join('\n'),
        contains("palette vocabulary matches frozen palette 'marine' (C6)"));
  });

  test('a hand-corrupted vocabulary fails, naming the file', () {
    plantApp();
    final f = File('$appRoot/lib/ui/common/arxa_kit_app_colors.dart');
    f.writeAsStringSync(
        f.readAsStringSync().replaceFirst('#003249', '#003250'));
    final r = runGate();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'),
        contains('lib/ui/common/arxa_kit_app_colors.dart'),
        reason: 'the drift verdict names the file');
    expect(r.details.join('\n'), contains('do not hand-edit'));
  });

  test('a missing vocabulary file fails, naming it', () {
    plantApp();
    File('$appRoot/lib/ui/common/arxa_kit_app_colors.dart').deleteSync();
    final r = runGate();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'),
        contains('lib/ui/common/arxa_kit_app_colors.dart missing'));
  });

  test('no palettes block -> C6 silent, the gate unaffected', () {
    plantApp(plane: false);
    final r = runGate();
    expect(r.passed, isTrue, reason: r.details.join('\n'));
    expect(r.details.join('\n'), isNot(contains('palette vocabulary')),
        reason: 'absent block = no plane (valid for pre-law artifacts)');
  });
}
