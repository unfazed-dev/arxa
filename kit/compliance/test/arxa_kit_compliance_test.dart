import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arxa_kit_compliance/arxa_kit_testing.dart';

ArxaKitComplianceDocument _doc({
  String id = 'privacy-policy',
  ArxaKitComplianceDocumentKind kind = ArxaKitComplianceDocumentKind.privacyPolicy,
  String version = '2026-07-01',
  bool requiresExplicitAcceptance = true,
}) =>
    ArxaKitComplianceDocument(
      id: id,
      kind: kind,
      version: version,
      title: 'Doc $id',
      source: ArxaKitComplianceSource.remote(Uri.parse('https://example.com/$id')),
      effectiveDate: DateTime(2026, 7, 1),
      requiresExplicitAcceptance: requiresExplicitAcceptance,
    );

void main() {
  group('ArxaKitComplianceDocument & source', () {
    test('kit.compliance.documents — value equality over all fields', () {
      expect(_doc(), _doc());
      expect(_doc(version: '1.0.0') == _doc(version: '1.0.1'), isFalse);
    });

    test('kit.compliance.documents — sealed source variants compare by value', () {
      expect(ArxaKitComplianceSource.remote(Uri.parse('https://a')),
          ArxaKitComplianceSource.remote(Uri.parse('https://a')));
      expect(const ArxaKitComplianceSource.inline('body'),
          const ArxaKitComplianceSource.inline('body'));
      expect(
        ArxaKitComplianceSource.remote(Uri.parse('https://a')) ==
            const ArxaKitComplianceSource.inline('body'),
        isFalse,
      );
    });
  });

  group('ArxaKitComplianceRegistry', () {
    test('kit.compliance.registry — a registered document resolves by id', () {
      final registry = ArxaKitComplianceRegistry()..register(_doc());
      expect(registry.byId('privacy-policy'), _doc());
      expect(registry.byId('missing'), isNull);
    });

    test('kit.compliance.registry — currentFor returns the most-recently-registered of a kind', () {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'p-v1', version: '1'))
        ..register(_doc(id: 'p-v2', version: '2'));
      expect(registry.currentFor(ArxaKitComplianceDocumentKind.privacyPolicy)?.id,
          'p-v2');
      expect(registry.currentFor(ArxaKitComplianceDocumentKind.eula), isNull);
    });

    test('kit.compliance.registry — all preserves registration order', () {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'a', kind: ArxaKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'b', kind: ArxaKitComplianceDocumentKind.privacyPolicy));
      expect(registry.all.map((d) => d.id), ['a', 'b']);
    });

    test('kit.compliance.registry — re-registering an id replaces in place, keeping position', () {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'a', kind: ArxaKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'b', kind: ArxaKitComplianceDocumentKind.privacyPolicy))
        ..register(_doc(
            id: 'a',
            kind: ArxaKitComplianceDocumentKind.termsOfService,
            version: '2'));
      expect(registry.all.map((d) => d.id), ['a', 'b']);
      expect(registry.byId('a')?.version, '2');
    });

    test('kit.compliance.registry — currentDocuments is one-per-kind in first-seen order', () {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: ArxaKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp1', kind: ArxaKitComplianceDocumentKind.privacyPolicy, version: '1'))
        ..register(_doc(id: 'pp2', kind: ArxaKitComplianceDocumentKind.privacyPolicy, version: '2'));
      expect(registry.currentDocuments.map((d) => d.id), ['tos', 'pp2']);
    });

    test('kit.compliance.registry — two documents sharing a kind collapse to the latest (custom case)', () {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'custom-a', kind: ArxaKitComplianceDocumentKind.custom))
        ..register(_doc(id: 'custom-b', kind: ArxaKitComplianceDocumentKind.custom));
      // Both are in `all`, but the gate sees only the latest per kind.
      expect(registry.all, hasLength(2));
      expect(registry.currentDocuments.map((d) => d.id), ['custom-b']);
    });
  });

  group('ArxaKitConsentRecord', () {
    test('kit.compliance.consent-record — value equality', () {
      final at = DateTime(2026, 7, 1);
      final a = ArxaKitConsentRecord(
          documentId: 'p',
          documentVersion: '1',
          acceptedAt: at,
          method: ArxaKitConsentMethod.explicitTap,
          appVersion: '1.0.0');
      final b = ArxaKitConsentRecord(
          documentId: 'p',
          documentVersion: '1',
          acceptedAt: at,
          method: ArxaKitConsentMethod.explicitTap,
          appVersion: '1.0.0');
      expect(a, b);
      expect(a.isWithdrawal, isFalse);
    });
  });

  group('InMemoryArxaKitConsentStore', () {
    late InMemoryArxaKitConsentStore store;
    setUp(() => store = InMemoryArxaKitConsentStore());

    ArxaKitConsentRecord rec({
      String documentId = 'p',
      String version = '1',
      String? userId,
      DateTime? at,
      ArxaKitConsentMethod method = ArxaKitConsentMethod.explicitTap,
    }) =>
        ArxaKitConsentRecord(
          documentId: documentId,
          documentVersion: version,
          userId: userId,
          acceptedAt: at ?? DateTime(2026, 7, 1),
          method: method,
          appVersion: '1.0.0',
        );

    test('kit.compliance.consent-store — record then latestFor returns it', () async {
      await store.record(rec());
      expect((await store.latestFor('p'))?.documentVersion, '1');
    });

    test('kit.compliance.consent-store — withdraw appends a withdrawal that latestFor surfaces', () async {
      await store.record(rec());
      await store.withdraw(
          documentId: 'p',
          documentVersion: '1',
          appVersion: '1.0.0',
          at: DateTime(2026, 7, 2));
      final latest = await store.latestFor('p');
      expect(latest?.method, ArxaKitConsentMethod.withdrawn);
      expect(latest?.isWithdrawal, isTrue);
    });

    test('kit.compliance.consent-store — anonymous and per-user tracks are separate (both directions)',
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

    test('kit.compliance.consent-store — history filters by track and document, oldest first', () async {
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

    test('kit.compliance.consent-store — latest-wins tie-breaks equal timestamps by insertion order',
        () async {
      final at = DateTime(2026, 7, 1);
      await store.record(rec(version: 'first', at: at));
      await store.record(rec(version: 'second', at: at));
      expect((await store.latestFor('p'))?.documentVersion, 'second');
    });
  });

  group('ArxaKitConsentService.statusFor', () {
    late ArxaKitComplianceRegistry registry;
    late InMemoryArxaKitConsentStore store;
    late ArxaKitConsentService service;

    setUp(() {
      registry = ArxaKitComplianceRegistry();
      store = InMemoryArxaKitConsentStore();
      service = ArxaKitConsentService(store: store, registry: registry);
    });
    tearDown(() => service.dispose());

    test('kit.compliance.consent-status — notRequired when the document does not require acceptance', () async {
      final doc = _doc(requiresExplicitAcceptance: false);
      // Even with a record present, status is notRequired.
      await service.accept(doc,
          appVersion: '1.0.0', method: ArxaKitConsentMethod.implicitContinue);
      expect(await service.statusFor(doc), const ArxaKitConsentStatus.notRequired());
    });

    test('kit.compliance.consent-status — neverAccepted with no record', () async {
      expect(await service.statusFor(_doc()),
          const ArxaKitConsentStatus.neverAccepted());
    });

    test('kit.compliance.consent-status — accepted when the version matches exactly', () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0');
      expect(await service.statusFor(doc), const ArxaKitConsentStatus.accepted());
    });

    test('kit.compliance.consent-status — acceptedOutdatedVersion on any string mismatch (no semver)',
        () async {
      await service.accept(_doc(version: '1.0.0'), appVersion: '1.0.0');
      final status = await service.statusFor(_doc(version: '1.0.1'));
      expect(status,
          const ArxaKitConsentStatus.acceptedOutdatedVersion('1.0.0'));
      expect((status as ArxaKitConsentAcceptedOutdatedVersion).acceptedVersion,
          '1.0.0');
    });

    test('kit.compliance.consent-status — withdrawn when the latest action is a withdrawal', () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 1));
      await service.withdraw(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 2));
      expect(await service.statusFor(doc), const ArxaKitConsentStatus.withdrawn());
    });

    test('kit.compliance.consent-status — latest-wins: accept -> withdraw -> re-accept ends accepted',
        () async {
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 1));
      await service.withdraw(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 2));
      await service.accept(doc, appVersion: '1.0.0', at: DateTime(2026, 7, 3));
      expect(await service.statusFor(doc), const ArxaKitConsentStatus.accepted());
    });

    test('kit.compliance.consent-status — status is scoped to the service user track', () async {
      final doc = _doc(version: '1.0.0');
      final anon = ArxaKitConsentService(store: store, registry: registry);
      final u1 = ArxaKitConsentService(store: store, registry: registry, userId: 'u1');
      await u1.accept(doc, appVersion: '1.0.0');
      expect(await u1.statusFor(doc), const ArxaKitConsentStatus.accepted());
      expect(await anon.statusFor(doc), const ArxaKitConsentStatus.neverAccepted());
      await anon.dispose();
      await u1.dispose();
    });
  });

  group('outstandingDocuments', () {
    test('kit.compliance.outstanding — lists unsatisfied required docs in registry order, skipping notRequired',
        () async {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: ArxaKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp', kind: ArxaKitComplianceDocumentKind.privacyPolicy))
        ..register(_doc(
            id: 'cookie',
            kind: ArxaKitComplianceDocumentKind.cookiePolicy,
            requiresExplicitAcceptance: false));
      final store = InMemoryArxaKitConsentStore();
      final service = ArxaKitConsentService(store: store, registry: registry);
      await service.accept(registry.byId('tos')!, appVersion: '1.0.0');
      final outstanding = await service.outstandingDocuments();
      expect(outstanding.map((d) => d.id), ['pp']);
      await service.dispose();
    });
  });

  group('ArxaKitConsentService.statusChanges', () {
    test('kit.compliance.status-changes — accept emits an accepted status change on the broadcast stream',
        () async {
      final registry = ArxaKitComplianceRegistry();
      final store = InMemoryArxaKitConsentStore();
      final service = ArxaKitConsentService(store: store, registry: registry);
      final events = <ArxaKitConsentStatusChange>[];
      final sub = service.statusChanges.listen(events.add);
      final doc = _doc(version: '1.0.0');
      await service.accept(doc, appVersion: '1.0.0');
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.document, doc);
      expect(events.single.status, const ArxaKitConsentStatus.accepted());
      await sub.cancel();
      await service.dispose();
    });
  });

  group('ArxaKitConsentGate', () {
    test('kit.compliance.gate — blocked lists outstanding docs in registry order', () async {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'tos', kind: ArxaKitComplianceDocumentKind.termsOfService))
        ..register(_doc(id: 'pp', kind: ArxaKitComplianceDocumentKind.privacyPolicy));
      final service =
          ArxaKitConsentService(store: InMemoryArxaKitConsentStore(), registry: registry);
      final result = await ArxaKitConsentGate(service).evaluate();
      expect(result.canProceed, isFalse);
      expect(result, isA<ArxaKitConsentGateBlocked>());
      expect((result as ArxaKitConsentGateBlocked).outstanding.map((d) => d.id),
          ['tos', 'pp']);
      await service.dispose();
    });

    test('kit.compliance.gate — allowed when nothing is outstanding', () async {
      final registry = ArxaKitComplianceRegistry()
        ..register(_doc(id: 'pp', kind: ArxaKitComplianceDocumentKind.privacyPolicy));
      final service =
          ArxaKitConsentService(store: InMemoryArxaKitConsentStore(), registry: registry);
      await service.accept(registry.byId('pp')!, appVersion: '1.0.0');
      final result = await ArxaKitConsentGate(service).evaluate();
      expect(result.canProceed, isTrue);
      expect(result, const ArxaKitConsentGateResult.allowed());
      await service.dispose();
    });
  });

  group('ArxaKitLicensesService', () {
    test('kit.compliance.licenses — collect maps packages and paragraph text via the injected source',
        () async {
      final service = FakeArxaKitLicensesService(const [
        LicenseEntryWithLineBreaks(['my_pkg'], 'MIT license text'),
      ]);
      final entries = await service.collect();
      expect(entries.single.packages, ['my_pkg']);
      expect(entries.single.paragraphs.join(' '), contains('MIT'));
    });

    test('kit.compliance.licenses — byPackage groups an entry under each of its packages, sorted',
        () async {
      final service = FakeArxaKitLicensesService(const [
        LicenseEntryWithLineBreaks(['zeta', 'alpha'], 'shared license'),
        LicenseEntryWithLineBreaks(['alpha'], 'alpha only'),
      ]);
      final grouped = await service.byPackage();
      expect(grouped.keys.toList(), ['alpha', 'zeta']);
      expect(grouped['alpha'], hasLength(2));
      expect(grouped['zeta'], hasLength(1));
    });

    test('kit.compliance.licenses — ArxaKitLicenseEntry value equality', () {
      expect(
        const ArxaKitLicenseEntry(packages: ['a'], paragraphs: ['x']),
        const ArxaKitLicenseEntry(packages: ['a'], paragraphs: ['x']),
      );
      expect(
        const ArxaKitLicenseEntry(packages: ['a'], paragraphs: ['x']) ==
            const ArxaKitLicenseEntry(packages: ['a'], paragraphs: ['y']),
        isFalse,
      );
    });
  });
}
