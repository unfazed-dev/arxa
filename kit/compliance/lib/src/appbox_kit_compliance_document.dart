import 'package:flutter/foundation.dart';

/// The category of a compliance document.
///
/// [custom] covers anything outside the well-known legal surfaces.
enum AppBoxKitComplianceDocumentKind {
  termsOfService,
  privacyPolicy,
  eula,
  dataProcessingAgreement,
  cookiePolicy,
  communityGuidelines,
  custom,
}

/// Where a document's text lives: a remote [AppBoxKitComplianceRemoteSource] the app
/// fetches or opens, or an inline [AppBoxKitComplianceInlineSource] bundled with the
/// build. Modelled as a sealed type so a document can never be in the illegal
/// "both / neither" state a nullable uri+body pair would allow.
@immutable
sealed class AppBoxKitComplianceSource {
  const AppBoxKitComplianceSource();

  /// A document hosted at [uri].
  const factory AppBoxKitComplianceSource.remote(Uri uri) = AppBoxKitComplianceRemoteSource;

  /// A document whose full text [body] ships with the app.
  const factory AppBoxKitComplianceSource.inline(String body) =
      AppBoxKitComplianceInlineSource;
}

/// A document hosted at [uri] (opened in a browser or fetched by the app).
@immutable
final class AppBoxKitComplianceRemoteSource extends AppBoxKitComplianceSource {
  const AppBoxKitComplianceRemoteSource(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitComplianceRemoteSource && uri == other.uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'AppBoxKitComplianceRemoteSource($uri)';
}

/// A document whose full text [body] is bundled with the app.
@immutable
final class AppBoxKitComplianceInlineSource extends AppBoxKitComplianceSource {
  const AppBoxKitComplianceInlineSource(this.body);

  final String body;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitComplianceInlineSource && body == other.body;

  @override
  int get hashCode => body.hashCode;

  @override
  String toString() => 'AppBoxKitComplianceInlineSource(${body.length} chars)';
}

/// A versioned legal/compliance document the app may need the user to accept.
///
/// [version] is an opaque tag compared for **exact-string** equality — any
/// mismatch marks a prior acceptance outdated. No semver parsing is performed,
/// so "2026-07-01" and "1.2.0" are equally valid schemes.
@immutable
final class AppBoxKitComplianceDocument {
  const AppBoxKitComplianceDocument({
    required this.id,
    required this.kind,
    required this.version,
    required this.title,
    required this.source,
    required this.effectiveDate,
    this.requiresExplicitAcceptance = true,
    this.locale,
  });

  /// Stable identifier for the document across versions (e.g. `privacy-policy`).
  final String id;

  final AppBoxKitComplianceDocumentKind kind;

  /// Opaque version tag, compared exact-string (see class doc).
  final String version;

  final String title;

  final AppBoxKitComplianceSource source;

  /// When this version takes effect. Informational; never used for comparison.
  final DateTime effectiveDate;

  /// Whether the user must explicitly accept this document before proceeding.
  ///
  /// When `false`, the document is [AppBoxKitConsentNotRequired] regardless of
  /// records — though implicit consent can still be recorded against it.
  final bool requiresExplicitAcceptance;

  /// BCP-47 locale tag this document is written for (e.g. `en-US`), or null for
  /// a locale-agnostic document.
  final String? locale;

  @override
  bool operator ==(Object other) =>
      other is AppBoxKitComplianceDocument &&
      id == other.id &&
      kind == other.kind &&
      version == other.version &&
      title == other.title &&
      source == other.source &&
      effectiveDate == other.effectiveDate &&
      requiresExplicitAcceptance == other.requiresExplicitAcceptance &&
      locale == other.locale;

  @override
  int get hashCode => Object.hash(id, kind, version, title, source,
      effectiveDate, requiresExplicitAcceptance, locale);

  @override
  String toString() =>
      'AppBoxKitComplianceDocument(id: $id, kind: $kind, version: $version)';
}
