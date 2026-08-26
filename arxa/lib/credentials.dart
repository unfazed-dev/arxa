import 'vault.dart';

/// How the daemon reaches an **LLM provider**. One axis and one axis only —
/// deliberately NOT where the entitlement lives: an entitlement is a purchase
/// precondition and says nothing about provider auth.
enum CredentialTier { none, byoKey, harness, oauth }

/// A provider credential the daemon holds. An internal flag is not one of
/// these either.
class StoredCredential {
  final String id;
  final CredentialTier tier;
  final String label;
  const StoredCredential(this.id, this.tier, this.label);
}

/// Credential storage over the OS [Vault].
///
/// Ported from `app/lib/services/credential_service.dart`
/// (flutter_secure_storage → [Vault] seam; locator → injected key prefix).
///
/// **Key layout.** The tier is encoded in the key namespace so the vault is
/// self-describing and [hydrate] can rebuild state after a restart without a
/// side-car index:
///
/// ```
/// <prefix>key.<id>     a BYO provider API key
/// <prefix>oauth.<id>   an OAuth token (standalone case only, 8.10)
/// <prefix>flag.<name>  an internal boolean; never a credential
/// ```
///
/// Harness auth (8.10) holds no token by definition, so it is in-memory only —
/// re-derived each launch by probing the CLI, which is the honest source.
class CredentialStore {
  CredentialStore({required this.vault, required this.keyPrefix});

  final Vault vault;
  final String keyPrefix;

  final _credentials = <StoredCredential>[];
  List<StoredCredential> get credentials => List.unmodifiable(_credentials);

  String _keyKey(String id) => '${keyPrefix}key.$id';
  String _oauthKey(String id) => '${keyPrefix}oauth.$id';
  String _flagKey(String name) => '${keyPrefix}flag.$name';

  /// Rebuilds in-memory state from the vault. Must be awaited during startup:
  /// without it the vault and this list are two sources of truth that disagree
  /// the moment the daemon restarts.
  Future<void> hydrate() async {
    final all = await vault.readAllKeys();
    _credentials.clear();
    for (final k in all) {
      if (!k.startsWith(keyPrefix)) continue;
      final rest = k.substring(keyPrefix.length);
      if (rest.startsWith('key.')) {
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
    await vault.write(_keyKey(id), key);
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.byoKey)
      ..add(StoredCredential(id, CredentialTier.byoKey, id));
  }

  /// Records that auth flows through an already-authenticated harness CLI
  /// (8.10) — the daemon holds no token, so nothing is written to the vault.
  void markHarnessAuth(String id) {
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.harness)
      ..add(StoredCredential(id, CredentialTier.harness, id));
  }

  /// Records an OAuth token held for the standalone case only (8.10).
  Future<void> storeOAuthToken(
      {required String id, required String token}) async {
    await vault.write(_oauthKey(id), token);
    _credentials
      ..removeWhere((c) => c.id == id && c.tier == CredentialTier.oauth)
      ..add(StoredCredential(id, CredentialTier.oauth, id));
  }

  /// Reads a provider credential's secret back. Harness entries have no secret.
  Future<String?> read(String id) async =>
      await vault.read(_keyKey(id)) ?? await vault.read(_oauthKey(id));

  Future<void> delete(String id) async {
    await vault.delete(_keyKey(id));
    await vault.delete(_oauthKey(id));
    _credentials.removeWhere((c) => c.id == id);
  }

  // --- internal flags -------------------------------------------------------
  // Durable booleans the daemon needs across restarts (e.g. first-run). They
  // live in the vault for persistence, never in [credentials], and can never
  // move the tier.

  Future<void> setFlag(String name) => vault.write(_flagKey(name), '1');

  Future<bool> readFlag(String name) async =>
      await vault.read(_flagKey(name)) != null;

  Future<void> clearFlag(String name) => vault.delete(_flagKey(name));

  /// Active provider-auth tier, **derived** from what is held. Highest trust
  /// wins: a harness needs no token at all, so it outranks a key we must store.
  ///
  /// Every branch tests for its tier; there is no fallback `return byoKey`.
  CredentialTier get activeTier {
    bool has(CredentialTier t) => _credentials.any((c) => c.tier == t);
    if (has(CredentialTier.harness)) return CredentialTier.harness;
    if (has(CredentialTier.oauth)) return CredentialTier.oauth;
    if (has(CredentialTier.byoKey)) return CredentialTier.byoKey;
    return CredentialTier.none;
  }
}
