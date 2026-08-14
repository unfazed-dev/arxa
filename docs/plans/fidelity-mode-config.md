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
  `wantNative && AppBoxKitPlatform.supportsLiquidGlass|supportsComposeM3E`,
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
`AppBoxKitPlatform.override` / `AppBoxKitPlatformOverride` pattern in
`kit/core/lib/platform/appbox_kit_platform.dart`):

- `AppBoxKitFidelity.mode` — a compile-time const the generated app root
  sets from the map for the platform being built.
- Tier gate composition: `wantNative && supports* && fidelity.allowsNative`,
  where `flutter` ⇒ `allowsNative == false` (every two-tier widget and every
  vendor `preferFlutterTier` default resolves to the Flutter tier).
- Strict: `native` mode installs a fail-fast — at first tier-gate evaluation
  where `supports*` is false, throw a named `FidelityViolation` (debug AND
  release; QF-1: error, not fallback). No per-widget silent demotion.
- Per-widget `preferFlutterTier`/`wantNative` still exist and still win
  locally in `mix`; in `native` mode a per-widget `preferFlutterTier: true`
  is a lint error (it contradicts the declared mode).

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

- `AppBoxKitFidelity` kit implementation + tests (tier-gate composition,
  strict throw, override interplay with `AppBoxKitPlatformOverride`).
- Lint/gate updates: recognize the sanctioned exception; add the
  `preferFlutterTier`-in-native-mode lint.
- Desktop/web native tiers, if ever added, flip the §1 legality table —
  that is a data edit plus a legality-table edit here, not a redesign.
- Android strict floor: decide the minimum SDK where `native` (M3E) is
  guaranteed — owed to the first Android device pass (m3e-law open items).
