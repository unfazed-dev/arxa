// `appbox credentials` tests — list/check against a fake store
// (CredentialStore over InMemoryVault), set/unset against a temp
// SealedFileVault (SecureStore-sealed JSON file, the headless fallback).

import 'dart:io';

import 'package:appboxd/credential_cli.dart';
import 'package:appboxd/credentials.dart';
import 'package:appboxd/secure_store.dart';
import 'package:appboxd/vault.dart';
import 'package:test/test.dart';

const _catalogJson = '''
{
  "schema_version": 1,
  "credentials": [
    {
      "module": "kit/payments",
      "provider": "stripe",
      "key": "STRIPE_SECRET_KEY",
      "required": true,
      "kind": "secret",
      "url": "https://dashboard.stripe.com/apikeys",
      "simulator_note": "Test keys work on simulators."
    },
    {
      "module": "kit/payments",
      "provider": "stripe",
      "key": "STRIPE_PUBLISHABLE_KEY",
      "required": true,
      "kind": "publishable",
      "url": "https://dashboard.stripe.com/apikeys"
    },
    {
      "module": "llm/kimi",
      "provider": "kimi",
      "key": "KIMI_API_KEY",
      "required": false,
      "kind": "secret"
    }
  ]
}
''';

void main() {
  late Directory tmp;
  late String catalogPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('credential_cli_test');
    catalogPath = '${tmp.path}/catalog.json';
    File(catalogPath).writeAsStringSync(_catalogJson);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CredentialStore> fakeStore() async {
    final store =
        CredentialStore(vault: InMemoryVault(), keyPrefix: 'appbox.');
    await store.hydrate();
    return store;
  }

  group('catalog', () {
    test('loads entries with module/provider/kind/url/simulator_note', () {
      final catalog = loadCredentialCatalog(catalogPath);
      expect(catalog, hasLength(3));
      final stripe = catalog.first;
      expect(stripe.module, 'kit/payments');
      expect(stripe.provider, 'stripe');
      expect(stripe.kind, 'secret');
      expect(stripe.required, isTrue);
      expect(stripe.simulatorNote, contains('simulators'));
    });
  });

  group('check', () {
    test('exit 1 when a required key is missing, naming it (never a value)',
        () async {
      final rc = await credentialsMain(['check'],
          store: await fakeStore(), catalogPath: catalogPath);
      expect(rc, 1);
    });

    test('exit 0 once every required key is set', () async {
      final store = await fakeStore();
      await store.storeApiKey(id: 'STRIPE_SECRET_KEY', key: 'sk_test_1');
      await store.storeApiKey(id: 'STRIPE_PUBLISHABLE_KEY', key: 'pk_test_1');
      final rc = await credentialsMain(['check'],
          store: store, catalogPath: catalogPath);
      expect(rc, 0);
    });

    test('--module narrows the check; llm keys are optional', () async {
      final rc = await credentialsMain(['check', '--module', 'llm'],
          store: await fakeStore(), catalogPath: catalogPath);
      expect(rc, 0, reason: 'llm/* entries are optional BYO keys');
    });
  });

  group('list', () {
    test('exit 0 for the full catalog and per-module', () async {
      final store = await fakeStore();
      expect(
          await credentialsMain(['list'],
              store: store, catalogPath: catalogPath),
          0);
      expect(
          await credentialsMain(['list', '--module', 'kit/payments'],
              store: store, catalogPath: catalogPath),
          0);
    });
  });

  group('set/unset against a temp sealed store', () {
    // The data key lives in this vault — shared across store instances, like
    // the OS vault would be across processes.
    late InMemoryVault keyVault;
    setUp(() => keyVault = InMemoryVault());

    Future<CredentialStore> sealedStore(String path) async {
      final store = CredentialStore(
        vault: SealedFileVault(path, SecureStore(vault: keyVault)),
        keyPrefix: 'appbox.',
      );
      await store.hydrate();
      return store;
    }

    test('set stores in the sealed file; a fresh instance reads it back',
        () async {
      final path = '${tmp.path}/creds.abx';
      var store = await sealedStore(path);
      expect(
          await credentialsMain(['set', 'STRIPE_SECRET_KEY', 'sk_test_9'],
              store: store, catalogPath: catalogPath),
          0);
      expect(File(path).existsSync(), isTrue);
      // The sealed file never holds the plaintext secret.
      expect(File(path).readAsBytesSync().length, greaterThan(0));
      expect(
          String.fromCharCodes(File(path).readAsBytesSync())
              .contains('sk_test_9'),
          isFalse);
      store = await sealedStore(path);
      expect(await store.read('STRIPE_SECRET_KEY'), 'sk_test_9');
    });

    test('unset removes the key; check goes red again', () async {
      final path = '${tmp.path}/creds.abx';
      final store = await sealedStore(path);
      await credentialsMain(['set', 'STRIPE_SECRET_KEY', 'sk_test_9'],
          store: store, catalogPath: catalogPath);
      expect(
          await credentialsMain(['unset', 'STRIPE_SECRET_KEY'],
              store: store, catalogPath: catalogPath),
          0);
      expect(await store.read('STRIPE_SECRET_KEY'), isNull);
      expect(
          await credentialsMain(['check'],
              store: store, catalogPath: catalogPath),
          1);
    });

    test('set/unset reject keys that are not in the catalog', () async {
      final store = await sealedStore('${tmp.path}/creds.abx');
      expect(
          await credentialsMain(['set', 'NOT_A_KEY', 'x'],
              store: store, catalogPath: catalogPath),
          2);
      expect(
          await credentialsMain(['unset', 'NOT_A_KEY'],
              store: store, catalogPath: catalogPath),
          2);
    });
  });
}
