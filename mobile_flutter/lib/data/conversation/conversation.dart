// The conversation domain models — the phone's projection of a dsh code
// session and its transcript (the code_shell data slice; engine routes are
// the locked contract: /__arxa/conversations[...]).
//
// Same pattern as the approvals slice: plain classes, hand-rolled
// fromJson/toJson, snake_case wire keys, and the cairn row shape IS the
// wire shape. No nested collections on the wire, so no jsonb column is
// needed here.

import 'package:arxa_kit_data/arxa_kit_data.dart';

/// One code session as the engine lists it. Any field except [id] may be
/// null on the wire.
class CodeSession {
  const CodeSession({
    required this.id,
    this.name,
    this.title,
    this.state,
    this.parkedReason,
    this.project,
    this.workspace,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.dshSessionId,
    this.org,
    this.running = false,
  });

  final String id;
  final String? name;
  final String? title;
  final String? state;

  /// Non-null when the session is blocked waiting on something (an
  /// approval, a question) — the Blocked filter key.
  final String? parkedReason;
  final String? project;
  final String? workspace;

  /// Epoch milliseconds.
  final int createdAt;

  /// Epoch milliseconds — the list sorts newest-first on this.
  final int updatedAt;

  /// The "arxa-"-prefixed engine session id (e.g. "arxa-s-mtgtrrx8-8mrlsd").
  /// CONTRACT PIN: the transcript/send routes are keyed by THIS, not the
  /// sidebar row [id] — the engine 404s (session-not-found) on the bare id.
  final String? dshSessionId;
  final String? org;

  /// TRANSIENT (not a schema column): the engine's live-turn flag from the
  /// LAST list pull — true while the session runs a turn on the studio. The
  /// cache round-trip drops it on purpose; [ConversationRepository.runningIds]
  /// is the query surface (this field only carries the fresh rows).
  final bool running;

  /// The display line: title, else name, else the raw id.
  String get displayTitle {
    final t = title;
    if (t != null && t.isNotEmpty) return t;
    final n = name;
    if (n != null && n.isNotEmpty) return n;
    return id;
  }

  factory CodeSession.fromJson(Map<String, dynamic> json) => CodeSession(
    id: json['id'] as String,
    name: json['name'] as String?,
    title: json['title'] as String?,
    state: json['state'] as String?,
    parkedReason: json['parkedReason'] as String?,
    project: json['project'] as String?,
    workspace: json['workspace'] as String?,
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    dshSessionId: json['dshSessionId'] as String?,
    org: json['org'] as String?,
    running: json['running'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (title != null) 'title': title,
    if (state != null) 'state': state,
    if (parkedReason != null) 'parkedReason': parkedReason,
    if (project != null) 'project': project,
    if (workspace != null) 'workspace': workspace,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (dshSessionId != null) 'dshSessionId': dshSessionId,
    if (org != null) 'org': org,
  };
}

/// One human command in the engine's registry — the studio composer's
/// `+` palette row, verbatim (name without the slash, one-line
/// description, optional input hint for commands that take arguments).
class EngineCommand {
  const EngineCommand({
    required this.name,
    required this.description,
    this.inputHint,
  });

  final String name;
  final String description;

  /// Present when the command reads a free-text argument
  /// (`/feedback <text>`, `/goal [<objective>|clear|...]`).
  final String? inputHint;

  factory EngineCommand.fromJson(Map<String, dynamic> json) => EngineCommand(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    inputHint: (json['input'] as Map<String, dynamic>?)?['hint'] as String?,
  );
}

/// One live push from the engine's SSE rail
/// (/__arxa/conversations/events). [type] is 'hello' | 'sessions' |
/// 'session'; 'session' pings carry the [sessionId] (the dsh form) and
/// the [reason] (user/message, assistant/message, turn/start, turn/end,
/// session/title, question/*).
class ConversationLiveEvent {
  const ConversationLiveEvent({
    required this.type,
    this.sessionId,
    this.reason,
  });

