/// arxa_kit_compliance — a standalone port for legal/compliance surfaces.
///
/// Three concerns, no widgets:
/// - **Documents & versions** — [ArxaKitComplianceDocument] (a versioned legal
///   document, categorised by [ArxaKitComplianceDocumentKind]) held in a
///   [ArxaKitComplianceRegistry].
/// - **Consent** — [ArxaKitConsentRecord]s persisted behind the [ArxaKitConsentStore]
///   port (default [InMemoryArxaKitConsentStore]); [ArxaKitConsentService] derives a
///   typed [ArxaKitConsentStatus] per document, and [ArxaKitConsentGate] turns the set
///   of outstanding documents into a [ArxaKitConsentGateResult].
/// - **OSS licenses** — [ArxaKitLicensesService] gathers Flutter's `LicenseRegistry`
///   into typed [ArxaKitLicenseEntry]s for the app to render (`showLicensePage` or
///   a custom surface — the UI stays in the app).
///
/// Version comparison is **exact-string** (no semver parsing): any mismatch
/// between the accepted version and the document's current version is
/// [ArxaKitConsentAcceptedOutdatedVersion]. Withdrawal beats a prior acceptance
/// (latest-wins), and anonymous (`userId == null`) versus per-user records are
/// **separate tracks**.
///
/// This package intentionally depends on no other kit (not `arxa_kit`,
/// `stacked`, or `stacked_services`) — persistence is behind a port the app
/// binds. Its only dependency is the Flutter SDK (for `LicenseRegistry` and
/// `@immutable`).
///
/// Scriptable fakes live in `package:arxa_kit_compliance/arxa_kit_testing.dart`.
library;

export 'src/arxa_kit_compliance_document.dart';
export 'src/arxa_kit_compliance_registry.dart';
export 'src/arxa_kit_consent_gate.dart';
export 'src/arxa_kit_consent_record.dart';
export 'src/arxa_kit_consent_service.dart';
export 'src/arxa_kit_consent_status.dart';
export 'src/arxa_kit_consent_store.dart';
export 'src/arxa_kit_license_entry.dart';
export 'src/arxa_kit_licenses_service.dart';
