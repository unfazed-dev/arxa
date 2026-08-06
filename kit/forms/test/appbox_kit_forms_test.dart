import 'package:flutter_test/flutter_test.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_forms/appbox_kit_forms.dart';
import 'package:appbox_kit_forms/appbox_kit_testing.dart';

/// Minimal concrete subclass proving [AppBoxKitFormViewModelMixin] composes onto a
/// real [FormViewModel] and drives Stacked's [FormStateHelper] maps.
class _BridgeViewModel extends FormViewModel with AppBoxKitFormViewModelMixin {
  _BridgeViewModel(this.appBoxKitForm);

  @override
  final AppBoxKitFormController appBoxKitForm;
}

void main() {
  group('AppBoxKitValidators', () {
    test('required fails empty, passes non-empty', () {
      final validator = AppBoxKitValidators.required();
      expect(validator('')?.code, AppBoxKitValidationCode.required);
      expect(validator('  ')?.code, AppBoxKitValidationCode.required);
      expect(validator('x'), isNull);
    });

    test('email passes empty, fails malformed, passes valid', () {
      final validator = AppBoxKitValidators.email();
      expect(validator(''), isNull);
      expect(validator('nope')?.code, AppBoxKitValidationCode.email);
      expect(validator('a@b.co'), isNull);
    });

    test('minLength interpolates the bound into the message', () {
      final error = AppBoxKitValidators.minLength(8)('abc');
      expect(error?.code, AppBoxKitValidationCode.minLength);
      expect(error?.message, contains('8'));
      expect(error?.params['min'], 8);
    });

    test('compose short-circuits to the first failure', () {
      final validator = AppBoxKitValidators.compose([
        AppBoxKitValidators.required(),
        AppBoxKitValidators.minLength(3),
      ]);
      expect(validator('')?.code, AppBoxKitValidationCode.required);
      expect(validator('ab')?.code, AppBoxKitValidationCode.minLength);
      expect(validator('abc'), isNull);
    });

    test('toStacked surfaces the message string for the form generator', () {
      final validator = AppBoxKitValidators.required(message: 'Required!').toStacked();
      expect(validator(''), 'Required!');
      expect(validator('x'), isNull);
    });

    test('match compares against a lazily-read other value', () {
      var password = 'secret';
      final validator = AppBoxKitValidators.match(() => password);
      expect(validator('secret'), isNull);
      password = 'changed';
      expect(validator('secret')?.code, AppBoxKitValidationCode.match);
    });
  });

  group('AppBoxKitFieldController', () {
    test('sync validation moves between valid and invalid', () async {
      final field = AppBoxKitFieldController<String>(
        name: 'email',
        validators: [AppBoxKitValidators.required(), AppBoxKitValidators.email()],
      );
      expect(field.status, AppBoxKitFieldStatus.pristine);

      field.value = '';
      await field.validate();
      expect(field.status, AppBoxKitFieldStatus.invalid);
      expect(field.error?.code, AppBoxKitValidationCode.required);

      field.value = 'a@b.co';
      await field.validate();
      expect(field.status, AppBoxKitFieldStatus.valid);
      expect(field.error, isNull);
    });

    test('async validation transitions through validating', () async {
      final fake = AppBoxKitFakeAsyncValidator<String>();
      final field = AppBoxKitFieldController<String>(
        name: 'username',
        asyncValidators: [fake.validator],
      );

      final future = field.validate();
      expect(field.status, AppBoxKitFieldStatus.validating);
      expect(fake.isPending, isTrue);

      fake.resolveInvalid(const AppBoxKitFieldError(code: 'taken', message: 'Taken'));
      expect(await future, isFalse);
      expect(field.status, AppBoxKitFieldStatus.invalid);
      expect(field.error?.code, 'taken');
    });

    test('scripted validator returns queued outcomes then default', () {
      final scripted = AppBoxKitScriptedValidator<String>(
        outcomes: const [AppBoxKitFieldError(code: 'a', message: 'a'), null],
      );
      final field = AppBoxKitFieldController<String>(
        name: 'f',
        validators: [scripted.validator],
      );
      field.setValueSilently('x');
      expect(scripted.validator('x')?.code, 'a');
      expect(scripted.validator('x'), isNull);
      expect(scripted.callCount, 2);
    });

    test('reset restores the initial value and pristine status', () async {
      final field = AppBoxKitFieldController<String>(
        name: 'f',
        initialValue: 'seed',
        validators: [AppBoxKitValidators.required()],
      );
      field.value = '';
      await field.validate();
      expect(field.status, AppBoxKitFieldStatus.invalid);
      field.reset();
      expect(field.value, 'seed');
      expect(field.status, AppBoxKitFieldStatus.pristine);
    });
  });

  group('AppBoxKitFormController', () {
    test('canSubmit gates on every field being valid', () async {
      final email = AppBoxKitFieldController<String>(
        name: 'email',
        validators: [AppBoxKitValidators.required(), AppBoxKitValidators.email()],
      );
      final form = AppBoxKitFormController([email]);

      expect(form.canSubmit, isFalse);
      expect(form.status, AppBoxKitFormStatus.pristine);

      email.value = 'a@b.co';
      final valid = await form.validate();
      expect(valid, isTrue);
      expect(form.status, AppBoxKitFormStatus.valid);
      expect(form.canSubmit, isTrue);

      final result = await form.submit((values) async => values['email']);
      expect(result, 'a@b.co');
      form.dispose();
    });

    test('submit returns null and does not run action when invalid', () async {
      final email = AppBoxKitFieldController<String>(
        name: 'email',
        validators: [AppBoxKitValidators.required()],
      );
      final form = AppBoxKitFormController([email]);
      var ran = false;
      final result = await form.submit((values) async {
        ran = true;
        return 'ok';
      });
      expect(result, isNull);
      expect(ran, isFalse);
      expect(form.status, AppBoxKitFormStatus.invalid);
      form.dispose();
    });
  });

  group('AppBoxKitFormViewModelMixin', () {
    test('syncAppBoxKitForm pushes values and errors into FormStateHelper', () async {
      final email = AppBoxKitFieldController<String>(
        name: 'email',
        validators: [AppBoxKitValidators.required()],
      );
      final vm = _BridgeViewModel(AppBoxKitFormController([email]));

      email.value = '';
      await email.validate();
      vm.syncAppBoxKitForm();

      expect(vm.formValueMap['email'], '');
      expect(vm.fieldsValidationMessages['email'], isNotNull);

      email.value = 'a@b.co';
      await email.validate();
      vm.syncAppBoxKitForm();

      expect(vm.formValueMap['email'], 'a@b.co');
      // setValidationMessages strips null entries, so a valid field clears.
      expect(vm.fieldsValidationMessages.containsKey('email'), isFalse);
    });
  });

  group('AppBoxKitMultiStepFormController (stub)', () {
    test('advances only when the current step can submit', () async {
      final field = AppBoxKitFieldController<String>(
        name: 'name',
        validators: [AppBoxKitValidators.required()],
      );
      final step1 = AppBoxKitFormController([field]);
      final step2 = AppBoxKitFormController([
        AppBoxKitFieldController<String>(name: 'extra'),
      ]);
      final flow = AppBoxKitMultiStepFormController([step1, step2]);

      expect(flow.next(), isFalse); // step1 not valid yet
      field.value = 'Ada';
      await step1.validate();
      expect(flow.next(), isTrue);
      expect(flow.index, 1);
      expect(flow.isLast, isTrue);
    });
  });
}
