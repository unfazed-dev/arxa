// Tests for the intake gate's brief-SECTION check (gate_intake.dart).
//
// When the trace source is intake answers AND a brief exists on disk, the
// brief must be the unified chain brief: `## Surface inventory` always, `##
// Layout template` when the answers declare one. Hand-written briefs without
// answers (10.7) skip the check. Traceability itself is covered elsewhere;
// these tests isolate the section check.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/gate_intake.dart';
import 'package:arxa/gates.dart';
import 'package:arxa/intake.dart' show emitFlows;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('arxa_gate_intake');
    Directory('${tmp.path}/designs/arxa-studio/models/screens_model')
        .createSync(recursive: true);
    Directory('${tmp.path}/pipeline/state').createSync(recursive: true);
    File('${tmp.path}/designs/arxa-studio/models/screens_model/registry.json')
        .writeAsStringSync(jsonEncode([
      {'id': 'projects.home'},
    ]));
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void writeAnswers(Map<String, dynamic> answers) {
    File('${tmp.path}/pipeline/state/run.intake.json')
        .writeAsStringSync(jsonEncode({'answers': answers}));
  }

  void writeBrief(String md) {
    File('${tmp.path}/designs/arxa-studio/brief.md').writeAsStringSync(md);
  }

  Map<String, dynamic> answers({bool withLayout = false}) {
    final a = <String, dynamic>{
      'surfaces': [
        {'id': 'projects.home', 'label': 'Home', 'shell': 'projects', 'provenance': 'client'},
      ],
    };
    if (withLayout) {
      a['layoutTemplate'] = {'value': {}, 'provenance': 'client'};
    }
    return a;
  }

  const chainBrief = '# App\n\n## Surface inventory\n\n'
      '| id | label |\n|---|---|\n| `projects.home` | Home |\n';

  GateResult run() => intakeGate(GateContext(repoRoot: tmp.path));

  group('brief-section check', () {
    test('passes when the chain headings are present', () {
      writeAnswers(answers());
      writeBrief(chainBrief);
      final res = run();
      expect(res.passed, isTrue, reason: res.details.join('\n'));
    });

    test('fails when ## Surface inventory is missing, naming the chain fix', () {
      writeAnswers(answers());
      writeBrief('# App\n\n## Screens\n\n| id |\n|---|\n| `projects.home` |\n');
      final res = run();
      expect(res.passed, isFalse);
      expect(
          res.details.any((d) =>
              d.contains('## Surface inventory') &&
              d.contains('arxa emit story-map')),
          isTrue,
          reason: res.details.join('\n'));
    });

    test('fails when answers declare layoutTemplate but ## Layout template is missing', () {
      writeAnswers(answers(withLayout: true));
      writeBrief(chainBrief);
      final res = run();
      expect(res.passed, isFalse);
      expect(
          res.details.any((d) =>
              d.contains('## Layout template') &&
              d.contains('arxa emit story-map')),
          isTrue,
          reason: res.details.join('\n'));
    });

    test('passes with layoutTemplate when both headings are present', () {
      writeAnswers(answers(withLayout: true));
      writeBrief('# App\n\n## Layout template\n\nx\n\n$chainBrief');
      final res = run();
      expect(res.passed, isTrue, reason: res.details.join('\n'));
    });

    test('skipped for a hand-written brief without answers (10.7)', () {
      // No state files; the brief traces via its table under a non-standard
      // heading — no section check applies.
      writeBrief('# App\n\n## Screens\n\n'
          '| id | label |\n|---|---|\n| `projects.home` | Home |\n');
      final res = run();
      expect(res.passed, isTrue, reason: res.details.join('\n'));
    });

    test('skipped when no brief file exists on disk', () {
      writeAnswers(answers());
      final res = run();
      expect(res.passed, isTrue, reason: res.details.join('\n'));
    });
  });

  // The flows check compares parsed structures, never bytes. The comparison is
  // the unit under test: the gate's own wiring (project shell → flows.json) is
  // covered by running it against a real project.
  group('flows ≡ emitFlows(answers)', () {
    Map<String, dynamic> flowAnswers() => {
          'flows': [
            {
              'id': 'flow-onboarding',
              'name': 'Onboarding',
              'provenance': 'founder',
              'edges': [
                {'from': 'a.splash', 'to': 'a.auth', 'trigger': 'App launch'},
                {'from': 'a.auth', 'to': 'a.home', 'trigger': 'Sign-in success'},
              ],
            },
          ],
        };

    test('passes when the same data is written in a different KEY ORDER', () {
      final projected = emitFlows(flowAnswers());
      // A second writer, same data, keys emitted in the opposite order — the
      // legitimate excise-vs-appendTo variation in design_facade.js.
      final onDisk = [
        {
          'edges': [
            {'trigger': 'App launch', 'action': 'push', 'to': 'a.auth', 'from': 'a.splash'},
            {'trigger': 'Sign-in success', 'action': 'push', 'to': 'a.home', 'from': 'a.auth'},
          ],
          'provenance': 'founder',
          'name': 'Onboarding',
          'id': 'flow-onboarding',
        },
      ];
      // Guard the guard: a byte/JSON-string compare WOULD flap on this input,
      // so this assertion fails loudly if anyone swaps one in later.
      expect(jsonEncode(onDisk), isNot(equals(jsonEncode(projected))),
          reason: 'fixture no longer differs by key order — it proves nothing');
      expect(diffFlows(onDisk, projected), isEmpty);
    });

    test('fails on a differing trigger, naming flow, edge index and both values',
        () {
      final projected = emitFlows(flowAnswers());
      final onDisk = jsonDecode(jsonEncode(projected)) as List;
      (onDisk[0]['edges'][1] as Map)['trigger'] = 'continue';
      final diffs = diffFlows(onDisk, projected);
      expect(diffs, hasLength(1));
      expect(diffs.single, contains("flow 'flow-onboarding'"));
      expect(diffs.single, contains('edge 1'));
      expect(diffs.single, contains("key 'trigger'"));
      expect(diffs.single, contains('continue'));
      expect(diffs.single, contains('Sign-in success'));
    });

    test('fails when the EDGES are reordered — a flow is a chain', () {
      final projected = emitFlows(flowAnswers());
      final onDisk = jsonDecode(jsonEncode(projected)) as List;
      final edges = onDisk[0]['edges'] as List;
      onDisk[0]['edges'] = [edges[1], edges[0]];
      expect(diffFlows(onDisk, projected), isNotEmpty);
    });

    test('passes when an optional key is absent on BOTH sides', () {
      // Neither side carries `element` or `feedback`; absence must not diff.
      final projected = emitFlows(flowAnswers());
      final onDisk = jsonDecode(jsonEncode(projected)) as List;
      expect(
          (onDisk[0]['edges'][0] as Map).containsKey('element'), isFalse,
          reason: 'fixture must not carry the optional key it is testing');
      expect(diffFlows(onDisk, projected), isEmpty);
    });

    test('reports an optional key present on one side only', () {
      final projected = emitFlows(flowAnswers());
      final onDisk = jsonDecode(jsonEncode(projected)) as List;
      (onDisk[0]['edges'][0] as Map)['element'] = 'button:Continue';
      final diffs = diffFlows(onDisk, projected);
      expect(diffs, hasLength(1));
      expect(diffs.single, contains("key 'element'"));
      expect(diffs.single, contains('button:Continue'));
      expect(diffs.single, contains('(absent)'));
    });
  });
}
