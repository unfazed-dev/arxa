// Sheet interactivity contract: the picker sheets opened from the composer
// pills are LIVE — tapping a row pops the sheet and posts the selection
// (model / sandbox mode) through the repository to arxa studio.
import 'dart:async';

import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelBuilder;
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_body.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

class _FakeConversationRepository implements ConversationRepository {
  (String, String)? lastModeCall;
  (String, String, String)? lastSelectCall;
  Map<String, dynamic> directory = const {};

  /// Per-session transcript rows the fake serves (default: empty).
  Map<String, List<ConversationMessage>> transcripts = const {};

  @override
  Future<Map<String, dynamic>> models(String sessionId) async => directory;

  @override
  Future<void> setMode(String sessionId, String mode) async {
    lastModeCall = (sessionId, mode);
  }

  @override
  Future<Map<String, dynamic>> attachment(
          String sessionId, String attachmentId) async =>
      const {};

  @override
  Future<void> send(String sessionId, String text,
      {String mode = 'queue',
      List<({String mediaType, String data})> images = const []}) async {
    lastSendCall = (sessionId, text);
    lastImages = images;
  }

  (String, String)? lastSendCall;
  List<({String mediaType, String data})> lastImages = const [];

  @override
  Future<void> selectModel(String sessionId, String provider, String model) async {
    lastSelectCall = (sessionId, provider, model);
  }

  // Unused by the composer flows under test.
  @override
  String? get lastMode => null;

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
  Stream<ConversationLiveEvent> get liveEvents => const Stream.empty();

  @override
  void startLive() {}

  @override
  DateTime? get lastLiveAt => null;
  @override
  Set<String> get runningIds => const {};
  @override
  TransportService get transport => _NoTransport();
  @override
  Duration get healWait => const Duration(seconds: 1);
  @override
  Future<List<CodeSession>> listSessions() async => const [];
  @override
  Stream<List<CodeSession>> watchSessions() => const Stream.empty();
  @override
  Future<List<ConversationMessage>> transcript(String sessionId) async =>
      transcripts[sessionId] ?? const [];
  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) => const Stream.empty();
  @override
  Future<void> refreshSessions() async {}
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

Widget _host(CodeConversationViewModel viewModel) =>
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ViewModelBuilder<CodeConversationViewModel>.reactive(
        viewModelBuilder: () => viewModel,
        builder: (context, vm, child) => Scaffold(
          body: CodeConversationBody(viewModel: vm),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping a mode row posts the mode and closes the sheet',
      (tester) async {
    final repo = _FakeConversationRepository();
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());
    await tester.pumpWidget(_host(viewModel));

    // The mode pill opens the sheet.
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    expect(find.text('Select mode'), findsOneWidget);
    expect(find.text('Workspace write'), findsOneWidget);

    // THE CONTRACT: the row responds.
    await tester.tap(find.text('Workspace write'));
    await tester.pumpAndSettle();

    expect(find.text('Select mode'), findsNothing,
        reason: 'the sheet pops when a row is tapped');
    expect(repo.lastModeCall, ('s1', 'workspace-write'),
        reason: 'the row posts the mode to the studio');
    expect(viewModel.sessionMode, 'workspace-write');
  });

  testWidgets('tapping a model row posts the selection and closes the sheet',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..directory = const {
        'current': {'provider': 'zai', 'model': 'glm-5.3-flash'},
        // The selectable row id differs from the current model, so the
        // composer pill and the sheet row never share one string.
        'groups': [
          {
            'id': 'zai',
            'name': 'Z.ai',
            'models': [
              {'id': 'kimi-k3', 'name': 'Kimi K3'},
              {'id': 'glm-5.3-flash', 'name': 'GLM-5.3-Flash'},
            ],
          },
        ],
      };
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());
    await tester.pumpWidget(_host(viewModel));

    // The model pill (default label) opens the sheet; loadModels fills it.
    await tester.tap(find.text('glm-5.2'));
    await tester.pumpAndSettle();
    expect(find.text('Select model'), findsOneWidget);
    expect(find.text('kimi-k3'), findsOneWidget);

    await tester.tap(find.text('kimi-k3'));
    await tester.pumpAndSettle();

    expect(find.text('Select model'), findsNothing,
        reason: 'the sheet pops when a row is tapped');
    expect(repo.lastSelectCall, ('s1', 'zai', 'kimi-k3'),
        reason: 'the row posts the model to the studio');
    expect(viewModel.currentModel, 'kimi-k3');
  });

  testWidgets('thinking and tool rows open their content sheets',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:1', seq: 1, sessionId: 's1', role: 'user', text: 'go'),
          const ConversationMessage(
              id: 's1:2',
              seq: 2,
              sessionId: 's1',
              role: 'assistant',
              kind: 'thinking',
              text: 'Let me check the gate.\n\nSecond thought.'),
          const ConversationMessage(
              id: 's1:3',
              seq: 3,
              sessionId: 's1',
              role: 'assistant',
              kind: 'tool',
              toolName: 'ctx_batch_execute',
              toolInput: '{\n  "commands": [\n    "git status"\n  ]\n}',
              text: 'On branch main'),
          const ConversationMessage(
              id: 's1:4',
              seq: 4,
              sessionId: 's1',
              role: 'assistant',
              kind: 'text',
              text: 'Done.'),
        ],
      };
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());
    await tester.pumpWidget(_host(viewModel));
    await viewModel.refresh();
    await tester.pump();

    // The collapsed rows ride the thread between the bubbles.
    expect(find.text('go'), findsOneWidget);
    expect(find.text('Done.'), findsOneWidget);
    expect(find.text('Thought process'), findsOneWidget);
    expect(find.text('Ran Ctx Batch Execute'), findsOneWidget);

    // The thinking row opens the Thought process sheet (paragraph prose).
    await tester.tap(find.text('Thought process'));
    await tester.pumpAndSettle();
    expect(find.text('Let me check the gate.'), findsOneWidget);
    expect(find.text('Second thought.'), findsOneWidget);
    expect(find.text('Input'), findsNothing,
        reason: 'the thinking sheet carries prose, not tool sections');

    // Close (the X), then the tool row opens Input + Output.
    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ran Ctx Batch Execute'));
    await tester.pumpAndSettle();
    expect(find.text('Ctx Batch Execute'), findsOneWidget,
        reason: 'the sheet title is the humanized tool name');
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('On branch main'), findsOneWidget);
    expect(find.text('{\n  "commands": [\n    "git status"\n  ]\n}'), findsOneWidget,
        reason: 'the pretty arguments render verbatim in the mono box');
  });

  testWidgets('a tool row with no recorded output says so honestly',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..transcripts = {
        's1': [
          const ConversationMessage(
              id: 's1:1',
              seq: 1,
              sessionId: 's1',
              role: 'assistant',
              kind: 'tool',
              toolName: 'read',
              text: '',
              toolInput: '{ "path": "x.ts" }'),
        ],
      };
    final viewModel = CodeConversationViewModel(
        's1', repo, _FakeApprovalsRepository(), () => Future.value());
    await tester.pumpWidget(_host(viewModel));
    await viewModel.refresh();
    await tester.pump();

    await tester.tap(find.text('Ran Read'));
    await tester.pumpAndSettle();
    expect(find.text('No output was recorded.'), findsOneWidget);
    expect(find.text('Output'), findsNothing);
  });
}
