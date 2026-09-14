# Linux support — arxa desktop distribution

User-facing summary of how arxa studio ships on Linux. The deep document —
container harness, build routes, the AppImage patchelf war, the real-machine
Omarchy/Hyprland findings — lives in the **arxa-studio** repo
(`arxa-studio/docs/linux-support.md`, plan `docs/plans/linux-omarchy-port.md` in
either repo); this page carries what a user or a release engineer touching THIS
repo needs, plus the deferred Omarchy VM leg's runbook.

Status: **stable and beta release lanes are wired** (`desktop-release.yml`:
macOS lane fail-closed on stable, Linux lane builds AppImage + `.deb` on
ubuntu-22.04); the first real runner pass of both is still external (see the
studio repo's open-work inventory, AXS-019/AXS-053).

## Installing (users)

One command — reads the same `desktop/<channel>/linux/<arch>/latest.json` the
in-app updater reads, verifies the published `.sha256`, installs per user
(`~/.local/share/arxa-studio/`, `~/.local/bin/arxa-studio`, `.desktop` entry +
icon; no root except the host packages libfuse2/zenity/gnome-keyring/libsecret/
bubblewrap):

```sh
curl -fsSL https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main/install.sh | sh
ARXA_CHANNEL=beta sh install.sh          # the beta feed
sh install.sh --uninstall                # ~/.arxa data is kept
```

macOS twin: `install-macos.sh` (same repo root) — manifest fetch, `.sha256` +
minisign `.sig` verification, per-user `~/Applications` install, sticky channel
(`~/.config/arxa-studio/channel`), `--uninstall`. Local/dev overrides:
`ARXA_STUDIO_APPIMAGE=<file|url>` (Linux), `ARXA_STUDIO_BUNDLE=<file|url>`
(macOS), `ARXA_MANIFEST_BASE` for offline/`file://` testing. Focused test:
`sh desktop/scripts/test-install-macos.sh` (scratch `$HOME`, zero network).

## What ships, and where the engine lives

| Format | Lane | Updater artifact |
|---|---|---|
| AppImage (x86_64, ubuntu-22.04 → glibc ≥ 2.35 floor) | `release-linux` job | yes (`.sig` + `.sha256`) |
| `.deb` (Debian/Ubuntu) | `release-linux` job | no (D10 — AppImage-only updater) |
| PKGBUILD (Arch/Omarchy, `desktop/packaging/`) | local build | no |

The engine never runs from the AppImage mount and never lands in `usr/bin`:
all three formats put it at `/usr/libexec/arxa-studio/arxa-studio` (linuxdeploy
patchelfs every ELF under `usr/bin`+`usr/lib` and the bun-compiled engine does
not survive that). `desktop/src-tauri/tauri.linux.conf.json` carries the
`files` map; `desktop-gate.yml`'s `linux-engine-unit` job and the release
AppDir assertion pin the layout. Engine supervision on Linux is the systemd
**user** unit `arxa-engine.service` (renderer: `desktop/src-tauri/src/engine_unit.rs`,
tested only inside the Arch container — the module is `#[cfg(target_os = "linux")]`).

Wayland/HiDPI: the shell forces `GDK_BACKEND=wayland,x11` when
`WAYLAND_DISPLAY` is present (the AppRun hook's unconditional `x11` export was
the 2x-draws bug), drops its title bar on tiling compositors, and supports
`ARXA_GDK_BACKEND` / `ARXA_DECORATIONS` overrides. Full story:
arxa-studio `docs/linux-support.md` "Known issues".

## Container lanes (what a local machine can run)

`arxa-studio`'s `scripts/linux/run-container.sh` drives everything (toolchain,
suites, boot smoke, keyring round-trip, sidecar builds, `cargo test`
engine_unit, packaging + layout assertions) in Arch (dev loop) and Ubuntu
22.04 (release artifacts) containers. Docker-gated: when the daemon is down
the lanes degrade — the prepared commands are:

```sh
cd ../arxa-studio
scripts/linux/run-container.sh                      # Arch lane (arm64)
DISTRO=ubuntu scripts/linux/run-container.sh        # Ubuntu lane: AppImage + deb
```

## Deferred: the Omarchy VM user path (Task 16 runbook)

Not yet run: a disposable Omarchy VM + disposable user/home exercising the
REAL installer path. RAM floor (8 GB VM on a busy 16 GB host) deferred it;
`lima`/`colima` are present but were not started (scratch-state discipline —
the operator's docker daemon stays as they left it). The leg to run:

1. Boot a disposable Omarchy VM (lima or the operator's preferred hypervisor),
   create a disposable user with a fresh `$HOME` — never the operator's.
2. From that user:
   `ARXA_CHANNEL=beta curl -fsSL https://raw.githubusercontent.com/unfazed-dev/arxa-releases/main/install.sh | sh`
   (NOT `ARXA_STUDIO_APPIMAGE` — the point is the published feed path).
3. Assertions:
   - Wayland chosen (`xwayland=False` — the GDK fix holding on the real
     compositor; `ARXA_GDK_BACKEND=x11` still forces the old path);
   - the engine runs from the **stable copied path**
     `$XDG_DATA_HOME/arxa-studio/libexec/arxa-studio`, never `/tmp/.mount_*`;
   - `systemctl --user restart arxa-engine.service` restarts the engine;
   - tray icon, session composer usable, logs land under `$ARXA_HOME`;
   - the previously observed `cannot prepare session while it is live` resume
     flow: a session left live-but-agentless resumes via the composer (or
     reports why) — fix any reproduction test-first in the owning repo;
   - `sh install.sh --uninstall` removes the app, keeps `~/.arxa`.

A cheaper partial (also still deferred with the daemon): the Ubuntu container
leg of `run-container.sh` covers install/`--appimage-version`/uninstall as
root — it does NOT cover Hyprland/Wayland/tray, which is why the VM leg exists.

## Windows: DEFERRED (D23)

Native Windows distribution stays deferred under D23 — research
(`docs/research/windows-packaging.md`) is evidence for a revisit, never
authorization to build. Revisit trigger: sustained demand (a support/waitlist
volume threshold) or a Scale customer requiring local/offline builds the
hosted web version cannot serve. Recorded in the studio repo's
`docs/plans/open-work-inventory-2026-09-12.md`.
