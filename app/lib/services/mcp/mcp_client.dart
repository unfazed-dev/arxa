import 'package:app_box/services/mcp/mcp_transport.dart';

/// A tool advertised by an MCP server, with the [serverId] that owns it so the
/// registry can route a call back to the right server.
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;
  final String serverId;
  const McpTool(this.name, this.serverId, {this.description, this.inputSchema});

  factory McpTool.fromJson(Map<String, dynamic> json, String serverId) {
    return McpTool(
      json['name'] as String,
      serverId,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );
  }
}

/// A single MCP server connection: performs the initialize handshake, then lists
/// the tools it exposes.
class McpClient {
  McpClient(this.transport);
  final McpTransport transport;
  bool _initialized = false;

  Future<void> connect() async {
    if (_initialized) return;
    await transport.connect();
    // MCP initialize handshake (JSON-RPC 2.0).
    await transport.request('initialize', params: {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'app_box', 'version': '0.1.0'},
    });
    await transport.request('notifications/initialized');
    _initialized = true;
  }

  Future<List<McpTool>> listTools() async {
    final res = await transport.request('tools/list');
    final result = res['result'];
    if (result is Map<String, dynamic>) {
      final tools = result['tools'];
      if (tools is List) {
        return tools
            .whereType<Map<String, dynamic>>()
            .map((t) => McpTool.fromJson(t.cast<String, dynamic>(), transport.id))
            .toList();
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> args) {
    return transport.request('tools/call', params: {'name': name, 'arguments': args});
  }

  Future<void> close() => transport.close();
}
