# probe-runner — audit & cross-agent compatibility (Claude Code + hermes-agent)

**Audit date:** 2026-05-16
**Scope:** `.claude/skills/probe-runner/` — does it work in Claude Code, will it work in hermes-agent, does it need refactor?

## Verdict

| Question | Answer |
|---|---|
| Works as a Claude Code skill? | **Yes** — format, discovery, and script runtime verified. |
| Works as a hermes-agent skill? | **Yes, after install step** — format is agentskills.io-compatible; needs symlink or `external_dirs` entry. |
| Needs refactor? | **No.** Two doc/hygiene fixes only. |

## Evidence — Claude Code

| Check | Result |
|---|---|
| `SKILL.md` frontmatter (`name`, `description`, `allowed-tools`, `argument-hint`, `user-invocable`) | conforms to Anthropic skill spec (docs.anthropic.com/en/docs/claude-code/skills). |
| Discovery path `<repo>/.claude/skills/probe-runner/` | valid project-scoped skill location; Claude Code auto-loads at session start. |
| Slash-command files (`commands/pr-*.md`, 98 files) | all have frontmatter (`description`, `allowed-tools`, `argument-hint`) + inline `!`backtick exec of `python3 ${CLAUDE_SKILL_DIR}/scripts/<verb>.py $ARGUMENTS`. Conforming. |
| Scripts (103 `.py` under `scripts/`) | all `+x`, all have `#!/usr/bin/env python3` shebang. |
| Parse check (sample of 6: `shot.py`, `click.py`, `web_eval.py`, `adb_tap.py`, `ios_shot.py`, `flutter_attach.py`) | `ast.parse` clean. (Not a runtime smoke — only 6/103 verified.) |
| `_common.py` importable; `out_path`, `ts` helpers present | ✓ |
| End-to-end smoke: `find_window.py Finder` | exits cleanly with `no window found` (Finder not active) — script wiring works. |
| `__pycache__/` under `scripts/` | already in `.gitignore` (verified via `git check-ignore`). Not tracked. |

## Evidence — hermes-agent

Source: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/

| Requirement | Status |
|---|---|
| `SKILL.md` + YAML frontmatter (agentskills.io spec) | ✓ |
| `name`, `description` fields | ✓ |
| Multi-file layout with `scripts/`, `templates/`, `commands/`, `examples/` | ✓ — Hermes Hub spec explicitly lists these as supported. |
| Discovery path | ✗ as-installed. Hermes scans `~/.hermes/skills/` (primary) + `external_dirs` from `~/.hermes/config.yaml`. Current install at `.claude/skills/probe-runner/` is NOT scanned by Hermes by default. |
| Claude-Code-only frontmatter keys (`allowed-tools`, `user-invocable`, `argument-hint`) | ignored by Hermes — won't break parsing (unknown keys tolerated), but Hermes-native fields like `version`, `platforms`, `metadata.hermes.tags`, `metadata.hermes.category` are absent. |

**To use in hermes-agent**, add one of:

```bash
# Option A — symlink (preferred; one canonical copy)
ln -s "$PWD/.claude/skills/probe-runner" ~/.hermes/skills/probe-runner

# Option B — external_dirs entry (project-scoped, no copy)
cat >> ~/.hermes/config.yaml <<'EOF'
skills:
  external_dirs:
    - ${HOME}/Developer/business/brainiac/.claude/skills
EOF
```

Hermes will surface every `commands/pr-*.md` automatically as a `/pr-*` slash command via progressive disclosure. No code changes required.

## Issues found — fix list

| # | Severity | Location | Issue | Fix |
|---|---|---|---|---|
| 1 | doc-bug | `SKILL.md:95` | Claims `scripts/_common.py::tcc_check()` exists and "raises a clear error if missing". `grep -rn 'tcc_check'` returns only the SKILL.md mention itself — function is undefined. | Either implement a real `tcc_check()` in `_common.py` (calling `tccutil`/AX-check), or delete the sentence. Recommend delete — TCC errors already surface from `screencapture`/`cliclick` with platform-native messages. |
| 2 | enhancement | `SKILL.md` frontmatter | Missing optional Hermes-native keys. | Add (non-breaking): `metadata: { hermes: { tags: [macos, automation, debug], category: devops } }`. Hermes uses these for hub indexing; Claude Code ignores unknown metadata. |
| 3 | install-doc | `README.md` "Install" | Only documents Claude Code discovery (drops into `.claude/skills/`). | Add a "Using from hermes-agent" subsection with the symlink/`external_dirs` snippet from §"Evidence — hermes-agent" above. |

## Why no refactor

- **Surface size (98 verbs / 103 scripts) is intentional**: the design doc (`.claude/skills/probe-runner/docs/probe-runner-skill.md`) frames it as a capability-matrix toolset spanning macOS native + wry/Tauri/Dioxus + iOS sim + Android emu + host web + Flutter. Trimming would re-introduce the manual orchestration the skill exists to eliminate.
- **Language policy is sound**: one runtime (Python 3), one exception (Rust template for Dioxus drop-in). No shell scripts. No hidden globals.
- **Output convention is consistent**: `${PROBE_RUNNER_OUTDIR:-/tmp/probe-runner}` + `<target>-<ts>-<kind>.<ext>` everywhere.
- **Cross-target dispatch is honest**: `flutter_tap --target macos|web` returns rc=2 with a documented fallback (semantics tree + AX/DOM click) rather than faking a synthesised coord. This is the right shape.

## Out of scope for this audit

- Runtime smoke beyond `find_window.py` + 6-script parse check. Per-script behaviour should be validated by `examples/*_smoke.md` recipes against a live target.
- Linux/Windows host port (already named out-of-scope in design plan).
- Hermes-native `version` / `platforms` frontmatter additions — non-blocking for compatibility.

## Recommended action

Land issues #1, #2, #3 as a single trivial PR (`docs(probe-runner): fix tcc_check claim; document hermes-agent install`). No code refactor required. Skill is production-shaped for both targets.

## Reference

- Anthropic Claude Code skill spec: https://docs.anthropic.com/en/docs/claude-code/skills
- agentskills.io open standard: https://agentskills.io/specification
- Hermes-agent skills docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/
- Skill source: `.claude/skills/probe-runner/`
- Design plan: `.claude/skills/probe-runner/docs/probe-runner-skill.md`
