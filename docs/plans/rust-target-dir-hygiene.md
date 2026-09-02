# Rust target-dir hygiene — keep the internal disk lean

Decision record: `cairn/docs/adr/0044-cargo-build-dir-and-cache-hygiene.md`.
This plan is the operator runbook: exact commands, what was measured, how to
verify, how to roll back.

## Problem

Rust `target/` dirs (≈27.6 GB across cairn / arxa / pixel_77 + stale
worktrees) and `~/.gradle` (4.6 GB) + `~/.pub-cache` (3.3 GB) sit on the
internal drive. Cargo never prunes intermediates, and every fresh worktree
rebuilds the whole dependency tree into a new `target/`. The internal disk
fills, memory pressure follows, the machine gets slow.

## Facts checked before starting (2026-09-02)

| Check | Result |
|---|---|
| `~/.cargo`, `~/.rustup` | already symlinks → `/Volumes/developer_ssd/dev/.{cargo,rustup}` |
| `~/.gradle`, `~/.pub-cache` | real dirs in `$HOME` — 4.6 GB / 3.3 GB |
| Filesystems | `developer_ssd` APFS, `business_ssd` APFS |
| `build.build-dir` on 1.95.0 | works; cdylib still uplifted to `target/` |
| `profile.dev.package."*".debug=false` via config | merges, no warning |
| `native_toolchain_rust` | passes its own `--target-dir`; unaffected by `build-dir` |
| `cargo-ndk` | reads `target/<triple>/`; unaffected by `build-dir` |
| `cargo-sweep` | not installed |
| `launchctl getenv CARGO_HOME` | empty — GUI/launchd do not see `.zshrc` |

## Steps

### 1. Cargo config (`/Volumes/developer_ssd/dev/.cargo/config.toml`)

```toml
[build]
build-dir = "/Volumes/developer_ssd/dev/cargo-build/{workspace-path-hash}"

[profile.dev.package."*"]
debug = false
```

`mkdir -p /Volumes/developer_ssd/dev/cargo-build`.

Verify: `cargo +1.95.0 check -p cairn-domain` in cairn → a new
`cargo-build/<hash>/debug/` appears on the external SSD and
`cairn/target/debug/` holds only final artifacts.

### 2. Move Gradle and pub caches next to cargo/rustup

```sh
mv ~/.gradle    /Volumes/developer_ssd/dev/.gradle    && ln -s /Volumes/developer_ssd/dev/.gradle    ~/.gradle
mv ~/.pub-cache /Volumes/developer_ssd/dev/.pub-cache && ln -s /Volumes/developer_ssd/dev/.pub-cache ~/.pub-cache
cd cairn/sdk/cairn_flutter && flutter pub get      # package_config.json holds absolute paths
```

Symlink, not env var, so Xcode / Android Studio / Gradle daemons agree with
the shell.

### 3. Weekly prune via launchd agent

`cargo-sweep` 0.8.0 was installed, tested and **rejected**: it finds the
directory to sweep through `cargo metadata` → `target_directory`, which under
`build-dir` is the repo `target/` (final artifacts only). Pointed at the
build-dir it errors (`manifest path .../Cargo.toml does not exist`);
`--recursive` finds no projects. Uninstalled.

Replacement: `~/Library/Scripts/cargo-build-sweep.sh` — for each
`cargo-build/xx/<hash>/` workspace dir, `rm -rf` the **whole dir** if no file
in it was modified in the last 14 days; never delete single files. Logs
dirs removed + freed/remaining MiB, exits non-zero if the volume is missing
or unreadable. (First version was a per-file `find -mtime +7 -delete`;
rejected after advisor review — Cargo re-checks missing rlibs but not
build-script `out/` files, and the first run already hit 3 MiB of
fresh-but-old-mtime files.)

