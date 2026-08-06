import '../models/appbox_kit_payment_config.dart';
import '../models/appbox_kit_payment_item.dart';
import '../models/appbox_kit_payment_method.dart';
import '../models/appbox_kit_payment_result.dart';
import '../providers/appbox_kit_payments_provider.dart';
import '../providers/native/appbox_kit_pay_payments_provider.dart';

/// The port an app talks to for payments. One method to check availability,
/// one to charge — both delegate to whichever [AppBoxKitPaymentsProvider] is
/// registered for the wallet. Kept free of any provider SDK so ViewModels
/// depend only on this and the typed [AppBoxKitPaymentResult].
abstract interface class AppBoxKitPaymentsService {
  /// Whether the device + configuration can pay with [method] right now.
  Future<bool> canPay(AppBoxKitPaymentMethod method);

  /// Presents the payment sheet for [config] with [items] and resolves to a
  /// typed result. Never throws for user dismissal or a wallet error — the
  /// outcome is always a [AppBoxKitPaymentResult] branch.
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  });
}

/// Registry-backed [AppBoxKitPaymentsService]. Routes each call to the first
/// provider that supports the requested wallet.
class DefaultAppBoxKitPaymentsService implements AppBoxKitPaymentsService {
  final AppBoxKitPaymentsProviderRegistry registry;

  DefaultAppBoxKitPaymentsService(this.registry);

  /// Convenience for the common case: a single native Apple/Google Pay
  /// provider. Pass the profiles you want advertised.
  factory DefaultAppBoxKitPaymentsService.native({
    AppBoxKitApplePayConfig? applePay,
    AppBoxKitGooglePayConfig? googlePay,
  }) =>
      DefaultAppBoxKitPaymentsService(
        AppBoxKitPaymentsProviderRegistry([
          AppBoxKitPayPaymentsProvider(
            applePayConfig: applePay,
            googlePayConfig: googlePay,
          ),
        ]),
      );

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async {
    final provider = registry.providerFor(method);
    if (provider == null) return false;
    return provider.canPay(method);
  }

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    final provider = registry.providerFor(config.method);
    if (provider == null) {
      return AppBoxKitPaymentError('No payment provider registered for ${config.method}');
    }
    return provider.requestPayment(config: config, items: items);
  }
}
