#!/usr/bin/env bash
# gates/native_deps/native_deps.sh — the NATIVE DEPENDENCY PACKAGING gate.
#
# Asserts that every plugin dependency is packaged the way the toolchain a
# target needs. Today that means one live migration: Apple platforms moving from
# CocoaPods to Swift Package Manager.
#
# WHY THIS GATE EXISTS. Flutter 3.44 enables SwiftPM by default and warns, per
# build, that plugins without a Package.swift "will become an error in a future
# version of Flutter". That warning scrolls past in build output nobody reads,
# and it is invisible to a generated app until someone happens to look. app_box
# shipped for months with flutter_js in exactly that state. A generated app must
# not inherit a dependency that is scheduled to stop building.
#
# WHAT IT DELIBERATELY DOES NOT DO.
#   * It does not check Android (AGP namespace / compileSdk) or Windows/Linux
#     (CMake). Those toolchains have no SwiftPM concept and no live migration
#     here; inventing checks for problems this repo has not hit is how a gate
#     suite drifts back into vacuous prohibitions. Non-Apple targets are
#     REPORTED as out of scope, never silently passed.
#   * It does not run `flutter pub get`. A gate is a read-only assertion, and
#     pub get rewrites .dart_tool. Flutter already PERSISTS its verdict (see
#     below), so re-running it would add a side effect and no information.
#   * It does not judge whether SwiftPM is a good idea. If a project turns it
#     off, the gate says so plainly and moves on.
#
# HOW DETECTION WORKS — two strategies, because they can disagree.
#   S1 (authoritative) Flutter's own generated manifest,
#      <plat>/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/
#      Package.swift, lists every plugin Flutter actually resolved as a Swift
#      package. This is the toolchain's verdict, written by the toolchain,
#      readable without re-running it.
#   S2 (cross-check) scan .dart_tool/package_config.json for a plugin shipping
#      <plat>/*.podspec with no Package.swift anywhere under <plat>/.
#
#   They are BOTH run and COMPARED. flutter/flutter has an open defect where a
#   plugin with a valid Package.swift still trips the CLI warning when it
#   arrives via a `git:` + `path:` dependency — and this repo consumes its kit
#   as ~39 git deps, so disagreement is a live possibility, not a hypothetical.
#   A disagreement is reported as a WARN with both lists, because a difference
#   we cannot adjudicate is information, not breakage.
#
# SEVERITY — brief non-negotiable #1, "red must mean broken".
#   WARN (exit 0)  plugins lack SwiftPM but CocoaPods integration is present:
#                  the app builds today via fallback. Migration debt, not a
#                  broken build. Nothing goes red for future work.
#   FAIL (exit 1)  plugins lack SwiftPM and there is no CocoaPods integration to
#                  fall back to: the build is broken now.
#   FAIL (exit 1)  a target was named that this gate does not know.
#   N/A  (exit 2)  no Apple target, or no dependency metadata to read.
#
# Usage: native_deps.sh [--targets macos,ios] [app-root]   (0 pass / 1 FAIL / 2 env)
#        native_deps.sh --self-test
#   --targets  explicit target set; absent => read from pipeline state.

GATE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_DIR/../_common/sarif.sh"
# shellcheck source=../_common/state_reader.sh
source "$GATE_DIR/../_common/state_reader.sh"
# state_reader.sh enables `set -e`; gates run WITHOUT it (a failed check is a
# recorded status, not an abort). Re-assert the gate's mode.
set +e
set -uo pipefail

APPLE_TARGETS="ios macos"
KNOWN_TARGETS="ios macos android linux windows web"

fail=0
warned=0
say(){ printf '%s\n' "$*"; }

# --- plugin inventory (S2 input) ---------------------------------------------
# Prints "<name>\t<abs-plugin-dir>" for every dependency that carries native
# sources for <plat> (or the federated `darwin/` directory).
plugins_for(){
  local app="$1" plat="$2" cfg="$1/.dart_tool/package_config.json"
  [ -f "$cfg" ] || return 1
  python3 - "$cfg" "$plat" "$app" <<'PY'
import json, os, sys
cfg_path, plat, app = sys.argv[1], sys.argv[2], sys.argv[3]
base = os.path.dirname(os.path.abspath(cfg_path))
app = os.path.realpath(app)
with open(cfg_path) as fh:
    cfg = json.load(fh)
for pkg in cfg.get("packages", []):
    root = pkg.get("rootUri", "")
    root = root[7:] if root.startswith("file://") else os.path.normpath(os.path.join(base, root))
    # The HOST app is not one of its own dependencies. Its <plat>/ dir holds the
    # Runner and Flutter's generated Swift package, so without this it counts
    # itself as a plugin and the totals go incoherent (observed: "26/25").
    if os.path.realpath(root) == app:
        continue
    for d in (plat, "darwin"):
        pdir = os.path.join(root, d)
        if not os.path.isdir(pdir):
            continue
        has_pod = any(f.endswith(".podspec") for f in os.listdir(pdir))
        has_spm = False
        for dp, dirs, fs in os.walk(pdir):
            # Flutter's generated output is not plugin source; a Package.swift
            # under ephemeral/ says nothing about whether THIS package migrated.
            dirs[:] = [x for x in dirs if x not in ("ephemeral", ".symlinks", "Pods", "build")]
            if "Package.swift" in fs:
                has_spm = True
                break
        if has_pod or has_spm:
            print("\t".join([pkg.get("name", "?"), pdir, "pod" if has_pod else "-", "spm" if has_spm else "-"]))
        break
PY
}

