/// The application shell's viewmodel (route `/showcase`). The view calls
/// actions in and reads streams out; the viewmodel never touches the view.
///
/// This is the business logic for the showcase's tabbed root shell. It is a
/// no-op host today: the shell view owns the tab router and this viewmodel
/// holds no state of its own.
///
/// Requirements:
/// 1. [Tab host] — shell-demos.home-and-application-shells.browse-the-application-shell
/// The shell mounts the four tab shells (home, search, profile, notes).
///
/// Relationships:
///
///          ┌────────────────────────┐
///          │ application shell view │
///          └────────────────────────┘
///       ┌─────────────────────────────┐
///       │ application shell viewmodel │
///       └─────────────────────────────┘
///         ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_application_shell/showcase_application_shell_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseApplicationShellViewModel extends BaseViewModel {}
