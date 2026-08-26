import 'package:flutter/foundation.dart';

/// The category of a compliance document.
///
/// [custom] covers anything outside the well-known legal surfaces.
enum ArxaKitComplianceDocumentKind {
  termsOfService,
  privacyPolicy,
  eula,
  dataProcessingAgreement,
  cookiePolicy,
  communityGuidelines,
  custom,
}

/// Where a document's text lives: a remote [ArxaKitComplianceRemoteSource] the app
/// fetches or opens, or an inline [ArxaKitComplianceInlineSource] bundled with the
/// build. Modelled as a sealed type so a document can never be in the illegal
/// "both / neither" state a nullable uri+body pair would allow.
@immutable
sealed class ArxaKitComplianceSource {
  const ArxaKitComplianceSource();

  /// A document hosted at [uri].
  const factory ArxaKitComplianceSource.remote(Uri uri) = ArxaKitComplianceRemoteSource;

  /// A document whose full text [body] ships with the app.
  const factory ArxaKitComplianceSource.inline(String body) =
      ArxaKitComplianceInlineSource;
}

/// A document hosted at [uri] (opened in a browser or fetched by the app).
@immutable
final class ArxaKitComplianceRemoteSource extends ArxaKitComplianceSource {
  const ArxaKitComplianceRemoteSource(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitComplianceRemoteSource && uri == other.uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'ArxaKitComplianceRemoteSource($uri)';
}

/// A document whose full text [body] is bundled with the app.
@immutable
final class ArxaKitComplianceInlineSource extends ArxaKitComplianceSource {
  const ArxaKitComplianceInlineSource(this.body);

  final String body;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitComplianceInlineSource && body == other.body;

  @override
  int get hashCode => body.hashCode;

  @override
  String toString() => 'ArxaKitComplianceInlineSource(${body.length} chars)';
}

/// A versioned legal/compliance document the app may need the user to accept.
///
/// [version] is an opaque tag compared for **exact-string** equality — any
/// mismatch marks a prior acceptance outdated. No semver parsing is performed,
/// so "2026-07-01" and "1.2.0" are equally valid schemes.
@immutable
final class ArxaKitComplianceDocument {
  const ArxaKitComplianceDocument({
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

  final ArxaKitComplianceDocumentKind kind;

  /// Opaque version tag, compared exact-string (see class doc).
  final String version;

  final String title;

  final ArxaKitComplianceSource source;

  /// When this version takes effect. Informational; never used for comparison.
  final DateTime effectiveDate;

  /// Whether the user must explicitly accept this document before proceeding.
  ///
  /// When `false`, the document is [ArxaKitConsentNotRequired] regardless of
  /// records — though implicit consent can still be recorded against it.
  final bool requiresExplicitAcceptance;

  /// BCP-47 locale tag this document is written for (e.g. `en-US`), or null for
  /// a locale-agnostic document.
  final String? locale;

  @override
  bool operator ==(Object other) =>
      other is ArxaKitComplianceDocument &&
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
      'ArxaKitComplianceDocument(id: $id, kind: $kind, version: $version)';
}
