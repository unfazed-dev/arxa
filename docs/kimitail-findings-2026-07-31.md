# Kimitail review findings — 2026-07-31

**Status: DOCUMENTED ONLY — no fixes applied.** Deferred until the full arxa
implementation is complete; re-review then. Scope: `arxa/`, `kit/`, root
tooling (`hooks/`, `tools/`, `gates/`, `pipeline/`, `config/`). Excluded:
`arxa-studio/`, `designs/arxa-studio/` (active development), `archives/`.

Four review passes, every "unused" claim grep-verified by the reviewers before
inclusion. Format: `path:L<lines>: <tag> <what>. <replacement>.` Tags:
`delete:` dead code · `stdlib:` stdlib ships it · `yagni:` speculative
abstraction · `shrink:` same logic, fewer lines.

**Totals: ≈ −7,600 lines possible** (arxa −2,450 · kit part 1 −1,500 ·
kit part 2 −3,200 · root tooling −480). Net counts are a ceiling — some
findings may be deliberate generated-app API surface (noted inline).

---

## arxa/ (−2,450; ≈−1,000 if imminent features are wired instead of cut)

### Three large dead blocks (≈1,450 of the total)

- `arxa/lib/blueprint.dart:L2964-3505: delete: ~420 lines of data-model projection machinery unreachable — buildBlueprint's only caller never passes dataModelPath, so _entityDart/_supabaseAdapterDart/_driftDbDart/_migrationSql/seed-SQL helpers never run. Delete, or wire a --data-model flag.`
- `arxa/lib/generate_view.dart:L900-1509 + L3057-3111: delete: ~700 lines of uncalled VM/OTP template emitters (tplVmHomeBase/Stub, tplVmSplash, tplVmAuth, tplVmWelcome, tplVmOtp, tplViewOtp, tplVmBase) — buildView emits only views.`
- `arxa/lib/runtime_config.dart:L1-126 + harness.dart:L1-34 + credentials.dart:L1-149: delete: three whole files (~310 lines) with zero production callers, test-only — ports landed ahead of wiring. Delete with their tests, or wire them. (If wiring is imminent, hold.)`

### blueprint / emit / generate_view

- `arxa/lib/blueprint.dart:L3404-3435: yagni: _assemble opts factoryV/generated/stack/appNameOverride never passed; upfront mkdir loop redundant with write loop's recursive create.`
- `arxa/lib/blueprint.dart:L504-563: yagni: _tplPorts/_tplBaseRepo emit Repository/CrudRepository/BaseSupabaseRepository that no generated code implements or extends.`
- `arxa/lib/blueprint.dart:L329-358: shrink: _sortedJsonEncode/_prettySortedJson duplicate emit_stage.dart's _sortKeys+_encodeSorted — hoist one shared helper.`
- `arxa/lib/blueprint.dart:L2644-2698: delete: unused tabScreens param in _tplNavShellView/_tplNavShellVm.`
- `arxa/lib/emit_stage.dart:L990-1076: yagni: public emit() has one caller; adopt/supabaseUrl/supabasePublishableKey never passed and the .env block is dead — inline into emitStage.`
- `arxa/lib/emit_stage.dart:L43-48: shrink: _binaryExt list + _isBinary for one extension → endsWith('.png').`
- `arxa/lib/generate_view.dart:L828-896 + L158-164 + L383-399: delete: seedToSessionLiterals/AnchorDate/seedDefaultMap/dartStrSeed — only callers are tests.`
- `arxa/lib/generate_view.dart:L1522-1634 + L780-790 + L1512-1518 + L2318-2319: delete: extractCallSites/tplHomeAssetsStub, specProviders, stubIsDefault, children() — zero callers.`
- `arxa/lib/generate_view.dart:L1705-1751: delete: svgAssets/svgLedger/dropGlyph — write-only state, populated and never read.`
- `arxa/lib/generate_view.dart:L2097-2102: shrink: !inner.contains('\${') and !inner.contains(r'${') are the same check twice.`
- `arxa/lib/scaffold.dart:L684-715: yagni: ScaffoldEmitter facade class with zero callers — scaffold_cli calls scaffold() directly.`

### engine / memory / fabric / pipeline

