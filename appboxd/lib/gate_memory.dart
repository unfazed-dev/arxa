// Memory gate — port of gates/memory/memory.sh to pure Dart.
//
// Checks (all must pass):
//   1. index    — memory/MEMORY.md exists and is <= 100 lines
//   2. facts    — every memory/facts/*.json parses as [{fact, source, ts}]
//   3. lessons  — every memory/stages/*.LESSONS.md is <= 200 lines
//   4. abspath  — no forbidden absolute-path prefix under memory/

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/gates.dart';

GateResult memoryGate(GateContext ctx) {
  final root = ctx.repoRoot;
  final mem = Directory('$root/memory');
  final details = <String>[];
  var fails = 0;

  void ok(String msg) => details.add('  ✓ $msg');
  void fail(String msg) {
    details.add('  ✗ $msg');
    ctx.sarif.result('memory', 'error', 'memory', msg);
    fails++;
  }

  // ---- 1. index ----
  final indexFile = File('${mem.path}/MEMORY.md');
  if (!indexFile.existsSync()) {
    fail('index: memory/MEMORY.md missing — the curated-memory index is the entry point');
  } else {
    final n = indexFile.readAsLinesSync().length;
    if (n <= 100) {
      ok('index: MEMORY.md $n line(s) (cap 100)');
    } else {
      fail('index: MEMORY.md is $n lines (cap 100) — consolidate, don\'t grow');
    }
  }

  // ---- 2. facts parse as [{fact, source, ts}] ----
  final factsDir = Directory('${mem.path}/facts');
  var factsCount = 0;
  if (factsDir.existsSync()) {
    for (final f in factsDir.listSync()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      factsCount++;
      try {
        final data = jsonDecode(f.readAsStringSync());
        if (data is! List) {
          fail('facts: ${f.uri.pathSegments.last} does not parse as an array of {fact, source, ts}');
          continue;
        }
        bool valid = data.every((e) =>
            e is Map &&
            e['fact'] is String &&
            e['source'] is String &&
            e['ts'] is String);
        if (!valid) {
          fail('facts: ${f.uri.pathSegments.last} does not parse as an array of {fact, source, ts}');
        }
      } catch (_) {
        fail('facts: ${f.uri.pathSegments.last} does not parse as an array of {fact, source, ts}');
      }
    }
  }
  if (factsCount == 0) {
    fail('facts: no memory/facts/*.json — durable facts must be recorded, not held in heads');
  } else {
    ok('facts: $factsCount topic file(s) parse');
  }

  // ---- 3. lessons caps ----
  final stagesDir = Directory('${mem.path}/stages');
  var lessonsCount = 0;
  if (stagesDir.existsSync()) {
    for (final f in stagesDir.listSync()) {
      if (f is! File || !f.path.endsWith('.LESSONS.md')) continue;
      lessonsCount++;
      final n = f.readAsLinesSync().length;
      if (n <= 200) {
        ok('lessons: ${f.uri.pathSegments.last} $n line(s) (cap 200)');
      } else {
        fail('lessons: ${f.uri.pathSegments.last} is $n lines (cap 200) — drop the oldest lessons');
      }
    }
  }
  if (lessonsCount == 0) {
    fail('lessons: no memory/stages/*.LESSONS.md — one lesson log per pipeline stage');
  }

  // ---- 4. no forbidden absolute-path prefixes under memory/ (R3) ----
  final prefixesFile = File('$root/config/forbidden_abs_prefixes.txt');
  if (prefixesFile.existsSync()) {
    final prefixes = prefixesFile
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
        .toList();
    var hasHit = false;
    if (mem.existsSync()) {
      for (final entry in mem.listSync(recursive: true)) {
        if (entry is! File) continue;
        final content = entry.readAsStringSync();
        for (final prefix in prefixes) {
          if (content.contains(prefix)) {
            final rel = entry.path.substring(root.length + 1);
            fail('abspath: $rel contains forbidden prefix "$prefix" (R3)');
            hasHit = true;
          }
        }
      }
    }
    if (!hasHit) ok('abspath: no forbidden absolute-path prefixes under memory/');
  } else {
    ok('abspath: no config/forbidden_abs_prefixes.txt — check skipped');
  }

  if (fails > 0) {
    return GateResult.fail('memory: FAIL ($fails check(s))', details);
  }
  return GateResult.ok(
    'memory: PASS — memory/ is gate-clean (index <=100, facts parse, lessons <=200, no absolute paths).',
    details,
  );
}
