// genui 0.10.1 spike: local mock A2UI stream, basic + custom catalog items.
// No Firebase, no cloud LLM. The "server" is `_mockServerSend`, which replays
// canned A2UI JSON, chunked to exercise the incremental parser.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

void main() => runApp(const SpikeApp());

// ---------------------------------------------------------------------------
// Canned "LLM" responses (A2UI v0.9 wire format, verified against
// a2ui_core-0.1.0/lib/src/core/messages.dart).
// ---------------------------------------------------------------------------

/// Response 1: basic catalog items — Text + Card + Button (with action).
const String _cannedBasic = '''
{"version":"v0.9","createSurface":{"surfaceId":"basic-1","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json"}}
{"version":"v0.9","updateComponents":{"surfaceId":"basic-1","components":[{"id":"root","component":"Column","children":["title","card"]},{"id":"title","component":"Text","text":"Pipeline summary (basic catalog)","variant":"h3"},{"id":"card","component":"Card","child":"cardCol"},{"id":"cardCol","component":"Column","children":["cardText","retryBtn"]},{"id":"cardText","component":"Text","text":"3 stages green, 1 flaky. The button below fires an A2UI action back to the transport."},{"id":"retryBtn","component":"Button","child":"retryLabel","variant":"primary","action":{"event":{"name":"retry_stage","context":{"stage":"freeze"}}}},{"id":"retryLabel","component":"Text","text":"Retry stage: freeze"}]}}
''';

/// Response 2: custom catalog item (BuildStageCard), data-bound via DataModel.
const String _cannedStage = '''
{"version":"v0.9","createSurface":{"surfaceId":"stage-1","catalogId":"https://a2ui.org/specification/v0_9/basic_catalog.json"}}
{"version":"v0.9","updateDataModel":{"surfaceId":"stage-1","path":"/stage","value":{"name":"freeze","status":"running","progress":0.6}}}
{"version":"v0.9","updateComponents":{"surfaceId":"stage-1","components":[{"id":"root","component":"Column","children":["head","stage"]},{"id":"head","component":"Text","text":"Custom catalog item, bound to the DataModel:","variant":"caption"},{"id":"stage","component":"BuildStageCard","name":{"path":"/stage/name"},"status":{"path":"/stage/status"},"progress":{"path":"/stage/progress"}}]}}
''';

// ---------------------------------------------------------------------------
// Custom catalog item: BuildStageCard.
// ---------------------------------------------------------------------------

final CatalogItem buildStageCardItem = CatalogItem(
  name: 'BuildStageCard',
  dataSchema: S.object(
    description:
        'A card showing one build-pipeline stage: name, status, progress.',
    properties: {
      'name': A2uiSchemas.stringReference(description: 'Stage name.'),
      'status': A2uiSchemas.stringReference(
        description: "One of 'pending', 'running', 'done', 'failed'.",
      ),
      'progress': A2uiSchemas.numberReference(
        description: 'Progress from 0.0 to 1.0.',
      ),
    },
    required: ['name', 'status', 'progress'],
  ),
  widgetBuilder: (itemContext) {
    final data = itemContext.data as JsonMap;
    return BuildStageCardView(
      name: itemContext.dataContext.resolve(data['name']),
      status: itemContext.dataContext.resolve(data['status']),
      progress: itemContext.dataContext.resolve(data['progress']),
      onMarkDone: () {
        // Local DataModel round-trip: write back through the DataContext and
        // let the bound streams re-render the card.
        itemContext.dataContext.update(DataPath('/stage/status'), 'done');
        itemContext.dataContext.update(DataPath('/stage/progress'), 1.0);
      },
    );
  },
);

/// Visible widget for the custom catalog item. Plain Containers, no packages.
class BuildStageCardView extends StatelessWidget {
  const BuildStageCardView({
    super.key,
    required this.name,
    required this.status,
    required this.progress,
    required this.onMarkDone,
  });

  final Stream<Object?> name;
  final Stream<Object?> status;
  final Stream<Object?> progress;
  final VoidCallback onMarkDone;

  static const Map<String, Color> _statusColors = {
    'pending': Colors.grey,
    'running': Colors.orange,
    'done': Colors.green,
    'failed': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    return _Bound(name, (nameVal) {
      return _Bound(status, (statusVal) {
        return _Bound(progress, (progressVal) {
          final stageName = nameVal?.toString() ?? '…';
          final stageStatus = statusVal?.toString() ?? 'pending';
          final p = progressVal is num
              ? progressVal.toDouble()
              : double.tryParse('${progressVal ?? 0}') ?? 0.0;
          final color = _statusColors[stageStatus] ?? Colors.blueGrey;
          return Container(
            key: const Key('build-stage-card'),
            width: 320,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stageName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      key: const Key('stage-status-chip'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        stageStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 240,
                  height: 8,
                  color: Colors.black12,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    key: const Key('stage-progress-bar'),
                    widthFactor: p.clamp(0.0, 1.0),
                    child: Container(color: color),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('mark-done-button'),
                  onPressed: stageStatus == 'done' ? null : onMarkDone,
                  child: const Text('Mark done (DataModel write)'),
                ),
              ],
            ),
          );
        });
      });
    });
  }
}

