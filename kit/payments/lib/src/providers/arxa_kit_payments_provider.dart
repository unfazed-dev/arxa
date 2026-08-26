import '../models/arxa_kit_payment_config.dart';
import '../models/arxa_kit_payment_item.dart';
import '../models/arxa_kit_payment_method.dart';
import '../models/arxa_kit_payment_result.dart';

/// A pluggable payment backend. The native Apple/Google Pay provider is the
/// one implemented today; Stripe and PayPal ship as stubs of this exact shape
/// so they slot into the registry later without touching call sites.
///
/// A provider is responsible for one or more [ArxaKitPaymentMethod]s (see
/// [supportedMethods]). [ArxaKitPaymentsService] routes each request to the first
/// registered provider whose [supportedMethods] contains the config's method.
abstract interface class ArxaKitPaymentsProvider {
  /// Stable identifier for logging / registry keys (e.g. `'native_pay'`,
  /// `'stripe'`, `'paypal'`).
  String get id;

  /// The wallets this provider can fulfil.
  Set<ArxaKitPaymentMethod> get supportedMethods;

  /// Whether the device + configuration can start a payment with [method].
  /// Returns false (never throws) for an unsupported or unconfigured method.
  Future<bool> canPay(ArxaKitPaymentMethod method);

  /// Presents the payment sheet for [config] and resolves to a typed result.
  /// Implementations MUST map user dismissal to [ArxaKitPaymentCancelled] and never
  /// let a wallet exception escape — return [ArxaKitPaymentError] / [ArxaKitPaymentDeclined]
  /// instead.
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  });
}

/// An ordered set of providers keyed by the methods they support. First
/// registration for a given method wins, so register the native provider
/// before any fallback.
class ArxaKitPaymentsProviderRegistry {
  final List<ArxaKitPaymentsProvider> _providers;

  ArxaKitPaymentsProviderRegistry([List<ArxaKitPaymentsProvider>? providers])
      : _providers = List.of(providers ?? const []);

  /// All registered providers, in registration order.
  List<ArxaKitPaymentsProvider> get providers => List.unmodifiable(_providers);

  /// Appends [provider]. Later registrations are lower priority.
  void register(ArxaKitPaymentsProvider provider) => _providers.add(provider);

  /// The highest-priority provider that supports [method], or null.
  ArxaKitPaymentsProvider? providerFor(ArxaKitPaymentMethod method) {
    for (final provider in _providers) {
      if (provider.supportedMethods.contains(method)) return provider;
    }
    return null;
  }
}
