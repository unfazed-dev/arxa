/// Standalone licence CLI (deliberately separate from bin/appboxd.dart).
///
///   `dart run bin/licence_tool.dart status [--licence <path>]`
///   `dart run bin/licence_tool.dart verify <file>`
///
/// `status` prints exactly one JSON line to stdout — the contract other
/// appbox code consumes:
///
///   {"status":"paid"|"free"|"none","tier":...,"expires":...}
///
/// where paid = valid|grace (expired past grace, tampered/invalid, and
/// unreadable files all report free; a missing file reports none).
/// Exit code: 0 when the licence unlocks (valid/grace), 1 otherwise
/// (invalid/none/expired).
///
/// Licence path resolution for `status`:
///   1. `--licence <path>` when given;
///   2. `~/.appbox/licence.json` (HOME, or USERPROFILE on Windows);
///   3. `config/licence.json` under the repo root (found by walking
///      up from the cwd until config/appbox.config.json appears, same rule as
///      bin/appboxd.dart).
/// The first path that exists wins; if none exists the status is `none`.
///
/// `verify <file>` is the diagnostic form: prints the raw verdict
/// (valid|expired|grace|invalid|none plus email/updates_until) for the
/// given file only. Same exit-code rule.
library;

import 'dart:convert';
import 'dart:io';

import 'package:appboxd/licence.dart';

void main(List<String> args) {
  if (args.isEmpty) _usage();
  switch (args.first) {
    case 'status':
      _status(args.sublist(1));
    case 'verify':
      if (args.length != 2) _usage();
      _verify(args[1]);
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln(
      'usage: licence_tool status [--licence <path>] | licence_tool verify <file>');
  exit(64);
}

void _status(List<String> args) {
  String? explicit;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--licence' && i + 1 < args.length) {
      explicit = args[i + 1];
      i++;
    } else {
      _usage();
    }
  }

  final path = explicit ?? _defaultLicencePath();
  final verdict =
      path == null ? null : Licence.verifyFile(path);
  if (verdict == null || verdict.status == LicenceStatus.none) {
    _print({'status': 'none', 'tier': null, 'expires': null});
    exit(1);
  }
  _print({
    'status': verdict.unlocks ? 'paid' : 'free',
    'tier': verdict.tier,
    'expires': verdict.expires?.toIso8601String(),
  });
  exit(verdict.unlocks ? 0 : 1);
}

void _verify(String path) {
  final verdict = Licence.verifyFile(path);
  _print({
    'status': verdict.status.name,
    'tier': verdict.tier,
    'email': verdict.email,
    'expires': verdict.expires?.toIso8601String(),
    'updates_until': verdict.updatesUntil?.toIso8601String(),
    'file': path,
  });
  exit(verdict.unlocks ? 0 : 1);
}

/// First existing candidate, or null when no licence file is present.
/// Candidates exist-check in order; a path that does not exist falls
/// through to the next.
String? _defaultLicencePath() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'];
  if (home != null) {
    final userPath = '$home/.appbox/licence.json';
    if (File(userPath).existsSync()) return userPath;
  }
  var root = Directory.current.path;
  while (!File('$root/config/appbox.config.json').existsSync()) {
    final parent = Directory(root).parent.path;
    if (parent == root) return null; // outside a repo: no fallback path
    root = parent;
  }
  final repoPath = '$root/config/licence.json';
  return File(repoPath).existsSync() ? repoPath : null;
}

void _print(Map<String, Object?> json) => stdout.writeln(jsonEncode(json));
