// prd_adr tests — the anti-fabrication proofs for Slice B4.
//
// These are not "does it render" tests. A PRD emitter that invents a Problem
// paragraph would pass any shape test ever written, so the assertions here are
// built to go RED on invention specifically:
//
//   - the sparse goldens are byte-exact, so ANY new line the emitter starts
//     producing changes the bytes and fails;
//   - the sparse PRD is additionally asserted to carry exactly ONE `##`
//     heading, so a template-filling regression cannot hide inside a golden
//     that someone lazily re-blessed;
//   - the determinism test feeds two maps with identical content in DIFFERENT
//     insertion order. `emitPrd` has no clock and no I/O, so re-running it on
//     the same map is a tautology; varying key order is the version of the
//     test that can actually fail (it fails the moment anyone iterates
//     `answers.keys` instead of the const section table);
//   - the ADR whitelist test asserts every emitted line is either a fixed
//     heading or a string the caller supplied, which is what makes
//     `emitAdrs([]) == []` mean "refuses to invent" rather than "collector
//     happened to be empty".
//
// The goldens diverge from `skills/arxa-designer/docs/adr/`'s hand-written
// prose voice deliberately — see the note in prd_adr.dart's header.

import 'package:arxa/intake.dart' show inferredMark;
import 'package:arxa/prd_adr.dart';
import 'package:test/test.dart';

/// The PRD's fixed preamble. Extracted so the goldens below read as content.
const _preamble = '''
> Emitted by arxa-intake from elicited answers.
> **Intake elicits; it does not generate** (architecture §22).
> A section absent below was NOT elicited — it is restated as an open
> question rather than filled with prose nobody supplied.
> Fields marked **[inferred]** were not stated by the client and MUST
> be confirmed before anyone builds against this.''';

/// `emitPrd({})` — every section unelicited. This is the shape a fabricating
/// emitter cannot produce.
const _sparseGolden = '''
# (unnamed product) — PRD

$_preamble

## Open questions

- **Product** — what is this product called? `product` is unanswered; the title above is a placeholder.
- **Problem** — what problem does this product solve? `answers.json` has no problem field, so intake never asked. Nothing here can be filled without asking.
- **Users** — who is this for? `audience` is unanswered.
- **Goals** — what must the app do? `appMustDo` is unanswered.
- **Non-goals** — what is explicitly excluded? `outOfScope` is unanswered.
- **Scope** — which surfaces, platforms, locales and constraints bound this? None of `surfaces`, `targets`, `locales`, `constraints` is answered.
- **Success signals** — how will anyone know this worked? `answers.json` has no metrics field, so intake never asked.
- **Risks** — what could make this fail? `answers.json` has no risks field, so intake never asked. Note that `constraints` is rendered under Scope and is NOT a risk register.
''';

const _populatedGolden = '''
# Demo app — PRD

$_preamble

## Users

Indie devs

_source: `audience` (provenance: client)_

## Goals

- list projects
- run a build

_source: `appMustDo` (provenance: client)_

## Scope

### Surfaces

- `projects.home` — Home (shell: projects)
- `projects.new` — New (shell: projects) [inferred]

_source: `surfaces` — provenance is per surface, marked inline._

### Platform targets

- macos

_source: `targets` (provenance: client)_

### Constraints

$inferredMark

- offline first

_source: `constraints` (provenance: inferred)_

## Open questions

- **Problem** — what problem does this product solve? `answers.json` has no problem field, so intake never asked. Nothing here can be filled without asking.
- **Non-goals** — what is explicitly excluded? `outOfScope` is unanswered.
- **Success signals** — how will anyone know this worked? `answers.json` has no metrics field, so intake never asked.
- **Risks** — what could make this fail? `answers.json` has no risks field, so intake never asked. Note that `constraints` is rendered under Scope and is NOT a risk register.
- `constraints` is **[inferred]**, not stated by the client — confirm or correct.
''';

Map<String, dynamic> _populatedAnswers() => {
      'product': {'value': 'Demo app', 'provenance': 'client'},
      'audience': {'value': 'Indie devs', 'provenance': 'client'},
      'appMustDo': {
        'value': ['list projects', 'run a build'],
        'provenance': 'client',
      },
      'targets': {
        'value': ['macos'],
        'provenance': 'client',
      },
      'constraints': {
        'value': ['offline first'],
        'provenance': 'inferred',
      },
      'surfaces': [
        {
          'id': 'projects.home',
          'label': 'Home',
          'shell': 'projects',
          'provenance': 'client',
        },
        {
          'id': 'projects.new',
          'label': 'New',
          'shell': 'projects',
          'provenance': 'inferred',
        },
      ],
    };

