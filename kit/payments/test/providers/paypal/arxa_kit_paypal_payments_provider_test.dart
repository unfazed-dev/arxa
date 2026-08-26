import 'package:arxa_kit_payments/arxa_kit_payments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBackend extends Mock implements ArxaKitPayPalBackend {}

class _MockAuthenticator extends Mock implements ArxaKitWebAuthenticator {}

final _order = ArxaKitPayPalOrderApproval(
  orderId: '8XS12345AB678901C',
  approvalUrl: _approvalUrl,
);
final _approvalUrl = Uri.parse(
    'https://www.sandbox.paypal.com/checkoutnow?token=8XS12345AB678901C');

void main() {
  setUpAll(() => registerFallbackValue(Uri()));

  late _MockBackend backend;
  late _MockAuthenticator authenticator;
  late ArxaKitPayPalPaymentsProvider provider;

  const config = ArxaKitPayPalConfig(currencyCode: 'EUR');
  const items = [ArxaKitPaymentItem(label: 'Total', amount: '49.99')];

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
        (_) async => Uri.parse('arxa.paypal://paypalpay?token=${_order.orderId}'));
    when(() => backend.captureOrder(any())).thenAnswer(
        (_) async => const ArxaKitPayPalCaptureResult(
            status: 'COMPLETED', captureId: '3CX12345AB678901D'));
  }

  setUp(() {
    backend = _MockBackend();
    authenticator = _MockAuthenticator();
    provider = ArxaKitPayPalPaymentsProvider(
      backend: backend,
      callbackUrlScheme: 'arxa.paypal',
      authenticator: authenticator,
    );
  });

  group('ArxaKitPayPalPaymentsProvider — contract', () {
    test('kit.payments.paypal — id is "paypal"', () {
      expect(provider.id, 'paypal');
    });

    test('kit.payments.paypal — supports only PayPal — never the native wallets', () {
      expect(provider.supportedMethods, {ArxaKitPaymentMethod.payPal});
    });

    test('kit.payments.paypal — canPay is static: true for PayPal, false for the wallets', () async {
      expect(await provider.canPay(ArxaKitPaymentMethod.payPal), isTrue);
      expect(await provider.canPay(ArxaKitPaymentMethod.applePay), isFalse);
      expect(await provider.canPay(ArxaKitPaymentMethod.googlePay), isFalse);
    });
  });

  group('ArxaKitPayPalPaymentsProvider — Orders v2 flow', () {
    test('kit.payments.paypal — success: create → approve → capture, token is the capture id',
        () async {
      stubHappyPath();

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentSuccess>());
      final success = result as ArxaKitPaymentSuccess;
      expect(success.token, '3CX12345AB678901D');
      expect(success.method, ArxaKitPaymentMethod.payPal);
      expect(success.raw['orderId'], _order.orderId);

      // Decimal total + config currency; return URLs derive from the scheme.
      verify(() => backend.createOrder(
            amount: '49.99',
            currencyCode: 'EUR',
            returnUrl: 'arxa.paypal://paypalpay',
            cancelUrl: 'arxa.paypal://paypalcancel',
          )).called(1);
      verify(() => authenticator.authenticate(
          url: _order.approvalUrl,
          callbackUrlScheme: 'arxa.paypal')).called(1);
      verify(() => backend.captureOrder(_order.orderId)).called(1);
    });

    test('kit.payments.paypal — buyer back-out maps to ArxaKitPaymentCancelled and never captures',
        () async {
      stubHappyPath();
      when(() => authenticator.authenticate(
            url: any(named: 'url'),
            callbackUrlScheme: any(named: 'callbackUrlScheme'),
          )).thenThrow(const ArxaKitWebAuthCancelled());

      expect(await provider.requestPayment(config: config, items: items),
          isA<ArxaKitPaymentCancelled>());
      verifyNever(() => backend.captureOrder(any()));
    });

    test('kit.payments.paypal — order creation failure maps to ArxaKitPaymentError and never opens the web '
        'session', () async {
      when(() => backend.createOrder(
            amount: any(named: 'amount'),
            currencyCode: any(named: 'currencyCode'),
            returnUrl: any(named: 'returnUrl'),
            cancelUrl: any(named: 'cancelUrl'),
          )).thenThrow(Exception('network down'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, contains('network down'));
      verifyNever(() => authenticator.authenticate(
          url: any(named: 'url'),
          callbackUrlScheme: any(named: 'callbackUrlScheme')));
    });

    test('kit.payments.paypal — declined capture maps to ArxaKitPaymentDeclined with the reason', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any())).thenAnswer((_) async =>
          const ArxaKitPayPalCaptureResult(
              status: 'DECLINED', declineReason: 'INSTRUMENT_DECLINED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentDeclined>());
      expect((result as ArxaKitPaymentDeclined).reason, 'INSTRUMENT_DECLINED');
    });

    test('kit.payments.paypal — an unexpected capture status maps to ArxaKitPaymentError', () async {
      stubHappyPath();
      when(() => backend.captureOrder(any()))
          .thenAnswer((_) async => const ArxaKitPayPalCaptureResult(status: 'VOIDED'));

      final result =
          await provider.requestPayment(config: config, items: items);

      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, contains('VOIDED'));
    });

    test('kit.payments.paypal — a wallet config is rejected', () async {
      final result = await provider.requestPayment(
        config: const ArxaKitApplePayConfig.fromJson('{}'),
        items: items,
      );
      expect(result, isA<ArxaKitPaymentError>());
      expect(
          (result as ArxaKitPaymentError).message, contains('requires a ArxaKitPayPalConfig'));
    });

    test('kit.payments.paypal — a pending item maps to ArxaKitPaymentError and never calls the backend',
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
      verifyNever(() => backend.createOrder(
          amount: any(named: 'amount'),
          currencyCode: any(named: 'currencyCode')));
    });
  });

  group('ArxaKitPayPalPaymentsProvider — registry integration', () {
    test('kit.payments.paypal — routes through DefaultArxaKitPaymentsService like any provider',
        () async {
      stubHappyPath();
      final service = DefaultArxaKitPaymentsService(
        ArxaKitPaymentsProviderRegistry([provider]),
      );

      expect(await service.canPay(ArxaKitPaymentMethod.payPal), isTrue);
      expect(await service.requestPayment(config: config, items: items),
          isA<ArxaKitPaymentSuccess>());
    });
  });
}
