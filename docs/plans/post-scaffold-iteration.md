# Post-scaffold iteration

## Scope & non-goals

Scope: how a project changes *after* the first `appbox emit scaffold` run — design edits that
require re-scaffolding, the boundary between what regen may overwrite and what a developer owns,
and the pipeline that decides whether a regen diff ships as a Shorebird patch or a store release.

Non-goals: the LLM merge-agent's UI/UX: the studio-agent conflict-resolution surface itself is a
separate build. Hosted-web iteration story: D24/D25 stop the hosted pipeline at scaffold and hand
off a zip/local folder with no Totem-side tooling commitment — whether iteration applies there at
all is an open question below, not solved here. Asset-patch support: gated on Shorebird issue #318
landing (shorebird-release-mechanics.md, Uncertainty flags). The D19/D33 Shorebird-org-pooling
contradiction (see Risks) is a billing decision, not an iteration-architecture one — flagged, not
resolved, here.

## Architecture

**SSOT and regen direction (D12, D8).** `structure.json` is frozen and authoritative; scaffold is
one-way regen from it (D12). The only other per-iteration input is the sidecar
`kit-manifest.json`'s `resolved` section, consumed verbatim by `scaffold()` alongside
`targets`/`derivationPath` (D8) — kit-manifest is the second regen-diff surface, not just
structure.json.

