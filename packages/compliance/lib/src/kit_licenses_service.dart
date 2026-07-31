import 'package:flutter/foundation.dart';

import 'kit_license_entry.dart';

/// Collects OSS licenses from Flutter's [LicenseRegistry] into typed
/// [KitLicenseEntry] values.
///
/// The rendering surface (a `showLicensePage`, a custom list) stays in the app;
/// this service only gathers the data. Inject [source] to test without a
/// Flutter binding — see `FakeKitLicensesService` in
/// `package:appbox_kit_compliance/testing.dart`.
class KitLicensesService {
  KitLicensesService({Stream<LicenseEntry> Function()? source})
      : _source = source ?? (() => LicenseRegistry.licenses);

  final Stream<LicenseEntry> Function() _source;

  /// All license entries, one [KitLicenseEntry] per registered [LicenseEntry].
  Future<List<KitLicenseEntry>> collect() async {
    final entries = <KitLicenseEntry>[];
    await for (final entry in _source()) {
      entries.add(KitLicenseEntry(
        packages: List<String>.unmodifiable(entry.packages),
        paragraphs: List<String>.unmodifiable(
            [for (final paragraph in entry.paragraphs) paragraph.text]),
      ));
    }
    return List<KitLicenseEntry>.unmodifiable(entries);
  }

  /// Entries grouped by package name. A single [LicenseEntry] may list several
  /// packages, so it appears under each. Keys are sorted alphabetically.
  Future<Map<String, List<KitLicenseEntry>>> byPackage() async {
    final all = await collect();
    final grouped = <String, List<KitLicenseEntry>>{};
    for (final entry in all) {
      for (final package in entry.packages) {
        (grouped[package] ??= <KitLicenseEntry>[]).add(entry);
      }
    }
    final keys = grouped.keys.toList()..sort();
    return {
      for (final key in keys)
        key: List<KitLicenseEntry>.unmodifiable(grouped[key]!),
    };
  }
}
