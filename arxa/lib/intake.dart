// arxa-intake — the elicitation engine (Dart port of
// `skills/arxa-intake/intake.py`).
//
// Architecture §22: intake ELICITS requirements; it NEVER generates design or
// code. This is the single engine both the headless phase and the desktop
// wizard drive ("one engine" — if the two front ends can disagree, plan 10 has
// failed). It does three things and only three things:
//
//   1. validate — check an answers document, where every field carries
//      provenance (client | founder | inferred).
//   2. emit     — turn validated answers into docs/intake/brief.md (every
//      `inferred` field visibly marked) and a seeded registry.json (ids,
//      shells, comps; surface ALWAYS null — intake names, never designs).
//      The default registry path is the GATE's canonical one (structure.json's
//      "registry" field under designs/arxa-studio), not the client-repo
//      docs/intake/ fallback — see defaultRegistryOut().
//
// [renderBriefSections] is public so the intake → story-map chain
// (story_map.dart renderBrief's `answers` path) can emit the UNIFIED brief
// without duplicating the section rendering — one engine, one renderer.
//   3. seed     — accept a HAND-WRITTEN brief (plan 10.7: intake is optional)
//      and derive the registry seed from its surface table, without rewriting
//      a word of the brief.
//
// THE CONTRACT THIS MODULE EXISTS TO ENFORCE
//   Emission is a PURE function of its input. [emitBrief]/[emitRegistry] add
//   no content that was not elicited: no new surfaces, no new field values, no
//   invented copy. The only things derived are mechanical naming (comp from
//   id, by the convention in declare-structure) and the structural default
//   surface=null. Everything else is the client's words, passed through.

import 'dart:convert';
import 'dart:io';

import 'package:arxa/decision_log.dart';
import 'package:arxa/intake_artifacts.dart';
import 'package:arxa/prd_adr.dart';
import 'package:arxa/project.dart';

/// Who supplied a field. `inferred` = NOT elicited; a placeholder the brief must
/// visibly flag. There is no fourth value — 'guessed', 'assumed', 'default' are
/// all 'inferred'.
const provenance = ['client', 'founder', 'inferred'];

/// Surface id is `<shell>.<short>`, both lowercase alnum (see
/// intake.schema.json).
final _idRe = RegExp(r'^([a-z][a-z0-9]*)\.([a-z][a-z0-9]*)$');

/// Flow id is `flow-<name>` (kebab), matching the registry's flows.json.
final _flowIdRe = RegExp(r'^flow-[a-z0-9]+(-[a-z0-9]+)*$');

/// The typed navigation actions an edge can carry (flows.json v2). `system`
/// marks non-gesture edges (auth-success, deep-link) — the scaffolder maps
/// them to route guards, never to buttons.
const edgeActions = ['push', 'replace', 'back', 'modal', 'system'];

/// The CLOSED vocabulary of screen-level states (D2). A state is a way the
/// SCREEN can look while it waits, has nothing, or has failed — it maps to
/// `kit/state`. The list is closed on purpose: an open vocabulary let every
/// project invent a synonym ('skeleton', 'pending', 'blank') that no kit
/// implements. Emitted in THIS order wherever states are derived.
const surfaceStates = ['loading', 'empty', 'error'];

/// The CLOSED vocabulary of edge-level feedback kinds (D2). Feedback is a
/// consequence of a TRANSITION — a toast — so it lives on the edge, not in
/// `states`; it maps to `kit/ui_library`, not `kit/state`.
const feedbackKinds = ['success', 'error', 'info'];

/// Every key a flow edge may carry. CLOSED, and it works as a PAIR with the
/// spread in [emitFlows]: the spread guarantees no authored key is ever
/// dropped, and this set guarantees nothing unauthorised rides along on it.
/// Change one and you must change the other — plus `/definitions/edge` in
/// `skills/arxa-intake/intake.schema.json`, which nothing loads and so
/// drifts invisibly.
///
/// Closing this set does NOT catch the bug it was added alongside: `element`
/// and `feedback` were both *validated and then dropped* — legal keys the
/// emitter forgot. Only the spread (and the passthrough test) catch that.
const edgeKeys = ['from', 'to', 'trigger', 'action', 'element', 'feedback'];

/// Every key a flow may carry. CLOSED, same reasoning as [edgeKeys].
const flowKeys = ['id', 'name', 'provenance', 'edges'];

/// Every key a `feedback` object may carry. CLOSED. `inferred` is the
/// derivation stamp intake adds, never authored copy. `action` is the
/// snackbar's button — optional, because most toasts are only read.
const feedbackKeys = ['kind', 'text', 'inferred', 'action'];

/// Every key a `feedback.action` object may carry. CLOSED, same reasoning as
/// [edgeKeys] — an open sub-object in this file would be the one unclosed set.
///
/// NOT the same thing as an edge's `action` (the typed nav op in
/// [edgeActions]): this one is the button ON the toast. `trigger` is what
/// taking it does, in the client's words — deliberately prose and NOT a
/// surface id, because the canonical case is Retry, which re-runs the failed
/// operation rather than navigating anywhere.
const feedbackActionKeys = ['label', 'trigger'];

/// The visible marker the emitted brief puts on any `inferred` field. A reader
/// who skims must not miss it — that is the entire point of marking inference.
const inferredMark = '> **[inferred]** — not stated by the client; confirm or correct.';

/// Ordered brief sections (the brief renders them in this order).
const _fieldTitles = <(String, String)>[
  ('product', 'Product'),
  ('audience', 'Audience'),
  ('appMustDo', 'What the app must do'),
  ('existingSystems', 'Existing systems'),
  ('targets', 'Targets'),
  ('locales', 'Locales'),
  ('brand', 'Brand'),
  ('direction', 'Design direction'),
  ('contentAnchors', 'Content anchors'),
  ('constraints', 'Constraints'),
  ('outOfScope', 'Out of scope'),
  ('layoutTemplate', 'Layout template'),
];

const _listFields = {'appMustDo', 'constraints', 'outOfScope', 'locales', 'contentAnchors'};

final _tableSplit = RegExp(r'\s*\|\s*');
const _sepChars = {'-', ':', ' '};

// ---------------------------------------------------------------- validation

