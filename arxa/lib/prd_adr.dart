// prd_adr — PRD and ADR RENDERERS (Slice B4).
//
// Architecture §22 again, in the one place it is easiest to break: a PRD and
// an ADR read as authoritative whether or not a human supplied a word of
// them. "Generate a PRD" is the canonical hallucination shape — it produces
// goals, metrics and rationale nobody stated, in a format that makes them
// look agreed. So both functions here are RENDERS, exactly as
// [emitBrief] is: a pure function of data that was actually recorded, with
// every unelicited field either omitted or visibly marked.
//
// WHAT THESE FUNCTIONS WILL NOT DO
//   - invent a section to complete a template. An absent field produces an
//     "Open question", never a confident paragraph.
//   - synthesise rationale. `emitAdrs` renders records it is GIVEN; it does
//     not go looking for decisions, and it cannot manufacture one.
//   - populate "Alternatives considered" from anything but genuinely
//     enumerated alternatives. Roads not taken are omitted, not guessed.
//
// WHY `emitAdrs` TAKES ITS RECORDS AS A PARAMETER (and ships no collector)
//   The B4 spec names four expected decision sources. All four were checked
//   against the tree and all four are empirically dry:
//     - kit selection    — `config/kit-registry.json` enumerates the kits that
//                          EXIST (dir/package/capabilities/backing/topology/
//                          phase/playbook). It carries no `alternatives`, no
//                          `rationale`, and no record that a project chose
//                          one. A catalogue is not a deliberation.
//     - auth strategy    — no `authStrategy`/`auth_strategy` field exists
//                          anywhere in arxa/, config/ or skills/.
//     - navigation model — likewise absent. ADR 0003 records the STUDIO's own
//                          navigation decision as hand-written prose; it is
//                          not a per-project pipeline output.
//     - theme derivation — `theme_map.dart` is a pure token→config map. It
//                          derives a fragment and records no choice.
//   `gen_playbook.dart:84` does search a kit README for a
//   decision/adr/rationale heading, but no kit README currently has one, so
//   that hook finds nothing today either.
//   A collector hard-coded to return `[]` would make the zero-ADR test
//   tautological — it would pass because the collector was empty, not because
//   the emitter refused to invent. So there is no collector: the caller
//   supplies whatever it can genuinely evidence, and today that is nothing.
//   Emitting zero ADRs is the correct output, not a missing feature.
//
// DIVERGENCE FROM THE EXISTING ADR CORPUS, DELIBERATELY
//   `skills/arxa-designer/docs/adr/` is hand-written prose — one flowing
//   paragraph that argues its case. These emitted ADRs are headed sections
//   holding verbatim record fields, because writing the argument is exactly
//   the generation §22 bans. Same `NNNN-kebab-title.md` naming, different
//   body shape, on purpose — noted here the way `intake_test.dart` notes its
//   deliberately divergent brief golden.
//
// Determinism: no clock (`project.dart:13` bans clock fields — an ADR dated
// "today" is not reproducible), no filesystem, no `answers.keys` iteration.
// Section order comes from the const tables below, so two answers maps with
// identical content but different insertion order render byte-identically.

import 'package:arxa/intake.dart';

// ─────────────────────────────────────────────────────────────────── PRD

/// One PRD section and the answers keys that may legitimately fill it.
///
/// `sources` empty is the load-bearing case: it means the intake schema has
/// NO field for this section, so it can never be filled honestly and is
/// always routed to Open questions. Problem, Success signals and Risks are
/// all in that state — intake never asks for them.
class _PrdSection {
  const _PrdSection(this.title, this.sources, this.openQuestion);
  final String title;
  final List<String> sources;
  final String openQuestion;
}

/// The PRD's section order, fixed. Iterating this (never `answers.keys`) is
/// what makes emission independent of the answers map's insertion order.
const _prdSections = <_PrdSection>[
  _PrdSection('Problem', [],
      '**Problem** — what problem does this product solve? `answers.json` has '
      'no problem field, so intake never asked. Nothing here can be filled '
      'without asking.'),
  _PrdSection('Users', ['audience'],
      '**Users** — who is this for? `audience` is unanswered.'),
  _PrdSection('Goals', ['appMustDo'],
      '**Goals** — what must the app do? `appMustDo` is unanswered.'),
  _PrdSection('Non-goals', ['outOfScope'],
      '**Non-goals** — what is explicitly excluded? `outOfScope` is '
      'unanswered.'),
  _PrdSection('Scope', ['surfaces', 'targets', 'locales', 'constraints'],
      '**Scope** — which surfaces, platforms, locales and constraints bound '
      'this? None of `surfaces`, `targets`, `locales`, `constraints` is '
      'answered.'),
  _PrdSection('Success signals', [],
      '**Success signals** — how will anyone know this worked? '
      '`answers.json` has no metrics field, so intake never asked.'),
  _PrdSection('Risks', [],
      '**Risks** — what could make this fail? `answers.json` has no risks '
      'field, so intake never asked. Note that `constraints` is rendered '
      'under Scope and is NOT a risk register.'),
];

