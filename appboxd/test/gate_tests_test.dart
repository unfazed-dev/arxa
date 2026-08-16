// gate_tests T1/T2/T3 tests — behavior-TDD enforcement on a fixture app.
//
// Every case is discriminating: the canonical fixture passes, and each single
// mutation fails with the offending file / story id named. T3 runs real
// `dart test` subprocesses against pure-Dart micro-fixtures (never flutter),
// so those cases carry a generous timeout.
//
// Numbering is the canon's (behavior-tdd-rules.md §Traceability + AGENTS.md):
//   T1 traceability — story-ID citation coverage + no empty stubs/groups
//   T2 anti-pattern scan — the canon's banned mechanical tests
//   T3 tests pass

import 'dart:io';

import 'package:appboxd/gate_tests.dart';
import 'package:appboxd/gates.dart';
import 'package:appboxd/project.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String app;

  void write(String rel, String body) {
    final f = File('$app/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
  }

  void rm(String rel) => File('$app/$rel').deleteSync();

  /// A map.json with one must story (plus a could story that must NOT be
  /// required) — the emitStoryMap shape: epics → features → stories.
  void plantMap(String rel) => write(rel, '''
{"releases": [], "counts": {}, "statuses": {},
 "epics": [{"id": "notes", "name": "Notes", "storyCount": 2, "provenance": "client",
   "features": [{"id": "notes.folders", "name": "Folders",
     "stories": [
       {"id": "notes.folders.create-folder", "name": "Create folder",
        "priority": "must", "release": null, "provenance": "client"},
       {"id": "notes.folders.archive-folder", "name": "Archive folder",
        "priority": "could", "release": null, "provenance": "inferred"}
     ]}]}]}
''');

  /// Canonical: one real test naming the must story's id.
  void plantPassingTestFile() => write('test/folders_test.dart',
      "// covers notes.folders.create-folder\n"
      "void main() { test('folder creation', () {}); }\n");

  GateResult run({bool check = true}) =>
      testsGate(GateContext(repoRoot: app, appRoot: app, check: check));
  String detailsOf(GateResult r) => r.details.join('\n');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gate-tests-test-');
    app = tmp.path;
    write('pubspec.yaml', 'name: demo\n');
  });

  tearDown(() {
    appboxHomeOverride = null;
    tmp.deleteSync(recursive: true);
  });

  group('T1: no empty stubs', () {
    setUp(() => plantMap('intake/map.json'));

    test('a test file with a test() invocation passes', () {
      plantPassingTestFile();
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('(T1)'));
    });

    test('testWidgets( and blocTest( also satisfy T1', () {
      write('test/widget_test.dart',
          "void main() { testWidgets('w', (tester) async {}); }\n");
      write('test/bloc_test.dart',
          "// covers notes.folders.create-folder\n"
          "void main() { blocTest('b', build: () {}); }\n");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('an empty stub fails and names the file', () {
      plantPassingTestFile();
      write('test/empty_stub_test.dart', '// TODO: write these tests\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('empty test stub (T1)'));
      expect(detailsOf(r), contains('empty_stub_test.dart'));
    });

    test('a file with only setUp() is still an empty stub', () {
      plantPassingTestFile();
      write('test/setup_only_test.dart', 'void main() { setUp(() {}); }\n');
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('setup_only_test.dart'));
    });

    test('no test dir warns and passes (vacuous, never false-fails)', () {
      rm('intake/map.json');
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('WARN'));
      expect(detailsOf(r), contains('nothing to check'));
    });

    test('an empty group() stub fails and names the file (canon T1)', () {
      plantPassingTestFile();
      write('test/group_stub_test.dart',
          "void main() { group('folders', () {}); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('empty group() stub (T1)'));
      expect(detailsOf(r), contains('group_stub_test.dart'));
    });
  });

  group('T2: anti-pattern scan (banned mechanical tests)', () {
    test('a constructor test fails and names the file', () {
      plantMap('intake/map.json');
      plantPassingTestFile();
      write('test/folders_ctor_test.dart',
          "void main() { test('constructor sets name', () => expect(Folder('x').name, 'x')); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('getter/constructor/toString test (T2)'));
      expect(detailsOf(r), contains('folders_ctor_test.dart'));
    });

    test('a toString test fails too', () {
      plantMap('intake/map.json');
      plantPassingTestFile();
      write('test/folders_str_test.dart',
          "void main() { test('toString is readable', () => expect(Folder('x').toString(), contains('x'))); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('getter/constructor/toString test (T2)'));
    });

    test('a verify()-only test fails (mock-verification theater)', () {
      plantMap('intake/map.json');
      plantPassingTestFile();
      write('test/sync_verify_test.dart', """
void main() {
  test('notes.folders.create-folder — save calls the repository', () async {
    await vm.save();
    verify(() => repo.save(any()));
  });
}
""");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('verify()-only test (T2)'));
      expect(detailsOf(r), contains('sync_verify_test.dart'));
    });

    test('a stub-then-assert-the-stub round-trip fails', () {
      plantMap('intake/map.json');
      plantPassingTestFile();
      write('test/roundtrip_test.dart', """
void main() {
  test('notes.folders.create-folder — lists folders', () {
    when(() => repo.all()).thenReturn([folder]);
    expect(repo.all(), [folder]);
  });
}
""");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('stub-then-assert round-trip (T2)'));
      expect(detailsOf(r), contains('roundtrip_test.dart'));
    });

    test('verify at a trust boundary WITH a real expect passes', () {
      plantMap('intake/map.json');
      write('test/enqueue_test.dart', """
void main() {
  test('notes.folders.create-folder — enqueueSync forwards and surfaces queued', () async {
    await vm.enqueueSync();
    verify(() => sync.enqueue(any()));
    expect(vm.queued, 1);
  });
}
""");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('a single trust-boundary verify with PINNED arguments passes (canon-blessed)', () {
      plantMap('intake/map.json');
      // The showcase/canon shape: the facade owns the write, so the verify's
      // pinned arguments ARE the observable behavior — no expect required.
      write('test/delegate_test.dart', """
void main() {
  test('notes.folders.create-folder — createFolder trims and delegates', () async {
    when(() => facade.currentSession).thenReturn(_evan);
    final vm = ShowcaseNotesViewModel();
    await vm.createFolder('  Errands ');
    verify(() => facade.createFolder('user-1', 'Errands', sortOrder: 2))
        .called(1);
  });
}
""");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('verifyNever with any() matchers passes (negative-boundary is real behavior)', () {
      plantMap('intake/map.json');
      write('test/negative_boundary_test.dart', """
void main() {
  test('notes.folders.create-folder — a blank name is dropped before the facade', () async {
    final vm = ShowcaseNotesViewModel();
    await vm.createFolder('   ');
    verifyNever(() => facade.createFolder(any(), any(), sortOrder: any(named: 'sortOrder')));
  });
}
""");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('a bare-any verify pile fails (theater, however many verifies)', () {
      plantMap('intake/map.json');
      plantPassingTestFile();
      write('test/double_verify_test.dart', """
void main() {
  test('notes.folders.create-folder — save persists and notifies', () async {
    await vm.save();
    verify(() => repo.save(any()));
    verify(() => bus.emit(any()));
  });
}
""");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('verify()-only test (T2)'));
      expect(detailsOf(r), contains('double_verify_test.dart'));
    });

    test('a two-phase verifyNever + pinned verify passes (corpus regression)', () {
      plantMap('intake/map.json');
      // The showcase shape: cancel-path asserted with verifyNever(any), then
      // the happy-path verified with PINNED arguments — two verifies, both
      // meaningful; the count rule would false-fail this.
      write('test/two_phase_test.dart', """
void main() {
  test('notes.folders.create-folder — createFolderWithPrompt creates the folder only when the prompt returns a name', () async {
    await vm.createFolderWithPrompt();
    verifyNever(() => facade.createFolder(any(), any(), sortOrder: any(named: 'sortOrder')));
    notifications.promptResult = 'Errands';
    await vm.createFolderWithPrompt();
    verify(() => facade.createFolder('user-1', 'Errands', sortOrder: 0)).called(1);
  });
}
""");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('a behavior test whose name merely contains "creates" passes', () {
      plantMap('intake/map.json');
      write('test/behavior_test.dart',
          "// covers notes.folders.create-folder\n"
          "void main() { test('notes.folders.create-folder — creates folder and emits it in folder list', () {}); }\n");
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });
  });

  group('T1: story coverage (traceability)', () {
    test('an uncovered must story fails and names the id', () {
      plantMap('intake/map.json');
      write('test/unrelated_test.dart', "void main() { test('x', () {}); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('uncovered story (T1)'));
      expect(detailsOf(r), contains('notes.folders.create-folder'));
    });

    test('a could story is never required', () {
      plantMap('intake/map.json');
      plantPassingTestFile(); // names only the must id
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), isNot(contains('archive-folder')));
    });

    test('a should story is required too', () {
      write('intake/map.json', '''
{"epics": [{"id": "e", "features": [{"id": "e.f",
  "stories": [{"id": "e.f.ship-it", "priority": "should"}]}]}]}
''');
      write('test/unrelated_test.dart', "void main() { test('x', () {}); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('e.f.ship-it'));
    });

    test('intake/map.json wins over docs/design/story-map.json', () {
      plantMap('intake/map.json'); // covered below
      // The design-doc map carries a story nothing covers; discovery must
      // never reach it.
      write('docs/design/story-map.json', '''
{"epics": [{"id": "e", "features": [{"id": "e.f",
  "stories": [{"id": "e.f.ghost", "priority": "must"}]}]}]}
''');
      plantPassingTestFile();
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
    });

    test('docs/design/story-map.json is the fallback', () {
      write('docs/design/story-map.json', '''
{"epics": [{"id": "e", "features": [{"id": "e.f",
  "stories": [{"id": "e.f.ghost", "priority": "must"}]}]}]}
''');
      write('test/unrelated_test.dart', "void main() { test('x', () {}); }\n");
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('e.f.ghost'));
    });

    test('no map found warns and passes (portalo-era projects lack maps)', () {
      plantPassingTestFile();
      final r = run();
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('WARN'));
      expect(detailsOf(r), contains('no story map found'));
    });

    test('an unparseable map fails (present input never passes quietly)', () {
      write('intake/map.json', '{not json');
      plantPassingTestFile();
      final r = run();
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('does not parse'));
    });

    test('--project reads ~/.appbox/projects/<name>/intake/map.json', () {
      appboxHomeOverride = '${tmp.path}/.appbox';
      Directory('$app/.appbox/projects/demo/intake')
          .createSync(recursive: true);
      plantMap('.appbox/projects/demo/intake/map.json');
      write('test/unrelated_test.dart', "void main() { test('x', () {}); }\n");
      final r = testsGate(
          GateContext(repoRoot: app, appRoot: app, check: true),
          project: 'demo');
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('notes.folders.create-folder'));
    });

    test('--project refuses a path-traversal name', () {
      final r = testsGate(
          GateContext(repoRoot: app, appRoot: app, check: true),
          project: '..');
      expect(r.exitCode, envExit);
    });
  });

  group('T3: tests pass', () {
    // Real `dart test` subprocesses — first run compiles the runner.
    const t3Timeout = Timeout(Duration(minutes: 3));

    /// A pure-Dart micro-fixture: test as a dev dependency, resolved offline
    /// from the pub cache (the cache provably holds it — this very suite runs
    /// on it). Never a flutter fixture: the suite stays fast and hermetic.
    void plantDartPackage(String testBody) {
      write('pubspec.yaml', '''
name: demo
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
      write('test/demo_test.dart', testBody);
      final pub = Process.runSync('dart', ['pub', 'get', '--offline'],
          workingDirectory: app);
      if (pub.exitCode != 0) {
        fail('fixture `dart pub get --offline` failed: ${pub.stderr}');
      }
    }

    test('a passing dart test suite passes the gate', () {
      plantDartPackage("import 'package:test/test.dart';\n"
          "void main() { test('math', () => expect(1 + 1, 2)); }\n");
      final r = run(check: false);
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('dart test passed (T3)'));
    }, timeout: t3Timeout);

    test('a failing dart test suite fails the gate with the output tail', () {
      plantDartPackage("import 'package:test/test.dart';\n"
          "void main() { test('math', () => expect(1 + 1, 3)); }\n");
      final r = run(check: false);
      expect(r.passed, isFalse);
      expect(detailsOf(r), contains('dart test failed (exit 1) (T3)'));
      expect(detailsOf(r), contains('output tail'));
    }, timeout: t3Timeout);

    test('--check skips the test run even when tests would fail', () {
      plantDartPackage("import 'package:test/test.dart';\n"
          "void main() { test('math', () => expect(1 + 1, 3)); }\n");
      final r = run(check: true);
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('test run skipped (T3)'));
    }, timeout: t3Timeout);
  });

  group('R5 self-test', () {
    test('the embedded --self-test passes (positive + negative)', () {
      final r = testsGate(
          GateContext(repoRoot: app, appRoot: app, selfTest: true));
      expect(r.passed, isTrue, reason: detailsOf(r));
      expect(detailsOf(r), contains('NEGATIVE'));
    });
  });
}
