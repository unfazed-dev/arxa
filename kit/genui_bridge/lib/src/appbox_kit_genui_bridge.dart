import 'dart:convert';

import 'appbox_kit_a2ui_message.dart';
import 'appbox_kit_a2ui_stream_parser.dart';
import 'appbox_kit_chat_stream.dart';
import 'appbox_kit_json_schema.dart';

/// The catalogId of the A2UI v0.9 basic catalog (the one genui ships as
/// `BasicCatalogItems`). Used as the prompt default; an opaque agreed string,
/// never fetched.
const String appBoxKitA2uiBasicCatalogId =
    'https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json';

/// The validated result of one [AppBoxKitGenuiBridge.generate] turn.
class AppBoxKitA2uiTurn {
  const AppBoxKitA2uiTurn({
    required this.messages,
    required this.texts,
    required this.attempts,
  });

  /// The validated A2UI messages, in stream order. Only valid messages ever
  /// appear here — a turn whose messages fail validation is retried, never
  /// partially emitted.
  final List<AppBoxKitA2uiMessage> messages;

  /// Non-message prose the model emitted alongside the messages.
  final List<String> texts;

  /// How many provider calls this turn took (1 = no repair needed).
  final int attempts;

  /// The canonical JSONL wire form of [messages] — safe to forward verbatim
  /// to a genui `A2uiTransportAdapter.addChunk` caller.
  String toJsonl() => messages.map((m) => m.toJsonLine()).join('\n');
}

/// Raised when a turn is still invalid after all repair attempts.
class AppBoxKitGenuiBridgeFailure implements Exception {
  const AppBoxKitGenuiBridgeFailure({
    required this.attempts,
    required this.errors,
    required this.lastRawOutput,
  });

  /// Total provider calls made (1 initial + repairs).
  final int attempts;

  /// One entry per failed attempt, describing what was wrong.
  final List<String> errors;

  /// The raw model output of the final attempt, for diagnostics.
  final String lastRawOutput;

  @override
  String toString() => 'AppBoxKitGenuiBridgeFailure: still invalid after $attempts '
      'attempt(s):\n${errors.join('\n')}';
}

/// The reliability core: drives a [AppBoxKitChatStream], parses its output into A2UI
/// messages, validates them against the catalog, and re-asks with the
/// validation error appended when output is invalid — at most [maxRepairs]
/// times. Only valid messages ever leave the bridge.
///
/// Reliability does not depend on any provider's structured-output mode; the
/// contract is prompt → streamed parse → validate → bounded repair.
class AppBoxKitGenuiBridge {
  /// [catalog] maps component type names (`Text`, `Card`, …) to their JSON
  /// schemas (runtime inputs — flatten any `$ref`s first; see
  /// [AppBoxKitJsonSchemaValidator] for the supported subset). An empty catalog
  /// disables per-component validation. [systemPrompt] overrides the prompt
  /// built from the catalog when you need full control.
  AppBoxKitGenuiBridge({
    required AppBoxKitChatStream chat,
    Map<String, AppBoxKitJsonSchema> catalog = const {},
    this.catalogId = appBoxKitA2uiBasicCatalogId,
    this.maxRepairs = 2,
    String? systemPrompt,
    AppBoxKitJsonSchemaValidator validator = const AppBoxKitJsonSchemaValidator(),
  })  : _chat = chat,
        _catalog = catalog,
        _validator = validator,
        systemPrompt = systemPrompt ??
            appBoxKitBuildA2uiSystemPrompt(catalogId: catalogId, catalog: catalog);

  final AppBoxKitChatStream _chat;
  final Map<String, AppBoxKitJsonSchema> _catalog;
  final AppBoxKitJsonSchemaValidator _validator;

  /// The catalogId the prompt instructs the model to use, and the one
  /// [AppBoxKitCreateSurface] messages are checked against.
  final String catalogId;

  /// Maximum number of re-asks after an invalid attempt. Total provider
  /// calls per turn ≤ 1 + maxRepairs.
  final int maxRepairs;

  /// The system prompt prepended to every provider call.
  final String systemPrompt;

