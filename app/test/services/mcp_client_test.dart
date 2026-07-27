import 'package:flutter_test/flutter_test.dart';
import 'package:app_box/services/mcp/mcp_client.dart';
import 'package:app_box/services/mcp/mcp_transport.dart';

/// 8.9 / done-when #5 — the chat surface is an MCP client over BOTH transports
/// (stdio + Streamable HTTP+SSE). They share the JSON-RPC 2.0 contract, so a
/// scripted transport proves the handshake + tools/list works for the shape
/// every real transport speaks. No live MCP server needed.
class _ScriptedTransport implements McpTransport {
  _ScriptedTransport(this.id, this._responder);
  @override
  final String id;
  final Map<String, dynamic> Function(String method) _responder;
  bool connected = false;
  final requests = <String>[];

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<Map<String, dynamic>> request(String method,
      {Map<String, dynamic>? params}) async {
    requests.add(method);
    return _responder(method);
  }

  @override
  Future<void> close() async => connected = false;
}

void main() {
  group('McpClient — JSON-RPC handshake over any transport', () {
    test('initialize handshake + tools/list yields the combined tool set', () async {
      final transport = _ScriptedTransport('local', (method) {
        switch (method) {
          case 'initialize':
            return {'result': {'protocolVersion': '2024-11-05'}};
          case 'tools/list':
            return {
              'result': {
                'tools': [
                  {'name': 'scaffold', 'description': 'scaffold a view'},
                  {'name': 'gate_status', 'description': 'read a gate'},
                ]
              }
            };
          default:
            return {'result': {}};
        }
      });
      final client = McpClient(transport);

      await client.connect();
      final tools = await client.listTools();

      expect(transport.requests, containsAll(['initialize', 'tools/list']));
      expect(tools.length, 2);
      expect(tools.map((t) => t.name), containsAll(['scaffold', 'gate_status']));
      // Each tool carries the owning server id — the registry routes by this.
      expect(tools.every((t) => t.serverId == 'local'), isTrue);
    });

    test('a transport exposing no tools resolves to an empty set, not an error',
        () async {
      final transport = _ScriptedTransport('remote', (method) =>
          method == 'tools/list' ? {'result': {'tools': []}} : {'result': {}});
      final client = McpClient(transport);
      await client.connect();
      expect(await client.listTools(), isEmpty);
    });
  });
}
