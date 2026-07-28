import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';

/// How the app reaches an **LLM provider**. This is one axis and one axis only.
///
/// It is deliberately NOT where the licence lives: a licence is a purchase
/// precondition (8.12) and says nothing about provider auth. Conflating the two
/// is what made a fresh install announce "BYO key — stored in the macOS
/// Keychain" having stored nothing at all.
enum CredentialTier { none, byoKey, harness, oauth }

/// A provider credential the app holds. The licence is not one of these, and
/// neither is an internal flag.
class StoredCredential {
  final String id;
  final CredentialTier tier;
  final String label;
  const StoredCredential(this.id, this.tier, this.label);
}

/// Credential storage on `flutter_secure_storage` (the macOS Keychain).
///
/// 8.6: never hand-rolled crypto. Secrets live behind the OS vault; this service
/// is a thin typed wrapper.
///
/// **Key layout.** The tier is encoded in the key namespace so the vault is
/// self-describing and [hydrate] can rebuild state after a restart without a
/// side-car index:
///
/// ```
/// <prefix>key.<id>     a BYO provider API key
/// <prefix>oauth.<id>   an OAuth token (standalone case only, 8.10)
/// <prefix>licence      the licence string (a precondition, not a tier)
/// <prefix>flag.<name>  an internal boolean; never a credential
/// ```
///
/// Harness auth (8.10) holds no token by definition, so it is in-memory only —
/// it is re-derived each launch by probing the CLI, which is the honest source.
class CredentialService {
  CredentialService({FlutterSecureStorage? store})
      : _store = store ?? const FlutterSecureStorage();

  final FlutterSecureStorage _store;

  ConfigService get _config => locator<ConfigService>();
  String get _prefix => _config.credentialKeyPrefix;

  final _credentials = <StoredCredential>[];
  List<StoredCredential> get credentials => List.unmodifiable(_credentials);

  bool _hasLicence = false;

  /// Human-readable vault name for surfaces (brief J1), e.g. "macOS Keychain".
  String get storageTierLabel => _config.credentialStorageTierLabel;

  /// Whether a licence is held. Read after [hydrate] so a restart does not
  /// forget a licence the user already paid for.
  bool get hasLicence => _hasLicence;

  String _keyKey(String id) => '${_prefix}key.$id';
  String _oauthKey(String id) => '${_prefix}oauth.$id';
  String get _licenceKey => '${_prefix}licence';
  String _flagKey(String name) => '${_prefix}flag.$name';

  /// Rebuilds in-memory state from the vault. Must be awaited during startup:
  /// without it the vault and this list are two sources of truth that disagree
  /// the moment the app restarts (a stored licence would read as absent and
  /// block the build).
  Future<void> hydrate() async {
    final all = await _store.readAll();
    _credentials.clear();
    _hasLicence = false;
    for (final entry in all.entries) {
      final k = entry.key;
      if (!k.startsWith(_prefix)) continue;
      final rest = k.substring(_prefix.length);
      if (rest == 'licence') {
        _hasLicence = true;
      } else if (rest.startsWith('key.')) {
        final id = rest.substring(4);
        _credentials.add(StoredCredential(id, CredentialTier.byoKey, id));
      } else if (rest.startsWith('oauth.')) {
        final id = rest.substring(6);
        _credentials.add(StoredCredential(id, CredentialTier.oauth, id));
      }
      // 'flag.' is intentionally ignored — an internal marker is not a credential.
    }
  }

  /// Stores a BYO **LLM provider** API key.
  Future<void> storeApiKey({required String id, required String key}) async {
    await _store.write(key: _keyKey(id), value: key);
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.byoKey)
      ..add(StoredCredential(id, CredentialTier.byoKey, id));
  }

  /// Records that auth flows through an already-authenticated harness CLI
  /// (8.10) — the app holds no token, so nothing is written to the vault.
  void markHarnessAuth(String id) {
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.harness)
      ..add(StoredCredential(id, CredentialTier.harness, id));
  }

  /// Records an OAuth token held for the standalone case only (8.10).
  Future<void> storeOAuthToken(
      {required String id, required String token}) async {
    await _store.write(key: _oauthKey(id), value: token);
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.oauth)
      ..add(StoredCredential(id, CredentialTier.oauth, id));
  }

  /// Stores the licence (a precondition, 8.12 — not a gate and not a tier).
  Future<void> storeLicence(String licence) async {
    await _store.write(key: _licenceKey, value: licence);
    _hasLicence = true;
  }

  Future<String?> readLicence() => _store.read(key: _licenceKey);

  Future<void> deleteLicence() async {
    await _store.delete(key: _licenceKey);
    _hasLicence = false;
  }

  /// Reads a provider credential's secret back. Harness entries have no secret.
  Future<String?> read(String id) async =>
      await _store.read(key: _keyKey(id)) ??
      await _store.read(key: _oauthKey(id));

  Future<void> delete(String id) async {
    await _store.delete(key: _keyKey(id));
    await _store.delete(key: _oauthKey(id));
    _credentials.removeWhere((c) => c.id == id);
  }

  // --- internal flags -------------------------------------------------------
  // Durable booleans the app needs across reinstalls (e.g. first-run). They live
  // in the vault for persistence, never in [credentials], and can never move the
  // tier. Storing one through storeApiKey() was the original defect.

  Future<void> setFlag(String name) =>
      _store.write(key: _flagKey(name), value: '1');

  Future<bool> readFlag(String name) async =>
      await _store.read(key: _flagKey(name)) != null;

  Future<void> clearFlag(String name) => _store.delete(key: _flagKey(name));

  /// Active provider-auth tier, **derived** from what is held. Highest trust
  /// wins: a harness needs no token at all, so it outranks a key we must store.
  ///
  /// Every branch tests for its tier; there is no fallback `return byoKey`.
  /// That fallback was what let any non-empty list answer "BYO key".
  CredentialTier get activeTier {
    bool has(CredentialTier t) => _credentials.any((c) => c.tier == t);
    if (has(CredentialTier.harness)) return CredentialTier.harness;
    if (has(CredentialTier.oauth)) return CredentialTier.oauth;
    if (has(CredentialTier.byoKey)) return CredentialTier.byoKey;
    return CredentialTier.none;
  }
}
