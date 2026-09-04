# Self-hosted CI runners — the standard

**Rule: every CI job for arxa, arxa studio, and any arxa-managed repo runs on a self-hosted runner.** Never `macos-14`/`ubuntu-latest` GitHub-hosted runners.

## Canonical `runs-on`

```yaml
runs-on: [self-hosted, macOS, ARM64, arxa]
```

## Why per-repo runners

`unfazed-dev` is a **personal GitHub account** — org-level (shared) runners are not available. Each repo gets its own runner *instance* on the same machine, following the existing pattern:

| Repo | Runner dir | Runner name |
|---|---|---|
| `unfazed-dev/arxa` | `~/actions-runner-arxa` | `evans-macbook-arxa` |
| `unfazed-dev/arxa-studio` | `~/actions-runner-arxa-studio` | `evans-macbook-arxa-studio` |
| `unfazed-dev/energize` | `~/actions-runner-energize` | `evans-macbook-energize` |

All are LaunchAgent-managed (`./svc.sh install && ./svc.sh start`) so they survive reboots.

## Register a runner for a new repo

```bash
scripts/register-runner.sh <repo-name>   # e.g. scripts/register-runner.sh arxa-releases
```

Manual equivalent: extract `~/actions-runner-energize/runner.tar.gz` into `~/actions-runner-<repo>`, then `./config.sh --url https://github.com/unfazed-dev/<repo> --token $(gh api -X POST repos/unfazed-dev/<repo>/actions/runners/registration-token --jq .token) --name evans-macbook-<repo> --labels macOS,ARM64,arxa --unattended`, then `./svc.sh install && ./svc.sh start`.

## Apps built with arxa (scaffolded CI)

When arxa scaffolds CI workflows for a user's app, the generated workflow MUST:

1. Default `runs-on: [self-hosted, macOS, ARM64, arxa]` — same label contract.
2. Make it **overridable** (workflow input / repo variable). End users run their **own** runners with these labels — generated apps must never depend on Arxa Digital Solutions' machines or infrastructure (see root CLAUDE.md ownership boundary).

## Secrets gotchas (learned the hard way)

- `TAURI_SIGNING_PRIVATE_KEY` lives in the protected **`release` GitHub
  environment** on the arxa repo (D10 — not a bare repo secret readable by
  every run); the workflow's `environment: release` is what gates exposure.
  The key (`~/.arxa/updater/arxa-updater.key`, never committed) has an
  **empty password**, and that local file is now the **offline backup only**
  — not a release build input. `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` must be
  set to the empty string — any other value fails the build with
  `incorrect updater private key password`.
- One updater keypair is shared by arxa and arxa-studio; secrets are set per-repo on both.
- Moving a release tag: tag-triggered runs use the workflow file **at the tag's commit** — re-point the tag after workflow edits.