- `arxa/lib/phases.dart:L102-148: yagni: PipelineRunner/PipelineAvailability — only tests touch them; server.dart uses runPhase.`
- `arxa/lib/memory_cache.dart:L37-43,L126-151: yagni: cacheBreakpointMarker/assemblePrompt test-only; engine calls cache directly.`
- `arxa/lib/memory.dart:L10-11,L136-149: delete: dead MemoryKinds.licence/.deploy constants and test-only countByKind.`
- `arxa/lib/memory_curate.dart:L66-85: yagni: lessonsFor/readFacts test-only; production calls appendLesson only.`
- `arxa/lib/tier1.dart:L52-71: delete: RealRunner — its own docstring admits it's unused.`
- `arxa/lib/engine.dart:L29-43: delete: Stage.gate is write-only; Stage.toJson uncalled.`
- `arxa/lib/trace.dart:L124-128: delete: _routeFactoryRe — declared with // ignore: unused_element.`
- `arxa/lib/intake.dart:L438,L481: delete: unused ValidationResult.ok getter and IntakeEngine.validate wrapper.`
- `arxa/lib/fabric.dart:L15-190: yagni: escalation and three notes fields parsed, stored, never read.`
- `arxa/lib/fabric.dart:L150-151: delete: ModelFabric.paramPolicy — zero callers.`
- `arxa/lib/pipeline_fsm.dart:L71-206: yagni: initPipeline({targets}) and approvePrototype({note}) — params never passed; targets state key write-only.`
- `arxa/lib/memory_analytics.dart:L27,L173: delete/yagni: LineCounts.total incremented never read; spend({since}) never passed in production.`
- `arxa/lib/gen_playbook.dart:L42-319: yagni: loadKitFacts + ~70 lines of README-mining reachable only via it — dead in production (bin reads facts JSON raw). Wire or cut.`
- `arxa/lib/gen_freshness.dart:L44: shrink: bool? buildFailed — only true/absent occur; make it bool = false.`

### gates

- `arxa/lib/gate_freeze.dart:L98-308: delete: _checkShape always returns true — dead early-return.`
- `arxa/lib/gate_freeze.dart:L184-189 + L892-897: shrink: _Derivation/_FutureServer single-use wrapper classes → records.`
- `arxa/lib/gate_freeze.dart:L767-803 + gate_lens.dart:L482-519: shrink: _bindStaticServer/_mime duplicated near-verbatim — hoist to gates.dart; same for the duplicated _Vp class.`
- `arxa/lib/gate_freeze.dart:L191-251 + gate_coverage.dart:L379-418: shrink: both re-implement the derivation inherit-walk — one shared resolver.`
- `arxa/lib/gate_freeze.dart:L419-425,L652-653,L927-939: shrink: _listEq/_setEq/_renderFallback single-use helpers — inline.`
- `arxa/lib/gate_freeze.dart:L1090 + gate_scaffold.dart:L610: stdlib: hand-rolled basename helpers → p.basename (package:path already a direct dep).`
- `arxa/lib/gate_scaffold.dart:L687-705: stdlib: _normalize reimplements p.normalize.`
- `arxa/lib/gate_coverage.dart:L439-447 + gate_deploy.dart:L159-167: shrink: _truthy duplicated verbatim — hoist one.`
- `arxa/lib/gate_runner.dart:L51,L91-166: delete/shrink: uncalled SuiteResult.allPassed; _runSingleGate alias fold; _tryBashGate extensions map dead except 'review' (and duplicates bin/arxa.dart's _runReviewGate).`

### design server / tools / selftest

- `arxa/lib/design_server.dart:L575-586: stdlib: _parseCookies hand-parses the Cookie header — dart:io ships req.cookies.`
- `arxa/lib/design_server.dart:L507-519 + L687-688: shrink/delete: _triedList re-derives resolveArtifact's candidate walk; serveRegistryFileCount uncalled.`
- `arxa/lib/design_server/worker.dart:L37,L306: delete/yagni: WorkerResponse.locale never read; findWorkerAssetsDir(from:) never passed.`
- `arxa/lib/design_selftest.dart:L148-172 + design_tools.dart:L72-75,L794-802: shrink: _findRepoRoot, _walkFiles, and recursive copy duplicated across the two files — share one each.`
- `arxa/lib/design_selftest.dart:L889-891 + L994-998: shrink/delete: 3-line claimed loop is one map().toSet(); mutationLabel uncalled.`
- `arxa/lib/design_tools.dart:L184-197 + L954-955: shrink/stdlib: designCheckLadder parses ladder.json twice; manual basename → p.basename.`

