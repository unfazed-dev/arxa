// Flutter VM service client — raw dart:io WebSocket JSON-RPC.
//
// Fakes the VM service with a loopback HttpServer upgraded to WebSocket,
// so no real Flutter app is required. Mirrors the pattern the plan
// describes for probe-runner's _flutter/* block.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arxa/lens/native/flutter_vm.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// A fake VM service: a loopback HttpServer that upgrades to WebSocket
/// and answers JSON-RPC requests from the FlutterVm client.
class FakeVmService {
  HttpServer? _server;
  WebSocket? _socket;
  String? lastUpgradeUri;
  final List<Map<String, dynamic>> received = [];

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      lastUpgradeUri = request.uri.toString();
      _socket = await WebSocketTransformer.upgrade(request);
      _socket!.listen((data) {
        final req = jsonDecode(data as String) as Map<String, dynamic>;
        received.add(req);
        final res = _respond(req);
        if (res != null) _socket!.add(jsonEncode(res));
      });
    });
    return 'http://${_server!.address.address}:${_server!.port}/token=/';
  }

  /// Push an unsolicited event (no id) to the connected client.
  void pushEvent(Map<String, dynamic> event) =>
      _socket?.add(jsonEncode(event));

  Map<String, dynamic>? _respond(Map<String, dynamic> req) {
    final id = req['id'];
    final method = req['method'] as String?;
    switch (method) {
      case 'getVM':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'isolates': [
              {'id': 'isolates/1'},
            ],
          },
        };
      case 'ext.flutter.screenshot':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'screenshot': pngB64},
        };
      case 'ext.flutter.debugDumpRenderTree':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'value': 'RenderView#00000\n └─RenderSemanticsGestureHandler'},
        };
      case 'getIsolate':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {
            'id': 'isolates/1',
            'rootLib': {'id': 'libraries/1', 'name': 'package:app/main.dart'},
            'libraries': [
              {'id': 'libraries/1', 'name': 'package:app/main.dart'},
            ],
          },
        };
      case 'evaluate':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'valueAsString': '42'},
        };
      case 'ext.flutter.bogusError':
        return {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': -32601, 'message': 'no such extension'},
        };
      case null:
        return null; // unsolicited inbound message — ignore
      default:
        final params = req['params'];
        return {
          'jsonrpc': '2.0',
          'id': id,
          'result': {'ok': true, 'echo': ?params},
        };
    }
  }

  Future<void> close() async {
    await _socket?.close();
    await _server?.close();
  }
}

// 1x1 red PNG — what ext.flutter.screenshot returns, base64-encoded.
final Uint8List pngBytes =
    img.encodePng(img.Image(width: 1, height: 1)..setPixelRgb(0, 0, 255, 0, 0));
final String pngB64 = base64Encode(pngBytes);

void main() {
  group('parseVmServiceUri', () {
    test('interactive "Dart VM service is listening" form', () {
      final uri = parseVmServiceUri(
        'Observatory listening on...\n'
        'The Dart VM service is listening on http://127.0.0.1:50123/abc=/',
      );
      expect(uri, 'http://127.0.0.1:50123/abc=/');
    });

    test('flutter run --machine JSON app.debugPort form', () {
      final uri = parseVmServiceUri(
        '{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:50123/abc=/ws"}}',
      );
      expect(uri, 'ws://127.0.0.1:50123/abc=/ws');
    });

    test('garbage returns null', () {
      expect(parseVmServiceUri('just some tool output, no uri'), isNull);
    });
  });

  group('FlutterVm', () {
    late FakeVmService fake;
    late FlutterVm vm;

    setUp(() async {
      fake = FakeVmService();
      final base = await fake.start();
      vm = await FlutterVm.connect(base);
    });

    tearDown(() async {
      await vm.dispose();
      await fake.close();
    });

    test('connect upgrades http→ws and appends /ws', () {
      // The fake captured the upgrade request URI; the client must have
      // turned http://…/token=/ into ws://…/token=/ws.
      expect(fake.lastUpgradeUri, endsWith('/ws'));
      expect(fake.lastUpgradeUri, contains('token='));
    });

    test('mainIsolateId returns isolates/1', () async {
      expect(await vm.mainIsolateId(), 'isolates/1');
    });

    test('screenshot() decodes the base64 PNG', () async {
      final bytes = await vm.screenshot();
      expect(bytes, equals(pngBytes));
      // PNG magic intact.
      expect(bytes[0], 0x89);
      expect(bytes[1], 0x50); // P
    });

    test('callServiceExtension passes the isolateId', () async {
      await vm.callServiceExtension('ext.flutter.custom',
          isolateId: 'isolates/42');
      final req = fake.received.lastWhere(
        (r) => r['method'] == 'ext.flutter.custom',
      );
      expect(req['params']['isolateId'], 'isolates/42');
    });

    test('dumpRenderTree returns the canned value', () async {
      expect(await vm.dumpRenderTree(), contains('RenderView'));
    });

    test('evalDart evaluates in the root library', () async {
      expect(await vm.evalDart('1 + 41'), '42');
    });

    test('JSON-RPC error throws LensVmException with the message', () {
      expect(
        vm.rpc('ext.flutter.bogusError'),
        throwsA(isA<LensVmException>()
            .having((e) => e.message, 'message', contains('no such extension'))),
      );
    });

    test('unsolicited streamNotify events land on the events stream',
        () async {
      final first = vm.events.first;
      fake.pushEvent({
        'jsonrpc': '2.0',
        'method': 'streamNotify',
        'params': {'streamId': 'Extension', 'event': {'kind': 'Extension'}},
      });
      final ev = await first.timeout(const Duration(seconds: 2));
      expect(ev['method'], 'streamNotify');
      expect(ev['params']['streamId'], 'Extension');
    });
  });
}
