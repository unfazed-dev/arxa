# Shorebird Code Push + Flutter Release-Train Mechanics

Research date: 2026-08-03. Sources fetched live from `docs.shorebird.dev`, Apple, and Google
primary policy pages (see citation URLs per section). Verbatim quotes are marked with `>`.

---

## Summary (≤200 words)

Shorebird patches carry **Dart code only**. The official decision flowchart is a two-gate test:
native code changed → release; assets changed → release; otherwise → patch. Pubspec dependency
bumps are patchable *only if* the new dependency introduces no native code. Flutter/engine version
bumps always require a release. Generated `app_localizations` from `.arb` files is explicitly
patchable — it compiles to Dart.

Versioning: a release is `1.0.0+1` (a store concept); a patch is an auto-incrementing integer
scoped to one release, and does not change the app version. Only one patch is active per release
at a time. A new release starts patch numbering fresh; users on the old release keep receiving that
release's patches. Tracks (`stable` default, `beta`, `staging`) plus `shorebird patches set-track`
give staged rollout and promotion. Rollback is console/CLI-driven plus automatic on-device
rollback on hash/signature/load failure.

Policy: Google Play's Device and Network Abuse policy carves out interpreted-code runtimes;
Apple's DPLA §3.3.2(B) permits downloaded interpreted code that does not change the app's primary
purpose. **However Apple App Review Guideline 2.5.2 is worded more strictly** — this tension is a
real residual risk (see Q3).

---

## Q1 — What exactly can a Shorebird patch change?

Source: <https://docs.shorebird.dev/code-push/faq/> ("Is my change patchable?" and "What types of
changes can be included in a patch?")

### Official decision flowchart (verbatim from the FAQ)

```
flowchart TD
    A["Did you make changes?"] --> B{"Do changes include native code?\n(Java, Kotlin, Swift, Obj-C)"}
    B -- Yes --> C["New Store Release Required\n(Run 'shorebird release')"]
    B -- No --> D{"Do changes include asset updates?\n(Images, fonts, pubspec assets)"}
    D -- Yes --> C
    D -- No --> E["Patchable OTA!\n(Run 'shorebird patch')"]
```

### Patchable

> Patches can change any Dart code in your application. This includes:
> * App code
> * Generated code (including `app_localizations` if following the recommended
>   [Internationalization Approach](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization))
> * Dependencies in `pubspec.yaml`, as long as they don't include native code changes.

### NOT patchable — forces a full store release

