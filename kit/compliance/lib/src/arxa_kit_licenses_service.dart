import 'package:flutter/foundation.dart';

import 'arxa_kit_license_entry.dart';

/// Collects OSS licenses from Flutter's [LicenseRegistry] into typed
/// [ArxaKitLicenseEntry] values.
///
/// The rendering surface (a `showLicensePage`, a custom list) stays in the app;
/// this service only gathers the data. Inject [source] to test without a
/// Flutter binding — see `FakeArxaKitLicensesService` in
/// `package:arxa_kit_compliance/arxa_kit_testing.dart`.
class ArxaKitLicensesService {
  ArxaKitLicensesService({Stream<LicenseEntry> Function()? source})
      : _source = source ?? (() => LicenseRegistry.licenses);

  final Stream<LicenseEntry> Function() _source;

  /// All license entries, one [ArxaKitLicenseEntry] per registered [LicenseEntry].
  Future<List<ArxaKitLicenseEntry>> collect() async {
    final entries = <ArxaKitLicenseEntry>[];
    await for (final entry in _source()) {
      entries.add(ArxaKitLicenseEntry(
        packages: List<String>.unmodifiable(entry.packages),
        paragraphs: List<String>.unmodifiable(
            [for (final paragraph in entry.paragraphs) paragraph.text]),
      ));
    }
    return List<ArxaKitLicenseEntry>.unmodifiable(entries);
  }

  /// Entries grouped by package name. A single [LicenseEntry] may list several
  /// packages, so it appears under each. Keys are sorted alphabetically.
  Future<Map<String, List<ArxaKitLicenseEntry>>> byPackage() async {
    final all = await collect();
    final grouped = <String, List<ArxaKitLicenseEntry>>{};
    for (final entry in all) {
      for (final package in entry.packages) {
        (grouped[package] ??= <ArxaKitLicenseEntry>[]).add(entry);
      }
    }
    final keys = grouped.keys.toList()..sort();
    return {
      for (final key in keys)
        key: List<ArxaKitLicenseEntry>.unmodifiable(grouped[key]!),
    };
  }
}
