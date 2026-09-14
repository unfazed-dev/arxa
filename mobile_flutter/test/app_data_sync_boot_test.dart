// B2 phase-1b: the boot decision — sync mode when pairing + tunnel +
// engine bootstrap come up in time, localOnly otherwise. Pure fake
// transport + a real loopback HttpServer (the bootstrap route is the only
// network in the suite).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_cairn/arxa_kit_cairn.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/app/app_data.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

void main() {
  group('AppData.resolveSyncConfig', () {
    setUp(() => AppData.syncBootWait = const Duration(milliseconds: 250));
    tearDown(() => AppData.syncBootWait = const Duration(seconds: 18));

    test('no stored pairing: null without touching the network', () async {
      final transport = FakeTransportService()..storedPairing = false;
      final sw = Stopwatch()..start();
      final result = await AppData.resolveSyncConfig(transport);
      sw.stop();
      expect(result, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test(
      'connected + bootstrap answers: sync config through the proxy path',
      () async {
        final server = await _spawnBootstrap(
          status: 200,
          body: {'token': 'tok-9'},
        );
        addTearDown(server.close);
        final transport = FakeTransportService(port: server.port)
          ..storedPairing = true;
        final future = AppData.resolveSyncConfig(transport);
        unawaited(transport.resume()); // the boot resume brings the link up
        final record = await future;
        expect(record, isNotNull);
        expect(record!.config.mode, ArxaKitCairnMode.sync);
        expect(
          record.config.syncUrl,
          'ws://127.0.0.1:${server.port}/__cairn/sync',
        );
        expect(
          record.config.push,
          isFalse,
          reason: 'no notifications seam here',
        );
        expect(await record.token(), 'tok-9');
      },
    );

    test('current status already connected wins without waiting', () async {
      final server = await _spawnBootstrap(
        status: 200,
        body: {'token': 'tok-7'},
      );
      addTearDown(server.close);
      final transport = FakeTransportService(port: server.port)
        ..storedPairing = true;
      await transport.resume(); // emits connecting -> connected
      final sw = Stopwatch()..start();
      final record = await AppData.resolveSyncConfig(transport);
      sw.stop();
      expect(record, isNotNull);
      expect(await record!.token(), 'tok-7');
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('bootstrap 404 (engine not configured): localOnly', () async {
      final server = await _spawnBootstrap(status: 404, body: {'error': 'x'});
      addTearDown(server.close);
      final transport = FakeTransportService(port: server.port)
        ..storedPairing = true;
      final future = AppData.resolveSyncConfig(transport);
      unawaited(transport.resume());
      expect(await future, isNull);
    });

    test('tunnel never comes up: null after the bounded wait', () async {
      final transport = FakeTransportService()..storedPairing = true;
      final sw = Stopwatch()..start();
      final record = await AppData.resolveSyncConfig(transport);
      sw.stop();
      expect(record, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}

Future<HttpServer> _spawnBootstrap({
  required int status,
  required Map<String, Object?> body,
}) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    if (request.uri.path == '/__arxa/cairn-sync') {
      request.response.statusCode = status;
      request.response.write(jsonEncode(body));
      await request.response.close();
      return;
    }
    request.response.statusCode = 404;
    await request.response.close();
  });
  return server;
}
