/// The search shell's viewmodel (route `/showcase/search`). The view calls
/// actions in and reads streams out; the viewmodel never touches the view.
///
/// This is the business logic for the search tab's shell. It is a no-op host
/// today: the shell view owns the nested router and this viewmodel holds no
/// state of its own.
///
/// Requirements:
/// 1. [Search host] — search-and-attachments.search.search-notes-by-text / search-and-attachments.search.open-a-note-from-a-search-result
/// The shell hosts the search leaf through a nested router.
///
/// Relationships:
///
///          ┌───────────────────┐
///          │ search shell view │
///          └───────────────────┘
///       ┌────────────────────────┐
///       │ search shell viewmodel │
///       └────────────────────────┘
///       ════════ abxAction ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_search_shell/showcase_search_shell_viewmodel.dart
library;

import 'package:appbox_kit_ui_library/appbox_kit_ui_library.dart';

class ShowcaseSearchShellViewModel extends BaseViewModel {}
