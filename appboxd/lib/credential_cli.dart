// `appbox credentials` — the unified credential manager.
//
// One catalog (config/credentials.catalog.json) names every credential a user
// may need — kit modules (payments/auth/maps/deploy/...) and LLM providers.
// Secrets are stored through [CredentialStore] over the OS vault
// (credentials.dart), with a [SealedFileVault] fallback on hosts without a
// vault backend. `list`/`check` report set/unset status only — secret values
// are never printed.
//
//   appbox credentials list [--module <m>]    catalog + set/unset status
//   appbox credentials check [--module <m>]   missing required keys (exit 1)
//   appbox credentials set <KEY> [value]      store (stdin when value omitted)
//   appbox credentials unset <KEY>            remove
//
// Exit codes: 0 ok · 1 check found missing required keys · 2 usage/unknown key.

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/credentials.dart';
import 'package:appboxd/secure_store.dart';
import 'package:appboxd/vault.dart';
import 'package:path/path.dart' as p;

const _usage = '''
Usage: appbox credentials <verb> [args]

Verbs:
  list [--module <m>]    Show the catalog with set/unset status (no secrets)
  check [--module <m>]   Exit 1 when required keys are missing (module or all)
  set <KEY> [value]      Store a credential in the vault (reads stdin when
                         the value is omitted)
  unset <KEY>            Remove a credential from the vault
''';

/// One catalog entry — see config/credentials.catalog.json.
class CatalogEntry {
  const CatalogEntry({
    required this.module,
    required this.provider,
    required this.key,
    required this.required,
    required this.kind,
    this.url,
    this.simulatorNote,
  });

  final String module;
  final String provider;
  final String key;
  final bool required;

  /// `secret` | `publishable` — publishable values may ship in the client.
  final String kind;
  final String? url;
  final String? simulatorNote;
}

/// Loads config/credentials.catalog.json.
List<CatalogEntry> loadCredentialCatalog(String path) {
  final doc = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final e in doc['credentials'] as List)
      CatalogEntry(
        module: e['module'] as String,
        provider: e['provider'] as String,
        key: e['key'] as String,
        required: e['required'] as bool,
        kind: e['kind'] as String,
        url: e['url'] as String?,
        simulatorNote: e['simulator_note'] as String?,
      ),
  ];
}

/// The store the CLI uses when no test double is injected: the OS vault, with
/// a sealed-file fallback where no vault backend exists yet.
Future<CredentialStore> defaultCredentialStore(String stateDir) async {
  Vault vault;
  try {
    vault = platformVault();
  } on UnsupportedError {
    vault = SealedFileVault(
      p.join(stateDir, 'credentials.abx'),
      SecureStore(vault: null),
    );
  }
  final store = CredentialStore(vault: vault, keyPrefix: 'appbox.');
  await store.hydrate();
  return store;
}

/// Entry point for `appbox credentials`. Returns the process exit code.
Future<int> credentialsMain(
  List<String> args, {
  CredentialStore? store,
  String? catalogPath,
}) async {
  if (args.isEmpty) {
    stderr.write(_usage);
    return 2;
  }
  final verb = args.first;
  final rest = args.sublist(1);

  String? module;
  final positional = <String>[];
  for (var i = 0; i < rest.length; i++) {
    if (rest[i] == '--module' && i + 1 < rest.length) {
      module = rest[++i];
    } else {
      positional.add(rest[i]);
    }
  }

  final catalog = loadCredentialCatalog(
      catalogPath ?? 'config/credentials.catalog.json');
  bool matches(CatalogEntry e) =>
      module == null || e.module == module || e.module.startsWith('$module/');

  store ??= await defaultCredentialStore(p.join(_homeDir(), '.appbox'));

  switch (verb) {
    case 'list':
      final setIds = store.credentials.map((c) => c.id).toSet();
      String? lastModule;
      for (final e in catalog.where(matches)) {
        if (e.module != lastModule) {
          print(e.module);
          lastModule = e.module;
        }
        final status = setIds.contains(e.key) ? 'set' : 'unset';
        final req = e.required ? 'required' : 'optional';
        print('  ${e.key}  [${e.kind} · $req · $status]  ${e.provider}');
      }
      return 0;
    case 'check':
      final missing = <CatalogEntry>[];
      for (final e in catalog.where(matches)) {
        if (e.required && await store.read(e.key) == null) missing.add(e);
      }
      if (missing.isEmpty) {
        print('credentials check: all required keys set'
            '${module != null ? ' ($module)' : ''}');
        return 0;
      }
      for (final e in missing) {
        stderr.writeln('missing required: ${e.key} (${e.module}/${e.provider})'
            '${e.url != null ? ' — ${e.url}' : ''}');
      }
      stderr.writeln(
          'credentials check: ${missing.length} required key(s) missing');
      return 1;
    case 'set':
      if (positional.isEmpty) {
        stderr.writeln('appbox credentials set: missing <KEY>');
        return 2;
      }
      final key = positional.first;
      if (!catalog.any((e) => e.key == key)) {
        stderr.writeln('appbox credentials set: "$key" is not in the catalog');
        return 2;
      }
      final value = positional.length > 1
          ? positional[1]
          : stdin.readLineSync()?.trim() ?? '';
      if (value.isEmpty) {
        stderr.writeln('appbox credentials set: empty value, nothing stored');
        return 2;
      }
      await store.storeApiKey(id: key, key: value);
      print('set $key');
      return 0;
    case 'unset':
      if (positional.isEmpty) {
        stderr.writeln('appbox credentials unset: missing <KEY>');
        return 2;
      }
      final key = positional.first;
      if (!catalog.any((e) => e.key == key)) {
        stderr.writeln(
            'appbox credentials unset: "$key" is not in the catalog');
        return 2;
      }
      await store.delete(key);
      print('unset $key');
      return 0;
    default:
      stderr.writeln('appbox credentials: unknown verb "$verb"');
      stderr.write(_usage);
      return 2;
  }
}

String _homeDir() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
