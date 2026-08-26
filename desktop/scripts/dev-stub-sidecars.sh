#!/usr/bin/env bash
# Create placeholder sidecar binaries so `cargo check` / `tauri dev` work
# without the real arxa binaries. Real binaries are injected by the release
# pipeline (see desktop/README.md). Stubs are gitignored.
set -euo pipefail

dir="$(cd "$(dirname "$0")/../src-tauri/binaries" && pwd)"
triple="$(rustc --version --verbose | sed -n 's/^host: //p')"

for name in arxa arxa-studio; do
  stub="$dir/$name-$triple"
  if [ ! -f "$stub" ]; then
    printf '#!/bin/sh\necho "%s sidecar stub — replaced by release pipeline" >&2\nexit 1\n' "$name" > "$stub"
    chmod +x "$stub"
    echo "created $stub"
  else
    echo "exists  $stub"
  fi
done
