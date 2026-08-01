import 'package:appbox_kit_payments/appbox_kit_payments.dart';
import 'package:flutter_stripe/flutter_stripe.dart'
    show FailureCode, LocalizedErrorMessage, StripeException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements KitStripeBackend {}

class _MockGateway extends Mock implements StripeSheetGateway {}

const _fallbackConfig = StripeSheetConfig(
  publishableKey: 'pk_test_x',
  clientSecret: 'pi_x_secret_y',
  merchantDisplayName: 'x',
  merchantCountryCode: 'US',
  currencyCode: 'usd',
);

const _intent = StripePaymentIntent(clientSecret: 'pi_demo_123_secret_abc');

void main() {
  setUpAll(() => registerFallbackValue(_fallbackConfig));

  late _MockBackend backend;
  late _MockGateway gateway;
  late StripePaymentsProvider provider;

  // The provider never parses wallet JSON — the config only picks the method.
  const config = GooglePayConfig.fromJson('{}');
  const items = [KitPaymentItem(label: 'Total', amount: '19.99')];

  StripePaymentsProvider build({
    KitStripeBackend? backend,
    String publishableKey = 'pk_test_abc',
    String? merchantIdentifier = 'merchant.com.appbox',
  }) =>
      StripePaymentsProvider(
        publishableKey: publishableKey,
        merchantIdentifier: merchantIdentifier,
        backend: backend,
        gateway: gateway,
      );

  void stubHappyPath() {
    when(() => backend.createPaymentIntent(
          amountMinor: any(named: 'amountMinor'),
          currency: any(named: 'currency'),
          customerId: any(named: 'customerId'),
        )).thenAnswer((_) async => _intent);
    when(() => gateway.initSheet(any())).thenAnswer((_) async {});
    when(() => gateway.presentSheet()).thenAnswer((_) async {});
  }

  setUp(() {
    backend = _MockBackend();
    gateway = _MockGateway();
    provider = build(backend: backend);
  });

  group('StripePaymentsProvider — contract', () {
    test('id is "stripe"', () {
      expect(provider.id, 'stripe');
    });

    test('supports both wallets when a merchant identifier is set', () {
      expect(provider.supportedMethods,
          {KitPaymentMethod.applePay, KitPaymentMethod.googlePay});
    });

    test('drops Apple Pay without a merchant identifier', () {
      expect(build(backend: backend, merchantIdentifier: null).supportedMethods,
          {KitPaymentMethod.googlePay});
    });

    test('googlePayTestEnv follows the key mode', () {
      expect(provider.googlePayTestEnv, isTrue); // pk_test_
      expect(build(backend: backend, publishableKey: 'pk_live_abc')
          .googlePayTestEnv, isFalse);
    });

    test('canPay is true for a supported method with a backend', () async {
      expect(await provider.canPay(KitPaymentMethod.googlePay), isTrue);
      expect(await provider.canPay(KitPaymentMethod.applePay), isTrue);
    });

    test('canPay is false without a backend', () async {
      expect(await build(backend: null).canPay(KitPaymentMethod.googlePay),
          isFalse);
    });

    test('canPay is false for PayPal', () async {
      expect(await provider.canPay(KitPaymentMethod.payPal), isFalse);
    });
  });

  group('StripePaymentsProvider — PaymentSheet flow', () {
    test('success: intent → init → present, token is the pi_ id', () async {
      stubHappyPath();

      final result = await provider.requestPayment(
          config: config, items: items);

      expect(result, isA<PaymentSuccess>());
      final success = result as PaymentSuccess;
      expect(success.token, 'pi_demo_123');
      expect(success.method, KitPaymentMethod.googlePay);
      expect(success.raw['paymentIntentId'], 'pi_demo_123');

      // Amount is summed to minor units; currency comes from the provider.
      verify(() => backend.createPaymentIntent(
          amountMinor: 1999, currency: 'usd')).called(1);

      // Sheet got the client secret + wallet toggles for a test key.
      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as StripeSheetConfig;
      expect(sheetConfig.clientSecret, _intent.clientSecret);
      expect(sheetConfig.applePayEnabled, isTrue);
      expect(sheetConfig.googlePayEnabled, isTrue);
      expect(sheetConfig.googlePayTestEnv, isTrue);
      verify(() => gateway.presentSheet()).called(1);
    });

    test('customer pairing from the intent is forwarded to the sheet',
        () async {
      when(() => backend.createPaymentIntent(
            amountMinor: any(named: 'amountMinor'),
            currency: any(named: 'currency'),
            customerId: any(named: 'customerId'),
          )).thenAnswer((_) async => const StripePaymentIntent(
            clientSecret: 'pi_c_secret_x',
            customerId: 'cus_1',
            customerEphemeralKeySecret: 'ek_1',
          ));
      when(() => gateway.initSheet(any())).thenAnswer((_) async {});
      when(() => gateway.presentSheet()).thenAnswer((_) async {});

      await provider.requestPayment(config: config, items: items);

      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as StripeSheetConfig;
      expect(sheetConfig.customerId, 'cus_1');
      expect(sheetConfig.customerEphemeralKeySecret, 'ek_1');
    });

    test('user dismissal maps to PaymentCancelled', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const StripeSheetCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<PaymentCancelled>());
    });

    test('card decline maps to PaymentDeclined with the SDK reason', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const StripeSheetDeclined('Your card was declined.'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentDeclined>());
      expect((result as PaymentDeclined).reason, 'Your card was declined.');
    });

    test('init failure maps to PaymentError', () async {
      stubHappyPath();
      when(() => gateway.initSheet(any()))
          .thenThrow(const StripeSheetError('bad client secret'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, 'bad client secret');
    });

    test('backend failure maps to PaymentError and never shows the sheet',
        () async {
      when(() => backend.createPaymentIntent(
            amountMinor: any(named: 'amountMinor'),
            currency: any(named: 'currency'),
            customerId: any(named: 'customerId'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, contains('network down'));
      verifyNever(() => gateway.initSheet(any()));
      verifyNever(() => gateway.presentSheet());
    });

    test('no backend maps to PaymentError', () async {
      final result = await build(backend: null)
          .requestPayment(config: config, items: items);
      expect(result, isA<PaymentError>());
    });

    test('a pending item maps to PaymentError and never calls the backend',
        () async {
      final result = await provider.requestPayment(
        config: config,
        items: const [
          KitPaymentItem(
              label: 'Shipping',
              amount: '5.00',
              status: KitPaymentItemStatus.pending),
        ],
      );

      expect(result, isA<PaymentError>());
      verifyNever(() => backend.createPaymentIntent(
          amountMinor: any(named: 'amountMinor'),
          currency: any(named: 'currency'),
          customerId: any(named: 'customerId')));
    });

    test('a PayPal config is rejected', () async {
      final result = await provider.requestPayment(
        config: const PayPalConfig(),
        items: items,
      );
      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, contains('does not support'));
    });
  });

  group('FlutterStripeSheetGateway.mapStripeError', () {
    // Pure mapping over flutter_stripe data types — no platform channel.
    test('Canceled → StripeSheetCancelled', () {
      final error = FlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Canceled),
        ),
      );
      expect(error, isA<StripeSheetCancelled>());
    });

    test('Failed → StripeSheetDeclined with the localized reason', () {
      final error = FlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Failed,
            localizedMessage: 'Your card was declined.',
          ),
        ),
      );
      expect(error, isA<StripeSheetDeclined>());
      expect((error as StripeSheetDeclined).reason, 'Your card was declined.');
    });

    test('Timeout → StripeSheetError', () {
      final error = FlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Timeout),
        ),
      );
      expect(error, isA<StripeSheetError>());
    });

    test('Unknown → StripeSheetError falling back to the message', () {
      final error = FlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Unknown,
            message: 'something broke',
          ),
        ),
      );
      expect(error, isA<StripeSheetError>());
      expect((error as StripeSheetError).message, 'something broke');
    });

    test('non-Stripe exceptions wrap as StripeSheetError', () {
      final error = FlutterStripeSheetGateway.mapStripeError('boom');
      expect(error, isA<StripeSheetError>());
      expect((error as StripeSheetError).cause, 'boom');
    });
  });
}
