/// The profile shell's viewmodel (route `/showcase/profile`). A viewmodel is
/// actions in and streams out: the view calls methods when the user does
/// something, and reads getters when something changed. The viewmodel never
/// touches the view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the profile shell's navigation frame. The
/// shell hosts the profile surface and its gallery destinations, but all
/// shell-level state (the rail selection) lives in the profile viewmodel — so
/// this viewmodel is currently empty, existing to hold the surface's five-file
/// shape.
///
/// Requirements:
/// 1. [Shell scaffold]
/// The viewmodel holds no state; the profile shell's rail selection lives in the profile viewmodel.
///
/// Relationships:
///
///         ┌────────────────────┐
///         │ profile shell view │
///         └────────────────────┘
///      ┌───────────────────────────┐
///      │  profile shell viewmodel  │
///      └───────────────────────────┘
///       ════════ abxAction ════════
///
///  No streams, actions, or commands — the viewmodel is empty.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile_shell_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseProfileShellViewModel extends BaseViewModel {}
