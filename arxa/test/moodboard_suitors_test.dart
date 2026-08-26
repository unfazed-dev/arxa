// The direction audition (suitors) — the second human gate between the
// reference selection and the design commission.
//
// Every assertion here is written to FAIL if the behaviour it names is
// removed, in the house style of intake_artifacts_test.dart. The three
// discriminating setups:
//   * the grandfather group — the energize-shaped LEGACY record (locked
//     scores, no evidence, no suitors) must stay green; if the new law ever
//     applied retroactively this group goes red and every recorded project
//     before the audition lands is invalidated;
//   * the locked-proof group — the SAME arithmetic that passes a legacy
//     record must fail a new-style one missing evidence: the law rides the
//     suitors marker, not the score;
//   * the emitter group — suitors/suitorChoice written into answers.json
//     must survive emitMoodboard; an emitter that dropped them would
//     silently rewind the pipeline while the answers file claimed an
//     audition.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/commission.dart';
import 'package:arxa/intake_artifacts.dart';
import 'package:arxa/moodboard_check.dart';
import 'package:test/test.dart';

Map<String, dynamic> _criterion(String id, num weight, {bool locked = false}) =>
    <String, dynamic>{'id': id, 'weight': weight, if (locked) 'locked': true};

Map<String, dynamic> _ref(String name, Map<String, dynamic> scores,
        {bool selected = false,
        double? total,
        List<Map<String, dynamic>>? evidence}) =>
    <String, dynamic>{
      'name': name,
      'url': 'https://example.com/',
      'provenance': 'inferred',
      'scores': scores,
      'total': ?total,
      if (selected) 'selected': true,
      'evidence': ?evidence,
    };

Map<String, dynamic> _suitor(String id,
        {String provenance = 'judged',
        List<String>? leads,
        List<Map<String, dynamic>>? evidence}) =>
    <String, dynamic>{
      'id': id,
      'name': 'direction $id',
      'spread': 'owns the register the others do not',
      'leads': leads ?? const ['main/Polestar'],
      'tokens': <String, dynamic>{
        'palette': 'warm white / deep green',
        'motion': 'scroll-scrubbed canvas',
      },
      'provenance': provenance,
      'evidence': ?evidence,
    };

/// The energize-shaped record as the law of its day knew it: approved,
/// locked animated-3d fed by a selected 4, no evidence anywhere, no suitors.
Map<String, dynamic> _legacyRecord() => <String, dynamic>{
      'criteria': [
        _criterion('animated-3d', 3, locked: true),
        _criterion('premium', 1),
      ],
      'selectionStatus': 'approved',
      'boards': [
        {
          'id': 'main',
          'references': [
            _ref('Polestar', {'animated-3d': 4, 'premium': 5},
                selected: true, total: 4.25),
            _ref('Club Car', {'animated-3d': 2, 'premium': 3}, total: 2.25),
          ],
        },
      ],
    };

Map<String, dynamic> _newStyleRecord(
    {List<Map<String, dynamic>>? suitors, Map<String, dynamic>? choice}) {
  final rec = _legacyRecord();
  // The locked 4 must now be FED WITH PROOF: evidence citing animated-3d.
  final board = (rec['boards'] as List).first as Map<String, dynamic>;
  final refs = board['references'] as List;
  refs[0] = _ref('Polestar', {'animated-3d': 4, 'premium': 5},
      selected: true,
      total: 4.25,
      evidence: [
        {
          'kind': 'motion',
          'criterion': 'animated-3d',
          'file': 'evidence/polestar__two-settles.png',
        }
      ]);
  rec['suitors'] = suitors ??
      [
        _suitor('A'),
        _suitor('B'),
        _suitor('C', provenance: 'measured', evidence: [
          {'kind': 'tokens', 'file': 'evidence/suitor-c__tokens.json'},
        ]),
      ];
  if (choice != null) rec['suitorChoice'] = choice;
  return rec;
}

