/// Post-emit provenance/watermark pass — pure-Dart port of the archived
/// tools/watermark/watermark.mjs.
///
/// Walks an emitted tree and prepends a provenance block (`appbox:provenance`
/// marker) to every `.dart/.js/.mjs/.ts/.yaml/.yml/.sh/.html` file. Free tier
/// carries a watermark line inside the block; paid tier emits a clean
/// provenance header. `.json` has no comment syntax — its provenance is a
/// sibling entry in the manifest instead. Writes `.appbox-provenance.json`
/// (a sha256 manifest of every touched file, post-injection).
///
/// The block is EVIDENCE, not a lock — stripping it is handled by licence
/// terms, not crypto (Unity Personal splash precedent). Emitted source is
/// never encrypted. Idempotent via the [marker] token.
///
/// Licence status comes from `licence.dart` (LicenceVerdict.unlocks). Only
/// `paid` (valid/grace) is clean; `none`/invalid/expired all watermark like
/// `free`, never blocking emission.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'crypto_aead.dart';
import 'licence.dart';

/// The idempotency token every provenance block carries.
const marker = 'appbox:provenance';

/// Watermark line emitted inside the block on the free tier.
const watermarkLine = 'Built with appbox (free tier) — https://appbox.dev';

/// Name of the sha256 manifest written at the tree root.
const manifestName = '.appbox-provenance.json';

/// Comment syntax per extension. `.html` is special (HTML comment); `.json`
/// is deliberately absent — no comment syntax.
const commentSyntax = <String, String>{
  '.dart': '//',
  '.js': '//',
  '.mjs': '//',
  '.ts': '//',
  '.yaml': '#',
  '.yml': '#',
  '.sh': '#',
  '.html': 'html',
};

final _doctype = RegExp(r'^\s*<!doctype[^>]*>', caseSensitive: false);

/// Renders the provenance block for [ext] (lowercased, with leading dot).
String renderBlock(String ext, {required String tier, required String projectHash}) {
  final lines = <String>[
    marker,
    'generator: appbox  licence: $tier  project: $projectHash',
  ];
  if (tier == 'free') lines.add(watermarkLine);
  if (ext == '.html') {
    // <!-- appbox:provenance
    //      generator: ...
    //      Built with appbox (free tier) — ... -->
    final body = lines.skip(1).map((l) => '     $l').join('\n');
    return '<!-- ${lines.first}\n$body\n-->\n';
  }
  final c = commentSyntax[ext]!;
  return '${lines.map((l) => '$c $l').join('\n')}\n';
}

/// Prepends a provenance header to [filePath]. Returns one of:
/// `injected` | `already` | `json-skip` | `unsupported`.
String injectProvenance(String filePath,
    {required String tier, required String projectHash}) {
  final ext = p.extension(filePath).toLowerCase();
  if (ext == '.json') return 'json-skip';
  if (!commentSyntax.containsKey(ext)) return 'unsupported';

  final src = File(filePath).readAsStringSync();
  if (src.contains(marker)) return 'already';

  final block = renderBlock(ext, tier: tier, projectHash: projectHash);
  String out;
  if (src.startsWith('#!')) {
    // Shebang must stay line 1.
    final nl = src.indexOf('\n');
    out = src.substring(0, nl + 1) + block + src.substring(nl + 1);
  } else if (ext == '.html' && _doctype.hasMatch(src)) {
    // A comment before <!DOCTYPE> triggers quirks mode — inject after it.
    out = src.replaceFirstMapped(_doctype, (m) => '${m[0]}$block');
  } else {
    out = block + src;
  }
  File(filePath).writeAsStringSync(out);
  return 'injected';
}

/// Walks [rootDir], injects provenance into every supported file, and writes
/// `.appbox-provenance.json` (`{tier, ts, files:[{path, sha256, note?}]}`).
///
/// [tier] overrides licence detection (`'paid'`/`'free'`); when null it
/// resolves from `licence.dart` (valid/grace → paid, else free). [licencePath]
/// overrides the licence file location. Returns the manifest map.
Map<String, Object?> runPass(String rootDir,
    {String? tier, String? licencePath, String? projectHash}) {
  final resolvedTier = tier ?? _resolveTier(licencePath);
  final hash = projectHash ??
      hexEncode(sha256(Uint8List.fromList(utf8.encode(p.canonicalize(rootDir)))))
          .substring(0, 12);

  final files = <Map<String, Object?>>[];
  final entries = Directory(rootDir).listSync(recursive: true).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in entries) {
    if (entity is! File) continue;
    final segments = p.split(entity.path);
    if (segments.any((s) => s == 'node_modules' || s == '.git')) continue;
    if (p.basename(entity.path) == manifestName) continue;

    final ext = p.extension(entity.path).toLowerCase();
    if (!commentSyntax.containsKey(ext) && ext != '.json') continue;

    final result =
        injectProvenance(entity.path, tier: resolvedTier, projectHash: hash);
    final entry = <String, Object?>{
      'path': p.relative(entity.path, from: rootDir),
      'sha256': hexEncode(sha256(entity.readAsBytesSync())),
    };
    if (result == 'json-skip') {
      entry['note'] =
          'json: no comment syntax — provenance is this manifest entry';
    }
    files.add(entry);
  }

  final manifest = <String, Object?>{
    'tier': resolvedTier,
    'ts': DateTime.now().toUtc().toIso8601String(),
    'files': files,
  };
  File(p.join(rootDir, manifestName))
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
  return manifest;
}

/// Mirrors licence_tool's path resolution: `~/.appbox/licence.json` then a
/// walk-up for `<repo>/pipeline/state/licence.json`. Empty string = absent.
String _defaultLicencePath() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home != null) {
    final userPath = p.join(home, '.appbox', 'licence.json');
    if (File(userPath).existsSync()) return userPath;
  }
  var root = Directory.current.path;
  while (!File(p.join(root, 'pipeline', 'pipeline.sh')).existsSync()) {
    final parent = Directory(root).parent.path;
    if (parent == root) return '';
    root = parent;
  }
  final repoPath = p.join(root, 'pipeline', 'state', 'licence.json');
  return File(repoPath).existsSync() ? repoPath : '';
}

/// Only a valid/grace licence is `paid`; everything else watermarks as `free`.
String _resolveTier(String? licencePath) {
  final path = licencePath ?? _defaultLicencePath();
  if (path.isEmpty) return 'free';
  return Licence.verifyFile(path).unlocks ? 'paid' : 'free';
}
