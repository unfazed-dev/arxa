#!/usr/bin/env bash
# kill-switch.sh — halt an update rollout by removing the feed manifest(s).
#
# Why this works: the Tauri updater treats non-2xx on ALL configured
# endpoints as "no update available", so deleting latest.json stops every
# NEW update check from offering the bad release. It does NOT reach installs
# that already applied it — the updater structurally never downgrades; the
# only recovery for those is shipping a HIGHER version (see
# docs/ci/release-ops.md#rollback, the rollback runbook).
#
# Usage:
#   desktop/scripts/kill-switch.sh <stable|beta> [options]
#
# Options:
#   --target <target>   updater target family   (default darwin)
#   --arch <arch>       updater arch            (default aarch64)
#   --bucket <name>     R2 feed bucket          (default arxa-releases)
#   --repo <owner/repo> manifest host repo      (default unfazed-dev/arxa-releases)
#   --r2                remove the R2 copy only (requires CLOUDFLARE_API_TOKEN)
#   --github            remove the arxa-releases main-branch copy only (requires gh)
#
# Default (no --r2/--github flag): do both. Feed layout is identical on both
# hosts: desktop/<channel>/<target>/<arch>/latest.json
set -euo pipefail

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

CHANNEL=""
TARGET="darwin"
ARCH="aarch64"
BUCKET="arxa-releases"
REPO="unfazed-dev/arxa-releases"
DO_R2=0
DO_GITHUB=0

while [ $# -gt 0 ]; do
  case "$1" in
    stable|beta) CHANNEL="$1"; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --r2) DO_R2=1; shift ;;
    --github) DO_GITHUB=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[ -n "$CHANNEL" ] || { echo "error: channel (stable|beta) is required" >&2; usage >&2; exit 1; }
# Neither flag given => kill the feed everywhere it is served.
if [ "$DO_R2" -eq 0 ] && [ "$DO_GITHUB" -eq 0 ]; then DO_R2=1; DO_GITHUB=1; fi

PATH_IN_FEED="desktop/${CHANNEL}/${TARGET}/${ARCH}/latest.json"

kill_r2() {
  echo ">> r2: deleting r2://${BUCKET}/${PATH_IN_FEED}"
  if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "error: --r2 requires CLOUDFLARE_API_TOKEN in the environment" >&2
    exit 1
  fi
  local out
  if out="$(npx -y wrangler@latest r2 object delete "${BUCKET}/${PATH_IN_FEED}" --remote 2>&1)"; then
    echo "$out"
  elif grep -qiE "not found|does not exist|no such key|404|NoSuchKey" <<<"$out"; then
    # Missing object is the goal state — treat as success. (S3-style delete
    # of a nonexistent key usually succeeds outright; this covers the cases
    # where wrangler surfaces it as an error instead.)
    echo "   already gone (missing object treated as success)"
  else
    echo "$out" >&2
    exit 1
  fi
}

kill_github() {
  echo ">> github: deleting ${PATH_IN_FEED} from ${REPO}@main"
  local sha out
  if ! out="$(gh api "/repos/${REPO}/contents/${PATH_IN_FEED}?ref=main" --jq .sha 2>&1)"; then
    if grep -qiE "404|not found" <<<"$out"; then
      echo "   already gone (404)"
      return 0
    fi
    echo "$out" >&2
    exit 1
  fi
  sha="$(tr -d '\n"' <<<"$out")"
  [ -n "$sha" ] || { echo "error: could not read file sha for ${PATH_IN_FEED}" >&2; exit 1; }
  gh api -X DELETE "/repos/${REPO}/contents/${PATH_IN_FEED}" \
    -f message="kill-switch: halt ${CHANNEL} rollout" \
    -f sha="$sha" \
    -f branch=main > /dev/null
  echo "   deleted (sha ${sha:0:12})"
}

[ "$DO_R2" -eq 1 ] && kill_r2
[ "$DO_GITHUB" -eq 1 ] && kill_github

echo "feed killed — new update offers halted. For installs already on a bad version, ship a HIGHER version (Tauri updater never downgrades). See docs/ci/release-ops.md#rollback."
