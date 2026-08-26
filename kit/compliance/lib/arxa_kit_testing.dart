/// Scriptable test doubles for arxa_kit_compliance.
///
/// The consent store already ships an in-memory working default
/// ([InMemoryArxaKitConsentStore]) usable directly in tests. This library adds the
/// license fake and re-exports the main API:
///
/// ```dart
/// final registry = ArxaKitComplianceRegistry()
///   ..register(ArxaKitComplianceDocument(
///     id: 'privacy-policy',
///     kind: ArxaKitComplianceDocumentKind.privacyPolicy,
///     version: '2026-07-01',
///     title: 'Privacy Policy',
///     source: ArxaKitComplianceSource.remote(Uri.parse('https://example.com/p')),
///     effectiveDate: DateTime(2026, 7, 1),
///   ));
/// final store = InMemoryArxaKitConsentStore();
/// final service = ArxaKitConsentService(store: store, registry: registry);
///
/// expect((await ArxaKitConsentGate(service).evaluate()).canProceed, isFalse);
/// await service.accept(registry.byId('privacy-policy')!, appVersion: '1.0.0');
/// expect((await ArxaKitConsentGate(service).evaluate()).canProceed, isTrue);
/// await service.dispose();
///
/// // Licenses, without a Flutter binding:
/// final licenses = FakeArxaKitLicensesService(const [
///   LicenseEntryWithLineBreaks(['my_pkg'], 'MIT ...'),
/// ]);
/// expect((await licenses.collect()).single.packages, ['my_pkg']);
/// ```
library;

import 'package:flutter/foundation.dart';

import 'src/arxa_kit_licenses_service.dart';

export 'arxa_kit_compliance.dart';

/// A [ArxaKitLicensesService] backed by a fixed list of [LicenseEntry]s instead of
/// the global [LicenseRegistry] — no Flutter binding required.
class FakeArxaKitLicensesService extends ArxaKitLicensesService {
  FakeArxaKitLicensesService(List<LicenseEntry> entries)
      : super(source: () => Stream<LicenseEntry>.fromIterable(entries));
}