/// Validate [answers]; returns the list of human-readable error strings
/// (empty = valid). Structural + semantic checks that the JSON Schema cannot
/// express on their own; each error names the offending field.
ValidationResult validateIntake(Map<String, dynamic> answers) {
  final errs = <String>[];

  for (final key in const ['product', 'audience', 'appMustDo', 'targets']) {
    if (!answers.containsKey(key)) {
      errs.add('$key: required field is missing');
    }
  }

  for (final (key, _) in _fieldTitles) {
    if (!answers.containsKey(key)) continue;
    final node = answers[key];
    if (node is! Map) {
      errs.add('$key: expected {value, provenance}, got ${_pyTypeName(node)}');
      continue;
    }
    final prov = node['provenance'];
    if (!provenance.contains(prov)) {
      errs.add("$key: provenance '$prov' is not one of $provenance "
          "(there is no fourth value — unstated means 'inferred')");
    }
    final val = node['value'];
    if (_listFields.contains(key)) {
      if (val is! List || val.any((x) => x is! String)) {
        errs.add('$key: value must be a list of strings');
      }
    } else if (key == 'targets') {
      if (val is! List || val.any((x) => x is! String)) {
        errs.add('$key: value must be a list of platform strings (§11)');
      }
    } else if (key == 'layoutTemplate') {
      errs.addAll(_validateLayoutTemplate(val));
    } else if (key == 'direction') {
      errs.addAll(_validateDirection(val));
    } else {
      if (val is! String) {
        errs.add('$key: value must be a string');
      }
    }
  }

  // surfaces: shape + the shell==id-prefix invariant + uniqueness.
  // ABSENT is legal — "no surfaces named at intake, the designer authors
  // the registry" (emitBrief renders exactly that). Only a PRESENT non-list
  // is a type defect, and the error must say so (F6: a missing key used to
  // report "must be a list", pointing the author at a defect that wasn't).
  var surfaces = answers['surfaces'];
  if (surfaces == null) {
    surfaces = const [];
  } else if (surfaces is! List) {
    errs.add(
        'surfaces: must be a list of surface objects, got ${_pyTypeName(surfaces)}');
    surfaces = const [];
  }
  final seen = <String>{};
  for (var i = 0; i < surfaces.length; i++) {
    final s = surfaces[i];
    final where = 'surfaces[$i]';
    if (s is! Map) {
      errs.add('$where: expected an object');
      continue;
    }
    for (final req in const ['id', 'label', 'shell', 'provenance']) {
      if (!s.containsKey(req)) {
        errs.add("$where: missing '$req'");
      }
    }
    final sid = s['id'].toString();
    final m = _idRe.firstMatch(sid);
    if (m == null) {
      errs.add("$where: id '$sid' must be <shell>.<short> (lowercase alnum, "
          'e.g. projects.home)');
    } else {
      final shellFromId = m.group(1)!;
      if (s['shell'] != shellFromId) {
        errs.add("$where: shell '${s['shell']}' must equal the id's first "
            "segment '$shellFromId'");
      }
    }
    if (!provenance.contains(s['provenance'])) {
      errs.add("$where: provenance '${s['provenance']}' is not one of $provenance");
    }
    final states = s['states'];
    if (states != null && (states is! List || states.any((x) => x is! String))) {
      errs.add("$where: states must be a list of strings (e.g. empty, loading, error)");
    } else if (states is List) {
      // The vocabulary is CLOSED (D2). Name the offender AND the whole allowed
      // set — the message has to carry the fix, because the only way out is to
      // pick a different word.
      for (final st in states) {
        if (!surfaceStates.contains(st)) {
          errs.add("$where: state '$st' is not one of $surfaceStates — the "
              'screen-state vocabulary is closed (a toast is not a screen '
              "state; put it on a flow edge as `feedback`)");
        }
      }
    }
    if (s.containsKey('feedback')) {
      errs.add("$where: feedback does not belong on a surface — a toast is a "
          'consequence of a TRANSITION, so it belongs on a flow edge '
          '(flows[].edges[].feedback)');
    }
    if (seen.contains(sid)) {
      errs.add("$where: duplicate id '$sid' (ids are permanent — add a new "
          'one, do not reuse)');
    }
    seen.add(sid);
    final route = s['route'];
    if (route != null && (route is! String || !route.startsWith('/'))) {
      errs.add("$where: route must be a path string starting with '/' "
          '(omit it to derive /<short>)');
    }
    for (final flag in const ['requiresAuth', 'tab']) {
      if (s[flag] != null && s[flag] is! bool) {
        errs.add("$where: $flag must be a boolean");
      }
    }
  }

  errs.addAll(_validateFlows(answers, seen));
  // personas (Slice B2) is checked on its own, NOT through the _fieldTitles
  // loop: that loop demands {value, provenance} and drives the brief's section
  // order, and a list-shaped group there would be reported as a type error on
  // every valid answers document. Absent is valid — see [validatePersonas].
  errs.addAll(validatePersonas(answers));

  return ValidationResult(errs);
}

/// Validate the optional `flows` group: a list of
/// `{id, name, provenance, edges: [{from, to, trigger, action?}]}`, where
/// every endpoint is a DECLARED surface and each flow is a LINEAR chain
/// (≤1 outgoing and ≤1 incoming edge per screen — no branches, no loops).
List<String> _validateFlows(Map<String, dynamic> answers, Set<String> surfaceIds) {
  final errs = <String>[];
  final flows = answers['flows'];
  if (flows == null) return errs; // absent → the engine derives drafts
  if (flows is! List) return ['flows: must be a list'];
  final seenFlows = <String>{};
  for (var i = 0; i < flows.length; i++) {
    final f = flows[i];
    final where = 'flows[$i]';
    if (f is! Map) {
      errs.add('$where: expected an object');
      continue;
    }
    final fid = f['id']?.toString() ?? '';
    if (!_flowIdRe.hasMatch(fid)) {
      errs.add("$where: id '$fid' must be flow-<name> (kebab-case)");
    }
    if (seenFlows.contains(fid)) errs.add("$where: duplicate flow id '$fid'");
    seenFlows.add(fid);
    if (f['name'] is! String || (f['name'] as String?)!.isEmpty) {
      errs.add("$where: missing 'name'");
    }
    if (!provenance.contains(f['provenance'])) {
      errs.add("$where: provenance '${f['provenance']}' is not one of $provenance");
    }
    if (f.containsKey('feedback')) {
      errs.add('$where: feedback belongs on an EDGE, not on the flow — a toast '
          'fires on one transition, not for a whole journey');
    }
    for (final k in f.keys) {
      if (k != 'feedback' && !flowKeys.contains(k)) {
        errs.add("$where: unknown key '$k' — a flow carries only $flowKeys");
      }
    }
    final edges = f['edges'];
    if (edges is! List || edges.isEmpty) {
      errs.add('$where: edges must be a non-empty list (a flow is a chain)');
      continue;
    }
    final outgoing = <String>{};
    final incoming = <String>{};
    for (var j = 0; j < edges.length; j++) {
      final e = edges[j];
      final ew = '$where.edges[$j]';
      if (e is! Map) {
        errs.add('$ew: expected an object');
        continue;
      }
      for (final req in const ['from', 'to', 'trigger']) {
        if (e[req] is! String || (e[req] as String?)!.isEmpty) {
          errs.add("$ew: missing '$req'");
        }
      }
      for (final end in const ['from', 'to']) {
        final sid = e[end]?.toString() ?? '';
        if (e[end] is String && !surfaceIds.contains(sid)) {
          errs.add("$ew: $end '$sid' is not a declared surface "
              '(flows wire intake surfaces, nothing else)');
        }
      }
      final action = e['action'];
      if (action != null && !edgeActions.contains(action)) {
        errs.add("$ew: action '$action' is not one of $edgeActions");
      }
      // `element` names the thing a user touches to take this edge — it joins
      // to a `data-el` value on the surface (e.g. "button:Continue"). Type only:
      // whether it resolves to a real data-el lives in the rendered surface,
      // which intake cannot see. Optional — absent means the flow walk falls
      // back to a fuzzy trigger match.
      final element = e['element'];
      if (element != null && (element is! String || element.isEmpty)) {
        errs.add('$ew: element must be a non-empty string naming a data-el '
            '(e.g. "button:Continue") — omit it to fuzzy-match the trigger');
      }
      errs.addAll(_validateFeedback(e['feedback'], ew));
      // The gate that makes emitFlows' spread safe: every authored key is
      // carried through, so an unrecognised one must be refused HERE or it
      // rides along into flows.json and is honoured by nobody.
      for (final k in e.keys) {
        if (!edgeKeys.contains(k)) {
          errs.add("$ew: unknown key '$k' — an edge carries only $edgeKeys");
        }
      }
      final from = e['from']?.toString() ?? '';
      final to = e['to']?.toString() ?? '';
      if (from == to) errs.add("$ew: self-edge '$from' (loops are not drawn)");
      if (!outgoing.add(from)) {
        errs.add("$ew: '$from' has a second outgoing edge "
            '(flows are linear chains — no branches)');
      }
      if (!incoming.add(to)) {
        errs.add("$ew: '$to' has a second incoming edge "
            '(flows are linear chains — no merges)');
      }
    }
  }
  return errs;
}

