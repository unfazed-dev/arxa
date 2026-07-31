import 'package:flutter/foundation.dart';

/// The category of a compliance document.
///
/// [custom] covers anything outside the well-known legal surfaces.
enum KitComplianceDocumentKind {
  termsOfService,
  privacyPolicy,
  eula,
  dataProcessingAgreement,
  cookiePolicy,
  communityGuidelines,
  custom,
}

/// Where a document's text lives: a remote [KitComplianceRemoteSource] the app
/// fetches or opens, or an inline [KitComplianceInlineSource] bundled with the
/// build. Modelled as a sealed type so a document can never be in the illegal
/// "both / neither" state a nullable uri+body pair would allow.
@immutable
sealed class KitComplianceSource {
  const KitComplianceSource();

  /// A document hosted at [uri].
  const factory KitComplianceSource.remote(Uri uri) = KitComplianceRemoteSource;

  /// A document whose full text [body] ships with the app.
  const factory KitComplianceSource.inline(String body) =
      KitComplianceInlineSource;
}

/// A document hosted at [uri] (opened in a browser or fetched by the app).
@immutable
final class KitComplianceRemoteSource extends KitComplianceSource {
  const KitComplianceRemoteSource(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is KitComplianceRemoteSource && uri == other.uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'KitComplianceRemoteSource($uri)';
}

/// A document whose full text [body] is bundled with the app.
@immutable
final class KitComplianceInlineSource extends KitComplianceSource {
  const KitComplianceInlineSource(this.body);

  final String body;

  @override
  bool operator ==(Object other) =>
      other is KitComplianceInlineSource && body == other.body;

  @override
  int get hashCode => body.hashCode;

  @override
  String toString() => 'KitComplianceInlineSource(${body.length} chars)';
}

/// A versioned legal/compliance document the app may need the user to accept.
///
/// [version] is an opaque tag compared for **exact-string** equality — any
/// mismatch marks a prior acceptance outdated. No semver parsing is performed,
/// so "2026-07-01" and "1.2.0" are equally valid schemes.
@immutable
final class KitComplianceDocument {
  const KitComplianceDocument({
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

  final KitComplianceDocumentKind kind;

  /// Opaque version tag, compared exact-string (see class doc).
  final String version;

  final String title;

  final KitComplianceSource source;

  /// When this version takes effect. Informational; never used for comparison.
  final DateTime effectiveDate;

  /// Whether the user must explicitly accept this document before proceeding.
  ///
  /// When `false`, the document is [KitConsentNotRequired] regardless of
  /// records — though implicit consent can still be recorded against it.
  final bool requiresExplicitAcceptance;

  /// BCP-47 locale tag this document is written for (e.g. `en-US`), or null for
  /// a locale-agnostic document.
  final String? locale;

  @override
  bool operator ==(Object other) =>
      other is KitComplianceDocument &&
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
      'KitComplianceDocument(id: $id, kind: $kind, version: $version)';
}
