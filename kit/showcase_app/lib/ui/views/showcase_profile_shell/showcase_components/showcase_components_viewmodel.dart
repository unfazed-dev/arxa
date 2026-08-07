/// The components gallery's viewmodel (route `/showcase/profile/components`).
/// A viewmodel is actions in and streams out: the view calls methods when the
/// user does something, and reads getters when something changed. The
/// viewmodel never touches the view — swap the UI for any other and this file
/// stays unchanged.
///
/// This is the business logic for the components gallery. Every demo on the
/// surface is stateless — each interaction is an imperative kit call fired
/// directly from the view — so this viewmodel holds no state and exists to
/// satisfy the surface's five-file shape.
///
/// Requirements:
/// 1. [Gallery scaffold]
/// The viewmodel holds no state; every components demo is a stateless imperative kit call.
///
/// Relationships:
///
///           ┌────────────────────────┐
///           │components gallery view │
///           └────────────────────────┘
///      ┌─────────────────────────────────┐
///      │  components gallery viewmodel   │
///      └─────────────────────────────────┘
///          ════════ abxAction ════════
///
///  No streams, actions, or commands — the viewmodel is empty.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseComponentsViewModel extends BaseViewModel {}
