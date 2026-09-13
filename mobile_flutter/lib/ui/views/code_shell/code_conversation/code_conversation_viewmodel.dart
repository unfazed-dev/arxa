// Code conversation viewmodel — one session's transcript plus its pending
// approvals threaded inline (the shared ApprovalCard), and a composer that
// queues/steers a prompt then re-pulls. Reactive: refresh on model-ready,
// after each send/decision, on pull-to-refresh, and whenever the tunnel
// (re)announces connected (the approvals pattern).
import 'dart:async';

import 'dart:convert' show base64Decode, base64Encode, utf8;

import 'dart:io' show Directory;

import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/foundation.dart';
import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app_data.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;

import '../../../../data/approvals/approval.dart';
import '../../../../data/approvals/approvals_repository.dart';
import '../../../../data/conversation/conversation.dart';
import '../../../../data/conversation/conversation_api_client.dart';
import '../../../../data/conversation/conversation_media.dart';
import '../../../../data/conversation/conversation_repository.dart';
import '../../../../services/transport_service.dart';

/// Why the last refresh failed — the view maps these to l10n copy.
enum CodeConversationError { offline, remote }

class CodeConversationViewModel extends BaseViewModel {
  CodeConversationViewModel(
    this.sessionId, [
    ConversationRepository? repository,
    ApprovalsRepository? approvalsRepository,
    Future<void> Function()? dataReady,
    ConversationMedia? media,
  ]) : _repository = repository ?? locator<ConversationRepository>(),
       _approvals = approvalsRepository ?? locator<ApprovalsRepository>(),
       _dataReady = dataReady ?? (() => AppData.ready.future),
       media = media ?? ConversationMedia();

  /// The dsh session this conversation shows (the route arg).
  final String sessionId;

  final ConversationRepository _repository;
  final ApprovalsRepository _approvals;

  /// The data boot runs in the BACKGROUND; every repository touch gates on
  /// it so a late boot never crashes a locator lookup.
  final Future<void> Function() _dataReady;

  /// The composer's media shelf (camera / photos / files / recents). A ctor
  /// seam so tests fake the pickers.
  final ConversationMedia media;

  /// Images staged on the composer — picked, not yet sent.
  List<PendingImage> get pendingImages => _pendingImages;
  List<PendingImage> _pendingImages = const [];

  /// Attachment-byte fetches, memoized per id (thumbnails render once).
  final Map<String, Future<Uint8List?>> _attachmentFutures = {};

  List<ConversationMessage> get messages => _messages;
  List<ConversationMessage> _messages = const [];

  /// This session's pending approvals, threaded inline in the transcript.
  List<Approval> get pendingApprovals => _pendingApprovals;
  List<Approval> _pendingApprovals = const [];

  /// The last refresh failure (loud, never a queue). Null after a
  /// successful refresh — the cached transcript still renders while set.
  CodeConversationError? get loadError => _error;
  CodeConversationError? _error;

  /// The message POST in flight (disables the composer).
  bool get sending => _sending;
  bool _sending = false;

  /// The approval id whose decision POST is in flight (disables its card).
  String? get decidingId => _decidingId;
  String? _decidingId;

  /// The session's effective sandbox mode (last switch or deployment
  /// default): read-only | workspace-write | danger-full-access.
  String? get sessionMode => _sessionMode;
  String? _sessionMode;

  /// The composer's model menu rows (provider groups flattened), the
  /// currently-selected model id, and the menu's fetch state.
  List<ModelOption> get models => _models;
  List<ModelOption> _models = const [];
  String get currentModel => _currentModel;
  String _currentModel = 'glm-5.2';
  bool get modelsLoading => _modelsLoading;
  bool _modelsLoading = false;
  bool _modelsLoaded = false;

  StreamSubscription<ArxaConnectionStatus>? _statusSub;

  /// The engine's live rail (SSE): a 'session' ping for THIS conversation
  /// re-pulls the transcript (debounced); the staleness guard re-pulls on a
  /// slow timer when the rail is quiet or the SSE carrier (the tunnel
  /// proxy) ever buffers. Web-side sends land here within a beat — and
  /// phone sends land in the studio, same store, same rail.
  StreamSubscription<ConversationLiveEvent>? _liveSub;
  Timer? _liveRefreshTimer;
  Timer? _stalenessTimer;

