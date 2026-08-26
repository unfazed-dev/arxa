/// A view renders the screen: it reads state from the viewmodel and redraws
/// when that state changes, and it turns the user's taps and gestures into
/// actions on the viewmodel. The view holds no business logic — swap the
/// viewmodel for another and this file stays unchanged.
///
/// This is the user interface for the profile tab's shell — the container
/// that hosts the profile tab's nested router and routes it to the right
/// form-factor variant. It owns no chrome: chrome is per-surface, so the
/// profile TAB ROOT carries the gallery chrome and the pushed Motion, Maps and
/// Components routes carry only their own. The tablet and desktop variants are
/// stubs. The viewmodel is an empty placeholder (the shell only routes), kept
/// to satisfy the showcase's five-file surface pattern.
///
/// Requirements:
/// 1. [Profile tab host] — view-the-profile-surface
/// The shell hosts the profile tab's nested router and routes it to a form-factor variant.
///
/// Relationships:
///
///      ┌────────────────────┐
///      │ profile shell view │
///      └────────────────────┘
///   ┌─────────────────────────┐
///   │ profile shell viewmodel │
///   └─────────────────────────┘
///   ════════ abxAction ════════
///
///   No streams or actions — the viewmodel is an empty placeholder.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_profile_shell_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:arxa_kit_showcase_app/ui/views/showcase_profile_shell/showcase_profile_shell_viewmodel.dart';

class ShowcaseProfileShellViewMobile
    extends ViewModelWidget<ShowcaseProfileShellViewModel> {
  const ShowcaseProfileShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseProfileShellViewModel viewModel) {
    return const NestedRouter();
  }
}
