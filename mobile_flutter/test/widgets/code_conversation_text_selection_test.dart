// Thread text is inert under every gesture. A hold-then-drag on a
// message bubble — how scrolls start while reading — must scroll the
// transcript and must NEVER start a text selection: the selection
// highlight, drag handles, iOS magnifier and Copy toolbar tracking the
// finger are the 'text animates every time I scroll' defect (root cause:
// SelectableText's gesture-selection subsystem, still armed after the
// scroll-physics fixes). The thread and sheets render plain Text.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_body.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_viewmodel.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelBuilder;

class _FakeRepo implements ConversationRepository {
  Map<String, List<ConversationMessage>> transcripts = const {};
  @override Future<List<ConversationMessage>> transcript(String sessionId) async => transcripts[sessionId] ?? const [];
  @override Stream<List<ConversationMessage>> watchTranscript(String sessionId) => const Stream.empty();
  @override Set<String> get runningIds => const {};
  @override String? get lastMode => null;
  @override Duration get healWait => const Duration(seconds: 1);
  @override TransportService get transport => _NoTransport();
  @override Future<List<CodeSession>> listSessions() async => const [];
  @override Future<void> refreshSessions() async {}
  @override Stream<List<CodeSession>> watchSessions() => const Stream.empty();
  @override Stream<ConversationLiveEvent> get liveEvents => const Stream.empty();
  @override void startLive() {}
  @override DateTime? get lastLiveAt => null;
  @override Future<List<EngineCommand>> commands(String sessionId) async => const [];
  @override Future<({String kind, String text})> runCommand(String sessionId, String line) async => (kind: 'success', text: '');
  @override Future<String> exportTranscript(String sessionId, String savePath) async => savePath;
  @override Future<Map<String, dynamic>> models(String sessionId) async => const {};
  @override Future<void> selectModel(String sessionId, String provider, String model) async {}
  @override Future<void> setMode(String sessionId, String mode) async {}
  @override Future<Map<String, dynamic>> attachment(String sessionId, String attachmentId) async => const {};
  @override Future<void> send(String sessionId, String text, {String mode = 'queue', List<({String mediaType, String data})> images = const []}) async {}
  @override Future<void> refreshSession(String sessionId) async {}
}

class _NoTransport implements TransportService {
  @override ArxaConnectionStatus get current => const ArxaConnectionStatus(ArxaConnectionState.notPaired);
  @override Stream<ArxaConnectionStatus> get status => const Stream.empty();
  @override Future<bool> hasStoredPairing() async => false;
  @override Future<void> beginPairing(String ticket) async {}
  @override Future<void> setPushToken(String platform, String token) async {}
  @override Future<void> unpair() async {}
  @override Future<void> resume() async {}
  @override Future<void> dispose() async {}
}

class _FakeApprovals implements ApprovalsRepository {
  @override TransportService get transport => _NoTransport();
  @override Duration get healWait => const Duration(seconds: 1);
  @override Future<List<Approval>> list() async => const [];
  @override Stream<List<Approval>> watch() => const Stream.empty();
  @override Future<void> refresh() async {}
  @override Future<void> decide(String id, List<ApprovalAnswer> answers) async {}
}

const _target = 'message number one with enough words to wrap across lines';
const _thought = 'A thinking paragraph long enough to matter.';

Future<CodeConversationViewModel> _pump(WidgetTester tester, _FakeRepo repo) async {
  final viewModel = CodeConversationViewModel('s1', repo, _FakeApprovals(), () => Future.value());
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ViewModelBuilder<CodeConversationViewModel>.reactive(
      viewModelBuilder: () => viewModel,
      builder: (context, vm, child) => Scaffold(body: CodeConversationBody(viewModel: vm)),
    ),
  ));
  await viewModel.refresh();
  await tester.pump();
  return viewModel;
}

Scrollable _transcript(WidgetTester tester) => tester.allWidgets
    .whereType<Scrollable>()
    .firstWhere((s) => s.controller!.position.maxScrollExtent > 100);

/// The defect's exact gesture: finger down, a reading pause past the
/// long-press timeout, then the scroll drag.
Future<void> _holdThenDrag(WidgetTester tester, Finder target) async {
  final g = await tester.startGesture(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 700));
  for (var i = 0; i < 5; i++) {
    await g.moveBy(const Offset(0, -25));
    await tester.pump(const Duration(milliseconds: 60));
  }
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hold-then-scroll on a bubble scrolls the thread and starts no selection (iOS)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repo = _FakeRepo()
        ..transcripts = {
            's1': [
              const ConversationMessage(id: 's1:x', seq: 1, sessionId: 's1', role: 'assistant', text: _target),
              for (var i = 0; i < 8; i++)
                ConversationMessage(
                    id: 's1:f$i',
                    seq: i + 2,
                    sessionId: 's1',
                    role: i.isEven ? 'assistant' : 'user',
                    text: 'filler message row number $i enough rows that the transcript genuinely overflows and scrolls'),
            ],
          };
      await _pump(tester, repo);
      await _holdThenDrag(tester, find.text(_target));

      expect(_transcript(tester).controller!.position.pixels, greaterThan(40),
          reason: 'the transcript scrolls even when the drag began with a hold');
      expect(find.textContaining('Copy'), findsNothing,
          reason: 'no selection toolbar may ever appear from a scroll gesture');
      expect(
          find.descendant(
              of: find.byType(ListView), matching: find.byType(EditableText)),
          findsNothing,
          reason: 'thread bubbles carry no text-editing machinery at all '
              '— plain Text has no selection recognizers to arm');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the sheet text is equally inert under a hold-then-drag', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repo = _FakeRepo()
        ..transcripts = {
            's1': [
              const ConversationMessage(
                  id: 's1:t', seq: 1, sessionId: 's1', role: 'assistant',
                  kind: 'thinking',
                  text: _thought),
            ],
          };
      await _pump(tester, repo);
      await tester.tap(find.text('Thought process'));
      await tester.pumpAndSettle();
      await _holdThenDrag(tester, find.text(_thought));

      expect(find.textContaining('Copy'), findsNothing,
          reason: 'sheet prose never selects from a scroll gesture');
      expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.byType(EditableText)),
          findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}