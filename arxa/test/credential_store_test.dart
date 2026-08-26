import 'package:arxa/credentials.dart';
import 'package:arxa/vault.dart';
import 'package:test/test.dart';

void main() {
  const prefix = 'arxa.';
  late InMemoryVault vault;
  late CredentialStore store;

  setUp(() {
    vault = InMemoryVault();
    store = CredentialStore(vault: vault, keyPrefix: prefix);
  });

  test('stores and reads a BYO API key under <prefix>key.<id>', () async {
    await store.storeApiKey(id: 'anthropic', key: 'sk-1');
    expect(await vault.read('arxa.key.anthropic'), 'sk-1');
    expect(await store.read('anthropic'), 'sk-1');
    expect(store.activeTier, CredentialTier.byoKey);
  });

  test('flags persist in the vault but are never credentials', () async {
    await store.setFlag('first_run_done');
    expect(await store.readFlag('first_run_done'), isTrue);
    expect(store.credentials, isEmpty);
    await store.clearFlag('first_run_done');
    expect(await store.readFlag('first_run_done'), isFalse);
  });

  test('hydrate rebuilds tiers from the vault key layout', () async {
    await vault.write('arxa.key.openai', 'sk-2');
    await vault.write('arxa.oauth.google', 'tok');
    await vault.write('arxa.flag.x', '1');
    await vault.write('foreign.key', 'nope');

    await store.hydrate();

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
        await vault.readAllKeys(), isNot(contains('arxa.key.claude-cli')));
  });

  test('delete removes both key and oauth entries for the id', () async {
    await store.storeApiKey(id: 'x', key: 'k');
    await store.storeOAuthToken(id: 'x', token: 't');
    await store.delete('x');
    expect(await vault.read('arxa.key.x'), isNull);
    expect(await vault.read('arxa.oauth.x'), isNull);
    expect(store.activeTier, CredentialTier.none);
  });
}
