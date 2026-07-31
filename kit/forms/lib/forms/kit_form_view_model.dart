import 'package:stacked/stacked.dart';

import 'kit_form_controller.dart';

/// Bridges a [KitFormController] into Stacked's [FormViewModel] conventions.
///
/// Mix onto a [FormViewModel] and provide [kitForm]. Calling [syncKitForm]
/// pushes the kit form's values into [FormStateHelper.formValueMap] and its
/// errors into [FormStateHelper.fieldsValidationMessages], so a generated
/// form's `<field>ValidationMessage` getters light up from the kit's richer
/// async/typed validation layer.
///
/// This is the single file in `appbox_kit_forms` that touches Stacked's
/// surface; the field/form controllers and validators are Flutter-only and can
/// be used without a [FormViewModel] at all.
mixin KitFormViewModelMixin on FormViewModel {
  /// The kit form backing this view model. Implementers provide it.
  KitFormController get kitForm;

  /// Syncs the kit form's current values and errors into the Stacked
  /// [FormStateHelper] maps. Call after the kit form changes (e.g. from a
  /// listener) or before reading Stacked's generated getters.
  ///
  /// [setData] and [setValidationMessages] each notify listeners internally.
  void syncKitForm() {
    setData(<String, dynamic>{...formValueMap, ...kitForm.values});
    setValidationMessages(<String, String?>{
      for (final entry in kitForm.errors.entries)
        entry.key: entry.value.message,
    });
  }
}
