/// The home tab's viewmodel (route `/showcase/home-shell/home`). The view
/// calls actions in and reads streams out — once real behavior lands; right
/// now the tab body is built from stateless demo widgets, so there is nothing
/// to call or read yet. The viewmodel never touches the view — swap the UI for
/// any other and this file stays unchanged.
///
/// This is the business logic for the home tab's body. It holds the slot the
/// home view binds to while demo widgets (snackbar smokes, Glass CTA,
/// theme-mode toggle, feedback tier) render directly.
///
/// Requirements:
/// 1. [Tab host]
/// The home view binds here so the demo-widget body has a viewmodel to anchor to.
///
/// Relationships:
///
///   ┌──────────────────────────┐
///   │        home view         │
///   └──────────────────────────┘
///   ┌──────────────────────────┐
///   │      home viewmodel      │
///   └──────────────────────────┘
///    ════════ abxAction ════════
///
/// No streams, actions, or commands yet — the body is stateless demo widgets.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_home_shell/showcase_home/showcase_home_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseHomeViewModel extends BaseViewModel {}
