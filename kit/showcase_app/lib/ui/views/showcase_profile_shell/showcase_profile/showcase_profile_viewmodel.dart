/// The profile surface's viewmodel (route `/showcase/profile`). A viewmodel is
/// actions in and streams out: the view calls methods when the user does
/// something, and reads getters when something changed. The viewmodel never
/// touches the view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the profile surface. It holds which rail
/// destination is selected — the rail's labels come from the enum, never a
/// parallel array — and rebuilds the view so the right section shows.
///
/// Requirements:
/// 1. [Rail selection] — profile-and-gallery-demos.profile.view-the-profile-surface
/// The user picks a section from the rail, and that section is shown.
///
/// Relationships:
///
///       ┌──────────────┐
///       │ profile view │
///       └──────────────┘
///       ACT ▼
///       [1]
///    ┌─────────────────────┐
///    │  profile viewmodel  │
///    └─────────────────────┘
///  ════════ abxAction ════════
///
///  actions (ACT)
///    1. setRailIndex
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile/showcase_profile_viewmodel.dart
library;

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/enums/showcase_profile_enums/enums.dart';

class ShowcaseProfileViewModel extends BaseViewModel {
  // ── Initial state ─────────────────────────────────────────────────────────

  /// [1. Rail selection] The selected rail tab, starting at the first section.
  int _railIndex = 0;
  int get railIndex => _railIndex;

  /// [1. Rail selection] The selected rail destination — labels derive from the
  /// enum, never a parallel array.
  ShowcaseProfileRail get rail => ShowcaseProfileRail.values[_railIndex];

  // ── Actions ───────────────────────────────────────────────────────────────

  /// [1. Rail selection] The view calls this when the user taps a rail tab.
  void setRailIndex(int index) {
    _railIndex = index;
    notifyListeners();
  }
}
