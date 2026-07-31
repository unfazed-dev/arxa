import 'package:stacked/stacked.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

class ShowcaseMotionViewModel extends BaseViewModel {
  static const presetLabels = ['Standard', 'Subtle', 'Energetic'];
  static const _presets = [
    KitMotionSpec.standard,
    KitMotionSpec.subtle,
    KitMotionSpec.energetic,
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
  /// [KitMotionScope] on the demo surface.
  KitMotionSpec get spec => _presets[_presetIndex].copyWith(enabled: _enabled);
}
