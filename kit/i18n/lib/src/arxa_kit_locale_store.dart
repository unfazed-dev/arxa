import 'package:shared_preferences/shared_preferences.dart';

/// Persistence port for the user's locale override.
///
/// Implementations store a single BCP-47 tag (or nothing — no override).
/// Tests use `FakeArxaKitLocaleStore` from `arxa_kit_i18n/arxa_kit_testing.dart`.
abstract interface class ArxaKitLocaleStore {
  /// The persisted override tag, or null when none is set.
  Future<String?> read();

  /// Persist [tag] as the override.
  Future<void> write(String tag);

  /// Remove the override (fall back to the system locale).
  Future<void> clear();
}

/// [ArxaKitLocaleStore] backed by `shared_preferences`.
///
/// Uses `SharedPreferencesWithCache` scoped to the single `'locale'` key so no
/// other preference ever touches the cache. Create once at app start and keep
/// the instance.
class SharedPreferencesArxaKitLocaleStore implements ArxaKitLocaleStore {
  SharedPreferencesArxaKitLocaleStore._(this._prefs);

  /// The shared_preferences key the override lives under.
  static const String key = 'locale';

  final SharedPreferencesWithCache _prefs;

  /// Create the store, instantiating the underlying cache once.
  static Future<SharedPreferencesArxaKitLocaleStore> create() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    return SharedPreferencesArxaKitLocaleStore._(prefs);
  }

  @override
  Future<String?> read() async => _prefs.getString(key);

  @override
  Future<void> write(String tag) => _prefs.setString(key, tag);

  @override
  Future<void> clear() => _prefs.remove(key);
}
