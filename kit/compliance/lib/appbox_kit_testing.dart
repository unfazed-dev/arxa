/// Scriptable test doubles for appbox_kit_compliance.
///
/// The consent store already ships an in-memory working default
/// ([InMemoryAppBoxKitConsentStore]) usable directly in tests. This library adds the
/// license fake and re-exports the main API:
///
/// ```dart
/// final registry = AppBoxKitComplianceRegistry()
///   ..register(AppBoxKitComplianceDocument(
///     id: 'privacy-policy',
///     kind: AppBoxKitComplianceDocumentKind.privacyPolicy,
///     version: '2026-07-01',
///     title: 'Privacy Policy',
///     source: AppBoxKitComplianceSource.remote(Uri.parse('https://example.com/p')),
///     effectiveDate: DateTime(2026, 7, 1),
///   ));
/// final store = InMemoryAppBoxKitConsentStore();
/// final service = AppBoxKitConsentService(store: store, registry: registry);
///
/// expect((await AppBoxKitConsentGate(service).evaluate()).canProceed, isFalse);
/// await service.accept(registry.byId('privacy-policy')!, appVersion: '1.0.0');
/// expect((await AppBoxKitConsentGate(service).evaluate()).canProceed, isTrue);
/// await service.dispose();
///
/// // Licenses, without a Flutter binding:
/// final licenses = FakeAppBoxKitLicensesService(const [
///   LicenseEntryWithLineBreaks(['my_pkg'], 'MIT ...'),
/// ]);
/// expect((await licenses.collect()).single.packages, ['my_pkg']);
/// ```
library;

import 'package:flutter/foundation.dart';

import 'src/appbox_kit_licenses_service.dart';

export 'appbox_kit_compliance.dart';

/// A [AppBoxKitLicensesService] backed by a fixed list of [LicenseEntry]s instead of
/// the global [LicenseRegistry] — no Flutter binding required.
class FakeAppBoxKitLicensesService extends AppBoxKitLicensesService {
  FakeAppBoxKitLicensesService(List<LicenseEntry> entries)
      : super(source: () => Stream<LicenseEntry>.fromIterable(entries));
}
