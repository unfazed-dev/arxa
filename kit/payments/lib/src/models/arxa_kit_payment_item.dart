import 'package:pay/pay.dart' as pay;

/// How a line item's amount should be treated by the wallet sheet. Mirrors
/// `pay`'s `PaymentItemStatus` but keeps the port pay-agnostic so the Stripe /
/// PayPal providers (which never touch the `pay` plugin) can build the same
/// item list.
enum ArxaKitPaymentItemStatus {
  /// A known, final amount (the common case for the grand total).
  finalPrice,

  /// An amount still being determined (e.g. shipping before an address is
  /// chosen). Rendered as pending by the wallet.
  pending,
}

/// A single line shown in the Apple Pay / Google Pay sheet. [amount] is a
/// decimal string in the config's currency (e.g. `'99.99'`) — never an int of
/// minor units — because that is what both wallets expect.
class ArxaKitPaymentItem {
  final String label;
  final String amount;
  final ArxaKitPaymentItemStatus status;

  const ArxaKitPaymentItem({
    required this.label,
    required this.amount,
    this.status = ArxaKitPaymentItemStatus.finalPrice,
  });

  /// Maps to the `pay` plugin's item type. Internal to the native provider and
  /// the widgets — callers of the port never need it.
  pay.PaymentItem toPayItem() => pay.PaymentItem(
        label: label,
        amount: amount,
        status: switch (status) {
          ArxaKitPaymentItemStatus.finalPrice => pay.PaymentItemStatus.final_price,
          ArxaKitPaymentItemStatus.pending => pay.PaymentItemStatus.pending,
        },
      );
}
