import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Read-only rollups over the pipeline's JSONL streams (M1,
/// docs/plans/appbox-memory-and-payment.md). This module never writes —
/// deterministic writers (engine, gateway, gates) own the append path;
/// analytics only reads:
///
/// - `pipeline/state/scorecard.jsonl` — per stage run:
///   {stage, tier, provider, model, tokens_in, tokens_out, cost, gate_pass,
///   retries} (E4, engine.dart).
/// - `pipeline/state/usage.jsonl` — per gateway call:
///   {consumer_token_id, consumer, tier, provider, model, tokens_in,
///   tokens_out, ts} (E2, gateway.dart). `cost` is read when present
///   (future field) — never estimated.
/// - `pipeline/state/memory/events.jsonl` — raw memory events in the
///   MemoryEvent shape {ts, kind, actor, payload} (memory.dart); absence is
///   normal and tolerated.
///
/// All readers stream line-by-line and are corrupt-line tolerant: a bad
/// line is skipped and counted, never fatal.

/// How a single JSONL read went: lines seen vs. lines skipped as corrupt.
class LineCounts {
  int total = 0;
  int corrupt = 0;
}

/// Streams decoded JSON objects from [file], tolerating absence and
/// corrupt lines (counted into [counts]).
Stream<Map<String, Object?>> _readJsonl(File file, LineCounts counts) async* {
  if (!file.existsSync()) return;
  await for (final line in file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    counts.total++;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      counts.corrupt++;
      continue;
    }
    if (decoded is! Map) {
      counts.corrupt++;
      continue;
    }
    yield decoded.cast<String, Object?>();
  }
}

int? _asInt(Object? value) =>
    value is int ? value : (value is num ? value.toInt() : null);

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

String? _asString(Object? value) => value is String ? value : null;

// ---------------------------------------------------------------------------
// routingRegret — the E4 tuning metric: per-stage gate-pass-rate per tier.
// ---------------------------------------------------------------------------

/// One stage×tier cell of the routing-regret report.
class RegretRow {
  RegretRow({required this.stage, required this.tier});

  final String stage;

  /// Null tier is possible: scorecards written before fabric wiring (and
  /// non-LLM stages) carry `tier: null`.
  final String? tier;

  int runs = 0;
  int totalRetries = 0;

  /// gate_pass counted only where it is a bool — null (gate not yet run)
  /// is excluded from the rate, not treated as a failure.
  int passKnown = 0;
  int passes = 0;

  double get meanRetries => runs == 0 ? 0 : totalRetries / runs;

  /// Null when no run in this cell has a recorded gate verdict.
  double? get passRate => passKnown == 0 ? null : passes / passKnown;
}

/// The routing-regret report (E4: "routing-regret metric = per-stage
/// gate-pass-rate per tier; tune the map from it").
class RoutingRegret {
  RoutingRegret({required this.rows, required this.counts});

  /// Sorted by stage, then tier (nulls last).
  final List<RegretRow> rows;
  final LineCounts counts;
}

/// Rolls up `pipeline/state/scorecard.jsonl` under [repoRoot] into
/// per-stage-per-tier gate pass rates and mean retries.
Future<RoutingRegret> routingRegret(String repoRoot) async {
  final counts = LineCounts();
  final cells = <String, RegretRow>{};
  final file = File(p.join(repoRoot, 'pipeline', 'state', 'scorecard.jsonl'));
  await for (final entry in _readJsonl(file, counts)) {
    final stage = _asString(entry['stage']) ?? '(unknown)';
    final tier = _asString(entry['tier']);
    final row = cells.putIfAbsent(
        '$stage$tier', () => RegretRow(stage: stage, tier: tier));
    row.runs++;
    row.totalRetries += _asInt(entry['retries']) ?? 0;
    final gatePass = entry['gate_pass'];
    if (gatePass is bool) {
      row.passKnown++;
      if (gatePass) row.passes++;
    }
  }
  final rows = cells.values.toList()
    ..sort((a, b) {
      final byStage = a.stage.compareTo(b.stage);
      if (byStage != 0) return byStage;
      return (a.tier ?? '').compareTo(b.tier ?? '');
    });
  return RoutingRegret(rows: rows, counts: counts);
}

// ---------------------------------------------------------------------------
// spend — tokens/cost by provider, model, consumer, day (E2 attribution).
// ---------------------------------------------------------------------------

