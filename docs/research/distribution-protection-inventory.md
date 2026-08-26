# Distribution-protection inventory — what stops arxa's own system being extracted

**Scope:** repo `unfazed-dev/arxa`, worktree `scaffold-shell-worktree`, 2026-08-03. Read-only survey. `archives/` excluded from all "what ships today" claims.

> **Amendment (2026-08-05).** `explode.js`, listed below among the first-party
> islands, retired with the views-lens components container (`7babc79`); four
> islands remain (`canvas.js`, `drag.js`, `inspect.js`, `flowwalk.js`). The
> rest of this snapshot stands as surveyed.

## Summary (≤150 words)

Little prevents redistribution of the arxa system, and one thing actively permits it. The repo is **private** (GitHub returns 404 anonymously), which is today's only real control. There is **no root LICENSE** — all-rights-reserved by default, but never asserted. Against that, two skill directories carry **root-level MIT LICENSE files** (`skills/arxa-designer/LICENSE`, `skills/arxa-story-mapper/LICENSE.txt`). Both are legitimately inbound (declared in `THIRD-PARTY-NOTICES.md`), but neither carves out arxa's own additions beneath them — `system-prompt.md`, `references/app-architecture.md`, `kit-catalog.md`, `ui-recipes.md`, `starter-partials/`. Read plainly they grant "use, copy, modify, publish, distribute… and/or sell" over the methodology IP. Nothing is compiled: `dart compile exe` is *planned only*, so arxa ships as readable Dart plus a repo tree the design server reads at runtime. `arxa design eject` is narrow. No EULA exists. Existing gates are inbound-compliance and anti-rot; none is a redistribution control.

---

## Q1 — Legal layer

**No root licence.** Root contains `THIRD-PARTY-NOTICES.md` but no `LICENSE`/`COPYING`/`EULA` (root listing: `AGENTS.md, arxa-studio, arxa, archives, assets, CLAUDE.md, config, deploy, designs, docs, gates, hooks, kit, memory, pipeline, skills, THIRD-PARTY-NOTICES.md, tools`). Default position is all-rights-reserved — protective by omission, but nowhere asserted. There is **no EULA, terms-of-service or "all rights reserved" string** anywhere in first-party `.md`/`.dart`/`.yaml` (only `kit/compliance/lib/src/kit_compliance_document.dart:9`, an *enum member* for apps built with arxa, and third-party notes in `docs/research/monetization-and-licensing.md:141`).

**The MIT problem — this is the real exposure.**

- `skills/arxa-designer/LICENSE:1` `MIT License`, `:3` `Copyright (c) 2026 Jim Liu 宝玉`, `:5-8` port note describing it as a Kimi-Code-only port of `github.com/JimLiu/baoyu-design`. The grant text at `:15-18` is unmodified MIT.
- `skills/arxa-designer/SKILL.md:174` — "Licensed MIT — this skill is a fork. See `LICENSE`…".
- `THIRD-PARTY-NOTICES.md:8-13` scopes it as "`skills/arxa-designer` is a fork of an MIT-licensed design skill… The same `LICENSE` file is also retained inside `skills/arxa-designer/`."

**The discriminator:** the LICENSE sits at the *skill root*, not in a vendored subtree, and neither it nor `SKILL.md:174` nor `THIRD-PARTY-NOTICES.md` carves out arxa's own additions. Beneath that root sit the arxa-authored methodology files — `references/app-architecture.md`, `references/kit-catalog.md`, `references/ui-recipes.md`, `references/harness-tools.md`, `system-prompt.md`, `DESIGN-ARCHITECTURE.md`, `starter-partials/`, `built-in-skills/`, `docs/adr/` — none of which came from upstream. A reader applying MIT to the directory it heads gets a free right to redistribute all of it. Inbound MIT does *not* compel this; the fix is a scope statement, not a licence change.

