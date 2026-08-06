# appbox_kit_compliance

A standalone kit for the legal/compliance surfaces every app eventually needs:
a versioned document registry, consent tracking behind a port, a pure
consent-gate, and an OSS-license collector over Flutter's `LicenseRegistry`.
Typed results throughout, no widgets, and **zero third-party runtime
dependencies** — the Flutter SDK is the only backing package.

## Scope

- **Documents & versions** — `AppBoxKitComplianceDocument` (id, `AppBoxKitComplianceDocumentKind`,
  opaque `version`, title, sealed `AppBoxKitComplianceSource` remote/inline body,
  `effectiveDate`, `requiresExplicitAcceptance`, `locale`) held in a
  `AppBoxKitComplianceRegistry` (`register` / `byId` / `currentFor(kind)` /
  `currentDocuments` / `all`).
- **Consent** — `AppBoxKitConsentRecord` (with `AppBoxKitConsentMethod`:
  `explicitTap` / `implicitContinue` / `imported` / `withdrawn`) persisted
  behind the `AppBoxKitConsentStore` port. `InMemoryAppBoxKitConsentStore` is the working
  default. `AppBoxKitConsentService` derives a typed `AppBoxKitConsentStatus`
  (`accepted` / `acceptedOutdatedVersion(acceptedVersion)` / `withdrawn` /
  `neverAccepted` / `notRequired`), exposes `outstandingDocuments()`, and emits
  `AppBoxKitConsentStatusChange`es on a broadcast `statusChanges` stream.
- **Consent gate** — `AppBoxKitConsentGate.evaluate()` returns a sealed
  `AppBoxKitConsentGateResult` (`allowed` / `blocked(outstanding)`), in registry
  order. Pure logic, no UI.
- **OSS licenses** — `AppBoxKitLicensesService` gathers `LicenseRegistry.licenses`
  into typed `AppBoxKitLicenseEntry`s (`collect()` / `byPackage()`). Rendering
  (`showLicensePage` or custom) stays in the app.

## Semantics

- **Version comparison is exact-string** — no semver parsing. Any mismatch
  between the accepted version and the document's current version is
  `acceptedOutdatedVersion`; `2026-07-01` and `1.2.0` are equally valid schemes.
- **Withdrawal beats a prior acceptance** — status is latest-wins, not sticky:
  accept → withdraw → re-accept ends `accepted`.
- **Separate tracks** — anonymous (`userId == null`) and per-user records never
  bleed into each other; the store matches `userId` exactly.
- **`notRequired` documents can still record implicit consent** —
  `statusFor` returns `notRequired`, but an `implicitContinue` record is still
  persisted for the audit log.

## Dependency direction

This package intentionally depends on **no other kit** (not `appbox_kit`,
`stacked`, or `stacked_services`). Persistence is behind the `AppBoxKitConsentStore`
port; the app binds `InMemoryAppBoxKitConsentStore` or its own durable
implementation. Nothing here imports Flutter widgets.

## Backing packages

- **State / persistence** — Flutter SDK only. `AppBoxKitConsentStore` is an abstract
  port; the in-memory default keeps an append-only log. Consent value types and
  the license reader use `@immutable` and `LicenseRegistry` from
  `package:flutter/foundation.dart`.
- **App version** — passed in as a plain string. This kit takes no dependency
  on `package_info_plus`.

## Testing

`package:appbox_kit_compliance/appbox_kit_testing.dart` re-exports the API and adds
`FakeAppBoxKitLicensesService`, a `AppBoxKitLicensesService` backed by a scripted list of
`LicenseEntry`s (build them with `LicenseEntryWithLineBreaks`) so license
collection can be tested without a Flutter binding. The in-memory consent store
is used directly in tests.

## Phase notes

- **v0 (this package)** — standalone, own `AppBoxKitConsentStore` port, in-memory
  default, exact-string versioning.
- **One document per kind** — `currentDocuments` and the gate collapse to a
  single current document per `AppBoxKitComplianceDocumentKind` (latest registered
  wins). Two documents sharing a kind — most plausibly `custom` — gate as one;
  give each its own kind if both must be presented.
- **Deferred** — durable store bindings (secure storage / a backend), semver-aware
  version policies, locale-negotiation of which document to present, and any
  consent UI. Add as consuming apps need them. Unifying the typed results onto
  `appbox_kit_state` is a documented later phase; there are no cross-kit imports
  now.
