import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_payments/appbox_kit_payments.dart';

void main() {
  // The seed provider never parses the JSON, so an empty document is enough.
  final config = ApplePayConfig.fromJson('{}');
  const items = [KitPaymentItem(label: 'Total', amount: '10.00')];

  Future<PaymentResult> request(SeedPaymentsProvider p) =>
      p.requestPayment(config: config, items: items);

  group('SeedPaymentsProvider — contract', () {
    test('id is "seed"', () {
      expect(SeedPaymentsProvider().id, 'seed');
    });

    test('supports both wallets by default', () {
      expect(
        SeedPaymentsProvider().supportedMethods,
        {KitPaymentMethod.applePay, KitPaymentMethod.googlePay},
      );
    });

    test('supportedMethods is constrained to the override', () {
      final provider = SeedPaymentsProvider(
        supportedMethods: {KitPaymentMethod.googlePay},
      );
      expect(provider.supportedMethods, {KitPaymentMethod.googlePay});
    });

    test('canPay is true for supported, false for unsupported', () async {
      final provider = SeedPaymentsProvider(
        supportedMethods: {KitPaymentMethod.applePay},
      );
      expect(await provider.canPay(KitPaymentMethod.applePay), isTrue);
      expect(await provider.canPay(KitPaymentMethod.googlePay), isFalse);
    });
  });

  group('SeedPaymentsProvider — profiles', () {
    test('succeed (default) returns PaymentSuccess mirroring native shape',
        () async {
      final provider = SeedPaymentsProvider(profile: const SeedSucceed());
      final result = await request(provider);

      expect(result, isA<PaymentSuccess>());
      final success = result as PaymentSuccess;
      expect(success.method, KitPaymentMethod.applePay);
      expect(success.token, 'seed_token_apple_pay');
      expect(success.raw['provider'], 'seed');
      expect(success.raw['profile'], 'succeed');
    });

    test('decline returns PaymentDeclined with the given reason', () async {
      final provider = SeedPaymentsProvider(
        profile: const SeedDecline(reason: 'insufficient_funds'),
      );
      final result = await request(provider);

      expect(result, isA<PaymentDeclined>());
      expect((result as PaymentDeclined).reason, 'insufficient_funds');
    });

    test('decline defaults to a null reason', () async {
      final provider = SeedPaymentsProvider(profile: const SeedDecline());
      final result = await request(provider);
      expect(result, isA<PaymentDeclined>());
      expect((result as PaymentDeclined).reason, isNull);
    });

    test('cancel returns PaymentCancelled', () async {
      final provider = SeedPaymentsProvider(profile: const SeedCancel());
      final result = await request(provider);
      expect(result, isA<PaymentCancelled>());
    });

    test('timeout resolves to PaymentError after the duration', () async {
      final provider = SeedPaymentsProvider(
        profile: const SeedTimeout(Duration(milliseconds: 5)),
      );
      final stopwatch = Stopwatch()..start();
      final result = await request(provider);
      stopwatch.stop();

      expect(result, isA<PaymentError>());
      expect((result as PaymentError).message, contains('timed out'));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(5));
    });
  });

  group('SeedPaymentsProvider — runtime mutation', () {
    test('flipping the profile changes the next result', () async {
      final provider = SeedPaymentsProvider(profile: const SeedSucceed());

      expect(await request(provider), isA<PaymentSuccess>());

      provider.profile = const SeedDecline();
      expect(await request(provider), isA<PaymentDeclined>());

      provider.profile = const SeedCancel();
      expect(await request(provider), isA<PaymentCancelled>());

      provider.profile =
          const SeedTimeout(Duration(milliseconds: 1));
      expect(await request(provider), isA<PaymentError>());

      provider.profile = const SeedSucceed();
      expect(await request(provider), isA<PaymentSuccess>());
    });

    test('two providers hold independent profiles', () async {
      final a = SeedPaymentsProvider(profile: const SeedSucceed());
      final b = SeedPaymentsProvider(profile: const SeedCancel());

      expect(await request(a), isA<PaymentSuccess>());
      expect(await request(b), isA<PaymentCancelled>());

      a.profile = const SeedDecline();
      // b was untouched
      expect(await request(b), isA<PaymentCancelled>());
      expect(await request(a), isA<PaymentDeclined>());
    });
  });

  group('SeedPaymentsProvider — registry integration', () {
    test('plugs into DefaultKitPaymentsService like a real provider', () async {
      final service = DefaultKitPaymentsService(
        KitPaymentsProviderRegistry([
          SeedPaymentsProvider(profile: const SeedSucceed()),
        ]),
      );

      expect(
        await service.requestPayment(config: config, items: items),
        isA<PaymentSuccess>(),
      );
    });

    test('canPay flows through the service', () async {
      final service = DefaultKitPaymentsService(
        KitPaymentsProviderRegistry([SeedPaymentsProvider()]),
      );
      expect(await service.canPay(KitPaymentMethod.applePay), isTrue);
    });
  });
}
