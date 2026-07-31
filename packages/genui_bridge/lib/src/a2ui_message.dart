import 'dart:convert';

/// The A2UI protocol version genui 0.10.1 (`a2ui_core`) accepts on the wire.
///
/// Ground truth: `a2ui_core`'s `A2uiMessage.fromJson` rejects any envelope
/// whose `version` is not exactly this string.
/// Source: https://github.com/flutter/genui/blob/main/packages/a2ui_core/lib/src/core/messages.dart
const String a2uiVersion = 'v0.9';

/// Thrown when a JSON envelope is not a well-formed [A2uiMessage].
///
/// Raised for a missing/wrong `version`, zero or multiple verb keys, an
/// unknown verb, or a body whose required fields are missing or mistyped.
/// The bridge's repair loop turns this into a re-ask, so it carries the
/// offending [details] payload for diagnostics.
class A2uiFormatException extends FormatException {
  A2uiFormatException(super.message, [this.details]);

  /// The JSON payload that failed to parse, when available.
  final Object? details;

  @override
  String toString() => 'A2uiFormatException: $message';
}

/// Base class for the four A2UI v0.9 server-to-client messages (verbs).
///
/// Wire form (canonical on write):
///
/// ```json
/// {"version": "v0.9", "<verb>": { ...body... }}
/// ```
///
/// with exactly one of `createSurface`, `updateComponents`, `updateDataModel`,
/// `deleteSurface` per envelope.
///
/// Reading is tolerant of the rename-in-flight: the v0.8 names
/// `surfaceUpdate` (→ [UpdateComponents]) and `dataModelUpdate`
/// (→ [UpdateDataModel]) are accepted as aliases. Writing always uses the
/// canonical v0.9 names. (v0.8's `beginRendering` is NOT aliased — its body
/// shape differs from [CreateSurface]; a pre-v0.9 message without
/// `version: "v0.9"` is rejected outright.)
sealed class A2uiMessage {
  const A2uiMessage();

  /// The surface this message targets.
  String get surfaceId;

  /// Canonical v0.9 envelope for this message.
  Map<String, dynamic> toJson();

  /// Serializes to the canonical one-line (JSONL) wire form.
  String toJsonLine() => jsonEncode(toJson());

  /// Deserializes one envelope, accepting the v0.8 verb aliases.
  ///
  /// Throws [A2uiFormatException] on any structural problem — callers feeding
  /// LLM output should treat that as a repairable validation failure.
  static A2uiMessage fromJson(Map<String, dynamic> json) {
    final Object? rawVersion = json['version'];
    if (rawVersion is! String || rawVersion != a2uiVersion) {
      throw A2uiFormatException(
        'A2UI message must have version "$a2uiVersion" '
        '(got ${rawVersion is String ? '"$rawVersion"' : rawVersion}).',
        json,
      );
    }

    // Canonical verb name → legacy alias accepted on read.
    const verbKeys = <String, String?>{
      'createSurface': null,
      'updateComponents': 'surfaceUpdate',
      'updateDataModel': 'dataModelUpdate',
      'deleteSurface': null,
    };
    // Every verb key present (canonical names and aliases count separately —
    // a message carrying both `updateComponents` and `surfaceUpdate` is as
    // ambiguous as one carrying two different verbs).
    final present = <String>[
      for (final entry in verbKeys.entries) ...[
        if (json.containsKey(entry.key)) entry.key,
        if (entry.value != null && json.containsKey(entry.value)) entry.value!,
      ],
    ];
    if (present.length != 1) {
      throw A2uiFormatException(
        'A2UI message must contain exactly one of '
        '${verbKeys.keys.join(', ')}; got '
        '${present.isEmpty ? 'none' : present.join(', ')}.',
        json,
      );
    }

    final presentKey = present.single;
    final verb = verbKeys.keys.firstWhere(
      (canonical) =>
          canonical == presentKey || verbKeys[canonical] == presentKey,
    );
    final body = json[presentKey];
    if (body is! Map<String, dynamic>) {
      throw A2uiFormatException(
        'A2UI "$verb" body must be a JSON object.',
        json,
      );
    }

    switch (verb) {
      case 'createSurface':
        return CreateSurface(
          surfaceId: _requiredString(body, 'surfaceId', verb, json),
          catalogId: _requiredString(body, 'catalogId', verb, json),
          theme: _optionalMap(body, 'theme', verb, json),
          sendDataModel:
              _optionalBool(body, 'sendDataModel', verb, json) ?? false,
        );
      case 'updateComponents':
        final rawComponents = body['components'];
        if (rawComponents is! List) {
          throw A2uiFormatException(
            'A2UI "$verb" message must have a "components" array.',
            json,
          );
        }
        return UpdateComponents(
          surfaceId: _requiredString(body, 'surfaceId', verb, json),
          components: [
            for (final c in rawComponents)
              if (c is Map<String, dynamic>)
                c
              else
                throw A2uiFormatException(
                  'A2UI "$verb" components must be JSON objects.',
                  json,
                ),
          ],
        );
      case 'updateDataModel':
        final path = body['path'];
        if (path != null && path is! String) {
          throw A2uiFormatException(
            'A2UI "$verb" "path" must be a string when present.',
            json,
          );
        }
        return UpdateDataModel(
          surfaceId: _requiredString(body, 'surfaceId', verb, json),
          path: path as String?,
          value: body['value'],
        );
      case 'deleteSurface':
        return DeleteSurface(
          surfaceId: _requiredString(body, 'surfaceId', verb, json),
        );
      default:
        // Unreachable: `present` only contains keys of `verbKeys`.
        throw StateError(verb);
    }
  }

