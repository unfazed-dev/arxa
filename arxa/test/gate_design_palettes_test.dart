/// Mutation tests for the P-gate (P1–P4 + the advisory hex sweep).
///
/// Same shape as w_gate_test.dart: one clean synthetic artifact tree that
/// passes every rule, then per-rule mutations. Each mutation asserts BOTH
/// directions — the mutated rule fires, the others stay silent. The P4
/// engine (checkPaletteTemplate, package:arxa/design_palette_index.dart) is
/// injected in the mutation groups so these tests pin the GATE's plumbing;
/// the indexer's diff semantics belong to design_palette_index_test. The
/// clean-tree and lint-plumbing tests call the gate un-injected, against
/// the real engine — the fixture carries no stylesheets outside the plane,
/// so any faithful --check finds nothing to drift.
library;

import 'dart:io';

import 'package:arxa/design_tools.dart' show LintFinding, designLint;
import 'package:arxa/gate_design_palettes.dart';
import 'package:test/test.dart';

// ══ fixture ═════════════════════════════════════════════════════════════

const _marine = '{"id":"marine","name":"Marine Blue",'
    '"swatch":["#ccdbdc","#9ad1d4","#80ced7","#007ea7","#003249"],'
    '"themeColor":"#007ea7","seeded":true}';
const _iris = '{"id":"c-6f58c9","name":"Lavender Iris",'
    '"swatch":["#bdede0","#bbdbd1","#b6b8d6","#7e78d2","#6f58c9"],'
    '"themeColor":"#7e78d2","seeded":true,'
    '"sheet":"/assets/styles/palettes/palette-c-6f58c9.css"}';

String _manifest(String entries, {String defaultId = 'marine'}) =>
    '{"version":1,"default":"$defaultId","palettes":[$entries]}';

/// A minimal plane-declaring artifact that passes all five rules: the
/// seeded default (base corpus — no sheet, no tokens block) plus one seeded
/// override with its sheet and tokens block. No stylesheets exist outside
/// the plane, so template coverage has nothing to index and the advisory
/// sweep nothing to find. The template declares a (vacuous — no slots)
/// pair contract so P5 treats it as a modern plane, matching what the
/// starter ships since the 2026-09-11 contrast engine.
final _cleanTree = <String, String>{
  'palettes.json': _manifest('$_marine,$_iris'),
  'assets/styles/palettes/_template.json':
      '{"anchors":{},"tokens":[],"rules":[],"pairs":[],"familyPairs":[],"surfaces":{}}',
  'assets/styles/palettes/palette-c-6f58c9.css':
      '/* generated override sheet — do not hand-edit */\n',
  'assets/app/palette.js':
      '// the palette plane runtime: owns data-palette + broadcast\n',
  'ui/styles/common/tokens.css':
      ':root {\n}\n\n[data-palette="c-6f58c9"] {\n}\n',
};

/// Sentinel: a mutation that removes a file from the clean tree.
const _deleted = '\x00deleted\x00';

String _tree(Directory dir, Map<String, String> mutations) {
  final tree = {..._cleanTree, ...mutations};
  for (final e in tree.entries) {
    final f = File('${dir.path}/${e.key}');
    if (e.value == _deleted) {
      if (f.existsSync()) f.deleteSync();
      continue;
    }
    f
      ..createSync(recursive: true)
      ..writeAsStringSync(e.value);
  }
  return dir.path;
}

/// Rule ids present in [findings], e.g. {'P1'}.
Set<String> _rules(List<LintFinding> findings) =>
    findings.map((f) => f.message.split(' ').first).toSet();

