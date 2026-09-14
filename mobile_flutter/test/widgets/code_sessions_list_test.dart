// The sessions list widget: the engine's live-turn flag renders as the
// row's pulsing green dot, and the leading (newest) tile carries the
// steady last-active marker when idle.
import 'dart:async';

import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_sessions/code_sessions_body.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_sessions/code_sessions_viewmodel.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart'
    show ViewModelBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepository implements ConversationRepository {
  List<CodeSession> sessionRows = const [];
  Set<String> runningRows = const {};

  @override
  Set<String> get runningIds => runningRows;
  @override
  String? get lastMode => null;
  @override
  Duration get healWait => const Duration(seconds: 1);
  @override
  TransportService get transport => FakeTransportService();
  @override
  Future<List<CodeSession>> listSessions() async {
    final rows = [...sessionRows]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return rows;
  }

  @override
  Future<void> refreshSessions() async {}
  @override
  Future<List<ConversationMessage>> transcript(String sessionId) async =>
      const [];
  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) =>
      const Stream.empty();
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
    String sessionId,
    String line,
  ) async => (kind: 'success', text: '');
  @override
  Future<String> exportTranscript(String sessionId, String savePath) async =>
      savePath;
  @override
  Future<Map<String, dynamic>> models(String sessionId) async => const {};
  @override
  Future<void> selectModel(
    String sessionId,
    String provider,
    String model,
  ) async {}
  @override
  Future<void> setMode(String sessionId, String mode) async {}
  @override
  Future<Map<String, dynamic>> attachment(
    String sessionId,
    String attachmentId,
  ) async => const {};
  @override
  Future<void> send(
    String sessionId,
    String text, {
    String mode = 'queue',
    List<({String mediaType, String data})> images = const [],
  }) async {}
  @override
  Future<void> refreshSession(String sessionId) async {}
}

Widget _host(CodeSessionsViewModel viewModel) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: ViewModelBuilder<CodeSessionsViewModel>.reactive(
    viewModelBuilder: () => viewModel,
    builder: (context, vm, child) =>
        Scaffold(body: CodeSessionsBody(viewModel: vm)),
  ),
);

void main() {
  testWidgets('a live session shows the active dot, an idle one does not', (
    tester,
  ) async {
    final repo = _FakeRepository()
      ..sessionRows = [
        const CodeSession(
          id: 's-idle',
          title: 'Idle one',
          dshSessionId: 'arxa-s-idle',
          updatedAt: 5,
        ),
        const CodeSession(
          id: 's-live',
          title: 'Live one',
          dshSessionId: 'arxa-s-live',
          updatedAt: 4,
        ),
      ]
      ..runningRows = {'arxa-s-live'};
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    await tester.pumpWidget(_host(viewModel));
    await viewModel.refresh();
    await tester.pump();

    expect(find.text('Live one'), findsOneWidget);
    expect(find.text('Idle one'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('running-dot')),
      findsOneWidget,
      reason: 'exactly the live-turn session carries the pulsing dot',
    );

    // The flag turns over with the next pull — the pulse follows the set,
    // and the leading tile keeps the steady last-active marker.
    repo.runningRows = const {};
    await viewModel.refresh();
    await tester.pump();
    expect(find.byKey(const ValueKey('running-dot')), findsNothing);
    expect(
      find.byKey(const ValueKey('last-active-dot')),
      findsOneWidget,
      reason: 'the newest tile stays marked as the last-active session',
    );
  });

  testWidgets('the list renders newest-first (most recent on top)', (
    tester,
  ) async {
    final repo = _FakeRepository()
      ..sessionRows = [
        const CodeSession(id: 'a', title: 'Older', updatedAt: 100),
        const CodeSession(id: 'b', title: 'Newer', updatedAt: 200),
      ];
    final viewModel = CodeSessionsViewModel(repo, () => Future.value());
    await tester.pumpWidget(_host(viewModel));
    await viewModel.refresh();
    await tester.pump();

    final titles = [
      tester.widget<Text>(find.text('Newer')).data,
      tester.widget<Text>(find.text('Older')).data,
    ];
    final newerTop =
        tester.getTopLeft(find.text('Newer')).dy <
        tester.getTopLeft(find.text('Older')).dy;
    expect(titles, isNotEmpty);
    expect(
      newerTop,
      isTrue,
      reason: 'the most recently updated session leads the list',
    );
  });
}
