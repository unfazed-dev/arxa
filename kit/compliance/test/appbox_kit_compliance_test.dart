import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appbox_kit_compliance/appbox_kit_testing.dart';

AppBoxKitComplianceDocument _doc({
  String id = 'privacy-policy',
  AppBoxKitComplianceDocumentKind kind = AppBoxKitComplianceDocumentKind.privacyPolicy,
  String version = '2026-07-01',
  bool requiresExplicitAcceptance = true,
}) =>
    AppBoxKitComplianceDocument(
      id: id,
      kind: kind,
      version: version,
      title: 'Doc $id',
      source: AppBoxKitComplianceSource.remote(Uri.parse('https://example.com/$id')),
      effectiveDate: DateTime(2026, 7, 1),
      requiresExplicitAcceptance: requiresExplicitAcceptance,
    );

void main() {
  group('AppBoxKitComplianceDocument & source', () {
    test('value equality over all fields', () {
      expect(_doc(), _doc());
      expect(_doc(version: '1.0.0') == _doc(version: '1.0.1'), isFalse);
    });

    test('sealed source equality', () {
      expect(AppBoxKitComplianceSource.remote(Uri.parse('https://a')),
          AppBoxKitComplianceSource.remote(Uri.parse('https://a')));
      expect(const AppBoxKitComplianceSource.inline('body'),
          const AppBoxKitComplianceSource.inline('body'));
      expect(
        AppBoxKitComplianceSource.remote(Uri.parse('https://a')) ==
            const AppBoxKitComplianceSource.inline('body'),
        isFalse,
      );
    });
  });

  group('AppBoxKitComplianceRegistry', () {
    test('register / byId', () {
      final registry = AppBoxKitComplianceRegistry()..register(_doc());
      expect(registry.byId('privacy-policy'), _doc());
      expect(registry.byId('missing'), isNull);
    });

    test('currentFor returns the most-recently-registered of a kind', () {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'p-v1', version: '1'))
        ..register(_doc(id: 'p-v2', version: '2'));
      expect(registry.currentFor(AppBoxKitComplianceDocumentKind.privacyPolicy)?.id,
          'p-v2');
      expect(registry.currentFor(AppBoxKitComplianceDocumentKind.eula), isNull);
    });

    test('all preserves registration order', () {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'a', kind: AppBoxKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'b', kind: AppBoxKitComplianceDocumentKind.privacyPolicy));
      expect(registry.all.map((d) => d.id), ['a', 'b']);
    });

    test('re-registering an id replaces in place, keeping position', () {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'a', kind: AppBoxKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'b', kind: AppBoxKitComplianceDocumentKind.privacyPolicy))
        ..register(_doc(
            id: 'a',
            kind: AppBoxKitComplianceDocumentKind.termsOfService,
            version: '2'));
      expect(registry.all.map((d) => d.id), ['a', 'b']);
      expect(registry.byId('a')?.version, '2');
    });

    test('currentDocuments is one-per-kind in first-seen order', () {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: AppBoxKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp1', kind: AppBoxKitComplianceDocumentKind.privacyPolicy, version: '1'))
        ..register(_doc(id: 'pp2', kind: AppBoxKitComplianceDocumentKind.privacyPolicy, version: '2'));
      expect(registry.currentDocuments.map((d) => d.id), ['tos', 'pp2']);
    });

    test('two documents sharing a kind collapse to the latest (custom case)', () {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'custom-a', kind: AppBoxKitComplianceDocumentKind.custom))
        ..register(_doc(id: 'custom-b', kind: AppBoxKitComplianceDocumentKind.custom));
      // Both are in `all`, but the gate sees only the latest per kind.
      expect(registry.all, hasLength(2));
      expect(registry.currentDocuments.map((d) => d.id), ['custom-b']);
    });
  });

  group('AppBoxKitConsentRecord', () {
    test('value equality', () {
      final at = DateTime(2026, 7, 1);
      final a = AppBoxKitConsentRecord(
          documentId: 'p',
          documentVersion: '1',
          acceptedAt: at,
          method: AppBoxKitConsentMethod.explicitTap,
          appVersion: '1.0.0');
      final b = AppBoxKitConsentRecord(
          documentId: 'p',
          documentVersion: '1',
          acceptedAt: at,
          method: AppBoxKitConsentMethod.explicitTap,
          appVersion: '1.0.0');
      expect(a, b);
      expect(a.isWithdrawal, isFalse);
    });
  });

  group('InMemoryAppBoxKitConsentStore', () {
    late InMemoryAppBoxKitConsentStore store;
    setUp(() => store = InMemoryAppBoxKitConsentStore());

    AppBoxKitConsentRecord rec({
      String documentId = 'p',
      String version = '1',
      String? userId,
      DateTime? at,
      AppBoxKitConsentMethod method = AppBoxKitConsentMethod.explicitTap,
    }) =>
        AppBoxKitConsentRecord(
          documentId: documentId,
          documentVersion: version,
          userId: userId,
          acceptedAt: at ?? DateTime(2026, 7, 1),
          method: method,
          appVersion: '1.0.0',
        );

    test('record then latestFor returns it', () async {
      await store.record(rec());
      expect((await store.latestFor('p'))?.documentVersion, '1');
    });

    test('withdraw appends a withdrawal that latestFor surfaces', () async {
      await store.record(rec());
      await store.withdraw(
          documentId: 'p',
          documentVersion: '1',
          appVersion: '1.0.0',
          at: DateTime(2026, 7, 2));
      final latest = await store.latestFor('p');
      expect(latest?.method, AppBoxKitConsentMethod.withdrawn);
      expect(latest?.isWithdrawal, isTrue);
    });

    test('anonymous and per-user tracks are separate (both directions)',
        () async {
      await store.record(rec(userId: 'u1'));
      // Anonymous query must not see u1's record.
      expect(await store.latestFor('p'), isNull);
      expect(await store.latestFor('p', userId: 'u1'), isNotNull);
      // And a user query must not see an anonymous record.
      await store.record(rec(at: DateTime(2026, 7, 3)));
      expect(await store.latestFor('p', userId: 'u2'), isNull);
      expect((await store.latestFor('p'))?.userId, isNull);
    });

    test('history filters by track and document, oldest first', () async {
      await store.record(rec(at: DateTime(2026, 7, 1)));
      await store.record(rec(documentId: 'q', at: DateTime(2026, 7, 2)));
      await store.record(rec(userId: 'u1', at: DateTime(2026, 7, 3)));
      final anon = await store.history();
      expect(anon.map((r) => r.documentId), ['p', 'q']);
      final anonP = await store.history(documentId: 'p');
      expect(anonP.map((r) => r.documentId), ['p']);
      final u1 = await store.history(userId: 'u1');
      expect(u1, hasLength(1));
    });

    test('latest-wins tie-breaks equal timestamps by insertion order',
        () async {
      final at = DateTime(2026, 7, 1);
      await store.record(rec(version: 'first', at: at));
      await store.record(rec(version: 'second', at: at));
      expect((await store.latestFor('p'))?.documentVersion, 'second');
    });
  });

  group('AppBoxKitConsentService.statusFor', () {
    late AppBoxKitComplianceRegistry registry;
    late InMemoryAppBoxKitConsentStore store;
    late AppBoxKitConsentService service;

    setUp(() {
      registry = AppBoxKitComplianceRegistry();
      store = InMemoryAppBoxKitConsentStore();
      service = AppBoxKitConsentService(store: store, registry: registry);
    });
    tearDown(() => service.dispose());

    test('notRequired when the document does not require acceptance', () async {
      final doc = _doc(requiresExplicitAcceptance: false);
      // Even with a record present, status is notRequired.
      await service.accept(doc,
          appVersion: '1.0.0', method: AppBoxKitConsentMethod.implicitContinue);
      expect(await service.statusFor(doc), const AppBoxKitConsentStatus.notRequired());
    });

    test('neverAccepted with no record', () async {
      expect(await service.statusFor(_doc()),
          const AppBoxKitConsentStatus.neverAccepted());
    });

    test('accepted when the version matches exactly', () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0');
      expect(await service.statusFor(doc), const AppBoxKitConsentStatus.accepted());
    });

    test('acceptedOutdatedVersion on any string mismatch (no semver)',
        () async {
      await service.accept(_doc(version: '1.0.0'), appVersion: '1.0.0');
      final status = await service.statusFor(_doc(version: '1.0.1'));
      expect(status,
          const AppBoxKitConsentStatus.acceptedOutdatedVersion('1.0.0'));
      expect((status as AppBoxKitConsentAcceptedOutdatedVersion).acceptedVersion,
          '1.0.0');
    });

    test('withdrawn when the latest action is a withdrawal', () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 1));
      await service.withdraw(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 2));
      expect(await service.statusFor(doc), const AppBoxKitConsentStatus.withdrawn());
    });

    test('latest-wins: accept -> withdraw -> re-accept ends accepted',
        () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 1));
      await service.withdraw(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 2));
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 3));
      expect(await service.statusFor(doc), const AppBoxKitConsentStatus.accepted());
    });

    test('status is scoped to the service user track', () async {
      final doc = _doc(version: '1.0.0');
      final anon = AppBoxKitConsentService(store: store, registry: registry);
      final u1 = AppBoxKitConsentService(store: store, registry: registry, userId: 'u1');
      await u1.accept(doc, appVersion: '1.0.0');
      expect(await u1.statusFor(doc), const AppBoxKitConsentStatus.accepted());
      expect(await anon.statusFor(doc), const AppBoxKitConsentStatus.neverAccepted());
      await anon.dispose();
      await u1.dispose();
    });
  });

  group('outstandingDocuments', () {
    test('lists unsatisfied required docs in registry order, skipping notRequired',
        () async {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: AppBoxKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp', kind: AppBoxKitComplianceDocumentKind.privacyPolicy))
        ..register(_doc(
            id: 'cookie',
            kind: AppBoxKitComplianceDocumentKind.cookiePolicy,
            requiresExplicitAcceptance: false));
      final store = InMemoryAppBoxKitConsentStore();
      final service = AppBoxKitConsentService(store: store, registry: registry);
      await service.accept(registry.byId('tos')!, appVersion: '1.0.0');
      final outstanding = await service.outstandingDocuments();
      expect(outstanding.map((d) => d.id), ['pp']);
      await service.dispose();
    });
  });

  group('AppBoxKitConsentService.statusChanges', () {
    test('accept emits an accepted status change on the broadcast stream',
        () async {
      final registry = AppBoxKitComplianceRegistry();
      final store = InMemoryAppBoxKitConsentStore();
      final service = AppBoxKitConsentService(store: store, registry: registry);
      final events = <AppBoxKitConsentStatusChange>[];
      final sub = service.statusChanges.listen(events.add);
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0');
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.document, doc);
      expect(events.single.status, const AppBoxKitConsentStatus.accepted());
      await sub.cancel();
      await service.dispose();
    });
  });

  group('AppBoxKitConsentGate', () {
    test('blocked lists outstanding docs in registry order', () async {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: AppBoxKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp', kind: AppBoxKitComplianceDocumentKind.privacyPolicy));
      final service =
          AppBoxKitConsentService(store: InMemoryAppBoxKitConsentStore(), registry: registry);
      final result = await AppBoxKitConsentGate(service).evaluate();
      expect(result.canProceed, isFalse);
      expect(result, isA<AppBoxKitConsentGateBlocked>());
      expect((result as AppBoxKitConsentGateBlocked).outstanding.map((d) => d.id),
          ['tos', 'pp']);
      await service.dispose();
    });

    test('allowed when nothing is outstanding', () async {
      final registry = AppBoxKitComplianceRegistry()
        ..register(_doc(id: 'pp', kind: AppBoxKitComplianceDocumentKind.privacyPolicy));
      final service =
          AppBoxKitConsentService(store: InMemoryAppBoxKitConsentStore(), registry: registry);
      await service.accept(registry.byId('pp')!, appVersion: '1.0.0');
      final result = await AppBoxKitConsentGate(service).evaluate();
      expect(result.canProceed, isTrue);
      expect(result, const AppBoxKitConsentGateResult.allowed());
      await service.dispose();
    });
  });

  group('AppBoxKitLicensesService', () {
    test('collect maps packages and paragraph text via the injected source',
        () async {
      final service = FakeAppBoxKitLicensesService(const [
        LicenseEntryWithLineBreaks(['my_pkg'], 'MIT license text'),
      ]);
      final entries = await service.collect();
      expect(entries.single.packages, ['my_pkg']);
      expect(entries.single.paragraphs.join(' '), contains('MIT'));
    });

    test('byPackage groups an entry under each of its packages, sorted',
        () async {
      final service = FakeAppBoxKitLicensesService(const [
        LicenseEntryWithLineBreaks(['zeta', 'alpha'], 'shared license'),
        LicenseEntryWithLineBreaks(['alpha'], 'alpha only'),
      ]);
      final grouped = await service.byPackage();
      expect(grouped.keys.toList(), ['alpha', 'zeta']);
      expect(grouped['alpha'], hasLength(2));
      expect(grouped['zeta'], hasLength(1));
    });

    test('AppBoxKitLicenseEntry value equality', () {
      expect(
        const AppBoxKitLicenseEntry(packages: ['a'], paragraphs: ['x']),
        const AppBoxKitLicenseEntry(packages: ['a'], paragraphs: ['x']),
      );
      expect(
        const AppBoxKitLicenseEntry(packages: ['a'], paragraphs: ['x']) ==
            const AppBoxKitLicenseEntry(packages: ['a'], paragraphs: ['y']),
        isFalse,
      );
    });
  });
}
