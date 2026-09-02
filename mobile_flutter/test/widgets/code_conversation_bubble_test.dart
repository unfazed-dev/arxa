// Message-bubble contracts: a drag starting on a fitting bubble must scroll
// the transcript (never the bubble's own text scrollable — device fonts leave
// a fractional maxScrollExtent that made it grab drags), and attachment
// thumbnails keep the same 16px screen inset as the text bubble.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_body.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_viewmodel.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class _FakeConversationRepository implements ConversationRepository {
  Map<String, List<ConversationMessage>> transcripts = const {};
  @override
  Future<List<ConversationMessage>> transcript(String sessionId) async =>
      transcripts[sessionId] ?? const [];
  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) =>
      const Stream.empty();
  @override
  Set<String> get runningIds => const {};
  @override
  String? get lastMode => null;
  @override
  Duration get healWait => const Duration(seconds: 1);
  @override
  TransportService get transport => _NoTransport();
  @override
  Future<List<CodeSession>> listSessions() async => const [];
  @override
  Future<void> refreshSessions() async {}
  @override
  Stream<List<CodeSession>> watchSessions() => const Stream.empty();
  @override
  Stream<ConversationLiveEvent> get liveEvents => const Stream.empty();
  @override
  void startLive() {}
  @override
  DateTime? get lastLiveAt => null;
  @override
  Future<List<EngineCommand>> commands(String sessionId) async => const [];
  @override
  Future<({String kind, String text})> runCommand(
          String sessionId, String line) async =>
      (kind: 'success', text: '');
  @override
  Future<String> exportTranscript(String sessionId, String savePath) async =>
      savePath;
  @override
  Future<Map<String, dynamic>> models(String sessionId) async => const {};
  @override
  Future<void> selectModel(String sessionId, String provider, String model) async {}
  @override
  Future<void> setMode(String sessionId, String mode) async {}
  @override
  Future<Map<String, dynamic>> attachment(
          String sessionId, String attachmentId) async =>
      const {};
  @override
  Future<void> send(String sessionId, String text,
      {String mode = 'queue',
      List<({String mediaType, String data})> images = const []}) async {}
  @override
  Future<void> refreshSession(String sessionId) async {}
}

class _NoTransport implements TransportService {
  @override
  ArxaConnectionStatus get current =>
      const ArxaConnectionStatus(ArxaConnectionState.notPaired);
  @override
  Stream<ArxaConnectionStatus> get status => const Stream.empty();
  @override
  Future<bool> hasStoredPairing() async => false;
  @override
  Future<void> beginPairing(String ticket) async {}
  @override
  Future<void> setPushToken(String platform, String token) async {}
  @override
  Future<void> unpair() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeApprovalsRepository implements ApprovalsRepository {
  @override
  TransportService get transport => _NoTransport();
  @override
  Duration get healWait => const Duration(seconds: 1);
  @override
  Future<List<Approval>> list() async => const [];
  @override
  Stream<List<Approval>> watch() => const Stream.empty();
  @override
  Future<void> refresh() async {}
  @override
  Future<void> decide(String id, List<ApprovalAnswer> answers) async {}
}

const _shortBubble = 'short bubble that fits on one line';

Future<CodeConversationViewModel> _pump(
    WidgetTester tester, _FakeConversationRepository repo) async {
  final viewModel = CodeConversationViewModel(
      's1', repo, _FakeApprovalsRepository(), () => Future.value());
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ViewModelBuilder<CodeConversationViewModel>.reactive(
      viewModelBuilder: () => viewModel,
      builder: (context, vm, child) => Scaffold(
        body: CodeConversationBody(viewModel: vm),
      ),
    ),
  ));
  await viewModel.refresh();
  await tester.pump();
  return viewModel;
}