Correction to the source brief: D7 ("Run surface: dedicated scaffold shell") does not state
"frozen structure.json is SSOT" — that claim lives in D8 ("sidecar kit-manifest.json beside frozen
structure.json") and is made explicit in D12 ("structure.json SSOT"). Citations below use D8/D12
for this claim.

**Generation-gap boundary — what's owned vs. generated, as scaffold.dart actually behaves today**
(scaffolder-implementation.md §2-4). Generated, mechanically regenerable: per-screen file tree
shape under `lib/ui/views/<shell>_<short>/`, factor-derivation (`deriveFactors`, scaffold.dart:62-97),
`.shell-structure.json` manifest (`buildManifest`, 413-453), ARB l10n copy-through (`_emitL10n`,
366-406), design-system markdown, shell-chrome stub class signature. Owned, currently 100% outside
generation entirely (not merely marked-and-preserved, but never emitted at all):

- **Navigation.** `scaffold.dart` reads only `data['screens']` (line 586) and never `flows` or
  `shellRoots` (scaffolder-implementation.md gap #1) — zero generated navigation exists today.
- **Kit dependency wiring.** Declared `kits` surface only as inert comments in stub bodies
  (`_stubView` 136-216, `_stubViewmodel` 248-273); no pubspec/import is ever added (gap #2).
- **Platform ceremony files.** Explicitly out of scope per SKILL.md, and for the current htmx
  producer shape `gate_coverage.dart`'s C5 check silently defers this — it isn't even gated (gap #3).

This matters for the iteration model because the industry pattern this pipeline adopted
(post-scaffold-iteration-practices.md, Recommendation) is generation-gap-with-marked-boundary as
the default, escalating to LLM 3-way merge only for boundary-crossing edits. But scaffold.dart's
stub bodies (`_stubView`/`_stubViewmodel`) carry **no markers at all** — they're meant to be edited
directly, in place, with nothing distinguishing "generator wrote this" from "developer wrote this."
That's the un-decided part of the boundary (Workstream 2 / Open questions) — decisions D8/D12
settled *that* there's a boundary, not *where the line is drawn inside a single generated file*.
The decision matrix's own warning applies directly: "boundary must be designed well up front."

**Classifier pipeline (D12, shorebird-release-mechanics.md).** Decision order is fixed by the
research and restated in D12: hard gates → policy gates → `shorebird patch --dry-run` → patch;
any gate trip or dry-run disagreement → release; default on ambiguity or missing metadata →
release. `deploy.app` (D9) surfaces the verdict as a Patch/Release badge.

## Workstreams

1. **Regen-diff baseline capture.** Reuse scaffold.dart's existing `--check`/`_check`
   (scaffold.dart:675-767) as the mechanical "generate && fail-on-diff" primitive — it already does
   diff-not-write. Persist a last-generated baseline per file (Copier `.copier-answers` analog,
   post-scaffold-iteration-practices.md §1) so later workstreams have the triple
   (last-generated, new-generated, current-repo-state) a 3-way merge needs. Use porcelain-style
   diffing, not `git diff --exit-code` (engine-decision-digest.md MEMORY §, untracked-file miss);
   note the ~30% recall ceiling of diff-only drift detection and don't rely on it alone for
   semantic gates. Touchpoints: `scaffold.dart` (556-671, 675-767), `.shell-structure.json`
   (`buildManifest`, 413-453).

2. **Decide and implement the in-file boundary marker.** Pick protected-region markers
   (`// BEGIN/END GENERATED <id>`) vs. a generation-gap class split (base skeleton class +
   never-touched dev subclass) for `_stubView`/`_stubViewmodel` output (scaffold.dart:136-216,
   248-273). Research trade-off (post-scaffold-iteration-practices.md §1, §3): markers are
   familiar and keep file count flat but break if a human damages/deletes them; generation-gap
   subclassing survives that failure mode but doubles file count with product-meaning-free
   "technical vehicle" files. This choice blocks everything downstream — without it, Workstream 1's
   diff has no sub-file granularity to reason about.

3. **Fence the three ungenerated gaps as owned territory, explicitly.** Navigation
   (flows/shellRoots, gap #1), kit dependency/pubspec wiring (gap #2), and platform ceremony files
   (gap #3) must be declared owned-territory in the boundary spec from Workstream 2 — not
   discovered as merge conflicts. Until scaffold.dart is extended to actually emit any of these
   (out of scope here), the classifier and 3-way merge must never attempt automatic reconciliation
   on them; regen diffs touching these paths route straight to human review regardless of what the
   hard/policy gates say.

4. **Kit-manifest regen-diff input.** Diff `kit-manifest.json`'s `resolved` section (D8) against
   the `kits` map last written into `.shell-structure.json` (precedent scaffold.dart:443-451) to
   detect kit-set changes as a first-class trigger, feeding the classifier's
   `changed_kits`/`kit_manifest.has_native_deps`/`.has_assets` soft signals
   (shorebird-release-mechanics.md, Classifier inputs).

5. **Classifier implementation.** Encode the exact tables from shorebird-release-mechanics.md
   verbatim: hard gates (`native_files_changed`, `asset_files_changed`,
   `pubspec_assets_or_fonts_block_changed`, `flutter_version_changed`, `app_version_changed`,
   `new_or_bumped_dependency_with_native_code`, `dart_sdk_constraint_changed`,
   `shorebird_yaml_changed`); policy gates (`touches_payment_or_iap_surface`,
   `introduces_new_user_facing_surface`, `changes_advertised_functionality`,
   `changes_permissions_or_data_collection`, `unlocks_previously_gated_behaviour`); mechanical
   tiebreaker via `shorebird patch --dry-run` exit code and asset/native-diff flags. Automation must
   never pass `--allow-asset-diffs`/`--allow-native-diffs`. Consumes the diff from Workstreams 1-4.

6. **deploy.app surfacing + release-version ledger.** Render the classifier verdict as a
   Patch/Release badge on deploy.app (D9, the per-project screen). Store the release-version the
   current `main` corresponds to at release time (tag or manifest) so the patch lane always passes
   an explicit `--release-version` rather than ambiguous `latest`
   (shorebird-release-mechanics.md Q4, wiring note 7).

7. **LLM-mediated 3-way merge escalation.** For boundary-crossing hand-edits the mechanical diff
   can't resolve cleanly: clean hunks auto-apply, conflicting hunks get git-style markers, the
   studio LLM agent proposes resolutions, a pre-commit hook blocks unresolved markers, human/policy
   approves before commit (post-scaffold-iteration-practices.md §4, Copier/Cruft-plus-AI pattern).

8. **CI wiring.** Two fastlane lanes (`release_shorebird`/`patch_shorebird`); classify first and
   never let a lane guess; `--dry-run` as a PR gate reroutes a wrong "patchable" verdict to the
   release lane; patches land on a `staging` track first, promotion to `stable` is a separate
   human-gated job (shorebird-release-mechanics.md Q4, wiring notes 1-4).

## Risks

- **Misclassification is asymmetric.** A wrong patch ships to every installed device and costs a
  rollback plus quota; a wrong release only costs a review cycle. Every gate above defaults to
  release on ambiguity — this must not be relaxed for velocity.
- **The boundary is undesigned today.** scaffold.dart's stub bodies have zero markers separating
  generated from hand-owned content; regen after any hand-edit currently has no mechanical way to
  know what changed. Workstream 2 blocks Workstreams 1, 3, 4, 5.
- **Diff-based drift detection recall is ~30%** (web-research-drift.md via engine-decision-digest.md)
  — pair the mechanical diff with execution/coverage assertions, don't gate solely on it.
- **Asset-patching is roadmap, not shipped** (Shorebird issue #318) — if it lands, the
  `asset_files_changed` hard gate becomes CLI-version-dependent; pin and re-verify before relying
  on it.
- **Apple policy tension is unresolved by primary sources** (ARG 2.5.2 vs. DPLA 3.3.2(B)) — the
  policy gates rely on an industry interpretation, not adjudicated Apple guidance.
- **D19/D33 conflict on Shorebird org ownership.** D19: "Shorebird orgs per-customer or
  customer-owned — never pooled on Totem Labs' plan." D33: "Totem owns the Shorebird org … pooled
  on Totem org," with quota bundled/overage passed through. This directly affects the classifier's
  `patch_install_quota_remaining` and `live_release_versions[]` soft signals — whose quota is being
  checked depends on which decision stands. Needs resolution before Workstream 5 ships, not
  re-litigated here.

## Open questions

- **Marker format (Workstream 2).** No decision recorded choosing protected-region markers vs.
  generation-gap subclassing for scaffold.dart's stub output.
- **Hosted-web applicability.** D24/D25 hand off a zip/local folder with no Totem-side tooling
  commitment past scaffold — does any of this iteration/classifier pipeline run for hosted-web
  users at all, or is it local-CLI/daemon-only? None of the four sources addresses this.
- **Multi-platform patch-number consistency.** `shorebird patch -p android,ios` patches both
  platforms in one invocation; whether patch numbers stay identical across platforms is undocumented
  (shorebird-release-mechanics.md Q4, note 6) — affects whether the release-version ledger
  (Workstream 6) can key on a single number or needs one per platform.
