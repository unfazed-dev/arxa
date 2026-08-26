import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Exact-match response cache for the LLM gateway, per
/// `docs/research/agent-memory-and-caching.md`: keyed on
/// `(stage, model, prompt hash)`, JSONL-class local storage, NO semantic
/// cache (near-duplicate app specs would false-positive).
///
/// Entries are individual JSON files under
/// `<repoRoot>/pipeline/state/memory/cache/<hex key>.json` with the shape
/// `{response, model, stage, ts, ttl_seconds}` — one file per entry so a
/// corrupt entry can only kill itself, never its neighbours.
///
/// All reads are fail-silent: expired, missing, or corrupt entries return
/// null and never throw — a cache must never take the pipeline down.
class ResponseCache {
  ResponseCache({
    required this.repoRoot,
    this.ttl = const Duration(hours: 24),
    this.maxEntries = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Repository root; the cache lives in `pipeline/state/memory/cache/`.
  final String repoRoot;

  /// Default time-to-live for entries written without an explicit TTL.
  final Duration ttl;

  /// Maximum number of entries kept; oldest-ts eviction past this cap.
  final int maxEntries;

  final DateTime Function() _clock;

  /// Where the Anthropic `cache_control` breakpoint belongs in an assembled
  /// prompt: between the static prefix (system + stage instructions +
  /// lessons) and the variable suffix. Provider-side caching reads
  /// everything above this marker at ~0.1x input cost; [assemblePrompt]
  /// only enforces the order discipline — the gateway sets the actual
  /// breakpoint on the final block of the prefix region.
  static const cacheBreakpointMarker = '--- arxa cache breakpoint ---';

  Directory get _dir =>
      Directory(p.join(repoRoot, 'pipeline', 'state', 'memory', 'cache'));

  /// FNV-1a 64-bit over the UTF-8 bytes of `stage|model|prompt`.
  ///
  /// kimitail: non-crypto hash is fine for cache keys — worst case of a
  /// collision is a wrong cached response, not a breach. Swap for sha256
  /// (crypto package) if collision attacks ever matter.
  static String cacheKey(String stage, String model, String prompt) {
    var hash = 0xcbf29ce484222325; // FNV offset basis
    const prime = 0x100000001b3; // FNV prime
    for (final byte in utf8.encode('$stage|$model|$prompt')) {
      hash ^= byte;
      hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// The cached response for `(stage, model, prompt)`, or null when the
  /// entry is missing, expired, or unreadable.
  String? get(String stage, String model, String prompt) {
    final file = File(p.join(_dir.path, '${cacheKey(stage, model, prompt)}.json'));
    try {
      if (!file.existsSync()) return null;
      final entry = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final ts = DateTime.fromMillisecondsSinceEpoch(entry['ts'] as int);
      final ttlSeconds = (entry['ttl_seconds'] as num?) ?? ttl.inSeconds;
      if (_clock().difference(ts).inSeconds >= ttlSeconds) {
        file.deleteSync();
        return null;
      }
      return entry['response'] as String;
    } catch (_) {
      return null; // corrupt entry — treat as a miss, never throw
    }
  }

  /// Stores [response] under `(stage, model, prompt)` with an optional
  /// per-entry [ttlSeconds] overriding the cache default.
  void put(String stage, String model, String prompt, String response,
      {int? ttlSeconds}) {
    _dir.createSync(recursive: true);
    final entry = {
      'response': response,
      'model': model,
      'stage': stage,
      'ts': _clock().millisecondsSinceEpoch,
      'ttl_seconds': ttlSeconds ?? ttl.inSeconds,
    };
    File(p.join(_dir.path, '${cacheKey(stage, model, prompt)}.json'))
        .writeAsStringSync(jsonEncode(entry));
    _evict();
  }

  /// Drops oldest-ts entries once past [maxEntries].
  ///
  /// kimitail: full directory scan + parse on every put past the cap —
  /// O(n log n) at ~500 tiny files, runs only when over the cap. Swap for
  /// a side-car index file if profiling ever shows it.
  void _evict() {
    final files = _dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (files.length <= maxEntries) return;
    int tsOf(File f) {
      try {
        return (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['ts']
                as int? ??
            0;
      } catch (_) {
        return 0; // corrupt sorts oldest — first out the door
      }
    }

    files.sort((a, b) => tsOf(a).compareTo(tsOf(b)));
    for (final f in files.take(files.length - maxEntries)) {
      f.deleteSync();
    }
  }

  /// Assembles a stage prompt in cache-first order: static prefix first,
  /// lessons (stable across runs of the same stage) inside the prefix
  /// region, variable spec LAST. Everything above [cacheBreakpointMarker]
  /// is the provider-cacheable prefix; the marker documents where the
  /// Anthropic `cache_control` breakpoint goes when the gateway translates
  /// this string into API blocks. Run-varying content must NEVER appear
  /// above the marker — it would pay a full cache write on every call.
  static String assemblePrompt({
    required String staticPrefix,
    String? lessons,
    required String variableSpec,
  }) {
    final buffer = StringBuffer(staticPrefix.trimRight());
    if (lessons != null && lessons.trim().isNotEmpty) {
      buffer
        ..write('\n\n')
        ..write(lessons.trim());
    }
    buffer
      ..write('\n\n')
      ..writeln(cacheBreakpointMarker)
      ..write('\n')
      ..write(variableSpec.trim());
    return buffer.toString();
  }
}
