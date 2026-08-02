// decision_log_test — proves the ADR pipeline records only choices that were
// actually made, and records them for the reason that actually fired.
//
// The three properties under test are the ones that make the feature honest
// rather than merely present:
//
//   1. a project where the pipeline really chose something produces an ADR
//      naming that choice, with a reason traceable to the code path;
//   2. a project where the pipeline chose NOTHING produces ZERO ADRs — and
//      this is proved with the SAME collector that produces ADRs in (1), so it
//      cannot pass by being hard-wired to return `[]`;
//   3. two emissions of the same project are byte-identical (no clock, no set
//      iteration order leaking into the output).

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/decision_log.dart';
import 'package:appboxd/intake.dart';
import 'package:appboxd/prd_adr.dart';
import 'package:appboxd/project.dart';
import 'package:test/test.dart';

Map<String, dynamic> _node(Object? v, [String prov = 'client']) =>
    <String, dynamic>{'value': v, 'provenance': prov};

/// Base answers with only the four required fields, so each fixture below
/// differs ONLY in the surfaces/flows that drive derivation.
Map<String, dynamic> _base() => <String, dynamic>{
      'product': _node('Probe'),
      'audience': _node('Testers'),
      'appMustDo': _node(['exist']),
      'targets': _node(['ios']),
    };

/// A project where the pipeline genuinely chooses: no `flows` group (so the
/// draft-flow decomposition fires), a collection-word id, a form-word id, and
/// a surface whose ONLY error signal is `requiresAuth` (the right disjunct).
Map<String, dynamic> _answersWithChoices() => _base()
  ..['surfaces'] = [
    {'id': 'home.feed', 'label': 'Feed', 'shell': 'home', 'provenance': 'client'},
    {'id': 'home.detail', 'label': 'Detail', 'shell': 'home', 'provenance': 'client'},
    {'id': 'auth.login', 'label': 'Login', 'shell': 'auth', 'provenance': 'client'},
    {
      'id': 'auth.verify',
      'label': 'Verify',
      'shell': 'auth',
      'provenance': 'client',
      'requiresAuth': true,
    },
  ];

/// A project where the pipeline chooses NOTHING: every surface id avoids both
/// word lists, no `requiresAuth`, and flows are DECLARED with a non-mutation
/// trigger — so derive-drafts, derive-states and derive-feedback all sit out.
Map<String, dynamic> _answersWithoutChoices() => _base()
  ..['surfaces'] = [
    {'id': 'main.overview', 'label': 'Overview', 'shell': 'main', 'provenance': 'client'},
    {'id': 'main.chart', 'label': 'Chart', 'shell': 'main', 'provenance': 'client'},
  ]
  ..['flows'] = [
    {
      'id': 'flow-main',
      'name': 'Main journey',
      'provenance': 'client',
      'edges': [
        {'from': 'main.overview', 'to': 'main.chart', 'trigger': 'continue'},
      ],
    },
  ];