### lens / cdp

- `arxa/lib/lens.dart:L178-205: delete: runLensGate — zero callers (only a README mention).`
- `arxa/lib/cdp.dart:L106-107,L314-315,L405,L540-545,L706: yagni/delete: launch(chromePath:, extraArgs:), events getter, setViewport(deviceScaleFactor:), screencast maxWidth/maxHeight/everyNthFrame, ScreencastFrame.timestamp — all never passed/read.`
- `arxa/lib/cdp.dart:L584-620: yagni: setEmulatedMedia/elementScreenshot test-only (−36 if cdp.dart is lens substrate, keep if it's a general protocol lib).`
- `arxa/lib/lens_cli.dart:L253-261 + lens/crawl.dart:L334-341: shrink: _hexToRgb hand-rolled twice — hoist one.`
- `arxa/lib/lens_cli.dart:L452-457,L654-692: shrink: _color re-implements _emitJson; duplicated rung parsing; _matchRung one-liner with a doc promising unimplemented behavior.`
- `arxa/lib/lens/tokens.dart:L130-140: delete: tokensToJson — zero callers.`
- `arxa/lib/lens/native/flutter_vm.dart:L76-77 + sck.dart:L75-79: delete/yagni: uncalled start(); test-only tccOk().`

### misc

- `arxa/lib/story_map.dart:L335-343: stdlib: _esc hand-rolls HTML escaping — HtmlEscape().convert(s) is byte-identical and dart:convert is already imported.`
- `arxa/lib/story_map.dart:L40-41,L584-588: delete/shrink: _rankToPriority is a literal copy of _priorityOrder; _FeatureEntry holder → record.`
- `arxa/lib/crypto_aead.dart:L456-466: yagni: ChaCha20-Poly1305 (12-byte nonce) pair is test-only; production routes through XChaCha. Cut only with the RFC vector test, or keep as the vector seam.`
- `arxa/lib/deploy.dart:L264-266,L462-466: yagni/stdlib: targetStatus used only by self-test; _utcTimestamp hand-rolls toUtc().toIso8601String() (keep if seconds-precision parity with the Python port matters).`
- `arxa/lib/synthesize.dart:L445-463: shrink: _dumpSorted → SplayTreeMap key-sort + JsonEncoder.withIndent('  ') (verify against golden).`
- `arxa/lib/transform_tokens.dart:L71,L109: delete: _clamp255 guards provably-in-range 2-hex-digit parses — dead.`
- `arxa/lib/palette.dart:L20-82: stdlib: hand-rolled clamps → num.clamp; L84-85 dead if (h < 0) branch — Dart % is euclidean so the result is already non-negative (comment is wrong).`
- `arxa/lib/intake.dart:L565-575 + kit_facts.dart:L409-419: shrink: _stripAll/_stripEnds duplicate hand-rolled strip → one regex.`
- `arxa/lib/emit_htmx.dart:L88-90 + emit_playground.dart:L81-83: shrink: stripCssComments + contentRoot duplicated verbatim — hoist one shared copy.`
- `arxa/lib/kb_check.dart:L18-52: delete: verifyLinks option never passed true; only effect is a TODO warning.`
- `arxa/lib/server.dart:L14-18 + config.dart:L25,L49 + vault.dart:L61 + docs_lint.dart:L53-54: yagni: never-passed parameters (address, webRoot, service, memoryDir) — inline the defaults.`
- `arxa/lib/docs_lint.dart:L22-29: shrink: KbIssue is field-for-field DocIssue — reuse it.`
- `arxa/lib/api_map_scan.dart:L49-56: shrink: _stripDartComments byte-identical to capability_scan.dart's — hoist one.`
- `arxa/lib/deploy_cli.dart:L121-134 + watermark.dart:L146-162 + bin/arxa.dart:L835: shrink: three private copies of the walk-up repo/licence-path resolver — one shared helper (watermark's fallback also diverges despite the comment).`
- `arxa/lib/kit_lock.dart:L77-102: shrink: _discoverSkills/_discoverTools same loop, one filter apart — collapse.`
- `arxa/lib/scaffold_cli.dart:L28-56: shrink: 5 redundant break; statements — Dart 3 switch doesn't fall through.`
- `arxa/bin/arxa.dart:L481-483: shrink: _runCrud one-line wrapper — inline.`

