/// Fires a notification when a gate verdict transitions to FAIL (12.12).
///
/// The companion subscribes to the desktop's gate verdicts over the paired
/// channel and calls [report] each time it observes one. This feed fires
/// [onGateRed] exactly on the transition INTO red — a gate that STAYS red
/// across polls does not re-fire (one notification per transition, not per
/// heartbeat). The failure mode this prevents: a chatty notification every
/// heartbeat while a gate stays broken, which trains the human to dismiss them.
///
/// A gate recovering (red → green) and then failing again DOES re-fire — that
/// is a fresh regression and the human should hear about it.
class GateStatusFeed {
  GateStatusFeed(void Function(GateRedNotification)? onGateRed)
      : _onGateRed = onGateRed;

  final void Function(GateRedNotification)? _onGateRed;

  /// Last observed pass/fail per gate. Absent = unseen (a brand-new gate failing
  /// for the first time fires; a gate already red at subscribe does too — the
  /// human learns the gate is red once, not never).
  final Map<String, bool> _lastPassed = {};

  /// Observe a gate verdict. [gate] is the gate name; [passed] is its verdict.
  /// Fires [onGateRed] iff this is a transition INTO red.
  void report(String gate, bool passed) {
    final was = _lastPassed[gate];
    _lastPassed[gate] = passed;
    // Fire when transitioning TO red: previously passing OR never seen.
    // Staying red (was == false) does not re-fire.
    if (!passed && was != false) {
      _onGateRed?.call(GateRedNotification(gate: gate, firstSeen: was == null));
    }
  }

  /// Forget a gate's state (e.g. on a fresh pipeline run). The next [report]
  /// for it is treated as first-seen again.
  void reset() => _lastPassed.clear();
}

/// A gate went red. [firstSeen] distinguishes "this gate was red when we first
/// looked" from "this gate just regressed from green" — both notify, but the
/// wording differs (the human cares whether it's a new break or a known one).
class GateRedNotification {
  const GateRedNotification({required this.gate, required this.firstSeen});
  final String gate;
  final bool firstSeen;

  @override
  String toString() => 'GateRedNotification($gate${firstSeen ? ' (first seen)' : ' (regressed)'})';
}
