import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseProfileViewModel extends BaseViewModel {
  static const railLabels = ['Account', 'Privacy', 'Alerts'];

  int _railIndex = 0;
  int get railIndex => _railIndex;
  void setRailIndex(int index) {
    _railIndex = index;
    notifyListeners();
  }
}
