# Take code and leave — the output is hers

Actor: Michelle (buyer, evaluation mode) · Shell: ship-shell · Surfaces:
`ship.released` (null surface — shipped · version · rollback) · Decision refs:
architecture.md §3 (output/app/ contains no reference to app_box — builds with
plain `flutter build` on a machine that has never seen this tool), §17 decision
O1 (vendoring the kit means no external dependency; the app keeps building even
if she never pays app_box again); journey J10
([`../../journeys/michelle-buyer-journey.md`](../../../journeys/michelle-buyer-journey.md) §5)

## Trigger

The build went green and Gate 2 accepted it. Michelle does not want a store
submission — she wants the code. She opens the output location.

## Entry / exit

- Entry criteria: Gate 2 accepted (green build); `output/app/` written and
  content-hashed in `work/run.json`. No 💳 check on this flow — the licence
  precondition ran before the builder phase (§17), and taking the output repo
  is not a payable action.
- Exit states: **taken** — Michelle has copied `output/app/` into her own repo,
  inspected it, run `flutter build`, and left · **blocked** — she finds a
  violation of a §3/§17 invariant (output references app_box; app depends on a
  private registry; a kit throws that was offered without a STUBBED label) and
  the evaluation fails on a property the architecture promised would hold.

## Happy path

1. Build green (Gate 2 accepted). `ship.released` renders the shipped version
   and rollback info in plain language — *"Build 1.2.0 is ready. The code is at
   `output/app/`."* No Gate 3 prompt is forced on Michelle; the deploy triple
   is Evan's concern, not hers
   (see `../../evan-founder/ship-shell/confirm-ship.md`).
2. Michelle navigates to `output/app/`. It is a Flutter project — `pubspec.yaml`,
   `lib/`, `test/`, platform folders. No app_box directory, no app_box import,
   no generated manifest that points back at this tool.
3. She opens `lib/`. Ordinary Stacked MVVM: every surface is a
   `view`/`viewmodel` pair (`<name>_view.dart` + `<name>_viewmodel.dart`),
   routes in `app.dart`, services on the locator. Readable, extensible, the
   same shape she would have written by hand.
4. She copies the folder into her own repo and runs `flutter pub get` then
   `flutter build` on a machine that has never seen app_box. It builds.
5. Evaluation complete. She has her code — no export button, no "upgrade to
   download," no runtime she does not control. She leaves.

## Decision points

- **Take code vs deploy to store:** Michelle takes code. Gate 3 (ship confirm)
  is the deploy path — Evan's, not hers
  (`../../evan-founder/ship-shell/confirm-ship.md`). The surface offers both;
  the buyer's journey ends at the code, not the store.
- **Inspect code vs trust it:** Michelle inspects. She has been burned by
  generated code she could not extend (the FlutterFlow burn — see Edge cases).
  The output is designed to be read, not black-boxed: view/viewmodel pairs, no
  proprietary format, no minified intermediate.

## Edge cases

- **Output references app_box — FORBIDDEN.** §3 invariant: `output/app/`
  contains no reference to app_box. If an import, path, or generated comment
  leaks app_box into the delivered app, the build would not be "ordinary
  Stacked MVVM" and the evaluation fails on a promised property. This is
  asserted mechanically, not by inspection.
- **Shipped app depends on a private registry — FORBIDDEN.** §17 decision O1:
  the kit is vendored at a pinned SHA, so the shipped app has no external
  dependency. If `pubspec.yaml` pointed at a registry that stops resolving
  when her licence lapses, Michelle's code would break the day she stops
  paying — the exact incumbent behaviour this product is positioned against.
  Vendoring is the feature, not legacy.
- **Generated code she can't extend.** The FlutterFlow burn: export produces
  code that is technically valid but practically unreadable, locking the buyer
  into regeneration for every change. This flow exists to prove the opposite —
  the output is hand-editable Stacked MVVM. If Michelle cannot extend a
  viewmodel without re-running app_box, the positioning collapses.
- **`UnimplementedError` on an offered kit.** A kit that throws was offered
  without a STUBBED label — she was misled at selection time and discovers it
  only at build/run. Stubs must be labelled before the builder phase (§17); an
  unlabelled stub reaching `output/app/` is a contract violation, not a
  surprise to route around.
- **`flutter build` fails on a clean machine.** The §3 promise is that the
  delivered app builds with plain `flutter build` on a machine that has never
  seen this tool. A failure here is not a Michelle problem to debug — it is the
  invariant breaking, and it breaks the evaluation.

## Screens

| Step | Surface / sheet / dialog |
|---|---|
| 1 | `ship.released` (null surface) — shipped version + output path, in plain language |
| 2–4 | None — the output repo is a file-system path, not an app_box surface. Michelle is in her own editor/terminal from here |
| 5 | Evaluation complete; no further surface |

## Notes

- **This journey existing IS the positioning against the incumbent's one-way
  export** (journeys J10). The incumbent lets code go in but charges to get it
  out; app_box's output is ordinary Stacked MVVM the moment the build is green.
- The output is not an "export tier." There is no free/paid split on getting
  your code out — the payable inflection is the *builder* phase (§17), not the
  output. Once Gate 2 is green, the code is hers whether she keeps paying or
  not.
- No runtime lock-in: vendoring (§17 O1) means no private registry, no
  licence-check call at app startup, no phone-home. The app is inert without
  app_box.
- Evan's counterpart: `../../evan-founder/ship-shell/confirm-ship.md` (Gate 3 —
  the deploy path Michelle skips). Same surface, different exit: Evan confirms
  the deploy triple and writes to a store; Michelle takes the repo and leaves.
- MEM-B (`output/MEM-B.md`, §4) travels *with* the app — it records decisions
  taken for this client, surfaces built and why. It is documentation Michelle
  keeps, not a coupling back to app_box.
