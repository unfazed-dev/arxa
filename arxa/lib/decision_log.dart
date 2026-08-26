// decision_log — the pipeline's record of the choices IT made (task #67).
//
// WHY THIS EXISTS
//   `emitAdrs` (prd_adr.dart) was built, tested and correct, and emitted
//   nothing, because nothing in the pipeline recorded a decision for it to
//   render. Its header note listed the four sources the spec expected and
//   found all four dry. That note was right about those four and wrong about
//   the pipeline: intake makes real choices on every emit and throws away the
//   reason for each one.
//
// WHAT IS AND IS NOT A DECISION HERE
//   The test is NOT "were there mutually exclusive alternatives" — most of
//   these have none, and `AdrRecord.alternatives` is designed to be empty.
//   The test is the codebase's OWN marker: `provenance: 'inferred'` /
//   `statesProvenance: 'inferred'` / `feedback.inferred: true` is intake
//   declaring *"I chose this, nobody told me"*. `Intake.confirmFlow` exists
//   precisely so a human can ratify one of these — that is the code calling
//   them decisions. They fire CONDITIONALLY and they stand in for content the
//   client never supplied, which is what separates them from `theme_map.dart`
//   (a total token→config map that branches on nothing and substitutes for
//   nothing, and so records no choice).
//
//   RECORDED — all three are conditional and all three are `inferred`-stamped:
//     - flow decomposition  `emitFlows` — no `answers.flows`, so the whole
//                           navigation graph is the pipeline's construction.
//     - surface states      `deriveStates` — split into its TWO independent
//                           rules, because they have different reasons.
//     - edge feedback       `deriveFeedback` — a toast nobody asked for.
//
//   REJECTED, deliberately:
//     - `_edgeFeedback`'s declared-beats-derived precedence. It is a rule of
//       the code, identical in every project, and it fires on data that was
//       supplied rather than absent. An ADR per project asserting it would
//       document arxa, not the project.
//     - `'action': e['action'] ?? 'push'`. A schema default, per EDGE, and
//       pointedly NOT stamped `inferred` — the codebase itself declines to
//       call it an inference. Recording it would emit an ADR per edge and
//       bury the three signals above in noise.
//     - kit selection. It does not exist. `config/kit-registry.json` is read
//       only to VALIDATE dir names (`emit_structure.dart:348`) or mirror a
//       catalogue; `scaffold.dart:499` consumes `screen['kits']` that an
//       author DECLARED ("the emitter already validated the names against the
//       kit registry; scaffold consumes frozen output"); `blueprint.dart:81`
//       pins `stacked` as a hard-coded dependency and `:3571` defaults a
//       parameter to it. Nothing anywhere picks a kit for a project, so there
//       is no kit decision to record and none is invented.
//
// THE LINE THIS MUST NOT CROSS
//   `because` is the branch condition that actually ran, with the tokens that
//   actually matched — read from `intake.dart`'s own word sets through
//   [matchedCollectionWords]/[matchedFormWords]/[matchedMutationWords], never
//   re-derived here. `alternatives` is empty everywhere, because no branch in
//   intake enumerates candidates and rejects some: the closed vocabularies
//   (`surfaceStates`, `edgeActions`, `feedbackKinds`) are options that merely
//   EXISTED, and rendering those as options that were WEIGHED is the fiction
//   §22 bans.
//
// Determinism: a pure function of `answers` (plus `emitFlows` of the same),
// no clock (`project.dart:13`), no `answers.keys` iteration, and every matched
// word list sorted — set iteration order is not a contract and an ADR must be
// byte-identical across emissions.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/intake.dart';
import 'package:arxa/prd_adr.dart';

/// One choice the pipeline made, with the reason it made it.
///
/// The four content fields are the operator-approved shape
/// (`decision`/`because`/`alternatives`/`constrains`). [id] and [title] are
/// addressing, not content: [id] gives the log a stable key and fixes emission
/// order, [title] names the ADR file. Both are constants chosen per decision
/// KIND, so neither can vary with project data.
class PipelineDecision {
  const PipelineDecision({
    required this.id,
    required this.title,
    required this.decision,
    required this.because,
    this.alternatives = const [],
    required this.constrains,
  });

