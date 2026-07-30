import 'dart:convert';
import 'dart:io';

import 'package:appboxd/memory.dart';
import 'package:appboxd/memory_analytics.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes [lines] as JSONL at [relPath] under [root] (raw strings, so a
/// corrupt line can be a plain non-JSON string).
void writeJsonl(String root, String relPath, List<String> lines) {
  final file = File(p.join(root, relPath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(lines.map((l) => '$l\n').join());
}

String scorecardEntry({
  String stage = 'build',
  String? tier = 'standard',
  bool? gatePass = true,
  int retries = 0,
}) =>
    jsonEncode({
      'stage': stage,
      'tier': tier,
      'provider': 'kimi',
      'model': 'kimi-k2.7-code',
      'tokens_in': 100,
      'tokens_out': 50,
      'cost': null,
      'gate_pass': gatePass,
      'retries': retries,
    });

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('memory-analytics-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('routingRegret', () {
    test('per-stage-per-tier pass rate and mean retries', () async {
      writeJsonl(tmp.path, 'pipeline/state/scorecard.jsonl', [
        // build/standard: 2 of 3 judged pass, 3 retries over 3 runs.
        scorecardEntry(gatePass: true, retries: 1),
        scorecardEntry(gatePass: true, retries: 2),
        scorecardEntry(gatePass: false),
        // Null gate_pass is excluded from the rate, not a failure.
        scorecardEntry(gatePass: null),
        // review/frontier: all pass, no retries.
        scorecardEntry(stage: 'review', tier: 'frontier'),
        scorecardEntry(stage: 'review', tier: 'frontier'),
      ]);

      final report = await routingRegret(tmp.path);
      expect(report.rows, hasLength(2));

      final build = report.rows.firstWhere((r) => r.stage == 'build');
      expect(build.runs, 4);
      expect(build.passKnown, 3);
      expect(build.passRate, closeTo(2 / 3, 1e-9));
      expect(build.meanRetries, closeTo(3 / 4, 1e-9));

      final review = report.rows.firstWhere((r) => r.stage == 'review');
      expect(review.passRate, 1.0);
      expect(review.meanRetries, 0);
      // Sorted by stage name.
      expect(report.rows.map((r) => r.stage), ['build', 'review']);
    });

    test('null pass rate when no run has a gate verdict', () async {
      writeJsonl(tmp.path, 'pipeline/state/scorecard.jsonl',
          [scorecardEntry(gatePass: null)]);
      final report = await routingRegret(tmp.path);
      expect(report.rows.single.passRate, isNull);
      expect(report.rows.single.passKnown, 0);
    });

    test('corrupt lines are skipped and counted', () async {
      writeJsonl(tmp.path, 'pipeline/state/scorecard.jsonl', [
        scorecardEntry(),
        'this is not json',
        '[1, 2, 3]', // valid JSON, wrong shape
        '{"stage": "x"', // truncated
        scorecardEntry(gatePass: false),
      ]);
      final report = await routingRegret(tmp.path);
      expect(report.rows.single.runs, 2);
      expect(report.counts.total, 5);
      expect(report.counts.corrupt, 3);
    });

    test('missing scorecard file yields an empty report', () async {
      final report = await routingRegret(tmp.path);
      expect(report.rows, isEmpty);
      expect(report.counts.total, 0);
    });
  });

  group('spend', () {
    test('groups by provider, model, consumer, day', () async {
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer_token_id': 't1',
          'consumer': 'engine:build',
          'tier': 'standard',
          'provider': 'kimi',
          'model': 'kimi-k2.7-code',
          'tokens_in': 100,
          'tokens_out': 50,
          'ts': '2026-07-29T10:00:00.000Z',
        }),
        jsonEncode({
          'consumer_token_id': 't1',
          'consumer': 'engine:build',
          'tier': 'standard',
          'provider': 'kimi',
          'model': 'kimi-k2.7-code',
          'tokens_in': 200,
          'tokens_out': 60,
          'ts': '2026-07-29T22:00:00.000Z', // same day → same cell
        }),
        jsonEncode({
          'consumer_token_id': 't2',
          'consumer': 'genui',
          'tier': 'fast',
          'provider': 'zai',
          'model': 'glm-4.7-flash',
          'tokens_in': 10,
          'tokens_out': 5,
          'ts': '2026-07-30T01:00:00.000Z', // different day+consumer
        }),
      ]);

      final report = await spend(tmp.path);
      expect(report.rows, hasLength(2));
      // Sorted by total tokens descending.
      final kimi = report.rows.first;
      expect(kimi.provider, 'kimi');
      expect(kimi.consumer, 'engine:build');
      expect(kimi.day, '2026-07-29');
      expect(kimi.rows, 2);
      expect(kimi.tokensIn, 300);
      expect(kimi.tokensOut, 110);
      expect(report.totalTokensIn, 310);
      expect(report.totalTokensOut, 115);
    });

    test('cost is null-honest: sums non-null only, reports coverage', () async {
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer': 'engine:build',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 1,
          'tokens_out': 1,
          'cost': 0.0123,
          'ts': '2026-07-30T00:00:00.000Z',
        }),
        jsonEncode({
          'consumer': 'engine:build',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 1,
          'tokens_out': 1,
          'cost': null, // unknown — must not drag the sum or the coverage
          'ts': '2026-07-30T01:00:00.000Z',
        }),
        jsonEncode({
          'consumer': 'engine:build',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 1,
          'tokens_out': 1,
          // cost field absent entirely
          'ts': '2026-07-30T02:00:00.000Z',
        }),
      ]);

      final report = await spend(tmp.path);
      final row = report.rows.single;
      expect(row.rows, 3);
      expect(row.cost, closeTo(0.0123, 1e-12));
      expect(row.costCoverage, 1);
      expect(report.costCoverage, 1);
      expect(report.totalRows, 3);
    });

    test('since filters by ts and drops unparseable timestamps', () async {
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer': 'a',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 1,
          'tokens_out': 1,
          'ts': '2026-07-01T00:00:00.000Z',
        }),
        jsonEncode({
          'consumer': 'a',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 2,
          'tokens_out': 2,
          'ts': '2026-07-30T00:00:00.000Z',
        }),
        jsonEncode({
          'consumer': 'a',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 4,
          'tokens_out': 4,
          'ts': 'not-a-date',
        }),
      ]);

      final report = await spend(tmp.path,
          since: DateTime.utc(2026, 7, 15));
      expect(report.rows, hasLength(1));
      expect(report.rows.single.tokensIn, 2);
    });

    test('corrupt lines are skipped and counted', () async {
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer': 'a',
          'provider': 'kimi',
          'model': 'm',
          'tokens_in': 1,
          'tokens_out': 1,
          'ts': '2026-07-30T00:00:00.000Z',
        }),
        'garbage',
      ]);
      final report = await spend(tmp.path);
      expect(report.rows, hasLength(1));
      expect(report.counts.corrupt, 1);
    });

    test('missing usage file yields an empty report', () async {
      final report = await spend(tmp.path);
      expect(report.rows, isEmpty);
    });
  });

  group('briefing', () {
    test('renders all sections with all three inputs present', () async {
      writeJsonl(tmp.path, 'pipeline/state/scorecard.jsonl', [
        scorecardEntry(stage: 'intake', tier: 'frontier', retries: 2),
        scorecardEntry(stage: 'intake', tier: 'frontier', gatePass: false),
        scorecardEntry(),
        'corrupt line',
      ]);
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer': 'engine:build',
          'provider': 'kimi',
          'model': 'kimi-k2.7-code',
          'tokens_in': 100,
          'tokens_out': 50,
          'cost': 0.5,
          'ts': '2026-07-30T00:00:00.000Z',
        }),
      ]);
      writeJsonl(tmp.path, 'pipeline/state/memory/events.jsonl', [
        MemoryEvent(kind: MemoryKinds.gateRun, actor: 'deploy-gate').toLine(),
        MemoryEvent(kind: MemoryKinds.gateRun, actor: 'deploy-gate').toLine(),
        MemoryEvent(kind: MemoryKinds.note, actor: 'operator').toLine(),
      ]);

      final md = await briefing(tmp.path);
      expect(md, contains('# app-box operator briefing'));
      expect(md, contains('## Gate pass rate (routing regret)'));
      expect(md, contains('| intake | frontier | 2 | 50% | 1.00 |'));
      expect(md, contains('## Top retry offenders'));
      expect(md, contains('1. intake/frontier — mean 1.00 retries'));
      expect(md, contains('## Spend'));
      expect(md, contains('(1/1 rows priced)'));
      expect(md,
          contains('| kimi | kimi-k2.7-code | engine:build | 2026-07-30 | 100 | 50 | \$0.5000 |'));
      expect(md, contains('## Memory events'));
      expect(md, contains('3 events (gate_run=2, note=1)'));
      expect(md, contains('corrupt scorecard'));
      expect(md.split('\n').length, lessThanOrEqualTo(60));
    });

    test('counts events by the real MemoryEvent kind field', () async {
      // Pin the on-disk contract: writers (engine, gateway, gates) serialize
      // memory.dart's MemoryEvent — {ts, kind, actor, payload} — and the
      // briefing must count by `kind`, never a legacy `type` field.
      writeJsonl(tmp.path, 'pipeline/state/memory/events.jsonl', [
        MemoryEvent(
          kind: MemoryKinds.llmRequest,
          actor: 'gateway',
          payload: {'consumer': 'pipeline-stage:build', 'ok': true},
        ).toLine(),
        MemoryEvent(kind: MemoryKinds.llmRequest, actor: 'gateway').toLine(),
        MemoryEvent(kind: MemoryKinds.llmRequest, actor: 'gateway').toLine(),
        MemoryEvent(kind: MemoryKinds.stageRun, actor: 'engine').toLine(),
        MemoryEvent(kind: MemoryKinds.stageRun, actor: 'engine').toLine(),
        // A legacy/foreign line without `kind` is untyped, not miscounted.
        jsonEncode({'type': 'lesson', 'text': 'x'}),
      ]);

      final md = await briefing(tmp.path);
      expect(md,
          contains('6 events (llm_request=3, stage_run=2, (untyped)=1)'));
    });

    test('renders with all inputs missing', () async {
      final md = await briefing(tmp.path);
      expect(md, contains('no scorecard data'));
      expect(md, contains('no usage data'));
      expect(md, contains('memory/events.jsonl not present yet'));
      expect(md, contains('none')); // no retry offenders
      expect(md.split('\n').length, lessThanOrEqualTo(60));
    });

    test('unpriced spend renders an em dash, never a fabricated cost',
        () async {
      writeJsonl(tmp.path, 'pipeline/state/usage.jsonl', [
        jsonEncode({
          'consumer': 'genui',
          'provider': 'zai',
          'model': 'glm-4.7-flash',
          'tokens_in': 10,
          'tokens_out': 5,
          'ts': '2026-07-30T00:00:00.000Z',
        }),
      ]);
      final md = await briefing(tmp.path);
      expect(md, contains('cost: — (0/1 rows priced)'));
      expect(md, isNot(contains('\$0.0000')));
    });
  });
}