/// One provider×model×consumer×day cell of the spend report.
class SpendRow {
  SpendRow({this.provider, this.model, this.consumer, this.day});

  final String? provider;
  final String? model;
  final String? consumer;

  /// ISO date (yyyy-mm-dd) from the record's `ts`; null when absent.
  final String? day;

  int rows = 0;
  int tokensIn = 0;
  int tokensOut = 0;

  /// Sum over non-null costs only — cost is null-honest: rows whose cost
  /// is unknown contribute nothing, and [costCoverage] says how many rows
  /// actually carried a price.
  double cost = 0;
  int costCoverage = 0;
}

/// The spend report over `pipeline/state/usage.jsonl`.
class SpendReport {
  SpendReport({required this.rows, required this.counts});

  /// Sorted by total tokens (in + out), descending.
  final List<SpendRow> rows;
  final LineCounts counts;

  int get totalTokensIn => rows.fold(0, (sum, r) => sum + r.tokensIn);
  int get totalTokensOut => rows.fold(0, (sum, r) => sum + r.tokensOut);
  double get totalCost => rows.fold(0.0, (sum, r) => sum + r.cost);
  int get costCoverage => rows.fold(0, (sum, r) => sum + r.costCoverage);
  int get totalRows => rows.fold(0, (sum, r) => sum + r.rows);
}

/// Rolls up `pipeline/state/usage.jsonl` under [repoRoot]. With [since],
/// only records whose `ts` parses and is not before [since] are counted
/// (records with an unparseable `ts` are excluded from a filtered report).
Future<SpendReport> spend(String repoRoot, {DateTime? since}) async {
  final counts = LineCounts();
  final cells = <String, SpendRow>{};
  final file = File(p.join(repoRoot, 'pipeline', 'state', 'usage.jsonl'));
  await for (final entry in _readJsonl(file, counts)) {
    final ts = DateTime.tryParse(_asString(entry['ts']) ?? '');
    if (since != null && (ts == null || ts.isBefore(since))) continue;
    final provider = _asString(entry['provider']);
    final model = _asString(entry['model']);
    final consumer = _asString(entry['consumer']);
    final day = ts?.toUtc().toIso8601String().substring(0, 10);
    final row = cells.putIfAbsent(
        '$provider$model$consumer$day',
        () => SpendRow(
            provider: provider,
            model: model,
            consumer: consumer,
            day: day));
    row.rows++;
    row.tokensIn += _asInt(entry['tokens_in']) ?? 0;
    row.tokensOut += _asInt(entry['tokens_out']) ?? 0;
    final cost = _asDouble(entry['cost']);
    if (cost != null) {
      row.cost += cost;
      row.costCoverage++;
    }
  }
  final rows = cells.values.toList()
    ..sort((a, b) =>
        (b.tokensIn + b.tokensOut).compareTo(a.tokensIn + a.tokensOut));
  return SpendReport(rows: rows, counts: counts);
}

// ---------------------------------------------------------------------------
// Memory events (writers: engine, gateway, gates — absence is normal).
// ---------------------------------------------------------------------------

class EventCounts {
  EventCounts(
      {required this.present,
      required this.total,
      required this.byKind,
      required this.counts});

  /// Whether memory/events.jsonl exists at all.
  final bool present;
  final int total;

  /// Count by the event's `kind` field (memory.dart's MemoryEvent); events
  /// without one land under '(untyped)'.
  final Map<String, int> byKind;
  final LineCounts counts;
}

Future<EventCounts> _eventCounts(String repoRoot) async {
  final counts = LineCounts();
  final file =
      File(p.join(repoRoot, 'pipeline', 'state', 'memory', 'events.jsonl'));
  final byKind = <String, int>{};
  var total = 0;
  await for (final entry in _readJsonl(file, counts)) {
    total++;
    final kind = _asString(entry['kind']) ?? '(untyped)';
    byKind[kind] = (byKind[kind] ?? 0) + 1;
  }
  return EventCounts(
      present: file.existsSync(),
      total: total,
      byKind: byKind,
      counts: counts);
}

// ---------------------------------------------------------------------------
// briefing — compact markdown for the operator (M1: operator briefings).
// ---------------------------------------------------------------------------

/// Table row caps keep the briefing at or under 60 lines regardless of how
/// much history the streams hold.
const _maxRegretRows = 12;
const _maxSpendRows = 12;
const _maxOffenders = 5;

