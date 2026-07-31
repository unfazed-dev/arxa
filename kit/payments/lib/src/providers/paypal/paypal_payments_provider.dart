import '../../models/kit_payment_config.dart';
import '../../models/kit_payment_item.dart';
import '../../models/kit_payment_method.dart';
import '../../models/payment_result.dart';
import '../kit_payments_provider.dart';

/// STUB — not implemented. Slots into [KitPaymentsProviderRegistry] alongside
/// [PayPaymentsProvider] so a PayPal backend can be added without changing any
/// call site.
///
/// TODO(phase-later): implement over PayPal's Braintree / Orders v2 flow.
/// PayPal is a redirect/web-checkout rail, not a native wallet sheet, so:
///   1. Add the PayPal/Braintree SDK and server-side order creation seam.
///   2. In [canPay], report support statically (PayPal has no device gate).
///   3. In [requestPayment], launch the approval flow and map the return:
///      approved → [PaymentSuccess] (token = the order/nonce), buyer back-out
///      → [PaymentCancelled], funding failure → [PaymentDeclined].
///   4. Add a `payPal` member to [KitPaymentMethod] — this provider will not
///      report [KitPaymentMethod.applePay]/`.googlePay`.
class PayPalPaymentsProvider implements KitPaymentsProvider {
  const PayPalPaymentsProvider();

  @override
  String get id => 'paypal';

  @override
  Set<KitPaymentMethod> get supportedMethods =>
      throw UnimplementedError('PayPalPaymentsProvider is a stub (phase-later)');

  @override
  Future<bool> canPay(KitPaymentMethod method) =>
      throw UnimplementedError('PayPalPaymentsProvider.canPay (phase-later)');

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) =>
      throw UnimplementedError(
          'PayPalPaymentsProvider.requestPayment (phase-later)');
}