# --- S1: Flutter's own persisted verdict --------------------------------------
spm_resolved(){
  local app="$1" plat="$2"
  local gen="$app/$plat/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
  [ -f "$gen" ] || return 1
  sed -n 's/.*\.package(name: "\([^"]*\)".*/\1/p' "$gen" | sort -u
}

check_target(){
  local app="$1" plat="$2"
  say ""
  say "--- $plat"

  local inv; inv="$(plugins_for "$app" "$plat")"
  if [ -z "$inv" ]; then
    say "  N/A   no dependency metadata for $plat (.dart_tool/package_config.json absent or no native plugins)"
    return 2
  fi

  # S2 — on-disk shape
  local s2_missing; s2_missing="$(printf '%s\n' "$inv" | awk -F'\t' '$3=="pod" && $4!="spm" {print $1}' | sort -u)"
  local declared;   declared="$(printf '%s\n' "$inv" | cut -f1 | sort -u)"
  local n_declared; n_declared="$(printf '%s\n' "$declared" | grep -c . )"

  # S1 — the toolchain's verdict
  local s1 s1_have=1
  s1="$(spm_resolved "$app" "$plat")" || s1_have=0

  if [ "$s1_have" = 1 ]; then
    local s1_missing; s1_missing="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$s1"))"
    # Report the two counts side by side rather than as a fraction: the manifest
    # can legitimately name more packages than the on-disk scan classifies as
    # native (federated implementations, for one), and "26/24" reads as a bug.
    say "  S1 Flutter's manifest names $(printf '%s\n' "$s1" | grep -c .) Swift packages; $n_declared native plugin(s) declared for $plat"
    # Where the two strategies disagree, say so — do not silently prefer one.
    local only1 only2
    only1="$(comm -23 <(printf '%s\n' "$s1_missing" | grep . | sort -u) <(printf '%s\n' "$s2_missing" | grep . | sort -u))"
    only2="$(comm -13 <(printf '%s\n' "$s1_missing" | grep . | sort -u) <(printf '%s\n' "$s2_missing" | grep . | sort -u))"
    if [ -n "$only1$only2" ]; then
      warned=1
      say "  WARN  detection strategies disagree (flutter/flutter has an open defect here for git:+path: deps):"
      [ -n "$only1" ] && say "          Flutter did not resolve, but a Package.swift is on disk: $(echo $only1)"
      [ -n "$only2" ] && say "          Flutter resolved, but no Package.swift found on disk:   $(echo $only2)"
      sarif_result "native_deps" "warning" "$app/$plat" \
        "SwiftPM detection disagreement on $plat: only-S1=[$(echo $only1)] only-S2=[$(echo $only2)]"
    fi
    MISSING="$s1_missing"
  else
    say "  S1 unavailable (no generated Swift package manifest — never built for $plat, or SwiftPM off)"
    say "     falling back to the on-disk scan alone"
    MISSING="$s2_missing"
  fi

  MISSING="$(printf '%s\n' "$MISSING" | grep . | sort -u)"
  if [ -z "$MISSING" ]; then
    say "  ok    all $n_declared native plugins support Swift Package Manager"
    return 0
  fi

  # Broken vs merely-behind turns on whether a CocoaPods fallback still exists.
  local podfile="$app/$plat/Podfile"
  if [ -f "$podfile" ]; then
    warned=1
    say "  WARN  $(printf '%s\n' "$MISSING" | grep -c .) plugin(s) without Swift Package Manager support:"
    printf '%s\n' "$MISSING" | sed 's/^/          - /'
    say "        CocoaPods integration is present, so $plat still builds today."
    say "        Flutter warns this becomes an error in a future release. Remedy:"
    say "        vendor the plugin and add a Package.swift — gates/native_deps/README.md."
    printf '%s\n' "$MISSING" | while read -r m; do
      [ -n "$m" ] && sarif_result "native_deps" "warning" "$podfile" \
        "$m has no Swift Package Manager support for $plat; building via the CocoaPods fallback"
    done
    return 0
  fi

  fail=1
  say "  FAIL  $(printf '%s\n' "$MISSING" | grep -c .) plugin(s) without Swift Package Manager support"
  say "        and NO CocoaPods integration at $podfile to fall back to:"
  printf '%s\n' "$MISSING" | sed 's/^/          - /'
  printf '%s\n' "$MISSING" | while read -r m; do
    [ -n "$m" ] && sarif_result "native_deps" "error" "$app/$plat" \
      "$m has no Swift Package Manager support for $plat and no CocoaPods fallback: $plat cannot build"
  done
  return 1
}

