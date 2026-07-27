import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/gate_service.dart';

/// design.approve — GATE 1 — pending · approved (brief §4).
/// An agent may present directions; it cannot mint this approval.
class DesignApproveViewModel extends BaseViewModel {
  final _gates = locator<GateService>();
  bool get approved => _gates.allDesignApproved;

  void approve() {
    _gates.approveDesign();
    notifyListeners();
  }
}
