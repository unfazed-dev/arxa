/// Remote pipeline control from the paired phone (12.6).
///
/// The companion drives the pipeline over the paired channel — run a phase,
/// fetch findings (SARIF), reach a human gate. The load-bearing security
/// property of this whole feature: **a phone approval by the human IS a valid
/// approval; an agent's is NOT.**
///
/// Provenance, not transport, enforces this. Every gate approval carries the
/// paired device's id, and [approveGate] honors it ONLY if that id is in the
/// desktop's revocable paired-device list ([PairingSession.pairedDevices]). An
/// agent has no paired device — it never passed the human confirm dialog — so
/// its approval is rejected here, whatever else it presents. Revoking the device
/// ([PairingSession.revoke]) drops the approval capability immediately.
///
/// **"Reach but never pass":** the phone can navigate the pipeline up to a
/// pending gate and SEE it ([canReach]), but only [approveGate] from a paired
/// device advances past it. The gate is the human checkpoint; the phone is the
/// human's remote presence at it — it cannot mint an approval the human did not
/// make.
class PipelineControl {
  /// Returns true iff [deviceId] is a currently-paired device. Injected so this
  /// class has no live dependency on [PairingSession] — the test injects a fixed
  /// set, the desktop injects `session.pairedDevices`-backed lookup.
  final bool Function(String deviceId) _isPairedDevice;

  PipelineControl(this._isPairedDevice);

  /// A paired device may navigate the pipeline, fetch findings, and reach a
  /// gate. An unpaired requester (an agent, or a revoked device) may not even
  /// reach — it gets nothing.
  bool canReach(String deviceId) => _isPairedDevice(deviceId);

  /// Approve a human gate. This is the ONLY path that passes a gate, and it is
  /// honored exclusively for a paired device — the human approving remotely via
  /// their phone. An agent's approval is [GateApproval.denied].
  ///
  /// [deviceName] is recorded for the audit log (who approved) but is NOT the
  /// trust anchor — [deviceId] is, via [_isPairedDevice]. A forged deviceName
  /// with no paired id changes nothing.
  GateApproval approveGate(HumanGate gate, String deviceId, {String? deviceName}) {
    if (!_isPairedDevice(deviceId)) {
      return GateApproval.denied(
        gate,
        'gate approvals require a paired device — an agent is not the human (12.6)',
      );
    }
    return GateApproval.approved(gate, deviceId, deviceName: deviceName);
  }
}

/// The three human gates the phone can reach but only the human can pass
/// (mirrors pipeline.sh: HG1 design/prototype, HG2 review, HG3 deploy).
enum HumanGate { design, review, deploy }

/// The outcome of a gate-approval attempt. Never a bare bool — a denial must
/// carry the reason so the companion UI states *why* (and an audit log records
/// the rejection), and an approval records *who* (the paired device).
class GateApproval {
  final HumanGate gate;
  final bool approved;
  final String? deviceId;
  final String? deviceName;
  final String? deniedReason;

  const GateApproval.approved(this.gate, this.deviceId, {this.deviceName})
      : approved = true,
        deniedReason = null;

  const GateApproval.denied(this.gate, this.deniedReason)
      : approved = false,
        deviceId = null,
        deviceName = null;

  bool get isDenied => !approved;

  @override
  String toString() => approved
      ? 'GateApproval($gate approved by $deviceId)'
      : 'GateApproval($gate DENIED: $deniedReason)';
}
