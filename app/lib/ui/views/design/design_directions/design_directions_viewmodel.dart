import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/gate_service.dart';

/// design.directions — 3-up · one approved (brief §4). Three prototype
/// directions; approving one routes to the design gate (gate 1).
class DesignDirectionsViewModel extends BaseViewModel {
  final directions = const [
    _Direction('A', 'Bold / editorial'),
    _Direction('B', 'Calm / utilitarian'),
    _Direction('C', 'Playful / vibrant'),
  ];
  int? _selected;

  int? get selected => _selected;
  bool get approved => locator<GateService>().allDesignApproved;

  void select(int i) {
    _selected = i;
    notifyListeners();
  }
}

class _Direction {
  final String id;
  final String blurb;
  const _Direction(this.id, this.blurb);
}