/// Shape-check an edge's optional `feedback` value: `{kind, text}` with
/// `kind` in [feedbackKinds] and `text` a non-empty string. Absent is fine —
/// most transitions say nothing. [where] is the edge label so the message
/// points at one edge, not at the flow.
List<String> _validateFeedback(Object? val, String where) {
  if (val == null) return const [];
  if (val is! Map) {
    return [
      '$where: feedback must be an object {kind, text} — got '
          '${val.runtimeType}'
    ];
  }
  final errs = <String>[];
  final kind = val['kind'];
  if (!feedbackKinds.contains(kind)) {
    errs.add("$where: feedback.kind '$kind' is not one of $feedbackKinds");
  }
  final text = val['text'];
  if (text is! String || text.trim().isEmpty) {
    errs.add('$where: feedback.text must be a non-empty string (the words the '
        'user actually reads)');
  }
  errs.addAll(_validateFeedbackAction(val['action'], where));
  // Closed, and kept in step with `/definitions/edge/properties/feedback` in
  // intake.schema.json. `inferred` is the derivation stamp, not authored copy.
  for (final k in val.keys) {
    if (!feedbackKeys.contains(k)) {
      errs.add("$where: feedback has unknown key '$k' — it carries only "
          '$feedbackKeys');
    }
  }
  return errs;
}

/// Shape-check a feedback's optional `action`: `{label, trigger}`, both
/// non-empty strings. Absent is fine — most toasts are only read. Never
/// derived: inventing a button the client did not ask for is generation (§22).
List<String> _validateFeedbackAction(Object? val, String where) {
  if (val == null) return const [];
  if (val is! Map) {
    return [
      '$where: feedback.action must be an object {label, trigger} — got '
          '${val.runtimeType}'
    ];
  }
  final errs = <String>[];
  for (final k in feedbackActionKeys) {
    final v = val[k];
    if (v is! String || v.trim().isEmpty) {
      errs.add("$where: feedback.action.$k must be a non-empty string");
    }
  }
  for (final k in val.keys) {
    if (!feedbackActionKeys.contains(k)) {
      errs.add("$where: feedback.action has unknown key '$k' — it carries "
          'only $feedbackActionKeys');
    }
  }
  return errs;
}

/// Words in a surface's short id segment that mark it as a COLLECTION — a
/// screen that shows many of something, so it can be waiting or have none.
/// Derives `loading` + `empty`.
const _collectionWords = {
  'all', 'browse', 'cart', 'catalog', 'category', 'feed', 'gallery', 'history',
  'home', 'inbox', 'index', 'library', 'list', 'notifications', 'orders',
  'results', 'search', 'timeline',
};

/// Words in a surface's short id segment that mark it as a FORM, AUTH or
/// NETWORK screen — one that submits something and can therefore fail.
/// Derives `error`.
const _formWords = {
  'auth', 'checkout', 'compose', 'create', 'edit', 'form', 'login', 'new',
  'password', 'pay', 'payment', 'profile', 'register', 'reset', 'settings',
  'signin', 'signup', 'startup', 'sync', 'upload',
};

/// Verbs in an edge's trigger that mark it as a MUTATION — a transition that
/// changes server state, so the user needs telling it worked. Derives a
/// `feedback` toast.
const _mutationWords = {
  'add', 'apply', 'book', 'buy', 'checkout', 'confirm', 'create', 'delete',
  'pay', 'place', 'post', 'publish', 'remove', 'save', 'send', 'submit',
  'update', 'upload',
};

/// Split a string into lowercase word tokens for heuristic matching.
/// Deterministic and allocation-cheap; no locale rules, no stemming.
Set<String> _words(String s) => s
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.isNotEmpty)
    .toSet();

/// DERIVE a surface's states from the shape its own declaration implies.
///
/// Intake elicits; it does not generate (architecture §22) — so this is legal
/// only because every derived value is stamped `statesProvenance: 'inferred'`
/// and rendered `[inferred]` in the brief, exactly as `emitFlows` already does
/// for derived flows. The confirm step is what makes it honest.
///
/// The signal is the id's SHORT SEGMENT plus `requiresAuth` — a surface at
/// intake has no other shape to read. Returns states in [surfaceStates] order;
/// an empty result means "no signal", and the caller omits the key entirely.
List<String> deriveStates(Map surf) {
  final short = _idRe.firstMatch(surf['id'].toString())?.group(2) ?? '';
  final tokens = _words(short);
  final out = <String>{};
  if (tokens.any(_collectionWords.contains)) {
    out.addAll(['loading', 'empty']);
  }
  if (tokens.any(_formWords.contains) || surf['requiresAuth'] == true) {
    out.add('error');
  }
  return [
    for (final s in surfaceStates)
      if (out.contains(s)) s,
  ];
}

/// DERIVE an edge's feedback when its trigger names a mutation.
///
/// `text` is the trigger VERBATIM — a mechanical transform, never invented
/// copy. Writing a verb→noun table to make "Add to bag" read as "Added to bag"
/// would be generation, which §22 forbids; the tick and the styling belong to
/// the renderer, which reads `kind`. Returns null when the trigger names no
/// mutation.
/// The `feedback` entry an emitted edge should carry, as a spreadable map:
/// the declared value verbatim, else a derived one, else nothing at all.
Map<String, dynamic>? _edgeFeedback(Object? edge) {
  if (edge is! Map) return null;
  final declared = edge['feedback'];
  if (declared != null) return {'feedback': declared};
  final derived = deriveFeedback(edge);
  return derived == null ? null : {'feedback': derived};
}

Map<String, dynamic>? deriveFeedback(Map edge) {
  final trigger = edge['trigger'];
  if (trigger is! String) return null;
  if (!_words(trigger).any(_mutationWords.contains)) return null;
  return <String, dynamic>{
    'kind': 'success',
    'text': trigger,
    'inferred': true,
  };
}

// ─────────────────────────────────────────── which rule actually fired
//
// [deriveStates] and [deriveFeedback] answer WHAT was inferred and throw away
// WHY. `decision_log.dart` has to state the reason in an ADR, and an ADR whose
// reason was reconstructed rather than observed is the §22 failure this whole
// layer exists to prevent. So the evidence is read out of the SAME private
// word sets and the SAME tokenizer the rules use — a second copy of
// `_collectionWords` or of `_words` in the collector could drift from these
// and then confidently report a reason that never fired.
//
// Each returns the matched words SORTED (set iteration order is not a
// contract, and an ADR must be byte-identical across emissions).

/// The collection words in [surf]'s short id segment — the tokens that made
/// [deriveStates] add `loading` + `empty`. Empty means that branch did not fire.
List<String> matchedCollectionWords(Map surf) =>
    _matchedShortIdWords(surf, _collectionWords);

