#!/usr/bin/env bash
# Register a self-hosted GitHub Actions runner for a repo under unfazed-dev.
# Standard: every arxa-managed repo runs CI on [self-hosted, macOS, ARM64, arxa].
# See docs/ci/self-hosted-runners.md
set -euo pipefail

REPO="${1:?usage: register-runner.sh <repo-name> [owner]}"
OWNER="${2:-unfazed-dev}"
DIR="$HOME/actions-runner-$REPO"
TARBALL="$HOME/actions-runner-energize/runner.tar.gz"

if [ -d "$DIR" ] && [ -f "$DIR/.runner" ]; then
  echo "Runner already configured at $DIR"; exit 0
fi

if [ ! -f "$TARBALL" ]; then
  echo "Runner tarball not found at $TARBALL — download from https://github.com/actions/runner/releases" >&2
  exit 1
fi

mkdir -p "$DIR"
tar xzf "$TARBALL" -C "$DIR"
cd "$DIR"

TOKEN=$(gh api -X POST "repos/$OWNER/$REPO/actions/runners/registration-token" --jq .token)
./config.sh \
  --url "https://github.com/$OWNER/$REPO" \
  --token "$TOKEN" \
  --name "evans-macbook-$REPO" \
  --labels macOS,ARM64,arxa \
  --unattended \
  --work _work

./svc.sh install
./svc.sh start

sleep 5
gh api "repos/$OWNER/$REPO/actions/runners" --jq '.runners[] | {name, status, labels: [.labels[].name]}'
