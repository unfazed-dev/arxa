import 'package:flutter_stripe/flutter_stripe.dart';

import '../../models/kit_payment_config.dart';
import '../../models/kit_payment_item.dart';
import '../../models/kit_payment_method.dart';
import '../../models/payment_result.dart';
import '../kit_payments_provider.dart';

/// What the server hands back after creating a PaymentIntent. The secret key
/// never leaves the server; the app receives only the client secret (plus the
/// optional customer pairing for saved-card display).
class StripePaymentIntent {
  /// The PaymentIntent client secret (`pi_…_secret_…`).
  final String clientSecret;

  /// Stripe Customer id, when the server attached one.
  final String? customerId;

  /// Ephemeral key for [customerId], required by the sheet when a customer
  /// is attached.
  final String? customerEphemeralKeySecret;

  const StripePaymentIntent({
    required this.clientSecret,
    this.customerId,
    this.customerEphemeralKeySecret,
  });

  /// The `pi_…` id embedded in [clientSecret] — used as the [PaymentSuccess]
  /// token so the server can reconcile/capture.
  String get id => clientSecret.split('_secret').first;
}

/// Server-side seam for PaymentIntent creation. The actual
/// `POST /v1/payment_intents` call belongs on your backend (it needs the
/// secret key); implement this over your API client.
abstract interface class KitStripeBackend {
  /// Creates a PaymentIntent for [amountMinor] (smallest currency unit) in
  /// [currency] (ISO 4217 lowercase), optionally bound to [customerId].
  Future<StripePaymentIntent> createPaymentIntent({
    required int amountMinor,
    required String currency,
    String? customerId,
  });
}

/// Everything [StripeSheetGateway.initSheet] needs, in SDK-free terms so the
/// provider and its tests never import `flutter_stripe`.
class StripeSheetConfig {
  final String publishableKey;
  final String? merchantIdentifier;
  final String clientSecret;
  final String merchantDisplayName;
  final String merchantCountryCode;
  final String currencyCode;
  final String? customerId;
  final String? customerEphemeralKeySecret;

  /// Offer Apple Pay in the sheet (requires [merchantIdentifier]).
  final bool applePayEnabled;

  /// Offer Google Pay in the sheet.
  final bool googlePayEnabled;

  /// Google Pay test environment flag.
  final bool googlePayTestEnv;

  const StripeSheetConfig({
    required this.publishableKey,
    required this.clientSecret,
    required this.merchantDisplayName,
    required this.merchantCountryCode,
    required this.currencyCode,
    this.merchantIdentifier,
    this.customerId,
    this.customerEphemeralKeySecret,
    this.applePayEnabled = false,
    this.googlePayEnabled = false,
    this.googlePayTestEnv = true,
  });
}

/// The user dismissed the PaymentSheet. Maps to [PaymentCancelled].
class StripeSheetCancelled implements Exception {
  const StripeSheetCancelled();

  @override
  String toString() => 'StripeSheetCancelled()';
}

/// The payment instrument was rejected (card declined, risk block). Maps to
/// [PaymentDeclined]; [reason] is the SDK's localized/decline message.
class StripeSheetDeclined implements Exception {
  final String? reason;
  const StripeSheetDeclined([this.reason]);

  @override
  String toString() => 'StripeSheetDeclined($reason)';
}

/// Anything else the SDK threw (misconfiguration, network). Maps to
/// [PaymentError].
class StripeSheetError implements Exception {
  final String message;
  final Object? cause;
  const StripeSheetError(this.message, {this.cause});

  @override
  String toString() => 'StripeSheetError($message)';
}

/// SDK seam over the PaymentSheet. The real implementation is
/// [FlutterStripeSheetGateway]; tests substitute a mock so no platform
/// channel is ever touched.
abstract interface class StripeSheetGateway {
  /// Applies the publishable key and initialises the sheet.
  Future<void> initSheet(StripeSheetConfig config);

