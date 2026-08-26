import '../models/arxa_kit_payment_config.dart';
import '../models/arxa_kit_payment_item.dart';
import '../models/arxa_kit_payment_method.dart';
import '../models/arxa_kit_payment_result.dart';
import '../providers/arxa_kit_payments_provider.dart';
import '../providers/native/arxa_kit_pay_payments_provider.dart';

/// The port an app talks to for payments. One method to check availability,
/// one to charge — both delegate to whichever [ArxaKitPaymentsProvider] is
/// registered for the wallet. Kept free of any provider SDK so ViewModels
/// depend only on this and the typed [ArxaKitPaymentResult].
abstract interface class ArxaKitPaymentsService {
  /// Whether the device + configuration can pay with [method] right now.
  Future<bool> canPay(ArxaKitPaymentMethod method);

  /// Presents the payment sheet for [config] with [items] and resolves to a
  /// typed result. Never throws for user dismissal or a wallet error — the
  /// outcome is always a [ArxaKitPaymentResult] branch.
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  });
}

/// Registry-backed [ArxaKitPaymentsService]. Routes each call to the first
/// provider that supports the requested wallet.
class DefaultArxaKitPaymentsService implements ArxaKitPaymentsService {
  final ArxaKitPaymentsProviderRegistry registry;

  DefaultArxaKitPaymentsService(this.registry);

  /// Convenience for the common case: a single native Apple/Google Pay
  /// provider. Pass the profiles you want advertised.
  factory DefaultArxaKitPaymentsService.native({
    ArxaKitApplePayConfig? applePay,
    ArxaKitGooglePayConfig? googlePay,
  }) =>
      DefaultArxaKitPaymentsService(
        ArxaKitPaymentsProviderRegistry([
          ArxaKitPayPaymentsProvider(
            applePayConfig: applePay,
            googlePayConfig: googlePay,
          ),
        ]),
      );

  @override
  Future<bool> canPay(ArxaKitPaymentMethod method) async {
    final provider = registry.providerFor(method);
    if (provider == null) return false;
    return provider.canPay(method);
  }

  @override
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  }) async {
    final provider = registry.providerFor(config.method);
    if (provider == null) {
      return ArxaKitPaymentError('No payment provider registered for ${config.method}');
    }
    return provider.requestPayment(config: config, items: items);
  }
}
