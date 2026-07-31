import 'package:flutter_test/flutter_test.dart';
import 'package:stacked/stacked.dart';
import 'package:appbox_kit_forms/appbox_kit_forms.dart';
import 'package:appbox_kit_forms/testing.dart';

/// Minimal concrete subclass proving [KitFormViewModelMixin] composes onto a
/// real [FormViewModel] and drives Stacked's [FormStateHelper] maps.
class _BridgeViewModel extends FormViewModel with KitFormViewModelMixin {
  _BridgeViewModel(this.kitForm);

  @override
  final KitFormController kitForm;
}

void main() {
  group('KitValidators', () {
    test('required fails empty, passes non-empty', () {
      final validator = KitValidators.required();
      expect(validator('')?.code, KitValidationCode.required);
      expect(validator('  ')?.code, KitValidationCode.required);
      expect(validator('x'), isNull);
    });

    test('email passes empty, fails malformed, passes valid', () {
      final validator = KitValidators.email();
      expect(validator(''), isNull);
      expect(validator('nope')?.code, KitValidationCode.email);
      expect(validator('a@b.co'), isNull);
    });

    test('minLength interpolates the bound into the message', () {
      final error = KitValidators.minLength(8)('abc');
      expect(error?.code, KitValidationCode.minLength);
      expect(error?.message, contains('8'));
      expect(error?.params['min'], 8);
    });

    test('compose short-circuits to the first failure', () {
      final validator = KitValidators.compose([
        KitValidators.required(),
        KitValidators.minLength(3),
      ]);
      expect(validator('')?.code, KitValidationCode.required);
      expect(validator('ab')?.code, KitValidationCode.minLength);
      expect(validator('abc'), isNull);
    });

    test('toStacked surfaces the message string for the form generator', () {
      final validator = KitValidators.required(message: 'Required!').toStacked();
      expect(validator(''), 'Required!');
      expect(validator('x'), isNull);
    });

    test('match compares against a lazily-read other value', () {
      var password = 'secret';
      final validator = KitValidators.match(() => password);
      expect(validator('secret'), isNull);
      password = 'changed';
      expect(validator('secret')?.code, KitValidationCode.match);
    });
  });

  group('KitFieldController', () {
    test('sync validation moves between valid and invalid', () async {
      final field = KitFieldController<String>(
        name: 'email',
        validators: [KitValidators.required(), KitValidators.email()],
      );
      expect(field.status, KitFieldStatus.pristine);

      field.value = '';
      await field.validate();
      expect(field.status, KitFieldStatus.invalid);
      expect(field.error?.code, KitValidationCode.required);

      field.value = 'a@b.co';
      await field.validate();
      expect(field.status, KitFieldStatus.valid);
      expect(field.error, isNull);
    });

    test('async validation transitions through validating', () async {
      final fake = KitFakeAsyncValidator<String>();
      final field = KitFieldController<String>(
        name: 'username',
        asyncValidators: [fake.validator],
      );

      final future = field.validate();
      expect(field.status, KitFieldStatus.validating);
      expect(fake.isPending, isTrue);

      fake.resolveInvalid(const KitFieldError(code: 'taken', message: 'Taken'));
      expect(await future, isFalse);
      expect(field.status, KitFieldStatus.invalid);
      expect(field.error?.code, 'taken');
    });

    test('scripted validator returns queued outcomes then default', () {
      final scripted = KitScriptedValidator<String>(
        outcomes: const [KitFieldError(code: 'a', message: 'a'), null],
      );
      final field = KitFieldController<String>(
        name: 'f',
        validators: [scripted.validator],
      );
      field.setValueSilently('x');
      expect(scripted.validator('x')?.code, 'a');
      expect(scripted.validator('x'), isNull);
      expect(scripted.callCount, 2);
    });

    test('reset restores the initial value and pristine status', () async {
      final field = KitFieldController<String>(
        name: 'f',
        initialValue: 'seed',
        validators: [KitValidators.required()],
      );
      field.value = '';
      await field.validate();
      expect(field.status, KitFieldStatus.invalid);
      field.reset();
      expect(field.value, 'seed');
      expect(field.status, KitFieldStatus.pristine);
    });
  });

  group('KitFormController', () {
    test('canSubmit gates on every field being valid', () async {
      final email = KitFieldController<String>(
        name: 'email',
        validators: [KitValidators.required(), KitValidators.email()],
      );
      final form = KitFormController([email]);

      expect(form.canSubmit, isFalse);
      expect(form.status, KitFormStatus.pristine);

      email.value = 'a@b.co';
      final valid = await form.validate();
      expect(valid, isTrue);
      expect(form.status, KitFormStatus.valid);
      expect(form.canSubmit, isTrue);

      final result = await form.submit((values) async => values['email']);
      expect(result, 'a@b.co');
      form.dispose();
    });

    test('submit returns null and does not run action when invalid', () async {
      final email = KitFieldController<String>(
        name: 'email',
        validators: [KitValidators.required()],
      );
      final form = KitFormController([email]);
      var ran = false;
      final result = await form.submit((values) async {
        ran = true;
        return 'ok';
      });
      expect(result, isNull);
      expect(ran, isFalse);
      expect(form.status, KitFormStatus.invalid);
      form.dispose();
    });
  });

  group('KitFormViewModelMixin', () {
    test('syncKitForm pushes values and errors into FormStateHelper', () async {
      final email = KitFieldController<String>(
        name: 'email',
        validators: [KitValidators.required()],
      );
      final vm = _BridgeViewModel(KitFormController([email]));

      email.value = '';
      await email.validate();
      vm.syncKitForm();

      expect(vm.formValueMap['email'], '');
      expect(vm.fieldsValidationMessages['email'], isNotNull);

      email.value = 'a@b.co';
      await email.validate();
      vm.syncKitForm();

      expect(vm.formValueMap['email'], 'a@b.co');
      // setValidationMessages strips null entries, so a valid field clears.
      expect(vm.fieldsValidationMessages.containsKey('email'), isFalse);
    });
  });

  group('KitMultiStepFormController (stub)', () {
    test('advances only when the current step can submit', () async {
      final field = KitFieldController<String>(
        name: 'name',
        validators: [KitValidators.required()],
      );
      final step1 = KitFormController([field]);
      final step2 = KitFormController([
        KitFieldController<String>(name: 'extra'),
      ]);
      final flow = KitMultiStepFormController([step1, step2]);

      expect(flow.next(), isFalse); // step1 not valid yet
      field.value = 'Ada';
      await step1.validate();
      expect(flow.next(), isTrue);
      expect(flow.index, 1);
      expect(flow.isLast, isTrue);
    });
  });
}