/// A project whose only choice is a derived toast: flows are DECLARED (so no
/// decomposition decision) and one trigger names a mutation.
Map<String, dynamic> _answersWithMutation() => _base()
  ..['surfaces'] = [
    {'id': 'main.overview', 'label': 'Overview', 'shell': 'main', 'provenance': 'client'},
    {'id': 'main.chart', 'label': 'Chart', 'shell': 'main', 'provenance': 'client'},
  ]
  ..['flows'] = [
    {
      'id': 'flow-main',
      'name': 'Main journey',
      'provenance': 'client',
      'edges': [
        {'from': 'main.overview', 'to': 'main.chart', 'trigger': 'Save report'},
      ],
    },
  ];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('appbox-decision-log-');
    appboxHomeOverride = tmp.path;
  });

  tearDown(() {
    appboxHomeOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('collectDecisions — a real choice is recorded', () {
    test('derived draft flows are recorded with the rule that fired', () {
      final ds = collectDecisions(_answersWithChoices());
      final flow = ds.singleWhere((d) => d.id == 'flow-decomposition');

      // The choice itself, naming what was actually produced.
      expect(flow.decision, contains('flow-home'));
      expect(flow.decision, contains('flow-auth'));

      // The reason is the branch condition, not a post-hoc justification.
      expect(flow.because, contains('answers.flows'));
      expect(flow.because, contains('emitFlows'));

      // Nothing was enumerated at that branch, so nothing may be claimed.
      expect(flow.alternatives, isEmpty);

      // It binds the artifact it actually wrote.
      expect(flow.constrains, contains('intake/flows.json'));
    });

    test('collection-word states name the matched word, not the vocabulary', () {
      final ds = collectDecisions(_answersWithChoices());
      final d = ds.singleWhere((x) => x.id == 'surface-states-collection');

      expect(d.decision, contains('home.feed'));
      // Only the SHORT segment is tokenized, so `feed` matched and the shell
      // `home` (also a collection word) never entered the rule.
      expect(d.because, contains('"feed"'));
      expect(d.because, isNot(contains('"home"')));
      // `home.detail` has no collection word — it must not be swept in.
      expect(d.decision, isNot(contains('home.detail')));
      expect(d.alternatives, isEmpty);
    });

    test('the error branch names WHICH disjunct fired for each surface', () {
      final ds = collectDecisions(_answersWithChoices());
      final d = ds.singleWhere((x) => x.id == 'surface-states-error');

      // auth.login fired on the form word; auth.verify fired on requiresAuth.
      // `||` short-circuits, so conflating the two would report a cause that
      // never ran — the exact failure this assertion exists to catch.
      expect(d.because, contains('login'));
      expect(d.because, contains('requiresAuth'));
      expect(d.because, contains('auth.verify'));
      // auth.verify's short segment holds no form word, so it must not be
      // credited to the form-word disjunct.
      expect(
        RegExp(r'auth\.verify[^;]*form word').hasMatch(d.because),
        isFalse,
        reason: 'auth.verify has no form word; only requiresAuth fired',
      );
    });

    test('a mutation trigger records a derived toast', () {
      final ds = collectDecisions(_answersWithMutation());
      final d = ds.singleWhere((x) => x.id == 'edge-feedback');

      expect(d.decision, contains('Save report'));
      expect(d.because, contains('save')); // the matched mutation verb
      expect(d.because, contains('deriveFeedback'));
      expect(d.alternatives, isEmpty);

      // Flows were declared, so the decomposition decision must NOT appear.
      expect(ds.any((x) => x.id == 'flow-decomposition'), isFalse);
    });

    test('emitAdrs renders the collected decisions', () {
      final docs = emitAdrs(adrRecords(collectDecisions(_answersWithChoices())));
      expect(docs, isNotEmpty);
      expect(docs.first.filename, matches(RegExp(r'^0001-[a-z0-9-]+\.md$')));
      expect(docs.first.body, startsWith('# '));
      // No "Alternatives considered" heading may appear: nothing was enumerated.
      for (final d in docs) {
        expect(d.body, isNot(contains('Alternatives considered')));
      }
    });
  });

  group('collectDecisions — no choice means no ADR', () {
    test('a project that chose nothing yields zero decisions and zero ADRs', () {
      final ds = collectDecisions(_answersWithoutChoices());
      expect(ds, isEmpty);
      expect(emitAdrs(adrRecords(ds)), isEmpty);
    });

    test('the SAME collector is non-tautological', () {
      // The guard against a collector hard-wired to `[]`: one call returns
      // records and the other returns none, from the same function.
      expect(collectDecisions(_answersWithChoices()), isNotEmpty);
      expect(collectDecisions(_answersWithoutChoices()), isEmpty);
    });
  });

  group('emit --project writes the log and the ADRs', () {
    test('decisions.json and adr/ appear under intake/, never build/', () {
      final r = IntakeEngine().emit(_answersWithChoices(), project: 'probe');
      expect(r.ok, isTrue, reason: r.errors.join('; '));

      final dir = shellDir('probe', 'intake');
      final log = File('$dir/decisions.json');
      expect(log.existsSync(), isTrue);

      final entries = jsonDecode(log.readAsStringSync()) as List;
      expect(entries, isNotEmpty);
      // The operator-approved shape, verbatim.
      for (final e in entries) {
        expect((e as Map).keys,
            containsAll(['decision', 'because', 'alternatives', 'constrains']));
      }

      final adrs = Directory('$dir/adr')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(adrs, isNotEmpty);
      expect(adrs.first, startsWith('0001-'));

      // The stage trap: nothing may land under build/.
      expect(Directory(shellDir('probe', 'build')).listSync(), isEmpty);
      expect(projectStage('probe'), 'design');
    });

    test('a project with no choices writes an empty log and no ADR files', () {
      final r = IntakeEngine().emit(_answersWithoutChoices(), project: 'quiet');
      expect(r.ok, isTrue, reason: r.errors.join('; '));

      final dir = shellDir('quiet', 'intake');
      expect(jsonDecode(File('$dir/decisions.json').readAsStringSync()), isEmpty);
      final adrDir = Directory('$dir/adr');
      expect(adrDir.existsSync() ? adrDir.listSync() : const [], isEmpty);
    });

    test('two emissions are byte-identical', () {
      IntakeEngine().emit(_answersWithChoices(), project: 'twice');
      final dir = shellDir('twice', 'intake');
      String snapshot() {
        final files = [
          File('$dir/decisions.json'),
          ...Directory('$dir/adr').listSync().whereType<File>(),
        ]..sort((a, b) => a.path.compareTo(b.path));
        return files.map((f) => '${f.path}\n${f.readAsStringSync()}').join('\n');
      }

      final first = snapshot();
      IntakeEngine().emit(_answersWithChoices(), project: 'twice');
      expect(snapshot(), first);
    });

    test('a decision that stops firing removes its stale ADR', () {
      // Positional numbering (`startNumber + i`) means a shrinking record list
      // would otherwise leave `0003-*.md` on disk still asserting a decision
      // nobody made. emit OWNS the adr dir; it does not merge into it.
      IntakeEngine().emit(_answersWithChoices(), project: 'shrink');
      final dir = shellDir('shrink', 'intake');
      final before = Directory('$dir/adr').listSync().length;
      expect(before, greaterThan(1));

      IntakeEngine().emit(_answersWithoutChoices(), project: 'shrink');
      expect(Directory('$dir/adr').listSync(), isEmpty);
    });

    test('a hand-written note in adr/ survives re-emission', () {
      // Only `NNNN-*.md` is emit-owned. Deleting everything in the directory
      // would eat a human's notes, which the clear-then-write must not do.
      IntakeEngine().emit(_answersWithChoices(), project: 'notes');
      final dir = shellDir('notes', 'intake');
      File('$dir/adr/README.md').writeAsStringSync('mine\n');

      IntakeEngine().emit(_answersWithChoices(), project: 'notes');
      expect(File('$dir/adr/README.md').readAsStringSync(), 'mine\n');
    });
  });

  group('the reason cannot drift from the rule', () {
    test('matched-word helpers agree with the derivation they explain', () {
      // If these two ever disagree, an ADR states a reason that did not fire.
      for (final surf in _answersWithChoices()['surfaces'] as List) {
        final s = surf as Map;
        final states = deriveStates(s);
        expect(states.contains('loading'), matchedCollectionWords(s).isNotEmpty);
        expect(
          states.contains('error'),
          matchedFormWords(s).isNotEmpty || s['requiresAuth'] == true,
        );
      }
    });
  });
}
