import 'package:stacked/stacked.dart';

/// design.surface — live preview · stale (brief §4, non-negotiable #2: no state
/// is inferred from paint — the stale flag is real channel state, not "did it
/// render").
class DesignSurfaceViewModel extends BaseViewModel {
  bool _stale = false;
  bool get stale => _stale;

  void markStale() { _stale = true; notifyListeners(); }
  void refresh() { _stale = false; notifyListeners(); }
}