  /// Runs one turn: [messages] are the conversation so far (user/assistant
  /// turns; the bridge prepends its own system prompt). Returns the validated
  /// turn, or throws [AppBoxKitGenuiBridgeFailure] after 1 + [maxRepairs] attempts.
  Future<AppBoxKitA2uiTurn> generate(List<AppBoxKitChatMessage> messages) async {
    final attemptMessages = <AppBoxKitChatMessage>[
      AppBoxKitChatMessage.system(systemPrompt),
      ...messages,
    ];
    final errors = <String>[];
    var rawOutput = '';

    for (var attempt = 1; attempt <= maxRepairs + 1; attempt++) {
      final events = await const AppBoxKitA2uiStreamParser()
          .bind(_chat.complete(attemptMessages))
          .toList();

      final messagesOut = <AppBoxKitA2uiMessage>[];
      final texts = <String>[];
      final attemptErrors = <String>[];
      final raw = StringBuffer();

      for (final event in events) {
        switch (event) {
          case AppBoxKitA2uiMessageEvent(:final message):
            messagesOut.add(message);
            raw.writeln(message.toJsonLine());
          case AppBoxKitA2uiTextEvent(:final text):
            texts.add(text);
            raw.write(text);
          case AppBoxKitA2uiErrorEvent(:final error, :final raw):
            attemptErrors.add('$error (payload: ${_snippet(raw)})');
        }
      }
      rawOutput = raw.toString();

      attemptErrors.addAll(_validateCatalog(messagesOut));
      if (messagesOut.isEmpty && attemptErrors.isEmpty) {
        attemptErrors.add('output contained no A2UI messages');
      }

      if (attemptErrors.isEmpty) {
        return AppBoxKitA2uiTurn(
          messages: messagesOut,
          texts: texts,
          attempts: attempt,
        );
      }

      errors.add('attempt $attempt: ${attemptErrors.join('; ')}');
      if (attempt <= maxRepairs) {
        // Re-ask with the validation error appended, as the protocol's
        // "prompt-first" design intends. The failed output is included so
        // the model can correct rather than regenerate blind.
        attemptMessages
          ..add(AppBoxKitChatMessage.assistant(rawOutput))
          ..add(AppBoxKitChatMessage.user(_repairInstruction(attemptErrors)));
      }
    }

    throw AppBoxKitGenuiBridgeFailure(
      attempts: maxRepairs + 1,
      errors: errors,
      lastRawOutput: rawOutput,
    );
  }

  /// Validates parsed messages against the catalog: component shape, known
  /// component types, per-component schemas, and the createSurface catalogId.
  List<String> _validateCatalog(List<AppBoxKitA2uiMessage> messages) {
    final errors = <String>[];
    for (final message in messages) {
      switch (message) {
        case AppBoxKitCreateSurface(:final catalogId):
          if (catalogId != this.catalogId) {
            errors.add('createSurface: catalogId must be "${this.catalogId}"'
                ' (got "$catalogId")');
          }
        case AppBoxKitUpdateComponents(:final components):
          final seenIds = <String>{};
          for (final component in components) {
            final id = component['id'];
            final type = component['component'];
            if (id is! String) {
              errors.add('component ${jsonEncode(component)}: '
                  'missing string "id"');
              continue;
            }
            if (!seenIds.add(id)) {
              errors.add('component "$id": duplicate id');
            }
            if (type is! String) {
              errors.add('component "$id": missing string "component"');
              continue;
            }
            if (_catalog.isEmpty) continue;
            final schema = _catalog[type];
            if (schema == null) {
              errors.add('component "$id": type "$type" is not in the catalog');
              continue;
            }
            for (final e in _validator.validate(component, schema)) {
              errors.add('component "$id" ($type): $e');
            }
          }
        case AppBoxKitUpdateDataModel() || AppBoxKitDeleteSurface():
          break; // Envelope checks in fromJson suffice.
      }
    }
    return errors;
  }

  static String _repairInstruction(List<String> attemptErrors) =>
      'A2UI validation error:\n'
      '${attemptErrors.map((e) => '- $e').join('\n')}\n'
      'Re-emit the COMPLETE set of A2UI messages with every error corrected. '
      'Output only JSONL: one {"version":"$appBoxKitA2uiVersion",...} object per line, '
      'no markdown, no commentary.';

  static String _snippet(String raw) {
    final oneLine = raw.replaceAll('\n', ' ');
    return oneLine.length <= 200 ? oneLine : '${oneLine.substring(0, 200)}…';
  }
}

/// Builds the system prompt that instructs a model to speak A2UI v0.9 JSONL
/// against [catalog]. This — not any provider's structured-output mode — is
/// the first leg of the bridge's reliability story.
String appBoxKitBuildA2uiSystemPrompt({
  String catalogId = appBoxKitA2uiBasicCatalogId,
  Map<String, AppBoxKitJsonSchema> catalog = const {},
}) {
  final catalogSection = catalog.isEmpty
      ? 'Use only components from the A2UI v0.9 basic catalog '
          '(Text, Image, Icon, Row, Column, List, Card, Tabs, Modal, Divider, '
          'Button, TextField, CheckBox, ChoicePicker, Slider, DateTimeInput, '
          'Video, AudioPlayer).'
      : 'Use ONLY these component types, validating every component\'s props '
          'against its JSON schema:\n'
          '${const JsonEncoder.withIndent('  ').convert(catalog)}';
  return '''
You generate user interfaces for an A2UI v0.9 client. Respond with A2UI
messages ONLY: one complete JSON object per line (JSONL). No markdown fences,
no commentary, no surrounding prose.

Every message is an envelope {"version":"$appBoxKitA2uiVersion","<verb>":{...}} with
EXACTLY ONE verb key:

- createSurface {surfaceId, catalogId, theme?, sendDataModel?} — must be the
  first message for a new surface. Always use catalogId "$catalogId".
- updateComponents {surfaceId, components:[{id, component, ...props}]} — a
  flat list; the tree is expressed by id references (children/child). One
  component MUST have id "root".
- updateDataModel {surfaceId, path?, value?} — path is a JSON Pointer; omit
  it to replace the whole data model; omit value to remove the key at path.
- deleteSurface {surfaceId}.

$catalogSection

Where a component property expects data, bind it with a {"path":"/pointer"}
object referencing the surface data model instead of hardcoding a value.

If a later user message reports an "A2UI validation error", re-emit the
complete corrected message set as JSONL.''';
}