String _pct(double? rate) =>
    rate == null ? 'n/a' : '${(rate * 100).toStringAsFixed(0)}%';

String _money(double cost, int coverage) =>
    coverage == 0 ? '—' : '\$${cost.toStringAsFixed(4)}';

/// Renders the operator briefing: pass rates, top retry offenders, spend
/// table, event counts. Missing streams degrade to a one-line note, so the
/// briefing renders from day zero. Output is capped at 60 lines.
Future<String> briefing(String repoRoot) async {
  final regret = await routingRegret(repoRoot);
  final spendReport = await spend(repoRoot);
  final events = await _eventCounts(repoRoot);

  final out = StringBuffer()
    ..writeln('# appbox operator briefing')
    ..writeln(
        '_generated ${DateTime.now().toUtc().toIso8601String().substring(0, 19)}Z_')
    ..writeln()
    ..writeln('## Gate pass rate (routing regret)');

  if (regret.rows.isEmpty) {
    out.writeln('no scorecard data');
  } else {
    out
      ..writeln('| stage | tier | runs | pass rate | mean retries |')
      ..writeln('|---|---|---|---|---|');
    for (final row in regret.rows.take(_maxRegretRows)) {
      out.writeln(
          '| ${row.stage} | ${row.tier ?? '—'} | ${row.runs} | '
          '${_pct(row.passRate)}${row.passKnown < row.runs ? ' (${row.passKnown}/${row.runs} judged)' : ''} | '
          '${row.meanRetries.toStringAsFixed(2)} |');
    }
    if (regret.rows.length > _maxRegretRows) {
      out.writeln('_…and ${regret.rows.length - _maxRegretRows} more cells_');
    }
    if (regret.counts.corrupt > 0) {
      out.writeln('_skipped ${regret.counts.corrupt} corrupt scorecard line(s)_');
    }
  }

  out
    ..writeln()
    ..writeln('## Top retry offenders');
  final offenders = regret.rows.where((r) => r.totalRetries > 0).toList()
    ..sort((a, b) => b.meanRetries.compareTo(a.meanRetries));
  if (offenders.isEmpty) {
    out.writeln('none');
  } else {
    var rank = 0;
    for (final row in offenders.take(_maxOffenders)) {
      out.writeln(
          '${++rank}. ${row.stage}/${row.tier ?? '—'} — mean ${row.meanRetries.toStringAsFixed(2)} retries over ${row.runs} run(s)');
    }
  }

  out
    ..writeln()
    ..writeln('## Spend');
  if (spendReport.rows.isEmpty) {
    out.writeln('no usage data');
  } else {
    out
      ..writeln('tokens: ${spendReport.totalTokensIn} in / '
          '${spendReport.totalTokensOut} out · '
          'cost: ${_money(spendReport.totalCost, spendReport.costCoverage)} '
          '(${spendReport.costCoverage}/${spendReport.totalRows} rows priced)')
      ..writeln('| provider | model | consumer | day | tok in | tok out | cost |')
      ..writeln('|---|---|---|---|---|---|---|');
    for (final row in spendReport.rows.take(_maxSpendRows)) {
      out.writeln(
          '| ${row.provider ?? '—'} | ${row.model ?? '—'} | ${row.consumer ?? '—'} | '
          '${row.day ?? '—'} | ${row.tokensIn} | ${row.tokensOut} | '
          '${_money(row.cost, row.costCoverage)} |');
    }
    if (spendReport.rows.length > _maxSpendRows) {
      out.writeln(
          '_…and ${spendReport.rows.length - _maxSpendRows} more cells_');
    }
    if (spendReport.counts.corrupt > 0) {
      out.writeln('_skipped ${spendReport.counts.corrupt} corrupt usage line(s)_');
    }
  }

  out
    ..writeln()
    ..writeln('## Memory events');
  if (!events.present) {
    out.writeln('memory/events.jsonl not present yet');
  } else if (events.total == 0) {
    out.writeln('0 events');
  } else {
    final kinds = events.byKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    out.writeln(
        '${events.total} events (${kinds.map((e) => '${e.key}=${e.value}').join(', ')})');
    if (events.counts.corrupt > 0) {
      out.writeln('_skipped ${events.counts.corrupt} corrupt event line(s)_');
    }
  }

  return out.toString();
}