/// The form/auth/network words in [surf]'s short id segment — the LEFT disjunct
/// of [deriveStates]'s `error` branch. Empty means that disjunct did not fire,
/// which does NOT mean `error` was not added: `requiresAuth == true` is the
/// right disjunct and `||` short-circuits, so the two must be reported
/// separately or an ADR will name a cause that never ran.
List<String> matchedFormWords(Map surf) =>
    _matchedShortIdWords(surf, _formWords);

List<String> _matchedShortIdWords(Map surf, Set<String> vocabulary) {
  final short = _idRe.firstMatch(surf['id'].toString())?.group(2) ?? '';
  return (_words(short).where(vocabulary.contains).toList()..sort());
}

/// The mutation verbs in [edge]'s trigger — the tokens that made
/// [deriveFeedback] return a toast. Empty means it returned null.
List<String> matchedMutationWords(Map edge) {
  final trigger = edge['trigger'];
  if (trigger is! String) return const [];
  return (_words(trigger).where(_mutationWords.contains).toList()..sort());
}

List<String> _validateDirection(Object? val) {
  // Shape-check a direction value: {adjectives: [string], avoids: [string]} —
  // both lists optional, but when present they must be string lists.
  if (val is! Map) {
    return [
      'direction: value must be an object {adjectives, avoids} '
          '(both lists optional), got ${_pyTypeName(val)}'
    ];
  }
  final errs = <String>[];
  for (final k in const ['adjectives', 'avoids']) {
    final v = val[k];
    if (v != null && (v is! List || v.any((x) => x is! String))) {
      errs.add('direction: $k must be a list of strings');
    }
  }
  return errs;
}

List<String> _validateLayoutTemplate(Object? val) {
  // Shape-check a layoutTemplate value. Membership in the closed lists is the
  // schema's job (enums); here we guard the structure the brief renderer relies
  // on.
  if (val is! Map) {
    return [
      'layoutTemplate: value must be an object '
          '{category, archetype, areas, containers} '
          '(copied verbatim from layout_templates.json)'
    ];
  }
  final errs = <String>[];
  for (final req in const ['category', 'archetype', 'areas', 'containers']) {
    if (!val.containsKey(req)) {
      errs.add("layoutTemplate: value is missing '$req'");
    }
  }
  final areas = val['areas'];
  if (areas is! Map) {
    errs.add('layoutTemplate: areas must be an object keyed by rung');
  } else {
    for (final rung in const ['compact', 'medium', 'expanded']) {
      final rows = areas[rung];
      if (rows is! List || rows.any((r) => r is! String)) {
        errs.add('layoutTemplate: areas.$rung must be a list of '
            'grid-template-areas row strings');
      }
    }
  }
  if (val['containers'] is! Map) {
    errs.add('layoutTemplate: containers must be an object '
        '(named container -> {type, hints})');
  }
  return errs;
}

// ----------------------------------------------------------- naming (derived)

/// comp = PascalCase(shell) + PascalCase(short), the declare-structure
/// convention (shop.cart -> ShopCart). Purely mechanical; not design.
String deriveComp(String surfaceId) {
  final m = _idRe.firstMatch(surfaceId);
  if (m == null) {
    throw ArgumentError("cannot derive comp from malformed id '$surfaceId'");
  }
  return _cap(m.group(1)!) + _cap(m.group(2)!);
}

/// route = '/' + short segment (portalo.product -> /product). Purely
/// mechanical; an answers `route` key overrides per surface. Params
/// (/:id) are design's call, not intake's — intake names, never designs.
String deriveRoute(String surfaceId) {
  final m = _idRe.firstMatch(surfaceId);
  if (m == null) {
    throw ArgumentError("cannot derive route from malformed id '$surfaceId'");
  }
  return '/${m.group(2)!}';
}

String _cap(String seg) => seg[0].toUpperCase() + seg.substring(1);

// --------------------------------------------------------------- emission

/// Seed registry: one entry per elicited surface, surface ALWAYS null.
///
/// Keys are {id, label, shell, comp, route, surface} in that order, plus
/// ADDITIVE keys after `surface` when declared: `states`, `requiresAuth`,
/// `tab` (bottom-tab membership — the scaffolder's shell group). No entry
/// is invented and none is dropped: `out.length == answers['surfaces'].length`.
/// The keys [emitRegistry] OWNS. Anything else present in an existing
/// registry.json was put there by a later stage and must survive a re-emit.
const registryEmittedKeys = [
  'id',
  'label',
  'shell',
  'comp',
  'route',
  'surface',
  'states',
  'statesProvenance',
  'requiresAuth',
  'tab',
  // Slice B1. These MUST be listed here, not just emitted: mergeRegistry
  // spreads the prior entry AFTER the emitted one for every key it does not
  // recognise, so an emitted-but-unlisted key would be overwritten by its own
  // stale value and re-emitting after an edit would silently keep the old
  // priority. `seedFromBrief` already carried both through from a hand-written
  // story-map table; this is the same two columns arriving via the wizard.
  'priority',
  'release',
];

/// Carry forward the registry fields emit does not own.
///
/// [emitRegistry] is a PURE function of the answers and must stay that way — it
/// may not invent a field nobody elicited, so it cannot emit `kits`. But
/// `intake emit` WRITES the file, and later stages add keys the answers have no
/// home for — `kits` above all. Writing the pure result straight over the file
/// therefore DELETED those keys with nothing to restore them from: the data
/// lived ONLY in the generated file. That is exactly what happened to portalo
/// (all 10 entries lost their kits), and gate_intake's own repair message tells
/// users to run this command — so the tool's advice destroyed data.
///
/// Merging here breaks no contract: this is the write step, not the pure step.
/// Emit's own keys always win; every foreign key is carried across per id.
List<Map<String, dynamic>> mergeRegistry(
    List<Map<String, dynamic>> emitted, String existingPath) {
  final f = File(existingPath);
  if (!f.existsSync()) return emitted;
  Map<String, Map<String, dynamic>> prior;
  try {
    final raw = jsonDecode(f.readAsStringSync());
    if (raw is! List) return emitted;
    prior = {
      for (final e in raw)
        if (e is Map && e['id'] is String)
          e['id'] as String: e.cast<String, dynamic>(),
    };
  } catch (_) {
    // A corrupt or hand-mangled registry must never block a re-emit. The pure
    // result is still correct; it just carries nothing forward.
    return emitted;
  }
  return [
    for (final entry in emitted)
      {
        ...entry,
        for (final kv in (prior[entry['id']] ?? const <String, dynamic>{}).entries)
          if (!registryEmittedKeys.contains(kv.key)) kv.key: kv.value,
      }
  ];
}

