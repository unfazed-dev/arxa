import 'package:flutter/foundation.dart';

import '../forms/kit_form_controller.dart';

/// STUB (scheduled: multi-step form flow phase).
///
/// Sequences several [KitFormController]s into a wizard with per-step submit
/// gating. This minimal controller covers linear next/previous navigation; the
/// richer semantics (branching, progress, back-stack, per-step drafts) land in
/// a later phase.
class KitMultiStepFormController extends ChangeNotifier {
  KitMultiStepFormController(this.steps)
      : assert(steps.isNotEmpty, 'A multi-step form needs at least one step');

  final List<KitFormController> steps;
  int _index = 0;

  /// The current step index.
  int get index => _index;

  /// The form controller for the current step.
  KitFormController get current => steps[_index];

  bool get isFirst => _index == 0;
  bool get isLast => _index == steps.length - 1;

  /// Whether the current step is complete enough to advance.
  bool get canAdvance => current.canSubmit;

  /// Advances to the next step when [canAdvance]. Returns false at the last
  /// step or when the current step is not yet valid.
  bool next() {
    if (isLast || !canAdvance) return false;
    _index++;
    notifyListeners();
    return true;
  }

  /// Moves back one step. Returns false at the first step.
  bool previous() {
    if (isFirst) return false;
    _index--;
    notifyListeners();
    return true;
  }
}
