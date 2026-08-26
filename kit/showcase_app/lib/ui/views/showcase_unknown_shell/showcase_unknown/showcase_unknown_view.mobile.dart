/// The unknown leaf's form-factor variant. A view is actions in, streams out.
///
/// This is the user interface for the dead-end screen a bad route lands on —
/// the variant renders the static unknown body widget.
///
/// Requirements:
/// 1. [Dead-end body] — shell-demos.startup-and-unknown-shells.land-on-the-unknown-shell-for-a-bad-route
/// The variant renders the unknown body.
///
/// Relationships:
///
///         ┌──────────────────────┐
///         │ unknown leaf variant │
///         └──────────────────────┘
///       ┌─────────────────────────┐
///       │ unknown leaf viewmodel  │
///       └─────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_view.mobile.dart
library;

import 'package:flutter/material.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

import 'package:arxa_kit_showcase_app/ui/widgets/showcase_unknown_widgets/widgets.dart';

import 'package:arxa_kit_showcase_app/ui/views/showcase_unknown_shell/showcase_unknown/showcase_unknown_viewmodel.dart';

class ShowcaseUnknownViewMobile
    extends ViewModelWidget<ShowcaseUnknownViewModel> {
  const ShowcaseUnknownViewMobile({super.key});

  @override
  Widget build(BuildContext context, ShowcaseUnknownViewModel viewModel) {
    return const ShowcaseUnknownBodyWidget();
  }
}
