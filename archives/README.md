# archives/

Retired material, kept for history. Nothing here is live — do not cite it as
current behavior. The product is `appbox`; `app-box`/`app_box` spellings in
these directories are historical and intentionally left as-is.

- **app-box-app/** — the old dogfood prototype of appbox's own desktop app,
  designed with the retired `app-box-designer` flow. Archived 2026-07-28 in
  `6530bb9` ("chore: archive documents"). Superseded by the current
  `appbox-studio` app and its design under `designs/appbox-studio/`.

- **appbox-variants/** — six candidate design directions (canvas, focus,
  native, precision, thread, tool) explored before the contract was settled.
  Archived 2026-07-29 in `857f64f` when the chat-centric contract won.
  Superseded by `docs/intake/` (story map, 101 stories).

- **arxa-studio-v2/** — the studio's own v2 design tree (hub-hosted stage
  shells, stacked MVVM) that replaced v1 as the canonical studio design on
  2026-08-16. Archived 2026-09-07: arxa studio is now a fork of dsh, so the
  studio no longer designs itself through the design tool. `designs/arxa-studio`
  (v1) stays in-tree as the design arxa's own gates, probes and flow-services
  parity suite run against. Plans written against v2 — studio-v2-boot-sequence-wiring,
  studio-v2-emit-blockers, inspector-*, screen-vocabulary-identifier-rename,
  provenance-routed-text-editing — are superseded by the dsh fork.

- **design-v1/** — first-pass design docs (brief, personas, journeys, flows).
  Archived 2026-07-28 in `6530bb9`. Superseded by design-v2, which was itself
  later superseded by `docs/intake/`.

- **design-v2/** — the old design documentation: personas (Evan/Michelle),
  journeys, the flows library, and design briefs written in retired `app_box`
  vocabulary. Archived 2026-07-28 in `6530bb9` when the story-map-driven
  design flow replaced it. Superseded by `docs/intake/` (brief.md +
  story-map.json + story_map.html, produced by the appbox-story-mapper skill).

- **spikes/** — the `genui` spike (exploration of Google's genui SDK).
  Archived 2026-07-29 in `857f64f` alongside the variants. Superseded by the
  production `kit/genui_bridge` kit.

- **tooling-pre-dart/** — the retired Python/bash/Node tooling (gates,
  pipeline, pre-Dart skills, tools). Archived 2026-07-31 in Phase 7
  (`b5e8137`, "retire all Python/bash/Node tooling") per
  `docs/plans/appbox-dart-only-tooling.md`. Superseded by the Dart `appboxd`
  daemon; each retired piece moved here only after a golden-diff proved the
  Dart replacement identical.