Trigger: **not launchd.** A launchd agent was built, loaded and kicked with a
planted stale file: exit 0, log showed `find: … Operation not permitted`,
probe untouched — TCC denies removable-volume access to launchd-spawned
processes and the only fix is Full Disk Access for `/bin/sh` (rejected).
Instead `~/.zshrc` runs the script in the background at most once per
7 days (stamp `~/Library/Logs/cargo-build-sweep.stamp`, log
`~/Library/Logs/cargo-build-sweep.log`). Terminal already holds the grant —
the manual run reported real numbers.

### 4. Delete the old `target/` dirs (after step 1 is verified)

Every `target/` under the three repos and the stale `.claude/worktrees`
copies. All regenerable. Expected reclaim ≈ 27.6 GB internal/business_ssd.

### 5. Rebuild once

`cargo +1.95.0 test --workspace --no-run` in cairn to repopulate; confirm
`sdk/cairn_kotlin` (`cargo ndk`) and `sdk/cairn_flutter` (`flutter build`)
still find their artifacts.

## Rollback

- Remove the `[build]` / `[profile.dev.package."*"]` blocks from
  `config.toml`; next build goes back to `target/`.
- Remove the ADR-0044 block from `~/.zshrc`; delete
  `~/Library/Scripts/cargo-build-sweep.sh` and the stamp/log in
  `~/Library/Logs`.
- `~/.gradle` / `~/.pub-cache`: `rm` the symlink, `mv` the dir back.

## Status (2026-09-02)

- [x] 1 config — verified: `cargo check` wrote to
  `cargo-build/4a/0ae572b504fb7a/debug`, cdylib uplifted to
  `cairn/target/debug/libcairn_ffi_wasm.dylib`, no config warnings.
- [x] 2 `~/.gradle` (4.6 GB) and `~/.pub-cache` (3.3 GB) moved to
  `/Volumes/developer_ssd/dev/` and symlinked; 0 open handles at move time,
  no daemons killed; `flutter pub get` in `sdk/cairn_flutter` OK
  (package_config keeps `/Users/…/.pub-cache` paths, valid via the symlink).
- [x] 3 sweep: cargo-sweep rejected, launchd rejected (see above); zshrc
  hook installed.
- [x] 4 deleted 4 target dirs, **24,399 MB**: `cairn/target` 1007,
  `pixel_77/ax-poc-old/target` 15,210, `pixel_77/ax-poc-old/channels/target`
  109, `pixel_77/business/app/rust/target` 8,072. developer_ssd free
  118 → 141 Gi. (Earlier estimate was ~27.6 GB; only these four carried
  Cargo's `CACHEDIR.TAG` marker at deletion time.)
- [x] 5 rebuild + SDK builds verified:
  - `cargo +1.95.0 test --workspace --no-run` in cairn: 1m 59s, clean.
    Intermediates `cargo-build/4a/0ae572b504fb7a` = 3.8 GB (external);
    `cairn/target` = 204 MB, only final binaries, 0 rlibs, no `deps/`.
  - `cargo ndk -t arm64-v8a -o /tmp/ndk-probe build` in `sdk/cairn_kotlin`
    (its own workspace → `cargo-build/81/36031cbd1ed696`, 898 MB): the
    harness's expected path
    `sdk/cairn_kotlin/target/aarch64-linux-android/debug/libcairn_kotlin.so`
    exists (40.9 MB) and `-o` received the copy. cargo-ndk unaffected.
  - Sweep hook: fires on first shell start, not on the second (stamp).
    Whole-dir version tested with a planted idle workspace dir (removed)
    next to the live ones (kept, 36694 files before/after, Android
    `libsqlite3-sys/out/bindgen.rs` intact).
  - **The one per-file run (16:28, 3 MiB) did break the cairn desktop
    build**: `cargo build` failed with "couldn't read
    …/libsqlite3-sys-4aa77a1ad947ba1b/out/bindgen.rs". Cargo does not
    self-heal missing build-script outputs. Repaired with
    `cargo clean -p libsqlite3-sys && cargo build`. This is the concrete
    reason the sweep is whole-dir only.
  - `native_toolchain_rust` / Flutter build not exercised end-to-end this
    session; it passes an explicit `--target-dir`, which `build-dir` does not
    override, so no change in behaviour is expected.
