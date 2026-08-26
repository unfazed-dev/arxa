# Artifacts produced — schema, registry, flows

## What you produce (and what you do not)

Two artefacts, written by the chain:

1. **Validated answers** — elicited with `arxa intake`, conforming to
   `intake.schema.json`. The FIRST closed question of every intake is
   **`product.kind`** — *is this product a **site** (web/landing: htmx +
   islands, the designer's eject is runnable site code) or an **app**
   (Flutter targets, scaffold → build → stores)?* It is not the same axis
   as a target: a Flutter app may target `web` while being kind `app`, and
   a site is kind `site` regardless of hosting. Record it as
   `product.kind: site|app` — for repo-mode projects `arxa project sync
   <app-dir>` pushes it (with targets/locales) into the `arxa.json`
   marker. Downstream, kind is consumed where it matters: the commission
   header carries it, and kind `site` means the artifact's eject IS the
   build (no Flutter scaffold; see the designer's productionize doc for the
   site path and its dual-tree law). The scaffolder and deployer branch on
   TARGETS, not kind. Beyond the
   core fields, intake elicits four optional groups:
   - **`direction`** — `{adjectives: [...], avoids: [...]}`: the design
     direction (what it should feel like, what it must not).
   - **`contentAnchors`** — real content examples the app must show.
   - **`locales`** — locale codes (e.g. `[en, pl]`), rendered after Targets in
     the brief; drives the i18n capability and the ARB catalog set
     (`l10n/app_en.arb` template + one ARB per locale) the designer authors.
   - **per-surface `states`** — UI state names (loading, empty, error, …),
     carried into the registry seed and the brief's surface table.
   - optional per-surface flags: **`requiresAuth`** (the screen sits behind
     sign-in) and **`tab`** (bottom-tab membership — the scaffolder's shell
     group), booleans carried into the registry.
   The **audience** is elicited in JTBD form: *"When [situation], I want
   [motivation], so I can [outcome]."*

   **`personas`** — the user types, asked as its own question (Slice B2):

   > **Who are the main types of people who will use this?**
   > Name each one as you'd describe them to a new hire — as many as you
   > actually have, not a round number. For each, if you know it: what are
   > they trying to get done, what makes it painful today, where and when
   > do they use it, how comfortable are they with tools like this, and do
   > any of them have access needs?

   **Variable N.** Take as many as the client names and stop — one is a
   valid answer, so is seven. Do not pad to three, do not prompt for "a
   couple more", and do NOT synthesise one from `audience`: that field is a
   single JTBD sentence with no name, role or goals, so anything built from
   it is invention wearing the authority of elicitation (§22). If the
   client names none, omit the key — `personas.json` is then `[]`, which
   truthfully says nobody was named. Per-persona sub-answers left blank stay
   absent; a blank `accessibility` means unstated, never "none".
2. **The seeded registry + flows** — `arxa intake emit` seeds them in the
   project's `intake/` dir (with `--project`), or at the design root
   (`designs/<app>/models/screens_model/registry.json`, or whatever
   structure.json's `"registry"` field names) without it — the same path
   `arxa gate intake` reads. `docs/intake/registry.json` is only a fallback
   when no design root exists. One entry per surface the client named, with
   keys `{id, label, shell, comp, route, surface}`. `comp` and `route` are
   derived by convention (`shop.cart` → `ShopCart`, `/cart`), never authored —
   an answers `route` key overrides per surface. `surface` is **always
   `null`** — intake names what the client asked for; design binds a surface
   to each. `comp` is derived by convention, never authored.
   A hand-written brief whose surface table carries `priority` / `release`
   columns (e.g. from `arxa-story-mapper`) passes them through as optional
   sibling metadata — additive, never woven into the canon keys.

## Flows — derive + confirm

Flows wire the declared surfaces into linear user journeys; they are how the
designer later produces views + flows + prototype deterministically. Shape
(flows.json v2):

```json
[{ "id": "flow-browse-buy", "name": "Browse and buy", "provenance": "founder",
   "edges": [{ "from": "portalo.home", "to": "portalo.category",
               "trigger": "Category tile", "action": "push" }] }]
```

- **Edges** are `{from, to, trigger, action?}`; endpoints must be declared
  intake surfaces (flows wire what the client named, nothing else).
- **`action` is typed**: `push | replace | back | modal | system` (default
  `push`). `system` marks non-gesture edges (auth-success, deep-link) — the
  scaffolder maps them to route guards, never to buttons.
- **Linear chains only**: a screen has at most one outgoing and one incoming
  edge per flow. No branches, no loops, no self-edges — the validator rejects
  them by name. A screen may appear in MANY flows (multi-flow membership).
- **Derive + confirm**: when answers carry no `flows` group, the engine
  derives one draft flow per shell (surfaces chained in declaration order,
  trigger `continue`) marked `provenance: inferred` — a draft to confirm, never
  a fact. Confirming flips provenance:
  ```sh
  arxa intake flows confirm --project <name> --flow <id> --as founder|client
  ```

The unified `docs/intake/brief.md` is emitted by the chain's tail —
`arxa emit story-map --answers <answers.json>` (when `--answers` is omitted
it auto-discovers `pipeline/state/run.intake.json`, then
`pipeline/state/default.intake.json`). Every field whose provenance is
`inferred` is **visibly marked** in the brief — a reader who skims must not
miss it.

You do **not** produce: views, viewmodels, routes, copy, layouts, component
libraries, or anything that is design. That is the next phase. If you find
yourself writing a screen, stop — you are in the wrong skill.