/// The transcript scrollable — the only one with real scrollable extent.
Scrollable _transcriptScrollable(WidgetTester tester) {
  return tester.allWidgets
      .whereType<Scrollable>()
      .firstWhere((s) => s.controller!.position.maxScrollExtent > 100);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a drag starting on a fitting bubble scrolls the transcript, never '
      'the bubble itself', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:x', seq: 1, sessionId: 's1', role: 'user',
              text: _shortBubble),
          // 8 rows: enough to overflow the viewport, few enough that a
          // -120 drag keeps the short bubble mounted (cacheExtent).
          for (var i = 0; i < 8; i++)
            ConversationMessage(
                id: 's1:f$i',
                seq: i + 2,
                sessionId: 's1',
                role: i.isEven ? 'assistant' : 'user',
                text: 'filler message row number $i — enough rows that the '
                    'transcript genuinely overflows and scrolls.'),
        ],
      };
    await _pump(tester, repo);

    final transcript = _transcriptScrollable(tester).controller!.position;
    await tester.drag(find.text(_shortBubble), const Offset(0, -120));
    await tester.pumpAndSettle();

    // ~the drag minus touch slop; plain Text lets a hair more of the
    // drag through than SelectableText's recognizers did.
    expect(transcript.pixels, closeTo(100, 3),
        reason: 'the drag lands on the transcript, not the bubble (-120 minus touch slop)');
    expect(
        find.descendant(
            of: find.text(_shortBubble), matching: find.byType(Scrollable)),
        findsNothing,
        reason: 'a bubble is plain Text — no scrollable of its own exists');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'bubble text carries no editing or selection machinery at all',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:x', seq: 1, sessionId: 's1', role: 'user',
              text: _shortBubble),
        ],
      };
    await _pump(tester, repo);

    // Plain Text — the structural fix for both defects this file used to
    // probe by metrics: no inner scrollable to leave fractional device-
    // font extents, no gesture-selection recognizers to sweep the
    // highlight during scrolls. (The behavioral lock — a hold-then-drag
    // starts no selection, no Copy toolbar — lives in
    // code_conversation_text_selection_test.dart.)
    expect(find.byType(SelectableText), findsNothing);
    expect(
        find.descendant(
            of: find.byType(ListView), matching: find.byType(EditableText)),
        findsNothing);
  });

  testWidgets('attachment thumbnails keep the 16px screen inset',
      (tester) async {
    const text = '[phone rail] attachment smoke test';
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:a', seq: 1, sessionId: 's1', role: 'user',
              text: text,
              images: ['att-1']),
        ],
      };
    await _pump(tester, repo);

    final screenRight = tester.view.physicalSize.width /
        tester.view.devicePixelRatio;
    final thumb = tester.getRect(find.byKey(const ValueKey('thumb-att-1')));
    final bubble = tester.getRect(find.text(text));
    expect(thumb.right, closeTo(screenRight - 16, 0.5),
        reason: 'thumbnails respect the same edge inset as the bubble');
    expect(bubble.right, closeTo(screenRight - 16 - 12, 0.5),
        reason: 'text sits inside the bubble: 16px inset + 12px padding');
  });

  testWidgets(
      'sheet text (thinking prose, tool mono blocks) refuses drag grabs — the sheet scroll is the only scroller',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:t', seq: 1, sessionId: 's1', role: 'assistant',
              kind: 'thinking',
              text: 'A thinking paragraph long enough to matter.'),
          const ConversationMessage(
              id: 's1:r', seq: 2, sessionId: 's1', role: 'assistant',
              kind: 'tool',
              toolName: 'read',
              toolInput: '{ "path": "x.ts" }',
              text: 'the tool output line'),
        ],
      };
    await _pump(tester, repo);

    Finder sheetEditableText() => find.descendant(
        of: find.byType(BottomSheet), matching: find.byType(EditableText));

    // The thinking sheet: its prose text is plain Text — no inner
    // scrollable, no selection recognizers. The sheet's scroll view is
    // the only scroller.
    await tester.tap(find.text('Thought process'));
    await tester.pumpAndSettle();
    expect(sheetEditableText(), findsNothing,
        reason: 'the sheet scroll view, not the text, owns the drag');

    // Close via the sheet's X (lucide), then the tool sheet's mono blocks.
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ran Read'));
    await tester.pumpAndSettle();
    expect(sheetEditableText(), findsNothing,
        reason: 'mono block text is plain Text and never grabs the drag');
  });
}