# Feature/Module Selection UX in Scaffolding Tools — Survey

Research question: how do mature scaffolding/generator ecosystems let users choose optional
capabilities (auth, database, payments, analytics, ...) at generation time, and how do they
resolve the tension between "inferred from the project" and "explicitly picked by the user"?

## Comparison table

| Tool | When selection happens | Persisted / re-runnable? | How defaults are derived | Conflict/dependency handling | Late addition after initial generation |
|---|---|---|---|---|---|
| **create-t3-app** | Up-front interactive wizard (name → language → package checklist → git → install), or one-shot CLI flags in `--CI` mode | Not re-runnable as a generator; it's a one-time scaffold. Selections only live in the generated code | Wizard has no config file; `-y` bundles all packages as the default bundle. Non-interactive mode defaults every flag to "off" unless passed, except `--dbProvider` which defaults to sqlite | An "installer" system encodes cross-package rules (e.g. tRPC pulls in specific server plumbing when combined with a chosen ORM) so template files/deps are chosen based on the *combination*, not each flag independently | No — it's a single-shot generator; adding a package later means manual integration, not a CLI command |
| **Nx generators** | `nx g <plugin>:<generator>` any time, either interactively (JSON-Schema-driven prompts) or via flags/CI | Yes — generators are designed to be re-run; an `init` schematic sets a default collection "only if one does not currently exist" (idempotent guard) | Schema defines defaults per option; self-documenting via JSON Schema | Composition — generators can call other generators (`runTasksInSerial`/`runTasksInParallel`), so a top-level "add capability" generator can safely invoke and sequence dependent generators | Yes — this is the primary model. `nx g` is explicitly an additive, anytime command, not just a bootstrap step |
| **Angular `ng add` (used by Nx too)** | Anytime, post-init: `ng add <package>` | Yes, add schematics are meant to be re-run for new capabilities; CLI now checks the target actually contains an `ng-add` schematic (not just a schematics field) before running, with a built-in fallback for some packages (e.g. Tailwind) | Package's own `ng-add` schematic decides defaults/prompts | Peer-dependency version detection at add time; real-world conflicts arise when the schematic requires a newer CLI/Angular core than the project has — resolved by aligning versions or (last resort) `--legacy-peer-deps` | Yes — this *is* the late-addition mechanism for the whole ecosystem |
| **NestJS schematics** | `nest generate <schematic> <name>` per-artifact (module/service/resource), or third-party collections via `-c` for whole feature modules (auth, TypeORM, GraphQL) | Yes, run repeatedly per new module; not idempotent-checked by the core CLI itself (re-running can duplicate registrations) — collections vary | Flags like `--type=rest --crud` set generation shape; no global feature-selection config file | Each schematic manipulates the AST (e.g. registers the new module in the root module's imports) rather than solving cross-schematic conflicts explicitly | Yes — additive by design; this is the normal way to add a capability (e.g. auth-module) well after initial `nest new` |
| **Rails (`rails new`)** | Up-front only, via CLI flags (`--database=`, `--skip-*`, `--minimal`) | No — one-shot; flags only affect the initial generation | `-d/--database` defaults to sqlite3; `--minimal` is a bundle of `--skip-*` flags with a sane "smallest app" default | Known real gap: `--skip-active-record` silently drops the `--database` gem from the Gemfile — an unresolved ordering/precedence bug, illustrating the risk of flag combinations that aren't validated against each other | No native re-run; after initial generation, Rails relies on `rails generate <generator>` for per-artifact scaffolding (models/controllers), not for retroactively removing/adding whole subsystems like Action Mailer |
| **very_good_cli / Mason bricks** | Per-template subcommand at generation time (`very_good create flutter_app`) plus brick-level `vars` prompts when a brick runs | Bricks are explicitly re-runnable (`mason make <brick>`) — that's their core use case, used both for initial scaffolds and later feature-module generation | `brick.yaml` declares `type`, `default`, and `prompt` per var; unspecified vars fall back to their declared default | Conditionals are literal Mustache logic in the template: `{{#var}}...{{/var}}` in file content **and** in file paths (e.g. `{{#createChangelog}}CHANGELOG.md{{/createChangelog}}` — the file simply doesn't exist if the var is false). Composition of bricks (bloc/UI/tests as separate optional layers) is done by giving each brick several boolean vars (`has_ui`, `has_tests`, `include_bloc`) rather than a central conflict resolver | Yes — running a "feature brick" against an existing project to add a new feature module is a first-class, expected workflow |
| **create-vue (Vite)** | Up-front interactive wizard by default; or `-- --typescript --router --pinia ...` flags to skip prompts entirely | No — one-shot scaffold, not a re-runnable generator | No flags = full interactive wizard; passing *any* recognized feature flag switches the whole run to non-interactive and only flags you pass are enabled (others default off) | Minimal cross-feature logic — each flag independently toggles inclusion of a well-known official package (Router, Pinia, Vitest, ESLint...); the CLI doesn't need to arbitrate conflicts because these are additive, orthogonal libraries | No — like create-t3-app, later additions (e.g. Pinia) are manual `npm install` + wiring, not a CLI command |
| **Spring Initializr** | Up-front, via web UI or REST metadata-driven form (also usable non-interactively via `curl`/IDE plugin) | Effectively a config-server model: the same metadata endpoint can be queried repeatedly to regenerate a project with a different dependency set — not "re-run against an existing project," but the selection UI itself is reusable/inspectable | Metadata endpoint publishes a `default` attribute per capability (e.g. default packaging, default Java version); dependency list defaults to none selected | Dependencies are modeled as a `HIERARCHICAL_MULTI_SELECT` capability grouped by category; compatibility is expressed by scoping which dependencies are even offered for a given Boot version (`DependencyMetadata` is versioned) rather than validating arbitrary combinations after the fact | No — it's a from-scratch generator; there is no "add dependency to existing generated project" command (that's left to editing the `pom.xml`/`build.gradle` by hand) |
| **shadcn/ui `add`** | Anytime, post-init: `npx shadcn add <component...>` | Yes — explicitly designed for repeated, incremental use; default behavior is **non-destructive** (`-o/--overwrite` defaults to `false`, so re-running doesn't clobber customizations); newer CLI adds explicit `--reinstall`/`--no-reinstall` at init | No prompts for "which defaults" — the registry resolves the dependency graph and installs everything a requested component needs (e.g. requesting `login-01` pulls in `button`, `label`, `input`, `card` automatically) | Dependency resolution is transitive and automatic via the registry graph; conflicts are avoided by copying code into the user's own tree (components become user-owned files) rather than versioned packages, sidestepping most semver conflict classes entirely | Yes — this is the *primary* mode of operation. There is barely a concept of "initial generation" separate from `add`; `init` just sets up config, `add` is how all features/components arrive, indefinitely |
| **RedwoodJS `setup` commands** | Anytime, post-init: `yarn rw setup auth <provider>`, `yarn rw setup auth dbAuth`, etc. | Yes — designed to run after `redwood create`; some sub-features are themselves re-runnable/additive (e.g. WebAuthn can be added to an existing dbAuth install later) | Provider-specific: a setup command "installs all the packages, writes all the files, and makes all the code modifications you need" with sensible provider defaults; prompts appear for optional sub-features (e.g. "enable WebAuthn?") | The setup command patches known integration points in existing files (`App.tsx`'s `RedwoodApolloProvider`, `Routes.tsx`'s `Router`, `graphql.ts`'s handler) by wiring a `useAuth` prop into them, rather than requiring the user to hand-edit; post-install console output calls out manual follow-ups (e.g. DB columns for dbAuth) that the codemod can't safely do | Yes — this is the whole model: auth, deployment targets, and other subsystems are added post-generation via dedicated `setup` verbs, not chosen in the initial wizard |

## Two families that emerge

1. **Everything-up-front wizard, one-shot** (create-t3-app, Rails `rails new`, create-vue, Spring
   Initializr): all selection happens before/at generation time; there is no CLI-native path to
   retroactively add a subsystem — that becomes manual code editing. Non-interactive/CI modes
   exist as flag equivalents of the same wizard, not a separate mechanism.
2. **Additive, anytime commands** (Nx generators, `ng add`, NestJS schematics, Mason/very_good_cli
   bricks, shadcn/ui `add`, RedwoodJS `setup`): initial generation is deliberately minimal, and
   capability selection is deferred to a *second* command class that is explicitly safe (or made
   safe) to run repeatedly, often with idempotency or non-destructive guards (shadcn's
   `overwrite: false` default; Nx's "set default collection only if unset"; Mason's
   var-defaulted re-runs).

Rails is the interesting hybrid: it has both an up-front wizard (`rails new` flags) *and* a
separate additive mechanism (`rails generate <generator>`), but the additive side only covers
per-artifact scaffolding (models, controllers), not whole optional subsystems like Action Mailer —
those remain up-front-only, which is exactly the documented `--skip-active-record` +
`--database` conflict bug: a flag combination nobody validated because both are "up-front only."

## Patterns that transfer

- **Separate "what capability" from "how to configure it."** Every additive-model tool (Nx, `ng
  add`, shadcn, Redwood `setup`) treats capability selection as a distinct command from initial
  scaffolding, which is what makes late addition possible at all — a wizard-only design
  (t3, create-vue, Spring Initializr) structurally cannot support it later without a rewrite.
- **Make re-runs safe by default, not by convention.** shadcn's `add` defaults to
  `overwrite: false`; Nx's `init` schematic checks "no default collection set" before writing.
  Idempotency guards should be an explicit, tested precondition on the write path, not an
  assumption about user behavior.
- **Resolve dependencies transitively, not by asking the user to know them.** shadcn resolves a
  requested component's full dependency tree automatically; t3's installer picks template files
  based on the *combination* of selections, not per-flag. Users should pick capabilities, not
  enumerate their prerequisites.
- **Conditional file existence, not just conditional file content.** Mason's brick-path
  conditionals (`{{#var}}file.md{{/var}}`) show that "skip this capability" should be able to
  omit whole files/directories, not just leave placeholder content behind.
- **Non-interactive mode should be flag-parity with the wizard, not a separate code path.**
  create-t3-app's `--CI` mode and create-vue's `-- --flag` mode reuse the exact same option set
  as the interactive prompts; this avoids silent drift between "what you can pick" and "what you
  can script."
- **Validate flag combinations, don't just validate flags individually.** Rails'
  `--skip-active-record` + `--database=mysql` bug is a direct consequence of validating each flag
  in isolation; a capability-selection system needs a combination-level check, especially where
  one selection can silently disable the effect of another.
- **Patch known integration points explicitly, and say what you couldn't patch.** RedwoodJS's
  `setup auth` codemods specific named files/props and prints follow-up instructions for anything
  it can't safely automate (e.g. DB schema changes) — an explicit boundary between "safe to
  automate" and "tell the human," rather than silently doing a partial job.
- **Metadata-driven option surfaces decouple the UI from the option list.** Spring Initializr's
  metadata endpoint (with per-capability defaults and hierarchical grouping) means the same
  option set drives the web UI, IDE plugins, and scripted `curl` calls — one source of truth for
  "what's selectable" instead of duplicating it per client.

## Sources

- [Create T3 App — Installation docs](https://create.t3.gg/en/installation)
- [create-t3-app GitHub PR #575 — CLI synchronous rewrite](https://github.com/t3-oss/create-t3-app/pull/575)
- [DeepWiki — T3 Stack overview](https://deepwiki.com/t3-oss/create-t3-app/1.1-t3-stack)
- [Nx — Plugin Registry](https://nx.dev/docs/plugin-registry)
- [Nx — @nx/plugin Generators reference](https://nx.dev/docs/reference/plugin/generators)
- [Creating an ng-add schematic for an Nx plugin — DEV Community](https://dev.to/devinshoemaker/creating-an-ng-add-schematic-for-an-nx-plugin-309a)
- [Angular — Generating code using schematics](https://angular.dev/tools/cli/schematics)
- [angular-cli PR #24152 — ng-add package discovery fix](https://github.com/angular/angular-cli/pull/24152)
- [angular-cli PR #31065 — ng-add schematic verification + fallback](https://github.com/angular/angular-cli/pull/31065)
- [NestJS Schematics — nestjs-app-schematics (auth/TypeORM/GraphQL modules)](https://github.com/jamesblackjr/nestjs-app-schematics)
- [nestjsplus/dyn-schematics — dynamic module generator](https://github.com/nestjsplus/dyn-schematics)
- [Jaco Pretorius — rails new: Complete Guide to All Options (2025)](https://jacopretorius.net/2025/05/all-rails-new-options.html)
- [rails/rails Issue #25191 — --skip-active-record ignores --database](https://github.com/rails/rails/issues/25191)
- [Very Good CLI — Overview docs](https://cli.vgv.dev/docs/overview)
- [VeryGoodOpenSource/very_good_cli — GitHub](https://github.com/VeryGoodOpenSource/very_good_cli)
- [BrickHub Docs — Brick Syntax (vars, mustache conditionals, conditional file paths)](https://docs.brickhub.dev/brick-syntax/)
- [Codemagic Blog — Using Mason and bricks in your Flutter app](https://blog.codemagic.io/mason-cli/)
- [Verygood Ventures Blog — Code generation with Mason](https://verygood.ventures/blog/code-generation-with-mason/)
- [vuejs/create-vue — GitHub](https://github.com/vuejs/create-vue)
- [create-vue — npm package page](https://www.npmjs.com/package/create-vue)
- [Spring Initializr — Reference Guide](https://docs.spring.io/initializr/docs/current/reference/html/)
- [Spring Initializr — io.spring.initializr.metadata package docs](https://docs.spring.io/initializr/docs/current/api/io/spring/initializr/metadata/package-summary.html)
- [spring-io/initializr — GitHub](https://github.com/spring-io/initializr)
- [shadcn/ui — CLI docs](https://ui.shadcn.com/docs/cli)
- [shadcn/ui — Monorepo docs](https://ui.shadcn.com/docs/monorepo)
- [RedwoodJS Docs — Authentication](https://docs.redwoodjs.com/docs/authentication/)
- [RedwoodJS Docs — Self-hosted Authentication (dbAuth)](https://docs.redwoodjs.com/docs/auth/dbauth/)
- [RedwoodJS Docs — Custom Authentication](https://docs.redwoodjs.com/docs/auth/custom/)