  final String type;
  final String? sessionId;
  final String? reason;
}

/// One transcript row (engine fold, ascending by [seq]). The assistant
/// surface folds into EXPANDABLE rows — [kind] says which:
///   'text'     — a plain chat bubble (user rows are always this)
///   'thinking' — the model's reasoning; the thread shows a collapsed
///                "Thought process" row, the sheet shows [text]
///   'tool'     — one tool execution; the thread shows "Ran [toolLabel]", the
///                sheet shows [toolInput] + [text] (the paired output)
/// [toolName]/[toolInput]/[toolError] ride tool rows only. The transients
/// are NOT persisted (no schema columns): the wire is the only carrier, and
/// the cache keeps degraded plain rows.
class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.seq,
    required this.sessionId,
    required this.role,
    required this.text,
    this.at = 0,
    this.images = const <String>[],
    this.kind = 'text',
    this.toolName,
    this.toolInput,
    this.toolError = false,
  });

  /// Cache key — synthesized 'sessionId:seq' (the wire has no id; the kit
  /// repository keys rows by one).
  final String id;
  final int seq;
  final String sessionId;

  /// 'user' | 'assistant'
  final String role;
  final String text;

  /// Epoch milliseconds.
  final int at;

  /// Attachment ids of the admitted image blocks (user turns). Fetch the
  /// bytes through the engine's attachment read route to render thumbnails.
  /// Cache-ephemeral on purpose (not a schema column): a refresh re-pulls
  /// them, and the live pull is the only surface that shows them.
  final List<String> images;

  /// The row's surface kind — `text` | `thinking` | `tool` (user rows have
  /// none on the wire and default to `text`).
  final String kind;

  /// Tool rows: the engine tool name (e.g. 'ctx_batch_execute') and its
  /// pretty-printed arguments; [text] carries the paired output.
  final String? toolName;
  final String? toolInput;

  /// Tool rows: true when the engine flagged the result as an error.
  final bool toolError;

  bool get isThinking => kind == 'thinking';
  bool get isTool => kind == 'tool';

  /// Human label for a tool row ("Ran …"): 'ctx_batch_execute' ->
  /// 'Ctx Batch Execute'.
  String get toolLabel {
    final raw = toolName ?? '';
    final parts = raw
        .split(RegExp('[_\\- ]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1));
    final label = parts.join(' ');
    return label.isEmpty ? 'Tool' : label;
  }

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    final sessionId = json['sessionId'] as String? ?? '';
    final seq = (json['seq'] as num?)?.toInt() ?? 0;
    return ConversationMessage(
      id: json['id'] as String? ?? '$sessionId:$seq',
      seq: seq,
      sessionId: sessionId,
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
      at: (json['at'] as num?)?.toInt() ?? 0,
      images: [
        for (final image in (json['images'] as List<dynamic>? ?? <dynamic>[]))
          image as String,
      ],
      kind: json['kind'] as String? ?? 'text',
      toolName: json['name'] as String?,
      toolInput: json['input'] as String?,
      toolError: json['error'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'seq': seq,
    'sessionId': sessionId,
    'role': role,
    'text': text,
    'at': at,
  };
}

/// The entity registrations the app passes to ArxaKitData.initialize —
/// same shape as the approvals slice.
const sessionEntityRegistration = ArxaKitEntityRegistration<CodeSession>(
  schema: ArxaKitTableSchema(
    table: 'code_sessions',
    columns: [
      ArxaKitColumn.id(),
      ArxaKitColumn('name', ArxaKitColumnType.text),
      ArxaKitColumn('title', ArxaKitColumnType.text),
      ArxaKitColumn('state', ArxaKitColumnType.text),
      ArxaKitColumn('parkedReason', ArxaKitColumnType.text),
      ArxaKitColumn('project', ArxaKitColumnType.text),
      ArxaKitColumn('workspace', ArxaKitColumnType.text),
      ArxaKitColumn('createdAt', ArxaKitColumnType.integer),
      ArxaKitColumn('updatedAt', ArxaKitColumnType.integer),
      ArxaKitColumn('dshSessionId', ArxaKitColumnType.text),
      ArxaKitColumn('org', ArxaKitColumnType.text),
    ],
  ),
  fromJson: CodeSession.fromJson,
  toJson: _sessionToJson,
);

const messageEntityRegistration =
    ArxaKitEntityRegistration<ConversationMessage>(
      schema: ArxaKitTableSchema(
        table: 'code_messages',
        columns: [
          ArxaKitColumn.id(),
          ArxaKitColumn('seq', ArxaKitColumnType.integer),
          ArxaKitColumn('sessionId', ArxaKitColumnType.text),
          ArxaKitColumn('role', ArxaKitColumnType.text),
          ArxaKitColumn('text', ArxaKitColumnType.jsonb),
          ArxaKitColumn('at', ArxaKitColumnType.integer),
        ],
      ),
      fromJson: ConversationMessage.fromJson,
      toJson: _messageToJson,
    );

// Tear-offs of instance members would not be const; top-level functions
// keep the registrations const.
Map<String, dynamic> _sessionToJson(CodeSession session) => session.toJson();
Map<String, dynamic> _messageToJson(ConversationMessage message) =>
    message.toJson();

/// One image staged on the composer (picked, not yet sent): the preview
/// file stays local, the send carries canonical base64 + media type.
class PendingImage {
  const PendingImage({
    required this.mediaType,
    required this.data,
    required this.preview,
  });

  /// 'image/jpeg' | 'image/png' — the engine's admitted set.
  final String mediaType;

  /// Canonical base64 of the encoded bytes.
  final String data;

  /// Local file for the composer chip preview.
  final dynamic preview;
}

/// One selectable row in the composer's model menu (a model inside its
/// provider group — the group id is the provider route for selectModel).
class ModelOption {
  const ModelOption({
    required this.provider,
    required this.id,
    required this.name,
    this.groupName,
  });

  final String provider;
  final String id;
  final String name;
  final String? groupName;
}
