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
//   appbox credentials exec <KEY>... -- <cmd> run <cmd> with those keys in its
//                                             environment (never printed)
//
// Exit codes: 0 ok · 1 check found missing required keys · 2 usage/unknown key.
// EXCEPT `exec`, which returns the CHILD's exit code — so 1 and 2 are ambiguous
// there (they may be the child's, not ours). Every failure `exec` itself owns
// happens before the child starts, so an exec-owned 2 always comes with a
// message on stderr and no child output at all.
//
// Why `exec` and not `get`: a `get` verb would print a secret to stdout, where
// it lands in scrollback, shell history, CI logs, and agent transcripts. `exec`
// passes the value parent→child through the environment only — never argv (argv
// is world-readable via `ps`), never stdout. That keeps "secret values are never
// printed" literally true. It is not a defense against the machine's own owner:
// anyone who can run `exec` can run `exec KEY -- sh -c 'echo $KEY'`. It prevents
// accidents, which is the threat that actually keeps happening.

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
  exec <KEY>... -- <cmd> [args]
                         Run <cmd> with each KEY in its environment. The value
                         is never printed and never passed as an argument.
                         Returns the child's exit code.
                         e.g. appbox credentials exec ZAI_API_KEY -- dsh
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

  // `exec` is a passthrough, so everything after `--` belongs to the CHILD and
  // must never reach the flag scan below — otherwise a child's own `--module`
  // (or any future flag we add) gets silently eaten out of its argv.
  List<String>? childArgv;
  var scan = rest;
  if (verb == 'exec') {
    final sep = rest.indexOf('--');
    if (sep < 0) {
      stderr.writeln('appbox credentials exec: missing `--` before the command');
      stderr.writeln('  usage: appbox credentials exec <KEY>... -- <cmd> [args]');
      return 2;
    }
    scan = rest.sublist(0, sep);
    childArgv = rest.sublist(sep + 1);
  }

  String? module;
  final positional = <String>[];
  for (var i = 0; i < scan.length; i++) {
    if (scan[i] == '--module' && i + 1 < scan.length) {
      module = scan[++i];
    } else {
      positional.add(scan[i]);
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
    case 'exec':
      if (positional.isEmpty) {
        stderr.writeln('appbox credentials exec: missing <KEY> before `--`');
        return 2;
      }
      if (childArgv!.isEmpty) {
        stderr.writeln('appbox credentials exec: missing command after `--`');
        return 2;
      }
      // Same catalog gate as set/unset: an off-catalog name here would silently
      // inject nothing, and the child would fail somewhere far downstream with
      // no hint that the key name was the problem.
      for (final key in positional) {
        if (!catalog.any((e) => e.key == key)) {
          stderr.writeln(
              'appbox credentials exec: "$key" is not in the catalog');
          return 2;
        }
      }
      final childEnv = Map<String, String>.of(Platform.environment);
      for (final key in positional) {
        final value = await store.read(key);
        if (value == null || value.isEmpty) {
          // Fail CLOSED. Running the command without the key it asked for makes
          // the failure surface later, inside the child, as something unrelated.
          stderr.writeln('appbox credentials exec: "$key" is not set in the '
              'vault — refusing to run the command');
          stderr.writeln('  store it with: appbox credentials set $key');
          return 2;
        }
        childEnv[key] = value;
      }
      try {
        final proc = await Process.start(
          childArgv.first,
          childArgv.sublist(1),
          environment: childEnv,
          mode: ProcessStartMode.inheritStdio,
        );
        return await proc.exitCode;
      } on ProcessException catch (e) {
        stderr.writeln('appbox credentials exec: cannot run '
            '"${childArgv.first}": ${e.message}');
        return 127; // conventional "command not found"
      }
    default:
      stderr.writeln('appbox credentials: unknown verb "$verb"');
      stderr.write(_usage);
      return 2;
  }
}

String _homeDir() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
