/// The components gallery's viewmodel (route `/showcase/profile/components`).
/// A viewmodel is actions in and streams out: the view calls methods when the
/// user does something, and reads getters when something changed. The
/// viewmodel never touches the view — swap the UI for any other and this file
/// stays unchanged.
///
/// This is the business logic for the components gallery. Every demo on the
/// surface is stateless except the composer: the input-bar demo owns a seeded
/// fake conversation (notes-shell pattern — fake thread, REAL kit services
/// for audio), so this viewmodel holds that stream, its typing state, the
/// send action, and the tap-to-toggle record flow over the kit audio
/// service. The recorder is the same service the notes shell uses, resolved
/// from the locator — so the OS microphone-permission prompt is triggered
/// through the kit on the first tap.
///
/// Requirements:
/// 1. [Gallery scaffold]
/// The viewmodel holds no state; every components demo is a stateless imperative kit call.
/// 2. [Input bar]
/// The composer demo's thread is a seeded `messages` stream; `sendDraft`
/// appends the user's draft (text / attachments / voice note), flips `typing`,
/// and lands a fake kind-aware reply — the thread is live, not a static list.
/// 3. [Input bar — tap-to-toggle record]
/// Tapping the mic asks the kit recorder for permission, then records; the
/// recorder phase streams out so the view can animate the trailing action's
/// glyph mic → stop. Tapping stop sends the note; a stop under a second or
/// the strip's cancel discards it.
///
/// Relationships:
///
///           ┌────────────────────────┐
///           │components gallery view │
///           └────────────────────────┘
///      ┌─────────────────────────────────┐
///      │  components gallery viewmodel   │
///      └─────────────────────────────────┘
///          ══════ sendDraft ══════
///          ══ startRecording / stopRecording / cancelRecording ══
///          ═════ messages ══════
///          ══ recorderPhase / recordingElapsed / recordingLevel ══
///          ════════ typing ════════
///
/// History: git log --follow -- kit/showcase_app/lib/ui/views/showcase_profile_shell/showcase_components/showcase_components_viewmodel.dart
library;

import 'dart:async';

import 'package:arxa_kit_media/arxa_kit_media.dart';
import 'package:arxa_kit_showcase_app/data/models/showcase_composer_models/models.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';

/// Fixed fake timestamps for the seeded thread (stable across pumps/tests).
final _seedDay = DateTime(2026, 8, 16, 9, 41);

final _seedMessages = <ShowcaseComposerMessageModel>[
  ShowcaseComposerTextMessageModel(
    fromUser: false,
    sentAt: DateTime(2026, 8, 16, 9, 38),
    text: 'Morning! The studio build is ready for review — seeded demo '
        'thread, everything here is fake data.',
  ),
  ShowcaseComposerAttachmentMessageModel(
    fromUser: false,
    sentAt: _seedDay,
    attachment: ShowcaseComposerAttachmentModel(
      kind: ShowcaseComposerAttachmentKind.photo,
      name: 'site-photo.png',
      detail: '2.4 MB · Photo',
    ),
  ),
  ShowcaseComposerVoiceMessageModel(
    fromUser: false,
    sentAt: DateTime(2026, 8, 16, 9, 43),
    durationSeconds: 12,
  ),
  ShowcaseComposerTextMessageModel(
    fromUser: true,
    sentAt: DateTime(2026, 8, 16, 9, 45),
    text: 'Got it — reviewing now. The composer is fully usable: attach, '
        'record, send.',
  ),
];

/// Round-robin replies for plain-text drafts — the "other side" of the fake
/// conversation. Attachment and voice drafts get kind-aware replies instead
/// (see [_replyTo]).
const _textReplies = <String>[
  'On it — will review and circle back.',
  'Noted. Shipping the checklist after this.',
  'Makes sense — anything else before we lock it in?',
];

/// How long the fake contact "types" before the reply lands.
const _replyDelay = Duration(milliseconds: 1600);

/// A recording shorter than this is a fumble, not a note (the messenger
/// idiom) — the recorder's cancel throws the file away.
const _minRecording = Duration(seconds: 1);

/// Where the record flow is right now — the single source the trailing
/// action's glyph binds to (mic when idle, stop while recording).
/// [starting] spans the permission await: the OS prompt (first tap ever)
/// claims the screen, so the button disables until the answer lands instead
/// of accepting a second tap mid-flight.
enum ShowcaseComposerRecorderPhase { idle, starting, recording }

