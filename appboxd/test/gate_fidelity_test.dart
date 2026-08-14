// fidelity gate tests — spec: docs/plans/fidelity-mode-config.md (QF-1..QF-4).
//
// Every case is discriminating: a lawful fixture passes, and each single
// mutation fails naming the specific rule (bad_mode, illegal_mode, ios_floor,
// define_drift, prefer_flutter_in_native).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gate_fidelity.dart';
import 'package:appboxd/gates.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String repo;
  late String app;

  void write(String rel, String body) {
    final f = File('$repo/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
  }

  void config(Map<String, dynamic>? fidelity) {
    final body = <String, dynamic>{'version': 1};
    if (fidelity != null) body['fidelity'] = fidelity;
    write('config/appbox.config.json', jsonEncode(body));
  }

  void derivation() {
    write(
        'pipeline/state/targets.derivation.json',
        jsonEncode({
          'targets': {
            'ios': {},
            'android': {},
            'web': {},
            'macos': {},
          }
        }));
  }

  void pbxproj({String floor = '26.0'}) {
    write('app/ios/Runner.xcodeproj/project.pbxproj', '''
    buildSettings = {
      IPHONEOS_DEPLOYMENT_TARGET = $floor;
    };
    buildSettings = {
      IPHONEOS_DEPLOYMENT_TARGET = $floor;
    };
''');
  }

  GateResult run() => fidelityGate(GateContext(repoRoot: repo, appRoot: app));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate_fidelity_');
    repo = tmp.path;
    app = '$repo/app';
    Directory(app).createSync(recursive: true);
    derivation();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('no fidelity map: passes with all-mix default note', () {
    config(null);
    final r = run();
    expect(r.passed, isTrue);
    expect(r.summary, contains('default `mix`'));
  });

  test('lawful map passes and names the flutter sanctioned exception', () {
    config({'ios': 'mix', 'android': 'flutter', 'web': 'flutter'});
    // Non-mix declarations require an emitted define (const-drift rule).
    write('app/run.sh', '--dart-define=APPBOX_FIDELITY=flutter');
    final r = run();
    expect(r.passed, isTrue, reason: r.details.join('\n'));
    expect(r.details.join('\n'), contains('QF-4'));
    expect(r.details.join('\n'), contains('android: flutter'));
  });

  test('bad mode value fails as fidelity.bad_mode', () {
    config({'ios': 'nativ'});
    final r = run();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'), contains('fidelity.bad_mode'));
  });

  test('mix on web fails as fidelity.illegal_mode', () {
    config({'web': 'mix'});
    final r = run();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'), contains('fidelity.illegal_mode'));
  });

  test('native on macos (desktop) fails as fidelity.illegal_mode', () {
    config({'macos': 'native'});
    final r = run();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'), contains('fidelity.illegal_mode'));
  });

  test('unknown target key fails as fidelity.unknown_target', () {
    config({'watchos': 'flutter'});
    final r = run();
    expect(r.passed, isFalse);
    expect(r.details.join('\n'), contains('fidelity.unknown_target'));
  });

  group('ios native floor', () {
    void nativeIosWithDefine() {
      config({'ios': 'native'});
      // Satisfy the drift check so floor failures are isolated.
      write('app/run.sh', 'flutter run --dart-define=APPBOX_FIDELITY=native');
      write('app/lib/main.dart', 'void main() {}');
    }

    test('floor 26 passes', () {
      nativeIosWithDefine();
      pbxproj(floor: '26.0');
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });

    test('floor below 26 fails as fidelity.ios_floor', () {
      nativeIosWithDefine();
      pbxproj(floor: '17.0');
      final r = run();
      expect(r.passed, isFalse);
      expect(r.details.join('\n'), contains('fidelity.ios_floor'));
      expect(r.details.join('\n'), contains('17.0'));
    });

    test('ios dir present without pbxproj fails as fidelity.ios_floor', () {
      nativeIosWithDefine();
      Directory('$app/ios').createSync(recursive: true);
      final r = run();
      expect(r.passed, isFalse);
      expect(r.details.join('\n'), contains('project.pbxproj is missing'));
    });

    test('ios dir absent defers the floor check (coverage owns presence)', () {
      nativeIosWithDefine();
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });
  });

  group('const-drift', () {
    test('non-mix mode with no emitted define fails (folds to mix)', () {
      config({'android': 'flutter'});
      final r = run();
      expect(r.passed, isFalse);
      expect(r.details.join('\n'), contains('fidelity.define_drift'));
      expect(r.details.join('\n'), contains('folds to its `mix` default'));
    });

    test('emitted define matching declared mode passes', () {
      config({'android': 'flutter'});
      write('app/Makefile', 'run:\n\tflutter run --dart-define=APPBOX_FIDELITY=flutter');
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });

    test('emitted define matching no declared mode fails with location', () {
      config({'android': 'flutter'});
      write('app/run.sh', '--dart-define=APPBOX_FIDELITY=native');
      final r = run();
      expect(r.passed, isFalse);
      expect(r.details.join('\n'), contains('fidelity.define_drift'));
      expect(r.details.join('\n'), contains('run.sh:1'));
    });

    test('all-mix map with no define is lawful (mix is the const default)', () {
      config({'ios': 'mix'});
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });
  });

  group('preferFlutterTier lint', () {
    void nativeIos() {
      config({'ios': 'native'});
      pbxproj();
      write('app/run.sh', '--dart-define=APPBOX_FIDELITY=native');
    }

    test('preferFlutterTier: true under native mode fails with file:line', () {
      nativeIos();
      write('app/lib/screen.dart',
          'final w = CNButton(\n  preferFlutterTier: true,\n);');
      final r = run();
      expect(r.passed, isFalse);
      expect(r.details.join('\n'), contains('fidelity.prefer_flutter_in_native'));
      expect(r.details.join('\n'), contains('lib/screen.dart:2'));
    });

    test('preferFlutterTier: false under native mode is lawful', () {
      nativeIos();
      write('app/lib/screen.dart',
          'final w = CNButton(preferFlutterTier: false);');
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });

    test('preferFlutterTier: true under mix mode is lawful', () {
      config({'ios': 'mix'});
      write('app/lib/screen.dart',
          'final w = CNButton(preferFlutterTier: true);');
      final r = run();
      expect(r.passed, isTrue, reason: r.details.join('\n'));
    });
  });
}