- `skills/arxa-story-mapper/LICENSE.txt:1-8` has the same shape and one extra defect: `MIT License` / `Copyright (c) 2026` with **no copyright holder named**. It *is* declared upstream — `THIRD-PARTY-NOTICES.md:116-121` says the skill "is an MIT-licensed story-mapping skill, **adapted for arxa**" — but "adapted for arxa" is precisely the un-carved-out part, and the directory contains only `SKILL.md` and `story-map.schema.json`, i.e. the adaptation *is* the whole visible content. An unnamed holder also makes the grant hard to attribute or rebut.
- The other nine skills (`arxa-builder`, `-deployer`, `-intake`, `-lens`, `-lint`, `-moodboarder`, `-reviewer`, `-scaffolder`, `-tester`) carry **no licence file** → all-rights-reserved. The inconsistency is itself the signal that the two MIT files are accidental.

**pubspecs:** 28 of 34 non-archive pubspecs set `publish_to: 'none'` (e.g. `kit/core/pubspec.yaml:4`, `kit/ui_library/pubspec.yaml:4`, `arxa-studio/pubspec.yaml:3`). Missing on six: the five vendored `kit/ui_library/vendor/*` forks (upstream, each with its own LICENSE) and — critically — **`arxa/pubspec.yaml`** (`name: arxa`, `version: 1.0.0`, no `publish_to`). The engine is the one package a stray `dart pub publish` would push to pub.dev. No pubspec declares a `license:` field.

## Q2 — Shipping form

**Nothing is compiled today.** `dart compile exe` appears only in plans and a comment:
- `arxa/bin/arxa.dart:12` — `// Planned: dart compile exe bin/arxa.dart → self-contained binary.`
- `docs/plans/arxa-dart-only-tooling.md:85`, `:98`; `docs/plans/arxa-lens-full-port.md:3354`.

There are **no build or packaging scripts anywhere**: `tools/` holds only probe harnesses (`probe-*.mjs`, `sweep_rename.sh`, `phase5_kit_copy.sh`); `arxa/tool/` holds `_scaffold_smoke.dart`, `lens_check.dart`, `lens_shot.dart`; `arxa/bin/` holds `arxa.dart`, `arxad.dart`, `licence_tool.dart`; `deploy/remote/scripts/` holds only `gen-mesh-cert.sh`. No macOS/Windows/Linux packaging, no notarization, no installer.

Documented invocation is JIT-from-source: `gates/README.md:28` `dart run bin/arxa.dart gate <name>`, `gates/freeze/README.md:4`, `arxa/bin/licence_tool.dart:3`. **Full Dart source therefore ships wherever arxa runs.**

Worse for AOT: the design server reads its own assets from the *source tree* at runtime — `arxa/lib/design_server.dart:326` errors with `worker assets not found (lib/design_server/worker_assets)`, and `arxa/lib/design_server/worker.dart:906` joins `'worker_assets', 'worker_page.html'`. The design tools likewise resolve repo paths: `arxa/lib/design_tools.dart:451` (`skills/arxa-designer/runtime/ladder.json`), `:452` (`references/viewport-ladder.md`), `:1046` (`runtime/vendor`), `:1170`. **Running the designer requires `skills/arxa-designer/` on disk** — so shipping the designer today means shipping the methodology IP as files. Nothing is embedded.

## Q3 — Designer exposure via `arxa design eject`

Eject **is** implemented in Dart (contradicting any read that it is archived-only): dispatched at `arxa/lib/design_cli.dart:98` (`case 'eject':`), implemented at `arxa/lib/design_tools.dart:1181` onward, ported from `runtime/eject.mjs`.

What lands in a free user's output:
1. **A verbatim copy of their own artifact directory** — `design_tools.dart:1230` (`_copyTree(artifact, out)`). Their work, not arxa's.
2. **A narrowed slice of `runtime/vendor/`** — `design_tools.dart:1218-1219` resolves `skills/arxa-designer/runtime/vendor`; `:1191` `_vendorRefRe` scans artifact HTML for `/assets/vendor/<path>.(js|css)`; `:1269`/`:1277` copy only referenced files into `<out>/runtime/vendor/`. Two hard fails: missing vendored lib (`:1258`) and no `htmx.min.js` reference (`:1264`, "refusing to eject").
3. **A README** replacing the old node runtime (`design_tools.dart:1181-1186`, `:1207`, `:1326`). No `package.json`, no Node, no Hono server — the prior "self-contained hardened Hono app" description is stale; the Dart port dropped it.