/// Human labels for the answers keys a PRD section may draw on. A section
/// with more than one source renders each under its own `###` sub-heading so
/// the reader can see WHICH field was inferred — a single block-level mark
/// cannot say that.
const _prdSourceLabels = <String, String>{
  'audience': 'Audience',
  'appMustDo': 'What the app must do',
  'outOfScope': 'Out of scope',
  'surfaces': 'Surfaces',
  'targets': 'Platform targets',
  'locales': 'Locales',
  'constraints': 'Constraints',
};

/// Render the PRD markdown from [answers] — a pure function of the elicited
/// document, the same contract as [emitBrief].
///
/// Sections whose source fields were not answered are OMITTED and restated as
/// questions under "Open questions". Fields answered with provenance
/// `inferred` are rendered with [inferredMark] and additionally listed as
/// things to confirm. A sparse `answers.json` therefore yields a visibly
/// sparse PRD, which is the correct output and not a degraded one.
String emitPrd(Map<String, dynamic> answers) {
  final productNode = answers['product'];
  final product = (productNode is Map && productNode['value'] != null)
      ? productNode['value'].toString()
      : '(unnamed product)';

  final lines = <String>[
    '# ${mdEscape(product)} — PRD',
    '',
    '> Emitted by arxa-intake from elicited answers.',
    '> **Intake elicits; it does not generate** (architecture §22).',
    '> A section absent below was NOT elicited — it is restated as an open',
    '> question rather than filled with prose nobody supplied.',
    '> Fields marked **[inferred]** were not stated by the client and MUST',
    '> be confirmed before anyone builds against this.',
    '',
  ];

  final openQuestions = <String>[];

  // The product name heads the document, so its absence/inference has to be
  // called out even though it is not one of the eight PRD sections.
  if (productNode == null) {
    openQuestions.add('**Product** — what is this product called? `product` '
        'is unanswered; the title above is a placeholder.');
  } else if (productNode is Map && productNode['provenance'] == 'inferred') {
    openQuestions.add('`product` is **[inferred]**, not stated by the client '
        '— confirm or correct.');
  }

  for (final section in _prdSections) {
    final body = <String>[];
    final multi = section.sources.length > 1;
    for (final key in section.sources) {
      final rendered = _sourceBlock(key, answers, subHeading: multi);
      if (rendered.isEmpty) continue;
      body.addAll(rendered);
    }
    if (body.isEmpty) {
      // Nothing was elicited for this section. Omitting the heading entirely
      // is the point: an empty section under a real heading still reads as
      // "we considered this", which is the lie.
      openQuestions.add(section.openQuestion);
      continue;
    }
    lines.add('## ${section.title}');
    lines.add('');
    lines.addAll(body);
  }

  // Confirmations come after the "nothing elicited" questions so the reader
  // hits the holes first and the softer "check this" items second. Order is
  // section order then source order — never map order.
  for (final section in _prdSections) {
    for (final key in section.sources) {
      final node = answers[key];
      if (node is Map && node['provenance'] == 'inferred') {
        openQuestions.add('`$key` is **[inferred]**, not stated by the client '
            '— confirm or correct.');
      }
    }
  }

  lines.add('## Open questions');
  lines.add('');
  for (final q in openQuestions) {
    lines.add('- $q');
  }
  lines.add('');

  return '${lines.join('\n').trimRight()}\n';
}

/// Render one answers key as a PRD block, or `[]` when the key was not
/// answered. `subHeading` adds the `### Label` line that multi-source
/// sections need so a per-field [inferredMark] can attach to the right field.
List<String> _sourceBlock(String key, Map<String, dynamic> answers,
    {required bool subHeading}) {
  // `surfaces` is the odd one out: a bare top-level list of surface objects,
  // not a {value, provenance} node, and provenance lives PER SURFACE.
  if (key == 'surfaces') {
    final surfaces = answers['surfaces'];
    if (surfaces is! List) return const [];
    final items = <String>[
      for (final s in surfaces)
        if (s is Map)
          '- `${s['id']}` — ${mdEscape('${s['label']}')} (shell: ${s['shell']})'
              '${s['provenance'] == 'inferred' ? ' [inferred]' : ''}',
    ];
    if (items.isEmpty) return const [];
    return [
      if (subHeading) ...['### ${_prdSourceLabels[key]}', ''],
      ...items,
      '',
      '_source: `surfaces` — provenance is per surface, marked inline._',
      '',
    ];
  }

  final node = answers[key];
  if (node is! Map) return const [];
  final value = node['value'];
  final body = <String>[];
  if (value is List) {
    // An answered-but-empty list is a real answer ("nothing is out of
    // scope") and must not be silently upgraded into an open question.
    for (final item in value) {
      body.add('- ${mdEscape(item.toString())}');
    }
    if (body.isEmpty) body.add('_None stated._');
  } else if (value == null) {
    return const [];
  } else {
    body.add(mdEscape(value.toString()));
  }

  final out = <String>[];
  if (subHeading) {
    out.add('### ${_prdSourceLabels[key]}');
    out.add('');
  }
  if (node['provenance'] == 'inferred') {
    out.add(inferredMark);
    out.add('');
  }
  out.addAll(body);
  out.add('');
  out.add('_source: `$key` (provenance: ${node['provenance']})_');
  out.add('');
  return out;
}

