import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/services/gate_service.dart';

/// 8.11 / done-when #6 — an automated agent cannot advance past any of the
/// three gates. This is the proof: the agent-side API (markReached) never mints
/// approval; only the human approve* methods do, and ship.confirm requires the
/// exact triple.
void main() {
  group('GateService — an agent cannot mint approval', () {
    test('markReached (the only agent API) never approves any gate', () {
      final g = GateService();
      for (final id in GateId.values) {
        g.markReached(id);
      }
      for (final id in GateId.values) {
        expect(g.statusOf(id), GateStatus.pending, reason: '$id must stay pending');
      }
      expect(g.allDesignApproved, isFalse);
      expect(g.allBuildApproved, isFalse);
      expect(g.allShipApproved, isFalse);
    });

    test('a loop of markReached calls can never flip a gate to approved', () {
      final g = GateService();
      // Simulate an agent hammering the only API it has.
      for (var i = 0; i < 1000; i++) {
        g.markReached(GateId.design);
        g.markReached(GateId.build);
        g.markReached(GateId.ship);
      }
      expect(g.allShipApproved, isFalse, reason: 'no agent loop can ship');
    });

    test('only the human approve methods mint approval (gates 1 & 2)', () {
      final g = GateService();
      g.approveDesign();
      expect(g.allDesignApproved, isTrue);
      g.approveBuild();
      expect(g.allBuildApproved, isTrue);
    });

    test('ship.confirm (gate 3) rejects a mismatched triple', () {
      final g = GateService()
        ..declaredShipTriple = const ShipTriple('ios', '1.0.0', 'totem');
      final ok = g.confirmShip(const ShipTriple('ios', '1.0.0', 'wrong'));
      expect(ok, isFalse);
      expect(g.allShipApproved, isFalse);
    });

    test('ship.confirm approves only on the exact target+version+account', () {
      final g = GateService()
        ..declaredShipTriple = const ShipTriple('ios', '1.0.0', 'totem');
      final ok = g.confirmShip(const ShipTriple('ios', '1.0.0', 'totem'));
      expect(ok, isTrue);
      expect(g.allShipApproved, isTrue);
    });

    test('ship.confirm with no declared triple never approves', () {
      final g = GateService();
      expect(g.confirmShip(const ShipTriple('ios', '1.0.0', 'totem')), isFalse);
      expect(g.allShipApproved, isFalse);
    });
  });
}