class ShowcaseComponentsViewModel extends ArxaKitViewModel {
  ShowcaseComponentsViewModel() {
    // Bridge the recorder's broadcast streams into seeded subjects so the
    // view binds with ArxaKitStreamBuilder without a loading flash (the
    // notes adapter bridges the same streams the same way).
    listen(
      'conversation.record.elapsed',
      to: [_recorder.elapsed$],
      onData: (elapsed) => _recordingElapsed.add(elapsed as Duration?),
    );
    listen(
      'conversation.record.level',
      to: [_recorder.amplitude$],
      onData: (dbfs) => _recordingLevel.add(dbfs as double),
    );
  }

  /// The kit audio service (record plugin → AVAudioRecorder/AudioRecord),
  /// registered in the app locator under its interface — the same service
  /// the notes shell records voice memos with.
  final ArxaKitAudioRecorderService _recorder =
      arxaKitLocator<ArxaKitAudioRecorderService>();

  final BehaviorSubject<List<ShowcaseComposerMessageModel>> _messages =
      BehaviorSubject<List<ShowcaseComposerMessageModel>>.seeded(_seedMessages);

  final BehaviorSubject<bool> _typing = BehaviorSubject<bool>.seeded(false);

  final BehaviorSubject<Duration?> _recordingElapsed =
      BehaviorSubject<Duration?>.seeded(null);

  final BehaviorSubject<double> _recordingLevel =
      BehaviorSubject<double>.seeded(-45);

  final BehaviorSubject<ShowcaseComposerRecorderPhase> _recorderPhase =
      BehaviorSubject<ShowcaseComposerRecorderPhase>.seeded(
          ShowcaseComposerRecorderPhase.idle);

  /// The seeded fake conversation the composer demo renders and appends to.
  Stream<List<ShowcaseComposerMessageModel>> get messages => _messages.stream;

  /// True while the fake contact is "typing" a reply to the last send.
  Stream<bool> get typing => _typing.stream;

  /// [3. Tap-to-toggle record] The recorder's phase — the trailing action's
  /// glyph binds here (mic when idle, stop while recording), so the button
  /// IS the state and the native tier can animate the swap (SF Symbol
  /// replace transition on the Apple tiers).
  ValueStream<ShowcaseComposerRecorderPhase> get recorderPhase =>
      _recorderPhase.stream;

  /// [3. Tap-to-toggle record] How long the current recording has run;
  /// null while idle. Seeds null — the strip renders only while recording.
  ValueStream<Duration?> get recordingElapsed => _recordingElapsed.stream;

  /// [3. Tap-to-toggle record] Live input level in dBFS for the strip's dot.
  ValueStream<double> get recordingLevel => _recordingLevel.stream;

  int _replyCount = 0;

  // ── Tap-to-toggle record ─────────────────────────────────────────────────

  /// [3. Tap-to-toggle record] The mic tap. Requests microphone permission
  /// through the kit — the OS prompt fires on the very first tap — then
  /// starts recording and flips the phase to [recording] (the glyph swap the
  /// view animates). False only when permission was denied; the view
  /// surfaces that as the kit warning toast.
  Future<bool> startRecording() =>
      action('conversation.record.start', () async {
        if (_recorderPhase.value != ShowcaseComposerRecorderPhase.idle) {
          return true;
        }
        _recorderPhase.add(ShowcaseComposerRecorderPhase.starting);
        if (!await _recorder.hasPermission()) {
          _recorderPhase.add(ShowcaseComposerRecorderPhase.idle);
          return false;
        }
        // The phase may have moved on while the permission prompt was up
        // (a cancel racing the answer): consume it and skip the start.
        if (_recorderPhase.value != ShowcaseComposerRecorderPhase.starting) {
          return true;
        }
        await _recorder.start();
        _recorderPhase.add(ShowcaseComposerRecorderPhase.recording);
        return true;
      }).completeOnError('Recording start failed', withValue: false);

  /// [3. Tap-to-toggle record] The stop tap — stop-to-send. Stops the
  /// recording and returns the note (seconds + file path) for the draft, or
  /// null when there is nothing worth sending — no recording, or a
  /// sub-second fumble (discarded).
  Future<({int seconds, String? path})?> stopRecording() =>
      action('conversation.record.stop', () async {
        if (_recorderPhase.value != ShowcaseComposerRecorderPhase.recording) {
          _recorderPhase.add(ShowcaseComposerRecorderPhase.idle);
          return null;
        }
        _recorderPhase.add(ShowcaseComposerRecorderPhase.idle);
        if (_recorder.elapsed < _minRecording) {
          await _recorder.cancel(); // deletes the in-progress file
          return null;
        }
        final result = await _recorder.stop();
        if (result == null) return null;
        return (
          seconds: result.duration.inSeconds < 1
              ? 1
              : result.duration.inSeconds,
          path: result.path,
        );
      }).completeOnError('Recording stop failed', withValue: null);

