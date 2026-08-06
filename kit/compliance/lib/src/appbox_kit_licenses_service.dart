import 'package:flutter/foundation.dart';

import 'appbox_kit_license_entry.dart';

/// Collects OSS licenses from Flutter's [LicenseRegistry] into typed
/// [AppBoxKitLicenseEntry] values.
///
/// The rendering surface (a `showLicensePage`, a custom list) stays in the app;
/// this service only gathers the data. Inject [source] to test without a
/// Flutter binding — see `FakeAppBoxKitLicensesService` in
/// `package:appbox_kit_compliance/appbox_kit_testing.dart`.
class AppBoxKitLicensesService {
  AppBoxKitLicensesService({Stream<LicenseEntry> Function()? source})
      : _source = source ?? (() => LicenseRegistry.licenses);

  final Stream<LicenseEntry> Function() _source;

  /// All license entries, one [AppBoxKitLicenseEntry] per registered [LicenseEntry].
  Future<List<AppBoxKitLicenseEntry>> collect() async {
    final entries = <AppBoxKitLicenseEntry>[];
    await for (final entry in _source()) {
      entries.add(AppBoxKitLicenseEntry(
        packages: List<String>.unmodifiable(entry.packages),
        paragraphs: List<String>.unmodifiable(
            [for (final paragraph in entry.paragraphs) paragraph.text]),
      ));
    }
    return List<AppBoxKitLicenseEntry>.unmodifiable(entries);
  }

  /// Entries grouped by package name. A single [LicenseEntry] may list several
  /// packages, so it appears under each. Keys are sorted alphabetically.
  Future<Map<String, List<AppBoxKitLicenseEntry>>> byPackage() async {
    final all = await collect();
    final grouped = <String, List<AppBoxKitLicenseEntry>>{};
    for (final entry in all) {
      for (final package in entry.packages) {
        (grouped[package] ??= <AppBoxKitLicenseEntry>[]).add(entry);
      }
    }
    final keys = grouped.keys.toList()..sort();
    return {
      for (final key in keys)
        key: List<AppBoxKitLicenseEntry>.unmodifiable(grouped[key]!),
    };
  }
}