List<Map<String, dynamic>> emitRegistry(Map<String, dynamic> answers) {
  final out = <Map<String, dynamic>>[];
  final surfaces = answers['surfaces'];
  if (surfaces is! List) return out;
  for (final s in surfaces) {
    final surf = s as Map;
    final entry = <String, dynamic>{
      'id': surf['id'],
      'label': surf['label'],
      'shell': surf['shell'],
      'comp': deriveComp(surf['id'] as String),
      'route': surf['route'] ?? deriveRoute(surf['id'] as String),
      'surface': null, // intake names; design binds. Never non-null here.
    };
    // states: DECLARED wins, always. Only when the client said nothing do we
    // derive from shape — and then the entry says so, so the confirm step can
    // correct it (§22: intake elicits; derivation is legal only when marked).
    final states = surf['states'];
    if (states is List && states.isNotEmpty) {
      entry['states'] = states;
      entry['statesProvenance'] = surf['provenance'];
    } else {
      final derived = deriveStates(surf);
      if (derived.isNotEmpty) {
        entry['states'] = derived;
        entry['statesProvenance'] = 'inferred';
      }
      // No signal -> no key at all. `states` stays additive-only.
    }
    if (surf['requiresAuth'] == true) entry['requiresAuth'] = true;
    if (surf['tab'] == true) entry['tab'] = true;
    // priority/release: ADDITIVE columns, absent unless the client ranked the
    // surface. gate_intake reads only {id,label,shell,comp,route,surface}
    // (+states/requiresAuth/tab), so adding them cannot fail the gate. No
    // closed vocabulary is enforced: `seedFromBrief` accepts whatever a
    // hand-written story-map table says, and a wizard stricter than the brief
    // path would split the two front ends the "one engine" rule exists to keep
    // in step.
    if (surf['priority'] is String) entry['priority'] = surf['priority'];
    if (surf['release'] is String) entry['release'] = surf['release'];
    out.add(entry);
  }
  return out;
}

/// Emit the project's flows.json. Declared flows pass through (each edge
/// gains the default `action: 'push'`); when answers carry no flows group,
/// DERIVE one draft flow per shell — surfaces chained in declaration order,
/// provenance `inferred`, so the confirm step has something to confirm.
/// Deterministic: sorted shells, declaration order, no clock.
List<Map<String, dynamic>> emitFlows(Map<String, dynamic> answers) {
  final declared = answers['flows'];
  if (declared is List && declared.isNotEmpty) {
    return [
      for (final f in declared)
        <String, dynamic>{
          'id': f['id'],
          'name': f['name'],
          'provenance': f['provenance'],
          'edges': [
            for (final e in (f['edges'] as List))
              <String, dynamic>{
                // SPREAD, not an enumeration. Listing keys here is what silently
                // dropped `element` and `feedback`: both were validated and then
                // forgotten by this literal. Copying the edge means a key added
                // to `edgeKeys` cannot be lost by omission ever again. The
                // closed `edgeKeys` set is the other half — it refuses anything
                // unrecognised before it can ride along on this spread.
                ...(e as Map).cast<String, dynamic>(),
                // Re-assigning an existing key keeps its authored position, so
                // output order stays the author's and is stable per input.
                'action': e['action'] ?? 'push',
                // feedback: DECLARED wins and passes through untouched. Only a
                // mutation trigger with nothing declared gets a derived toast,
                // and that one carries `inferred: true` so the confirm step
                // can strike it (§22 — same rule as the derived flows below).
                // `element` needs no clause at all now: the spread carries it,
                // absent stays absent, and it is never derived (guessing which
                // button an edge fires is exactly what §22 forbids).
                ...?_edgeFeedback(e),
              },
          ],
        },
    ];
  }
  final surfaces = answers['surfaces'];
  if (surfaces is! List || surfaces.length < 2) return const [];
  final byShell = <String, List<String>>{};
  for (final s in surfaces) {
    final surf = s as Map;
    byShell.putIfAbsent(surf['shell'] as String, () => []).add(surf['id'] as String);
  }
  final shells = byShell.keys.toList()..sort();
  return [
    for (final shell in shells)
      if (byShell[shell]!.length > 1)
        <String, dynamic>{
          'id': 'flow-$shell',
          'name': '${_cap(shell)} journey',
          'provenance': 'inferred',
          'edges': [
            for (var i = 0; i + 1 < byShell[shell]!.length; i++)
              <String, dynamic>{
                'from': byShell[shell]![i],
                'to': byShell[shell]![i + 1],
                'trigger': 'continue',
                'action': 'push',
              },
          ],
        },
  ];
}

List<String> _block(String key, String title, Map<String, dynamic>? node) {
  // Render one brief section. An `inferred` field gets the visible mark;
  // client/founder provenance is noted quietly underneath (transparency, not
  // noise). The value is passed through verbatim — never rephrased.
  final lines = <String>['## $title', ''];
  if (node == null) {
    lines.add('_Not stated._');
    return lines;
  }
  final val = node['value'];
  final prov = node['provenance'];
  if (prov == 'inferred') {
    lines.add(inferredMark);
    lines.add('');
  }
  if (val is Map) {
    // Two object-valued fields: direction renders its adjectives/avoids,
    // layoutTemplate its grid areas. Everything else is a shape error the
    // validator has already named.
    lines.addAll(key == 'direction' ? _directionLines(val) : _layoutTemplateLines(val));
  } else if (val is List) {
    if (val.isNotEmpty) {
      for (final item in val) {
        lines.add('- ${mdEscape(item.toString())}');
      }
    } else {
      lines.add('_None stated._');
    }
  } else {
    lines.add(mdEscape(val.toString()));
  }
  lines.add('');
  lines.add('_provenance: ${prov}_');
  lines.add('');
  return lines;
}

List<String> _directionLines(Map val) {
  // Render a direction value: the adjectives to aim for and the anti-goals to
  // avoid, verbatim. Absent/empty lists are simply not rendered.
  final out = <String>[];
  final adjectives = val['adjectives'];
  if (adjectives is List && adjectives.isNotEmpty) {
    out.add('- adjectives: ${adjectives.map((x) => mdEscape(x.toString())).join(', ')}');
  }
  final avoids = val['avoids'];
  if (avoids is List && avoids.isNotEmpty) {
    out.add('- avoids: ${avoids.map((x) => mdEscape(x.toString())).join(', ')}');
  }
  if (out.isEmpty) out.add('_None stated._');
  return out;
}

List<String> _layoutTemplateLines(Map val) {
  // Render a layoutTemplate value readably: category, archetype, the
  // grid-template-areas per rung of the viewport ladder, and the named
  // containers. The value is passed through verbatim — never reworded.
  final out = <String>[
    '- category: ${mdEscape('${val['category']}')}',
    '- archetype: ${mdEscape('${val['archetype']}')}',
    '',
  ];
  final areas = val['areas'];
  if (areas is Map) {
    out.add('Grid template areas per rung (viewport ladder):');
    out.add('');
    for (final rung in const ['compact', 'medium', 'expanded']) {
      final rows = areas[rung];
      if (rows is! List || rows.isEmpty) continue;
      out.add('$rung:');
      out.add('```');
      for (final row in rows) {
        out.add('"${mdEscape(row.toString())}"');
      }
      out.add('```');
      out.add('');
    }
  }
  final containers = val['containers'];
  if (containers is Map && containers.isNotEmpty) {
    out.add('Named containers:');
    out.add('');
    for (final entry in containers.entries) {
      final name = entry.key;
      final meta = entry.value;
      final safeName = mdEscape(name.toString());
      if (meta is Map) {
        final ctype = mdEscape((meta['type'] ?? '').toString());
        final hints = mdEscape((meta['hints'] ?? '').toString());
        if (hints.isNotEmpty) {
          out.add('- `$safeName` — $ctype: $hints');
        } else {
          out.add('- `$safeName` — $ctype');
        }
      } else {
        out.add('- `$safeName` — ${mdEscape('$meta')}');
      }
    }
    out.add('');
  }
  return out;
}

