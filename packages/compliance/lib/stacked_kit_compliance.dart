/// appbox_kit_compliance — a standalone port for legal/compliance surfaces.
///
/// Three concerns, no widgets:
/// - **Documents & versions** — [KitComplianceDocument] (a versioned legal
///   document, categorised by [KitComplianceDocumentKind]) held in a
///   [KitComplianceRegistry].
/// - **Consent** — [KitConsentRecord]s persisted behind the [KitConsentStore]
///   port (default [InMemoryKitConsentStore]); [KitConsentService] derives a
///   typed [KitConsentStatus] per document, and [KitConsentGate] turns the set
///   of outstanding documents into a [KitConsentGateResult].
/// - **OSS licenses** — [KitLicensesService] gathers Flutter's `LicenseRegistry`
///   into typed [KitLicenseEntry]s for the app to render (`showLicensePage` or
///   a custom surface — the UI stays in the app).
///
/// Version comparison is **exact-string** (no semver parsing): any mismatch
/// between the accepted version and the document's current version is
/// [KitConsentAcceptedOutdatedVersion]. Withdrawal beats a prior acceptance
/// (latest-wins), and anonymous (`userId == null`) versus per-user records are
/// **separate tracks**.
///
/// This package intentionally depends on no other kit (not `stacked_kit`,
/// `stacked`, or `stacked_services`) — persistence is behind a port the app
/// binds. Its only dependency is the Flutter SDK (for `LicenseRegistry` and
/// `@immutable`).
///
/// Scriptable fakes live in `package:appbox_kit_compliance/testing.dart`.
library;

export 'src/kit_compliance_document.dart';
export 'src/kit_compliance_registry.dart';
export 'src/kit_consent_gate.dart';
export 'src/kit_consent_record.dart';
export 'src/kit_consent_service.dart';
export 'src/kit_consent_status.dart';
export 'src/kit_consent_store.dart';
export 'src/kit_license_entry.dart';
export 'src/kit_licenses_service.dart';
