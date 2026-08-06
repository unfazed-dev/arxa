import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'appbox_kit_secure_storage_service.dart';

/// Production [AppBoxKitSecureStorageService] backed by `flutter_secure_storage`.
///
/// A thin adapter over the plugin's Keychain / Keystore-backed store. It holds
/// no state; the plugin's options types stay behind the seam (pass a
/// pre-configured [FlutterSecureStorage] to the constructor to customise them).
class FlutterSecureStorageAppBoxKitSecureStorageService
    implements AppBoxKitSecureStorageService {
  const FlutterSecureStorageAppBoxKitSecureStorageService({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}