  /// [3. Tap-to-toggle record] The strip's cancel: throws the recording
  /// away, file included, and returns the composer to the idle mic.
  /// Fire-and-forget by design (`.execute()`): the strip's tap handler never
  /// awaits, and a bare builder would stay lazy.
  void cancelRecording() =>
      action('conversation.record.cancel', () async {
        if (_recorderPhase.value == ShowcaseComposerRecorderPhase.recording) {
          await _recorder.cancel();
        }
        _recorderPhase.add(ShowcaseComposerRecorderPhase.idle);
      }).completeOnError('Recording cancel failed').execute();

  // ── Thread ────────────────────────────────────────────────────────────────

  /// Appends one draft as user messages (text first, then attachments, then
  /// the voice note), then runs the live-reply choreography. A no-op for an
  /// empty draft.
  void sendDraft(ShowcaseComposerDraftModel draft) {
    if (draft.isEmpty) return;
    final now = DateTime.now();
    final sent = <ShowcaseComposerMessageModel>[
      if (draft.text.trim().isNotEmpty)
        ShowcaseComposerTextMessageModel(
            text: draft.text.trim(), fromUser: true, sentAt: now),
      for (final attachment in draft.attachments)
        ShowcaseComposerAttachmentMessageModel(
            attachment: attachment, fromUser: true, sentAt: now),
      if (draft.voiceNoteSeconds case final int seconds)
        ShowcaseComposerVoiceMessageModel(
          durationSeconds: seconds,
          path: draft.voiceNotePath,
          fromUser: true,
          sentAt: now,
        ),
    ];
    _messages.add([..._messages.value, ...sent]);
    _scheduleReply(draft);
  }

  /// The liveness half: the contact starts typing immediately, and the reply
  /// lands after [_replyDelay]. Runs through the action convention (unique
  /// key per send — the entity-suffix idiom — so two quick sends each get a
  /// reply instead of tripping the re-entry guard); auto-disposed with the
  /// viewmodel. `.execute()` is the sanctioned fire-and-forget form for a
  /// builder launched from a non-async method — without it the chain is
  /// lazy and never runs.
  void _scheduleReply(ShowcaseComposerDraftModel draft) {
    final int sendIndex = _messages.value.length;
    _typing.add(true);
    action('conversation.reply.$sendIndex', () async {
      await Future<void>.delayed(_replyDelay);
      if (_messages.isClosed || _typing.isClosed) return;
      _messages.add([..._messages.value, _replyTo(draft)]);
      _typing.add(false);
    }).execute();
  }

  /// Kind-aware fake replies — the thread visibly reacts to WHAT was sent,
  /// not just that something was. The reply copy is seeded; the recording
  /// behind a voice draft is real.
  ShowcaseComposerMessageModel _replyTo(ShowcaseComposerDraftModel draft) {
    final sentAt = DateTime.now();
    if (draft.voiceNoteSeconds case final int seconds) {
      final label =
          '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      return ShowcaseComposerTextMessageModel(
        fromUser: false,
        sentAt: sentAt,
        text: 'Voice note received — $label played back loud and clear. '
            '(Fake reply — the thread\'s contact is seeded.)',
      );
    }
    if (draft.attachments.isNotEmpty) {
      final names = [for (final a in draft.attachments) a.name].join(', ');
      return ShowcaseComposerTextMessageModel(
        fromUser: false,
        sentAt: sentAt,
        text:
            'Got the attachment${draft.attachments.length > 1 ? 's' : ''} — $names. Reviewing now. '
            '(Fake reply — seeded data only.)',
      );
    }
    final reply = _textReplies[_replyCount++ % _textReplies.length];
    return ShowcaseComposerTextMessageModel(
        fromUser: false, sentAt: sentAt, text: reply);
  }

  @override
  void dispose() {
    // A recording still running when the view goes away must not keep the
    // mic hot.
    if (_recorder.isRecording) {
      unawaited(_recorder.cancel().catchError((_) {}));
    }
    _recorderPhase.close();
    _recordingElapsed.close();
    _recordingLevel.close();
    _messages.close();
    _typing.close();
    super.dispose();
  }
}
