// THROWAWAY 5c probe v2 — can the REAL Rust engine load in a plain VM
// `flutter test` via FRB's ExternalLibrary seam, pointed at the hook-built
// dylib? Delete after the question is answered.
//
// Stack is expected DOWN: a connection error means the engine is live and
// dialed; a dylib/init failure means the VM placement is dead.
import 'dart:io';

import 'package:cairn_flutter/cairn_flutter.dart';
import 'package:cairn_flutter/src/rust/frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';

const _schema = CairnSchema(tables: [
  CairnTable(
    name: 'probe',
    primaryKey: ['id'],
    columns: [CairnColumn.text('id')],
  ),
]);

void main() {
  test('probe: real engine loads via ExternalLibrary in a VM test', () async {
    const dylib = 'build/native_assets/macos/libcairn_flutter_rust.dylib';
    expect(File(dylib).existsSync(), isTrue, reason: 'hook-built dylib missing');
    await RustLib.init(externalLibrary: ExternalLibrary.open(dylib));

    final tmp = await Directory.systemTemp.createTemp('cairn_probe_');
    try {
      // First connect: engine_selector will call RustLib.init() AGAIN
      // (its own _rustInitialized flag is still false) — this doubles as the
      // double-init tolerance probe.
      await CairnDatabase.connect(
        url: 'ws://127.0.0.1:1/sync', // nothing listens here
        token: 'probe',
        sqlitePath: '${tmp.path}/probe.sqlite',
        schema: _schema,
      ).timeout(const Duration(seconds: 15));
      fail('unreachable — the dead URL must not connect');
    } catch (e) {
      final msg = e.toString();
      expect(msg, isNot(contains('dylib')), reason: msg);
      expect(msg, isNot(contains('Failed to load')), reason: msg);
      expect(msg, isNot(contains('MissingPlugin')), reason: msg);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
