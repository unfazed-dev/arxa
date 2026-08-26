import 'package:stacked/stacked.dart';

import 'arxa_kit_form_controller.dart';

/// Bridges a [ArxaKitFormController] into Stacked's [FormViewModel] conventions.
///
/// Mix onto a [FormViewModel] and provide [arxaKitForm]. Calling [syncArxaKitForm]
/// pushes the kit form's values into [FormStateHelper.formValueMap] and its
/// errors into [FormStateHelper.fieldsValidationMessages], so a generated
/// form's `<field>ValidationMessage` getters light up from the kit's richer
/// async/typed validation layer.
///
/// This is the single file in `arxa_kit_forms` that touches Stacked's
/// surface; the field/form controllers and validators are Flutter-only and can
/// be used without a [FormViewModel] at all.
mixin ArxaKitFormViewModelMixin on FormViewModel {
  /// The kit form backing this view model. Implementers provide it.
  ArxaKitFormController get arxaKitForm;

  /// Syncs the kit form's current values and errors into the Stacked
  /// [FormStateHelper] maps. Call after the kit form changes (e.g. from a
  /// listener) or before reading Stacked's generated getters.
  ///
  /// [setData] and [setValidationMessages] each notify listeners internally.
  void syncArxaKitForm() {
    setData(<String, dynamic>{...formValueMap, ...arxaKitForm.values});
    setValidationMessages(<String, String?>{
      for (final entry in arxaKitForm.errors.entries)
        entry.key: entry.value.message,
    });
  }
}
