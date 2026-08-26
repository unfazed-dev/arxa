import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_payments/arxa_kit_payments.dart';

void main() {
  // The seed provider never parses the JSON, so an empty document is enough.
  final config = ArxaKitApplePayConfig.fromJson('{}');
  const items = [ArxaKitPaymentItem(label: 'Total', amount: '10.00')];

  Future<ArxaKitPaymentResult> request(ArxaKitSeedPaymentsProvider p) =>
      p.requestPayment(config: config, items: items);

  group('ArxaKitSeedPaymentsProvider — contract', () {
    test('kit.payments.seed — id is "seed"', () {
      expect(ArxaKitSeedPaymentsProvider().id, 'seed');
    });

    test('kit.payments.seed — supports both wallets by default', () {
      expect(
        ArxaKitSeedPaymentsProvider().supportedMethods,
        {ArxaKitPaymentMethod.applePay, ArxaKitPaymentMethod.googlePay},
      );
    });

    test('kit.payments.seed — supportedMethods is constrained to the override', () {
      final provider = ArxaKitSeedPaymentsProvider(
        supportedMethods: {ArxaKitPaymentMethod.googlePay},
      );
      expect(provider.supportedMethods, {ArxaKitPaymentMethod.googlePay});
    });

    test('kit.payments.seed — canPay is true for supported, false for unsupported', () async {
      final provider = ArxaKitSeedPaymentsProvider(
        supportedMethods: {ArxaKitPaymentMethod.applePay},
      );
      expect(await provider.canPay(ArxaKitPaymentMethod.applePay), isTrue);
      expect(await provider.canPay(ArxaKitPaymentMethod.googlePay), isFalse);
    });
  });

  group('ArxaKitSeedPaymentsProvider — profiles', () {
    test('kit.payments.seed — succeed (default) returns ArxaKitPaymentSuccess mirroring native shape',
        () async {
      final provider = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedSucceed());
      final result = await request(provider);

      expect(result, isA<ArxaKitPaymentSuccess>());
      final success = result as ArxaKitPaymentSuccess;
      expect(success.method, ArxaKitPaymentMethod.applePay);
      expect(success.token, 'seed_token_apple_pay');
      expect(success.raw['provider'], 'seed');
      expect(success.raw['profile'], 'succeed');
    });

    test('kit.payments.seed — decline returns ArxaKitPaymentDeclined with the given reason', () async {
      final provider = ArxaKitSeedPaymentsProvider(
        profile: const ArxaKitSeedDecline(reason: 'insufficient_funds'),
      );
      final result = await request(provider);

      expect(result, isA<ArxaKitPaymentDeclined>());
      expect((result as ArxaKitPaymentDeclined).reason, 'insufficient_funds');
    });

    test('kit.payments.seed — decline defaults to a null reason', () async {
      final provider = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedDecline());
      final result = await request(provider);
      expect(result, isA<ArxaKitPaymentDeclined>());
      expect((result as ArxaKitPaymentDeclined).reason, isNull);
    });

    test('kit.payments.seed — cancel returns ArxaKitPaymentCancelled', () async {
      final provider = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedCancel());
      final result = await request(provider);
      expect(result, isA<ArxaKitPaymentCancelled>());
    });

    test('kit.payments.seed — timeout resolves to ArxaKitPaymentError after the duration', () async {
      final provider = ArxaKitSeedPaymentsProvider(
        profile: const ArxaKitSeedTimeout(Duration(milliseconds: 5)),
      );
      final stopwatch = Stopwatch()..start();
      final result = await request(provider);
      stopwatch.stop();

      expect(result, isA<ArxaKitPaymentError>());
      expect((result as ArxaKitPaymentError).message, contains('timed out'));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(5));
    });
  });

  group('ArxaKitSeedPaymentsProvider — runtime mutation', () {
    test('kit.payments.seed — flipping the profile changes the next result', () async {
      final provider = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedSucceed());

      expect(await request(provider), isA<ArxaKitPaymentSuccess>());

      provider.profile = const ArxaKitSeedDecline();
      expect(await request(provider), isA<ArxaKitPaymentDeclined>());

      provider.profile = const ArxaKitSeedCancel();
      expect(await request(provider), isA<ArxaKitPaymentCancelled>());

      provider.profile =
          const ArxaKitSeedTimeout(Duration(milliseconds: 1));
      expect(await request(provider), isA<ArxaKitPaymentError>());

      provider.profile = const ArxaKitSeedSucceed();
      expect(await request(provider), isA<ArxaKitPaymentSuccess>());
    });

    test('kit.payments.seed — two providers hold independent profiles', () async {
      final a = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedSucceed());
      final b = ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedCancel());

      expect(await request(a), isA<ArxaKitPaymentSuccess>());
      expect(await request(b), isA<ArxaKitPaymentCancelled>());

      a.profile = const ArxaKitSeedDecline();
      // b was untouched
      expect(await request(b), isA<ArxaKitPaymentCancelled>());
      expect(await request(a), isA<ArxaKitPaymentDeclined>());
    });
  });

  group('ArxaKitSeedPaymentsProvider — registry integration', () {
    test('kit.payments.seed — plugs into DefaultArxaKitPaymentsService like a real provider', () async {
      final service = DefaultArxaKitPaymentsService(
        ArxaKitPaymentsProviderRegistry([
          ArxaKitSeedPaymentsProvider(profile: const ArxaKitSeedSucceed()),
        ]),
      );

      expect(
        await service.requestPayment(config: config, items: items),
        isA<ArxaKitPaymentSuccess>(),
      );
    });

    test('kit.payments.seed — canPay flows through the service', () async {
      final service = DefaultArxaKitPaymentsService(
        ArxaKitPaymentsProviderRegistry([ArxaKitSeedPaymentsProvider()]),
      );
      expect(await service.canPay(ArxaKitPaymentMethod.applePay), isTrue);
    });
  });
}