void main() {
  group('grandfather — the legacy record stays green under the old law', () {
    test('energize-shaped approved record with no suitors passes', () {
      expect(checkMoodboardRecord(_legacyRecord()), isEmpty);
    });

    test('legacy record is green even against a moodboardDir with no files',
        () {
      expect(
        checkMoodboardRecord(_legacyRecord(),
            moodboardDir: '${Directory.systemTemp.path}/nowhere'),
        isEmpty,
      );
    });
  });

  group('suitors — the audition shape', () {
    test('a valid audition with a choice is green (evidence on disk)', () {
      final dir = Directory.systemTemp.createTempSync('arxa_suitors');
      Directory('${dir.path}/moodboard/evidence').createSync(recursive: true);
      File('${dir.path}/moodboard/evidence/polestar__two-settles.png')
          .writeAsStringSync('png');
      File('${dir.path}/moodboard/evidence/suitor-c__tokens.json')
          .writeAsStringSync('{}');
      final rec = _newStyleRecord(choice: {
        'primary': 'B',
        'remix': [
          {'attribute': 'motion', 'from': 'C'},
        ],
      });
      expect(
        checkMoodboardRecord(rec, moodboardDir: '${dir.path}/moodboard'),
        isEmpty,
      );
      dir.deleteSync(recursive: true);
    });

    test('two suitors fail — the audition is exactly three', () {
      final rec = _newStyleRecord(suitors: [_suitor('A'), _suitor('B')]);
      final failures = checkMoodboardRecord(rec);
      expect(failures.any((f) => f.contains('exactly 3')), isTrue);
    });

    test('ids outside A/B/C fail', () {
      final rec = _newStyleRecord(
          suitors: [_suitor('X'), _suitor('Y'), _suitor('Z')]);
      final failures = checkMoodboardRecord(rec);
      expect(failures.any((f) => f.contains('exactly A, B, C')), isTrue);
    });

    test('a lead that is not a SELECTED reference fails', () {
      final rec = _newStyleRecord(suitors: [
        _suitor('A', leads: ['main/Club Car']),
        _suitor('B'),
        _suitor('C'),
      ]);
      final failures = checkMoodboardRecord(rec);
      expect(
        failures.any((f) =>
            f.contains('main/Club Car') && f.contains('not a selected reference')),
        isTrue,
      );
    });

    test('provenance measured without evidence fails; unknown provenance fails',
        () {
      final noEvidence = _newStyleRecord(suitors: [
        _suitor('A', provenance: 'measured'),
        _suitor('B'),
        _suitor('C'),
      ]);
      expect(
        checkMoodboardRecord(noEvidence)
            .any((f) => f.contains('measured but no evidence')),
        isTrue,
      );
      final remembered = _newStyleRecord(suitors: [
        _suitor('A', provenance: 'remembered'),
        _suitor('B'),
        _suitor('C'),
      ]);
      expect(
        checkMoodboardRecord(remembered)
            .any((f) => f.contains('measured|judged')),
        isTrue,
      );
    });
  });

  group('suitorChoice — the human pick', () {
    test('choice without suitors fails (the unauditioned synthesis)', () {
      final rec = _legacyRecord()
        ..['suitorChoice'] = {'primary': 'A'};
      expect(
        checkMoodboardRecord(rec).any((f) => f.contains('no suitors recorded')),
        isTrue,
      );
    });

    test('choice before selection approval fails (gate ordering)', () {
      final rec = _newStyleRecord(choice: {'primary': 'B'})
        ..['selectionStatus'] = 'pending';
      expect(
        checkMoodboardRecord(rec)
            .any((f) => f.contains('comes AFTER the reference selection gate')),
        isTrue,
      );
    });

    test('primary outside the audition fails', () {
      final rec = _newStyleRecord(choice: {'primary': 'D'});
      expect(
        checkMoodboardRecord(rec)
            .any((f) => f.contains('not one of the auditioned suitors')),
        isTrue,
      );
    });

    test('remix attribute outside the closed vocabulary fails', () {
      final rec = _newStyleRecord(choice: {
        'primary': 'B',
        'remix': [
          {'attribute': 'vibe', 'from': 'A'},
        ],
      });
      expect(
        checkMoodboardRecord(rec).any((f) => f.contains('closed vocabulary')),
        isTrue,
      );
    });

    test('remix from the primary itself fails', () {
      final rec = _newStyleRecord(choice: {
        'primary': 'B',
        'remix': [
          {'attribute': 'motion', 'from': 'B'},
        ],
      });
      expect(
        checkMoodboardRecord(rec)
            .any((f) => f.contains('amends the primary with a sibling')),
        isTrue,
      );
    });
  });

  group('lockedProof — a locked 3+ needs lens evidence on new-style records',
      () {
    test('the legacy-passing arithmetic fails without evidence', () {
      final rec = _newStyleRecord();
      final board = (rec['boards'] as List).first as Map<String, dynamic>;
      (board['references'] as List)[0] =
          _ref('Polestar', {'animated-3d': 4, 'premium': 5},
              selected: true, total: 4.25);
      expect(
        checkMoodboardRecord(rec).any((f) =>
            f.contains('animated-3d=4') && f.contains('no lens evidence')),
        isTrue,
      );
    });

    test('evidence citing the criterion but missing on disk fails', () {
      final rec = _newStyleRecord();
      final failures = checkMoodboardRecord(rec,
          moodboardDir: '${Directory.systemTemp.path}/nowhere');
      expect(
        failures.any((f) =>
            f.contains('polestar__two-settles.png') &&
            f.contains('does not resolve')),
        isTrue,
      );
    });

    test('shape-only mode (moodboardDir null) skips file resolution', () {
      final rec = _newStyleRecord(choice: {'primary': 'B'});
      expect(checkMoodboardRecord(rec), isEmpty);
    });
  });

  group('emitMoodboard — the audition survives the emitter', () {
    test('suitors and suitorChoice carry through verbatim', () {
      final answers = <String, dynamic>{
        'moodboard': _newStyleRecord(choice: {
          'primary': 'B',
          'remix': [
            {'attribute': 'motion', 'from': 'C'},
          ],
        }),
      };
      final out = emitMoodboard(answers);
      expect(out.containsKey('suitors'), isTrue,
          reason: 'an emitter that drops suitors silently rewinds the '
              'pipeline to the pre-audition law');
      expect((out['suitorChoice'] as Map)['primary'], 'B');
      expect(out.containsKey('selectionStatus'), isTrue);
    });

    test('no suitors in answers emits no suitors (legacy stays legacy)', () {
      final out =
          emitMoodboard(<String, dynamic>{'moodboard': _legacyRecord()});
      expect(out.containsKey('suitors'), isFalse);
      expect(out.containsKey('suitorChoice'), isFalse);
    });
  });

  group('commission — the compiler gates and renders the audition', () {
    late Directory appDir;

    setUp(() {
      appDir = Directory.systemTemp.createTempSync('arxa_commission');
      Directory('${appDir.path}/intake').createSync(recursive: true);
      Directory('${appDir.path}/moodboard/evidence')
          .createSync(recursive: true);
      File('${appDir.path}/moodboard/evidence/polestar__two-settles.png')
          .writeAsStringSync('png');
      File('${appDir.path}/moodboard/evidence/suitor-c__tokens.json')
          .writeAsStringSync('{}');
    });

    tearDown(() {
      appDir.deleteSync(recursive: true);
    });

    void writeMoodboard(Map<String, dynamic> rec) {
      File('${appDir.path}/intake/moodboard.json')
          .writeAsStringSync(jsonEncode(rec));
    }

    test('suitors without a choice: refused, no mandate written', () {
      writeMoodboard(_newStyleRecord());
      final code = commissionMain([appDir.path]);
      expect(code, 2);
      expect(File('${appDir.path}/design/commission.md').existsSync(), isFalse,
          reason: 'a refused mandate must not half-exist on disk');
    });

    test('chosen suitor renders as the spine with remix and declined lines',
        () {
      writeMoodboard(_newStyleRecord(choice: {
        'primary': 'B',
        'remix': [
          {'attribute': 'motion', 'from': 'C'},
        ],
      }));
      final code = commissionMain([appDir.path]);
      expect(code, 0);
      final md = File('${appDir.path}/design/commission.md')
          .readAsStringSync();
      expect(md.contains('The chosen direction — suitor B: direction B'),
          isTrue);
      expect(md.contains('remixed motion <- suitor C'), isTrue);
      expect(md.contains('Auditioned and declined'), isTrue);
      expect(md.contains('suitor A — direction A'), isTrue);
      // The chosen direction is the spine; the raw per-reference tokens stay.
      expect(md.contains('## Style tokens — extracted from the selected'),
          isTrue);
    });

    test('legacy record still compiles with its tokenSynthesis spine', () {
      final rec = _legacyRecord()
        ..['tokenSynthesis'] = {
          'palette': 'warm white',
          'motion': 'scroll-scrub',
        };
      writeMoodboard(rec);
      expect(commissionMain([appDir.path]), 0);
      final md = File('${appDir.path}/design/commission.md')
          .readAsStringSync();
      expect(md.contains('Synthesis — the cross-pollinated starting direction'),
          isTrue);
      expect(md.contains('The chosen direction'), isFalse);
    });
  });
}
