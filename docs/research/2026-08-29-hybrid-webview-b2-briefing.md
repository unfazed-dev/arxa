# Hybrid webview ↔ native mobile plan — B2 briefing (2026-08-29)

READ-ONLY research pass. Paths relative to `totem_labs/`. Verdict up front:
**the hybrid plan is documented, in three independent layers** — studio grill
docs (D30, mobile-flutter-migration-spec), arxa's own mobile docs
(mobile-pairing-transport.md, merge-companion plan, architecture.md §14–15), and
the shipped `mobile_flutter` code itself (webview_flutter 4.14.1 + native
pairing/push/approvals). The owner's "mix webview of arxa studio dsh and have
native ui mix" is real, not folklore — its most precise statement is
arxa-studio `shell-language-decision.md:14`.

## Sources (file:line quotes)

- **arxa-studio/docs/plans/shell-language-decision.md:14** — "Webview + native
  mix is mature on iOS/Android: native pairing/QR, push, biometric approvals,
  share sheets around a webview session view."
- **arxa-studio/docs/plans/mobile-grill-decisions.md:23-25 (M4)** — "Surface:
  full studio. The mobile app is the full studio, trimmed per-view only where a
  surface genuinely cannot work on mobile — decided as we go, not upfront.
  Native iOS/Android app, not a web wrapper." (Note the tension: M4's headline
  says "not a web wrapper", but the delivery mechanism below is a webview.)
- **arxa-studio/docs/plans/mobile-grill-decisions.md:46-51 (M8)** — "Offline
  data: online-only v1, cairn_tauri offline-first later… Offline-first arrives
  when the agent-owned cairn_tauri work… lands and is integrated."
- **arxa-studio/docs/plans/mobile-flutter-migration-spec.md:9** — "The scaffold
  is a **single-screen pairing shell + webview handoff**. Everything below is
  verified in code."; **:56 (M4)** — "the mobile app is the full studio via
  webview, not a companion subset"; **:88** — "webview_flutter 4.14.1 was
  verified for the desktop ADR; confirm it… for the iOS/Android session
  surface, incl. cleartext `http://127.0.0.1` allowances."
- **arxa/docs/plans/mobile-pairing-transport.md:12** — "on `connected` it
  navigates the webview to `studio_url` (decision M4)"; **:22-24 (M4
  delivery)** — "Desktop bridges each authed stream to the local engine HTTP
  server. Phone runs a loopback TCP proxy (random port) that forwards to iroh
  streams; `studio_url` = `http://127.0.0.1:<proxy-port>/`."
- **arxa/mobile_flutter/pubspec.yaml:2** — "Arxa Studio mobile shell — native
  pairing/push/approvals + full-studio webview session."; **:46-47** — "Studio
  session webview — 4.x verified for the desktop ADR (4.14.1). /
  webview_flutter: ^4.14.1".
- **arxa/docs/plans/merge-companion-into-one-flutter-project.md:38** —
  "`webview_flutter` is used only on the" [mobile target; deps don't fight].
- **arxa/docs/plans/architecture.md:535, 616-618** — "## 14. The hybrid —
  already authored, simply not wired"; "The companion opens it **fullscreen in
  a WebView**… A **floating, draggable FAB** rides above the WebView: arxa
  controls…" (earlier companion-app concept: webview prototype + native FAB).
- **arxa-studio/docs/plans/arxa-studio-grill-decisions.md:256-263 (D30)** —
  "Desktop app tech: C, Tauri shell over the dsh engine… Studio UI stays the
  existing web UI (`arxa.studio.localhost:7891`); no Flutter rewrite." (The
  same web UI the phone loads; Flutter desktop-wrap explicitly rejected there
  but endorsed for mobile at shell-language-decision.md:14.)
- **arxa-studio/docs/plans/arxa-studio-grill-decisions.md:456-479 (D46)** —
  "Cairn placement: git = file-content rail…; cairn = DB rail — index/session
  state, **mobile's projection of the tree (M7/M8)**, and the concrete
  implementation of the D32 BYO wire contract (local SQLite ↔ user's
  Postgres)." + "v1 keeps it boring: mobile online-only (M8)… cairn CRDT merge
  stays out of the authoritative path until offline-first ships."
- **arxa/docs/plans/doorbell-decision-2026-08-29.md:85-96 (B2 Sync-first)** —
  "Approvals ride cairn sync: desktop hosts or embeds a cairn-server, mobile
  syncs an `approvals` table, the server fan-out fires the silent doorbell…
  couples the doorbell to a studio data-path decision that hasn't been made." /
  "Recommendation: B1 now; B2 when the studio data-path decision lands."

## What the hybrid plan says

