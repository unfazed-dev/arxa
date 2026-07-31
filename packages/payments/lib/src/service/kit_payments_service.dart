import '../models/kit_payment_config.dart';
import '../models/kit_payment_item.dart';
import '../models/kit_payment_method.dart';
import '../models/payment_result.dart';
import '../providers/kit_payments_provider.dart';
import '../providers/native/pay_payments_provider.dart';

/// The port an app talks to for payments. One method to check availability,
/// one to charge — both delegate to whichever [KitPaymentsProvider] is
/// registered for the wallet. Kept free of any provider SDK so ViewModels
/// depend only on this and the typed [PaymentResult].
abstract interface class KitPaymentsService {
  /// Whether the device + configuration can pay with [method] right now.
  Future<bool> canPay(KitPaymentMethod method);

  /// Presents the payment sheet for [config] with [items] and resolves to a
  /// typed result. Never throws for user dismissal or a wallet error — the
  /// outcome is always a [PaymentResult] branch.
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  });
}

/// Registry-backed [KitPaymentsService]. Routes each call to the first
/// provider that supports the requested wallet.
class DefaultKitPaymentsService implements KitPaymentsService {
  final KitPaymentsProviderRegistry registry;

  DefaultKitPaymentsService(this.registry);

  /// Convenience for the common case: a single native Apple/Google Pay
  /// provider. Pass the profiles you want advertised.
  factory DefaultKitPaymentsService.native({
    ApplePayConfig? applePay,
    GooglePayConfig? googlePay,
  }) =>
      DefaultKitPaymentsService(
        KitPaymentsProviderRegistry([
          PayPaymentsProvider(
            applePayConfig: applePay,
            googlePayConfig: googlePay,
          ),
        ]),
      );

  @override
  Future<bool> canPay(KitPaymentMethod method) async {
    final provider = registry.providerFor(method);
    if (provider == null) return false;
    return provider.canPay(method);
  }

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) async {
    final provider = registry.providerFor(config.method);
    if (provider == null) {
      return PaymentError('No payment provider registered for ${config.method}');
    }
    return provider.requestPayment(config: config, items: items);
  }
}
