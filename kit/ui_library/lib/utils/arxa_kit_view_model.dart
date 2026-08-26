import 'package:stacked/stacked.dart';

import 'arxa_kit_action_owner.dart';

/// Base viewmodel for kit apps — the streams-only convention's lifecycle
/// half.
///
/// `BaseViewModel` is a lifecycle token: StackedView creates and disposes the
/// viewmodel, but the view is `reactive => false` and `notifyListeners` is
/// never called — all state is exposed as streams (facade pass-throughs,
/// rxdart compositions, seeded `BehaviorSubject`s for UI-owned state) and
/// bound in the view with `ArxaKitStreamBuilder`.
///
/// What this base adds over `BaseViewModel` (via [ArxaKitActionOwner]):
/// - **`action(name, operation)`:** runs ops with `owner: this` implied —
///   `await action('save', () => _repo.put(note))`, no widgetId strings.
/// - **`listen(name, to:, onData:)`:** owner-scoped stream listeners.
/// - **[actionState$]:** the busy/error stream for one of this VM's ops,
///   addressed by the same `name` the `action` chain used — views bind
///   `ArxaKitStreamBuilder(stream: viewModel.actionState$('save'), …)`.
/// - **Auto-dispose:** [dispose] routes through [disposeArxaKitActions], so every
///   resource the VM's ops created dies with it.
abstract class ArxaKitViewModel extends BaseViewModel
    with ArxaKitActionOwner {
  @override
  void dispose() {
    disposeArxaKitActions();
    super.dispose();
  }
}
