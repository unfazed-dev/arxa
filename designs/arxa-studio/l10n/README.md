# l10n/ — arxa design string catalogs

- `app_en.arb` — English template, the SSOT every locale mirrors key-for-key.
- `app_pl.arb` — Polish. **Provenance: agent-translated 2026-07-29.** Fine for
  design/layout testing; a native-Polish review pass is required before any
  launch copy ships (MT + human post-edit is the documented industry norm).
- `app_qps-ploc.arb` — generated pseudo-locale for layout stress; regenerate
  with `node skills/arxa-designer/runtime/pseudolocalize.mjs designs/arxa-studio`
  after editing `app_en.arb`, then re-run each model's `generate.mjs`.
  (The generator keeps machine enums — state/priority/gate/… — byte-identical;
  ARB `@`-prefixed metadata keys are ignored by gen-l10n, the parity gate, and
  the runtime loader, so docs live in `@_readme`.)

ARB files must stay strictly JSON-parseable (no `//` comments): the scaffolder
copies them verbatim into Flutter apps where gen-l10n parses strict JSON.
