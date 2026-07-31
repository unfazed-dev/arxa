// pipeline_fsm — pipeline state machine: init, advance, approve, review.
//
// Ports the FSM logic from the archived pipeline/pipeline.sh (lines 152-564).
// State lives in pipeline/state/default.state.json. Run audit trail in
// pipeline/state/runs.jsonl. Both are gitignored runtime state.
//
// The FSM phases (in order): intake → prototype → design → scaffold →
// review → build → deploy. Each phase maps to one or more gates (see
// phases.dart phaseGates). The FSM tracks whether each phase's gate passed,
// whether the human gates (prototype approval, review verdict) are met,
// and whether the tree is dirty (code changed since last review approval).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Phases in FSM order.
const fsmPhases = [
  'intake',
  'prototype',
  'design',
  'scaffold',
  'review',
  'build',
  'deploy',
];

/// Path to the state file under [repoRoot].
String _statePath(String repoRoot) =>
    p.join(repoRoot, 'pipeline', 'state', 'default.state.json');

/// Path to the runs audit log.
String _runsPath(String repoRoot) =>
    p.join(repoRoot, 'pipeline', 'state', 'runs.jsonl');

/// Read the full state map. Returns null if no state file exists.
Map<String, dynamic>? readState(String repoRoot) {
  final file = File(_statePath(repoRoot));
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } on FormatException {
    return null;
  }
}

/// Write the state map atomically (write-then-rename).
void _writeState(String repoRoot, Map<String, dynamic> state) {
  state['updatedAt'] = DateTime.now().toUtc().toIso8601String();
  final file = File(_statePath(repoRoot));
  file.parent.createSync(recursive: true);
  final tmp = File('${file.path}.tmp');
  tmp.writeAsStringSync('${JsonEncoder.withIndent('  ').convert(state)}\n');
  tmp.renameSync(file.path);
}

/// Append one line to the runs audit log.
void _appendRun(String repoRoot, Map<String, dynamic> entry) {
  final file = File(_runsPath(repoRoot));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
}

String _now() => DateTime.now().toUtc().toIso8601String();

// ── init ───────────────────────────────────────────────────────────

/// Create fresh pipeline state (phase=intake, all gates ready/blocked).
/// Overwrites any existing state.
Map<String, dynamic> initPipeline(String repoRoot, {List<String>? targets}) {
  final phaseStatus = <String, Map<String, dynamic>>{};
  for (var i = 0; i < fsmPhases.length; i++) {
    phaseStatus[fsmPhases[i]] = {
      'status': i == 0 ? 'ready' : 'blocked',
      'ts': null,
      'attempts': 0,
    };
  }

  final state = <String, dynamic>{
    'phase': fsmPhases[0],
    'targets': targets ?? ['macos'],
    'approvalTokens': <String, String>{},
    'designHash': '',
    'kitSha': '',
    'schema': 4,
    'createdAt': _now(),
    'dirty': false,
    'phaseStatus': phaseStatus,
    'humanApproved': <String, bool>{},
    'review': {'approved': false, 'rejections': 0},
  };
  _writeState(repoRoot, state);

  _appendRun(repoRoot, {
    'ts': _now(),
    'phase': fsmPhases[0],
    'action': 'init',
    'result': 'ok',
  });

  return state;
}

// ── record gate result ─────────────────────────────────────────────

/// Record the result of running a phase's gate. Sets phase status to
/// passed/failed, bumps attempts, and appends to runs.jsonl.
void recordPhaseStatus(
  String repoRoot,
  String phase,
  bool passed, {
  int? exitCode,
  String? failingSig,
}) {
  final state = readState(repoRoot);
  if (state == null) return;

  final statuses =
      (state['phaseStatus'] as Map<String, dynamic>?) ?? {};
  final ps = (statuses[phase] as Map<String, dynamic>?) ?? {};
  ps['status'] = passed ? 'passed' : 'failed';
  ps['ts'] = _now();
  ps['attempts'] = ((ps['attempts'] as num?) ?? 0).toInt() + 1;
  statuses[phase] = ps;
  state['phaseStatus'] = statuses;

  _writeState(repoRoot, state);

  _appendRun(repoRoot, {
    'ts': _now(),
    'phase': phase,
    'action': 'gate',
    'result': passed ? 'passed' : 'failed',
    'exitCode': exitCode,
    'failingSignature': ?failingSig,
  });
}

// ── advance ────────────────────────────────────────────────────────

