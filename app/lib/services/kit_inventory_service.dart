/// The honest wired-versus-stubbed kit registry.
///
/// 8.7 / done-when #4 — load-bearing. A buyer (Michelle) who picks a stubbed
/// provider and meets `UnimplementedError` at build time has been misled. This
/// service is the single source the `settings.kits` surface renders, so a stub
/// is always labelled as a stub — never offered as available.
///
/// Data sourced from `docs/research/stub-inventory.md` (the surveyed SSOT).
/// `stacked_kit` names a real runtime dependency (R2 exception 2) and is retained.
enum KitPhase { stable, nativeFirst, nativeFirstPartial }
enum ProviderState { wired, stub }

class KitProvider {
  final String name;
  final ProviderState state;
  /// For stubs: what happens if a buyer picks it (the UnimplementedError / TODO).
  final String? detail;
  const KitProvider(this.name, this.state, [this.detail]);
}

class KitEntry {
  final String name;
  final KitPhase phase;
  final List<KitProvider> providers;
  const KitEntry(this.name, this.phase, this.providers);

  bool get hasStub => providers.any((p) => p.state == ProviderState.stub);
  bool get allWired => providers.every((p) => p.state == ProviderState.wired);
}

class KitInventoryService {
  /// The 23 kits by phase + per-provider state, from stub-inventory.md.
  List<KitEntry> get kits => const [
        // stable — wired (14)
        KitEntry('core', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('ui_library', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('data', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('haptics', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('motion', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('forms', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('state', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('documents', KitPhase.nativeFirstPartial, [KitProvider('base', ProviderState.wired)]),
        // native-first (3)
        KitEntry('permissions', KitPhase.nativeFirst, [KitProvider('all', ProviderState.wired)]),
        KitEntry('media', KitPhase.nativeFirst, [KitProvider('capture/playback', ProviderState.wired)]),
        KitEntry('payments', KitPhase.nativeFirst, [
          KitProvider('Apple Pay', ProviderState.wired),
          KitProvider('Stripe', ProviderState.stub,
              "throws UnimplementedError('StripePaymentsProvider is a stub')"),
          KitProvider('PayPal', ProviderState.stub,
              "throws UnimplementedError('PayPalPaymentsProvider is a stub')"),
        ]),
        // native-first-partial (5)
        KitEntry('notifications', KitPhase.nativeFirstPartial, [KitProvider('base', ProviderState.wired)]),
        KitEntry('maps', KitPhase.nativeFirstPartial, [
          KitProvider('base', ProviderState.wired),
          KitProvider('OpenStreetMap', ProviderState.stub,
              "TODO: flutter_map ^8.x — not implemented"),
          KitProvider('Mapbox', ProviderState.stub,
              "TODO: mapbox_maps_flutter ^2.x — not implemented"),
        ]),
        KitEntry('bluetooth', KitPhase.nativeFirstPartial, [KitProvider('base', ProviderState.wired)]),
        KitEntry('security', KitPhase.nativeFirstPartial, [KitProvider('Keychain', ProviderState.wired)]),
        KitEntry('auth', KitPhase.stable, [
          KitProvider('email/password (seed)', ProviderState.wired),
          KitProvider('Apple SignIn', ProviderState.stub,
              "throws UnimplementedError('AppleSignInProvider — phase-later')"),
          KitProvider('Google SignIn', ProviderState.stub,
              "throws UnimplementedError('GoogleSignInProvider — phase-later')"),
          KitProvider('SeedAuthBackend', ProviderState.stub, 'stub (phase-4)'),
        ]),
        KitEntry('deploy', KitPhase.stable, [
          KitProvider('fastlane', ProviderState.wired),
          KitProvider('shorebird', ProviderState.wired),
          KitProvider('Cloudflare Pages', ProviderState.wired),
          KitProvider('Vercel', ProviderState.stub, 'VercelTarget throws'),
        ]),
        KitEntry('analytics', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('compliance', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('support', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
        KitEntry('wifi', KitPhase.stable, [KitProvider('all', ProviderState.wired)]),
      ];

  int get stubbedProviderCount =>
      kits.expand((k) => k.providers).where((p) => p.state == ProviderState.stub).length;
}
