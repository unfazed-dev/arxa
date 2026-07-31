import 'package:stacked/stacked.dart';

/// Search-filter state for the demo surface. Logic-only: holds primitives only
/// (no Flutter value types) so the viewmodel stays free of `package:flutter/*`
/// imports — the view converts to/from `RangeValues` at the slider boundary
/// (kit-reviewer check 1m: viewmodels are logic-only, UI-swappable).
class ShowcaseSearchViewModel extends BaseViewModel {
  double _radius = 0.5;
  double get radius => _radius;
  void setRadius(double value) {
    _radius = value;
    notifyListeners();
  }

  // ponytail: two doubles, not RangeValues — RangeValues is a Flutter material
  // value type and would drag a material import into the viewmodel (1m
  // violation). The view (re)builds the RangeValues at the slider.
  double _priceStart = 0.25;
  double _priceEnd = 0.75;
  double get priceStart => _priceStart;
  double get priceEnd => _priceEnd;
  void setPrice(double start, double end) {
    _priceStart = start;
    _priceEnd = end;
    notifyListeners();
  }

  bool _openNow = false;
  bool get openNow => _openNow;
  void setOpenNow(bool value) {
    _openNow = value;
    notifyListeners();
  }

  bool _outdoor = true;
  bool get outdoor => _outdoor;
  void setOutdoor(bool value) {
    _outdoor = value;
    notifyListeners();
  }
}