run_gate(){
  local app="${1:-$PWD}" targets_csv="${2:-}"
  local targets
  if [ -n "$targets_csv" ]; then
    targets="$(printf '%s' "$targets_csv" | tr ',' '\n' | grep . )"
  else
    targets="$(state_targets 2>/dev/null | grep . )"
  fi
  if [ -z "$targets" ]; then
    say "native_deps: N/A — no targets declared"
    return 2
  fi

  say "native_deps: over $app"
  say "  targets: $(echo $targets)"

  # An unknown target is a state error, not something to skip quietly.
  local t bad_t=""
  for t in $targets; do
    case " $KNOWN_TARGETS " in *" $t "*) ;; *) bad_t="$bad_t $t" ;; esac
  done
  if [ -n "$bad_t" ]; then
    say "  FAIL  unknown target(s):$bad_t (known: $KNOWN_TARGETS)"
    sarif_result "native_deps" "error" "$app" "unknown target(s):$bad_t"
    return 1
  fi

  # SwiftPM can be switched off per project; if it is, say so rather than
  # reporting a clean bill of health the setting is manufacturing.
  if [ -f "$app/pubspec.yaml" ] && grep -qE '^\s*enable-swift-package-manager:\s*false' "$app/pubspec.yaml"; then
    warned=1
    say "  WARN  SwiftPM is disabled in pubspec.yaml (flutter: config: enable-swift-package-manager: false)."
    say "        Apple targets are being built through CocoaPods by choice; this gate cannot vouch for them."
    sarif_result "native_deps" "warning" "$app/pubspec.yaml" \
      "SwiftPM explicitly disabled; Apple native packaging is unverified by this gate"
  fi

  local apple_seen=0 non_apple=""
  for t in $targets; do
    case " $APPLE_TARGETS " in
      *" $t "*) apple_seen=1; check_target "$app" "$t" ;;
      *)        non_apple="$non_apple $t" ;;
    esac
  done

  # Report, never silently pass, the targets this gate has no assertion for.
  if [ -n "$non_apple" ]; then
    say ""
    say "  note  out of scope for this gate:$non_apple"
    say "        Swift Package Manager is Apple-only; Gradle (android) and CMake"
    say "        (linux/windows) own native packaging there, and neither has a"
    say "        live migration in this repo. Not checked, and not claimed."
  fi

  if [ "$apple_seen" = 0 ]; then
    say ""
    say "native_deps: N/A — no Apple target among:$(echo " $targets")"
    return 2
  fi

  say ""
  if [ "$fail" != 0 ]; then say "native_deps: FAIL"; return 1; fi
  if [ "$warned" != 0 ]; then say "native_deps: pass (with warnings)"; return 0; fi
  say "native_deps: pass"
  return 0
}