/// The P4 seam the mutation groups share: no drift, so only the mutated
/// rule can fire.
List<String> _noDrift(String _) => const <String>[];

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('p_gate_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Assert the mutated tree fires exactly [rule] and nothing else, and that
  /// at least one message names the rule and reads like a fix instruction.
  void expectsOnly(String rule, Map<String, String> mutations,
      {String? messageContains}) {
    final notes = <LintFinding>[];
    final findings = gateDesignPalettes(_tree(tmp, mutations),
        notes: notes, templateCheck: _noDrift);
    expect(_rules(findings), {rule},
        reason: 'expected only $rule; got:\n${findings.join('\n')}');
    if (messageContains != null) {
      expect(findings.map((f) => f.message).join('\n'),
          contains(messageContains));
    }
  }

  group('clean tree', () {
    test('passes P1–P4 against the real P4 engine and sweeps clean', () {
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(_tree(tmp, const {}), notes: notes);
      expect(findings, isEmpty, reason: findings.join('\n'));
      expect(notes, isEmpty, reason: notes.join('\n'));
    });

    test('design lint reports the palette gate clean alongside the others',
        () {
      final r = designLint([_tree(tmp, const {})]);
      expect(r.exitCode, 0, reason: r.stderrLines.join('\n'));
      expect(r.stdoutLines.join('\n'), contains('palette gate clean'));
    });

    test('an artifact without palettes.json declares no plane — vacuous',
        () {
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(
          _tree(tmp, const {'palettes.json': _deleted}),
          notes: notes);
      expect(findings, isEmpty, reason: findings.join('\n'));
      expect(notes, isEmpty, reason: notes.join('\n'));
    });
  });

  group('P1 manifest', () {
    test('invalid JSON fails', () {
      expectsOnly('P1', {'palettes.json': 'not json {'},
          messageContains: 'not valid JSON');
    });

    test('a non-object manifest fails', () {
      expectsOnly('P1', {'palettes.json': '[]'},
          messageContains: 'must be a JSON object');
    });

    test('a manifest without default/palettes fails', () {
      expectsOnly('P1', {'palettes.json': '{"version":1}'},
          messageContains: 'must carry "default"');
    });

    test('a default that resolves to no entry fails', () {
      expectsOnly(
          'P1',
          {'palettes.json': _manifest('$_marine,$_iris', defaultId: 'nope')},
          messageContains: 'default "nope" resolves to no entry');
    });

    test('an entry that is not an object fails', () {
      expectsOnly('P1', {'palettes.json': _manifest('42,$_marine,$_iris')},
          messageContains: 'palettes[0] is not an entry object');
    });

    test('a swatch below 3 fails the 3–7 law', () {
      const short = '{"id":"marine","name":"Marine Blue",'
          '"swatch":["#ccdbdc","#003249"],'
          '"themeColor":"#007ea7","seeded":true}';
      expectsOnly('P1', {'palettes.json': _manifest('$short,$_iris')},
          messageContains: 'P1 3–7 law: palette "marine" declares 2 swatches');
    });

    test('a swatch above 7 fails the 3–7 law', () {
      const wide = '{"id":"marine","name":"Marine Blue",'
          '"swatch":["#ccdbdc","#9ad1d4","#80ced7","#007ea7","#003249",'
          '"#1b3a4b","#5b7a8c","#f2f4f5"],'
          '"themeColor":"#007ea7","seeded":true}';
      expectsOnly('P1', {'palettes.json': _manifest('$wide,$_iris')},
          messageContains: 'P1 3–7 law: palette "marine" declares 8 swatches');
    });

    test('a non-hex swatch fails', () {
      const bad = '{"id":"marine","name":"Marine Blue",'
          '"swatch":["#ccdbdc","#9ad1d4","#80ced7","#007ea7","#zzzzzz"],'
          '"themeColor":"#007ea7","seeded":true}';
      expectsOnly('P1', {'palettes.json': _manifest('$bad,$_iris')},
          messageContains: 'swatch "#zzzzzz" is not a valid hex');
    });
  });

  group('P2 plane files', () {
    test('missing _template.json fails (and P4 does not pile on)', () {
      expectsOnly(
          'P2', {'assets/styles/palettes/_template.json': _deleted},
          messageContains: '_template.json is missing');
    });

    test('missing palette.js fails', () {
      expectsOnly('P2', {'assets/app/palette.js': _deleted},
          messageContains: 'palette.js is missing');
    });
  });

  group('P3 artifacts intact', () {
    test('a declared sheet missing on disk fails', () {
      expectsOnly(
          'P3', {'assets/styles/palettes/palette-c-6f58c9.css': _deleted},
          messageContains:
              'palette "c-6f58c9" declares sheet /assets/styles/palettes/'
              'palette-c-6f58c9.css but the file is gone');
    });

    test('a non-default entry without a tokens block fails', () {
      expectsOnly('P3', {'ui/styles/common/tokens.css': ':root {\n}\n'},
          messageContains: 'carries no [data-palette="c-6f58c9"] block');
    });

    test('no tokens file in either layout fails per non-default entry', () {
      expectsOnly('P3', {'ui/styles/common/tokens.css': _deleted},
          messageContains: 'carries no [data-palette="c-6f58c9"] block');
    });

    test('app-layout tokens (assets/css/tokens.css) satisfy the gate', () {
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(
          _tree(tmp, const {
            'ui/styles/common/tokens.css': _deleted,
            'assets/css/tokens.css':
                ':root {\n}\n\n[data-palette="c-6f58c9"] {\n}\n',
          }),
          notes: notes,
          templateCheck: _noDrift);
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('site-layout tokens win when both layouts exist', () {
      // The app-layout file lacks the block; the site-layout file carries
      // it, so the resolution order — not luck — keeps the tree green.
      final findings = gateDesignPalettes(
          _tree(tmp, const {'assets/css/tokens.css': ':root {\n}\n'}),
          templateCheck: _noDrift);
      expect(findings, isEmpty, reason: findings.join('\n'));
    });
  });

  group('P4 template coverage', () {
    test('drift descriptions become findings anchored at the template', () {
      final findings = gateDesignPalettes(_tree(tmp, const {}),
          templateCheck: (_) =>
              const ['assets/css/styles.css rule .hero is not indexed']);
      expect(_rules(findings), {'P4'});
      expect(findings.single.message,
          'P4 template coverage: assets/css/styles.css rule .hero is not '
          'indexed');
      expect(findings.single.file, endsWith('_template.json'));
    });

    test('drift naming only allowlisted colors drops to notes — the '
        'intentional error-red class', () {
      // The amendment pattern: the indexer honestly reports EVERY unindexed
      // chromatic rule; the gate excuses the operator-allowlisted colors
      // (#c0392b, academy.css .waitlist-error) and fails everything else —
      // including a line that mixes an allowlisted color with a leak.
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(_tree(tmp, const {}),
          notes: notes,
          templateCheck: (_) => const [
                'assets/css/academy.css rule .waitlist-error '
                    '(color: #c0392b) is not indexed',
                'assets/css/styles.css rule .hero (color: #1b3a4b) is not '
                    'indexed',
                'assets/css/mixed.css rule .bad (color: #c0392b, '
                    'border-color: #1b3a4b) is not indexed',
              ]);
      expect(_rules(findings), {'P4'});
      expect(findings.length, 2,
          reason: 'the leak and the mixed line fail; got:\n'
              '${findings.join('\n')}');
      expect(findings.map((f) => f.message).join('\n'),
          contains('(color: #1b3a4b)'));
      expect(notes.length, 1, reason: notes.join('\n'));
      expect(notes.single.message, contains('allowlisted'));
      expect(notes.single.message, contains('#c0392b'));
      expect(notes.single.message, contains('.waitlist-error'));
    });

    test('an empty drift list stays silent', () {
      final findings =
          gateDesignPalettes(_tree(tmp, const {}), templateCheck: _noDrift);
      expect(findings, isEmpty, reason: findings.join('\n'));
    });

    test('P4 is skipped when the template itself is missing', () {
      final findings = gateDesignPalettes(
          _tree(tmp, const {'assets/styles/palettes/_template.json': _deleted}),
          templateCheck: (_) => const ['would fire if P4 ran']);
      expect(_rules(findings), {'P2'},
          reason: 'P2 owns the missing template; P4 must not pile on');
    });
  });

  group('advisory hex sweep', () {
    test('hardcoded hexes outside the plane ride the notes channel only',
        () {
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(
          _tree(tmp, const {
            'assets/css/styles.css':
                '.hero { color: #1b3a4b; background: #fafafa; }\n',
          }),
          notes: notes,
          templateCheck: _noDrift);
      expect(findings, isEmpty,
          reason: 'the sweep never fails the gate; got:\n'
              '${findings.join('\n')}');
      expect(notes.length, 1);
      expect(notes.single.message, contains('hardcoded hexes'));
      expect(notes.single.message, contains('#1b3a4b'));
      expect(notes.single.message, contains('#fafafa'));
    });

    test('the allowlist quiets intentional non-palette colors', () {
      final notes = <LintFinding>[];
      final findings = gateDesignPalettes(
          _tree(tmp, const {
            'assets/css/styles.css':
                '.stage-island { background: #0a0a0a; }\n',
          }),
          notes: notes,
          templateCheck: _noDrift);
      expect(findings, isEmpty);
      expect(notes, isEmpty, reason: notes.join('\n'));
    });
  });
}