/// Advance to the next phase. Guards: current phase must be 'passed',
/// and 'prototype' requires human approval. Returns the new phase or null
/// if the guard fails.
String? advance(String repoRoot) {
  final state = readState(repoRoot);
  if (state == null) return null;

  final phase = state['phase'] as String? ?? '';
  final idx = fsmPhases.indexOf(phase);
  if (idx < 0 || idx >= fsmPhases.length - 1) return null; // at deploy or unknown

  // Guard: current phase gate must have passed.
  final statuses = (state['phaseStatus'] as Map<String, dynamic>?) ?? {};
  final ps = (statuses[phase] as Map<String, dynamic>?) ?? {};
  if (ps['status'] != 'passed') return null;

  // Guard: prototype requires human approval.
  if (phase == 'prototype') {
    final approved = (state['humanApproved'] as Map<String, dynamic>?) ?? {};
    if (approved['prototype'] != true) return null;
  }

  final next = fsmPhases[idx + 1];
  state['phase'] = next;
  final nextPs = (statuses[next] as Map<String, dynamic>?) ?? {};
  nextPs['status'] = 'ready';
  statuses[next] = nextPs;
  state['phaseStatus'] = statuses;

  _writeState(repoRoot, state);
  _appendRun(repoRoot, {
    'ts': _now(),
    'phase': next,
    'action': 'advance',
    'result': 'ok',
  });

  return next;
}

// ── human gates ────────────────────────────────────────────────────

/// Human Gate 1: approve the prototype (freeze) design.
/// Mints an approval token and marks the prototype as human-approved.
void approvePrototype(String repoRoot, {String? note}) {
  final state = readState(repoRoot);
  if (state == null) return;

  final tokens =
      (state['approvalTokens'] as Map<String, dynamic>?) ?? {};
  tokens['prototype'] = note ?? 'human-approved';
  state['approvalTokens'] = tokens;

  final approved = (state['humanApproved'] as Map<String, dynamic>?) ?? {};
  approved['prototype'] = true;
  state['humanApproved'] = approved;

  _writeState(repoRoot, state);
  _appendRun(repoRoot, {
    'ts': _now(),
    'phase': 'prototype',
    'action': 'approve',
    'result': 'ok',
    'note': ?note,
  });
}

/// Human Gate 2: review verdict. Approve marks the pipeline done-eligible.
/// Reject rewinds to the design phase and bumps rejections.
void reviewVerdict(String repoRoot, bool approve, {String? reason}) {
  final state = readState(repoRoot);
  if (state == null) return;

  final review = (state['review'] as Map<String, dynamic>?) ?? {};

  if (approve) {
    review['approved'] = true;
    state['dirty'] = false;
    _appendRun(repoRoot, {
      'ts': _now(),
      'phase': 'review',
      'action': 'review',
      'result': 'approved',
    });
  } else {
    review['approved'] = false;
    review['rejections'] = ((review['rejections'] as num?) ?? 0).toInt() + 1;
    // Rewind to design phase for rework.
    state['phase'] = 'design';
    final statuses =
        (state['phaseStatus'] as Map<String, dynamic>?) ?? {};
    final designPs = (statuses['design'] as Map<String, dynamic>?) ?? {};
    designPs['status'] = 'ready';
    statuses['design'] = designPs;
    state['phaseStatus'] = statuses;
    _appendRun(repoRoot, {
      'ts': _now(),
      'phase': 'review',
      'action': 'review',
      'result': 'rejected',
      'reason': ?reason,
    });
  }

  state['review'] = review;
  _writeState(repoRoot, state);
}

// ── dirty + done ───────────────────────────────────────────────────

/// Mark the pipeline dirty (code changed since last review approval).
/// Resets review.approved to false.
void markDirty(String repoRoot) {
  final state = readState(repoRoot);
  if (state == null) return;
  state['dirty'] = true;
  final review = (state['review'] as Map<String, dynamic>?) ?? {};
  review['approved'] = false;
  state['review'] = review;
  _writeState(repoRoot, state);
}

/// Is the pipeline done? Review approved and not dirty.
bool isDone(String repoRoot) {
  final state = readState(repoRoot);
  if (state == null) return false;
  final review = (state['review'] as Map<String, dynamic>?) ?? {};
  return review['approved'] == true && state['dirty'] != true;
}

/// Read the runs.jsonl audit trail. Returns empty list if no log exists.
List<Map<String, dynamic>> readRuns(String repoRoot) {
  final file = File(_runsPath(repoRoot));
  if (!file.existsSync()) return [];
  return file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
}
