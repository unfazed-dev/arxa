import '../models/appbox_kit_payment_config.dart';
import '../models/appbox_kit_payment_item.dart';
import '../models/appbox_kit_payment_method.dart';
import '../models/appbox_kit_payment_result.dart';

/// A pluggable payment backend. The native Apple/Google Pay provider is the
/// one implemented today; Stripe and PayPal ship as stubs of this exact shape
/// so they slot into the registry later without touching call sites.
///
/// A provider is responsible for one or more [AppBoxKitPaymentMethod]s (see
/// [supportedMethods]). [AppBoxKitPaymentsService] routes each request to the first
/// registered provider whose [supportedMethods] contains the config's method.
abstract interface class AppBoxKitPaymentsProvider {
  /// Stable identifier for logging / registry keys (e.g. `'native_pay'`,
  /// `'stripe'`, `'paypal'`).
  String get id;

  /// The wallets this provider can fulfil.
  Set<AppBoxKitPaymentMethod> get supportedMethods;

  /// Whether the device + configuration can start a payment with [method].
  /// Returns false (never throws) for an unsupported or unconfigured method.
  Future<bool> canPay(AppBoxKitPaymentMethod method);

  /// Presents the payment sheet for [config] and resolves to a typed result.
  /// Implementations MUST map user dismissal to [AppBoxKitPaymentCancelled] and never
  /// let a wallet exception escape — return [AppBoxKitPaymentError] / [AppBoxKitPaymentDeclined]
  /// instead.
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  });
}

/// An ordered set of providers keyed by the methods they support. First
/// registration for a given method wins, so register the native provider
/// before any fallback.
class AppBoxKitPaymentsProviderRegistry {
  final List<AppBoxKitPaymentsProvider> _providers;

  AppBoxKitPaymentsProviderRegistry([List<AppBoxKitPaymentsProvider>? providers])
      : _providers = List.of(providers ?? const []);

  /// All registered providers, in registration order.
  List<AppBoxKitPaymentsProvider> get providers => List.unmodifiable(_providers);

  /// Appends [provider]. Later registrations are lower priority.
  void register(AppBoxKitPaymentsProvider provider) => _providers.add(provider);

  /// The highest-priority provider that supports [method], or null.
  AppBoxKitPaymentsProvider? providerFor(AppBoxKitPaymentMethod method) {
    for (final provider in _providers) {
      if (provider.supportedMethods.contains(method)) return provider;
    }
    return null;
  }
}
