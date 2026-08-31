// arxa-scaffolder: view model skeleton. STRUCTURE ONLY — builder fills this.
//   surface:       code_shell_sessions_view
//   comp:          CodeSessionsViewModel
//   deps (builder wires): services/facades/conversation_facade.js
// TODO(arxa-builder): wire services from the deps above.
import 'package:stacked/stacked.dart';

class CodeSessionsViewModel extends BaseViewModel {
  /// What the view's error retry calls. Emitted by the same generator as
  /// that view, so the button can never point at a missing method.
  /// Wrap the real load in setBusy/setError so the branches light up.
  Future<void> refresh() async {}
}
