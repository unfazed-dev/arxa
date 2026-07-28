# probe-runner

Capture + drive + introspect macOS desktop apps (wry/Tauri/Dioxus), iOS sims,
Android emulators, host browsers (Chrome default, Safari fallback), and
Flutter targets — all from one Claude Code skill installed at
`.claude/skills/probe-runner/`.

Think "Playwright-shaped, screencapture-powered" for everything that isn't a
plain web page in Chrome.

## Install

The skill itself is just files in this directory — Claude Code auto-discovers
it on next session start. Tooling you need on the host:

```bash
# core, required for most verbs
xcode-select --install           # provides screencapture, osascript, xcrun simctl, sample, vmmap, leaks, log, ioreg
brew install cliclick            # synthetic mouse + key events

# optional / per-block
brew install ffmpeg              # web_record alt path, lossless host capture
brew install fswatch             # filesystem change watch
brew install --cask google-chrome   # default web target
brew install idb-companion       # iOS UI ops (idb)
pipx install fb-idb              # the `idb` CLI
brew install android-platform-tools  # adb, emulator
pip3 install Pillow pyobjc-framework-Vision pyobjc-framework-Cocoa \
              websocket-client selenium
```

System Python 3 on macOS already ships `pyobjc-framework-Quartz` and
`pyobjc-framework-ApplicationServices`. Verify:

```bash
python3 -c "import Quartz, ApplicationServices; print('ok')"
```

`safaridriver --enable` one-time, if you want the Safari fallback for the web
block.

## Using from hermes-agent

The skill format is agentskills.io-compatible, so hermes-agent can load it
without modification. Hermes scans `~/.hermes/skills/` plus any directories
listed under `skills.external_dirs` in `~/.hermes/config.yaml`. Pick one:

```bash
# Option A — symlink (one canonical copy, recommended)
ln -s "$PWD/.claude/skills/probe-runner" ~/.hermes/skills/probe-runner

# Option B — external_dirs entry (project-scoped, no symlink)
mkdir -p ~/.hermes
cat >> ~/.hermes/config.yaml <<'EOF'
skills:
  external_dirs:
    - ${HOME}/Developer/business/brainiac/.claude/skills
EOF
```

After either step, every `commands/pr-*.md` surfaces as a `/pr-*` slash
command in hermes. Claude-Code-only frontmatter keys (`allowed-tools`,
`user-invocable`, `argument-hint`) are ignored by hermes without error.

## TCC permissions

The first time a script runs, macOS prompts for one or more of these. Grant
in System Settings → Privacy & Security:

| Permission | Needed for |
|---|---|
| Screen Recording | `screencapture` window/region/video, ocr |
| Accessibility | `cliclick`, AX tree reads, AX click |
| Input Monitoring | some Quartz scroll/event synthesis |
| Automation → Safari / target app | osascript driving menus, focus |

## Quick start

```bash
# discover a running app's window
python3 .claude/skills/probe-runner/scripts/find_window.py perf_domain_heavy_100

# screenshot it
python3 .claude/skills/probe-runner/scripts/shot.py perf_domain_heavy_100

# record a 5s video
python3 .claude/skills/probe-runner/scripts/record.py perf_domain_heavy_100 --seconds 5 --clicks

# send a key chord
python3 .claude/skills/probe-runner/scripts/key_chord.py perf_domain_heavy_100 "cmd+shift+s"

# open a real web page in Chrome, eval JS
python3 .claude/skills/probe-runner/scripts/web_launch.py
python3 .claude/skills/probe-runner/scripts/web_open.py https://example.com
python3 .claude/skills/probe-runner/scripts/web_eval.py "document.title"

# iOS sim
python3 .claude/skills/probe-runner/scripts/ios_boot.py "iPhone 15"
python3 .claude/skills/probe-runner/scripts/ios_shot.py

# Android emu
python3 .claude/skills/probe-runner/scripts/adb_list.py
python3 .claude/skills/probe-runner/scripts/adb_shot.py

# Flutter (with a `flutter run` already in another shell)
flutter run -d "iPhone 15" 2>&1 | tee /tmp/flutter.log &
python3 .claude/skills/probe-runner/scripts/flutter_attach.py --tail /tmp/flutter.log
python3 .claude/skills/probe-runner/scripts/flutter_tree.py --kind widget
```

## Slash commands

96 commands under `commands/pr-*.md` — every script has a slash form, e.g.:

```
/pr-shot perf_domain_heavy_100
/pr-record perf_domain_heavy_100 --seconds 10
/pr-web-eval "document.title"
/pr-ios-shot
/pr-adb-tap 500 1000
/pr-flutter-reload
```

## Output

Everything lands under `${PROBE_RUNNER_OUTDIR:-/tmp/probe-runner}/`. Override
in shell:

```bash
export PROBE_RUNNER_OUTDIR=$HOME/probe-runner-out
```

See `templates/env_skill.example` for the full env-var list.

## Dioxus probe template

`templates/dioxus_debug_probe.rs` is a drop-in Rust module that exposes
typed `probe_dom`, `tail_console`, `dom_snapshot`, `install` helpers on top
of `dioxus::document::eval`. Wiring instructions in
`templates/dioxus_cargo_feature.md`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `no window found for owner '<name>'` | App not running, minimized, or wrong owner name. Try `find_window.py <name> --all`. |
| `missing dependency 'cliclick'` | `brew install cliclick` |
| `Chrome not running with CDP` | `python3 scripts/web_launch.py` first |
| `safaridriver init failed` | `safaridriver --enable` (one-time) |
| `Secure Input is active` | Close password fields / 1Password etc; macOS blocks synthetic input system-wide while a password field is focused |
| `idb` missing | `brew install idb-companion && pipx install fb-idb` |
| `adb` missing | `brew install android-platform-tools` |
| `no Flutter VM service URL` | App built in release; rerun with `flutter run --debug` |
| Window screenshot is letterboxed / wrong size | wry on Retina returns logical bounds but `screencapture` uses physical pixels. `find_window.py` reports logical; `shot.py` handles the doubling automatically |

## Limits (documented up front)

- macOS only.
- Multi-touch gestures are best-effort (Cmd+scroll fallback).
- Secure Input blocks synthetic typing; the skill refuses with a clear error.
- App-Store-distributed apps with hardened-runtime sandbox may reject AX events; fall back to cliclick coord-based.
- `nettrace.py` needs sudo (tcpdump).
- `ax_observe.py` is polling, not callback-based (true `AXObserver` needs a CFRunLoop).
- iOS / Android UI hierarchy dumps see Flutter widgets as one opaque view unless the app enables `SemanticsBinding` (see `flutter_semantics.py`).
- Safari fallback for the web block lacks network intercept and device emulation; the scripts report `unsupported`.
- Real-device (non-simulator/emulator) iOS/Android works but is undocumented this round — codesigning and USB debug trust prompts are operator responsibility.
