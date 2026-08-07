/// The notes shell viewmodel — the root container for the notes tab. It
/// holds no state of its own; its job is to be the route entry point the
/// shell view binds, so the router has a viewmodel to resolve.
///
/// This is the business logic for the notes tab shell. It is an empty
/// container — the shell view hosts nested routes, and each child carries
/// its own viewmodel.
///
/// Requirements:
/// 1. [Shell entry]
/// Provides a viewmodel for the notes shell route.
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_notes_shell/showcase_notes_shell_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseNotesShellViewModel extends BaseViewModel {}