  final String id;
  final String title;

  /// What was chosen, naming the artifacts it actually produced.
  final String decision;

  /// The branch condition that ran, with the values that made it run.
  final String because;

  /// Candidates genuinely enumerated and rejected at that branch. Empty
  /// everywhere today — see the header note.
  final List<String> alternatives;

  /// The artifacts this choice binds.
  final List<String> constrains;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'decision': decision,
        'because': because,
        'alternatives': alternatives,
        'constrains': constrains,
      };
}

/// Every choice the pipeline made while emitting [answers], in a fixed order.
///
/// Returns `[]` when the pipeline chose nothing — which is the correct and
/// common result, not a failure. This is the same function in both cases:
/// a collector wired to return `[]` would make the zero-ADR test tautological,
/// so what varies is the INPUT, never the code path's ability to produce.
List<PipelineDecision> collectDecisions(Map<String, dynamic> answers) {
  return <PipelineDecision>[
    ...?_flowDecomposition(answers),
    ...?_statesFromCollectionWords(answers),
    ...?_statesFromFormOrAuth(answers),
    ...?_edgeFeedback(answers),
  ];
}

/// Render [decisions] as the records [emitAdrs] consumes.
///
/// `context` carries `because` and `consequences` carries `constrains` —
/// `AdrRecord`'s existing field names for the same two ideas. The mapping adds
/// nothing: every string here was written by a collector above.
List<AdrRecord> adrRecords(List<PipelineDecision> decisions) => [
      for (final d in decisions)
        AdrRecord(
          title: d.title,
          decision: d.decision,
          // The ONLY string here not lifted from a collector, so it is held to
          // what the collectors' own guards prove: every one of them fires
          // exclusively on output stamped `inferred`, and only after finding
          // the client declared nothing at that slot (`_derivableSurfaces`
          // skips declared states; `_flowDecomposition` returns null on
          // declared flows; `_edgeFeedback` reads `feedback.inferred == true`,
          // which `_edgeFeedback` in intake.dart sets only when none was
          // declared). It deliberately does NOT say "unconfirmed": nothing
          // here reads a confirmation state, and `Intake.confirmFlow` can flip
          // a flow's provenance without this code seeing it.
          status: 'inferred — derived by the pipeline, not elicited from the client',
          context: d.because,
          consequences: d.constrains,
          alternatives: d.alternatives,
        ),
    ];

// ────────────────────────────────────────────────────────── the collectors

/// The whole navigation graph, when the client supplied none.
///
/// Rule (`emitFlows`): the pass-through branch is guarded by
/// `declared is List && declared.isNotEmpty`. When that is false the fallback
/// chains each shell's surfaces in declaration order, skipping shells with one
/// surface — so an empty result means the fallback ran and still chose
/// nothing, which is not a decision.
List<PipelineDecision>? _flowDecomposition(Map<String, dynamic> answers) {
  final declared = answers['flows'];
  if (declared is List && declared.isNotEmpty) return null;

  final flows = emitFlows(answers);
  if (flows.isEmpty) return null;

  final ids = [for (final f in flows) f['id'] as String];
  final surfaces = answers['surfaces'];
  final count = surfaces is List ? surfaces.length : 0;

  return [
    PipelineDecision(
      id: 'flow-decomposition',
      title: 'Draft flows derived per shell',
      decision:
          'The project\'s navigation graph was derived, not elicited: one '
          'draft flow per shell that holds more than one surface, with that '
          'shell\'s surfaces chained in declaration order — '
          '${ids.map((i) => '`$i`').join(', ')}. Each carries '
          '`provenance: "inferred"`.',
      because: '`emitFlows` (intake.dart): `answers.flows` was '
          '${declared == null ? 'absent' : 'present but empty'}, so the '
          'pass-through branch `declared is List && declared.isNotEmpty` did '
          'not fire and the per-shell fallback ran over the $count declared '
          'surface(s).',
      constrains: [
        'intake/flows.json',
        for (final id in ids) 'flow `$id` and every edge in it',
        'the confirm step: `Intake.confirmFlow` must ratify each of these '
            'before they stop reading as inferred',
      ],
    ),
  ];
}

