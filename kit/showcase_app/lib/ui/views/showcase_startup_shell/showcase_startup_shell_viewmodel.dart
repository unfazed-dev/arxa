/// The startup shell's viewmodel (route `/showcase/startup-shell`). The shell
/// view calls actions in and reads streams out — once real behavior lands;
/// right now the shell is a passive nested-router outlet for the startup leaf,
/// so there is nothing to call or read yet. The viewmodel never touches the
/// view — swap the UI for any other and this file stays unchanged.
///
/// This is the business logic for the startup shell's outer frame. It holds
/// the slot the shell view binds to while a nested router fills the body with
/// the startup leaf (boot logic + loading UI).
///
/// Requirements:
/// 1. [Shell host]
/// The shell view binds here so the nested router has a viewmodel to anchor to.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │    startup shell view    │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │ startup shell viewmodel  │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No streams, actions, or commands yet — passive router-outlet host.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_startup_shell/showcase_startup_shell_viewmodel.dart
library;

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseStartupShellViewModel extends BaseViewModel {}
