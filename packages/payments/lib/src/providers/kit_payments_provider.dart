import '../models/kit_payment_config.dart';
import '../models/kit_payment_item.dart';
import '../models/kit_payment_method.dart';
import '../models/payment_result.dart';

/// A pluggable payment backend. The native Apple/Google Pay provider is the
/// one implemented today; Stripe and PayPal ship as stubs of this exact shape
/// so they slot into the registry later without touching call sites.
///
/// A provider is responsible for one or more [KitPaymentMethod]s (see
/// [supportedMethods]). [KitPaymentsService] routes each request to the first
/// registered provider whose [supportedMethods] contains the config's method.
abstract interface class KitPaymentsProvider {
  /// Stable identifier for logging / registry keys (e.g. `'native_pay'`,
  /// `'stripe'`, `'paypal'`).
  String get id;

  /// The wallets this provider can fulfil.
  Set<KitPaymentMethod> get supportedMethods;

  /// Whether the device + configuration can start a payment with [method].
  /// Returns false (never throws) for an unsupported or unconfigured method.
  Future<bool> canPay(KitPaymentMethod method);

  /// Presents the payment sheet for [config] and resolves to a typed result.
  /// Implementations MUST map user dismissal to [PaymentCancelled] and never
  /// let a wallet exception escape — return [PaymentError] / [PaymentDeclined]
  /// instead.
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  });
}

/// An ordered set of providers keyed by the methods they support. First
/// registration for a given method wins, so register the native provider
/// before any fallback.
class KitPaymentsProviderRegistry {
  final List<KitPaymentsProvider> _providers;

  KitPaymentsProviderRegistry([List<KitPaymentsProvider>? providers])
      : _providers = List.of(providers ?? const []);

  /// All registered providers, in registration order.
  List<KitPaymentsProvider> get providers => List.unmodifiable(_providers);

  /// Appends [provider]. Later registrations are lower priority.
  void register(KitPaymentsProvider provider) => _providers.add(provider);

  /// The highest-priority provider that supports [method], or null.
  KitPaymentsProvider? providerFor(KitPaymentMethod method) {
    for (final provider in _providers) {
      if (provider.supportedMethods.contains(method)) return provider;
    }
    return null;
  }
}