  /// The engine's human-command palette (the studio `+` list), loaded once
  /// per conversation.
  List<EngineCommand> get commands => _commands;
  List<EngineCommand> _commands = const [];
  bool _commandsLoaded = false;

  /// True while a command/export round-trip is in flight (the menu dims).
  bool get commandBusy => _commandBusy;
  bool _commandBusy = false;

  /// Auto-refresh: re-pull whenever the tunnel (re)announces connected.
  /// Subscribes once.
  void listenTransport() {
    if (_statusSub != null) return;
    _statusSub = _repository.transport.status.listen((s) {
      if (s.state == ArxaConnectionState.connected) refresh();
    });
  }

  Future<void> refresh() async {
    await _dataReady();
    var failed = false;
    try {
      await _repository.refreshSession(sessionId);
      _error = null;
    } on ConversationOfflineException {
      _error = CodeConversationError.offline;
      // Re-kick the dial so a desktop that came back late is found; the
      // connected announcement re-triggers this refresh.
      unawaited(_repository.transport.resume());
      failed = true;
    } on Exception {
      if (!failed) _error = CodeConversationError.remote;
    }
    // Pending approvals ride the sync'd approvals cache — refresh it too
    // (offline failures here leave the cached cards in place).
    try {
      await _approvals.refresh();
    } on Exception catch (e) {
      debugPrint('[code-conversation] approvals refresh failed: $e');
    }
    final approvals = await _approvals.list();
    _pendingApprovals = [
      for (final approval in approvals)
        if (approval.sessionId == sessionId) approval,
    ];
    _messages = await _repository.transcript(sessionId);
    _sessionMode = _repository.lastMode;
    notifyListeners();
  }

  /// Queue (or steer) a prompt into the session, then re-pull the
  /// transcript so the user bubble lands. Never throws: the composer's
  /// busy state clears on EVERY outcome.
  Future<bool> send(String text) async {
    await _dataReady();
    final trimmed = text.trim();
    if (_sending || (trimmed.isEmpty && _pendingImages.isEmpty)) return false;
    _sending = true;
    final staged = _pendingImages;
    notifyListeners();
    var accepted = false;
    try {
      await _repository.send(
        sessionId,
        trimmed,
        images: [
          for (final image in staged)
            (mediaType: image.mediaType, data: image.data),
        ],
      );
      accepted = true;
      _error = null;
      _pendingImages = const [];
    } on ConversationConflictException {
      accepted = false;
    } on ConversationOfflineException {
      _error = CodeConversationError.offline;
      accepted = false;
    } on Exception {
      _error = CodeConversationError.remote;
      accepted = false;
    } finally {
      _sending = false;
      // The follow-up refresh must never reject send() itself.
      try {
        await refresh();
      } on Object catch (e) {
        debugPrint('[code-conversation] post-send refresh failed: $e');
      }
    }
    return accepted;
  }

  /// Answer one pending approval inline. Returns true when accepted; false
  /// when refused (someone answered first), refused by the engine, or
  /// offline. Never throws (the card's busy state clears on every outcome).
  Future<bool> decide(Approval approval, List<ApprovalAnswer> answers) async {
    await _dataReady();
    _decidingId = approval.id;
    notifyListeners();
    var accepted = false;
    try {
      await _approvals.decide(approval.id, answers);
      accepted = true;
    } on Exception {
      accepted = false;
    } finally {
      _decidingId = null;
      try {
        await refresh();
      } on Object catch (e) {
        debugPrint('[code-conversation] post-decide refresh failed: $e');
      }
    }
    return accepted;
  }

