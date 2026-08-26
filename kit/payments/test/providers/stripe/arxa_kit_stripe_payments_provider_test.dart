import 'package:arxa_kit_payments/arxa_kit_payments.dart';
import 'package:flutter_stripe/flutter_stripe.dart'
    show FailureCode, LocalizedErrorMessage, StripeException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements ArxaKitStripeBackend {}

class _MockGateway extends Mock implements ArxaKitStripeSheetGateway {}

const _fallbackConfig = ArxaKitStripeSheetConfig(
  publishableKey: 'pk_test_x',
  clientSecret: 'pi_x_secret_y',
  merchantDisplayName: 'x',
  merchantCountryCode: 'US',
  currencyCode: 'usd',
);

const _intent = ArxaKitStripePaymentIntent(clientSecret: 'pi_demo_123_secret_abc');

void main() {
  setUpAll(() => registerFallbackValue(_fallbackConfig));

  late _MockBackend backend;
  late _MockGateway gateway;
  late ArxaKitStripePaymentsProvider provider;

  // The provider never parses wallet JSON — the config only picks the method.
  const config = ArxaKitGooglePayConfig.fromJson('{}');
  const items = [ArxaKitPaymentItem(label: 'Total', amount: '19.99')];

  ArxaKitStripePaymentsProvider build({
    ArxaKitStripeBackend? backend,
    String publishableKey = 'pk_test_abc',
    String? merchantIdentifier = 'merchant.com.arxa',
  }) =>
      ArxaKitStripePaymentsProvider(
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

  group('ArxaKitStripePaymentsProvider — contract', () {
    test('kit.payments.stripe — id is "stripe"', () {
      expect(provider.id, 'stripe');
    });

    test('kit.payments.stripe — supports both wallets when a merchant identifier is set', () {
      expect(provider.supportedMethods,
          {ArxaKitPaymentMethod.applePay, ArxaKitPaymentMethod.googlePay});
    });

    test('kit.payments.stripe — drops Apple Pay without a merchant identifier', () {
      expect(build(backend: backend, merchantIdentifier: null).supportedMethods,
          {ArxaKitPaymentMethod.googlePay});
    });

    test('kit.payments.stripe — googlePayTestEnv follows the key mode', () {
      expect(provider.googlePayTestEnv, isTrue); // pk_test_
      expect(build(backend: backend, publishableKey: 'pk_live_abc')
          .googlePayTestEnv, isFalse);
    });

    test('kit.payments.stripe — canPay is true for a supported method with a backend', () async {
      expect(await provider.canPay(ArxaKitPaymentMethod.googlePay), isTrue);
      expect(await provider.canPay(ArxaKitPaymentMethod.applePay), isTrue);
    });

    test('kit.payments.stripe — canPay is false without a backend', () async {
      expect(await build(backend: null).canPay(ArxaKitPaymentMethod.googlePay),
          isFalse);
    });

    test('kit.payments.stripe — canPay is false for PayPal', () async {
      expect(await provider.canPay(ArxaKitPaymentMethod.payPal), isFalse);
    });
  });

  group('ArxaKitStripePaymentsProvider — PaymentSheet flow', () {
    test('kit.payments.stripe — success: intent → init → present, token is the pi_ id', () async {
      stubHappyPath();

      final result = await provider.requestPayment(
          config: config, items: items);

      expect(result, isA<ArxaKitPaymentSuccess>());
      final success = result as ArxaKitPaymentSuccess;
      expect(success.token, 'pi_demo_123');
      expect(success.method, ArxaKitPaymentMethod.googlePay);
      expect(success.raw['paymentIntentId'], 'pi_demo_123');

      // Amount is summed to minor units; currency comes from the provider.
      verify(() => backend.createPaymentIntent(
          amountMinor: 1999, currency: 'usd')).called(1);

      // Sheet got the client secret + wallet toggles for a test key.
      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as ArxaKitStripeSheetConfig;
      expect(sheetConfig.clientSecret, _intent.clientSecret);
      expect(sheetConfig.applePayEnabled, isTrue);
      expect(sheetConfig.googlePayEnabled, isTrue);
      expect(sheetConfig.googlePayTestEnv, isTrue);
      verify(() => gateway.presentSheet()).called(1);
    });

    test('kit.payments.stripe — customer pairing from the intent is forwarded to the sheet',
        () async {
      when(() => backend.createPaymentIntent(
            amountMinor: any(named: 'amountMinor'),
            currency: any(named: 'currency'),
            customerId: any(named: 'customerId'),
          )).thenAnswer((_) async => const ArxaKitStripePaymentIntent(
            clientSecret: 'pi_c_secret_x',
            customerId: 'cus_1',
            customerEphemeralKeySecret: 'ek_1',
          ));
      when(() => gateway.initSheet(any())).thenAnswer((_) async {});
      when(() => gateway.presentSheet()).thenAnswer((_) async {});

      await provider.requestPayment(config: config, items: items);

      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as ArxaKitStripeSheetConfig;
      expect(sheetConfig.customerId, 'cus_1');
      expect(sheetConfig.customerEphemeralKeySecret, 'ek_1');
    });

    test('kit.payments.stripe — user dismissal maps to ArxaKitPaymentCancelled', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const ArxaKitStripeSheetCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<ArxaKitPaymentCancelled>());
    });

    test('kit.payments.stripe — card decline maps to ArxaKitPaymentDeclined with the SDK reason', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const ArxaKitStripeSheetDeclined('Your card was declined.'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentDeclined>());
      expect((result as ArxaKitPaymentDeclined).reason, 'Your card was declined.');
    });

    test('kit.payments.stripe — init failure maps to ArxaKitPaymentError', () async {
      stubHappyPath();
      when(() => gateway.initSheet(any()))
          .thenThrow(const ArxaKitStripeSheetError('bad client secret'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, 'bad client secret');
    });

    test('kit.payments.stripe — backend failure maps to ArxaKitPaymentError and never shows the sheet',
        () async {
      when(() => backend.createPaymentIntent(
            amountMinor: any(named: 'amountMinor'),
            currency: any(named: 'currency'),
            customerId: any(named: 'customerId'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, contains('network down'));
      verifyNever(() => gateway.initSheet(any()));
      verifyNever(() => gateway.presentSheet());
    });

    test('kit.payments.stripe — no backend maps to ArxaKitPaymentError', () async {
      final result = await build(backend: null)
          .requestPayment(config: config, items: items);
      expect(result, isA<ArxaKitPaymentError>());
    });

    test('kit.payments.stripe — a pending item maps to ArxaKitPaymentError and never calls the backend',
        () async {
      final result = await provider.requestPayment(
        config: config,
        items: const [
          ArxaKitPaymentItem(
              label: 'Shipping',
              amount: '5.00',
              status: ArxaKitPaymentItemStatus.pending),
        ],
      );

      expect(result, isA<ArxaKitPaymentError>());
      verifyNever(() => backend.createPaymentIntent(
          amountMinor: any(named: 'amountMinor'),
          currency: any(named: 'currency'),
          customerId: any(named: 'customerId')));
    });

    test('kit.payments.stripe — a PayPal config is rejected', () async {
      final result = await provider.requestPayment(
        config: const ArxaKitPayPalConfig(),
        items: items,
      );
      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, contains('does not support'));
    });
  });

  group('ArxaKitFlutterStripeSheetGateway.mapStripeError', () {
    // Pure mapping over flutter_stripe data types — no platform channel.
    test('kit.payments.stripe — Canceled → ArxaKitStripeSheetCancelled', () {
      final error = ArxaKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Canceled),
        ),
      );
      expect(error, isA<ArxaKitStripeSheetCancelled>());
    });

    test('kit.payments.stripe — Failed → ArxaKitStripeSheetDeclined with the localized reason', () {
      final error = ArxaKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Failed,
            localizedMessage: 'Your card was declined.',
          ),
        ),
      );
      expect(error, isA<ArxaKitStripeSheetDeclined>());
      expect((error as ArxaKitStripeSheetDeclined).reason, 'Your card was declined.');
    });

    test('kit.payments.stripe — Timeout → ArxaKitStripeSheetError', () {
      final error = ArxaKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Timeout),
        ),
      );
      expect(error, isA<ArxaKitStripeSheetError>());
    });

    test('kit.payments.stripe — Unknown → ArxaKitStripeSheetError falling back to the message', () {
      final error = ArxaKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Unknown,
            message: 'something broke',
          ),
        ),
      );
      expect(error, isA<ArxaKitStripeSheetError>());
      expect((error as ArxaKitStripeSheetError).message, 'something broke');
    });

    test('kit.payments.stripe — non-Stripe exceptions wrap as ArxaKitStripeSheetError', () {
      final error = ArxaKitFlutterStripeSheetGateway.mapStripeError('boom');
      expect(error, isA<ArxaKitStripeSheetError>());
      expect((error as ArxaKitStripeSheetError).cause, 'boom');
    });
  });
}
