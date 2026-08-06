# A2UI reference fixtures — provenance

Files in this directory are **verbatim reference copies** of the upstream
A2UI v0.9 specification artifacts this package is pinned against. They are
not loaded at runtime; they exist so the wire shapes in `lib/` can be
diffed against the spec, and so tests can anchor to the canonical schema.
Do not edit them by hand — re-fetch and update this header instead.

| File | Source URL | Spec version | Date fetched |
| --- | --- | --- | --- |
| `server_to_client.json` | https://github.com/google/A2UI/blob/main/specification/v0_9/json/server_to_client.json (raw: https://raw.githubusercontent.com/google/A2UI/main/specification/v0_9/json/server_to_client.json) | A2UI **v0.9** (Stable, created 2025-11-20) | 2026-07-28 |

Cross-checks the shapes in `lib/src/appbox_kit_a2ui_message.dart` were verified against
on the same date:

- The spec prose: https://github.com/google/A2UI/blob/main/specification/v0_9/docs/a2ui_protocol.md
  (served on the docs site as `docs/public/specification/v0.9-a2ui.md`).
- The renderer's ground truth — genui 0.10.1's `a2ui_core` message models:
  https://github.com/flutter/genui/blob/main/packages/a2ui_core/lib/src/core/messages.dart
  (requires `version == "v0.9"`, exactly one verb key per envelope).
- genui's streamed-chunk parser (extraction semantics the bridge mirrors):
  https://github.com/flutter/genui/blob/main/packages/genui/lib/src/transport/a2ui_parser_transformer.dart
- genui package manifest confirming version 0.10.1 and the `a2ui_core` dep:
  https://github.com/flutter/genui/blob/main/packages/genui/pubspec.yaml

## Known disagreements between spec, README, and code (as of 2026-07-28)

- **Rename-in-flight:** A2UI v0.8 named the verbs `surfaceUpdate`,
  `dataModelUpdate`, and `beginRendering`. v0.9 renamed them to
  `updateComponents`, `updateDataModel`, and `createSurface`. The docs site
  still shows the old names in places. The bridge accepts the v0.8 aliases
  for the two same-shaped renames on read and always writes canonical v0.9
  names (`beginRendering` is NOT aliased — its body shape differs).
- **Strictness:** the schema (`server_to_client.json`) is stricter than the
  renderer — it declares `additionalProperties: false` on every envelope and
  body and `minItems: 1` on `components`; `a2ui_core`'s `fromJson` enforces
  neither (it only requires the `v0.9` version string and ≤ 1 verb key, and
  reads fields with bare casts). The bridge follows the renderer's acceptance
  behavior on read and emits schema-conformant canonical JSON on write.
- **genui README vs code:** genui's README does not state an A2UI version;
  the `a2ui_core` code is the authority and pins `version == "v0.9"`.
  A2UI v0.9.1 (Current) changes no message shapes relative to v0.9 — only
  prose and the version badge differ in the spec documents.
