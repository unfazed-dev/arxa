<!--
  PR title: [arxa-<skill-name>] <subject> — first tag = primary stage.
  The full tag map lives in docs/ci/decisions.md (SSOT) and below.
-->

## Pipeline stage / agent

`[arxa-…]` tag(s): <!-- e.g. [arxa-deployer] or [arxa-builder][arxa-tester] -->
Skill name(s): <!-- the full skill name(s) behind the tags -->

## What changes

<!-- One paragraph: what and why. Link the governing doc/row (AXS-…). -->

## Evidence

<!-- What proves it: check areas run green, test names, screenshots, receipts.
     `scripts/check.sh` is the local root — name the areas you ran. -->

## Stage-tag map (footer — keep in sync with docs/ci/decisions.md)

| Tag | Stage | | Tag | Stage |
|-----|-------|-|-----|-------|
| `[arxa-orchestrator]` | Ø front door | | `[arxa-tester]` | 5 tests |
| `[arxa-intake]` | 1 intake | | `[arxa-reviewer]` | 6 QC |
| `[arxa-story-mapper]` | 0 story map | | `[arxa-deployer]` | 9 stores/OTA |
| `[arxa-moodboarder]` | 0 references | | `[arxa-lens]` | 8 visual |
| `[arxa-designer]` | 2 design | | `[arxa-lint]` | 7 knowledge |
| `[arxa-scaffolder]` | 3 emit | | `[arxa-cicd]` | 10 frame |
| `[arxa-builder]` | 4 surfaces | | | |