/// `loading` + `empty` for surfaces whose short id names a collection.
List<PipelineDecision>? _statesFromCollectionWords(Map<String, dynamic> answers) {
  final hits = <(String, List<String>)>[];
  for (final surf in _derivableSurfaces(answers)) {
    final words = matchedCollectionWords(surf);
    if (words.isNotEmpty) hits.add((surf['id'] as String, words));
  }
  if (hits.isEmpty) return null;

  return [
    PipelineDecision(
      id: 'surface-states-collection',
      title: 'Loading and empty states derived for collection surfaces',
      decision: '`loading` and `empty` were added to '
          '${hits.map((h) => '`${h.$1}`').join(', ')}, each stamped '
          '`statesProvenance: "inferred"`. The client declared no states for '
          'these surfaces.',
      because: '`deriveStates` (intake.dart): the surface id\'s short segment '
          'contains a collection word, so `tokens.any(_collectionWords.'
          'contains)` was true — '
          '${hits.map((h) => '`${h.$1}` matched ${h.$2.map((w) => '"$w"').join(', ')}').join('; ')}.',
      constrains: [
        'intake/registry.json — `states` and `statesProvenance` on '
            '${hits.map((h) => '`${h.$1}`').join(', ')}',
        'intake/brief.md — the states column, marked `[inferred]`',
        'the kit/state widgets the builder wires for those surfaces',
      ],
    ),
  ];
}

/// `error` for surfaces that submit something or sit behind auth.
///
/// The rule is `tokens.any(_formWords.contains) || surf['requiresAuth'] == true`
/// and `||` SHORT-CIRCUITS. Reporting one reason for both disjuncts would name
/// a cause that never ran for half the surfaces, so each surface is credited
/// to the disjunct(s) that actually held.
List<PipelineDecision>? _statesFromFormOrAuth(Map<String, dynamic> answers) {
  final reasons = <String>[];
  final ids = <String>[];
  for (final surf in _derivableSurfaces(answers)) {
    final words = matchedFormWords(surf);
    final auth = surf['requiresAuth'] == true;
    if (words.isEmpty && !auth) continue;
    final id = surf['id'] as String;
    ids.add(id);
    final why = <String>[
      if (words.isNotEmpty)
        'form word ${words.map((w) => '"$w"').join(', ')}',
      if (auth) 'requiresAuth: true',
    ];
    reasons.add('`$id` — ${why.join(' and ')}');
  }
  if (ids.isEmpty) return null;

  return [
    PipelineDecision(
      id: 'surface-states-error',
      title: 'Error state derived for form and authenticated surfaces',
      decision: '`error` was added to ${ids.map((i) => '`$i`').join(', ')}, '
          'each stamped `statesProvenance: "inferred"`. The client declared no '
          'states for these surfaces.',
      because: '`deriveStates` (intake.dart): '
          '`tokens.any(_formWords.contains) || surf[\'requiresAuth\'] == true` '
          'was true. `||` short-circuits, so the disjunct that actually held is '
          'recorded per surface — ${reasons.join('; ')}.',
      constrains: [
        'intake/registry.json — `states` and `statesProvenance` on '
            '${ids.map((i) => '`$i`').join(', ')}',
        'intake/brief.md — the states column, marked `[inferred]`',
        'the kit/state error widget the builder wires for those surfaces',
      ],
    ),
  ];
}

