import 'package:flutter/foundation.dart';

/// One collected OSS license: the [packages] it applies to and its [paragraphs]
/// of text.
@immutable
final class KitLicenseEntry {
  const KitLicenseEntry({required this.packages, required this.paragraphs});

  /// The packages this license covers (a single license may cover several).
  final List<String> packages;

  /// The license text, one string per paragraph.
  final List<String> paragraphs;

  @override
  bool operator ==(Object other) =>
      other is KitLicenseEntry &&
      listEquals(packages, other.packages) &&
      listEquals(paragraphs, other.paragraphs);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(packages), Object.hashAll(paragraphs));

  @override
  String toString() =>
      'KitLicenseEntry(packages: $packages, ${paragraphs.length} paragraphs)';
}
