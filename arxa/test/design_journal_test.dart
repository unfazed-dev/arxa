import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_draft.dart';
import 'package:arxa/design_journal.dart';
import 'package:test/test.dart';

DesignJournal j() => DesignJournal(artifact: 'hello-hda');

void main() {
  group('record / coalesce / truncate', () {
    test('each new gesture appends a step and advances the cursor', () {
      final journal = j();
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      journal.record(
          gesture: 'g2',
          scope: JournalScope.token,
          key: '--brand',
          before: '#f00',
          after: '#0f0');
      expect(journal.steps.length, 2);
      expect(journal.undoDepth, 2);
      expect(journal.redoDepth, 0);
    });

    test('same gesture + key coalesces, keeping first before / last after',
        () {
      final journal = j();
      for (final v in ['N', 'Ne', 'New']) {
        journal.record(
            gesture: 'typing-1',
            scope: JournalScope.patch,
            key: 'el:home-e1',
            before: null,
            after: {'text': v});
      }
      expect(journal.steps.length, 1);
      expect(journal.steps.single.before, isNull);
      expect((journal.steps.single.after as Map)['text'], 'New');
    });

    test('same gesture but different key does NOT coalesce', () {
      final journal = j();
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--ink',
          before: null,
          after: '#000');
      expect(journal.steps.length, 2);
    });

    test('recording after undo truncates the redo tail (linear history)', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda');
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      journal.record(
          gesture: 'g2',
          scope: JournalScope.token,
          key: '--brand',
          before: '#f00',
          after: '#0f0');
      journal.undo(overlay);
      expect(journal.redoDepth, 1);
      journal.record(
          gesture: 'g3',
          scope: JournalScope.token,
          key: '--ink',
          before: null,
          after: '#000');
      expect(journal.redoDepth, 0);
      expect(journal.steps.length, 2);
      expect(journal.steps.last.key, '--ink');
    });

    test('over JournalCaps.steps the oldest step falls off', () {
      final journal = j();
      for (var i = 0; i < JournalCaps.steps + 5; i++) {
        journal.record(
            gesture: 'g$i',
            scope: JournalScope.token,
            key: '--brand',
            before: '#$i',
            after: '#${i + 1}');
      }
      expect(journal.steps.length, JournalCaps.steps);
      expect(journal.steps.first.gesture, 'g5');
      expect(journal.undoDepth, JournalCaps.steps);
    });
  });

  group('undo / redo application', () {
    test('token edit: undo removes, redo restores', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda');
      overlay.tokens['--brand'] = '#f00';
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      expect(journal.undo(overlay), isNotNull);
      expect(overlay.tokens.containsKey('--brand'), isFalse);
      expect(journal.redo(overlay), isNotNull);
      expect(overlay.tokens['--brand'], '#f00');
    });

    test('patch edit: undo restores the prior patch snapshot', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda', patches: {
        'el:home-e1': DraftPatch(style: {'color': 'blue'}),
      });
      journal.record(
          gesture: 'g1',
          scope: JournalScope.patch,
          key: 'el:home-e1',
          before: {
            'style': {'color': 'red'}
          },
          after: {
            'style': {'color': 'blue'}
          });
      journal.undo(overlay);
      expect(overlay.patches['el:home-e1']!.style['color'], 'red');
      journal.redo(overlay);
      expect(overlay.patches['el:home-e1']!.style['color'], 'blue');
    });

    test('undoing a patch created from nothing removes it entirely', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda', patches: {
        'el:home-e1': DraftPatch(text: 'New'),
      });
      journal.record(
          gesture: 'g1',
          scope: JournalScope.patch,
          key: 'el:home-e1',
          before: null,
          after: {'text': 'New'});
      journal.undo(overlay);
      expect(overlay.patches.containsKey('el:home-e1'), isFalse);
    });

    test('undo at the barrier and redo with no tail return null', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda');
      expect(journal.undo(overlay), isNull);
      expect(journal.redo(overlay), isNull);
    });
  });

  group('json', () {
    test('roundtrip preserves steps and cursor', () {
      final journal = j();
      final overlay = DraftOverlay(artifact: 'hello-hda');
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      journal.record(
          gesture: 'g2',
          scope: JournalScope.patch,
          key: 'el:home-e1',
          before: null,
          after: {'text': 'New'});
      journal.undo(overlay);
      final back = DesignJournal.fromJson(
          jsonDecode(jsonEncode(journal.toJson())),
          artifact: 'hello-hda');
      expect(back.steps.length, 2);
      expect(back.cursor, 1);
      expect(back.undoDepth, 1);
      expect(back.redoDepth, 1);
      expect(back.steps.last.scope, JournalScope.patch);
    });

    test('cursor out of range is refused', () {
      expect(
          () => DesignJournal.fromJson({'v': 1, 'cursor': 3, 'steps': []},
              artifact: 'x'),
          throwsFormatException);
    });

    test('bad scope, bad token value, and bad patch snapshot are refused', () {
      JournalStep parse(Map<String, Object?> m) => JournalStep.fromJson(m, 0);
      expect(
          () => parse({'gesture': 'g', 'scope': 'git', 'key': 'k'}),
          throwsFormatException);
      expect(
          () => parse({
                'gesture': 'g',
                'scope': 'token',
                'key': '--x',
                'after': '<script>'
              }),
          throwsFormatException);
      expect(
          () => parse({
                'gesture': 'g',
                'scope': 'patch',
                'key': 'el:e1',
                'after': {'nth': -4}
              }),
          throwsFormatException);
    });
  });

  group('JournalFileStore', () {
    late Directory home;
    setUp(() =>
        home = Directory.systemTemp.createTempSync('journal-store-test'));
    tearDown(() => home.deleteSync(recursive: true));

    test('save / load / clear roundtrip', () async {
      final s = JournalFileStore(
          artifactDir: '/tmp/checkouts/hello-hda', home: home.path);
      final journal = DesignJournal(artifact: s.artifact);
      journal.record(
          gesture: 'g1',
          scope: JournalScope.token,
          key: '--brand',
          before: null,
          after: '#f00');
      await s.save(journal);
      final back = await s.load();
      expect(back.undoDepth, 1);
      await s.clear();
      expect((await s.load()).steps, isEmpty);
      expect(await s.file.exists(), isFalse);
    });

    test('distinct artifact paths get distinct files', () {
      final a = JournalFileStore(
          artifactDir: '/tmp/a/hello-hda', home: home.path);
      final b = JournalFileStore(
          artifactDir: '/tmp/b/hello-hda', home: home.path);
      expect(a.file.path, isNot(b.file.path));
    });

    test('an unreadable journal starts blank instead of breaking the serve',
        () async {
      final s = JournalFileStore(
          artifactDir: '/tmp/checkouts/hello-hda', home: home.path);
      s.file.parent.createSync(recursive: true);
      s.file.writeAsStringSync('{not json');
      final back = await s.load();
      expect(back.steps, isEmpty);
      expect(back.undoDepth, 0);
    });
  });
}
