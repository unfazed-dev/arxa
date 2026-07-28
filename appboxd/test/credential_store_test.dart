import 'package:appboxd/credentials.dart';
import 'package:appboxd/vault.dart';
import 'package:test/test.dart';

void main() {
  const prefix = 'app_box.';
  late InMemoryVault vault;
  late CredentialStore store;

  setUp(() {
    vault = InMemoryVault();
    store = CredentialStore(vault: vault, keyPrefix: prefix);
  });

  test('stores and reads a BYO API key under <prefix>key.<id>', () async {
    await store.storeApiKey(id: 'anthropic', key: 'sk-1');
    expect(await vault.read('app_box.key.anthropic'), 'sk-1');
    expect(await store.read('anthropic'), 'sk-1');
    expect(store.activeTier, CredentialTier.byoKey);
  });

  test('a licence is a precondition, not a credential', () async {
    await store.storeLicence('LIC-123');
    expect(store.hasLicence, isTrue);
    expect(await store.readLicence(), 'LIC-123');
    expect(store.credentials, isEmpty);
    expect(store.activeTier, CredentialTier.none);
  });

  test('flags persist in the vault but are never credentials', () async {
    await store.setFlag('first_run_done');
    expect(await store.readFlag('first_run_done'), isTrue);
    expect(store.credentials, isEmpty);
    await store.clearFlag('first_run_done');
    expect(await store.readFlag('first_run_done'), isFalse);
  });

  test('hydrate rebuilds tiers from the vault key layout', () async {
    await vault.write('app_box.key.openai', 'sk-2');
    await vault.write('app_box.oauth.google', 'tok');
    await vault.write('app_box.licence', 'LIC');
    await vault.write('app_box.flag.x', '1');
    await vault.write('foreign.key', 'nope');

    await store.hydrate();

    expect(store.hasLicence, isTrue);
    expect(store.credentials.map((c) => c.id),
        containsAll(['openai', 'google']));
    // oauth outranks byoKey; the foreign key and the flag are invisible.
    expect(store.activeTier, CredentialTier.oauth);
  });

  test('harness outranks every stored tier and holds no secret', () async {
    await store.storeApiKey(id: 'anthropic', key: 'sk-1');
    store.markHarnessAuth('claude-cli');
    expect(store.activeTier, CredentialTier.harness);
    expect(
        await vault.readAllKeys(), isNot(contains('app_box.key.claude-cli')));
  });

  test('delete removes both key and oauth entries for the id', () async {
    await store.storeApiKey(id: 'x', key: 'k');
    await store.storeOAuthToken(id: 'x', token: 't');
    await store.delete('x');
    expect(await vault.read('app_box.key.x'), isNull);
    expect(await vault.read('app_box.oauth.x'), isNull);
    expect(store.activeTier, CredentialTier.none);
  });
}
