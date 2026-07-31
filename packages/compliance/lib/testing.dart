/// Scriptable test doubles for appbox_kit_compliance.
///
/// The consent store already ships an in-memory working default
/// ([InMemoryKitConsentStore]) usable directly in tests. This library adds the
/// license fake and re-exports the main API:
///
/// ```dart
/// final registry = KitComplianceRegistry()
///   ..register(KitComplianceDocument(
///     id: 'privacy-policy',
///     kind: KitComplianceDocumentKind.privacyPolicy,
///     version: '2026-07-01',
///     title: 'Privacy Policy',
///     source: KitComplianceSource.remote(Uri.parse('https://example.com/p')),
///     effectiveDate: DateTime(2026, 7, 1),
///   ));
/// final store = InMemoryKitConsentStore();
/// final service = KitConsentService(store: store, registry: registry);
///
/// expect((await KitConsentGate(service).evaluate()).canProceed, isFalse);
/// await service.accept(registry.byId('privacy-policy')!, appVersion: '1.0.0');
/// expect((await KitConsentGate(service).evaluate()).canProceed, isTrue);
/// await service.dispose();
///
/// // Licenses, without a Flutter binding:
/// final licenses = FakeKitLicensesService(const [
///   LicenseEntryWithLineBreaks(['my_pkg'], 'MIT ...'),
/// ]);
/// expect((await licenses.collect()).single.packages, ['my_pkg']);
/// ```
library;

import 'package:flutter/foundation.dart';

import 'src/kit_licenses_service.dart';

export 'appbox_kit_compliance.dart';

/// A [KitLicensesService] backed by a fixed list of [LicenseEntry]s instead of
/// the global [LicenseRegistry] — no Flutter binding required.
class FakeKitLicensesService extends KitLicensesService {
  FakeKitLicensesService(List<LicenseEntry> entries)
      : super(source: () => Stream<LicenseEntry>.fromIterable(entries));
}
