import 'dart:convert';

import 'package:pay/pay.dart' as pay;

import '../../models/appbox_kit_payment_config.dart';
import '../../models/appbox_kit_payment_item.dart';
import '../../models/appbox_kit_payment_method.dart';
import '../../models/appbox_kit_payment_result.dart';
import '../appbox_kit_payments_provider.dart';

/// The native-first provider: Apple Pay + Google Pay through Google's `pay`
/// plugin (PassKit / Google Pay API). This is the only fully-implemented
/// provider; Stripe and PayPal are stubs of the same [AppBoxKitPaymentsProvider]
/// shape.
///
/// Constructed with the profiles it should advertise: `canPay(method)` (which
/// takes no config) uses the profile registered here, while `requestPayment`
/// uses the config passed to the call. Provide at least one config — a
/// provider with none supports no methods.
class AppBoxKitPayPaymentsProvider implements AppBoxKitPaymentsProvider {
  final AppBoxKitApplePayConfig? applePayConfig;
  final AppBoxKitGooglePayConfig? googlePayConfig;

  const AppBoxKitPayPaymentsProvider({this.applePayConfig, this.googlePayConfig});

  @override
  String get id => 'native_pay';

  @override
  Set<AppBoxKitPaymentMethod> get supportedMethods => {
        if (applePayConfig != null) AppBoxKitPaymentMethod.applePay,
        if (googlePayConfig != null) AppBoxKitPaymentMethod.googlePay,
      };

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async {
    final config = _configFor(method);
    if (config == null) return false;
    try {
      final client = await _clientForConfig(config);
      return await client.userCanPay(_toPayProvider(method));
    } catch (_) {
      // userCanPay throws on unsupported platforms / malformed config; a
      // thrown check is a "no" as far as the caller is concerned.
      return false;
    }
  }

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    final method = config.method;
    try {
      final client = await _clientForConfig(config);
      final result = await client.showPaymentSelector(
        _toPayProvider(method),
        items.map((item) => item.toPayItem()).toList(),
      );
      return AppBoxKitPaymentSuccess(
        token: _extractToken(result, method),
        method: method,
        raw: result,
      );
    } catch (error) {
      // The plugin throws on user dismissal; there is no dedicated cancel
      // type, so we match the message. Everything else is a real error.
      if (_isCancellation(error)) return const AppBoxKitPaymentCancelled();
      return AppBoxKitPaymentError(error.toString(), cause: error);
    }
  }

  AppBoxKitPaymentConfig? _configFor(AppBoxKitPaymentMethod method) => switch (method) {
        AppBoxKitPaymentMethod.applePay => applePayConfig,
        AppBoxKitPaymentMethod.googlePay => googlePayConfig,
        // PayPal is a web rail, not a native wallet — never this provider.
        AppBoxKitPaymentMethod.payPal => null,
      };

  Future<pay.Pay> _clientForConfig(AppBoxKitPaymentConfig config) async {
    final configuration = config.json != null
        ? pay.PaymentConfiguration.fromJsonString(config.json!)
        : await pay.PaymentConfiguration.fromAsset(config.asset!);
    return pay.Pay({_toPayProvider(config.method): configuration});
  }

  static pay.PayProvider _toPayProvider(AppBoxKitPaymentMethod method) =>
      switch (method) {
        AppBoxKitPaymentMethod.applePay => pay.PayProvider.apple_pay,
        AppBoxKitPaymentMethod.googlePay => pay.PayProvider.google_pay,
        // Unreachable: _configFor returns null for payPal before this runs.
        AppBoxKitPaymentMethod.payPal =>
          throw ArgumentError.value(method, 'method', 'not a native wallet'),
      };

  /// Pulls the processor token out of the plugin's result map. Apple Pay puts
  /// it under `token`; Google Pay nests it under
  /// `paymentMethodData.tokenizationData.token`. Falls back to the encoded
  /// result so no data is dropped when a wallet changes its shape.
  static String _extractToken(Map<String, dynamic> result, AppBoxKitPaymentMethod _) {
    final direct = result['token'];
    if (direct is String && direct.isNotEmpty) return direct;

    final paymentMethodData = result['paymentMethodData'];
    if (paymentMethodData is Map) {
      final tokenization = paymentMethodData['tokenizationData'];
      if (tokenization is Map && tokenization['token'] is String) {
        return tokenization['token'] as String;
      }
    }
    return jsonEncode(result);
  }

  static bool _isCancellation(Object error) =>
      error.toString().toLowerCase().contains('cancel');
}
