/// Entitlement CLI (`arxa entitlement …`) — the operator surface for the
/// cached entitlement JWT. Mirrors the retired licence_tool's shape.
///
///   `arxa entitlement status [--token <path>]`
///   `arxa entitlement verify <file>`
///
/// `status` prints exactly one JSON line to stdout — the contract other
/// arxa code consumes:
///
///   {"status":"entitled"|"unentitled"|"none","features":...,"expires":...}
///
/// where entitled = valid|grace (expired past grace, tampered/invalid,
/// wrong-machine, and unreadable tokens all report unentitled; a missing
/// token reports none). `reason` always carries the honest verdict text.
/// Exit code: 0 when the entitlement unlocks (valid/grace), 1 otherwise.
///
/// Token path resolution for `status`: `--token <path>` when given, else
/// `~/.arxa/entitlement.jwt` (the one cache location — the entitlement is
/// per-user, never per-repo).
///
/// `verify <file>` is the diagnostic form: prints the raw verdict
/// (valid|grace|expired|invalid|none plus subject/features/expires) for the
/// given file only. Same exit-code rule.
///
/// There is NO mint path in this binary. Tokens are issued exclusively by
/// the /activate Edge Function (docs/plans/entitlement-backend-runbook.md);
/// the former `mint --dev` dogfood path was deleted when the production
/// keypair landed (see test/release_gate_test.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'entitlement.dart';

/// Entry point for `arxa entitlement`. Returns the process exit code.
int entitlementMain(List<String> args) {
  if (args.isEmpty) _usage();
  switch (args.first) {
    case 'status':
      return _status(args.sublist(1));
    case 'verify':
      if (args.length != 2) _usage();
      return _verify(args[1]);
    case 'mint':
      stderr.writeln('arxa entitlement mint has been removed: the production '
          'keypair has landed and there is no client-side mint. Tokens are '
          'issued by the /activate Edge Function.');
      return 64;
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln('usage: arxa entitlement status [--token <path>] | '
      'arxa entitlement verify <file>');
  exit(64);
}

int _status(List<String> args) {
  String? explicit;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--token' && i + 1 < args.length) {
      explicit = args[i + 1];
      i++;
    } else {
      _usage();
    }
  }

  final verdict = Entitlement.verifyCurrent(path: explicit);
  if (verdict.status == EntitlementStatus.none) {
    _print({
      'status': 'none',
      'features': null,
      'expires': null,
      'reason': verdict.reason,
    });
    return 1;
  }
  _print({
    'status': verdict.unlocks ? 'entitled' : 'unentitled',
    'features': verdict.features,
    'expires': verdict.expires?.toIso8601String(),
    'reason': verdict.reason,
  });
  return verdict.unlocks ? 0 : 1;
}

int _verify(String path) {
  final verdict = Entitlement.verifyFile(path);
  _print({
    'status': verdict.status.name,
    'subject': verdict.subject,
    'features': verdict.features,
    'expires': verdict.expires?.toIso8601String(),
    'reason': verdict.reason,
    'file': path,
  });
  return verdict.unlocks ? 0 : 1;
}

void _print(Map<String, Object?> json) => stdout.writeln(jsonEncode(json));