void main() {
  group('emitPrd — sparse in, sparse out', () {
    test('empty answers render only open questions, byte-exact', () {
      expect(emitPrd(const {}), _sparseGolden);
    });

    test('a sparse PRD carries exactly one section heading', () {
      // The assertion that catches template-filling independently of the
      // golden: if the emitter ever starts emitting `## Problem` (or any other
      // section it has no data for), this fails even if someone re-blessed the
      // golden without reading it.
      final headings = emitPrd(const {})
          .split('\n')
          .where((l) => l.startsWith('## '))
          .toList();
      expect(headings, ['## Open questions']);
    });

    test('sections intake never asks for are questions, not prose', () {
      final prd = emitPrd(_populatedAnswers());
      // Problem / Success signals / Risks have NO answers.json field at all,
      // so they must never appear as headings however full the answers are.
      for (final never in const ['## Problem', '## Success signals', '## Risks']) {
        expect(prd, isNot(contains(never)),
            reason: '$never has no elicited source and must stay a question');
      }
      expect(prd, contains('- **Problem** — what problem does this product solve?'));
      expect(prd, contains('- **Success signals** — how will anyone know'));
      expect(prd, contains('- **Risks** — what could make this fail?'));
    });

    test('answered-with-nothing is NOT the same as unanswered', () {
      // The module's core semantic and the easiest thing for a later refactor
      // to collapse: "nothing is out of scope" is a real answer and must keep
      // its section, while an absent `outOfScope` must become a question.
      // Treating empty as unanswered would silently discard a client's answer.
      final answers = _populatedAnswers()
        ..['outOfScope'] = {'value': <String>[], 'provenance': 'client'};
      final prd = emitPrd(answers);
      expect(prd, contains('## Non-goals'));
      expect(prd, contains('_None stated._'));
      expect(prd, isNot(contains('- **Non-goals** — what is explicitly excluded?')));
    });

    test('an unanswered field becomes an open question, not a section', () {
      final prd = emitPrd(_populatedAnswers()); // no outOfScope, no locales
      expect(prd, isNot(contains('## Non-goals')));
      expect(prd, contains('- **Non-goals** — what is explicitly excluded?'));
      expect(prd, isNot(contains('Locales')));
    });
  });

  group('emitPrd — [inferred] marking', () {
    test('an inferred field carries the shared mark, not a second marker', () {
      final prd = emitPrd(_populatedAnswers());
      expect(prd, contains(inferredMark));
      // The mark attaches to the field that was inferred, under its own
      // sub-heading — a block-level mark on Scope could not say which of
      // surfaces/targets/constraints was unstated.
      expect(prd, contains('### Constraints\n\n$inferredMark'));
      // ...and NOT to the client-stated ones.
      expect(prd, isNot(contains('### Platform targets\n\n$inferredMark')));
    });

    test('per-surface provenance is marked inline', () {
      final prd = emitPrd(_populatedAnswers());
      expect(prd, contains('- `projects.new` — New (shell: projects) [inferred]'));
      expect(prd, contains('- `projects.home` — Home (shell: projects)\n'));
    });

    test('every inferred field is also listed as a thing to confirm', () {
      expect(emitPrd(_populatedAnswers()),
          contains('- `constraints` is **[inferred]**, not stated by the client'));
    });

    test('populated answers render byte-exact', () {
      expect(emitPrd(_populatedAnswers()), _populatedGolden);
    });
  });

  group('emitPrd — determinism', () {
    test('key insertion order does not change a byte', () {
      // The version of the determinism test that can fail: `emitPrd` has no
      // clock and no I/O, so running it twice on the SAME map proves nothing.
      // Two maps with identical content in different insertion order go red
      // the moment anyone iterates `answers.keys`.
      final a = <String, dynamic>{};
      for (final k in const [
        'product',
        'audience',
        'appMustDo',
        'targets',
        'constraints',
        'surfaces'
      ]) {
        a[k] = _populatedAnswers()[k];
      }
      final b = <String, dynamic>{};
      for (final k in const [
        'surfaces',
        'constraints',
        'targets',
        'appMustDo',
        'audience',
        'product'
      ]) {
        b[k] = _populatedAnswers()[k];
      }
      expect(a.keys.toList(), isNot(b.keys.toList())); // the premise holds
      expect(emitPrd(a), emitPrd(b));
    });

    test('re-emitting the same answers is byte-identical', () {
      final answers = _populatedAnswers();
      expect(emitPrd(answers), emitPrd(answers));
      expect(emitPrd(const {}), emitPrd(const {}));
    });
  });

  group('emitAdrs — no recorded decision, no ADR', () {
    test('no records produces zero ADRs', () {
      expect(emitAdrs(const []), isEmpty);
    });

    test('one record produces exactly one ADR and nothing beyond it', () {
      // The paired half of the zero-ADR test. Without this, `emitAdrs([])` is
      // empty could just mean the function is a stub. Here the emitter is
      // shown to render, and shown to render ONLY what it was handed.
      const rec = AdrRecord(
        title: 'Boosted MPA navigation',
        decision: 'Every Surface is a real URL; hx-boost converts links to body swaps.',
        status: 'accepted',
        consequences: ['constrains models/screens_model/registry.json'],
      );
      final docs = emitAdrs(const [rec]);
      expect(docs, hasLength(1));

      const fixed = {
        '',
        '## Status',
        '## Context',
        '## Decision',
        '## Alternatives considered',
        '## Consequences',
      };
      final supplied = {
        '# ${rec.title}',
        rec.status,
        rec.decision,
        for (final c in rec.consequences) '- $c',
        for (final a in rec.alternatives) '- $a',
      };
      for (final line in docs.single.body.split('\n')) {
        expect(fixed.contains(line) || supplied.contains(line), isTrue,
            reason: 'ADR line was neither a fixed heading nor caller-supplied '
                'text — the emitter invented it: "$line"');
      }
    });

    test('alternatives nobody enumerated produce no heading at all', () {
      // Not "Alternatives considered: none" — that sentence is itself a claim
      // about a deliberation that may never have happened.
      final docs = emitAdrs(const [
        AdrRecord(title: 'Kit selection', decision: 'core + ui_library'),
      ]);
      expect(docs.single.body, isNot(contains('Alternatives')));
      expect(docs.single.body, isNot(contains('none')));
      // Unsupplied optional sections are absent too, not stubbed.
      expect(docs.single.body, isNot(contains('## Status')));
      expect(docs.single.body, isNot(contains('## Context')));
      expect(docs.single.body, isNot(contains('## Consequences')));
    });

    test('genuinely enumerated alternatives are rendered verbatim', () {
      final docs = emitAdrs(const [
        AdrRecord(
          title: 'Boosted MPA navigation',
          decision: 'Boosted MPA.',
          alternatives: ['plain MPA + cross-document VT', 'fragment-shell SPA'],
        ),
      ]);
      expect(docs.single.body, contains('## Alternatives considered'));
      expect(docs.single.body, contains('- plain MPA + cross-document VT'));
      expect(docs.single.body, contains('- fragment-shell SPA'));
    });
  });

  group('emitAdrs — numbering and naming', () {
    test('filenames match the existing NNNN-kebab-title.md convention', () {
      final docs = emitAdrs(const [
        AdrRecord(title: 'Boosted MPA navigation', decision: 'x'),
        AdrRecord(title: 'Server-first HDA runtime', decision: 'y'),
      ]);
      final re = RegExp(r'^\d{4}-[a-z0-9]+(-[a-z0-9]+)*\.md$');
      for (final d in docs) {
        expect(re.hasMatch(d.filename), isTrue, reason: d.filename);
      }
      expect(docs.map((d) => d.filename),
          ['0001-boosted-mpa-navigation.md', '0002-server-first-hda-runtime.md']);
    });

    test('startNumber is the caller\'s, not a directory scan', () {
      // A filesystem scan inside the emitter would break the no-I/O invariant
      // and make output depend on the tree rather than the input.
      final docs = emitAdrs(
        const [AdrRecord(title: 'Theme derivation', decision: 'tokens only')],
        startNumber: 9,
      );
      expect(docs.single.filename, '0009-theme-derivation.md');
    });

    test('emitting twice is byte-identical', () {
      const recs = [AdrRecord(title: 'Kit selection', decision: 'core')];
      expect(emitAdrs(recs).single.body, emitAdrs(recs).single.body);
      expect(emitAdrs(recs).single.filename, emitAdrs(recs).single.filename);
    });
  });

  group('emitAdrs — records that are not records', () {
    test('a title with no alphanumerics is rejected, not silently numbered', () {
      expect(() => emitAdrs(const [AdrRecord(title: '???', decision: 'x')]),
          throwsArgumentError);
    });

    test('a record with no decision is rejected', () {
      // A heading pretending to be a record is the exact failure mode this
      // module exists to prevent.
      expect(() => emitAdrs(const [AdrRecord(title: 'Something', decision: '  ')]),
          throwsArgumentError);
    });
  });
}
