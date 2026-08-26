import 'package:flutter_test/flutter_test.dart';
import 'package:stacked/stacked.dart';
import 'package:arxa_kit_forms/arxa_kit_forms.dart';
import 'package:arxa_kit_forms/arxa_kit_testing.dart';

/// Minimal concrete subclass proving [ArxaKitFormViewModelMixin] composes onto a
/// real [FormViewModel] and drives Stacked's [FormStateHelper] maps.
class _BridgeViewModel extends FormViewModel with ArxaKitFormViewModelMixin {
  _BridgeViewModel(this.arxaKitForm);

  @override
  final ArxaKitFormController arxaKitForm;
}

void main() {
  group('ArxaKitValidators', () {
    test('kit.forms.validators — required fails empty, passes non-empty', () {
      final validator = ArxaKitValidators.required();
      expect(validator('')?.code, ArxaKitValidationCode.required);
      expect(validator('  ')?.code, ArxaKitValidationCode.required);
      expect(validator('x'), isNull);
    });

    test('kit.forms.validators — email passes empty, fails malformed, passes valid', () {
      final validator = ArxaKitValidators.email();
      expect(validator(''), isNull);
      expect(validator('nope')?.code, ArxaKitValidationCode.email);
      expect(validator('a@b.co'), isNull);
    });

    test('kit.forms.validators — minLength interpolates the bound into the message', () {
      final error = ArxaKitValidators.minLength(8)('abc');
      expect(error?.code, ArxaKitValidationCode.minLength);
      expect(error?.message, contains('8'));
      expect(error?.params['min'], 8);
    });

    test('kit.forms.validators — compose short-circuits to the first failure', () {
      final validator = ArxaKitValidators.compose([
        ArxaKitValidators.required(),
        ArxaKitValidators.minLength(3),
      ]);
      expect(validator('')?.code, ArxaKitValidationCode.required);
      expect(validator('ab')?.code, ArxaKitValidationCode.minLength);
      expect(validator('abc'), isNull);
    });

    test('kit.forms.validators — toStacked surfaces the message string for the form generator', () {
      final validator = ArxaKitValidators.required(message: 'Required!').toStacked();
      expect(validator(''), 'Required!');
      expect(validator('x'), isNull);
    });

    test('kit.forms.validators — match compares against a lazily-read other value', () {
      var password = 'secret';
      final validator = ArxaKitValidators.match(() => password);
      expect(validator('secret'), isNull);
      password = 'changed';
      expect(validator('secret')?.code, ArxaKitValidationCode.match);
    });
  });

  group('ArxaKitFieldController', () {
    test('kit.forms.fields — sync validation moves between valid and invalid', () async {
      final field = ArxaKitFieldController<String>(
        name: 'email',
        validators: [ArxaKitValidators.required(), ArxaKitValidators.email()],
      );
      expect(field.status, ArxaKitFieldStatus.pristine);

      field.value = '';
      await field.validate();
      expect(field.status, ArxaKitFieldStatus.invalid);
      expect(field.error?.code, ArxaKitValidationCode.required);

      field.value = 'a@b.co';
      await field.validate();
      expect(field.status, ArxaKitFieldStatus.valid);
      expect(field.error, isNull);
    });

    test('kit.forms.fields — async validation transitions through validating', () async {
      final fake = ArxaKitFakeAsyncValidator<String>();
      final field = ArxaKitFieldController<String>(
        name: 'username',
        asyncValidators: [fake.validator],
      );

      final future = field.validate();
      expect(field.status, ArxaKitFieldStatus.validating);
      expect(fake.isPending, isTrue);

      fake.resolveInvalid(const ArxaKitFieldError(code: 'taken', message: 'Taken'));
      expect(await future, isFalse);
      expect(field.status, ArxaKitFieldStatus.invalid);
      expect(field.error?.code, 'taken');
    });

    test('kit.forms.fields — scripted validator returns queued outcomes then default', () {
      final scripted = ArxaKitScriptedValidator<String>(
        outcomes: const [ArxaKitFieldError(code: 'a', message: 'a'), null],
      );
      final field = ArxaKitFieldController<String>(
        name: 'f',
        validators: [scripted.validator],
      );
      field.setValueSilently('x');
      expect(scripted.validator('x')?.code, 'a');
      expect(scripted.validator('x'), isNull);
      expect(scripted.callCount, 2);
    });

    test('kit.forms.fields — reset restores the initial value and pristine status', () async {
      final field = ArxaKitFieldController<String>(
        name: 'f',
        initialValue: 'seed',
        validators: [ArxaKitValidators.required()],
      );
      field.value = '';
      await field.validate();
      expect(field.status, ArxaKitFieldStatus.invalid);
      field.reset();
      expect(field.value, 'seed');
      expect(field.status, ArxaKitFieldStatus.pristine);
    });
  });

  group('ArxaKitFormController', () {
    test('kit.forms.form — canSubmit gates on every field being valid', () async {
      final email = ArxaKitFieldController<String>(
        name: 'email',
        validators: [ArxaKitValidators.required(), ArxaKitValidators.email()],
      );
      final form = ArxaKitFormController([email]);

      expect(form.canSubmit, isFalse);
      expect(form.status, ArxaKitFormStatus.pristine);

      email.value = 'a@b.co';
      final valid = await form.validate();
      expect(valid, isTrue);
      expect(form.status, ArxaKitFormStatus.valid);
      expect(form.canSubmit, isTrue);

      final result = await form.submit((values) async => values['email']);
      expect(result, 'a@b.co');
      form.dispose();
    });

    test('kit.forms.form — submit returns null and does not run action when invalid', () async {
      final email = ArxaKitFieldController<String>(
        name: 'email',
        validators: [ArxaKitValidators.required()],
      );
      final form = ArxaKitFormController([email]);
      var ran = false;
      final result = await form.submit((values) async {
        ran = true;
        return 'ok';
      });
      expect(result, isNull);
      expect(ran, isFalse);
      expect(form.status, ArxaKitFormStatus.invalid);
      form.dispose();
    });
  });

  group('ArxaKitFormViewModelMixin', () {
    test('kit.forms.stacked-bridge — syncArxaKitForm pushes values and errors into FormStateHelper', () async {
      final email = ArxaKitFieldController<String>(
        name: 'email',
        validators: [ArxaKitValidators.required()],
      );
      final vm = _BridgeViewModel(ArxaKitFormController([email]));

      email.value = '';
      await email.validate();
      vm.syncArxaKitForm();

      expect(vm.formValueMap['email'], '');
      expect(vm.fieldsValidationMessages['email'], isNotNull);

      email.value = 'a@b.co';
      await email.validate();
      vm.syncArxaKitForm();

      expect(vm.formValueMap['email'], 'a@b.co');
      // setValidationMessages strips null entries, so a valid field clears.
      expect(vm.fieldsValidationMessages.containsKey('email'), isFalse);
    });
  });

  group('ArxaKitMultiStepFormController (stub)', () {
    test('kit.forms.multistep — advances only when the current step can submit', () async {
      final field = ArxaKitFieldController<String>(
        name: 'name',
        validators: [ArxaKitValidators.required()],
      );
      final step1 = ArxaKitFormController([field]);
      final step2 = ArxaKitFormController([
        ArxaKitFieldController<String>(name: 'extra'),
      ]);
      final flow = ArxaKitMultiStepFormController([step1, step2]);

      expect(flow.next(), isFalse); // step1 not valid yet
      field.value = 'Ada';
      await step1.validate();
      expect(flow.next(), isTrue);
      expect(flow.index, 1);
      expect(flow.isLast, isTrue);
    });
  });
}
