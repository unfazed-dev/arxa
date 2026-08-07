import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';

class ShowcaseProfileViewModel extends BaseViewModel {
  int _railIndex = 0;
  int get railIndex => _railIndex;
  void setRailIndex(int index) {
    _railIndex = index;
    notifyListeners();
  }

  /// The selected rail destination — labels derive from the enum, never a
  /// parallel array.
  ShowcaseProfileRail get rail => ShowcaseProfileRail.values[_railIndex];
}
