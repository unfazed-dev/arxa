import 'package:app_box_companion/pipeline/gate_status_feed.dart';
import 'package:app_box_companion/pipeline/pipeline_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PipelineControl (12.6 — phone approval valid, agent not)', () {
    // A paired-device set the test controls. Revoking = removing an id.
    final paired = <String>{'dev-0001'};
    bool isPaired(String id) => paired.contains(id);
    final ctrl = PipelineControl(isPaired);

    test('a paired device can reach the pipeline', () {
      expect(ctrl.canReach('dev-0001'), isTrue);
    });

    test('a paired device approving a gate is recorded (the human, remotely)', () {
      final a = ctrl.approveGate(HumanGate.review, 'dev-0001', deviceName: 'iPhone');
      expect(a.approved, isTrue);
      expect(a.deviceId, 'dev-0001');
      expect(a.deviceName, 'iPhone');
    });

    // R5 NEGATIVE — the load-bearing invariant: an agent (no paired device) is
    // denied. If this ever passes for an agent, the whole security model falls.
    test('an unpaired agent cannot reach OR approve', () {
      expect(ctrl.canReach('agent-anon'), isFalse);
      final a = ctrl.approveGate(HumanGate.deploy, 'agent-anon');
      expect(a.approved, isFalse);
      expect(a.isDenied, isTrue);
      expect(a.deniedReason, contains('paired device'));
      expect(a.deniedReason, contains('agent is not the human'));
    });

    // R5 NEGATIVE — a forged deviceName does not bypass the id check. The id is
    // the trust anchor; the name is display/audit only.
    test('a forged deviceName with an unpaired id is still denied', () {
      final a = ctrl.approveGate(
        HumanGate.design,
        'agent-anon',
        deviceName: 'iPhone', // forged — claims to be a paired device
      );
      expect(a.approved, isFalse);
    });

    // R5 NEGATIVE — revoking the device drops approval capability immediately
    // (12.4 revocable list ↔ 12.6 approval). This is the cross-feature invariant.
    test('a revoked device can no longer approve', () {
      expect(ctrl.approveGate(HumanGate.review, 'dev-0001').approved, isTrue);
      paired.remove('dev-0001'); // revoke
      expect(ctrl.canReach('dev-0001'), isFalse);
      expect(ctrl.approveGate(HumanGate.review, 'dev-0001').approved, isFalse);
    });
  });

  group('GateStatusFeed (12.12 — gate-red push, deduped)', () {
    test('a passing→failing transition fires once', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('structure', true); // green — no fire
      expect(fired, isEmpty);
      feed.report('structure', false); // red — fire
      expect(fired, hasLength(1));
      expect(fired.single.gate, 'structure');
      expect(fired.single.firstSeen, isFalse); // we saw it green first
    });

    // R5 NEGATIVE — staying red does NOT re-fire (the dedup that prevents
    // notification spam). If this fires, every heartbeat notifies.
    test('staying red across polls does not re-fire', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('coverage', false); // first red — fire
      feed.report('coverage', false); // still red — no fire
      feed.report('coverage', false); // still red — no fire
      expect(fired, hasLength(1));
    });

    test('a gate red at first-seen fires with firstSeen=true', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('freeze', false); // never seen before, already red
      expect(fired.single.firstSeen, isTrue);
    });

    test('a regression (red→green→red) re-fires', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('review', false); // red — fire #1
      feed.report('review', true);  // recovered — no fire
      feed.report('review', false); // regressed — fire #2
      expect(fired, hasLength(2));
      expect(fired.last.firstSeen, isFalse); // not first-seen (we saw it before)
    });

    test('multiple gates tracked independently', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('a', false); // fire
      feed.report('b', false); // fire (different gate)
      feed.report('a', false); // no fire (a stays red)
      expect(fired.map((n) => n.gate), ['a', 'b']);
    });

    test('reset clears state — next failure is first-seen again', () {
      final fired = <GateRedNotification>[];
      final feed = GateStatusFeed(fired.add);
      feed.report('structure', false);
      feed.reset();
      feed.report('structure', false); // treated as first-seen post-reset
      expect(fired, hasLength(2));
      expect(fired.last.firstSeen, isTrue);
    });
  });
}
