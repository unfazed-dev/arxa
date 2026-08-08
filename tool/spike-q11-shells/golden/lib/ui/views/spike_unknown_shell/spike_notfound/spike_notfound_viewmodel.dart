/// The views layer draws what the user sees and forwards the user's input.
/// A viewmodel holds the state a view renders and the actions a view calls;
/// it never touches Flutter widgets.
///
/// The viewmodel behind not found. The scaffolder emits it empty; the
/// builder fills the actions and streams the surface requires.
///
/// Requirements:
/// 1. [Placeholder]
/// PLACEHOLDER(builder): the requirements body is user-owned. The
/// scaffolder emits the section and this marker only.
///
/// Relationships:
///
/// PLACEHOLDER(builder): the relationships diagram is user-owned.
/// The scaffolder emits the section and this marker only.
///
/// History: git log --follow -- tool/spike-q11-shells/golden/lib/ui/views/spike_unknown_shell/spike_notfound/spike_notfound_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class SpikeNotfoundViewModel extends BaseViewModel {}
