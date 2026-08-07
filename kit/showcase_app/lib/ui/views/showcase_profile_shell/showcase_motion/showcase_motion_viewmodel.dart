import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

class ShowcaseMotionViewModel extends BaseViewModel {
  static const presetLabels = ['Standard', 'Subtle', 'Energetic'];
  static const _presets = [
    AppBoxKitMotionSpec.standard,
    AppBoxKitMotionSpec.subtle,
    AppBoxKitMotionSpec.energetic,
  ];

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
  AppBoxKitMotionSpec get spec => _presets[_presetIndex].copyWith(enabled: _enabled);
}
