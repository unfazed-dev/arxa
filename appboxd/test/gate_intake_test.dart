// Tests for the intake gate's brief-SECTION check (gate_intake.dart).
//
// When the trace source is intake answers AND a brief exists on disk, the
// brief must be the unified chain brief: `## Surface inventory` always, `##
// Layout template` when the answers declare one. Hand-written briefs without
// answers (10.7) skip the check. Traceability itself is covered elsewhere;
// these tests isolate the section check.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gate_intake.dart';
import 'package:appboxd/gates.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('appbox_gate_intake');
    Directory('${tmp.path}/designs/appbox-studio/models/screens_model')
        .createSync(recursive: true);
    Directory('${tmp.path}/pipeline/state').createSync(recursive: true);
    File('${tmp.path}/designs/appbox-studio/models/screens_model/registry.json')
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
    File('${tmp.path}/designs/appbox-studio/brief.md').writeAsStringSync(md);
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
              d.contains('appbox emit story-map')),
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
              d.contains('appbox emit story-map')),
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
}