  /// Presents the sheet; completes only on a confirmed payment, and throws
  /// [StripeSheetCancelled] / [StripeSheetDeclined] / [StripeSheetError]
  /// otherwise.
  Future<void> presentSheet();
}

/// [StripeSheetGateway] over `flutter_stripe`'s PaymentSheet (the supported
/// surface — CardField/CardForm are sunset). Card entry, Apple Pay, Google
/// Pay and 3DS all run inside the one sheet.
class FlutterStripeSheetGateway implements StripeSheetGateway {
  const FlutterStripeSheetGateway();

  @override
  Future<void> initSheet(StripeSheetConfig config) async {
    Stripe.publishableKey = config.publishableKey;
    final merchantId = config.merchantIdentifier;
    if (merchantId != null) Stripe.merchantIdentifier = merchantId;
    await Stripe.instance.applySettings();
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: config.clientSecret,
          merchantDisplayName: config.merchantDisplayName,
          customerId: config.customerId,
          customerEphemeralKeySecret: config.customerEphemeralKeySecret,
          applePay: config.applePayEnabled
              ? PaymentSheetApplePay(
                  merchantCountryCode: config.merchantCountryCode,
                )
              : null,
          googlePay: config.googlePayEnabled
              ? PaymentSheetGooglePay(
                  merchantCountryCode: config.merchantCountryCode,
                  currencyCode: config.currencyCode,
                  testEnv: config.googlePayTestEnv,
                )
              : null,
        ),
      );
    } on StripeException catch (error) {
      throw mapStripeError(error);
    }
  }

  @override
  Future<void> presentSheet() async {
    try {
      await Stripe.instance.presentPaymentSheet();
    } catch (error) {
      throw mapStripeError(error);
    }
  }

  /// Maps a `flutter_stripe` failure onto the gateway's exception taxonomy.
  /// Exposed for tests — the platform channel can't run in a unit test, but
  /// this mapping is pure and is where cancel/decline/error get split.
  static Exception mapStripeError(Object error) {
    if (error is StripeException) {
      final code = error.error.code;
      final message = error.error.localizedMessage ??
          error.error.message ??
          error.error.declineCode;
      return switch (code) {
        FailureCode.Canceled => const StripeSheetCancelled(),
        // The sheet reports card declines as Failed — distinct from a broken
        // integration, so callers retry with a different payment method.
        FailureCode.Failed => StripeSheetDeclined(message),
        FailureCode.Timeout ||
        FailureCode.Unknown =>
          StripeSheetError(message ?? 'Stripe payment failed', cause: error),
      };
    }
    return StripeSheetError(error.toString(), cause: error);
  }
}

/// Stripe backend over `flutter_stripe`'s PaymentSheet. Fulfils the same
/// [KitPaymentMethod.applePay] / [KitPaymentMethod.googlePay] slots as the
/// native provider — register it *after* [PayPaymentsProvider] as a fallback,
/// or instead of it when Stripe should front the wallets (its sheet also
/// takes raw card entry, which the native provider cannot).
///
/// Flow (mirrors the Tier-1 spec in `appboxd/lib/tier1.dart`): init with the
/// publishable key → create a PaymentIntent via [KitStripeBackend] (secret
/// stays server-side) → init + present the sheet.
///
/// Test-mode aware: [googlePayTestEnv] defaults to true when
/// [publishableKey] starts with `pk_test_`, so Google Pay runs in the test
/// environment on emulators without extra wiring. Apple Pay works on the iOS
/// simulator in Stripe test mode with dummy payment data.
class StripePaymentsProvider implements KitPaymentsProvider {
  /// Stripe publishable key (`pk_test_…` / `pk_live_…`). Safe to ship in the
  /// app; the secret key never leaves the server.
  final String publishableKey;

  /// Apple Pay merchant identifier (`merchant.com.…`). When null, Apple Pay
  /// is not offered in the sheet.
  final String? merchantIdentifier;

  /// Name shown on the PaymentSheet.
  final String merchantDisplayName;