> This does **not** include:
> * Asset files (images, fonts, etc.), although we have plans to support this in the near future
>   (see <https://github.com/shorebirdtech/shorebird/issues/318>).
> * Native code (e.g. Java/Kotlin on Android or Objective-C/Swift on iOS).
> * Flutter engine changes (i.e., you cannot change the Flutter version of your app using Code Push).

Also release-forcing in practice:
- Anything read from the app bundle rather than compiled: `pubspec.yaml` `assets:` entries,
  fonts, launcher icons, splash screens.
- Native manifest / plist / permissions / entitlements / signing changes.
- New plugin dependencies that ship platform code (the common failure mode for "just a Dart
  dependency bump").
- App version/build-number changes (that *is* a release by definition).

### Escape hatches (documented but discouraged)

`shorebird patch` exposes `--allow-asset-diffs` and `--allow-native-diffs`, both documented as
**"Not recommended."** They publish anyway when Shorebird's differ detects asset or native drift.
The changed assets/native code are **not** delivered — only the Dart diff is — so the patched Dart
runs against the *old* release's assets/native code. An automated classifier must never set these.

Source (flags table): <https://docs.shorebird.dev/code-push/patch/> (`shorebird patch` options; URL
verified 200)

Note: the docs describe these flags as publishing "even if asset/native differences are detected."
They do **not** state what happens to the undelivered assets or native code at runtime. Treat the
runtime consequence as unspecified — which is itself reason enough for automation never to set them.

### Important operational note (from the same FAQ)

> By default, the Shorebird updater runs on a background thread on startup … The patch is
> downloaded in the background while the user is using the app and will be applied on the **next
> launch** (meaning users will see the update on their second launch of the app).

So OTA is not instantaneous — it is a two-launch delay unless the app opts into a blocking/manual
update flow via `package:shorebird_code_push`.

---

## Q2 — Versioning semantics, workflows, tracks, rollback

Sources:
- Glossary: <https://docs.shorebird.dev/code-push/> (Concepts → Application / Release / Patch / Artifact)
- FAQ: <https://docs.shorebird.dev/code-push/faq/#when-should-i-create-a-patch-vs-a-release>
- Staging patches: <https://docs.shorebird.dev/code-push/guides/staging-patches/>
- Rollback: <https://docs.shorebird.dev/code-push/rollback/>
- `shorebird patch` reference: <https://docs.shorebird.dev/code-push/patch/>
- `shorebird release` reference: <https://docs.shorebird.dev/code-push/release/>
- `shorebird preview` reference: <https://docs.shorebird.dev/code-push/preview/>
- Percentage rollouts: <https://docs.shorebird.dev/code-push/guides/percentage-based-rollouts/>

All URLs in this document were verified to return HTTP 200 on 2026-08-03 against
`https://docs.shorebird.dev/sitemap-0.xml`.

### Release vs patch numbering

> A release is a specific version of an application, identified by a version and build number
> (e.g., `1.0.0+1`). … A release can have zero or more patches applied to it.

> A patch is a change to a specific release, applied as an over-the-air update. … Multiple patches
> can be published for a given release, although only one patch can be active at a time. Patches
> are identified by their associated release version and a patch number, which is an
> auto-incrementing integer.

> A "release" gets a unique release version, while a "patch" does not change the release version,
> just the "patch number". The "release version" is a store concept, whereas "patch number" is a
> Shorebird concept.

Consequences the classifier must model:
- Patch identity is the pair `(release_version, patch_number)` — patch numbers are **not** globally
  unique, they restart per release.
- Patches never migrate across releases. Users still on an old release continue to receive that
  release's patch stream; they do not jump to a newer release's patches. The same fix must be
  patched onto every still-live release you intend to support — which bounds how many releases you
  can afford to keep patchable. *(Derived, not quoted: the docs state a patch is "a change to a
  specific release" identified by "their associated release version and a patch number", and
  `shorebird patch` requires `--release-version`. That a new release restarts numbering at 1 is a
  sound inference from per-release scoping, but I did not find it stated verbatim — verify against
  the Console before relying on it for identity keys.)*
- The app version reported to the OS/stores is unchanged by a patch. Android `in_app_update` will
  not see patches; analytics must read `ShorebirdUpdater.readCurrentPatch()` from
  `package:shorebird_code_push` to disambiguate `1.0.1+13 patch 0` from `1.0.1+13 patch 3`.
  Docs: <https://pub.dev/packages/shorebird_code_push>

### Workflows

```
shorebird release <android|ios|macos|windows|linux>   # builds + uploads release artifacts, then you upload to stores
shorebird patch   <android|ios|macos|windows|linux>   # builds diff vs the associated release, uploads patch artifacts
```

Key `shorebird patch` options (reference table):

| Option | Meaning |
| --- | --- |
| `--release-version` | Release to patch, e.g. `1.0.0+1`; `latest` targets the most recently updated release |
| `--platforms` / `-p` | Comma-separated multi-platform patch, e.g. `android,ios` |
| `--flavor` | Product flavor (note: each flavor has its own `app_id`) |
| `--target` / `-t` | Entrypoint |
| `--track` | Deployment track, **default `stable`**; `staging` / `beta` supported |
| `--dry-run` / `-n` | Build and validate, do **not** upload — the CI sanity check |
| `--allow-asset-diffs` | Publish despite asset drift — *not recommended* |
| `--allow-native-diffs` | Publish despite native drift — *not recommended* |

`--dry-run` is the single most useful primitive for an automated classifier: it lets CI *ask
Shorebird* whether a diff is patchable rather than inferring it.

### Tracks / staged rollout

- Three tracks in use in the docs: `stable` (default), `beta`, `staging`.
- Publish to a non-default track: `shorebird patch android --track=staging`
- Preview a track before promoting:
  `shorebird preview --track staging --app-id <app_id> --release-version 1.0.0+1`
- Promote a validated patch:
  `shorebird patches set-track --release-version 1.0.0+1 --patch-number 1 --track stable`
- Percentage rollouts are implemented **client-side**: the app derives a stable group number per
  device and chooses `UpdateTrack.beta` vs `UpdateTrack.stable` against a rollout percentage you
  serve. Shorebird does not do server-side percentage gating for you.
- Caveat, verbatim: Shorebird **cannot** gate patches by Play test track or TestFlight membership —
  > "not all of these mechanisms allow 3rd parties to detect when apps are installed in any
  > specific Test Track or via TestFlight. Thus … Shorebird cannot reliably gate access to patches
  > based on these groups."
  Staging must therefore be modelled as your own track name, not as the store's beta channel.

### Rollback

> If you discover that a live patch has a bug, Shorebird supports patch roll back. When a patch is
> rolled back, it is remotely uninstalled from end users' devices and replaced by either the
> previous patch or the base release if no previous patch is available.

- Console: release → patch row → three-dots → **Rollback**.
- Requires **minimum Flutter 3.27.4**.
- Downloading an older patch during rollback **counts against your monthly patch installs**; if
  quota is exhausted the app reverts to the base release.
- Automatic, on-device safety net (no human needed):
  - patch file hash is stored separately and checked on every install and boot;
  - optional cryptographic **patch signing** (KMS-backed) — note: lose the private key and *no
    patch can ever be made for that release again*, only a new store release;
  - if hash/signature mismatch → patch discarded; if the patch fails to load into the Dart runtime
    → marked "bad" on that device and automatically rolled back;
  - previous patch file is retained until the next patch boots successfully once.

---

## Q3 — Store-policy compliance for OTA code push

### Google Play — Device and Network Abuse policy

Source: <https://support.google.com/googleplay/android-developer/answer/9888379> (fetched verbatim)

> An app distributed via Google Play may not modify, replace, or update itself using any method
> other than Google Play's update mechanism. Likewise, an app may not download executable code
> (such as dex, JAR, .so files) from a source other than Google Play. **This restriction does not
> apply to code that runs in a virtual machine or an interpreter where either provides indirect
> access to Android APIs** (such as JavaScript in a webview or browser).

Shorebird's position is that its patched Dart runs in the Dart VM's interpreter path and therefore
falls in the carve-out. Note the carve-out's own wording is about VM/interpreter code with
*indirect* API access — this is the load-bearing legal assumption. It has not, to my knowledge,
been tested publicly against Play enforcement for Flutter specifically. **Flag as assumption, not
adjudicated fact.**

### Apple — two documents that do not say the same thing

**(a) Apple Developer Program License Agreement §3.3.2(B) "Executable Code"** — fetched verbatim:

> Except as set forth in the next paragraph, an Application may not download or install executable
> code. **Interpreted code may be downloaded to an Application** but only so long as such code:
> (a) does not change the primary purpose of the Application by providing features or functionality
> that are inconsistent with the intended and advertised purpose of the Application
> (b) does not bypass signing, sandbox, or other security features of the OS; and
> (c) for Applications distributed on the App Store, does not create a store or storefront for
> other Applications.

Source: <https://developer.apple.com/support/terms/apple-developer-program-license-agreement/>

**(b) App Store Review Guideline 2.5.2** — fetched verbatim:

> 2.5.2 Apps should be self-contained in their bundles, and may not read or write data outside the
> designated container area, nor may they download, install, or execute code which introduces or
> changes features or functionality of the app, including other apps.

Source: <https://developer.apple.com/app-store/review/guidelines/>

**Honest reading of the tension:** 2.5.2 contains no interpreted-code exception on its face. The
exception lives in the DPLA. The prevailing industry interpretation (used by Expo, Microsoft
CodePush historically, and Shorebird) is that the DPLA carve-out governs and 2.5.2 targets
downloading *executable/native* code. That interpretation is widely relied on and has survived
years of shipping, but it is an interpretation. Apple can, and does, exercise discretion.

### Practical policy-safe classification

| Change class | Patch-safe? | Rationale |
| --- | --- | --- |
| Bug fix, crash fix, logic correction | Yes | No change to advertised purpose (DPLA 3.3.2(B)(a)) |
| Copy / string / l10n edits | Yes | Cosmetic; purpose unchanged |
| Layout, styling, widget-tree refactor of an existing screen | Yes | Same feature, different presentation |
| Perf tuning, analytics fixes, config plumbing | Yes | Purpose unchanged |
| **New user-facing feature or new surface** | Technically patchable, **policy-risky** | Risks "changes features or functionality" / "inconsistent with intended and advertised purpose" |
| Monetisation / paywall / IAP flow changes | **No — release** | Highest-scrutiny review area; must be reviewed |
| Anything gating or unlocking previously-unreviewed behaviour | **No — release** | Classic 2.5.2 / review-evasion pattern |
| Native, assets, Flutter bump | **No — release** | Technically impossible anyway (Q1) |

Rule of thumb the classifier should encode: *technical patchability is necessary but not
sufficient.* A change can be pure Dart and still warrant a release on policy grounds.

---

## Q4 — Fastlane + Shorebird CI pattern

Source: <https://docs.shorebird.dev/code-push/ci/fastlane/> (URL verified 200)
Working example repo: <https://github.com/shorebirdtech/fastlane_demo>
(`ios/fastlane/Fastfile` has both `release_shorebird` and `patch_shorebird` lanes)

Shorebird ships a fastlane plugin providing two actions: `shorebird_release` and `shorebird_patch`.

> Note that this change from `build_app` to `release_shorebird` is the only change needed to add
> Shorebird to your fastlane workflow.

Recommended shape — **two lanes, one decision point**. The following is the *actual* upstream
`ios/fastlane/Fastfile` from `shorebirdtech/fastlane_demo` (fetched verbatim from `main`, trimmed
to the two Shorebird lanes):

```ruby
desc "create new release with shorebird"
lane :release_shorebird do
  setup_ci
  sync_code_signing(
    type: "appstore",
    app_identifier: bundle_id,
    readonly: true
  )
  # This step replaces the build_app step
  shorebird_release(platform: "ios")
  app_store_connect_api_key(
    is_key_content_base64: true,
    in_house: false, # if it is enterprise or not
  )
  upload_to_app_store(
    app_identifier: bundle_id,
    force: false,
    precheck_include_in_app_purchases: false,
    run_precheck_before_submit: true,
    submit_for_review: false
  )
end

desc "patch with shorebird"
lane :patch_shorebird do
  setup_ci
  shorebird_patch(
    platform: "ios",
    args: "--release-version=latest"
  )
end
```

Note the upstream demo uses `--release-version=latest` and does **not** use tracks. For a
production classifier-driven pipeline, pass an explicit release version and a track instead (see
wiring note 7 below) — `latest` is ambiguous once two releases are live.

CI wiring that matters:
1. **Classify first.** A pipeline step decides `patch` vs `release` from the diff (see Q5) and
   selects the lane. Never let the same lane guess.
2. **`--dry-run` as a gate.** Run `shorebird patch … --dry-run` in PR CI. If it reports asset or
   native diffs, the classifier's "patchable" verdict was wrong → fail the PR or reroute to the
   release lane. This is the mechanical ground truth.
3. **Never pass `--allow-*-diffs` from automation.**
4. **Patch to `--track staging` first**, `shorebird preview --track staging` for QA, then promote
   with `shorebird patches set-track … --track stable`. Promotion is a separate, human-gated job.
5. **Auth via `SHOREBIRD_TOKEN`** (from `shorebird login:ci`) as a CI secret; code signing via
   fastlane `match` in readonly mode.
6. **Multi-platform:** `shorebird patch -p android,ios` patches both platforms from one invocation
   (documented as "Comma-separated list of platforms to patch simultaneously"). Whether this
   guarantees identical patch numbers across platforms is **not stated in the docs** — do not
   assume it; read patch numbers back per platform if you key anything off them.
7. **Keep the release-version ledger.** The patch lane needs `--release-version`; CI must know which
   store release the current `main` corresponds to. Store it (tag or manifest) at release time —
   `--release-version latest` is convenient but ambiguous once two releases are live.

---

## Q5 — Applied to the app-box scenario

Repo facts verified in this worktree (not assumed):
- `appbox-studio/pubspec.yaml` has `generate: true`; `appbox-studio/l10n.yaml` sets
  `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
  `output-localization-file: app_localizations.dart`.
- `.arb` files live at `appbox-studio/lib/l10n/*.arb` and at `designs/appbox-studio/l10n/*.arb`.
- The `flutter: assets:` block lists only `assets/config/` — the `.arb` files are **not** bundled
  assets.

This is exactly Flutter's recommended internationalization approach, so the `.arb` → Dart
`app_localizations.dart` path is the one Shorebird names as patchable.

### Change B — one-word typo in an `.arb` string → **PATCH**

`.arb` files are compile-time inputs to `gen_l10n`, not runtime assets. Editing one regenerates
`app_localizations.dart`, which is Dart code. Nothing native, no asset-manifest entry changes,
no dependency or Flutter change. Policy-wise a typo fix cannot change the app's advertised
purpose. **Patch, high confidence.**

Caveats the pipeline must still honour:
- If the typo fix *adds a new key*, the diff is still pure Dart → still patchable.
- If the pipeline ever switches to runtime `.arb` loading via `rootBundle` (i.e. `.arb` listed
  under `flutter: assets:`), this flips to **release**. The classifier must key off *how* the
  `.arb` is consumed, not off the file extension.

### Change A — checkout view completely redesigned, possibly a new kit → **RELEASE (default)**

Widget-tree restructuring alone is pure Dart and technically patchable. But "possibly new kit"
is the deciding term, and it introduces three independent release-forcing risks:

1. **Assets.** A new kit almost certainly brings images, icons, or fonts, and touches
   `pubspec.yaml` `assets:`/`fonts:`. Asset changes are hard-blocked from patches.
2. **Native code.** A new kit may pull plugins with platform code (payments, wallets — and
   *checkout* is precisely where Apple Pay / Google Pay / IAP plugins appear).
3. **Policy.** A complete checkout redesign is a payments-surface change — the highest-scrutiny
   review area. Even if it were 100% Dart, shipping it OTA to bypass review is the exact behaviour
   2.5.2 exists to prevent.

**Verdict: release.** Only if `--dry-run` proves zero asset diffs, zero native diffs, no new
dependency, no pubspec change, *and* a human signs off that the checkout flow's advertised
functionality is unchanged should this ever downgrade to a patch — and for a payments surface,
the pipeline should not offer that downgrade at all.

Asymmetry worth encoding explicitly: **misclassifying a release as a patch is far more expensive
than the reverse.** A wrong patch ships broken or non-compliant code to every installed device and
costs a rollback plus quota; a wrong release costs a review cycle. Default to release on any
ambiguity.

---

## Classifier inputs

Metadata an automated classifier needs to decide mechanically. Grouped by the gate they feed.

### Hard gates — any true ⇒ RELEASE (technical impossibility)

| Input | Source of truth |
| --- | --- |
| `native_files_changed` | diff touches `android/**` (`.java`,`.kt`,`.gradle`,`AndroidManifest.xml`), `ios/**` (`.swift`,`.m`,`.h`,`.plist`,`Podfile*`), `macos/**`, `windows/**`, `linux/**` |
| `asset_files_changed` | diff touches any path under a `pubspec.yaml` `flutter: assets:` root, or any `fonts:` entry |
| `pubspec_assets_or_fonts_block_changed` | structural diff of `pubspec.yaml` `flutter:` section |
| `flutter_version_changed` | `.fvmrc` / `fvm_config.json` / `pubspec.yaml` `environment.flutter` / CI pin / `shorebird.yaml` |
| `app_version_changed` | `pubspec.yaml` `version:` field |
| `new_or_bumped_dependency_with_native_code` | resolve added/changed deps in `pubspec.lock`; check each package for `android/`/`ios/` dirs or a `flutter.plugin` stanza |
| `dart_sdk_constraint_changed` | `pubspec.yaml` `environment.sdk` |
| `shorebird_yaml_changed` | `app_id`/flavor changes invalidate the patch target |

### Policy gates — any true ⇒ RELEASE (review required, even if Dart-only)

| Input | How to derive |
| --- | --- |
| `touches_payment_or_iap_surface` | path/kit tags: checkout, cart, paywall, subscription, billing |
| `introduces_new_user_facing_surface` | new route/screen registered in the design SSOT, not just a re-render of an existing one |
| `changes_advertised_functionality` | design-SSOT semantic diff: new capability vs restyling of an existing capability |
| `changes_permissions_or_data_collection` | manifest/plist diff, or privacy-manifest delta |
| `unlocks_previously_gated_behaviour` | feature-flag default flips |

### Soft signals — inform confidence and routing

| Input | Use |
| --- | --- |
| `changed_kits` + `kit_manifest.has_native_deps` / `.has_assets` | pre-screen before running a build |
| `arb_consumption_mode` (`gen_l10n` vs `rootBundle`) | decides whether `.arb` edits are Dart or asset |
| `l10n_only_change` | strongest patch signal in this repo's design |
| `widget_structure_changed` vs `style_tokens_only` | both patchable; affects QA depth and staging duration |
| `diff_scope` (files, LOC, kits touched) | large scope ⇒ prefer staging track + longer soak |
| `live_release_versions[]` | how many releases need the same patch applied |
| `patch_install_quota_remaining` | rollback cost model |

### Mechanical verification — the tiebreaker

| Input | Meaning |
| --- | --- |
| `shorebird_patch_dryrun_exit_code` | 0 ⇒ Shorebird itself agrees the diff is patchable |
| `shorebird_patch_dryrun_asset_diff_detected` | overrides any heuristic "patchable" verdict |
| `shorebird_patch_dryrun_native_diff_detected` | overrides any heuristic "patchable" verdict |

**Decision order:** hard gates → policy gates → `--dry-run` verification → patch. Any gate trips,
or `--dry-run` disagrees, → release. Default on ambiguity or missing metadata → **release**.

---

## Uncertainty flags

- **Asset patching is on Shorebird's roadmap** (issue #318). If it lands, the `asset_files_changed`
  hard gate becomes version-dependent — pin the Shorebird CLI version and re-verify.
- **Apple ARG 2.5.2 vs DPLA 3.3.2(B) tension is unresolved by primary sources.** Both quoted
  verbatim above. No Apple document reconciles them explicitly; the reconciliation is industry
  practice, not published Apple guidance.
- **Play's interpreter carve-out** has not been publicly adjudicated for Flutter/Dart specifically.
- `shorebird patches set-track` flag spelling and the exact track-promotion UX are current as of
  the fetch date; the CLI surface moves.
- Rollback requires **Flutter ≥ 3.27.4**; verify against the version this pipeline pins.
