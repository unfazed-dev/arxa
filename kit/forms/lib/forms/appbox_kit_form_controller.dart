import 'package:flutter/foundation.dart';

import '../fields/appbox_kit_field_controller.dart';
import '../fields/appbox_kit_field_status.dart';
import '../validators/appbox_kit_field_error.dart';
import 'appbox_kit_form_status.dart';

/// Aggregates [AppBoxKitFieldController]s into a single form: derived status, submit
/// gating, and a [submit] helper.
///
/// Listens to every field and re-notifies, so a view bound to the form rebuilds
/// when any field changes. By default the form *owns* its fields and disposes
/// them in [dispose]; pass `ownsFields: false` when the fields outlive the form.
class AppBoxKitFormController extends ChangeNotifier {
  AppBoxKitFormController(List<AppBoxKitFieldController> fields, {this.ownsFields = true})
      : _fields = {for (final field in fields) field.name: field} {
    for (final field in _fields.values) {
      field.addListener(_onFieldChanged);
    }
  }

  final Map<String, AppBoxKitFieldController> _fields;

  /// Whether [dispose] also disposes the underlying fields.
  final bool ownsFields;

  bool _submitting = false;

  Iterable<AppBoxKitFieldController> get fields => _fields.values;

  /// Looks up a field by [name]. Throws [ArgumentError] when absent.
  AppBoxKitFieldController<T> field<T>(String name) {
    final field = _fields[name];
    if (field == null) throw ArgumentError('No field named "$name"');
    return field as AppBoxKitFieldController<T>;
  }

  bool get isSubmitting => _submitting;

  /// Current field values keyed by name.
  Map<String, dynamic> get values =>
      {for (final entry in _fields.entries) entry.key: entry.value.value};

  /// Current field errors keyed by name (only invalid fields appear).
  Map<String, AppBoxKitFieldError> get errors => {
        for (final entry in _fields.entries)
          if (entry.value.error != null) entry.key: entry.value.error!,
      };

  /// Aggregate status derived from the fields.
  AppBoxKitFormStatus get status {
    final statuses = _fields.values.map((f) => f.status);
    if (statuses.contains(AppBoxKitFieldStatus.validating)) {
      return AppBoxKitFormStatus.validating;
    }
    if (statuses.contains(AppBoxKitFieldStatus.invalid)) {
      return AppBoxKitFormStatus.invalid;
    }
    if (statuses.every((s) => s == AppBoxKitFieldStatus.valid)) {
      return AppBoxKitFormStatus.valid;
    }
    return AppBoxKitFormStatus.pristine;
  }

  /// True when the form may be submitted: every field valid, none in flight,
  /// and not already submitting.
  bool get canSubmit =>
      !_submitting &&
      _fields.values.every((f) => f.status == AppBoxKitFieldStatus.valid);

  /// Validates every field (sync + async). Returns true when all pass.
  Future<bool> validate() async {
    final results =
        await Future.wait(_fields.values.map((field) => field.validate()));
    return results.every((ok) => ok);
  }

  /// Validates, then runs [action] with the field [values] when valid. Sets
  /// [isSubmitting] for the duration. Returns the action's result, or null when
  /// validation fails or a submit is already in progress.
  Future<R?> submit<R>(
    Future<R> Function(Map<String, dynamic> values) action,
  ) async {
    if (_submitting) return null;
    _submitting = true;
    notifyListeners();
    try {
      if (!await validate()) return null;
      return await action(values);
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Resets every field to its initial value.
  void reset() {
    for (final field in _fields.values) {
      field.reset();
    }
  }

  void _onFieldChanged() => notifyListeners();

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.removeListener(_onFieldChanged);
      if (ownsFields) field.dispose();
    }
    super.dispose();
  }
}
