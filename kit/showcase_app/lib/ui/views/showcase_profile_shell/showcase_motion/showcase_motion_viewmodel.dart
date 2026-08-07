import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';

class ShowcaseMotionViewModel extends BaseViewModel {
  int _presetIndex = 0;
  int get presetIndex => _presetIndex;
  void setPreset(int index) {
    _presetIndex = index;
    notifyListeners();
  }

  bool _enabled = true;
  bool get enabled => _enabled;
  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }

  /// The active spec: selected preset + master switch. Feeds every
  /// [AppBoxKitMotionScope] on the demo surface.
  AppBoxKitMotionSpec get spec =>
      ShowcaseMotionPreset.values[_presetIndex].spec.copyWith(enabled: _enabled);
}