// ─────────────────────────────────────────────────────────────────── ADR

/// One decision that was ACTUALLY made and recorded, ready to render.
///
/// Every field is caller-supplied and rendered verbatim. There is no
/// derivation here at all: if the caller cannot evidence a field, it leaves
/// it empty and the corresponding heading does not appear.
///
/// [alternatives] is the field this class exists to keep honest. Populate it
/// ONLY from alternatives that were genuinely enumerated at decision time.
/// The set of options that merely existed is not the set that was weighed,
/// and rendering the former as the latter is the fiction §22 bans.
class AdrRecord {
  const AdrRecord({
    required this.title,
    required this.decision,
    this.status = '',
    this.context = '',
    this.consequences = const [],
    this.alternatives = const [],
  });

  /// Human title; also the source of the filename slug.
  final String title;

  /// The recorded choice, in the words it was recorded in.
  final String decision;

  /// Recorded status (`accepted`, `superseded by 0009`, …). Empty → the
  /// Status heading is omitted rather than defaulted to "accepted", which
  /// would be an assertion nobody made.
  final String status;

  /// What was true when the decision was taken. Empty → heading omitted.
  final String context;

  /// The artifacts this decision constrains, cited concretely.
  final List<String> consequences;

  /// Alternatives genuinely enumerated at decision time. Empty → the whole
  /// "Alternatives considered" heading is omitted.
  final List<String> alternatives;
}

/// A rendered ADR: its `NNNN-kebab-title.md` name and its markdown body.
/// Returned rather than written so the emitter stays filesystem-free.
class AdrDoc {
  const AdrDoc(this.filename, this.body);
  final String filename;
  final String body;
}

/// Render [records] as ADR documents, numbered from [startNumber].
///
/// Returns one document per record, in the order given — no more, no fewer.
/// **An empty [records] returns an empty list.** That is the expected result
/// for the pipeline as it stands (see the header note): nothing decision-like
/// is recorded anywhere today, and manufacturing an ADR to demonstrate that
/// the feature works would be the exact failure this module is written to
/// avoid.
///
/// [startNumber] is a parameter, not a directory scan, because scanning is a
/// filesystem read and these emitters take everything as input. The caller
/// that knows where the ADRs live picks the next free number.
List<AdrDoc> emitAdrs(List<AdrRecord> records, {int startNumber = 1}) {
  return [
    for (var i = 0; i < records.length; i++)
      _renderAdr(records[i], startNumber + i),
  ];
}

AdrDoc _renderAdr(AdrRecord r, int number) {
  final slug = _kebab(r.title);
  if (slug.isEmpty) {
    // A blank title yields `0001-.md`, which collides with the next blank one
    // and tells a reader nothing. Fail where the bad record was written.
    throw ArgumentError('AdrRecord.title must contain at least one '
        'alphanumeric character (got "${r.title}")');
  }
  if (r.decision.trim().isEmpty) {
    // An ADR without a Decision is a heading pretending to be a record.
    throw ArgumentError('AdrRecord.decision must not be empty (title: '
        '"${r.title}")');
  }

  final lines = <String>['# ${r.title}', ''];

  void section(String heading, List<String> body) {
    if (body.isEmpty) return; // omitted, never stubbed
    lines.add('## $heading');
    lines.add('');
    lines.addAll(body);
    lines.add('');
  }

  section('Status', r.status.trim().isEmpty ? const [] : [r.status]);
  section('Context', r.context.trim().isEmpty ? const [] : [r.context]);
  section('Decision', [r.decision]);
  // Omitted wholesale when nothing was enumerated — an "Alternatives
  // considered: none" line would itself be a claim about the deliberation.
  section('Alternatives considered', [for (final a in r.alternatives) '- $a']);
  section('Consequences', [for (final c in r.consequences) '- $c']);

  final n = number.toString().padLeft(4, '0');
  return AdrDoc('$n-$slug.md', '${lines.join('\n').trimRight()}\n');
}

/// Title → filename slug, matching `skills/arxa-designer/docs/adr/`
/// (`0003-boosted-mpa-navigation.md`).
String _kebab(String title) {
  final buf = StringBuffer();
  var pendingDash = false;
  for (final rune in title.toLowerCase().runes) {
    final c = String.fromCharCode(rune);
    final isAlnum = (rune >= 0x30 && rune <= 0x39) || (rune >= 0x61 && rune <= 0x7a);
    if (isAlnum) {
      if (pendingDash && buf.isNotEmpty) buf.write('-');
      pendingDash = false;
      buf.write(c);
    } else {
      pendingDash = true;
    }
  }
  return buf.toString();
}
