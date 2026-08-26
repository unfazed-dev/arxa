# Distribution and platforms

## Scope & non-goals

v1 surfaces are three, per D23: native macOS app (app + daemon, unchanged
shape), an iOS/Android controller app, and a Totem-hosted web version of
arxa studio — free access, same Supabase-backed gates as the macOS app,
BYO-LLM on macOS and web (D19, D26/D29). This plan covers how each surface
ships and updates, and the release-engineering work that backs all three.

**Explicitly deferred: native Windows and Linux** (D23 supersedes the
Win/Linux portions of D22's installer scope). The hosted web version is the
v1 answer for those users — no native desktop build, no local daemon on
those OSes. Revisit triggers (not yet recorded anywhere; proposed here since
none exists):
- Sustained demand signal — a support/waitlist volume threshold, or a Scale
  customer requiring local/offline builds unavailable through hosted web.
- Flutter's Windows/Linux desktop embedding stability closes the gap that
  today makes macOS the only native target (deploy-machinery.md Q1 confirms
  neither `deploy.dart` nor `kit/deploy/` has ever had a Windows/Linux
  target — this would be genuinely new work, not dormant code).
- Windows packaging specifics — research now exists:
  `docs/research/windows-packaging.md` (D34, research-only; no decision
  taken). Key corrections it establishes for the eventual revisit: MSIX
  does NOT sandbox by default (Desktop-Bridge apps run full trust —
  local server + headless Chrome CDP survive); winget treats
  exe/Inno/MSI/MSIX as equally first-class; Azure Trusted Signing's real
  gate is eligibility (US/Canada orgs, 3+ years history; individual
  onboarding paused Apr 2025) — Totem Labs eligibility UNVERIFIED, needs
  an in-portal check before any signing decision; SmartScreen no longer
  favors EV (since 2024), so OV certs (~$220-300/yr) are the fallback.
  Precedent (VS Code, Figma): classic installer + self-built updater as
  consumer default, mirroring the macOS D22 posture — recommended default
  is Inno/WiX, not MSIX. A Windows revisit starts from that report, not
  from scratch.

Also out of scope (owned by sibling plans): the deploy shell UI and
patch/release classifier (`docs/plans/deploy-engine-unification.md`,
D9/D13), BYOK provider routing and key custody mechanics
(`docs/plans/byok-llm-key-custody.md`, D26/D29), Shorebird billing/org model
(D19/D33).

## Per-platform architecture

### macOS app

Distribution channel per D22: signed/notarized installer direct from Totem
Labs' site, a built-in auto-updater, and a Homebrew cask for the CLI.
Billing is Stripe-only, outside any app store (0% cut, no review latency, no
sandbox friction with the build toolchain) — this only ever applied to
macOS; D23 killed the Windows/Linux half of D22, the macOS half stands.
Store presence (e.g. Mac App Store) is deferred to a later, marketing-only
consideration.

This channel has a hard precondition, not yet met: D21 requires `dart
compile exe` (currently only a comment at `arxa/bin/arxa.dart:12`) plus
embedding every on-disk dependency the design server and design tools
resolve from the source tree today (`design_server.dart:326`,
`design_tools.dart:451/452/1046/1170` — worker_assets/, runtime/vendor/,
ladder.json, reference text). `docs/research/distribution-protection-inventory.md`
is unambiguous: nothing is compiled today, no packaging/notarization/installer
scripts exist anywhere, and running the designer requires
`skills/arxa-designer/` readable on disk — shipping today would hand over
the methodology IP as files. AOT+embed gates this whole channel.

Entitlement, not watermarking, gates the paid boundary at scaffold (D17,
D18): Supabase Auth PKCE, Postgres entitlements synced from Stripe, a
short-lived arxa-signed JWT bound to machine fingerprint, verified locally
with silent background refresh, and Ed25519-licence demoted to a
signed+TTL offline-continuation file. `watermark.dart` is retired entirely —
the previous degrade-don't-block model is superseded specifically at the
scaffold boundary, and no watermark or licence-string logic should appear
anywhere in the scaffolded output path. The legal layer backing the shipped
binary (D20): root proprietary LICENSE, short free-tier EULA (user owns
ejected output; no redistribution/reverse-engineering of arxa components),
and re-scoped MIT carve-outs on the two skill directories that currently leak
methodology IP under an unscoped grant (`skills/arxa-designer/LICENSE`,
`skills/arxa-story-mapper/LICENSE.txt` — inventory's ranked gaps #1-#3).
EULA is presented at first-run accept.

### iOS/Android controller app

Pairs with both transports from day one (D28): the user's macOS daemon over
the existing SHA-256 fingerprint-pin pairing channel, and a Totem-hosted web
session. One pairing abstraction, two transports — the controller shell
must not diverge in UI or behavior by which it's talking to. The hosted-
session leg is net-new server scope: session binding to Supabase identity
plus a real-time relay channel between controller and browser session (no
existing equivalent for the browser side; the daemon leg reuses the
companion-mined security layer already built).

This app's distribution posture is the inverse of the macOS app's: it must
go through the App Store and Play Store (no realistic sideload path for iOS
control apps) — a review-risk source, see Risks. It carries no purchase
flow of its own (entitlement is checked via the paired macOS/hosted
session, not sold as a separate SKU), the intended way to sidestep Apple's
in-app-purchase/anti-steering scrutiny — but that framing needs explicit
confirmation against current guidelines before submission, not assumed.

### Hosted web

Server-side pipeline stops at scaffold (D24): Totem servers run intake →
design → freeze → scaffold only. Scaffold output is delivered as a zip
download or written to a user-chosen local folder via the File System
Access API (Chromium-only; Safari/Firefox fall back to zip) — D25. Past
that point, installing Flutter and building is the user's own
responsibility; there is no hosted preview and no Totem-side build
commitment. Tenancy is local-first with opt-in sync (D27): anonymous design
runs entirely in-browser (IndexedDB/OPFS), Totem stores nothing for
anonymous users, and Supabase sign-in is demanded only at the first
identity-needing action — carrying decision 16's principle onto web
unchanged. Signed-in users get opt-in server-side project sync as a
convenience; storage quota and sync-conflict handling are acknowledged as
net-new v1 scope, not yet designed.

Same gates as macOS: the entitlement architecture (D18) and Stripe-backed
tiers (D19) apply identically — hosted web is free access to design + eject,
paid at scaffold, same as the desktop app, not a separate pricing surface.

BYO-LLM on web is constrained by browser CORS, not by choice (D26/D29,
detailed in `docs/plans/byok-llm-key-custody.md`): Anthropic, DeepSeek,
Moonshot, and Z.ai are called directly from the browser (Anthropic via a
documented opt-in header; the other three via empirically-confirmed but
undocumented reflected-origin CORS, re-verified before ship); OpenAI and
Gemini route through a same-origin, stateless passthrough proxy that never
persists a key. Client-side key storage is in-memory by default,
`sessionStorage` as an explicit opt-in, `localStorage` never. Hosted web's
"artifact serving" — the zip/FSA delivery above — is a separate concern from
the deploy engine's Vercel/Cloudflare targets (`kit/deploy/`,
`docs/plans/deploy-engine-unification.md`, D13), which serve *deployed apps*
built from scaffolded output, not the scaffold artifact itself.

## Release engineering workstreams

1. **AOT + embed (D21)** — blocking precondition for any macOS packaging
   work below. `publish_to: 'none'` on `arxa/pubspec.yaml` is a
   same-day stopgap already identified but not yet applied.
2. **Signing/notarization + auto-update pipeline (D22)** — net-new; the
   repo currently has zero packaging, notarization, or installer machinery
   (inventory Q2). No CI exists (`deploy-machinery.md` Summary: `.github/
   workflows` absent) — this workstream and CI need to land together, since
   a signed build without a repeatable pipeline just moves the manual-step
   risk rather than removing it.
3. **Deploy engine unification (D13, tracked in its own plan)** — `kit/
   deploy`'s five target classes become the sole execution path; arxa
   keeps the approval-token gate, append-only ledger, and licence gate as
   orchestration; `gate_deploy.dart` is wired to assert against the ledger,
   which it currently doesn't. This underlies web/app-store release lanes
   but is explicitly out of scope to redo here.
4. **Shorebird patch vs. release lanes** — the upstream fastlane pattern
   (`shorebird_release` / `shorebird_patch` as two lanes, one decision
   point, confirmed working in `shorebirdtech/fastlane_demo`) is the shape
   to adopt once a Fastfile exists (none does today — inventory confirms no
   `Fastfile`, no `fastlane/` directory; commands are shelled directly).
   Patch/release classification itself is D13's opening clause, a separate
   concern from this plan.
5. **Redistribution gate** — a gate-suite addition (sibling to
   `gate_coverage.dart`'s C5) failing on any LICENSE outside a declared
   third-party allowlist, or a packaged-artifact manifest containing a path
   under `skills/` — closes the loop on D21/D20 rather than leaving them as
   one-time fixes that can silently rot.
6. **Controller pairing relay (D28)** — new server infrastructure, not a
   packaging concern, but shares a ship date with the controller app store
   submissions above.

## Risks

- **App Store/Play Store review risk for the controller app.** No purchase
  flow reduces but doesn't eliminate scrutiny; remote-device-control apps
  have drawn platform review friction before. Needs a compliance pass
  against current guidelines, not assumed from the "no IAP" framing alone.
- **Notarization pipeline is entirely unbuilt.** Signing/notarization,
  auto-update, and CI are all greenfield simultaneously (workstream 2) —
  higher integration risk than adding one piece to existing machinery.
- **Relay privacy for hosted-session controller pairing.** Unlike the
  daemon leg (existing companion-mined local-network security layer), the
  hosted leg introduces a new relay between controller and browser session
  bound to Supabase identity — a new data-in-transit trust boundary with no
  existing design to inherit from.
- **Windows/Linux packaging is unresearched, not merely deferred.** If the
  revisit trigger fires, MSIX/winget/Azure Trusted Signing (or any
  alternative) starts from zero — there is no D-number to fall back on.
- **Reflected-origin CORS for three BYOK providers can vanish silently**
  (D26/D29) — shared risk with the BYOK plan, surfaced here because hosted
  web's "same gates, BYO-LLM" claim depends on it holding through ship.

## Open questions

- Does the controller app's "no purchase flow" framing actually clear App
  Store review, or does entitlement-via-paired-session read as a
  disguised subscription gate to reviewers?
- Who owns the hosted-session relay's infrastructure and privacy posture —
  is it in scope for this plan's release-engineering workstreams or a
  separate backend plan?
- Storage quota and sync-conflict handling for signed-in hosted web users
  (D27) — flagged as undesigned net-new scope, no owner assigned yet.
- Should the macOS auto-updater (Sparkle-class) also gate Shorebird-patched
  builds, or are OTA patches and full-installer auto-updates two separate,
  non-interacting update paths users experience differently?
