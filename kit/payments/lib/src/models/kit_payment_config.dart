import 'kit_payment_method.dart';

/// A payment-provider profile. Per the `pay` plugin convention a config is a
/// JSON document (the `"provider"` + `"data"` shape) supplied either inline or
/// from an asset — see the sample profiles under `example/`. Sealed so
/// [KitPaymentsService] can select a provider by [method] without inspecting
/// the JSON, and so `switch` over configs stays exhaustive.
sealed class KitPaymentConfig {
  const KitPaymentConfig();

  /// Which wallet this profile drives.
  KitPaymentMethod get method;

  /// Inline JSON document, or null when [asset] is used instead.
  String? get json;

  /// Asset path to a JSON document, or null when [json] is used instead.
  String? get asset;
}

/// An Apple Pay profile — a JSON document shaped after `PKPaymentRequest`
/// (merchantIdentifier, supportedNetworks, countryCode, currencyCode, …).
final class ApplePayConfig extends KitPaymentConfig {
  @override
  final String? json;
  @override
  final String? asset;

  /// Inline profile JSON (build-time or fetched at runtime).
  const ApplePayConfig.fromJson(String this.json) : asset = null;

  /// Profile JSON bundled as a Flutter asset (declared in the host's pubspec).
  const ApplePayConfig.fromAsset(String this.asset) : json = null;

  @override
  KitPaymentMethod get method => KitPaymentMethod.applePay;
}

/// A Google Pay profile — a JSON document shaped after the Google Pay API
/// request object (environment, allowedPaymentMethods, merchantInfo, …).
final class GooglePayConfig extends KitPaymentConfig {
  @override
  final String? json;
  @override
  final String? asset;

  /// Inline profile JSON (build-time or fetched at runtime).
  const GooglePayConfig.fromJson(String this.json) : asset = null;

  /// Profile JSON bundled as a Flutter asset (declared in the host's pubspec).
  const GooglePayConfig.fromAsset(String this.asset) : json = null;

  @override
  KitPaymentMethod get method => KitPaymentMethod.googlePay;
}

/// A PayPal profile. PayPal has no `pay`-plugin-style JSON document (order
/// creation happens server-side via Orders v2), so the config carries only
/// what a single payment needs: the ISO 4217 [currencyCode] the order is
/// created in. [json] / [asset] are always null — they exist only because the
/// sealed base declares them.
final class PayPalConfig extends KitPaymentConfig {
  /// ISO 4217 currency code for the order (e.g. `'USD'`, `'EUR'`).
  final String currencyCode;

  const PayPalConfig({this.currencyCode = 'USD'});

  @override
  String? get json => null;

  @override
  String? get asset => null;

  @override
  KitPaymentMethod get method => KitPaymentMethod.payPal;
}
