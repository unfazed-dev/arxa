import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../models/appbox_kit_payment_config.dart';
import '../../models/appbox_kit_payment_item.dart';
import '../../models/appbox_kit_payment_method.dart';
import '../../models/appbox_kit_payment_result.dart';
import '../appbox_kit_payments_provider.dart';

/// What the server hands back after creating a PayPal order (Orders v2
/// `POST /v2/checkout/orders`): the order id plus the payer-approval link
/// (`rel: "payer-action"` / legacy `"approve"`).
class AppBoxKitPayPalOrderApproval {
  /// PayPal order id (e.g. `8XS12345AB678901C`).
  final String orderId;

  /// Absolute URL the buyer is sent to in order to approve the payment.
  final Uri approvalUrl;

  const AppBoxKitPayPalOrderApproval({required this.orderId, required this.approvalUrl});
}

/// What the server reports after capturing an approved order
/// (`POST /v2/checkout/orders/{id}/capture`).
class AppBoxKitPayPalCaptureResult {
  /// Orders v2 capture/order status — `COMPLETED`, `DECLINED`, `FAILED`, …
  /// Compared case-insensitively by the provider.
  final String status;

  /// Capture id (`purchase_units[].payments.captures[].id`) when completed.
  final String? captureId;

  /// Processor decline reason when the capture failed.
  final String? declineReason;

  const AppBoxKitPayPalCaptureResult({
    required this.status,
    this.captureId,
    this.declineReason,
  });
}

/// Server-side seam for PayPal Orders v2. There is no healthy first-party
/// PayPal Flutter SDK in 2026 (the native checkout SDK is deprecated), so
/// order create/capture — which need the client secret — live on your
/// backend; implement this over your API client.
abstract interface class AppBoxKitPayPalBackend {
  /// Creates an order for [amount] (decimal string, e.g. `'49.99'`) in
  /// [currencyCode] (ISO 4217) and returns its approval link. [returnUrl] /
  /// [cancelUrl] are the deep links PayPal redirects to after approval /
  /// back-out; build them from the app's [AppBoxKitPayPalPaymentsProvider]
  /// callback scheme.
  Future<AppBoxKitPayPalOrderApproval> createOrder({
    required String amount,
    required String currencyCode,
    String? returnUrl,
    String? cancelUrl,
  });

  /// Captures the approved order [orderId].
  Future<AppBoxKitPayPalCaptureResult> captureOrder(String orderId);
}

/// The buyer closed the web session without approving. Maps to
/// [AppBoxKitPaymentCancelled].
class AppBoxKitWebAuthCancelled implements Exception {
  const AppBoxKitWebAuthCancelled();

  @override
  String toString() => 'AppBoxKitWebAuthCancelled()';
}

/// In-app browser seam (ASWebAuthenticationSession / Chrome Auth Tab). The
/// real implementation is [AppBoxKitFlutterWebAuth2Authenticator]; tests substitute a
/// mock so no platform channel is ever touched.
abstract interface class AppBoxKitWebAuthenticator {
  /// Opens [url] and completes with the callback URL the flow redirected to.
  /// Throws [AppBoxKitWebAuthCancelled] when the user dismisses the session.
  Future<Uri> authenticate({required Uri url, required String callbackUrlScheme});
}

/// [AppBoxKitWebAuthenticator] over `flutter_web_auth_2`.
class AppBoxKitFlutterWebAuth2Authenticator implements AppBoxKitWebAuthenticator {
  const AppBoxKitFlutterWebAuth2Authenticator();

  @override
  Future<Uri> authenticate({
    required Uri url,
    required String callbackUrlScheme,
  }) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: callbackUrlScheme,
      );
      return Uri.parse(result);
    } on PlatformException catch (error) {
      // Both platforms report dismissal as PlatformException(code: CANCELED).
      if (error.code.toUpperCase().contains('CANCEL')) {
        throw const AppBoxKitWebAuthCancelled();
      }
      rethrow;
    }
  }
}

