# App fidelity mode — config format + scaffolder emission spec

Implements rulings QF-1…QF-4 (docs/plans/designer-scaffolder-grill-decisions.md,
2026-08-14). Law basis: liquid-glass-allowlist.md "Sanctioned exception — app
fidelity mode"; m3e-law.md rule 5; VOCABULARY.md "App fidelity mode".
Status: SPEC — nothing below is implemented yet.

## 1. The config: per-platform fidelity map (QF-3)

Fidelity is **data, not code** (P06/R3): a `fidelity` map lives alongside the
target rows the scaffolder already derives in
`pipeline/state/targets.derivation.json`. Shape:

```json
{
  "fidelity": {
    "ios":     "mix",
    "android": "mix",
    "web":     "flutter",
    "desktop": "flutter"
  }
}
```

Values: `flutter | mix | native`.

- **`mix` (default)** — the kit's existing tier gate unchanged:
  `wantNative && ArxaKitPlatform.supportsLiquidGlass|supportsComposeM3E`,
  frosted/fallback tier elsewhere. Omitted map ⇒ `{ios: mix, android: mix,
  web: flutter, desktop: flutter}`.
- **`flutter`** — Flutter tier wholesale; native wiring tree-shaken (§3).
- **`native` (strict, QF-1)** — every widget with a native tier must render
  it; an unsupported tier is a build/assert error, never a silent frosted
  fallback. Explicitly NOT Flutter-free codegen (out of kit scope).

**Validation (scaffolder gate):** `mix`/`native` are illegal where no native
tier exists — today that is `web` and `desktop`; the scaffolder REJECTS the
config with a named error rather than silently no-opping. `native` on ios
additionally forces the deployment floor to iOS 26 (Liquid Glass gate is
`iosMajor >= 26`); the scaffolder must write that floor or reject.

## 2. Runtime SSOT: root default (QF-2, data half)

The kit gains one small surface (mirrors the existing
`ArxaKitPlatform.override` / `ArxaKitPlatformOverride` pattern in
`kit/core/lib/platform/arxa_kit_platform.dart`):

- `ArxaKitFidelity.mode` — resolved from
  `const String.fromEnvironment('ARXA_FIDELITY', defaultValue: 'mix')`.
  The scaffolder emits `--dart-define=ARXA_FIDELITY=<mode>` per build
  target, derived mechanically from the `fidelity` map (advisor 2026-08-14:
  a runtime static cannot tree-shake and adds mutable global state; only a
  const environment value participates in const conditionals). The review
  gate re-derives the define from `targets.derivation.json` and fails on
  mismatch — the emitted const cannot silently drift from the config.
- Tier gate composition: `wantNative && supports* && fidelity.allowsNative`,
  where `allowsNative` is `const` (`mode != 'flutter'`) so `flutter` mode
  tree-shakes every native branch (every two-tier widget and every vendor
  `preferFlutterTier` default resolves to the Flutter tier).
- Strict (`native`, QF-1 as amended): ONE fail-fast validation at app-root
  init — if `supports*` is false at startup, throw a named
  `FidelityViolation` (debug AND release). Deterministic single crash
  point; QF-1's "error, not fallback" is preserved, only the throw site
  moved from first-gate-evaluation to root init (amendment recorded in
  designer-scaffolder-grill-decisions.md). Per-gate check survives as a
  debug-only assert in the shared gate helper. No per-widget silent
  demotion.
- Testability: the gate is factored as a pure function; a
  `kDebugMode`-guarded test override channel exists (tree-shaken in
  release builds). Tests never flip the const directly.
- Per-widget `preferFlutterTier`/`wantNative` still exist and still win
  locally in `mix`; in `native` mode a per-widget `preferFlutterTier: true`
  is a lint error (it contradicts the declared mode).

**Defaults (explicit):**
- `fidelity` map absent ⇒ `{ios: mix, android: mix, web: flutter,
  desktop: flutter}` (§1).
- `ARXA_FIDELITY` define absent (un-scaffolded kit dev) ⇒ `mix` — on
  web/desktop `supports*` is already false, so `mix` resolves to the
  Flutter tier there with no native wiring exercised.
- Per-widget `native`/`preferFlutterTier` absent in `mix` ⇒ platform
  default: `wantNative = ArxaKitPlatform.supportsNativeChrome`.

## 3. Tree-shake at scaffold (QF-2, code half)

When a platform's mode is `flutter`, the scaffolder emits the app root
WITHOUT the native-tier wiring — glass warm-up, chrome gate hookups, view
slicer registration — instead of leaving dormant law machinery in the
generated app. Mechanism: the emitted mode is a `const`, so the compiler
drops the native branches; the scaffolder additionally omits the wiring
imports/registrations it would otherwise emit. Law machinery that only
polices the native tier (warm-up, gate, slicer) is absent by construction,
which is lawful under the sanctioned exception — gates/lints must key on
the declared fidelity mode before flagging missing native wiring.

## 4. Scaffolder flow

1. Intake/design phases unchanged — fidelity is not a design decision; the
   designer's frozen anatomy stays tier-agnostic (chrome EXISTENCE remains
   the design's call; fidelity decides how chrome is RENDERED).
2. Scaffold phase reads `fidelity`, validates (§1), then per target:
   emit root const + wiring per mode (§2–3).
3. Review/build gates: lint recognizes the mode (allowlist amendment);
   `native` builds get the strict fail-fast test pinned.

## 5. Open items (owed before implementation)

- `ArxaKitFidelity` kit implementation + tests (tier-gate composition,
  strict throw, override interplay with `ArxaKitPlatformOverride`).
- Lint/gate updates: recognize the sanctioned exception; add the
  `preferFlutterTier`-in-native-mode lint.
- Desktop/web native tiers, if ever added, flip the §1 legality table —
  that is a data edit plus a legality-table edit here, not a redesign.
- Android strict floor: decide the minimum SDK where `native` (M3E) is
  guaranteed — owed to the first Android device pass (m3e-law open items).
