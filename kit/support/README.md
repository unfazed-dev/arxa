# appbox_kit_support

In-app **support** for `appbox_kit` apps: a screenshot+annotation feedback flow
bundled with a Talker log export, routed to a swappable submission sink.

## Scope

- **`AppBoxKitSupportService`** — the entry point:
  - `startFeedbackFlow(context)` opens the `feedback` package's screenshot +
    annotation flow and returns a typed `AppBoxKitFeedbackSubmission` (null if dismissed).
  - `captureDiagnostics()` / `withDiagnostics(submission)` export the **injected**
    Talker's log history into a `AppBoxKitDiagnosticsBundle` (capped at
    `maxDiagnosticEntries`, most recent kept) and attach it.
  - `submit(submission)` routes to the sink; `collectAndSubmit(context)` does
    both.
- **`AppBoxKitSubmissionSink`** (port) + **`AppBoxKitLocalFileSubmissionSink`** — the working
  default writes `feedback.json` + `screenshot.png` (+ `diagnostics.log`) to a
  timestamped folder under the app-documents directory. `AppBoxKitCallbackSubmissionSink`
  wraps any callback (Supabase insert, existing HTTP client, web).

## Talker is injected, not created

Apps already register a `Talker` as a lazy singleton. `AppBoxKitSupportService`
**reads from that instance** (`required this.talker`) — it never constructs a
competing logger, so the exported diagnostics are the same logs the app has been
writing all along.

## Non-goals

- **No dependency on `appbox_kit` core, `stacked`, or `stacked_services`.**
- No transport of its own is bundled beyond the local-file default: the email
  and github-issue sinks are **stubs** (`UnimplementedError`) — no SMTP/HTTP
  client is pulled until a host opts in.
- Not a crash reporter — pair Talker with Crashlytics/Sentry separately; this
  captures *user-initiated* feedback plus a log snapshot.

## Host-app wiring (out of scope for this package)

- Wrap the app in **`BetterFeedback`** at the root (from the `feedback`
  package) — `startFeedbackFlow` requires that ancestor.
- `feedback`'s screenshots need Flutter's **CanvasKit renderer** on web, and
  platform views (maps, webviews) render blank in the screenshot.
- `AppBoxKitLocalFileSubmissionSink` uses `dart:io`; on web, inject a
  `AppBoxKitCallbackSubmissionSink` instead.

## Phase

**0.1.0 — priority implemented.** `AppBoxKitSupportService` (feedback flow +
diagnostics bundling + submit) and `AppBoxKitLocalFileSubmissionSink` are complete and
analyzer-clean, on `feedback: ^3.2.0` and `talker_flutter: ^5.1.17`.
`AppBoxKitEmailSubmissionSink` and `AppBoxKitGithubIssueSink` are real-signature stubs.

## Testing

`import 'package:appbox_kit_support/appbox_kit_testing.dart';` for
`RecordingAppBoxKitSubmissionSink` (records `submissions`, scriptable `result`),
`appBoxKitFakeFeedbackSubmission(...)`, and `appBoxKitCannedDiagnosticsBundle(...)` — assert the
diagnostics/submit path without a widget tree or a real Talker.