### Checked and lean (no findings)

gateway.dart, crud.dart, emit_playground.dart, kb_build.dart, licence.dart,
lint_conventions.dart, intake_cli.dart, bin/arxad.dart, bin/licence_tool.dart,
secure_store.dart, process.dart, theme_map.dart, kit_conventions.dart,
validate_docs.dart, design_cli.dart, design_server/l10n.dart,
lens/{net,dom,a11y,skeleton,states,motion,ocr,native/adb,native/simctl},
gate_lens/gate_native_deps/gate_memory (beyond cross-file dedupes above).
Deliberate non-findings: hand-rolled SHA-1 and _jsonEqual (crypto/collection not
in pubspec — zero-dep by design), _pyStr/_pyRound byte-parity machinery pinned
by goldens, sri() openssl spawn (documented kimitail tradeoff).

### Out of scope but spotted

- `emit_stage.dart:L1138-1142` treats `{'isArxa': false}` as truthy — correctness bug (fixed 2026-07-31).
- `tool/lens_check.dart` + `tool/lens_shot.dart` superseded by lens_cli verbs.
- `design_server/worker.dart:230-260` duplicates CdpClient.launch internals.

---

## kit/ part 1 — analytics, auth, bluetooth, branding, compliance, core, data, deploy, documents, forms, genui_bridge, haptics, i18n (−1,500; ≈−1,100 if documented generated-app surfaces are kept)

### kit/core (biggest, ~5,500 lines)

- `kit/core/lib/common/kit_app_constants.dart:L99-516: yagni: ~445 const declarations, only ~35 referenced repo-wide; kElev/kSigma/kOffset/kPercent/kOpacity ladders fully unused (verified). Keep what's used, add rungs when needed. −400.`
- `kit/core/lib/common/kit_app_constants.dart:L7-25: delete: kd* device-constraint constants — zero references.`
- `kit/core/lib/services/error/kit_error_service.dart:L44-48,62-68,400-478: delete: widget event-log subsystem (widgetEvents\$/widgetEventCounts\$, getWidgetEvents, clearWidgetEvents) — zero consumers; mirrored in testing.dart. −150.`
- `kit/core/lib/services/error/kit_error_service.dart:L7-24: yagni: ErrorType (13 values)/ErrorSeverity (6 values) — no caller ever passes type:/severity:. Drop enums + threaded params (−60 with fake).`
- `kit/core/lib/services/error/kit_error_service.dart:L87-132,150-156,408-421: stdlib: hand-parses stack traces and hand-builds timestamps — Talker (already the dep) records time/level/stackTrace. −60.`
- `kit/core/lib/extensions/kit_selectable_extension.dart:L1-416: yagni: whole selectable layer — withSelectable has zero call sites (only locator registration + docs). Caveat: documented in core_playbook.mdx as generated-app API. −416 if generated apps don't emit it.`
- `kit/core/lib/common/kit_ui_helpers.dart:L26-96: delete: spacedDivider, screenWidth/HeightFraction, half/third/quarterScreenWidth, six getResponsive* helpers — no callers. −60.`
- `kit/core/lib/utils/kit_time_utils.dart:L1-42: delete: greeting helpers — referenced only in docs.`
- `kit/core/lib/utils/formatters/mobile_number_input_formatter.dart:L1-22: delete: exact subset of KitMobileAusInputFormatter's local branch.`
- `kit/core/lib/enums/kit_icon_position.dart:L1-14: delete: for KitCheckbox/KitRadio which don't exist in the kit.`
- `kit/core/lib/services/theme/kit_theme_service.dart:L17,27,60-63: yagni: BehaviorSubject wrapping the constant 'theme_mode'; themeKey\$ unconsumed → const String.`
- `kit/core/lib/utils/mouse_transforms/scale_on_hover.dart:L14: shrink: scale param accepted but ignored (hardcoded 1.1).`
- `kit/core/lib/extensions/kit_hover_extensions.dart:L99-104: yagni: kIsWeb gate makes the entire hover layer (~285 lines with mouse_transforms) a silent no-op on macOS/Windows desktop — fix the gate or delete the layer.`

### kit/data