/// PayPal backend over Orders v2 web checkout: the backend Port creates the
/// order, the buyer approves it in an in-app browser via [AppBoxKitWebAuthenticator]
/// (deep-link return), and the backend Port captures it.
///
/// PayPal is a redirect rail, not a native wallet sheet, so this provider
/// reports only [AppBoxKitPaymentMethod.payPal] — never Apple/Google Pay.
/// [canPay] is static: there is no device gate.
///
/// Flow (mirrors the Tier-1 spec in `appboxd/lib/tier1.dart`): create order →
/// approve (the "token" step) → capture. Approved + captured →
/// [AppBoxKitPaymentSuccess] with the capture id as the token; buyer back-out →
/// [AppBoxKitPaymentCancelled]; failed capture → [AppBoxKitPaymentDeclined].
class AppBoxKitPayPalPaymentsProvider implements AppBoxKitPaymentsProvider {
  /// Server-side Orders v2 seam.
  final AppBoxKitPayPalBackend backend;

  /// The deep-link scheme the host app registered for the approval return
  /// (e.g. `com.example.app`). PayPal must redirect to
  /// `<callbackUrlScheme>://paypalpay` — pass the matching return/cancel URLs
  /// to your backend.
  final String callbackUrlScheme;

  final AppBoxKitWebAuthenticator _authenticator;

  AppBoxKitPayPalPaymentsProvider({
    required this.backend,
    required this.callbackUrlScheme,
    AppBoxKitWebAuthenticator? authenticator,
  }) : _authenticator = authenticator ?? const AppBoxKitFlutterWebAuth2Authenticator();

  @override
  String get id => 'paypal';

  @override
  Set<AppBoxKitPaymentMethod> get supportedMethods => const {AppBoxKitPaymentMethod.payPal};

  @override
  Future<bool> canPay(AppBoxKitPaymentMethod method) async =>
      supportedMethods.contains(method);

  @override
  Future<AppBoxKitPaymentResult> requestPayment({
    required AppBoxKitPaymentConfig config,
    required List<AppBoxKitPaymentItem> items,
  }) async {
    if (config.method != AppBoxKitPaymentMethod.payPal || config is! AppBoxKitPayPalConfig) {
      return AppBoxKitPaymentError(
          'AppBoxKitPayPalPaymentsProvider requires a AppBoxKitPayPalConfig, got ${config.runtimeType}');
    }
    final amount = _total(items);
    if (amount == null) {
      return const AppBoxKitPaymentError(
          'AppBoxKitPayPalPaymentsProvider requires final-priced items');
    }
    try {
      final order = await backend.createOrder(
        amount: amount,
        currencyCode: config.currencyCode,
        returnUrl: '$callbackUrlScheme://paypalpay',
        cancelUrl: '$callbackUrlScheme://paypalcancel',
      );
      try {
        await _authenticator.authenticate(
          url: order.approvalUrl,
          callbackUrlScheme: callbackUrlScheme,
        );
      } on AppBoxKitWebAuthCancelled {
        return const AppBoxKitPaymentCancelled();
      }
      // Any deep-link return that didn't cancel is treated as an approval —
      // the capture call is the source of truth for the money.
      final capture = await backend.captureOrder(order.orderId);
      final status = capture.status.toUpperCase();
      if (status == 'COMPLETED') {
        return AppBoxKitPaymentSuccess(
          token: capture.captureId ?? order.orderId,
          method: AppBoxKitPaymentMethod.payPal,
          raw: {
            'provider': 'paypal',
            'orderId': order.orderId,
            'captureId': capture.captureId,
          },
        );
      }
      if (status.contains('DECLIN') || status.contains('FAIL')) {
        return AppBoxKitPaymentDeclined(reason: capture.declineReason);
      }
      return AppBoxKitPaymentError('PayPal capture ended in status ${capture.status}');
    } catch (error) {
      return AppBoxKitPaymentError(error.toString(), cause: error);
    }
  }

  /// Sums final-priced items to a decimal string. Returns null when any item
  /// is pending or unparseable — charging a guessed total is worse than
  /// failing.
  static String? _total(List<AppBoxKitPaymentItem> items) {
    var total = 0.0;
    for (final item in items) {
      if (item.status != AppBoxKitPaymentItemStatus.finalPrice) return null;
      final amount = double.tryParse(item.amount);
      if (amount == null) return null;
      total += amount;
    }
    return total.toStringAsFixed(2);
  }
}