**Not copied:** `design_server.dart`, the emit/scaffold engine, kit playbooks, `config/kit-registry.json`, `system-prompt.md`, `references/`, `starter-partials/`, `built-in-skills/`. Eject is genuinely narrow.

**The arxa-owned residue** is the first-party glue islands inside `runtime/vendor/`, which are copied byte-for-byte when referenced: `canvas.js`, `drag.js`, `inspect.js`, `flowwalk.js`, `explode.js`, `map_island.js`, `game_island.js`, `rive_island.js`, `dotlottie_island.js`. Their headers self-identify as first-party — `flowwalk.js:1` "the flow-walk island (ADR-0002 amendment 2026-08-02)"; `inspect.js:2` "The third named first-party script (sibling to canvas.js and drag.js)". These are small, self-contained UI glue, not the engine. The genuinely third-party neighbours (`htmx.min.js`, `leaflet/`, `lottie-player.js`, `rive.js`, `model-viewer.min.js`, `mustache.min.js`, `lucide/`, SRI-pinned per `vendor/SRI.md`) were never arxa IP and their readability is not a leak.

## Q4 — Skills / prompts leakage

The `skills/arxa-*` tree is **repo-only**: no distributed artifact copies it, and eject does not touch it. `.gitignore:81` excludes only `skills/**/node_modules/`, i.e. the tree is tracked and shipped with the repo.

The leak is therefore not "eject copies it" but **(a)** the MIT grant at `skills/arxa-designer/LICENSE` and `skills/arxa-story-mapper/LICENSE.txt` covering it (Q1), and **(b)** the runtime dependency on those paths (`design_tools.dart:451,452,1046,1170`) meaning any desktop/CLI distribution must place them on the user's disk in cleartext until assets are embedded (Q2).

## Q5 — Existing integrity / anti-rot mechanisms

None is a redistribution control.

- `arxa/lib/licence.dart:1-3` — the only genuine enforcement primitive: "Offline licence verification for arxa… Ed25519-signed licence file, verified fully offline by arxa; flat annual + perpetual fallback", with `tier: "annual" | "perpetual"`. Paired with `arxa/bin/licence_tool.dart` and `arxa/test/licence_test.dart`. This gates *entitlement to run*, not *reuse of source* — and offline Ed25519 verification inside shipped-as-source Dart is trivially patchable.
- `arxa/lib/gate_coverage.dart:22` — C5 is "ceremonies — every active target's platform files/keys present (6.8)"; `:189`, `:336`. Build-correctness only.
- `arxa/lib/design_selftest_kit_catalog_mirror.dart:1-9` — anti-rot: every `dir` in `config/kit-registry.json` must appear in `references/kit-catalog.md`. Internal doc consistency; it *guarantees the canon stays mirrored into the MIT-covered directory*, which is a mild aggravator, not a control.
- `kit/compliance/lib/src/kit_licenses_service.dart`, `kit_license_entry.dart` — inbound third-party attribution for apps *built with* arxa. Nothing to do with arxa's own IP.

## Ranked gaps

