import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pay/pay.dart' as pay;

import '../models/kit_payment_config.dart';
import '../models/kit_payment_item.dart';
import '../models/kit_payment_method.dart';
import '../models/payment_result.dart';

/// The native wallet button, picked per platform. Renders `pay`'s
/// `ApplePayButton` on iOS and `GooglePayButton` on Android from whichever
/// config is supplied, and normalises the plugin's split success/error
/// callbacks into a single [onResult] taking a typed [PaymentResult].
///
/// Supply the config for each platform you target; the button for the current
/// platform is shown (an empty box when none is configured for it). For full
/// control over styling, use `pay`'s buttons directly — they are re-exported
/// from `package:appbox_kit_payments/appbox_kit_payments.dart`.
class KitPayButton extends StatelessWidget {
  /// Apple Pay profile — used when running on iOS.
  final ApplePayConfig? applePay;

  /// Google Pay profile — used when running on Android.
  final GooglePayConfig? googlePay;

  /// Line items shown in the sheet.
  final List<KitPaymentItem> items;

  /// Called with a [PaymentSuccess] on a minted token, or a [PaymentError] /
  /// [PaymentCancelled] when the plugin reports a failure. (Apple/Google Pay
  /// do not distinguish decline client-side; those arrive as [PaymentError].)
  final ValueChanged<PaymentResult> onResult;

  /// Widget shown while the button initialises. Defaults to an empty box.
  final Widget? loadingIndicator;

  /// Apple Pay button style (iOS only).
  final pay.ApplePayButtonStyle applePayStyle;

  /// Apple Pay button type (iOS only).
  final pay.ApplePayButtonType applePayType;

  /// Google Pay button type (Android only).
  final pay.GooglePayButtonType googlePayType;

  /// Outer margin applied to whichever button renders.
  final EdgeInsets margin;

  const KitPayButton({
    super.key,
    required this.items,
    required this.onResult,
    this.applePay,
    this.googlePay,
    this.loadingIndicator,
    this.applePayStyle = pay.ApplePayButtonStyle.black,
    this.applePayType = pay.ApplePayButtonType.buy,
    this.googlePayType = pay.GooglePayButtonType.buy,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final loader = loadingIndicator ?? const SizedBox.shrink();
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        final config = applePay;
        if (config == null) return const SizedBox.shrink();
        return _resolve(
          config,
          loader,
          (configuration) => pay.ApplePayButton(
            paymentConfiguration: configuration,
            paymentItems: _payItems,
            style: applePayStyle,
            type: applePayType,
            margin: margin,
            loadingIndicator: loader,
            onPaymentResult: _handleSuccess(KitPaymentMethod.applePay),
            onError: _handleError,
          ),
        );
      case TargetPlatform.android:
        final config = googlePay;
        if (config == null) return const SizedBox.shrink();
        return _resolve(
          config,
          loader,
          (configuration) => pay.GooglePayButton(
            paymentConfiguration: configuration,
            paymentItems: _payItems,
            type: googlePayType,
            margin: margin,
            loadingIndicator: loader,
            onPaymentResult: _handleSuccess(KitPaymentMethod.googlePay),
            onError: _handleError,
          ),
        );
      default:
        // pay only supports Android + iOS.
        return const SizedBox.shrink();
    }
  }

  List<pay.PaymentItem> get _payItems =>
      items.map((item) => item.toPayItem()).toList();

  /// Builds the button once its `PaymentConfiguration` is ready — synchronously
  /// for inline JSON, via a [FutureBuilder] for asset-backed configs.
  Widget _resolve(
    KitPaymentConfig config,
    Widget loader,
    Widget Function(pay.PaymentConfiguration) builder,
  ) {
    final json = config.json;
    if (json != null) {
      return builder(pay.PaymentConfiguration.fromJsonString(json));
    }
    return FutureBuilder<pay.PaymentConfiguration>(
      future: pay.PaymentConfiguration.fromAsset(config.asset!),
      builder: (context, snapshot) =>
          snapshot.hasData ? builder(snapshot.data!) : loader,
    );
  }

  void Function(Map<String, dynamic>) _handleSuccess(KitPaymentMethod method) =>
      (result) => onResult(
            PaymentSuccess(
              token: _tokenFrom(result),
              method: method,
              raw: result,
            ),
          );

  void _handleError(Object? error) =>
      onResult(PaymentError(error?.toString() ?? 'Payment failed', cause: error));

  static String _tokenFrom(Map<String, dynamic> result) {
    final direct = result['token'];
    if (direct is String && direct.isNotEmpty) return direct;
    final paymentMethodData = result['paymentMethodData'];
    if (paymentMethodData is Map) {
      final tokenization = paymentMethodData['tokenizationData'];
      if (tokenization is Map && tokenization['token'] is String) {
        return tokenization['token'] as String;
      }
    }
    return result.toString();
  }
}
