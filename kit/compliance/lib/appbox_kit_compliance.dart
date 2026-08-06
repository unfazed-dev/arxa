/// appbox_kit_compliance — a standalone port for legal/compliance surfaces.
///
/// Three concerns, no widgets:
/// - **Documents & versions** — [AppBoxKitComplianceDocument] (a versioned legal
///   document, categorised by [AppBoxKitComplianceDocumentKind]) held in a
///   [AppBoxKitComplianceRegistry].
/// - **Consent** — [AppBoxKitConsentRecord]s persisted behind the [AppBoxKitConsentStore]
///   port (default [InMemoryAppBoxKitConsentStore]); [AppBoxKitConsentService] derives a
///   typed [AppBoxKitConsentStatus] per document, and [AppBoxKitConsentGate] turns the set
///   of outstanding documents into a [AppBoxKitConsentGateResult].
/// - **OSS licenses** — [AppBoxKitLicensesService] gathers Flutter's `LicenseRegistry`
///   into typed [AppBoxKitLicenseEntry]s for the app to render (`showLicensePage` or
///   a custom surface — the UI stays in the app).
///
/// Version comparison is **exact-string** (no semver parsing): any mismatch
/// between the accepted version and the document's current version is
/// [AppBoxKitConsentAcceptedOutdatedVersion]. Withdrawal beats a prior acceptance
/// (latest-wins), and anonymous (`userId == null`) versus per-user records are
/// **separate tracks**.
///
/// This package intentionally depends on no other kit (not `appbox_kit`,
/// `stacked`, or `stacked_services`) — persistence is behind a port the app
/// binds. Its only dependency is the Flutter SDK (for `LicenseRegistry` and
/// `@immutable`).
///
/// Scriptable fakes live in `package:appbox_kit_compliance/appbox_kit_testing.dart`.
library;

export 'src/appbox_kit_compliance_document.dart';
export 'src/appbox_kit_compliance_registry.dart';
export 'src/appbox_kit_consent_gate.dart';
export 'src/appbox_kit_consent_record.dart';
export 'src/appbox_kit_consent_service.dart';
export 'src/appbox_kit_consent_status.dart';
export 'src/appbox_kit_consent_store.dart';
export 'src/appbox_kit_license_entry.dart';
export 'src/appbox_kit_licenses_service.dart';
