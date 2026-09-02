# Engine distribution — ship vs host, closed (2026-09-02)

Question: does the arxa engine ship on the customer's machine (current D30 / consolidate #11)
or run on arxa-owned servers? This doc exists so the question stops being reopened: it records
the constraints, the measured facts, the industry precedents, the four real options, the
decision, and the **numeric triggers** that would justify revisiting.

## 1. Why it keeps reopening

Three separate worries get conflated as "control":

1. *Someone copies the paid engine.* (piracy)
2. *Someone reads the engine's internals.* (IP)
3. *Install is going to be huge.* (size — the worry raised 2026-09-02)

Only (2) is helped by hosting. (1) is a licence-mechanics problem. (3) is not true — see §2.

## 2. Measured facts (this machine, built artefacts)

| Piece | Size | What it is |
|---|---|---|
| Engine sidecar `arxa-aarch64-apple-darwin` | **13 MB** | `dart compile exe` of `arxa/lib` (2.9 MB source, 6 deps). **Code only.** |
| Harness sidecar `arxa-studio-aarch64-apple-darwin` | **193 MB** | = node runtime **116 MB** (`pack-sidecar.mjs:77` copies `process.execPath`) + node_modules payload ~75 MB (`@opentelemetry` 34, `@img` 17, `openai` 16, `@google` 14, `@aws-sdk` 7, `@smithy` 7, dsh 0.2) |
| Tauri shell | not built | est. 5–15 MB; Linux uses system webkit2gtk |
| Kit templates (git-tracked) | **26 MB** | `kit/` on disk is 2.2 GB, of which 2.17 GB is untracked build output |
| Designs / builder UI (`arxa/designs/*`) | small | served from disk by `design_server.dart:141` |

**What the 13 MB does *not* contain** — and this answers "did you omit the kit?": the engine reads
`kit/`, `designs/`, and templates from a **repo checkout at runtime** (`bin/arxa.dart:322
findRepoRoot()`, `gate_kind_registry.dart:337 kitRoot = root/kit`). No shipped artefact today
carries them. The founder's machine works because the repo is there. A customer's would not.
That is a **distribution gap**, independent of ship-vs-host, and is tracked in §7.

Install as planned: ≈230–250 MB raw, ~100–130 MB compressed. Cursor ≈200 MB, VS Code ≈100 MB.
The Flutter SDK, Xcode and Android SDK the customer needs anyway are 5–20 GB.

## 3. Industry precedents