Native shell owns: QR pairing (M2), iroh tunnel (M1), push registration (M7),
approvals answering, share sheets. The webview owns: the *entire studio UI*,
loopback-proxied from the engine over iroh — "full studio… via webview, not a
companion subset" (migration-spec M4). M4's "not a web wrapper" phrase means
"not merely a thin wrapper app" — the native half is real and growing
(approvals shell, APNs bridge); it is not a rejection of the webview surface,
which the same doc's own delivery contract mandates.

## What dsh web gives the phone for free

- **Sidebar/session rows**: `arxa-studio/plugins/arxa-sidebar/package.json` —
  "arxa's own sidebar: the stock shell (brand, fold, New-session CTA) plus the
  ORGANISATIONS rows world — … list orgs, projects, sessions and trash from
  the file-org-shell lifecycle." Replaces stock
  `@deepseek-ai/dsh-client-ui-sidebar` (README: brand row, New Session,
  session browser via `sidebar.workspaces` slot, settings seat).
- **Org model**: D36-D44 — user-chosen workspace root, org repo + nested
  project repos (D37), fixed five categories (D42), version chip pill (D44).
  The sidebar browses exactly the orgs/folders/projects tree.
- **Approval/question surfaces in-web**:
  `@deepseek-ai/dsh-client-ui-user-questions` registers the `question`
  entry in the conversation composer; `dsh-user-approval` is the
  channel-neutral one-shot approval seam (fail-closed, audit-paired). So the
  web UI can already render pending questions inline.
- `dsh-web-app` README: the browser-surface bundle serving the built
  frontend; `dsh web` URL is what the phone's loopback proxy bridges to.

## Mobile webview state today

- `mobile_flutter/lib/ui/views/studio_shell/studio_session/studio_session_view.dart:2-3,33`
  — "the full studio via webview — navigates to the transport's loopback
  studioUrl; whole-screen webview per the screen-level split rule"; renders
  `WebViewWidget(controller: controller)`.
- `studio_session_viewmodel.dart:24` creates a `WebViewController` when
  connected; the test pins "Not connected: no studioUrl, so no webview
  controller is created".
- Android `network_security_config.xml` / iOS `Info.plist:73`: loopback-only
  cleartext for the studio session webview.
- `app.dart:16` — "studio session is the webview handoff; approvals is
  notification-driven." Approvals shell is native and now live (phone leg
  complete, doorbell memo:112-156): `approvals_list_viewmodel.dart:1-5` —
  "Pull-based v1: refresh on model-ready, after each decision, and on
  pull-to-refresh; the repository exposes watch() for later reactive wiring."
  No `flutter_inappwebview`; only `webview_flutter`.

## B2 implications

**Docs-supported:**
- B1 (visible doorbell → approvals shell) is shipped and phone-proven; the
  memo itself says B2 waits on "a studio data-path decision that hasn't been
  made" (:88-89) — that decision is exactly D46 + M8.
- D46 already assigns cairn a job that the webview **cannot** do: "mobile's
  projection of the tree (M7/M8)" and the D32 BYO wire contract. Browsing in
  the webview is online-only over the tunnel; M8 defers offline-first but
  explicitly to *cairn_tauri*, i.e. B2 is the documented path to offline
  org/project browsing, push-render (silent doorbell →
  `waitForFirstSync()` → render, per atlet's proven pattern, doorbell
  memo:58-61), and D46's append-only mobile edit log.
- Native approvals already pull over the tunnel; a synced `approvals` table
  would make the notification buzz *and* the list reactive without the tunnel
  up (watch() seam exists).

**Would be a NEW decision (not supported by docs today):**
- Collapsing B2 to "silent doorbell + webview" only — i.e. dropping native
  sync of orgs/folders/projects — would contradict D46's cairn placement and
  M8's offline-first intent. It's arguable (webview + relay covers most
  cases per M8's "iroh relay covers most gaps") but nothing in the docs makes
  that call; the memo's open item (:103-105) — "Whether the desktop ever
  hosts/embeds cairn-server (the B2 enabler)" — remains explicitly open.
- A narrower B2 that syncs *only* the approvals table (not the whole tree) is
  consistent with D46's disjointness rule and would be the minimal
  docs-compatible version.

## Open questions for the grill

1. Does B2 mean full D46 cairn (mobile tree projection + BYO wire) or
   approvals-table-only first? (D46/M8 support either; scope is a new call.)
2. Does the desktop ever host/embed cairn-server (memo open item :103-105)?
3. If the phone browses orgs in the webview online-only, is offline browsing a
   real product requirement, or is M8's "iroh relay covers most gaps"
   acceptable forever?
4. M4's "not a web wrapper" vs webview-as-full-studio — reconcile the wording
   before it misleads a future decision.
5. Does the in-web user-questions UI (dsh-client-ui-user-questions) plus native
   approvals shell double-present the same pending question on the phone?
