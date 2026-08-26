# 08 — The macOS desktop app

**Goal.** arxa itself: a chromed Stacked MVVM macOS app, forked from the
showcase app so the chrome, theming and seed data are copied, not written.

**Blocks:** 09, 10, 12, 14. **Depends on:** 02.

## Source

`stacked_kit/showcase_app` — **124 Dart files, 8,626 lines**, already carrying
tabbars, splash, theming and seeded/fake data through
`services/{facades,repositories}`.

⚠️ It ships **`ios android web` only — there is no `macos/` folder.** Adding it
is step 8.2 and is the one real cost of this base.

## Steps

- [x] **8.1** Copy `showcase_app` to `app/`. Keep `lib/{app,extensions,services,ui}`
      and `main.dart`.
- [x] **8.2** Add the macOS platform: `flutter create --platforms=macos .` in
      `app/`. Verify it builds and runs before changing anything else.
- [x] **8.3** Strip the showcase's demo domain (`lib/notes/` and any notes
      surfaces). Keep the **chrome, theming, splash, navigation and the
      services/facades/repositories skeleton** — that skeleton is the point of
      this base.
- [x] **8.4** Rebrand: arxa name, logo, splash, accent. Branding flows
      through the kit's generated brand colours — **do not hand-edit generated
      colour files**.
- [x] **8.5** Add macOS **Keychain Sharing entitlements to BOTH**
      `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
      Missing this is `-34018 errSecMissingEntitlement`.
- [x] **8.6** Implement credential storage on `flutter_secure_storage`. **Never
      hand-rolled crypto.** State the active tier in the UI — *"stored in the
      macOS Keychain"*.
- [x] **8.7** Build the surfaces from [`../../design/arxa-persona-design-brief.md`](../../design/arxa-persona-design-brief.md)
      §10 — the 20-surface inventory with its states. `settings.kits` must render
      **wired vs stubbed honestly**; a buyer who picks a stubbed provider and
      meets `UnimplementedError` at build time has been misled.
- [x] **8.8** The app **shells out** to the vendored pipeline through a
      process-runner port — the same pattern the deploy kit proves, so command
      shapes are unit-testable with a scripted runner and **no toolchain in CI**.
      Do not reimplement the pipeline in Dart.
- [x] **8.9** Implement the chat surface as an **MCP client**. Support **both**
      transports: `stdio` (local, optimal for desktop) and Streamable HTTP + SSE
      (remote, bearer/API keys). Combine tools from all connected servers into
      one registry.
- [x] **8.10** Subscription auth: **shell out to an already-authenticated
      harness CLI where one is present**; hold OAuth tokens only for the
      standalone case (§ credentials).
- [x] **8.11** Implement the **three human gates** as distinct, visually
      unmistakable surfaces. An agent may reach a gate and stop; it can never
      mint an approval token.
- [x] **8.12** The licence check is a **precondition, not a gate**. It runs
      before the builder phase and fails with a licence message. **Nothing goes
      red for money.**
- [x] **8.13** Auto-launch the showcase app on first install (journey J1) —
      Michelle must see output quality before typing anything.

## Done-when

1. `flutter build macos` succeeds; the app launches with arxa branding.
2. **Credential proof: write → restart → read back in a signed and notarised
   build.** Not `flutter run --release` — two known macOS failure modes (App
   Group missing from `keychain-access-groups`, hardened runtime after
   notarisation) fail *silently and green*.
3. All 14 brief surfaces exist with their declared states.
4. `settings.kits` shows at least one stubbed provider as stubbed.
5. Chat connects over stdio **and** HTTP.
6. An automated agent cannot advance past any of the three gates — prove it.
7. `flutter analyze` clean.
