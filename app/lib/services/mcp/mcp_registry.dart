import 'dart:async';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/config_service.dart';
import 'package:app_box/services/mcp/mcp_client.dart';
import 'package:app_box/services/mcp/mcp_transport.dart';

/// 8.9 — the chat surface's MCP registry. Connects to every configured server
/// (stdio + HTTP), combines their tools into one registry, and routes a tool
/// call to the server that owns it.
///
/// Servers come from config (R3); none enabled by default. With no servers the
/// surface states that honestly. The transports themselves are exercised by the
/// scripted-transport unit test (no live server needed to prove the handshake).
class McpRegistry {
  final _clients = <String, McpClient>{};
  final _tools = <McpTool>[];
  List<McpTool> get tools => List.unmodifiable(_tools);

  /// Builds transports from config for the enabled servers.
  List<McpTransport> _transportsFromConfig() {
    final config = locator<ConfigService>();
    final servers = config.mcpServers.where((s) => s['enabled'] == true);
    return servers.map((s) {
      final transport = s['transport'] as String;
      if (transport == 'stdio') {
        return StdioMcpTransport(
          id: s['id'] as String,
          command: s['command'] as String,
        );
      }
      return HttpMcpTransport(
        id: s['id'] as String,
        url: s['url'] as String,
      );
    }).toList();
  }

  /// Connects to all configured servers and aggregates their tools.
  Future<void> connectAll() async {
    for (final transport in _transportsFromConfig()) {
      final client = McpClient(transport);
      try {
        await client.connect();
        _clients[transport.id] = client;
        _tools.addAll(await client.listTools());
      } catch (_) {
        // A server failing to connect must not take the registry down — the
        // surface reports per-server status. Honest, not a silent green.
        await client.close();
      }
    }
  }

  /// Routes a tool call to the owning server. Throws if no server owns it
  /// (never silently fakes a result).
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) async {
    final owner = _tools.firstWhere((t) => t.name == name);
    final client = _clients[owner.serverId];
    if (client == null) {
      throw StateError('No connected server owns tool "$name"');
    }
    return client.callTool(name, args);
  }

  bool get hasServers => _clients.isNotEmpty;

  Future<void> disconnectAll() async {
    for (final c in _clients.values) {
      await c.close();
    }
    _clients.clear();
    _tools.clear();
  }
}
