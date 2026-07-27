import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';

/// How a credential reached the vault. Surfaced in the UI verbatim
/// ("stored in the macOS Keychain") so a buyer never has to guess the tier.
enum CredentialTier { none, byoKey, harness, oauth }

/// A credential the app holds (an API key, an OAuth token, the licence).
class StoredCredential {
  final String id;
  final CredentialTier tier;
  final String label;
  const StoredCredential(this.id, this.tier, this.label);
}

/// Credential storage on `flutter_secure_storage` (the macOS Keychain).
///
/// 8.6: never hand-rolled crypto. Secrets live behind the OS vault; this service
/// is a thin typed wrapper. The active tier is observable so surfaces can state
/// it plainly ("stored in the macOS Keychain").
class CredentialService {
  final _store = const FlutterSecureStorage();

  ConfigService get _config => locator<ConfigService>();

  final _credentials = <StoredCredential>[];
  List<StoredCredential> get credentials => List.unmodifiable(_credentials);

  /// Human-readable tier label for surfaces (brief J1).
  String get storageTierLabel => _config.credentialStorageTierLabel;

  bool get hasLicence => _credentials.any((c) => c.id == 'licence');

  /// Stores a BYO API key in the Keychain and records its tier.
  Future<void> storeApiKey({required String id, required String key}) async {
    await _store.write(key: '${_config.credentialKeyPrefix}$id', value: key);
    _credentials.add(StoredCredential(id, CredentialTier.byoKey, id));
  }

  /// Records that auth flows through an already-authenticated harness CLI (8.10)
  /// — no token held by the app.
  void markHarnessAuth(String id) {
    _credentials.add(StoredCredential(id, CredentialTier.harness, id));
  }

  /// Records an OAuth token held for the standalone case only (8.10).
  Future<void> storeOAuthToken({required String id, required String token}) async {
    await _store.write(key: '${_config.credentialKeyPrefix}$id', value: token);
    _credentials.add(StoredCredential(id, CredentialTier.oauth, id));
  }

  /// Stores the licence string (a precondition, 8.12 — not a gate).
  Future<void> storeLicence(String licence) async {
    await _store.write(key: '${_config.credentialKeyPrefix}licence', value: licence);
    _credentials.add(const StoredCredential('licence', CredentialTier.byoKey, 'Licence'));
  }

  Future<String?> read(String id) =>
      _store.read(key: '${_config.credentialKeyPrefix}$id');

  Future<void> delete(String id) async {
    await _store.delete(key: '${_config.credentialKeyPrefix}$id');
    _credentials.removeWhere((c) => c.id == id);
  }

  /// Active tier for the UI badge. Highest-trust tier wins.
  CredentialTier get activeTier {
    if (_credentials.isEmpty) return CredentialTier.none;
    if (_credentials.any((c) => c.tier == CredentialTier.harness)) {
      return CredentialTier.harness;
    }
    if (_credentials.any((c) => c.tier == CredentialTier.oauth)) {
      return CredentialTier.oauth;
    }
    return CredentialTier.byoKey;
  }
}