/// Neutralize CLIENT-SUPPLIED strings before they land in generated
/// markdown (brief.md, the PRD, ADRs, the unified chain brief). Markdown has
/// no boundary between "content" and "markup", so an elicited value carrying
/// a script tag, a [link](url), **emphasis**, a table pipe or a newline
/// would otherwise become active document structure the moment anyone
/// renders the artifact. The escape is a NO-OP on benign prose: only the
/// characters markdown/HTML treat as syntax are touched, via backslash
/// escapes (CommonMark renders those as the literal character) and HTML
/// entities for angle brackets. Newlines/tabs flatten to spaces — a client
/// string is inline content, never new document structure.
String mdEscape(String s) {
  if (s.isEmpty) return s;
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x5C: // \ — escape it or a smuggled escape would mask the next char
        b.write(r'\\');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x5B:
        b.write(r'\[');
      case 0x5D:
        b.write(r'\]');
      case 0x60: // backtick — code spans
        b.write('\\`');
      case 0x2A:
        b.write(r'\*');
      case 0x7C:
        b.write(r'\|');
      case 0x09: // tab
      case 0x0A: // \n
      case 0x0D: // \r
        b.write(' ');
      default:
        b.write(String.fromCharCode(r));
    }
  }
  return b.toString();
}

/// Render the intake brief sections (the `## Title` blocks in `_fieldTitles`
/// order, provenance marks included) as lines. Public so the intake →
/// story-map chain (story_map.dart `renderBrief(answers:)`) can emit the
/// UNIFIED brief without duplicating this logic.
List<String> renderBriefSections(Map<String, dynamic> answers) {
  final lines = <String>[];
  for (final (key, title) in _fieldTitles) {
    lines.addAll(_block(key, title, _asNode(answers[key])));
  }
  return lines;
}

/// Render the brief markdown. Every `inferred` field is visibly marked; the
/// header states the rule once. No prose is generated beyond section scaffolding
/// and the provenance notes — field VALUES come straight from the answers.
String emitBrief(Map<String, dynamic> answers) {
  final productNode = answers['product'];
  final product = (productNode is Map && productNode['value'] != null)
      ? productNode['value'].toString()
      : '(unnamed product)';
  final lines = <String>[
    '# ${mdEscape(product)} — design brief',
    '',
    '> Emitted by arxa-intake from elicited answers.',
    '> **Intake elicits; it does not generate** (architecture §22).',
    '> Fields marked **[inferred]** were not stated by the client and MUST',
    '> be confirmed before design consumes this brief.',
    '',
  ];
  lines.addAll(renderBriefSections(answers));

  // surface inventory — the registry seed (surface null everywhere)
  final surfaces = answers['surfaces'];
  final surfaceList = surfaces is List ? surfaces : const [];
  final hasSurfaces = surfaceList.isNotEmpty;
  lines.add('## Surface inventory — the registry seed');
  lines.add('');
  if (!hasSurfaces) {
    lines.add('_No surfaces named at intake. The designer authors the registry._');
  } else {
    lines.add('| id | shell | comp | label | states | surface |');
    lines.add('|---|---|---|---|---|---|');
    for (final s in surfaceList) {
      final surf = s as Map;
      // A derived states cell is marked [inferred] so the confirm step has
      // something to confirm — declared states are shown bare.
      final states = surf['states'];
      final String statesCell;
      if (states is List && states.isNotEmpty) {
        statesCell = states.map((x) => mdEscape(x.toString())).join(', ');
      } else {
        final derived = deriveStates(surf);
        statesCell = derived.isEmpty ? '' : '${derived.join(', ')} [inferred]';
      }
      // F1: label and states are CLIENT strings — a pipe/backtick/newline
      // in them would break the table the gate parses. ids/shell/comp are
      // grammar-constrained (mdEscape is a no-op on them).
      lines.add('| `${mdEscape('${surf['id']}')}` | ${mdEscape('${surf['shell']}')} | '
          '${deriveComp(surf['id'] as String)} | ${mdEscape('${surf['label']}')} | $statesCell | _null_ |');
    }
    lines.add('');
    lines.add('Every `surface` is `null` — intake names what the client asked for; '
        'design binds a surface to each.');
  }
  lines.add('');
  lines.addAll(_feedbackSection(answers));
  return lines.join('\n');
}

/// Render the transition-feedback table: every edge that carries a toast,
/// declared or derived. It is a SEPARATE section from the surface inventory
/// because feedback is the other axis — a consequence of a transition, not a
/// way a screen can look (D2). Derived rows are marked `[inferred]`.
/// Deterministic: flows and edges in declaration order, no clock.
List<String> _feedbackSection(Map<String, dynamic> answers) {
  final rows = <String>[];
  for (final f in emitFlows(answers)) {
    for (final e in (f['edges'] as List)) {
      final fb = e['feedback'];
      if (fb is! Map) continue;
      final mark = fb['inferred'] == true ? ' [inferred]' : '';
      // F1: flow id + feedback text are client strings; from/to are
      // grammar-checked surface ids (escape is a no-op there).
      rows.add('| `${mdEscape('${f['id']}')}` | `${mdEscape('${e['from']}')}` → `${mdEscape('${e['to']}')}` | '
          '${fb['kind']} | ${mdEscape('${fb['text']}')}$mark |');
    }
  }
  if (rows.isEmpty) return const [];
  return [
    '## Transition feedback — the other axis',
    '',
    'A toast is a consequence of a TRANSITION, not a way a screen can look, so',
    'it lives on the flow edge and never in `states`.',
    '',
    '| flow | edge | kind | text |',
    '|---|---|---|---|',
    ...rows,
    '',
  ];
}

