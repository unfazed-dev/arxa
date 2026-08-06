import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_payments/appbox_kit_payments.dart';

void main() {
  // The seed provider never parses the JSON, so an empty document is enough.
  final config = AppBoxKitApplePayConfig.fromJson('{}');
  const items = [AppBoxKitPaymentItem(label: 'Total', amount: '10.00')];

  Future<AppBoxKitPaymentResult> request(AppBoxKitSeedPaymentsProvider p) =>
      p.requestPayment(config: config, items: items);

  group('AppBoxKitSeedPaymentsProvider — contract', () {
    test('kit.payments.seed — id is "seed"', () {
      expect(AppBoxKitSeedPaymentsProvider().id, 'seed');
    });

    test('kit.payments.seed — supports both wallets by default', () {
      expect(
        AppBoxKitSeedPaymentsProvider().supportedMethods,
        {AppBoxKitPaymentMethod.applePay, AppBoxKitPaymentMethod.googlePay},
      );
    });

    test('kit.payments.seed — supportedMethods is constrained to the override', () {
      final provider = AppBoxKitSeedPaymentsProvider(
        supportedMethods: {AppBoxKitPaymentMethod.googlePay},
      );
      expect(provider.supportedMethods, {AppBoxKitPaymentMethod.googlePay});
    });

    test('kit.payments.seed — canPay is true for supported, false for unsupported', () async {
      final provider = AppBoxKitSeedPaymentsProvider(
        supportedMethods: {AppBoxKitPaymentMethod.applePay},
      );
      expect(await provider.canPay(AppBoxKitPaymentMethod.applePay), isTrue);
      expect(await provider.canPay(AppBoxKitPaymentMethod.googlePay), isFalse);
    });
  });

  group('AppBoxKitSeedPaymentsProvider — profiles', () {
    test('kit.payments.seed — succeed (default) returns AppBoxKitPaymentSuccess mirroring native shape',
        () async {
      final provider = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedSucceed());
      final result = await request(provider);

      expect(result, isA<AppBoxKitPaymentSuccess>());
      final success = result as AppBoxKitPaymentSuccess;
      expect(success.method, AppBoxKitPaymentMethod.applePay);
      expect(success.token, 'seed_token_apple_pay');
      expect(success.raw['provider'], 'seed');
      expect(success.raw['profile'], 'succeed');
    });

    test('kit.payments.seed — decline returns AppBoxKitPaymentDeclined with the given reason', () async {
      final provider = AppBoxKitSeedPaymentsProvider(
        profile: const AppBoxKitSeedDecline(reason: 'insufficient_funds'),
      );
      final result = await request(provider);

      expect(result, isA<AppBoxKitPaymentDeclined>());
      expect((result as AppBoxKitPaymentDeclined).reason, 'insufficient_funds');
    });

    test('kit.payments.seed — decline defaults to a null reason', () async {
      final provider = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedDecline());
      final result = await request(provider);
      expect(result, isA<AppBoxKitPaymentDeclined>());
      expect((result as AppBoxKitPaymentDeclined).reason, isNull);
    });

    test('kit.payments.seed — cancel returns AppBoxKitPaymentCancelled', () async {
      final provider = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedCancel());
      final result = await request(provider);
      expect(result, isA<AppBoxKitPaymentCancelled>());
    });

    test('kit.payments.seed — timeout resolves to AppBoxKitPaymentError after the duration', () async {
      final provider = AppBoxKitSeedPaymentsProvider(
        profile: const AppBoxKitSeedTimeout(Duration(milliseconds: 5)),
      );
      final stopwatch = Stopwatch()..start();
      final result = await request(provider);
      stopwatch.stop();

      expect(result, isA<AppBoxKitPaymentError>());
      expect((result as AppBoxKitPaymentError).message, contains('timed out'));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(5));
    });
  });

  group('AppBoxKitSeedPaymentsProvider — runtime mutation', () {
    test('kit.payments.seed — flipping the profile changes the next result', () async {
      final provider = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedSucceed());

      expect(await request(provider), isA<AppBoxKitPaymentSuccess>());

      provider.profile = const AppBoxKitSeedDecline();
      expect(await request(provider), isA<AppBoxKitPaymentDeclined>());

      provider.profile = const AppBoxKitSeedCancel();
      expect(await request(provider), isA<AppBoxKitPaymentCancelled>());

      provider.profile =
          const AppBoxKitSeedTimeout(Duration(milliseconds: 1));
      expect(await request(provider), isA<AppBoxKitPaymentError>());

      provider.profile = const AppBoxKitSeedSucceed();
      expect(await request(provider), isA<AppBoxKitPaymentSuccess>());
    });

    test('kit.payments.seed — two providers hold independent profiles', () async {
      final a = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedSucceed());
      final b = AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedCancel());

      expect(await request(a), isA<AppBoxKitPaymentSuccess>());
      expect(await request(b), isA<AppBoxKitPaymentCancelled>());

      a.profile = const AppBoxKitSeedDecline();
      // b was untouched
      expect(await request(b), isA<AppBoxKitPaymentCancelled>());
      expect(await request(a), isA<AppBoxKitPaymentDeclined>());
    });
  });

  group('AppBoxKitSeedPaymentsProvider — registry integration', () {
    test('kit.payments.seed — plugs into DefaultAppBoxKitPaymentsService like a real provider', () async {
      final service = DefaultAppBoxKitPaymentsService(
        AppBoxKitPaymentsProviderRegistry([
          AppBoxKitSeedPaymentsProvider(profile: const AppBoxKitSeedSucceed()),
        ]),
      );

      expect(
        await service.requestPayment(config: config, items: items),
        isA<AppBoxKitPaymentSuccess>(),
      );
    });

    test('kit.payments.seed — canPay flows through the service', () async {
      final service = DefaultAppBoxKitPaymentsService(
        AppBoxKitPaymentsProviderRegistry([AppBoxKitSeedPaymentsProvider()]),
      );
      expect(await service.canPay(AppBoxKitPaymentMethod.applePay), isTrue);
    });
  });
}