- `kit/data/lib/repositories/seed/kit_seed_repository.dart:L87-146: shrink: ~60-line query evaluator byte-duplicated in testing.dart:L229-288 (fake's comment admits they must stay in sync). Extract one shared evaluator. −55.`
- `kit/data/lib/repositories/seed/kit_seed_persistence.dart:L69-77: stdlib: hand-rolled FNV-1a — crypto (already a dep) md5.convert replaces the loop.`
- `kit/data/lib/ids/kit_id_service.dart:L20-22: stdlib: hand-rolled UUID regex — installed uuid package ships Uuid.isValidUUID.`
- `kit/data/lib/kit_data.dart:L147-160,191-202,235-248: shrink: same entity-registration boilerplate ×3 → one _registerRepositories helper. −25.`
- `kit/data/lib/repositories/appwrite/kit_appwrite_repository.dart:L103-133,136-172: shrink: watchById/watchAll share ~30 lines of scaffolding → one _watch(channel, fetch). −15.`
- `kit/data/lib/kit_data.dart:L59-65: delete: KitData.registry static getter — zero references.`
- `kit/data/lib/schema/kit_schema_registry.dart:L24-30: delete: schemaFor — zero references; all use schemasByTable.`

### kit/genui_bridge, compliance, auth, haptics, analytics, deploy, documents

- `kit/genui_bridge/lib/src/adapters/openai_chat_stream.dart:L136-142 + anthropic_chat_stream.dart:L114-120: shrink: identical _resolve helper duplicated in both adapters → hoist one into sse_transport.dart.`
- `kit/genui_bridge/lib/src/a2ui_stream_parser.dart:L61-118: stdlib: hand-rolled StreamController pause/resume/cancel plumbing — the same package's sse_transport.dart already uses Stream.eventTransformed. −20.`
- `kit/compliance/lib/src/kit_consent_gate.dart:L9-77: yagni: one-method wrapper over outstandingDocuments() + sealed result class re-expressing "list is empty". −70.`
- `kit/compliance/lib/src/kit_consent_store.dart:L100-103: delete: InMemoryKitConsentStore.records — zero callers.`
- `kit/compliance/lib/src/kit_compliance_registry.dart:L55-56: delete: clear() — zero callers.`
- `kit/compliance/lib/src/kit_consent_status.dart:L31-114: shrink: four sealed subclasses × ~20 lines ==/hashCode/toString boilerplate → enum-kind class (−65; judgment call, sealed is the codebase idiom).`
- `kit/auth/lib/src/models/auth_session.dart:L26-37: delete: AuthSession.copyWith — zero callers.`
- `kit/auth/lib/src/backends/seed_auth_backend.dart + providers/kit_oauth_provider.dart + apple/ + google/: yagni: 119 lines of throw-only stubs, no real implementors — real seed backend lives in arxa/lib/tier1.dart. Caveat: tracked in config/kit-registry.json/stub-inventory.md; if that registry is load-bearing, finding is void.`
- `kit/haptics/lib/src/kit_haptic_service.dart:L61,92,128,170: shrink: BehaviorSubject wrapping constant 'haptic_enabled' → static const.`
- `kit/haptics/lib/src/kit_haptic_service.dart:L62,68-69,148,171: delete: _lastHapticEventSubject/lastHapticEvent\$ — zero consumers.`
- `kit/haptics/lib/src/kit_haptic_service.dart:L81-84: delete: hapticStateLabel\$ — zero consumers.`
- `kit/haptics/lib/src/kit_haptic_service.dart:L71-74: delete: three private getters duplicating the public ones on L77-79.`
- `kit/haptics/lib/src/kit_haptic_service.dart:L56: yagni: ListenableServiceMixin — listenToReactiveValues never called; drop mixin + stacked import.`
- `kit/haptics/lib/src/kit_haptic_extension.dart:L51-77 + service L157-164: yagni: 16 one-line convenience wrappers, zero callers (public-surface judgment call).`
- `kit/analytics/lib/src/kit_analytics_service.dart:L52-56: yagni: removeBackend/clearBackends — zero callers; backends registered once at startup.`
- `kit/deploy/lib/src/models/kit_deploy_config.dart:L7,22-23: delete: patchNumber — declared, never read.`
- `kit/documents/lib/src/kit_pdf_service.dart:L40-61: delete: UnimplementedKitPdfService — superseded by PdfrxPdfService; only its own throw-test references it.`

Lean already: forms, bluetooth, branding, i18n (stub flows/throwing backends are documented phase stubs, not flagged).