Map<String, dynamic>? _asNode(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

// ----------------------------------------------------- hand-written brief (10.7)

/// Plan 10.7: a hand-written brief is valid input. Derive the registry seed from
/// its surface-inventory table WITHOUT rewriting the brief. Rows whose first
/// (id) cell matches the `<shell>.<short>` pattern become seed entries; surface
/// is null. A brief with no such table yields an empty seed and that is NOT an
/// error — intake is optional.
List<Map<String, dynamic>> seedFromBrief(String md) {
  final seed = <Map<String, dynamic>>[];
  var inTable = false;
  var headerIdx = <String, int>{};
  for (final line in md.split(RegExp(r'\r\n|\r|\n'))) {
    final stripped = line.trim();
    final isRow = stripped.startsWith('|') &&
        stripped.endsWith('|') &&
        stripped.length > 2 &&
        stripped.substring(1, stripped.length - 1).contains('|');
    if (!isRow) {
      inTable = false;
      continue;
    }
    final cells = _stripAll(stripped, '|')
        .split(_tableSplit)
        .map((c) => _stripAll(c.trim(), '`'))
        .toList();
    // separator row (|---|---|)
    if (cells.every(_isSeparatorCell)) {
      continue;
    }
    if (!inTable) {
      // this row is a header; remember column positions
      headerIdx = {};
      for (var i = 0; i < cells.length; i++) {
        if (cells[i].isNotEmpty) {
          headerIdx[cells[i].toLowerCase()] = i;
        }
      }
      inTable = true;
      continue;
    }
    final idCol = headerIdx['id'] ?? 0;
    if (idCol >= cells.length) continue;
    final sid = cells[idCol].trim();
    final m = _idRe.firstMatch(sid);
    if (m == null) continue;
    final shell = m.group(1)!;
    final short = m.group(2)!;
    final labelCol = headerIdx['label'];
    final label = (labelCol != null && labelCol < cells.length)
        ? cells[labelCol].trim()
        : _cap(short);
    final entry = <String, dynamic>{
      'id': sid,
      'label': label.isNotEmpty ? label : _cap(short),
      'shell': shell,
      'comp': deriveComp(sid),
      'route': deriveRoute(sid),
      'surface': null,
    };
    // additive sibling metadata (never woven into the four required fields):
    // optional columns pass through — arxa-story-mapper emits priority/release,
    // intake's surface inventory emits states.
    for (final opt in const ['priority', 'release', 'states']) {
      final col = headerIdx[opt];
      if (col != null && col < cells.length) {
        final val = cells[col].trim();
        if (val.isNotEmpty) entry[opt] = val;
      }
    }
    seed.add(entry);
  }
  // de-dup keeping first, preserving order
  final seen = <String>{};
  final deduped = <Map<String, dynamic>>[];
  for (final e in seed) {
    final id = e['id'] as String;
    if (seen.contains(id)) continue;
    seen.add(id);
    deduped.add(e);
  }
  return deduped;
}

// ----------------------------------------------------------------- results

/// Outcome of [IntakeEngine.validate] (and [validateIntake]).
class ValidationResult {
  const ValidationResult(this.errors);
  final List<String> errors;
  bool get ok => errors.isEmpty;
}

/// Outcome of [IntakeEngine.emit].
class EmitResult {
  EmitResult.ok({
    required this.briefPath,
    required this.registryPath,
    required this.entries,
    required this.inferredCount,
    this.flowsPath,
  })  : ok = true,
        errors = const [];
  EmitResult.failure(this.errors)
      : ok = false,
        briefPath = null,
        registryPath = null,
        flowsPath = null,
        entries = 0,
        inferredCount = 0;

  final bool ok;
  final List<String> errors;
  final String? briefPath;
  final String? registryPath;
  final String? flowsPath;
  final int entries;
  final int inferredCount;
}

/// Outcome of [IntakeEngine.seed].
class SeedResult {
  const SeedResult(this.registry, {this.registryPath});
  final List<Map<String, dynamic>> registry;
  final String? registryPath;
  int get entries => registry.length;
}

// ----------------------------------------------------------------- engine

/// The intake engine: validate / emit / seed. Stateless; a `const` instance.
/// The rendering ([emitBrief]/[emitRegistry]/[seedFromBrief]) is a pure function
/// of its input; this class adds the file IO and default-path resolution.
class IntakeEngine {
  const IntakeEngine();

  ValidationResult validate(Map<String, dynamic> answers) => validateIntake(answers);

  /// Turn validated [answers] into brief.md + registry.json (+ flows.json
  /// when [project] is given). On invalid input, writes nothing and returns
  /// [EmitResult.failure] (no partial artefacts).
  /// Paths fall back to `INTAKE_BRIEF_OUT`/`INTAKE_REGISTRY_OUT` then to
  /// [defaultBriefOut]/[defaultRegistryOut]. With [project], ALL outputs
  /// land in `~/.arxa/projects/<project>/intake/` — answers.json (the
  /// input, verbatim), brief.md, registry.json, flows.json.
  EmitResult emit(
    Map<String, dynamic> answers, {
    String? briefOut,
    String? registryOut,
    String? project,
  }) {
    final errs = validateIntake(answers).errors;
    if (errs.isNotEmpty) return EmitResult.failure(errs);
    const json = JsonEncoder.withIndent('  ');
    String? flowsPath;
    final String briefPath;
    final String registryPath;
    if (project != null) {
      if (!validProjectName(project)) {
        return EmitResult.failure(['project: bad name "$project"']);
      }
      ensureProject(project);
      final dir = shellDir(project, 'intake');
      briefPath = '$dir/brief.md';
      registryPath = '$dir/registry.json';
      flowsPath = '$dir/flows.json';
      _write('$dir/answers.json', '${json.convert(answers)}\n');
      _write(flowsPath, '${json.convert(emitFlows(answers))}\n');
      // Slice B1 — four more project-shell artifacts, all pure functions of the
      // same answers (see intake_artifacts.dart). They are written ONLY on the
      // --project path: the legacy design-root path has no shell to put them
      // in, and scattering them next to a repo registry.json would give the
      // studio two sources for the same document.
      //
      // map.json goes through mergeStoryMap for the same reason registry.json
      // goes through mergeRegistry: its `statuses` are authored in the studio
      // and live only in the generated file, so a straight overwrite would
      // delete them with nothing to restore from.
      _write('$dir/personas.json', '${json.convert(emitPersonas(answers))}\n');
      _write('$dir/map.json',
          '${json.convert(mergeStoryMap(emitStoryMap(answers), '$dir/map.json'))}\n');
      _write('$dir/moodboard.json', '${json.convert(emitMoodboard(answers))}\n');
      _write('$dir/direction.json', '${json.convert(emitDirection(answers))}\n');
      // The PRD is a SECOND rendering of the same answers, not a second source:
      // [emitPrd] reads exactly what [emitBrief] reads and invents nothing the
      // brief would not also carry. It exists because a brief and a PRD are
      // read by different people for different decisions, not because there is
      // more information — so a field nobody supplied becomes an open question
      // in it rather than a confident paragraph.
      _write('$dir/prd.md', emitPrd(answers));
      // ADRs, at last (task #67). The note that stood here said none could be
      // written because nothing in the pipeline records a decision. That was
      // true of the four sources it named — the kit registry catalogues kits
      // that exist rather than alternatives weighed, and nothing anywhere
      // selects one — but wrong about intake itself, which chooses on every
      // emit and threw the reason away: the draft flow decomposition, the
      // derived surface states, the derived edge toasts. Each already stamps
      // its output `inferred`, which is this engine declaring it chose without
      // being told; `decision_log.dart` now keeps the WHY alongside, read from
      // the same word sets the rules use so the reason cannot drift from the
      // rule that fired.
      //
      // A project that inferred nothing still writes an EMPTY decisions.json
      // and no `adr/` at all — [collectDecisions] returns `[]` and `emitAdrs`
      // renders nothing, which is the honest output rather than a gap.
      writeDecisionLog(dir, collectDecisions(answers));
      // Targets/locales wiring: the answers are the SSOT for what the project
      // builds and speaks — init-time flags are a pre-conversation guess. Emit
      // syncs settings ← answers so the designer's viewport ladder and l10n
      // can never disagree with intake. Partial: absent fields leave settings
      // untouched.
      final answerTargets = _fieldList(answers['targets']);
      final answerLocales = _fieldList(answers['locales']);
      if (answerTargets != null || answerLocales != null) {
        updateProjectSettings(project,
            targets: answerTargets, locales: answerLocales);
      }
    } else {
      // F2: with neither --project nor an explicit target, the legacy
      // default resolved to <repoRoot>/docs/design/brief.md — inside any
      // arxa repo that is a TRACKED file, and emit OVERWRITES, so a bare
      // `intake emit --answers f.json` silently destroyed it. Refuse; the
      // env var keeps scripted/legacy flows explicit rather than implicit.
      if (briefOut == null &&
          Platform.environment['INTAKE_BRIEF_OUT'] == null) {
        return EmitResult.failure([
          'refusing to emit with no output target: --project is absent and '
          '--brief-out is unset, and the default path would silently '
          'overwrite ${defaultBriefOut()}. Pass --project <name> '
          '(recommended — projects live in ~/.arxa), or --brief-out <path> '
          '(+ --registry-out <path>), or set INTAKE_BRIEF_OUT to opt back '
          'into the default path.',
        ]);
      }
      briefPath = briefOut ?? defaultBriefOut();
      registryPath = registryOut ?? defaultRegistryOut();
    }
    _write(briefPath, emitBrief(answers));
    _write(registryPath,
        '${json.convert(mergeRegistry(emitRegistry(answers), registryPath))}\n');
    return EmitResult.ok(
      briefPath: briefPath,
      registryPath: registryPath,
      flowsPath: flowsPath,
      entries: (answers['surfaces'] is List) ? (answers['surfaces'] as List).length : 0,
      inferredCount: _countInferred(answers),
    );
  }

  /// Flip one flow's provenance to client/founder in the project's
  /// flows.json (the confirm half of derive + confirm). Returns the error
  /// string, or null on success.
  ///
  /// DUAL-WRITE. answers.json is the SSOT and flows.json is regenerated from
  /// it by `emitFlows`, so writing only flows.json means the next emit REVERTS
  /// the confirmation. Persisting the confirmed list back as `answers.flows`
  /// is what makes it stick — and it is safe to persist EMITTED flows because
  /// `emitFlows` is idempotent over its own output (the spread carries every
  /// key, `action` is already defaulted, and a declared feedback suppresses
  /// derivation).
  String? confirmFlow(String project, String flowId, String as) {
    if (!['client', 'founder'].contains(as)) {
      return "confirmFlow: as must be client|founder, got '$as'";
    }
    final path = '${shellDir(project, 'intake')}/flows.json';
    final f = File(path);
    if (!f.existsSync()) return 'confirmFlow: no flows.json at $path';
    final flows = jsonDecode(f.readAsStringSync());
    if (flows is! List) return 'confirmFlow: $path is not a flows list';
    var found = false;
    for (final flow in flows) {
      if (flow is Map && flow['id'] == flowId) {
        flow['provenance'] = as;
        found = true;
      }
    }
    if (!found) return "confirmFlow: no flow '$flowId' in $path";
    const json = JsonEncoder.withIndent('  ');
    // Back into the SSOT, or the next emit undoes what we just wrote. Validate
    // BEFORE either write: refusing here after flows.json was already updated
    // would leave the two files diverged — the exact failure this dual-write
    // exists to close. Invalid answers also make the next emit write NOTHING,
    // which is worse than the revert.
    final answersPath = '${shellDir(project, 'intake')}/answers.json';
    final af = File(answersPath);
    Map<String, dynamic>? answers;
    if (af.existsSync()) {
      final decoded = jsonDecode(af.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        decoded['flows'] = flows;
        final errs = validateIntake(decoded).errors;
        if (errs.isNotEmpty) {
          return 'confirmFlow: confirming would make $answersPath invalid — '
              '${errs.first}';
        }
        answers = decoded;
      }
    }
    _write(path, '${json.convert(flows)}\n');
    if (answers != null) _write(answersPath, '${json.convert(answers)}\n');
    return null;
  }

  /// Derive registry.json from a HAND-WRITTEN brief's surface table (10.7),
  /// without rewriting the brief.
  SeedResult seed(String briefPath, {String? registryOut}) {
    final md = File(briefPath).readAsStringSync();
    final registry = seedFromBrief(md);
    final out = registryOut ?? defaultRegistryOut();
    _write(out, '${const JsonEncoder.withIndent('  ').convert(registry)}\n');
    return SeedResult(registry, registryPath: out);
  }
}

int _countInferred(Map<String, dynamic> answers) {
  var n = 0;
  for (final (key, _) in _fieldTitles) {
    final node = answers[key];
    if (node is Map && node['provenance'] == 'inferred') n++;
  }
  final surfaces = answers['surfaces'];
  if (surfaces is List) {
    for (final s in surfaces) {
      if (s is Map && s['provenance'] == 'inferred') n++;
    }
  }
  return n;
}

// ----------------------------------------------------------------- io + paths

/// The list value of an answers field ({value: [...], provenance}), or null
/// when the field is absent/malformed — used for the settings sync only.
List<String>? _fieldList(dynamic field) {
  if (field is! Map) return null;
  final value = field['value'];
  if (value is! List) return null;
  return value.whereType<String>().toList();
}

String defaultBriefOut() =>
    Platform.environment['INTAKE_BRIEF_OUT'] ?? '${repoRoot()}/docs/intake/brief.md';

/// Default registry output: the GATE's canonical path, not the legacy
/// docs/design/ one (which the gate never reads). This is a deliberate
/// divergence from the Python emit. Mirrors `_resolveRegistry` in
/// gate_intake.dart — keep them in step; intake.dart does NOT import the gate.
String defaultRegistryOut() {
  final env = Platform.environment['INTAKE_REGISTRY_OUT'];
  if (env != null) return env;
  final root = repoRoot();
  // Same canonical default as GateContext.studioDesignDir (gates.dart) —
  // deliberately NOT imported from there (see the doc above); keep in step.
  // v2 design (canonical): intake/registry.json is the single AUTHORING
  // surface (composers write it; models/screens_model/registry.json is a
  // derived projection) — the intake emitter is a composer, so its output
  // lands at the authoring surface, never the projection (the v1 clobber
  // path). v1 trees keep the legacy models/screens_model behavior.
  var designRoot = '$root/designs/arxa-studio-v2';
  var rel = 'intake/registry.json';
  if (!Directory(designRoot).existsSync()) {
    // v1 tree (retained reference): registry under models/screens_model.
    designRoot = '$root/designs/arxa-studio';
    rel = 'models/screens_model/registry.json';
  }
  if (!Directory(designRoot).existsSync()) {
    // No design root yet (pre-scaffold) — the client-repo fallback.
    return '$root/docs/intake/registry.json';
  }
  final struct = File('$designRoot/structure.json');
  if (struct.existsSync()) {
    try {
      final data = jsonDecode(struct.readAsStringSync());
      if (data is Map &&
          data['registry'] is String &&
          (data['registry'] as String).isNotEmpty) {
        rel = data['registry'] as String;
      }
    } catch (_) {
      // keep default on parse error (same as the gate)
    }
  }
  return '$designRoot/$rel';
}

/// Repo root: walk up from the cwd for `config/arxa.config.json` (the same
/// discovery `arxa` uses), falling back to the cwd.
String repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/config/arxa.config.json').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}

void _write(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

// ----------------------------------------------------------------- helpers

/// Strip all leading/trailing occurrences of [ch] (Python str.strip).
String _stripAll(String s, String ch) {
  final unit = ch.codeUnitAt(0);
  var start = 0, end = s.length;
  while (start < end && s.codeUnitAt(start) == unit) {
    start++;
  }
  while (end > start && s.codeUnitAt(end - 1) == unit) {
    end--;
  }
  return s.substring(start, end);
}

bool _isSeparatorCell(String c) {
  if (c.isEmpty) return false;
  for (final ch in c.split('')) {
    if (!_sepChars.contains(ch)) return false;
  }
  return true;
}

/// Python type names for JSON values, so error strings match the .py.
String _pyTypeName(Object? v) {
  if (v == null) return 'NoneType';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is double) return 'float';
  if (v is String) return 'str';
  if (v is List) return 'list';
  if (v is Map) return 'dict';
  return v.runtimeType.toString();
}
