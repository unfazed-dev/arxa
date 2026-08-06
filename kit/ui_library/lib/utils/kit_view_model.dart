import 'package:rxdart/rxdart.dart' show ValueStream;
import 'package:stacked/stacked.dart';

import 'kit_action/kit_action.dart';

/// Base viewmodel for kit apps — the streams-only convention's lifecycle
/// half.
///
/// `BaseViewModel` is a lifecycle token: StackedView creates and disposes the
/// viewmodel, but the view is `reactive => false` and `notifyListeners` is
/// never called — all state is exposed as streams (facade pass-throughs,
/// rxdart compositions, seeded `BehaviorSubject`s for UI-owned state) and
/// bound in the view with `KitStreamBuilder`.
///
/// What this base adds over `BaseViewModel`:
/// - **Auto-dispose:** [dispose] routes through `KitAction.disposeOwner(this)`,
///   so every `KitAction.run/watch(owner: this, …)` resource — subscriptions,
///   state subjects — dies with the viewmodel. No hand-written widgetIds, no
///   manual `KitAction.dispose`.
/// - **[actionState$]:** the busy/error stream for one of this VM's ops,
///   addressed by the same `op` label the `run` chain used — views bind
///   `KitStreamBuilder(stream: viewModel.actionState$('save'), …)`.
abstract class KitViewModel extends BaseViewModel {
  /// Live busy/error state of the op this viewmodel runs as
  /// `KitAction.run(owner: this, op: op, …)`.
  ValueStream<KitActionState> actionState$(String op) =>
      KitAction.state$(owner: this, op: op);

  @override
  void dispose() {
    KitAction.disposeOwner(this);
    super.dispose();
  }
}