---

## kit/ part 2 — maps, media, motion, notifications, payments, permissions, security, showcase_app, state, support, ui_library, wifi (−3,200)

### The big one: kit_action (2,471-line module, ~9 real call sites using 4 methods)

- `kit/ui_library/lib/utils/kit_action/kit_action_builder.dart:L146-659,L679-717: yagni: 22 of ~30 fluent methods have zero call sites repo-wide (withLoadingSnackbar/withErrorSnackbar/withSnackbars/withNotificationType(s)/withDialogs/withBottomSheets/onSuccess/onComplete/onLoadingState/onSuccessState/onErrorState/withUIStateCallbacks/withProgress/asStream/withAutoCleanup/asCancellable/withTimeout/withDebounce/withThrottle/withDebugMode/withClearLoadingBeforeSuccess/withLoadingFor/onError, executeAsStream/executeAsCancellable). Only withErrorFallback, withRetry, withSuccessSnackbar, execute are ever called (9 sites in kit_overlay_extension.dart + kit/data/lib/facades/kit_data_facade.dart). Keep those four, delete the rest. −550.`
- `kit/ui_library/lib/utils/kit_action/managers/{stream_manager,success_manager,loading_manager}.dart: yagni: 351 lines of managers serving only the deleted features above. Delete with them. −351.`
- `kit/ui_library/lib/utils/kit_action/executors/async_executor.dart + kit_action_config.dart: shrink: 544-line executor+config collapses to a ~150-line try/catch+retry+snackbar function once dead feature branches go. −390.`

### Dead exported surface in ui_library

- `kit/ui_library/lib/extensions/kit_overlay_extension.dart:L1-524: delete: withOverlay/KitOverlayService/KitOverlayOptions — zero call sites anywhere (incl. arxa templates); service locator-registered in showcase_app but never invoked. Also the only consumer of KitAction.watch/dispose, so those + their _subscriptions map in kit_action.dart:L149-228 die with it. −650.`
- `kit/ui_library/lib/enums/kit_widgets_enum.dart:L1-179: delete: exported via ui_library.dart but not one of its 8 enums is referenced anywhere. Includes KitContainerExpansionLimit — an enum with a single value. −179.`

### Throw-only "phase-later" stubs (later can scaffold for itself)

- `kit/media/lib/src/editing/media_editing_service.dart:L1-64: delete: MediaEditingService + StubMediaEditingService, every member throws, referenced nowhere. −64.`
- `kit/media/lib/src/video/video_player_service.dart:L179-218: delete: StubVideoPlayerService — exists only so a test can assert it throws. Delete class + that test. −40.`
- `kit/payments/lib/src/providers/stripe/stripe_payments_provider.dart:L20-41 + paypal/paypal_payments_provider.dart:L20-41: delete: both stubs throw on every member; never registered or referenced. −82.`
- `kit/maps/lib/src/providers/mapbox/mapbox_provider.dart:L12-27 + open_street_map/open_street_map_provider.dart:L12-26: delete: same throw-only stub pattern; drop the mapbox/openStreetMap enum cases in kit_map_provider.dart:L9 too. −55.`
- `kit/notifications/lib/src/backends/{fcm_push_backend.dart:L19-66,email_backend.dart:L19-28,sms_backend.dart:L19-30}: delete: three throw-only stub backends, never referenced. −120.`
- `kit/state/lib/retry/kit_retry_policy.dart:L1-47 + persistence/kit_state_persistence.dart:L9-36: delete: self-described STUBs "scheduled" for later phases; zero references outside kit/state. (Bonus: _pow loop reinvents dart:math pow, moot once deleted.) −83.`

### Hand-rolled what Dart 3 ships

- `kit/state/lib/state/kit_state.dart:L21-94: stdlib: when/maybeWhen/map/maybeMap combinators hand-rolled on a sealed class — the file's own doc says "use pattern matching (switch) directly". Native switch expressions do all four. −74.`

### showcase_app scaffold boilerplate

- `kit/showcase_app/lib/ui/views/**/*_view.{desktop,tablet}.dart: delete: 26 files / 618 lines of stacked-template "Hello, DESKTOP UI - …!" placeholders; only .mobile.dart views are real. Point ScreenTypeLayout tablet/desktop at the mobile view (or drop the layout) and delete the 26 files. −618.`

