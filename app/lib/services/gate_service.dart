/// The three human gates (8.11 / done-when #6).
///
/// Design approval (gate 1), build approval (gate 2), ship confirm (gate 3 — the
/// strictest; names target+version+account and requires confirming that exact
/// triple). An agent may reach a gate and stop; it can **never** mint an
/// approval token. The agent-side API ([markReached]) only records that the gate
/// was reached — it sets status to [GateStatus.pending], never approved. Only
/// the human-side [approve*] methods mint approval, and they require a human
/// gesture (the confirmation value / triple the agent cannot supply).
enum GateId { design, build, ship }
enum GateStatus { pending, approved }

class GateState {
  final GateId id;
  GateStatus status;
  GateState(this.id) : status = GateStatus.pending;
  bool get isApproved => status == GateStatus.approved;
}

/// What ship.confirm requires the human to retype exactly (gate 3).
class ShipTriple {
  final String target;
  final String version;
  final String account;
  const ShipTriple(this.target, this.version, this.account);
}

class GateService {
  final _gates = {
    for (final id in GateId.values) id: GateState(id),
  };

  /// The ship triple the project declared (set when a project is frozen).
  ShipTriple? declaredShipTriple;

  GateStatus statusOf(GateId id) => _gates[id]!.status;
  bool get allDesignApproved => _gates[GateId.design]!.isApproved;
  bool get allBuildApproved => _gates[GateId.build]!.isApproved;
  bool get allShipApproved => _gates[GateId.ship]!.isApproved;

  /// Agent-side: record that the agent reached this gate and stopped.
  /// Deliberately does NOT approve — there is no agent API that mints a token.
  void markReached(GateId id) {
    _gates[id]!.status = GateStatus.pending;
  }

  /// Human-side (gate 1): approve the chosen design direction.
  void approveDesign() {
    _gates[GateId.design]!.status = GateStatus.approved;
  }

  /// Human-side (gate 2): approve the build for ship.
  void approveBuild() {
    _gates[GateId.build]!.status = GateStatus.approved;
  }

  /// Human-side (gate 3 — strictest): confirm the exact target+version+account
  /// triple. Returns false unless the retyped triple matches the declared one,
  /// so a guess or an agent-supplied value cannot pass.
  bool confirmShip(ShipTriple retyped) {
    final declared = declaredShipTriple;
    if (declared == null) return false;
    final match = declared.target == retyped.target &&
        declared.version == retyped.version &&
        declared.account == retyped.account;
    if (match) {
      _gates[GateId.ship]!.status = GateStatus.approved;
    }
    return match;
  }

  /// Reset (new project / re-run). Used by the surface layer.
  void reset() {
    for (final g in _gates.values) {
      g.status = GateStatus.pending;
    }
    declaredShipTriple = null;
  }
}