  static String _requiredString(
    Map<String, dynamic> body,
    String field,
    String verb,
    Object? envelope,
  ) {
    final value = body[field];
    if (value is! String) {
      throw A2uiFormatException(
        'A2UI "$verb" message must have a string "$field".',
        envelope,
      );
    }
    return value;
  }

  static Map<String, dynamic>? _optionalMap(
    Map<String, dynamic> body,
    String field,
    String verb,
    Object? envelope,
  ) {
    final value = body[field];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw A2uiFormatException(
        'A2UI "$verb" "$field" must be an object when present.',
        envelope,
      );
    }
    return value;
  }

  static bool? _optionalBool(
    Map<String, dynamic> body,
    String field,
    String verb,
    Object? envelope,
  ) {
    final value = body[field];
    if (value == null) return null;
    if (value is! bool) {
      throw A2uiFormatException(
        'A2UI "$verb" "$field" must be a boolean when present.',
        envelope,
      );
    }
    return value;
  }
}

/// Signals the client to create a new surface and begin rendering it.
///
/// Spec: https://github.com/google/A2UI/blob/main/specification/v0_9/docs/a2ui_protocol.md
final class CreateSurface extends A2uiMessage {
  const CreateSurface({
    required this.surfaceId,
    required this.catalogId,
    this.theme,
    this.sendDataModel = false,
  });

  @override
  final String surfaceId;

  /// Identifies the component catalog this surface renders against. An
  /// opaque agreed string, not a resolvable URI.
  final String catalogId;

  /// Catalog-defined theme parameters (e.g. `{'primaryColor': '#FF0000'}`).
  final Map<String, dynamic>? theme;

  /// If true, the client includes this surface's full data model in the
  /// metadata of every client-to-server message. Defaults to false.
  final bool sendDataModel;

  @override
  Map<String, dynamic> toJson() => {
        'version': a2uiVersion,
        'createSurface': {
          'surfaceId': surfaceId,
          'catalogId': catalogId,
          if (theme != null) 'theme': theme,
          'sendDataModel': sendDataModel,
        },
      };
}

/// Adds to or replaces components of an existing surface. Components are a
/// flat list; the tree is expressed by ID references between them.
final class UpdateComponents extends A2uiMessage {
  const UpdateComponents({required this.surfaceId, required this.components});

  @override
  final String surfaceId;

  /// Component objects, each `{'id': ..., 'component': <type>, ...props}`.
  /// Kept as raw maps: the bridge validates them against the caller-supplied
  /// catalog schemas, not against a compiled-in component list.
  final List<Map<String, dynamic>> components;

  @override
  Map<String, dynamic> toJson() => {
        'version': a2uiVersion,
        'updateComponents': {'surfaceId': surfaceId, 'components': components},
      };
}

/// Replaces the value at [path] in a surface's data model. An omitted (or
/// `/`) path replaces the whole model; an omitted value removes the key at
/// [path].
final class UpdateDataModel extends A2uiMessage {
  const UpdateDataModel({required this.surfaceId, this.path, this.value});

  @override
  final String surfaceId;

  /// JSON Pointer into the data model; omitted means the root.
  final String? path;

  /// The replacement value; null means "remove the key at [path]".
  final Object? value;

  @override
  Map<String, dynamic> toJson() => {
        'version': a2uiVersion,
        'updateDataModel': {
          'surfaceId': surfaceId,
          if (path != null) 'path': path,
          if (value != null) 'value': value,
        },
      };
}

/// Removes a surface and all its components and data from the UI.
final class DeleteSurface extends A2uiMessage {
  const DeleteSurface({required this.surfaceId});

  @override
  final String surfaceId;

  @override
  Map<String, dynamic> toJson() => {
        'version': a2uiVersion,
        'deleteSurface': {'surfaceId': surfaceId},
      };
}