### Checked and lean (no findings)

security (app-lock controller/config/outcome, crypto, biometric), motion
(KitWake/KitMotionSpec/KitMotionAdapter), maps core providers, payments core +
pay button, permissions, wifi, support sinks, notifications local service,
media audio/capture, ui_library port widgets (catalog inventory by design —
unused-by-repo ≠ dead for a widget library), all testing.dart fakes.
KitNotificationService (426 lines) looked suspicious but is heavily used by
showcase_app — keep.

---

## Root tooling — hooks/, tools/, gates/, pipeline/, config/ (−480)

hooks/*.js steelmanned: the hook runners execute per-event shell commands, so
Node entry points are the registration format, not a choice. Not flagged for
being JS.

- `hooks/arxa-doc-enforce.js:47-49: shrink: hasMarker() wraps fs.existsSync in try/catch — existsSync never throws. Body is return fs.existsSync(MARKER).`
- `hooks/arxa-doc-health.js:23-31,36-55 + hooks/arxa-doc-enforce.js:84-92,34-36,60-68: shrink: identical stdin-read/JSON.parse/file_path-extract preamble (~10 lines) and identical repoRoot-locate + spawnSync('dart', …'docs') block (~15 lines) duplicated across both hooks. One shared sibling require('./_doc-hook-common.js') halves both files. Modest win; skip if zero-dependency hook files are valued.`
- `tools/sweep_rename.sh:1-67: delete: whole file. All patterns are identity mappings (arxa:arxa — header literally says "rename arxa → arxa"); sed replaces every string with itself; the script can only ever no-op. The rename already happened.`
- `tools/phase5_kit_copy.sh:1-68: delete: one-shot migration, already applied (kit/ exists). docs/plans/arxa-dart-only-tooling.md:227 already classifies both tools as "transient", and its hardcoded $SRC=/Volumes/... abs path violates the repo's own R3 (config/forbidden_abs_prefixes.txt). A re-copy is a 3-line rsync when actually needed.`
- `gates/review/review.dart:L1199-1490: delete: _fileFixtureSections (~290 lines) plus the fixturesDir.existsSync() branch at 1158-1163 — provably unreachable: the code itself states the fixture tree "is NOT shipped with this repo" (1153-1157). gates/review/selftest.sh covers the same negatives end-to-end via the CLI.`
- `gates/freeze/freeze.sh:74-82,506-507 + every sarif_result call: yagni: the SARIF "one transport" layer (gates/_common/sarif.sh, state_reader.sh, design_hash.sh) was designed for 8 gates and never built — _common/ does not exist, so both source lines fail at runtime and sarif_result/state_targets/state_set are unresolved commands. Build _common/ or drop the indirection; stderr/stdout is the de-facto transport today.`
- `gates/freeze/freeze.sh:121-143: shrink: viewport/inherits derivation from targets.derivation.json implemented a second time here (embedded python vps_of recursion) — arxa/lib/gate_coverage.dart:44-129 and scaffold_cli.dart:87 already parse the same table in Dart. One derivation should call the other.`
- `gates/README.md:24-59: yagni: documents 8 gates plus run_all.sh, test_gates_can_fail.sh, and the _common/ layer; only freeze/ and review/ exist. Trim to what shipped or build the rest — same for gates/review/README.md:9.`
- `pipeline/README.md:3-7: delete: the paragraph describing pipeline/pipeline.sh — no such file; pipeline/ contains only state/.`
- `config/arxa.config.json:10-14: yagni: dead keys. prototypeRuntime self-declared dead in docs/INDEX.md:47; prototypeServer, escalationLimit, dependencyMode, kit, viewportClasses have no reader in any in-repo code (grep hits are docs/plans only). Only targets and viewports are consumed. (evidence.json, kit-registry.json, model-fabric.json, the two .txt lists, pipeline/state/*.json are all read — clean.)`

---

## Re-review checklist (when implementation completes)

1. Re-run the four passes (arxa / kit×2 / root tooling) — new code will have
   landed; this document is a snapshot at commit 4f9c458.
2. Resolve the "wire or cut" questions first: credentials/harness/runtime_config
   ports, kit_action generated-app surface, selectable layer, haptic wrappers.
3. The throw-only stub findings overlap `docs/plans/stub-remediation.md` —
   whichever happens first (implement or delete) voids the other.