  /// Subscribe to the engine's live pings (once). Call together with
  /// [listenTransport] from the view's onModelReady.
  void listenLive() {
    if (_liveSub != null) return;
    _liveSub = _repository.liveEvents.listen((event) {
      if (event.type == 'session' && event.sessionId == sessionId) {
        _queueRefresh();
      }
    });
    _repository.startLive();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      final last = _repository.lastLiveAt;
      final stale =
          last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 25);
      if (stale) _queueRefresh();
    });
  }

  /// Fold bursts of pings into one refresh.
  void _queueRefresh() {
    _liveRefreshTimer ??= Timer(const Duration(milliseconds: 300), () {
      _liveRefreshTimer = null;
      refresh();
    });
  }

  /// Load the engine's command palette once (the `+` sheet's Commands
  /// section). A failure leaves it empty — the sheet shows the honest
  /// nothing; never throws.
  Future<void> loadCommands() async {
    if (_commandsLoaded || _commandBusy) return;
    try {
      await _dataReady();
      _commands = await _repository.commands(sessionId);
      _commandsLoaded = true;
      notifyListeners();
    } on ConversationConflictException {
      // a parked session the engine could not hydrate right now — the
      // palette still lists nothing, the composer keeps working
    } on Exception catch (e) {
      debugPrint('[code-conversation] commands load failed: $e');
    }
  }

  /// Execute one slash-command line. Returns the engine's own outcome text
  /// (success AND error kinds — the registry's refusals are honest) for the
  /// toast; null on transport failure. A follow-up refresh picks up any
  /// state the command moved (plan flag, compaction, goal).
  Future<String?> runCommand(String line) async {
    if (_commandBusy) return null;
    _commandBusy = true;
    notifyListeners();
    try {
      await _dataReady();
      final result = await _repository.runCommand(sessionId, line);
      return result.text.isEmpty ? 'done' : result.text;
    } on ConversationRemoteException catch (e) {
      return e.toString();
    } on ConversationConflictException catch (e) {
      return e.toString();
    } on Exception catch (e) {
      debugPrint('[code-conversation] command failed: $e');
      return null;
    } finally {
      _commandBusy = false;
      notifyListeners();
      try {
        await refresh();
      } on Object catch (e) {
        debugPrint('[code-conversation] post-command refresh failed: $e');
      }
    }
  }

  /// Export the transcript as markdown and open the share sheet. Returns
  /// false when the pull or the share failed (the toast says so).
  Future<bool> exportTranscript() async {
    if (_commandBusy) return false;
    _commandBusy = true;
    notifyListeners();
    try {
      await _dataReady();
      final path = '${Directory.systemTemp.path}/arxa-$sessionId.md';
      final saved = await _repository.exportTranscript(sessionId, path);
      await SharePlus.instance.share(ShareParams(files: [XFile(saved)]));
      return true;
    } on Exception catch (e) {
      debugPrint('[code-conversation] export failed: $e');
      return false;
    } finally {
      _commandBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_liveSub?.cancel());
    _liveRefreshTimer?.cancel();
    _stalenessTimer?.cancel();
    super.dispose();
  }

  /// Load the model directory once for the composer's model menu. A failure
  /// leaves the menu empty (the pill keeps the current label) — never throws.
  Future<void> loadModels() async {
    if (_modelsLoaded || _modelsLoading) return;
    _modelsLoading = true;
    notifyListeners();
    try {
      await _dataReady();
      final directory = await _repository.models(sessionId);
      final rows = <ModelOption>[];
      for (final group
          in (directory['groups'] as List<dynamic>? ?? <dynamic>[])) {
        final g = group as Map<String, dynamic>;
        for (final m in (g['models'] as List<dynamic>? ?? <dynamic>[])) {
          final model = m as Map<String, dynamic>;
          rows.add(
            ModelOption(
              provider: g['id'] as String? ?? '',
              id: model['id'] as String? ?? '',
              name: model['name'] as String? ?? model['id'] as String? ?? '',
              groupName: g['name'] as String?,
            ),
          );
        }
      }
      _models = rows;
      _modelsLoaded = true;
      final current = directory['current'] as Map<String, dynamic>?;
      final currentModel = current?['model'] as String?;
      if (currentModel != null && currentModel.isNotEmpty) {
        _currentModel = currentModel;
      }
    } on Exception catch (e) {
      debugPrint('[code-conversation] models load failed: $e');
    } finally {
      _modelsLoading = false;
      notifyListeners();
    }
  }

  /// Select the session's model. Optimistic label; a failure reverts it.
  Future<void> selectModel(String provider, String model) async {
    if (provider.isEmpty || model.isEmpty) return;
    final previous = _currentModel;
    _currentModel = model;
    notifyListeners();
    try {
      await _dataReady();
      await _repository.selectModel(sessionId, provider, model);
    } on Exception catch (e) {
      _currentModel = previous;
      debugPrint('[code-conversation] select model failed: $e');
      notifyListeners();
    }
  }

  /// Switch the session's sandbox mode. Optimistic; a failure reverts.
  Future<void> setMode(String mode) async {
    if (mode.isEmpty || mode == _sessionMode) return;
    final previous = _sessionMode;
    _sessionMode = mode;
    notifyListeners();
    try {
      await _dataReady();
      await _repository.setMode(sessionId, mode);
    } on Exception catch (e) {
      _sessionMode = previous;
      debugPrint('[code-conversation] set mode failed: $e');
      notifyListeners();
    }
  }

  /// Stage one picked image on the composer. Returns a user-facing message
  /// when the file is refused (unreadable or an unaccepted media type);
  /// null on success.
  Future<String?> stageImage(XFile file) async {
    final mediaType = _imageMediaType(file.path);
    if (mediaType == null) return 'Only JPEG and PNG images are supported';
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Exception {
      return 'Could not read the picked image';
    }
    if (bytes.lengthInBytes > _maxImageBytes) {
      return 'Image is too large to send';
    }
    _pendingImages = [
      ..._pendingImages,
      PendingImage(
        mediaType: mediaType,
        data: base64Encode(bytes),
        preview: file,
      ),
    ];
    notifyListeners();
    return null;
  }

  /// Take one staged image back off the composer.
  void removePendingImage(PendingImage image) {
    _pendingImages = [
      for (final staged in _pendingImages)
        if (staged != image) staged,
    ];
    notifyListeners();
  }

  /// A picked FILE: images join the staged images; a readable text file
  /// comes back as [inline] — a fenced block for the composer body (the
  /// engine's prompt surface is text + images, so that IS the honest file
  /// wire). [error] is a user-facing refusal; exactly one field is set.
  Future<({String? inline, String? error})> stageFile(XFile file) async {
    if (_imageMediaType(file.path) != null) {
      return (inline: null, error: await stageImage(file));
    }
    const textExts = {
      'txt',
      'md',
      'markdown',
      'json',
      'yaml',
      'yml',
      'toml',
      'xml',
      'html',
      'css',
      'js',
      'mjs',
      'ts',
      'tsx',
      'jsx',
      'dart',
      'py',
      'rb',
      'go',
      'rs',
      'java',
      'kt',
      'swift',
      'c',
      'h',
      'cpp',
      'hpp',
      'cs',
      'sh',
      'bash',
      'zsh',
      'fish',
      'sql',
      'proto',
      'gradle',
      'properties',
      'csv',
      'log',
      'env',
      'gitignore',
      'lock',
      'plist',
      'arb',
      'pubspec',
      'gemspec',
      'rake',
    };
    final ext = file.path.split('.').last.toLowerCase();
    if (!textExts.contains(ext)) {
      return (inline: null, error: 'Text files and images are supported');
    }
    try {
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > _maxTextFileBytes) {
        return (inline: null, error: 'Text file is too large to attach');
      }
      return (
        inline:
            '```$ext\n${utf8.decode(bytes, allowMalformed: true).trim()}\n```',
        error: null,
      );
    } on Exception {
      return (inline: null, error: 'Could not read the picked file');
    }
  }

  /// The stored bytes of one admitted attachment (memoized per id); null
  /// when the engine refuses (never referenced by this session).
  Future<Uint8List?> attachmentBytes(String attachmentId) {
    return _attachmentFutures.putIfAbsent(attachmentId, () async {
      try {
        await _dataReady();
        final body = await _repository.attachment(sessionId, attachmentId);
        final data = body['data'] as String?;
        return data == null ? null : base64Decode(data);
      } on Exception {
        return null;
      }
    });
  }

  /// The engine's admitted media types (canonical base64 carries the rest).
  static const _maxImageBytes = 6 * 1024 * 1024;
  static const _maxTextFileBytes = 256 * 1024;

  static String? _imageMediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
  }
}
