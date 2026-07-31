import '../../models/kit_payment_config.dart';
import '../../models/kit_payment_item.dart';
import '../../models/kit_payment_method.dart';
import '../../models/payment_result.dart';
import '../kit_payments_provider.dart';

/// STUB — not implemented. Slots into [KitPaymentsProviderRegistry] alongside
/// [PayPaymentsProvider] so a Stripe backend can be added without changing any
/// call site.
///
/// TODO(phase-later): implement with `flutter_stripe`. Stripe can front the
/// same Apple Pay / Google Pay sheets (its `PlatformPay` API) *and* raw card
/// entry via `PaymentSheet`. When wiring:
///   1. Add `flutter_stripe` to pubspec and initialise the publishable key.
///   2. In [canPay], delegate to `Stripe.instance.isPlatformPaySupported`.
///   3. In [requestPayment], run `PlatformPay.confirmPlatformPayPaymentIntent`
///      (or `PaymentSheet`) and map the outcome onto [PaymentResult] — surface
///      a card decline as [PaymentDeclined], not [PaymentError].
///   4. Broaden [KitPaymentMethod] if card-not-present rails are added.
class StripePaymentsProvider implements KitPaymentsProvider {
  const StripePaymentsProvider();

  @override
  String get id => 'stripe';

  @override
  Set<KitPaymentMethod> get supportedMethods =>
      throw UnimplementedError('StripePaymentsProvider is a stub (phase-later)');

  @override
  Future<bool> canPay(KitPaymentMethod method) =>
      throw UnimplementedError('StripePaymentsProvider.canPay (phase-later)');

  @override
  Future<PaymentResult> requestPayment({
    required KitPaymentConfig config,
    required List<KitPaymentItem> items,
  }) =>
      throw UnimplementedError(
          'StripePaymentsProvider.requestPayment (phase-later)');
}