/// Success toasts derived from mutation verbs in an edge trigger.
///
/// Read off the EMITTED flows rather than recomputed, so the record cannot
/// claim a toast that flows.json does not carry. Derived draft flows use the
/// trigger `continue`, which names no mutation, so in practice only DECLARED
/// flows reach here.
List<PipelineDecision>? _edgeFeedback(Map<String, dynamic> answers) {
  final hits = <(String, String, List<String>)>[];
  for (final flow in emitFlows(answers)) {
    for (final edge in (flow['edges'] as List)) {
      final e = edge as Map;
      final fb = e['feedback'];
      if (fb is! Map || fb['inferred'] != true) continue;
      hits.add((
        flow['id'] as String,
        e['trigger'] as String,
        matchedMutationWords(e),
      ));
    }
  }
  if (hits.isEmpty) return null;

  return [
    PipelineDecision(
      id: 'edge-feedback',
      title: 'Success toasts derived for mutation edges',
      decision: 'A `success` toast was added to '
          '${hits.length} edge(s) that declared no feedback — '
          '${hits.map((h) => 'trigger "${mdEscape(h.$2)}" in `${h.$1}`').join(', ')}. '
          'Each toast\'s text is the trigger VERBATIM and each carries '
          '`inferred: true`.',
      because: '`deriveFeedback` (intake.dart): the edge declared no '
          '`feedback`, and `_words(trigger).any(_mutationWords.contains)` was '
          'true — ${hits.map((h) => '"${mdEscape(h.$2)}" matched ${h.$3.map((w) => '"$w"').join(', ')}').join('; ')}. '
          '`kind` is hard-coded `success` at that site; `error` and `info` were '
          'never evaluated.',
      constrains: [
        'intake/flows.json — the `feedback` object on those edges',
        'the kit/ui_library snackbar the builder wires for each',
      ],
    ),
  ];
}

/// Surfaces whose states intake may derive: DECLARED states always win
/// (`emitRegistry`: `if (states is List && states.isNotEmpty)`), so a surface
/// that declared its own is not a choice the pipeline made.
Iterable<Map> _derivableSurfaces(Map<String, dynamic> answers) sync* {
  final surfaces = answers['surfaces'];
  if (surfaces is! List) return;
  for (final s in surfaces) {
    if (s is! Map) continue;
    final declared = s['states'];
    if (declared is List && declared.isNotEmpty) continue;
    yield s;
  }
}

// ───────────────────────────────────────────────────────────── persistence

/// Emitted-ADR filenames: `NNNN-slug.md`, the shape `emitAdrs` produces.
final _emittedAdr = RegExp(r'^\d{4}-[a-z0-9-]+\.md$');

/// Write `decisions.json` and the `adr/` directory into [intakeDir].
///
/// The ADR directory is OWNED, not merged. ADR numbering is positional
/// (`emitAdrs`: `startNumber + i`), so if a later emit yields fewer records a
/// merge would leave `0003-*.md` on disk still asserting a decision nobody
/// made — a stale file that reads exactly as authoritative as a live one.
/// Only `NNNN-slug.md` is cleared: anything else in `adr/` was put there by a
/// human and deleting it would be this function overstepping what it owns.
void writeDecisionLog(String intakeDir, List<PipelineDecision> decisions) {
  const json = JsonEncoder.withIndent('  ');
  File('$intakeDir/decisions.json')
    ..createSync(recursive: true)
    ..writeAsStringSync('${json.convert([for (final d in decisions) d.toJson()])}\n');

  final adrDir = Directory('$intakeDir/adr');
  if (adrDir.existsSync()) {
    for (final f in adrDir.listSync().whereType<File>()) {
      if (_emittedAdr.hasMatch(f.uri.pathSegments.last)) f.deleteSync();
    }
  }
  final docs = emitAdrs(adrRecords(decisions));
  if (docs.isEmpty) return; // no decisions -> no directory conjured
  adrDir.createSync(recursive: true);
  for (final doc in docs) {
    File('${adrDir.path}/${doc.filename}').writeAsStringSync(doc.body);
  }
}