# --------------------------------------------------------------------------
# --self-test — happy path AND negative cases (R5).
# --------------------------------------------------------------------------
selftest(){
  local T rc out p=0 f=0
  T="$(mktemp -d)"; trap 'rm -rf "$T"' RETURN
  chk(){ if [ "$1" = "$2" ]; then p=$((p+1)); echo "  ok   $3"; else f=$((f+1)); echo "  FAIL $3 (want exit $2, got $1)"; fi; }
  need(){ case "$1" in *"$2"*) p=$((p+1)); echo "  ok   $3";; *) f=$((f+1)); echo "  FAIL $3 — output lacked '$2'";; esac; }

  # fixture: <root>/app with one plugin dependency
  mk(){ # mk <name> <has_pod> <has_spm>
    local root="$1" name="$2" pod="$3" spm="$4"
    mkdir -p "$root/pkgs/$name/macos"
    [ "$pod" = 1 ] && printf "Pod::Spec.new\n" > "$root/pkgs/$name/macos/$name.podspec"
    if [ "$spm" = 1 ]; then
      mkdir -p "$root/pkgs/$name/macos/$name/Sources/$name"
      printf '// swift-tools-version: 5.9\n' > "$root/pkgs/$name/macos/$name/Package.swift"
    fi
    mkdir -p "$root/app/.dart_tool"
    cat > "$root/app/.dart_tool/package_config.json" <<EOF
{"configVersion":2,"packages":[{"name":"$name","rootUri":"../../pkgs/$name","packageUri":"lib/"}]}
EOF
    mkdir -p "$root/app/macos"
    printf 'name: host\n' > "$root/app/pubspec.yaml"
  }
  gen_manifest(){ # gen_manifest <root> [names...]
    local root="$1"; shift
    local d="$root/app/macos/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage"
    mkdir -p "$d"; : > "$d/Package.swift"
    for n in "$@"; do printf '        .package(name: "%s", path: "../.packages/%s"),\n' "$n" "$n" >> "$d/Package.swift"; done
  }

  echo "native_deps --self-test"

  # HAPPY: plugin has a Package.swift and Flutter resolved it
  local H="$T/happy"; mk "$H" goodplug 1 1; gen_manifest "$H" goodplug
  out="$(run_gate "$H/app" macos 2>&1)"; rc=$?
  chk "$rc" 0 "happy: an SPM-supporting plugin passes"
  need "$out" "all 1 native plugins support" "happy: states the count it checked"

  # NEGATIVE 1: no Package.swift, CocoaPods present => WARN, still exit 0
  fail=0; warned=0
  local N1="$T/warn"; mk "$N1" oldplug 1 0; gen_manifest "$N1"; printf "platform :osx\n" > "$N1/app/macos/Podfile"
  out="$(run_gate "$N1/app" macos 2>&1)"; rc=$?
  chk "$rc" 0 "NEGATIVE: unmigrated plugin WITH a CocoaPods fallback warns, never reds (red must mean broken)"
  need "$out" "WARN" "NEGATIVE: the warning is stated"
  need "$out" "oldplug" "NEGATIVE: the offending plugin is named"

  # NEGATIVE 2: no Package.swift, NO CocoaPods => genuinely unbuildable => FAIL
  fail=0; warned=0
  local N2="$T/broken"; mk "$N2" oldplug 1 0; gen_manifest "$N2"
  out="$(run_gate "$N2/app" macos 2>&1)"; rc=$?
  chk "$rc" 1 "NEGATIVE: unmigrated plugin with NO fallback FAILS (the build really is broken)"
  need "$out" "NO CocoaPods integration" "NEGATIVE: names why it is broken, not just that it is"

  # NEGATIVE 3: strategies disagree — Package.swift on disk, Flutter did not resolve it
  fail=0; warned=0
  local N3="$T/disagree"; mk "$N3" gitplug 1 1; gen_manifest "$N3"; printf "platform :osx\n" > "$N3/app/macos/Podfile"
  out="$(run_gate "$N3/app" macos 2>&1)"; rc=$?
  chk "$rc" 0 "NEGATIVE: a detection disagreement warns rather than guessing"
  need "$out" "disagree" "NEGATIVE: the disagreement is surfaced, not hidden"

  # NEGATIVE 4: an unknown target is a state error
  fail=0; warned=0
  out="$(run_gate "$H/app" solaris 2>&1)"; rc=$?
  chk "$rc" 1 "NEGATIVE: an unknown target fails rather than being skipped"

  # NEGATIVE 5: SwiftPM switched off must be stated, never a silent clean bill
  fail=0; warned=0
  local N5="$T/off"; mk "$N5" goodplug 1 1; gen_manifest "$N5" goodplug
  printf 'name: host\nflutter:\n  config:\n    enable-swift-package-manager: false\n' > "$N5/app/pubspec.yaml"
  out="$(run_gate "$N5/app" macos 2>&1)"; rc=$?
  need "$out" "SwiftPM is disabled" "NEGATIVE: a disabling setting is reported, not silently honoured"

  # non-Apple targets are reported as out of scope, never silently passed
  fail=0; warned=0
  out="$(run_gate "$H/app" android 2>&1)"; rc=$?
  chk "$rc" 2 "android alone is N/A (no SwiftPM concept)"
  need "$out" "out of scope" "non-Apple targets are named as unchecked"

  echo "native_deps --self-test: $p passed, $f failed"
  [ "$f" -eq 0 ]
}

# --------------------------------------------------------------------------
main(){
  local app="" targets=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --self-test) selftest; exit $? ;;
      --targets)   targets="$2"; shift 2 ;;
      --targets=*) targets="${1#--targets=}"; shift ;;
      *)           app="$1"; shift ;;
    esac
  done
  run_gate "${app:-$PWD}" "$targets"
  local rc=$?
  sarif_flush >/dev/null 2>&1 || true
  exit $rc
}
main "$@"
