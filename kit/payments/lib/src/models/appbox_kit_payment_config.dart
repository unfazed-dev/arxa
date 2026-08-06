import 'appbox_kit_payment_method.dart';

/// A payment-provider profile. Per the `pay` plugin convention a config is a
/// JSON document (the `"provider"` + `"data"` shape) supplied either inline or
/// from an asset — see the sample profiles under `example/`. Sealed so
/// [AppBoxKitPaymentsService] can select a provider by [method] without inspecting
/// the JSON, and so `switch` over configs stays exhaustive.
sealed class AppBoxKitPaymentConfig {
  const AppBoxKitPaymentConfig();

  /// Which wallet this profile drives.
  AppBoxKitPaymentMethod get method;

  /// Inline JSON document, or null when [asset] is used instead.
  String? get json;

  /// Asset path to a JSON document, or null when [json] is used instead.
  String? get asset;
}

/// An Apple Pay profile — a JSON document shaped after `PKPaymentRequest`
/// (merchantIdentifier, supportedNetworks, countryCode, currencyCode, …).
final class AppBoxKitApplePayConfig extends AppBoxKitPaymentConfig {
  @override
  final String? json;
  @override
  final String? asset;

  /// Inline profile JSON (build-time or fetched at runtime).
  const AppBoxKitApplePayConfig.fromJson(String this.json) : asset = null;

  /// Profile JSON bundled as a Flutter asset (declared in the host's pubspec).
  const AppBoxKitApplePayConfig.fromAsset(String this.asset) : json = null;

  @override
  AppBoxKitPaymentMethod get method => AppBoxKitPaymentMethod.applePay;
}

/// A Google Pay profile — a JSON document shaped after the Google Pay API
/// request object (environment, allowedPaymentMethods, merchantInfo, …).
final class AppBoxKitGooglePayConfig extends AppBoxKitPaymentConfig {
  @override
  final String? json;
  @override
  final String? asset;

  /// Inline profile JSON (build-time or fetched at runtime).
  const AppBoxKitGooglePayConfig.fromJson(String this.json) : asset = null;

  /// Profile JSON bundled as a Flutter asset (declared in the host's pubspec).
  const AppBoxKitGooglePayConfig.fromAsset(String this.asset) : json = null;

  @override
  AppBoxKitPaymentMethod get method => AppBoxKitPaymentMethod.googlePay;
}

/// A PayPal profile. PayPal has no `pay`-plugin-style JSON document (order
/// creation happens server-side via Orders v2), so the config carries only
/// what a single payment needs: the ISO 4217 [currencyCode] the order is
/// created in. [json] / [asset] are always null — they exist only because the
/// sealed base declares them.
final class AppBoxKitPayPalConfig extends AppBoxKitPaymentConfig {
  /// ISO 4217 currency code for the order (e.g. `'USD'`, `'EUR'`).
  final String currencyCode;

  const AppBoxKitPayPalConfig({this.currencyCode = 'USD'});

  @override
  String? get json => null;

  @override
  String? get asset => null;

  @override
  AppBoxKitPaymentMethod get method => AppBoxKitPaymentMethod.payPal;
}
