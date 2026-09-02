// The composer's Add-context sheet ('+'): opens with the Claude-style
// tiles + recent-photos row, and every control stages real content.
import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_media.dart';
import 'package:arxa_studio_mobile/data/conversation/conversation_repository.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart' show ViewModelBuilder;
import 'package:arxa_studio_mobile/l10n/app_localizations.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_body.dart';
import 'package:arxa_studio_mobile/ui/views/code_shell/code_conversation/code_conversation_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:lucide_flutter/lucide_flutter.dart';

// A repository that records staged sends (the media seam is what the sheet
// touches, so the repository stays a passive recorder here).
class _FakeConversationRepository implements ConversationRepository {
  (String, String)? lastModeCall;
  (String, String, String)? lastSelectCall;
  Map<String, dynamic> directory = const {};

  @override
  Future<Map<String, dynamic>> models(String sessionId) async => directory;
  @override
  Future<void> setMode(String sessionId, String mode) async {
    lastModeCall = (sessionId, mode);
  }
  @override
  Future<void> selectModel(String sessionId, String provider, String model) async {
    lastSelectCall = (sessionId, provider, model);
  }

  // Unused by the sheet flows under test.
  @override
  String? get lastMode => null;

  List<EngineCommand> palette = const [];
  String? lastCommandLine;

  @override
  Future<List<EngineCommand>> commands(String sessionId) async => palette;

  @override
  Future<({String kind, String text})> runCommand(
          String sessionId, String line) async {
    lastCommandLine = line;
    return (kind: 'success', text: 'Compacted 3 history items.');
  }

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
  Future<List<ConversationMessage>> transcript(String sessionId) async => const [];
  @override
  Stream<List<ConversationMessage>> watchTranscript(String sessionId) => const Stream.empty();
  @override
  Future<void> refreshSessions() async {}
  @override
  Future<void> refreshSession(String sessionId) async {}
  @override
  Future<void> send(String sessionId, String text,
          {String mode = 'queue',
          List<({String mediaType, String data})> images = const []}) async {}
  @override
  Future<Map<String, dynamic>> attachment(
          String sessionId, String attachmentId) async =>
      const {};
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

/// A media seam whose pickers hand back scripted files — no plugins.
class _ScriptedMedia extends ConversationMedia {
  _ScriptedMedia(this.next);
  final XFile? next;
  @override
  bool get hasCamera => true;
  @override
  Future<XFile?> capturePhoto() async => next;
  @override
  Future<XFile?> pickPhoto() async => next;
  @override
  Future<XFile?> pickFile() async => next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the + opens the Add context sheet with wired tiles',
      (tester) async {
    final repo = _FakeConversationRepository();
    final viewModel = CodeConversationViewModel('s1', repo,
        _FakeApprovalsRepository(), () => Future.value(),
        _ScriptedMedia(null));
    await tester.pumpWidget(ViewModelBuilder<CodeConversationViewModel>.
        reactive(
          viewModelBuilder: () => viewModel,
          builder: (context, vm, child) => MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CodeConversationBody(viewModel: vm),
            ),
          ),
        ));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();

    expect(find.text('Add context'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Show recent photos'), findsOneWidget);
    expect(find.text('Connectors'), findsNothing,
        reason: 'the sheet drops the connectors row');
  });

  testWidgets('the + sheet lists the engine command palette and runs one',
      (tester) async {
    final repo = _FakeConversationRepository()
      ..palette = const [
        EngineCommand(name: 'compact',
            description: 'Compact older conversation history'),
        EngineCommand(name: 'feedback',
            description: 'record feedback about this session',
            inputHint: '<text>'),
      ];
    final viewModel = CodeConversationViewModel('s1', repo,
        _FakeApprovalsRepository(), () => Future.value(),
        _ScriptedMedia(null));
    await tester.pumpWidget(ViewModelBuilder<CodeConversationViewModel>.
        reactive(
          viewModelBuilder: () => viewModel,
          builder: (context, vm, child) => MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CodeConversationBody(viewModel: vm),
            ),
          ),
        ));

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();

    // The commands section opens from the blue row and shows the
    // registry palette verbatim — plus the synthesized model row.
    await tester.tap(find.text('Show commands'));
    await tester.pumpAndSettle();

    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('Compact older conversation history'), findsOneWidget);
    expect(find.text('/feedback'), findsOneWidget);
    expect(find.text('<text>'), findsOneWidget);
    expect(find.text('/model'), findsOneWidget,
        reason: 'the model row is synthesized to match the studio list');

    // Running a command rides the engine registry — the line lands on
    // the repository and the sheet closes with the result toast.
    await tester.tap(find.text('/compact'));
    await tester.pumpAndSettle();

    expect(repo.lastCommandLine, '/compact');
    expect(find.text('Compacted 3 history items.'), findsOneWidget,
        reason: 'the engine result text toasts verbatim');
  });
}
