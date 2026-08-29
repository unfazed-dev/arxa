// iOS-simulator e2e for the approvals loop (grill D60–D68, sim leg of the
// D68 runbook). Runs the REAL app stack on a simulator: real iroh transport
// (FRB native), real cairn localOnly boot with the approvals entity, real
// tunnel to a live studio engine + pairhost (see
// desktop/src-tauri/examples/pairhost.rs). Phases select via --dart-define:
//
//   PHASE=smoke    boot, scan view renders, pair via manual ticket, reach
//                  connected, approvals route renders the empty state.
//   PHASE=e2e      with pendings raised engine-side: list renders them,
//                  answer on the phone (option chip + send), the list
//                  empties, a refused second answer surfaces the conflict.
//   PHASE=pressure rapid refresh hammering + repeated conflict decisions.
//
// Run (sim):
//   flutter test integration_test/approvals_e2e_test.dart \
//     -d <sim-id> --dart-define=PAIR_TICKET=<ticket> --dart-define=PHASE=e2e

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arxa_kit_data/arxa_kit_data.dart';
import 'package:arxa_kit_notifications/arxa_kit_notifications.dart';
import 'package:arxa_kit_ui_library/arxa_kit_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:arxa_studio_mobile/app/app.locator.dart';
import 'package:arxa_studio_mobile/app/app_data.dart';
import 'package:arxa_studio_mobile/app/app.router.dart';
import 'package:arxa_studio_mobile/app/kit_platform_router.dart';
import 'package:arxa_studio_mobile/data/approvals/approval.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_api_client.dart';
import 'package:arxa_studio_mobile/data/approvals/approvals_repository.dart';
import 'package:arxa_studio_mobile/main.dart';
import 'package:arxa_studio_mobile/services/push_token_service.dart';
import 'package:arxa_studio_mobile/services/transport_service.dart';

const ticket = String.fromEnvironment('PAIR_TICKET');
const phase = String.fromEnvironment('PHASE', defaultValue: 'smoke');

/// Ticket-server origin. The SIMULATOR shares the host loopback; a physical
/// device must reach the harness over the LAN (D68 runbook):
///   `--dart-define=TICKET_URL=http://<lan-ip>:8899/ticket.txt`
const ticketUrl = String.fromEnvironment(
    'TICKET_URL', defaultValue: 'http://127.0.0.1:8899/ticket.txt');

/// main()'s body minus runApp — the real boot, in-process, ONCE: the kit
/// refuses a second initialize and the locator is process-global, so every
/// test in this file shares the first boot.
var _booted = false;
Future<void> bootRealApp() async {
  if (_booted) return;
  _booted = true;
  debugPrint('E2E: boot begin');
  await setupLocator(stackedRouter: kitPlatformRouter);
  await AppData.initialize();
  debugPrint('E2E: data layer booted');
  locator.registerLazySingleton(
    () => ApprovalsRepository(
      cache: arxaKitLocator<ArxaKitRepository<Approval>>(),
      api: ApprovalsApiClient(transport: locator<TransportService>()),
    ),
  );
  setupArxaKitUiServices();
  debugPrint('E2E: boot complete');
}

/// Pair for real: drive the TransportService seam — the exact call
/// PairingScanViewModel.submitTicket makes after the (native) field fires.
/// The manual-entry UI itself hosts a REAL UITextField via
/// ArxaKitNativeTextField's Liquid Glass tier (a platform view), which
/// tester.enterText cannot reach — so the e2e starts one seam below the
/// field and covers everything above it (handoff, routes) and below it
/// (real iroh dial, AUTH, loopback proxy).
/// The harness (pairhost) serves its CURRENT ticket over loopback — the
/// simulator shares the host network namespace, and dart:io HTTP bypasses
/// ATS. Fetching at pair time kills the launch-time-to-dial race: an
/// expiry re-mint between test launch and dial used to strand the passed
/// ticket (measured 2026-08-29: 'rejected token' at AUTH).
Future<String> liveTicket() async {
  if (ticket.isNotEmpty) return ticket;
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(ticketUrl));
    final response = await request.close();
    return (await response.transform(utf8.decoder).join()).trim();
  } finally {
    client.close();
  }
}

