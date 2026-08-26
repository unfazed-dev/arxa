import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../../models/arxa_kit_payment_config.dart';
import '../../models/arxa_kit_payment_item.dart';
import '../../models/arxa_kit_payment_method.dart';
import '../../models/arxa_kit_payment_result.dart';
import '../arxa_kit_payments_provider.dart';

/// What the server hands back after creating a PayPal order (Orders v2
/// `POST /v2/checkout/orders`): the order id plus the payer-approval link
/// (`rel: "payer-action"` / legacy `"approve"`).
class ArxaKitPayPalOrderApproval {
  /// PayPal order id (e.g. `8XS12345AB678901C`).
  final String orderId;

  /// Absolute URL the buyer is sent to in order to approve the payment.
  final Uri approvalUrl;

  const ArxaKitPayPalOrderApproval({required this.orderId, required this.approvalUrl});
}

/// What the server reports after capturing an approved order
/// (`POST /v2/checkout/orders/{id}/capture`).
class ArxaKitPayPalCaptureResult {
  /// Orders v2 capture/order status — `COMPLETED`, `DECLINED`, `FAILED`, …
  /// Compared case-insensitively by the provider.
  final String status;

  /// Capture id (`purchase_units[].payments.captures[].id`) when completed.
  final String? captureId;

  /// Processor decline reason when the capture failed.
  final String? declineReason;

  const ArxaKitPayPalCaptureResult({
    required this.status,
    this.captureId,
    this.declineReason,
  });
}

/// Server-side seam for PayPal Orders v2. There is no healthy first-party
/// PayPal Flutter SDK in 2026 (the native checkout SDK is deprecated), so
/// order create/capture — which need the client secret — live on your
/// backend; implement this over your API client.
abstract interface class ArxaKitPayPalBackend {
  /// Creates an order for [amount] (decimal string, e.g. `'49.99'`) in
  /// [currencyCode] (ISO 4217) and returns its approval link. [returnUrl] /
  /// [cancelUrl] are the deep links PayPal redirects to after approval /
  /// back-out; build them from the app's [ArxaKitPayPalPaymentsProvider]
  /// callback scheme.
  Future<ArxaKitPayPalOrderApproval> createOrder({
    required String amount,
    required String currencyCode,
    String? returnUrl,
    String? cancelUrl,
  });

  /// Captures the approved order [orderId].
  Future<ArxaKitPayPalCaptureResult> captureOrder(String orderId);
}

/// The buyer closed the web session without approving. Maps to
/// [ArxaKitPaymentCancelled].
class ArxaKitWebAuthCancelled implements Exception {
  const ArxaKitWebAuthCancelled();

  @override
  String toString() => 'ArxaKitWebAuthCancelled()';
}

/// In-app browser seam (ASWebAuthenticationSession / Chrome Auth Tab). The
/// real implementation is [ArxaKitFlutterWebAuth2Authenticator]; tests substitute a
/// mock so no platform channel is ever touched.
abstract interface class ArxaKitWebAuthenticator {
  /// Opens [url] and completes with the callback URL the flow redirected to.
  /// Throws [ArxaKitWebAuthCancelled] when the user dismisses the session.
  Future<Uri> authenticate({required Uri url, required String callbackUrlScheme});
}

/// [ArxaKitWebAuthenticator] over `flutter_web_auth_2`.
class ArxaKitFlutterWebAuth2Authenticator implements ArxaKitWebAuthenticator {
  const ArxaKitFlutterWebAuth2Authenticator();

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
        throw const ArxaKitWebAuthCancelled();
      }
      rethrow;
    }
  }
}

/// PayPal backend over Orders v2 web checkout: the backend Port creates the
/// order, the buyer approves it in an in-app browser via [ArxaKitWebAuthenticator]
/// (deep-link return), and the backend Port captures it.
///
/// PayPal is a redirect rail, not a native wallet sheet, so this provider
/// reports only [ArxaKitPaymentMethod.payPal] — never Apple/Google Pay.
/// [canPay] is static: there is no device gate.
///
/// Flow (mirrors the Tier-1 spec in `arxa/lib/tier1.dart`): create order →
/// approve (the "token" step) → capture. Approved + captured →
/// [ArxaKitPaymentSuccess] with the capture id as the token; buyer back-out →
/// [ArxaKitPaymentCancelled]; failed capture → [ArxaKitPaymentDeclined].
class ArxaKitPayPalPaymentsProvider implements ArxaKitPaymentsProvider {
  /// Server-side Orders v2 seam.
  final ArxaKitPayPalBackend backend;

  /// The deep-link scheme the host app registered for the approval return
  /// (e.g. `com.example.app`). PayPal must redirect to
  /// `<callbackUrlScheme>://paypalpay` — pass the matching return/cancel URLs
  /// to your backend.
  final String callbackUrlScheme;

  final ArxaKitWebAuthenticator _authenticator;

  ArxaKitPayPalPaymentsProvider({
    required this.backend,
    required this.callbackUrlScheme,
    ArxaKitWebAuthenticator? authenticator,
  }) : _authenticator = authenticator ?? const ArxaKitFlutterWebAuth2Authenticator();

  @override
  String get id => 'paypal';

  @override
  Set<ArxaKitPaymentMethod> get supportedMethods => const {ArxaKitPaymentMethod.payPal};

  @override
  Future<bool> canPay(ArxaKitPaymentMethod method) async =>
      supportedMethods.contains(method);

  @override
  Future<ArxaKitPaymentResult> requestPayment({
    required ArxaKitPaymentConfig config,
    required List<ArxaKitPaymentItem> items,
  }) async {
    if (config.method != ArxaKitPaymentMethod.payPal || config is! ArxaKitPayPalConfig) {
      return ArxaKitPaymentError(
          'ArxaKitPayPalPaymentsProvider requires a ArxaKitPayPalConfig, got ${config.runtimeType}');
    }
    final amount = _total(items);
    if (amount == null) {
      return const ArxaKitPaymentError(
          'ArxaKitPayPalPaymentsProvider requires final-priced items');
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
      } on ArxaKitWebAuthCancelled {
        return const ArxaKitPaymentCancelled();
      }
      // Any deep-link return that didn't cancel is treated as an approval —
      // the capture call is the source of truth for the money.
      final capture = await backend.captureOrder(order.orderId);
      final status = capture.status.toUpperCase();
      if (status == 'COMPLETED') {
        return ArxaKitPaymentSuccess(
          token: capture.captureId ?? order.orderId,
          method: ArxaKitPaymentMethod.payPal,
          raw: {
            'provider': 'paypal',
            'orderId': order.orderId,
            'captureId': capture.captureId,
          },
        );
      }
      if (status.contains('DECLIN') || status.contains('FAIL')) {
        return ArxaKitPaymentDeclined(reason: capture.declineReason);
      }
      return ArxaKitPaymentError('PayPal capture ended in status ${capture.status}');
    } catch (error) {
      return ArxaKitPaymentError(error.toString(), cause: error);
    }
  }

  /// Sums final-priced items to a decimal string. Returns null when any item
  /// is pending or unparseable — charging a guessed total is worse than
  /// failing.
  static String? _total(List<ArxaKitPaymentItem> items) {
    var total = 0.0;
    for (final item in items) {
      if (item.status != ArxaKitPaymentItemStatus.finalPrice) return null;
      final amount = double.tryParse(item.amount);
      if (amount == null) return null;
      total += amount;
    }
    return total.toStringAsFixed(2);
  }
}
