// Rewrite the committed vendor manifest.json + SRI.md from the current
// `vendorPatches` registry, WITHOUT re-downloading anything.
//
// Why this exists: `vendorSriDoc` renders SRI.md from the registry, and a test
// asserts the committed file is byte-identical to that render. So editing a
// patch's `why` — or adding a patch — breaks the build until the doc is
// regenerated. The only other way to regenerate is a full `arxa design
// vendor-fetch`, which hits the network, needs esbuild, and re-downloads 25
// libraries to fix a paragraph. This does the same rewrite offline.
//
// It does NOT re-download, so it cannot discover a new upstream hash: the
// pristine hash is carried forward from the existing row. Use vendor-fetch for
// a genuine version bump; use this after editing the registry's prose.
//
// Run: cd arxa && dart run tool/regen_vendor_docs.dart
import 'dart:convert';
import 'dart:io';

import 'package:arxa/design_tools.dart';

const _vendor = '../skills/arxa-designer/runtime/vendor';

Future<void> main() async {
  final rows = (jsonDecode(File('$_vendor/manifest.json').readAsStringSync())
          as List)
      .map((e) => (e as Map).cast<String, String>())
      .toList();

  final patched = vendorPatches.map((p) => p.file).toSet();
  final out = <Map<String, String>>[];
  for (final row in rows) {
    if (!patched.contains(row['file'])) {
      if (row['upstreamIntegrity'] != null) {
        // The row claims a divergence the registry no longer owns — a patch
        // was removed. That is only coherent if the file was actually
        // reverted: require the on-disk bytes to hash to the recorded
        // upstream, then drop the stale divergence record.
        final onDisk =
            await sri(File('$_vendor/${row['file']}').readAsBytesSync());
        if (onDisk != row['upstreamIntegrity']) {
          stderr.writeln('!! ${row['file']}: its patch left the registry but '
              'the on-disk bytes still diverge from the recorded upstream '
              '($onDisk vs ${row['upstreamIntegrity']}). Either revert the '
              'file or restore the registry entry — regenerating now would '
              'erase the only record that this file is not the release.');
          exit(1);
        }
        out.add(manifestEntry(
            file: row['file']!,
            pkg: row['package']!,
            version: row['version']!,
            integrity: onDisk,
            category: row['category']!));
        stdout.writeln('${row['file']}: patch removed, on-disk verified '
            'pristine ($onDisk)');
        continue;
      }
      out.add(row);
      continue;
    }
    final onDisk = await sri(File('$_vendor/${row['file']}').readAsBytesSync());
    // Carried forward, never recomputed: after the patch is applied the
    // pristine bytes are gone from disk, so the only record of the upstream
    // hash is the one the last real fetch wrote.
    final upstream = row['upstreamIntegrity'] ?? row['integrity']!;
    if (onDisk == upstream) {
      stderr.writeln('!! ${row['file']}: the on-disk hash equals the upstream '
          'hash, so the local patch is NOT applied to the committed file. '
          'Re-apply it (arxa design vendor-fetch) before regenerating — '
          'writing the docs now would record the divergence as resolved when '
          'it is actually lost.');
      exit(1);
    }
    out.add(manifestEntry(
        file: row['file']!,
        pkg: row['package']!,
        version: row['version']!,
        integrity: onDisk,
        upstreamIntegrity: upstream,
        category: row['category']!));
    stdout.writeln('${row['file']}: patched=$onDisk upstream=$upstream');
  }

  File('$_vendor/manifest.json')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  File('$_vendor/SRI.md').writeAsStringSync(vendorSriDoc(out));
  stdout.writeln('rewrote manifest.json + SRI.md (${out.length} rows)');
}