| Product | Where the engine runs | How they keep control | What happens offline / on cancel | Relevance |
|---|---|---|---|---|
| **Unity** | Local editor | Named-user online sign-in; licence server; manual offline activation only for Enterprise/Industry seats; Personal has an offline grace period, after which open projects close ([manual activation](https://support.unity.com/hc/en-us/articles/4401914348436-How-do-I-manually-activate-my-Unity-license), [grace ended error](https://support.unity.com/hc/en-us/articles/23957059684116)) | Grace, then stop | **Same shape as arxa**: local engine, entitlement token, grace |
| **JetBrains** | Local IDE | Account activation, offline activation code, floating licence server for offline clients, perpetual fallback licence ([offline activation](https://sales.jetbrains.com/hc/en-gb/articles/360016995379-Activating-JetBrains-IDEs-with-an-offline-activation-code), [offline clients](https://intellij-support.jetbrains.com/hc/en-us/community/posts/206807935-License-server-How-to-deal-with-offline-clients)) | Works; fallback to perpetual version | Same shape; proves offline-first licensing is normal in paid dev tools |
| **Expo / EAS** | Local CLI, open source | Sell the *cloud services* (builds, OTA, submit), never the CLI ([local vs cloud](https://dev.to/mbugua70/local-vs-cloud-builds-in-expo-what-expo-prebuild-and-eas-build-really-do-3mnc), [pricing](https://checkthat.ai/brands/expo/pricing)) | Everything local keeps working | Model for a *future* arxa cloud layer, not for the engine |
| **Shorebird** | Local CLI (MIT/Apache), **closed hosted backend**, no self-host planned ([FAQ](https://docs.shorebird.dev/code-push/faq/), [issue #485](https://github.com/shorebirdtech/shorebird/issues/485)) | The service is the product | Apps keep working after cancel | arxa resells this; shows "open client + hosted service" holds commercially |
| **Zed** | Local, open source (GPL) | BYOK on all plans; hosted prompts metered ([comparison](https://dev.to/alexcloudstar/cursor-vs-windsurf-vs-zed-the-ai-ide-showdown-2026-44eo)) | Fully offline with local models | Closest to arxa's BYO-key stance |
| **Cursor / Windsurf** | Local editor, **hosted inference proxy** | Code routes through their servers; Privacy Mode is contractual ([overview](https://codemyspec.com/blog/ai-ides-compared-2026)) | Degrades to a plain editor | The hosted model — requires an ops org and a subscription to fund it |
| **FlutterFlow** | Hosted editor + desktop wrapper; code generated server-side; export gated by tier ([architecture](https://docs.flutterflow.io/before-you-begin/app-architecture/), [review](https://www.rapidevelopers.com/review/flutterflow)) | Hosting is the lock-in | Desktop app needs sign-in; large projects crash the desktop editor | The competitor arxa is positioned *against* (`competitors-and-pricing.md`) |
| **HashiCorp / BSL** | n/a (source) | Source-available licence to publish code yet restrict competitors ([BSL adoption](https://www.hashicorp.com/en/blog/hashicorp-adopts-business-source-license), [FOSSA on BSL](https://fossa.com/blog/business-source-license-requirements-provisions-history/)) | n/a | Option if the repo ever goes public; not needed while private |
| **Tauri sidecar + updater** | n/a (mechanism) | Signed updates mandatory; sidecars ship inside every AppImage update; `{{target}}/{{arch}}` in updater URL ([sidecar](https://v2.tauri.app/develop/sidecar/), [updater](https://v2.tauri.app/plugin/updater/), [AppImage](https://v2.tauri.app/distribute/appimage/)) | — | Constrains Linux packaging (see §7) |

Pattern: **every paid local dev tool ships the engine and controls it with a token + grace.**
Hosting the engine is what *editor-as-a-service* products do, and they fund an ops org to do it.
Nobody in this set hosts a code generator *because* it is copyable.

## 4. Constraints, ranked

1. Solo operator, no on-call. Anything that pages at 3 a.m. is a design failure.
2. Agencies (persona P5) must scaffold offline / during arxa outages — the monetization research's
   "server dependency bricks the product" verdict (`monetization-and-licensing.md`).
3. BYO-LLM key: arxa carries no inference cost, so nothing forces a server into the path.
4. Positioning against FlutterFlow's hosting lock-in — hosting the engine copies the competitor.
5. Engine internals are not visible in emitted code, but AOT is patchable — "paying easier than
   pirating" is the realistic ceiling either way.

## 5. The four options

| | A. Local sidecar (D30) | B. Local engine + static kit/artefact CDN | C. Local engine + optional hosted *convenience* layer | D. Hosted engine |
|---|---|---|---|---|
| Engine location | Customer disk | Customer disk | Customer disk | arxa servers |
| Kit delivery | Bundled or downloaded | Signed manifest + files from a **dumb bucket** (no compute) | As B | Server-side |
| Piracy protection | JWT + grace; AOT patchable | As A + revocable kit content | As B | Strong |
| IP protection | Weak | Weak | Weak | Strong |
| Offline paid scaffold | Yes | Yes (cached kits, grace) | Yes | **No** |
| Outage blast radius | None | Stale kits | Convenience features off | **All paid users blocked** |
| Ops per month (solo) | Edge Functions only (~0 h) | + bucket + CI upload (~1 h) | + telemetry/cloud-build service (10–40 h) | Production service, quotas, abuse, SLA (40 h+, on-call) |
| Reversible | Can add B/C/D later | Can fall back to A | Can switch layer off | **Cannot un-host without redoing distribution** |
| Contradicts | — | — | — | D30, consolidate #11 & #38, monetization verdict, FlutterFlow positioning |

**Forgotten option = C.** It is what Expo/Shorebird actually sell: the engine stays free-and-local,
the *hosted* things are conveniences (kit CDN, cloud builds via resold Shorebird/Codemagic,
telemetry, later Totem Cloud). It costs nothing to keep the door open and never bricks anyone.

## 6. Decision

**Engine ships locally as a Tauri sidecar (A), with kits delivered per B, and C reserved as the
growth path.** Licence stays the offline-verified Ed25519 JWT with grace (matches Unity/JetBrains).
This is a *confirmation* of D30 / consolidate #11, now with recorded reasons.

Said out loud: an offline JWT with grace accepts some licence sharing. We choose that revenue
leakage over the support burden and outage liability of hosting. Seat/org axis (Q6 in the
strategy digest) decides how much sharing matters.

**Revisit triggers** (decision holds until one fires, measured, not felt):
1. Verified pirated paid seats exceed **10 % of paid seats** in any quarter.
2. An engine feature is planned that **cannot run on a developer laptop** (fine-tuned model that
   isn't BYO-key, >8 GB RAM working set, GPU).
3. Paid-tier outage tolerance is renegotiated: a contract requires **revocation faster than the
   token TTL** and the customer won't accept a shorter TTL.
4. A second full-time operator exists to carry on-call.

## 7. Separate work items (not hosting arguments)

- **Kit distribution.** Engine currently needs a repo checkout (`findRepoRoot()`). Options:
  (i) bundle git-tracked `kit/` (26 MB) as a Tauri resource, or (ii) fetch on first run / on
  entitlement refresh from a static bucket with a signed manifest (option B). (ii) is preferred:
  updates kits without an app release, and makes paid kits revocable.
- **Linux build.** `tauri.conf.json` targets only `app`,`dmg`; `externalBin` only
  `aarch64-apple-darwin`. Needs `dart compile exe` on linux-x64, a linux node payload
  (`pack-sidecar.mjs` pins `process.execPath`), Tauri `appimage` + `deb` targets, built on the
  oldest supported distro (glibc), updater endpoint using `{{target}}`/`{{arch}}`.
- **Harness slimming (optional).** 116 MB of the 193 MB is the node runtime. Levers: ship node
  once per machine rather than per sidecar version, or prune `@opentelemetry`/`@img`/unused
  provider SDKs after a dsh dependency audit. Do not promise a number before the audit.
- **Doc updates.** Mark D30 "confirmed 2026-09-02 with triggers"; add this file as the ADR
  candidate; remove `licence.dart`/`watermark.dart` citations from the monetization plan.

## 8. Sources consulted

Official: [Tauri sidecar](https://v2.tauri.app/develop/sidecar/) · [Tauri updater](https://v2.tauri.app/plugin/updater/) ·
[Tauri AppImage](https://v2.tauri.app/distribute/appimage/) · [Unity manual activation](https://support.unity.com/hc/en-us/articles/4401914348436-How-do-I-manually-activate-my-Unity-license) ·
[Unity offline grace error](https://support.unity.com/hc/en-us/articles/23957059684116) · [JetBrains offline activation](https://sales.jetbrains.com/hc/en-gb/articles/360016995379-Activating-JetBrains-IDEs-with-an-offline-activation-code) (page fetch failed on TLS; cited from search summary) ·
[Shorebird FAQ](https://docs.shorebird.dev/code-push/faq/) · [FlutterFlow architecture](https://docs.flutterflow.io/before-you-begin/app-architecture/) ·
[HashiCorp BSL](https://www.hashicorp.com/en/blog/hashicorp-adopts-business-source-license).
Secondary: [Expo local vs cloud](https://dev.to/mbugua70/local-vs-cloud-builds-in-expo-what-expo-prebuild-and-eas-build-really-do-3mnc) ·
[Expo pricing](https://checkthat.ai/brands/expo/pricing) · [Tauri v2 sidecar lessons](https://dev.to/chenxxpro/bundling-a-cli-binary-as-a-tauri-v2-sidecar-lessons-from-building-a-desktop-app-5po) ·
[AI IDE comparison](https://codemyspec.com/blog/ai-ides-compared-2026) · [Cursor/Windsurf/Zed](https://dev.to/alexcloudstar/cursor-vs-windsurf-vs-zed-the-ai-ide-showdown-2026-44eo) ·
[FlutterFlow review](https://www.rapidevelopers.com/review/flutterflow) · [FOSSA on BSL](https://fossa.com/blog/business-source-license-requirements-provisions-history/).
Local: `arxa-studio/scripts/pack-sidecar.mjs`, `arxa/desktop/src-tauri/tauri.conf.json`, `arxa/arxa/bin/arxa.dart`,
`arxa/arxa/lib/gate_kind_registry.dart`, `arxa/arxa/lib/design_server.dart`, `docs/research/monetization-and-licensing.md`,
`docs/research/competitors-and-pricing.md`, `docs/plans/consolidate-one-app-plus-daemon.md`.
Advisor consult (architecture, confidence 0.82): decide local + triggers; forgotten option = hosted convenience layer.
