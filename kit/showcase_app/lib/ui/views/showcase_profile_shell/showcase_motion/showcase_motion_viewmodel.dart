/// The motion demo's viewmodel (route `/showcase/profile/motion`). A
/// viewmodel is actions in and streams out: the view calls methods when the
/// user does something, and reads getters when something changed. The
/// viewmodel never touches the view — swap the UI for any other and this file
/// stays unchanged.
///
/// This is the business logic for the motion demo surface. It holds the
/// selected motion preset and a master on/off switch, then composes them into
/// a single spec that every animated widget on the surface reads.
///
/// Requirements:
/// 1. [Preset selection] — profile-and-gallery-demos.gallery.view-the-motion-demo
/// The user picks a motion preset, and every animated widget adopts it.
/// 2. [Master switch] — profile-and-gallery-demos.gallery.view-the-motion-demo
/// A master toggle turns all motion effects on or off at once.
///
/// Relationships:
///
///    ┌──────────────────┐
///    │ motion demo view │
///    └──────────────────┘
///    ACT ▼
///    [1-2]
///    ┌──────────────────┐
///    │ motion viewmodel │
///    └──────────────────┘
/// ════════ abxAction ════════
///
///  actions (ACT)
///    1. setPreset
///    2. setEnabled
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_motion/showcase_motion_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';
import 'package:appbox_kit_motion/appbox_kit_motion.dart';

import 'package:appbox_kit_showcase_app/enums/showcase_profile_enums/enums.dart';

class ShowcaseMotionViewModel extends BaseViewModel {
  // ── Initial state ─────────────────────────────────────────────────────────

  /// [1. Preset selection] The selected motion preset, starting at the first.
  int _presetIndex = 0;
  int get presetIndex => _presetIndex;

  /// [2. Master switch] Whether motion effects are on, starting enabled.
  bool _enabled = true;
  bool get enabled => _enabled;

  /// [1. Preset selection][2. Master switch] The active spec: selected preset +
  /// master switch. Feeds every [AppBoxKitMotionScope] on the demo surface.
  AppBoxKitMotionSpec get spec =>
      ShowcaseMotionPreset.values[_presetIndex].spec.copyWith(enabled: _enabled);

  // ── Actions ───────────────────────────────────────────────────────────────

  /// [1. Preset selection] The view calls this when the user picks a preset.
  void setPreset(int index) {
    _presetIndex = index;
    notifyListeners();
  }

  /// [2. Master switch] The view calls this when the user toggles the switch.
  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
  }
}
