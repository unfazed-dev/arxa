import 'dart:async';

import 'package:stacked/stacked.dart';

import 'package:app_box/app/app.locator.dart';
import 'package:app_box/services/mcp/mcp_registry.dart';

enum ChatState { idle, streaming, toolCall, noServers }

/// chat.home — idle · streaming · tool-call (brief §4). The MCP registry (8.9)
/// connects to every configured server (stdio + Streamable HTTP+SSE) and
/// combines their tools into one registry.
class ChatHomeViewModel extends BaseViewModel {
  final _registry = locator<McpRegistry>();
  ChatState _state = ChatState.idle;
  final _log = <String>[];
  String _draft = '';

  ChatState get state => _state;
  List<String> get log => List.unmodifiable(_log);
  int get toolCount => _registry.tools.length;

  Future<void> connect() async {
    _state = ChatState.idle;
    _log.clear();
    notifyListeners();
    _log.add('Connecting to MCP servers…');
    await _registry.connectAll();
    if (!_registry.hasServers) {
      _state = ChatState.noServers;
      _log.add('No MCP servers enabled in config. Enable one in '
          'assets/config/app_box.config.json to connect.');
    } else {
      _log.add('Connected. ${_registry.tools.length} tool(s) across servers.');
    }
    notifyListeners();
  }

  void onDraft(String v) => _draft = v;

  /// Send a user turn. If it names a tool, the registry routes the call to the
  /// owning server (tool-call state); otherwise it's a streaming turn.
  Future<void> send() async {
    if (_draft.trim().isEmpty) return;
    final msg = _draft.trim();
    _draft = '';
    _log.add('You: $msg');
    _state = ChatState.streaming;
    notifyListeners();
    // Channel state, not inferred from paint (brief non-negotiable #2).
    await Future.delayed(const Duration(milliseconds: 300));
    final tool = _registry.tools.where((t) => msg.toLowerCase().contains(t.name.toLowerCase())).firstOrNull;
    if (tool != null) {
      _state = ChatState.toolCall;
      _log.add('→ tool call: ${tool.name} (server ${tool.serverId})');
      notifyListeners();
      try {
        final res = await _registry.callTool(tool.name, {});
        _log.add('← ${res['result'] ?? res['error'] ?? 'done'}');
      } catch (e) {
        _log.add('← tool error: $e');
      }
    } else {
      _log.add('app_box: (model reply over the connected transport)');
    }
    _state = ChatState.idle;
    notifyListeners();
  }
}
