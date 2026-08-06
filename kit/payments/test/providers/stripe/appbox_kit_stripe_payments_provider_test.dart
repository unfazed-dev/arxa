import 'package:appbox_kit_payments/appbox_kit_payments.dart';
import 'package:flutter_stripe/flutter_stripe.dart'
    show FailureCode, LocalizedErrorMessage, StripeException;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements AppBoxKitStripeBackend {}

class _MockGateway extends Mock implements AppBoxKitStripeSheetGateway {}

const _fallbackConfig = AppBoxKitStripeSheetConfig(
  publishableKey: 'pk_test_x',
  clientSecret: 'pi_x_secret_y',
  merchantDisplayName: 'x',
  merchantCountryCode: 'US',
  currencyCode: 'usd',
);

const _intent = AppBoxKitStripePaymentIntent(clientSecret: 'pi_demo_123_secret_abc');

void main() {
  setUpAll(() => registerFallbackValue(_fallbackConfig));

  late _MockBackend backend;
  late _MockGateway gateway;
  late AppBoxKitStripePaymentsProvider provider;

  // The provider never parses wallet JSON — the config only picks the method.
  const config = AppBoxKitGooglePayConfig.fromJson('{}');
  const items = [AppBoxKitPaymentItem(label: 'Total', amount: '19.99')];

  AppBoxKitStripePaymentsProvider build({
    AppBoxKitStripeBackend? backend,
    String publishableKey = 'pk_test_abc',
    String? merchantIdentifier = 'merchant.com.appbox',
  }) =>
      AppBoxKitStripePaymentsProvider(
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

  group('AppBoxKitStripePaymentsProvider — contract', () {
    test('id is "stripe"', () {
      expect(provider.id, 'stripe');
    });

    test('supports both wallets when a merchant identifier is set', () {
      expect(provider.supportedMethods,
          {AppBoxKitPaymentMethod.applePay, AppBoxKitPaymentMethod.googlePay});
    });

    test('drops Apple Pay without a merchant identifier', () {
      expect(build(backend: backend, merchantIdentifier: null).supportedMethods,
          {AppBoxKitPaymentMethod.googlePay});
    });

    test('googlePayTestEnv follows the key mode', () {
      expect(provider.googlePayTestEnv, isTrue); // pk_test_
      expect(build(backend: backend, publishableKey: 'pk_live_abc')
          .googlePayTestEnv, isFalse);
    });

    test('canPay is true for a supported method with a backend', () async {
      expect(await provider.canPay(AppBoxKitPaymentMethod.googlePay), isTrue);
      expect(await provider.canPay(AppBoxKitPaymentMethod.applePay), isTrue);
    });

    test('canPay is false without a backend', () async {
      expect(await build(backend: null).canPay(AppBoxKitPaymentMethod.googlePay),
          isFalse);
    });

    test('canPay is false for PayPal', () async {
      expect(await provider.canPay(AppBoxKitPaymentMethod.payPal), isFalse);
    });
  });

  group('AppBoxKitStripePaymentsProvider — PaymentSheet flow', () {
    test('success: intent → init → present, token is the pi_ id', () async {
      stubHappyPath();

      final result = await provider.requestPayment(
          config: config, items: items);

      expect(result, isA<AppBoxKitPaymentSuccess>());
      final success = result as AppBoxKitPaymentSuccess;
      expect(success.token, 'pi_demo_123');
      expect(success.method, AppBoxKitPaymentMethod.googlePay);
      expect(success.raw['paymentIntentId'], 'pi_demo_123');

      // Amount is summed to minor units; currency comes from the provider.
      verify(() => backend.createPaymentIntent(
          amountMinor: 1999, currency: 'usd')).called(1);

      // Sheet got the client secret + wallet toggles for a test key.
      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as AppBoxKitStripeSheetConfig;
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
          )).thenAnswer((_) async => const AppBoxKitStripePaymentIntent(
            clientSecret: 'pi_c_secret_x',
            customerId: 'cus_1',
            customerEphemeralKeySecret: 'ek_1',
          ));
      when(() => gateway.initSheet(any())).thenAnswer((_) async {});
      when(() => gateway.presentSheet()).thenAnswer((_) async {});

      await provider.requestPayment(config: config, items: items);

      final sheetConfig = verify(() => gateway.initSheet(captureAny()))
          .captured
          .single as AppBoxKitStripeSheetConfig;
      expect(sheetConfig.customerId, 'cus_1');
      expect(sheetConfig.customerEphemeralKeySecret, 'ek_1');
    });

    test('user dismissal maps to AppBoxKitPaymentCancelled', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const AppBoxKitStripeSheetCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<AppBoxKitPaymentCancelled>());
    });

    test('card decline maps to AppBoxKitPaymentDeclined with the SDK reason', () async {
      stubHappyPath();
      when(() => gateway.presentSheet())
          .thenThrow(const AppBoxKitStripeSheetDeclined('Your card was declined.'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentDeclined>());
      expect((result as AppBoxKitPaymentDeclined).reason, 'Your card was declined.');
    });

    test('init failure maps to AppBoxKitPaymentError', () async {
      stubHappyPath();
      when(() => gateway.initSheet(any()))
          .thenThrow(const AppBoxKitStripeSheetError('bad client secret'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, 'bad client secret');
    });

    test('backend failure maps to AppBoxKitPaymentError and never shows the sheet',
        () async {
      when(() => backend.createPaymentIntent(
            amountMinor: any(named: 'amountMinor'),
            currency: any(named: 'currency'),
            customerId: any(named: 'customerId'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, contains('network down'));
      verifyNever(() => gateway.initSheet(any()));
      verifyNever(() => gateway.presentSheet());
    });

    test('no backend maps to AppBoxKitPaymentError', () async {
      final result = await build(backend: null)
          .requestPayment(config: config, items: items);
      expect(result, isA<AppBoxKitPaymentError>());
    });

    test('a pending item maps to AppBoxKitPaymentError and never calls the backend',
        () async {
      final result = await provider.requestPayment(
        config: config,
        items: const [
          AppBoxKitPaymentItem(
              label: 'Shipping',
              amount: '5.00',
              status: AppBoxKitPaymentItemStatus.pending),
        ],
      );

      expect(result, isA<AppBoxKitPaymentError>());
      verifyNever(() => backend.createPaymentIntent(
          amountMinor: any(named: 'amountMinor'),
          currency: any(named: 'currency'),
          customerId: any(named: 'customerId')));
    });

    test('a PayPal config is rejected', () async {
      final result = await provider.requestPayment(
        config: const AppBoxKitPayPalConfig(),
        items: items,
      );
      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, contains('does not support'));
    });
  });

  group('AppBoxKitFlutterStripeSheetGateway.mapStripeError', () {
    // Pure mapping over flutter_stripe data types — no platform channel.
    test('Canceled → AppBoxKitStripeSheetCancelled', () {
      final error = AppBoxKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Canceled),
        ),
      );
      expect(error, isA<AppBoxKitStripeSheetCancelled>());
    });

    test('Failed → AppBoxKitStripeSheetDeclined with the localized reason', () {
      final error = AppBoxKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Failed,
            localizedMessage: 'Your card was declined.',
          ),
        ),
      );
      expect(error, isA<AppBoxKitStripeSheetDeclined>());
      expect((error as AppBoxKitStripeSheetDeclined).reason, 'Your card was declined.');
    });

    test('Timeout → AppBoxKitStripeSheetError', () {
      final error = AppBoxKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(code: FailureCode.Timeout),
        ),
      );
      expect(error, isA<AppBoxKitStripeSheetError>());
    });

    test('Unknown → AppBoxKitStripeSheetError falling back to the message', () {
      final error = AppBoxKitFlutterStripeSheetGateway.mapStripeError(
        const StripeException(
          error: LocalizedErrorMessage(
            code: FailureCode.Unknown,
            message: 'something broke',
          ),
        ),
      );
      expect(error, isA<AppBoxKitStripeSheetError>());
      expect((error as AppBoxKitStripeSheetError).message, 'something broke');
    });

    test('non-Stripe exceptions wrap as AppBoxKitStripeSheetError', () {
      final error = AppBoxKitFlutterStripeSheetGateway.mapStripeError('boom');
      expect(error, isA<AppBoxKitStripeSheetError>());
      expect((error as AppBoxKitStripeSheetError).cause, 'boom');
    });
  });
}
