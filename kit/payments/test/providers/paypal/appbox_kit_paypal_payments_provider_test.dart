import 'package:appbox_kit_payments/appbox_kit_payments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements AppBoxKitPayPalBackend {}

class _MockAuthenticator extends Mock implements AppBoxKitWebAuthenticator {}

final _order = AppBoxKitPayPalOrderApproval(
  orderId: '8XS12345AB678901C',
  approvalUrl: _approvalUrl,
);
final _approvalUrl = Uri.parse(
    'https://www.sandbox.paypal.com/checkoutnow?token=8XS12345AB678901C');

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  late _MockBackend backend;
  late _MockAuthenticator authenticator;
  late AppBoxKitPayPalPaymentsProvider provider;

  const config = AppBoxKitPayPalConfig(currencyCode: 'EUR');
  const items = [AppBoxKitPaymentItem(label: 'Total', amount: '49.99')];

  void stubHappyPath() {
    when(() => backend.createOrder(
          amount: any(named: 'amount'),
          currencyCode: any(named: 'currencyCode'),
          returnUrl: any(named: 'returnUrl'),
          cancelUrl: any(named: 'cancelUrl'),
        )).thenAnswer((_) async => _order);
    when(() => authenticator.authenticate(
          url: any(named: 'url'),
          callbackUrlScheme: any(named: 'callbackUrlScheme'),
        )).thenAnswer(
        (_) async => Uri.parse('appbox.paypal://paypalpay?token=${_order.orderId}'));
    when(() => backend.captureOrder(any())).thenAnswer(
        (_) async => const AppBoxKitPayPalCaptureResult(
            status: 'COMPLETED', captureId: '3CX12345AB678901D'));
  }

  setUp(() {
    backend = _MockBackend();
    authenticator = _MockAuthenticator();
    provider = AppBoxKitPayPalPaymentsProvider(
      backend: backend,
      callbackUrlScheme: 'appbox.paypal',
      authenticator: authenticator,
    );
  });

  group('AppBoxKitPayPalPaymentsProvider — contract', () {
    test('kit.payments.paypal — id is "paypal"', () {
      expect(provider.id, 'paypal');
    });

    test('kit.payments.paypal — supports only PayPal — never the native wallets', () {
      expect(provider.supportedMethods, {AppBoxKitPaymentMethod.payPal});
    });

    test('kit.payments.paypal — canPay is static: true for PayPal, false for the wallets', () async {
      expect(await provider.canPay(AppBoxKitPaymentMethod.payPal), isTrue);
      expect(await provider.canPay(AppBoxKitPaymentMethod.applePay), isFalse);
      expect(await provider.canPay(AppBoxKitPaymentMethod.googlePay), isFalse);
    });
  });

  group('AppBoxKitPayPalPaymentsProvider — Orders v2 flow', () {
    test('kit.payments.paypal — success: create → approve → capture, token is the capture id',
        () async {
      stubHappyPath();

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentSuccess>());
      final success = result as AppBoxKitPaymentSuccess;
      expect(success.token, '3CX12345AB678901D');
      expect(success.method, AppBoxKitPaymentMethod.payPal);
      expect(success.raw['orderId'], _order.orderId);

      // Decimal total + config currency; return URLs derive from the scheme.
      verify(() => backend.createOrder(
            amount: '49.99',
            currencyCode: 'EUR',
            returnUrl: 'appbox.paypal://paypalpay',
            cancelUrl: 'appbox.paypal://paypalcancel',
          )).called(1);
      verify(() => authenticator.authenticate(
          url: _order.approvalUrl,
          callbackUrlScheme: 'appbox.paypal')).called(1);
      verify(() => backend.captureOrder(_order.orderId)).called(1);
    });

    test('kit.payments.paypal — buyer back-out maps to AppBoxKitPaymentCancelled and never captures',
        () async {
      stubHappyPath();
      when(() => authenticator.authenticate(
            url: any(named: 'url'),
            callbackUrlScheme: any(named: 'callbackUrlScheme'),
          )).thenThrow(const AppBoxKitWebAuthCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<AppBoxKitPaymentCancelled>());
      verifyNever(() => backend.captureOrder(any()));
    });

    test('kit.payments.paypal — order creation failure maps to AppBoxKitPaymentError and never opens the web '
        'session', () async {
      when(() => backend.createOrder(
            amount: any(named: 'amount'),
            currencyCode: any(named: 'currencyCode'),
            returnUrl: any(named: 'returnUrl'),
            cancelUrl: any(named: 'cancelUrl'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, contains('network down'));
      verifyNever(() => authenticator.authenticate(
          url: any(named: 'url'),
          callbackUrlScheme: any(named: 'callbackUrlScheme')));
    });

    test('kit.payments.paypal — declined capture maps to AppBoxKitPaymentDeclined with the reason', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any())).thenAnswer((_) async =>
          const AppBoxKitPayPalCaptureResult(
              status: 'DECLINED', declineReason: 'INSTRUMENT_DECLINED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentDeclined>());
      expect((result as AppBoxKitPaymentDeclined).reason, 'INSTRUMENT_DECLINED');
    });

    test('kit.payments.paypal — an unexpected capture status maps to AppBoxKitPaymentError', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any()))
          .thenAnswer((_) async => const AppBoxKitPayPalCaptureResult(status: 'VOIDED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, contains('VOIDED'));
    });

    test('kit.payments.paypal — a wallet config is rejected', () async {
      final result = await provider.requestPayment(
        config: const AppBoxKitApplePayConfig.fromJson('{}'),
        items: items,
      );
      expect(result, isA<AppBoxKitPaymentError>());
      expect(
          (result as AppBoxKitPaymentError).message, contains('requires a AppBoxKitPayPalConfig'));
    });

    test('kit.payments.paypal — a pending item maps to AppBoxKitPaymentError and never calls the backend',
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
      verifyNever(() => backend.createOrder(
          amount: any(named: 'amount'),
          currencyCode: any(named: 'currencyCode')));
    });
  });

  group('AppBoxKitPayPalPaymentsProvider — registry integration', () {
    test('kit.payments.paypal — routes through DefaultAppBoxKitPaymentsService like any provider',
        () async {
      stubHappyPath();
      final service = DefaultAppBoxKitPaymentsService(
        AppBoxKitPaymentsProviderRegistry([provider]),
      );

      expect(await service.canPay(AppBoxKitPaymentMethod.payPal), isTrue);
      expect(await service.requestPayment(config: config, items: items),
          isA<AppBoxKitPaymentSuccess>());
    });
  });
}
