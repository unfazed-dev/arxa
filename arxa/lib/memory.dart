import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Well-known event kinds. `kind` is a plain [String], not a closed enum —
/// new writers may add kinds without touching this file.
abstract final class MemoryKinds {
  static const gateRun = 'gate_run';
  static const stageRun = 'stage_run';
  static const llmRequest = 'llm_request';
  static const deploy = 'deploy';
  static const note = 'note';
}

/// One raw memory event (plan M1: deterministic writers append raw events
/// always; consolidation happens elsewhere).
class MemoryEvent {
  MemoryEvent({
    DateTime? ts,
    required this.kind,
    required this.actor,
    Map<String, dynamic>? payload,
  })  : ts = ts ?? DateTime.now().toUtc(),
        payload = payload ?? const {};

  factory MemoryEvent.fromJson(Map<String, dynamic> json) => MemoryEvent(
        ts: DateTime.parse(json['ts'] as String),
        kind: json['kind'] as String,
        actor: json['actor'] as String,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
      );

  final DateTime ts;
  final String kind;
  final String actor;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'ts': ts.toUtc().toIso8601String(),
        'kind': kind,
        'actor': actor,
        'payload': payload,
      };

  String toLine() => jsonEncode(toJson());
}

/// The events returned by [EventLog.read], plus how many lines were skipped
/// as corrupt. A corrupt line is data damage, not a logic error — the reader
/// never throws on it.
class MemoryReadResult {
  MemoryReadResult(this.events, this.corruptLines);

  /// Matching events, oldest first — the newest event is last.
  final List<MemoryEvent> events;
  final int corruptLines;
}

/// Append-only JSONL event store under `<stateRoot>/memory/`.
///
/// The active file is `events.jsonl`; when it grows past [maxBytes] it is
/// rotated to `events.<yyyyMMdd-HHmmss>.jsonl` and appends continue in a
/// fresh active file. Rotated files are never rewritten, and reads cover the
/// rotated files (oldest first) plus the active one.
class EventLog {
  EventLog(this.stateRoot, {this.maxBytes = defaultMaxBytes});

  /// Directory standing in for `pipeline/state` (a temp dir in tests).
  final String stateRoot;

  static const defaultMaxBytes = 50 * 1024 * 1024; // ~50MB

  final int maxBytes;

  Directory get _memoryDir => Directory('$stateRoot/memory');
  File get _activeFile => File('${_memoryDir.path}/events.jsonl');

  /// Appends [event] as one JSONL line, rotating the active file first when
  /// it has already grown past [maxBytes].
  Future<void> append(MemoryEvent event) async {
    _memoryDir.createSync(recursive: true);
    final file = _activeFile;
    if (file.existsSync() && file.lengthSync() >= maxBytes) {
      _rotate(file);
    }
    await file.writeAsString('${event.toLine()}\n',
        mode: FileMode.append, flush: true);
  }

  // kimitail: one process appends, so rotate-then-append needs no lock; if
  // arxa ever shards writers, move to a single writer isolate with a queue.
  void _rotate(File active) {
    final now = DateTime.now().toUtc();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    var target = File('${_memoryDir.path}/events.$stamp.jsonl');
    // Two rotations inside the same second must not clobber each other.
    for (var i = 1; target.existsSync(); i++) {
      target = File('${_memoryDir.path}/events.$stamp-$i.jsonl');
    }
    active.renameSync(target.path);
  }

  /// Streams every matching event over rotated files (oldest first) plus the
  /// active file. Corrupt lines are skipped and counted. When more than
  /// [limit] events match, the *most recent* [limit] are returned.
  Future<MemoryReadResult> read({
    String? kind,
    DateTime? since,
    int limit = 1000,
  }) async {
    final events = <MemoryEvent>[];
    var corrupt = 0;
    await for (final line in _lines()) {
      MemoryEvent event;
      try {
        event = MemoryEvent.fromJson(
            (jsonDecode(line) as Map).cast<String, dynamic>());
      } on FormatException {
        corrupt++;
        continue;
      }
      if (kind != null && event.kind != kind) continue;
      if (since != null && event.ts.isBefore(since)) continue;
      events.add(event);
    }
    final start = events.length > limit ? events.length - limit : 0;
    return MemoryReadResult(events.sublist(start), corrupt);
  }

  /// Total events per kind across all files (corrupt lines skipped).
  Future<Map<String, int>> countByKind() async {
    final counts = <String, int>{};
    await for (final line in _lines()) {
      try {
        final json = (jsonDecode(line) as Map).cast<String, dynamic>();
        final kind = json['kind'];
        if (kind is String) counts[kind] = (counts[kind] ?? 0) + 1;
      } on FormatException {
        continue;
      }
    }
    return counts;
  }

  /// Lines of all event files, rotated ones (name-sorted = chronological)
  /// first, the active file last.
  Stream<String> _lines() async* {
    final dir = _memoryDir;
    if (!dir.existsSync()) return;
    final rotated = dir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.split('/').last.startsWith('events.') &&
            f.path != _activeFile.path)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final files = [...rotated, if (_activeFile.existsSync()) _activeFile];
    for (final file in files) {
      yield* file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty);
    }
  }
}
