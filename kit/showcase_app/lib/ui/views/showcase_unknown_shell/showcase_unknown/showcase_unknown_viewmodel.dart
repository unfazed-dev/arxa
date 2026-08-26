/// The unknown leaf's viewmodel (route `/showcase/unknown`, nested under the
/// unknown shell). The view calls actions in and reads streams out; the
/// viewmodel never touches the view.
///
/// This is the business logic for the dead-end screen a bad route lands on.
/// It is a no-op today: the leaf view renders a static body widget and this
/// viewmodel holds no state of its own.
///
/// Requirements:
/// 1. [Dead-end body] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The leaf renders a body so the unknown route is not a blank screen.
///
/// Relationships:
///
///          ┌────────────────────┐
///          │ unknown leaf view  │
///          └────────────────────┘
///       ┌─────────────────────────┐
///       │ unknown leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_viewmodel.dart
library;

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

class ShowcaseUnknownViewModel extends BaseViewModel {}