1. **CRITICAL — `skills/arxa-designer/LICENSE` at skill root**: MIT heading a directory whose `system-prompt.md`, `references/*.md`, `starter-partials/`, `built-in-skills/`, `docs/adr/` are arxa-authored. Neither the LICENSE, `SKILL.md:174`, nor `THIRD-PARTY-NOTICES.md:8-13` scopes the grant to the upstream fork. This is the methodology IP the business decision says must never be redistributable.
2. **CRITICAL — `skills/arxa-story-mapper/LICENSE.txt:1-3`**: same un-carved-out root MIT, plus no named copyright holder; `THIRD-PARTY-NOTICES.md:116-121` describes it as "adapted for arxa" without scoping the adaptation.
3. **HIGH — no root LICENSE / no EULA anywhere**: all-rights-reserved by default, but never asserted, so the two explicit MIT grants are the *only* stated terms and dominate any dispute. No terms bind a free designer user at all.
4. **HIGH — nothing compiles; full Dart source ships**: `arxa.dart:12` marks AOT as planned; `design_server.dart:326` and `design_tools.dart:451/1046` require the source tree and `skills/arxa-designer/` on disk. Distributing the free designer today = handing over the engine and the prompts.
5. **MEDIUM — `arxa/pubspec.yaml` lacks `publish_to: 'none'`** while 28 sibling pubspecs have it. One command from an accidental pub.dev publication of the engine.
6. **MEDIUM — offline-only licence check in interpreted source** (`licence.dart`): removable by editing the file the user already has.
7. **LOW — first-party islands copied into ejected output** (`canvas.js`, `drag.js`, `inspect.js`, `flowwalk.js`, `explode.js`, `*_island.js`): genuinely arxa-owned and readable, but small UI glue, no engine value.
8. **RESOLVED — repository visibility**: `origin https://github.com/unfazed-dev/arxa.git`. An unauthenticated fetch of that exact URL returns **404** (as does `unfazed-dev/arxa_kit`), consistent with both being private. Privacy is currently the *only* effective protection in the whole system — every gap above is latent, not realised, and stays that way only while the repo stays closed.

## Recommended countermeasures

1. **Keep the repo private, and treat that as a policy not an accident.** It is the only protection currently working. Restrict who can fork/clone; assume any public flip immediately realises gaps 1-6.
2. **Name the holder in `skills/arxa-story-mapper/LICENSE.txt:3`** and apply the same carve-out as (3). An MIT notice with no copyright holder protects nobody and satisfies no upstream obligation.
3. **Re-scope the designer's MIT grant, don't remove it.** Keep upstream attribution (the licence requires it) but move `LICENSE` out of the skill root into the fork's actual boundary — e.g. `skills/arxa-designer/runtime/UPSTREAM-LICENSE`, or add an explicit `NOTICE` at the root reading: *"The MIT grant covers only files derived from baoyu-design (enumerated below). All other files in this directory — including `system-prompt.md`, `references/`, `starter-partials/`, `built-in-skills/`, `docs/` — are © Totem Labs, all rights reserved."* Enumerate the derived files; anything unlisted is proprietary by default. Update `THIRD-PARTY-NOTICES.md:8-13` to state the same carve-out.
4. **Add a root `LICENSE` asserting proprietary all-rights-reserved**, plus a short EULA covering the free designer tier (no reverse engineering, no redistribution of arxa components, user owns their ejected artifact). Say explicitly that ejected output is the user's and vendored third-party libs keep their own terms — that clarity is what makes the rest enforceable.
5. **Ship AOT, and embed the assets.** Execute the `dart compile exe` plan at `arxa.dart:12`, and eliminate the on-disk dependencies at `design_server.dart:326`, `design_tools.dart:451/452/1046/1170` by embedding `worker_assets/`, `runtime/vendor/`, `ladder.json` and any needed reference text as binary resources. Until both land, the designer cannot be distributed without the methodology IP. Add `publish_to: 'none'` to `arxa/pubspec.yaml` today as a one-line stopgap.
6. **Add a redistribution gate to the gate suite** (sibling to `gate_coverage.dart` C5): fail if any `LICENSE`/`COPYING` file exists outside a declared third-party allowlist, if any non-vendor pubspec lacks `publish_to: 'none'`, or if a packaged artifact manifest contains a path under `skills/`. Given the anti-rot precedent in `design_selftest_kit_catalog_mirror.dart`, this is the idiom the repo already trusts to keep a rule from rotting.