  /// Two-letter ISO 3166 country of the business (Apple/Google Pay config).
  final String merchantCountryCode;

  /// ISO 4217 currency the PaymentIntent is created in.
  final String currencyCode;

  /// Whether Google Pay runs in its test environment. Defaults to true for
  /// `pk_test_…` keys.
  final bool googlePayTestEnv;

  /// Optional Stripe Customer id forwarded to intent creation.
  final String? customerId;

  /// Server-side PaymentIntent seam. When null the provider cannot pay —
  /// [canPay] reports false.
  final KitStripeBackend? backend;

  final StripeSheetGateway _gateway;

  StripePaymentsProvider({
    required this.publishableKey,
    required this.backend,
    this.merchantIdentifier,
    this.merchantDisplayName = 'appbox',
    this.merchantCountryCode = 'US',
    this.currencyCode = 'usd',
    bool? googlePayTestEnv,
    this.customerId,
    StripeSheetGateway? gateway,
  })  : googlePayTestEnv =
            googlePayTestEnv ?? publishableKey.startsWith('pk_test_'),
        _gateway = gateway ?? const FlutterStripeSheetGateway();

  @override
  String get id => 'stripe';

  @override
  Set<KitPaymentMethod> get supportedMethods => {
        if (merchantIdentifier != null) KitPaymentMethod.applePay,
        KitPaymentMethod.googlePay,
      };

  @override
  Future<bool> canPay(KitPaymentMethod method) async =>
      backend != null && supportedMethods.contains(method);

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) async {
    final method = config.method;
    if (!supportedMethods.contains(method)) {
      return PaymentError('StripePaymentsProvider does not support $method');
    }
    final backend = this.backend;
    if (backend == null) {
      return const PaymentError(
          'StripePaymentsProvider has no backend (PaymentIntents are created server-side)');
    }
    final amountMinor = _totalMinor(items);
    if (amountMinor == null) {
      return const PaymentError(
          'StripePaymentsProvider requires final-priced items');
    }
    try {
      final intent = await backend.createPaymentIntent(
        amountMinor: amountMinor,
        currency: currencyCode,
        customerId: customerId,
      );
      await _gateway.initSheet(
        StripeSheetConfig(
          publishableKey: publishableKey,
          merchantIdentifier: merchantIdentifier,
          clientSecret: intent.clientSecret,
          merchantDisplayName: merchantDisplayName,
          merchantCountryCode: merchantCountryCode,
          currencyCode: currencyCode,
          customerId: intent.customerId,
          customerEphemeralKeySecret: intent.customerEphemeralKeySecret,
          applePayEnabled: merchantIdentifier != null,
          googlePayEnabled: true,
          googlePayTestEnv: googlePayTestEnv,
        ),
      );
      await _gateway.presentSheet();
      return PaymentSuccess(
        token: intent.id,
        method: method,
        raw: {'provider': 'stripe', 'paymentIntentId': intent.id},
      );
    } on StripeSheetCancelled {
      return const PaymentCancelled();
    } on StripeSheetDeclined catch (error) {
      return PaymentDeclined(reason: error.reason);
    } on StripeSheetError catch (error) {
      return PaymentError(error.message, cause: error.cause);
    } catch (error) {
      // Backend threw (network, 4xx) or an unexpected gateway failure.
      return PaymentError(error.toString(), cause: error);
    }
  }

  /// Sums final-priced items to minor units. Returns null when any item is
  /// pending or unparseable — charging a guessed total is worse than failing.
  // kimitail: assumes 2-decimal currencies; JPY/KRW (0-decimal) need a
  // currency→exponent table if ever supported.
  static int? _totalMinor(List<KitPaymentItem> items) {
    var total = 0;
    for (final item in items) {
      if (item.status != KitPaymentItemStatus.finalPrice) return null;
      final amount = double.tryParse(item.amount);
      if (amount == null) return null;
      total += (amount * 100).round();
    }
    return total;
  }
}
