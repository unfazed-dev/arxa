/// The search leaf's viewmodel (route `/showcase/search`, nested under the
/// search shell). The view calls actions in and reads streams out; the
/// viewmodel never touches the view.
///
/// This is the business logic for the search demo surface. It holds the filter
/// values — radius, price range, open-now, outdoor — so the native sliders and
/// switches respond. The values are plain primitives (no Flutter types) so the
/// viewmodel stays logic-only and UI-swappable; the view converts to and from
/// `RangeValues` at the slider boundary.
///
/// Requirements:
/// 1. [Filter state] — search-and-attachments.search.search-notes-by-text
/// Holds the demo filter values so the native search controls respond.
///
/// Relationships:
///
///           ┌──────────────────┐
///           │ search leaf view │
///           └──────────────────┘
///           ACT ▼
///           [1-4]
///       ┌─────────────────────────┐
///       │  search leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
///  actions (ACT)
///    1. setRadius
///    2. setPrice
///    3. setOpenNow
///    4. setOutdoor
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search/showcase_search_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseSearchViewModel extends BaseViewModel {
  // ── Initial state ─────────────────────────────────────────────────────────

  /// [1. Filter state] Search-radius slider value.
  double _radius = 0.5;
  double get radius => _radius;

  // ponytail: two doubles, not RangeValues — RangeValues is a Flutter material
  // value type and would drag a material import into the viewmodel (1m
  // violation). The view (re)builds the RangeValues at the slider.
  /// [1. Filter state] Price-range slider endpoints.
  double _priceStart = 0.25;
  double _priceEnd = 0.75;
  double get priceStart => _priceStart;
  double get priceEnd => _priceEnd;

  /// [1. Filter state] Whether the "open now" switch is on.
  bool _openNow = false;
  bool get openNow => _openNow;

  /// [1. Filter state] Whether the "outdoor" switch is on.
  bool _outdoor = true;
  bool get outdoor => _outdoor;

  // ── Actions ──────────────────────────────────────────────────────────────

  /// [1. Filter state] Sets the radius slider value.
  void setRadius(double value) {
    _radius = value;
    notifyListeners();
  }

  /// [1. Filter state] Sets both price-range endpoints.
  void setPrice(double start, double end) {
    _priceStart = start;
    _priceEnd = end;
    notifyListeners();
  }

  /// [1. Filter state] Toggles the "open now" switch.
  void setOpenNow(bool value) {
    _openNow = value;
    notifyListeners();
  }

  /// [1. Filter state] Toggles the "outdoor" switch.
  void setOutdoor(bool value) {
    _outdoor = value;
    notifyListeners();
  }
}