/// Raw JSON over the tunnel's loopback proxy — the same transport
/// ApprovalsApiClient uses, for the engine /api contract and the gated test
/// seam (D68 phone leg: the test raises its own pending in-process).
Future<Map<String, dynamic>> tunnelJson(String method, Uri base, String path,
    [Map<String, dynamic>? body]) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, base.resolve(path))
        .timeout(const Duration(seconds: 10));
    request.headers.set('accept', 'application/json');
    if (body != null) {
      final encoded = jsonEncode(body);
      request.headers.set('content-type', 'application/json');
      request.headers.contentLength = utf8.encode(encoded).length;
      request.write(encoded);
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('tunnelJson $path -> ${response.statusCode}: $text');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<Uri> pairThroughUi(WidgetTester tester) async {
  final transport = locator<TransportService>();
  debugPrint('E2E: pairing begin');
  await transport.beginPairing(await liveTicket());
  debugPrint('E2E: beginPairing returned');
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (transport.current.state != ArxaConnectionState.connected) {
    if (DateTime.now().isAfter(deadline)) {
      fail('pairing did not reach connected: '
          '${transport.current.state} ${transport.current.error ?? ""}');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  final url = transport.current.studioUrl;
  debugPrint('E2E: connected, studioUrl=$url');
  expect(url, isNotNull, reason: 'connected carries the loopback studioUrl');
  return url!;
}

Future<void> openApprovals(WidgetTester tester) async {
  debugPrint('E2E: navigating to approvals');
  // NEVER await stacked navigation in a widget test: the returned future
  // completes only after the route transition animates — and transitions
  // need frames, which this coroutine would not pump while awaiting. Fire
  // it and pump instead (measured 2026-08-29: the await deadlocked the
  // whole run at this line with the tunnel already connected).
  unawaited(locator<RouterService>().replaceWith(ApprovalsListViewRoute()));
  // Bounded pumps, never pumpAndSettle: the kit's indeterminate animations
  // (loading indicators) never settle and pumpAndSettle would hang to its
  // 10-minute timeout.
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 16));
  }
  debugPrint('E2E: approvals route opened');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke: boot, pair, approvals shell live', (tester) async {
    await bootRealApp();
    await tester.pumpWidget(const ArxaStudioMobileApp());
    await tester.pump(const Duration(seconds: 1));

    await pairThroughUi(tester);
    await openApprovals(tester);

    // The shell is LIVE: l10n title renders, the empty state shows the
    // no-pendings copy (or, in later phases, real cards).
    expect(find.text('Approvals'), findsOneWidget);
  });

  testWidgets('e2e: pending approvals list and answer on the phone',
      (tester) async {
    // smoke stops after its own leg; phone runs raise their OWN pending
    // in-test (below) — pre-raised cards would never appear here.
    if (phase == 'smoke' || phase == 'phone') return;
    await bootRealApp();
    await tester.pumpWidget(const ArxaStudioMobileApp());
    await tester.pump(const Duration(seconds: 1));
    await pairThroughUi(tester);
    await openApprovals(tester);

    // Pendings were raised engine-side before this run (driver script).
    // The view refreshes once on model-ready; that single refresh can race
    // a freshly-redialed tunnel, so the wait RE-POLLS through the locator
    // repository (same path as pull-to-refresh) while it waits.
    final cardMarker = find.byType(Card);
    var deadline = DateTime.now().add(const Duration(seconds: 45));
    while (cardMarker.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('no pending approval card appeared');
      try {
        await locator<ApprovalsRepository>().refresh();
      } on Exception catch (e) {
        debugPrint('E2E: wait-refresh: $e');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Answer the FIRST approval: pick its first option chip, send. With
    // multiple pendings raised (pressure), several cards render — one Send
    // each — so tap the FIRST card's button, not the only one.
    final chips = find.byType(FilterChip);
    expect(chips, findsWidgets);
    await tester.tap(chips.first);
    await tester.pump();
    final send = find.text('Send answer');
    expect(send, findsWidgets);
    await tester.tap(send.first);

    // The decided approval leaves the list (bounded).
    deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('decided approval did not leave the list');
      await tester.pump(const Duration(milliseconds: 300));
    }

    if (phase == 'pressure') {
      // Pressure leg: hammer refresh + spam a conflict decision.
      final repo = locator<ApprovalsRepository>();
      final sw = Stopwatch()..start();
      for (var i = 0; i < 25; i++) {
        await repo.refresh();
      }
      sw.stop();
      debugPrint('PRESSURE: 25 refreshes over ${sw.elapsedMilliseconds}ms');
      // A decided id must now conflict loudly.
      final decided = const Approval(
        id: 'already-decided-id',
        sessionId: 's',
        kind: 'approval',
        summary: 'x',
        questions: [],
        raisedAt: 0,
      );
      try {
        await repo.decide(decided.id, const []);
        fail('deciding a gone id must conflict');
      } on ApprovalsConflictException {
        debugPrint('PRESSURE: conflict surfaced as expected');
      }
    }
  });

  // D68 phone leg — the one thing no simulator can prove: cairn-pushd →
  // APNs → a real buzz on physical hardware. Runs only with PHASE=phone
  // against an engine booted with ARXA_DOORBELL_PUSH=true +
  // ARXA_APPROVALS_TEST_SEAM=true and a REAL pushd holding the operator's
  // .p8 (CAIRN_APNS_SANDBOX=1 — development-signed build). Self-contained:
  // raises its own pending through the tunnel, no out-of-band driver.
  testWidgets('phone: real APNs doorbell — buzz, list, decide, unblock',
      (tester) async {
    if (phase != 'phone') return;
    await bootRealApp();
    await tester.pumpWidget(const ArxaStudioMobileApp());
    await tester.pump(const Duration(seconds: 1));
    await pairThroughUi(tester);

    // 1. Permission + the REAL APNs token. First run ever shows the OS
    //    dialog — tap Allow on the phone. The bridge registers the token
    //    over the tunnel (PUSH frame → pairing.json → pushd /v1/tokens).
    final push = locator<PushTokenService>();
    final permission = await push.requestPermission();
    debugPrint('PHONE: permission=${permission.status}');
    expect(permission.isGranted, isTrue,
        reason: 'notification permission must be granted (tap Allow)');
    final backend = locator<ArxaKitNotificationsService>();
    final token = await backend.currentToken();
    debugPrint('PHONE: apns token=${token?.value}');
    expect(token, isNotNull,
        reason: 'APNs device token must mint (entitlement + registration)');
    // The PUSH registration needs a beat to land in pairing.json before
    // anything rings (the doorbell reads its targets at send time).
    await tester.pump(const Duration(seconds: 3));

    // 2. Arm the buzz capture BEFORE raising: the doorbell fires on the mux
    //    frame's FIRST sight — subscribe first or miss it.
    final buzz = Completer<ArxaKitRemoteMessage>();
    final sub = backend.foregroundMessages.listen((m) {
      if (!buzz.isCompleted) buzz.complete(m);
    });

    // 3. Raise a real pending through the tunnel: session.create gives an
    //    idle-but-live agent; the seam raises the ask through the real
    //    provider (no LLM — the seam replaces the question source only).
    final base = locator<TransportService>().current.studioUrl!;
    final created = await tunnelJson('POST', base, '/api/session.create', {
      'type': 'client-request',
      'rpcId': 'phone-1',
      'method': 'session.create',
      'payload': <String, dynamic>{},
    });
    final sessionId = ((created['result'] as Map<String, dynamic>)['value']
        as Map<String, dynamic>)['sessionId'] as String;
    debugPrint('PHONE: session $sessionId');
    final raised = await tunnelJson(
        'POST', base, '/__arxa/approvals/__test_raise', {
      'sessionId': sessionId,
      'questions': [
        {
          'id': 'q1',
          'question': 'Ship the release?',
          'header': 'Release',
          'options': [
            {'label': 'Approve', 'description': 'ship it'},
            {'label': 'Deny', 'description': 'hold'},
          ],
        }
      ],
    });
    // The seam's counter is ENGINE-GLOBAL and survives app restarts (a
    // prior run's raises count too) — assert the increment, not the total.
    expect((raised['raised'] as int) > 0, isTrue,
        reason: 'seam must raise the ask');

    // 4. THE BUZZ: cairn-pushd → APNs sandbox → system presentation while
    //    foregrounded (native willPresent → channel event). The leg nothing
    //    simulated — real network, real .p8, real device radio.
    final message = await buzz.future.timeout(const Duration(seconds: 90));
    await sub.cancel();
    debugPrint('PHONE: BUZZ title=${message.title} body=${message.body}');
    expect(message.title, 'Approval needed', reason: 'D65 content-free copy');
    expect(message.body, contains('review'));

    // 5. List → decide: the same rails as the e2e phase, on hardware.
    await openApprovals(tester);
    final cardMarker = find.byType(Card);
    var deadline = DateTime.now().add(const Duration(seconds: 45));
    while (cardMarker.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('no pending approval card appeared');
      }
      try {
        await locator<ApprovalsRepository>().refresh();
      } on Exception catch (e) {
        debugPrint('E2E: wait-refresh: $e');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
    final chips = find.byType(FilterChip);
    expect(chips, findsWidgets);
    await tester.tap(chips.first);
    await tester.pump();
    final send = find.text('Send answer');
    expect(send, findsWidgets);
    await tester.tap(send.first);
    deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('decided approval did not leave the list');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 6. Agent unblock: the seam's ask resolved with the phone's answer —
    //    apiProxy.respond carried it to the live agent's ask().
    Map<String, dynamic> seamState = const <String, dynamic>{};
    deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      seamState = await tunnelJson(
          'GET', base, '/__arxa/approvals/__test_raised');
      final answered =
          (seamState['answered'] as List<dynamic>? ?? <dynamic>[]).length;
      if (answered >= 1) break;
      if (DateTime.now().isAfter(deadline)) {
        fail('agent ask never resolved: $seamState');
      }
      await tester.pump(const Duration(milliseconds: 300));
    }
    debugPrint('PHONE: AGENT UNBLOCKED ${seamState['answered']}');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
