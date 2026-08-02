// Chrome launch failures must carry Chrome's own account of the failure
// (finding 16). `_readWsUrl` matched `ws://` and dropped every other stderr
// line, so a worker that never printed a DevTools URL surfaced as a bare
// `TimeoutException after 0:00:30` — the intermittent `design_server_test`
// boot failure was undiagnosable by construction, and no amount of re-running
// would have said why.
//
// StderrTail owns both halves that can silently rot: the cap (an unbounded
// buffer turns one failure into a megabyte of log) and the message (an empty
// note must say Chrome was silent, not look like the old dropped-it-all
// behaviour). Neither announces itself when broken, hence this test.

import 'package:appboxd/design_server/worker.dart';
import 'package:test/test.dart';

void main() {
  group('StderrTail', () {
    test('keeps the LAST max lines, not the first', () {
      final t = StderrTail(max: 3);
      for (var i = 1; i <= 10; i++) {
        t.add('line$i');
      }
      expect(t.lines, ['line8', 'line9', 'line10']);
    });

    test('note carries every retained line', () {
      final t = StderrTail()
        ..add('FATAL:cannot create user data dir')
        ..add('trailing diagnostic line');
      expect(t.note, contains('cannot create user data dir'));
      expect(t.note, contains('trailing diagnostic line'));
      expect(t.note, contains('2 line(s)'));
    });

    test('silence is reported as silence, not as an absent note', () {
      // The distinction matters: "Chrome said nothing" and "we dropped what
      // Chrome said" are different diagnoses.
      final note = StderrTail().note;
      expect(note, contains('wrote nothing'));
      expect(note.trim(), isNotEmpty);
    });

    test('holds nothing back below the cap', () {
      final t = StderrTail(max: 20)..add('only');
      expect(t.lines, ['only']);
      expect(t.note, contains('1 line(s)'));
    });
  });
}
