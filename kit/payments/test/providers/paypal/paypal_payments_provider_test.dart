import 'package:appbox_kit_payments/appbox_kit_payments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements KitPayPalBackend {}

class _MockAuthenticator extends Mock implements KitWebAuthenticator {}

final _order = PayPalOrderApproval(
  orderId: '8XS12345AB678901C',
  approvalUrl: _approvalUrl,
);
final _approvalUrl = Uri.parse(
    'https://www.sandbox.paypal.com/checkoutnow?token=8XS12345AB678901C');

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  late _MockBackend backend;
  late _MockAuthenticator authenticator;
  late PayPalPaymentsProvider provider;

  const config = PayPalConfig(currencyCode: 'EUR');
  const items = [KitPaymentItem(label: 'Total', amount: '49.99')];

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
        (_) async => const PayPalCaptureResult(
            status: 'COMPLETED', captureId: '3CX12345AB678901D'));
  }

  setUp(() {
    backend = _MockBackend();
    authenticator = _MockAuthenticator();
    provider = PayPalPaymentsProvider(
      backend: backend,
      callbackUrlScheme: 'appbox.paypal',
      authenticator: authenticator,
    );
  });

  group('PayPalPaymentsProvider — contract', () {
    test('id is "paypal"', () {
      expect(provider.id, 'paypal');
    });

    test('supports only PayPal — never the native wallets', () {
      expect(provider.supportedMethods, {KitPaymentMethod.payPal});
    });

    test('canPay is static: true for PayPal, false for the wallets', () async {
      expect(await provider.canPay(KitPaymentMethod.payPal), isTrue);
      expect(await provider.canPay(KitPaymentMethod.applePay), isFalse);
      expect(await provider.canPay(KitPaymentMethod.googlePay), isFalse);
    });
  });

  group('PayPalPaymentsProvider — Orders v2 flow', () {
    test('success: create → approve → capture, token is the capture id',
        () async {
      stubHappyPath();

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentSuccess>());
      final success = result as PaymentSuccess;
      expect(success.token, '3CX12345AB678901D');
      expect(success.method, KitPaymentMethod.payPal);
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

    test('buyer back-out maps to PaymentCancelled and never captures',
        () async {
      stubHappyPath();
      when(() => authenticator.authenticate(
            url: any(named: 'url'),
            callbackUrlScheme: any(named: 'callbackUrlScheme'),
          )).thenThrow(const WebAuthCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<PaymentCancelled>());
      verifyNever(() => backend.captureOrder(any()));
    });

    test('order creation failure maps to PaymentError and never opens the web '
        'session', () async {
      when(() => backend.createOrder(
            amount: any(named: 'amount'),
            currencyCode: any(named: 'currencyCode'),
            returnUrl: any(named: 'returnUrl'),
            cancelUrl: any(named: 'cancelUrl'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, contains('network down'));
      verifyNever(() => authenticator.authenticate(
          url: any(named: 'url'),
          callbackUrlScheme: any(named: 'callbackUrlScheme')));
    });

    test('declined capture maps to PaymentDeclined with the reason', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any())).thenAnswer((_) async =>
          const PayPalCaptureResult(
              status: 'DECLINED', declineReason: 'INSTRUMENT_DECLINED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentDeclined>());
      expect((result as PaymentDeclined).reason, 'INSTRUMENT_DECLINED');
    });

    test('an unexpected capture status maps to PaymentError', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any()))
          .thenAnswer((_) async => const PayPalCaptureResult(status: 'VOIDED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, contains('VOIDED'));
    });

    test('a wallet config is rejected', () async {
      final result = await provider.requestPayment(
        config: const ApplePayConfig.fromJson('{}'),
        items: items,
      );
      expect(result, isA<PaymentError>());
      expect(
          (result as PaymentError).message, contains('requires a PayPalConfig'));
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
      verifyNever(() => backend.createOrder(
          amount: any(named: 'amount'),
          currencyCode: any(named: 'currencyCode')));
    });
  });

  group('PayPalPaymentsProvider — registry integration', () {
    test('routes through DefaultKitPaymentsService like any provider',
        () async {
      stubHappyPath();
      final service = DefaultKitPaymentsService(
        KitPaymentsProviderRegistry([provider]),
      );

      expect(await service.canPay(KitPaymentMethod.payPal), isTrue);
      expect(await service.requestPayment(config: config, items: items),
          isA<PaymentSuccess>());
    });
  });
}