class _Bound extends StatelessWidget {
  const _Bound(this.stream, this.builder);

  final Stream<Object?> stream;
  final Widget Function(Object? value) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: stream,
    builder: (context, snapshot) => builder(snapshot.data),
  );
}

// ---------------------------------------------------------------------------
// App.
// ---------------------------------------------------------------------------

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'genui spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SpikeHome(),
    );
  }
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => SpikeHomeState();
}

class SpikeHomeState extends State<SpikeHome> {
  /// Chunk size for the canned-stream replay — small on purpose to prove the
  /// incremental parser assembles split JSON.
  static const int chunkSize = 18;
  static const Duration chunkDelay = Duration(milliseconds: 10);

  late final Catalog _catalog;
  late final A2uiTransportAdapter _transport;
  late final SurfaceController _controller;
  late final Conversation _conversation;
  late final StreamSubscription<ConversationEvent> _eventSub;

  final TextEditingController _input = TextEditingController();
  final List<String> _log = [];

  /// Set via `--dart-define=SPIKE_AUTOSEND="show stage"` to auto-send one
  /// message shortly after launch (used for unattended screenshots).
  static const String autoSend = String.fromEnvironment('SPIKE_AUTOSEND');

  @override
  void initState() {
    super.initState();
    _catalog = BasicCatalogItems.asCatalog().copyWith(
      newItems: [buildStageCardItem],
    );
    _transport = A2uiTransportAdapter(onSend: _mockServerSend);
    _controller = SurfaceController(catalogs: [_catalog]);
    _conversation = Conversation(
      controller: _controller,
      transport: _transport,
    );
    _eventSub = _conversation.events.listen((event) {
      switch (event) {
        case ConversationSurfaceAdded(:final surfaceId):
          _appendLog('surface added: $surfaceId');
        case ConversationSurfaceRemoved(:final surfaceId):
          _appendLog('surface removed: $surfaceId');
        case ConversationContentReceived(:final text):
          _appendLog('llm text: $text');
        case ConversationError(:final error):
          _appendLog('ERROR: $error');
        default:
          break;
      }
    });
    if (autoSend.isNotEmpty) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          unawaited(_conversation.sendRequest(ChatMessage.user(autoSend)));
        }
      });
    }
  }

  @override
  void dispose() {
    _eventSub.cancel();
    _conversation.dispose();
    _controller.dispose();
    _transport.dispose();
    _input.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    if (autoSend.isNotEmpty && line.startsWith('surface added:')) {
      // Screenshot mode: once the surface is up, exercise its interactions
      // through the same public APIs the widgets use.
      final surfaceId = line.substring('surface added:'.length).trim();
      Future<void>.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        if (surfaceId == 'stage-1') {
          _controller.contextFor('stage-1').dataModel
            ..update(DataPath('/stage/status'), 'done')
            ..update(DataPath('/stage/progress'), 1.0);
        } else {
          _controller.handleUiEvent(
            UserActionEvent(
              name: 'retry_stage',
              sourceComponentId: 'retryBtn',
              context: const {'stage': 'freeze'},
            ),
          );
        }
      });
    }
  }

  /// The "mock server": genui's `onSend` seam. Replays a canned A2UI
  /// response, chunked; logs action round-trips instead of answering them.
  Future<void> _mockServerSend(ChatMessage message) async {
    final interactions = message.parts.uiInteractionParts.toList();
    if (interactions.isNotEmpty) {
      for (final part in interactions) {
        final decoded = jsonDecode(part.interaction) as Map<String, Object?>;
        final payload = decoded['action'] ?? decoded['error'] ?? decoded;
        _appendLog('ACTION round-trip received by transport: $payload');
      }
      return;
    }
    final userText = message.text;
    _appendLog('sent → mock server: "$userText"');
    final canned = userText.contains('stage') ? _cannedStage : _cannedBasic;
    for (var i = 0; i < canned.length; i += chunkSize) {
      await Future<void>.delayed(chunkDelay);
      _transport.addChunk(
        canned.substring(i, math.min(i + chunkSize, canned.length)),
      );
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    unawaited(_conversation.sendRequest(ChatMessage.user(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('genui 0.10.1 spike — mock A2UI')),
      body: ValueListenableBuilder<ConversationState>(
        valueListenable: _conversation.state,
        builder: (context, state, _) {
          return Column(
            children: [
              if (state.isWaiting) const LinearProgressIndicator(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final surfaceId in state.surfaces)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Surface(
                          surfaceContext: _controller.contextFor(surfaceId),
                        ),
                      ),
                    const Divider(),
                    const Text(
                      'event log',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final line in _log)
                      Text(line, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('chat-input'),
                        controller: _input,
                        decoration: const InputDecoration(
                          hintText:
                              'type anything → basic UI · "stage" → custom card',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('send-button'),
                      onPressed: _send,
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
