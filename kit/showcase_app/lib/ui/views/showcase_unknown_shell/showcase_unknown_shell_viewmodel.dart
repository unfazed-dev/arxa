/// The unknown shell's viewmodel (route `/showcase/unknown`). The view calls
/// actions in and reads streams out; the viewmodel never touches the view.
///
/// This is the business logic for the screen shown when a route doesn't match.
/// It is a no-op host today: the shell view owns the nested router and this
/// viewmodel holds no state of its own.
///
/// Requirements:
/// 1. [Bad-route host] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The shell mounts so an unknown route lands somewhere instead of breaking.
///
/// Relationships:
///
///          ┌─────────────────────┐
///          │ unknown shell view  │
///          └─────────────────────┘
///       ┌──────────────────────────┐
///       │ unknown shell viewmodel  │
///       └──────────────────────────┘
///        ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown_shell_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseUnknownShellViewModel extends BaseViewModel {}
