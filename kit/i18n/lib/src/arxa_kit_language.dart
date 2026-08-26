/// A supported language: BCP-47 tag plus English and native display names.
class ArxaKitLanguage {
  const ArxaKitLanguage({
    required this.tag,
    required this.nameEn,
    required this.nameNative,
  });

  /// BCP-47 language tag, e.g. `'en'` or `'pl'`.
  final String tag;

  /// English name, e.g. `'Polish'`.
  final String nameEn;

  /// Native endonym, e.g. `'polski'`.
  final String nameNative;

  /// Languages the kit ships with. Apps serving more locales extend their own
  /// table — lookups never hardcode beyond this launch set.
  static const List<ArxaKitLanguage> supported = [
    ArxaKitLanguage(tag: 'en', nameEn: 'English', nameNative: 'English'),
    ArxaKitLanguage(tag: 'pl', nameEn: 'Polish', nameNative: 'polski'),
  ];

  /// English, the kit-wide default when nothing else resolves.
  static const ArxaKitLanguage fallback = ArxaKitLanguage(
    tag: 'en',
    nameEn: 'English',
    nameNative: 'English',
  );

  /// Look up a language by BCP-47 tag, falling back to the base subtag so
  /// `'pl-PL'` resolves to `'pl'`. Null when no supported language matches.
  static ArxaKitLanguage? byTag(String tag) {
    for (final lang in supported) {
      if (lang.tag == tag) return lang;
    }
    final base = tag.split(RegExp('[-_]')).first;
    for (final lang in supported) {
      if (lang.tag == base) return lang;
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ArxaKitLanguage && other.tag == tag;

  @override
  int get hashCode => tag.hashCode;

  @override
  String toString() => 'ArxaKitLanguage($tag, $nameEn / $nameNative)';
}
