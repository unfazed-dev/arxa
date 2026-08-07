/// The unknown shell's form-factor variant. A view is actions in, streams out.
///
/// This is the user interface for the screen shown when a route doesn't match —
/// the variant renders the nested router outlet with no chrome of its own.
///
/// Requirements:
/// 1. [Bad-route host] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The variant hosts the unknown leaf through a nested router.
///
/// Relationships:
///
///         ┌───────────────────────┐
///         │ unknown shell variant │
///         └───────────────────────┘
///       ┌──────────────────────────┐
///       │ unknown shell viewmodel  │
///       └──────────────────────────┘
///        ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown_shell_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

import 'package:appbox_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown_shell_viewmodel.dart';

class ShowcaseUnknownShellViewMobile
    extends ViewModelWidget<ShowcaseUnknownShellViewModel> {
  const ShowcaseUnknownShellViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownShellViewModel viewModel) {
    return const NestedRouter();
  }
}
