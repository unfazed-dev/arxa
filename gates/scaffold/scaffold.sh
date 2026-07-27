#!/usr/bin/env bash
# shell_structure_gate.sh — the SHELL STRUCTURE gate (SCAFFOLD_GATE_D, Phase 1 of
# docs/plans/shell-structure-transformation.md): validates the self-contained
# shell pattern on a host app's lib/ui/views/ tree.
#
# Contract file: lib/ui/views/.shell-structure.json
#   { "selfContained": ["train_shell"], "notes": "..." }
#
# Shells NOT listed in selfContained are skipped (incremental migration — the
# gate is a flexible template: assert a value, never a view count, never
# generate). Absent manifest or empty list → WARN + exit 0 (no shell has opted
# in yet; the gate never rubber-stamps and never false-fails).
#
# Checks (cheapest first, all must pass):
#   S0 manifest  — .shell-structure.json parses; every named shell dir exists
#   SN snackbars — no snackbars/ subdir anywhere under lib/ui
#                  (P2NotificationService is the transient-feedback port)
#   S1 shape     — per self-contained shell: ≥ 1 *_view.dart, a matching
#                  *_viewmodel.dart, design-system.md present (NEVER a count
#                  of 5 views — just ≥ 1)
#   S2 locality  — per self-contained shell (the value assertion): a global
#                  overlay import (lib/ui/bottom_sheets|dialogs|snackbars) is a
#                  violation ONLY when the imported overlay no longer exists at
#                  that global path — i.e. it was relocated into a shell, so the
#                  import is a stale/ownership leak. Shared overlays that STAY
#                  global (share, report_block, membership_upsell, …) are exempt:
#                  importing them is fine, per the plan's decision table (locality
#                  fires only once a shell OWNS the subdir ⇔ the overlay left
#                  global). Plus: no import from another shell's view tree.
#                  (shared services/models imports are always fine.)
#   S3 barrels   — bottom_sheets/<n>/ carries <n>_sheet.dart; dialogs/<n>/
#                  carries <n>_dialog.dart (catches a half-move)
#   S4 doc teeth — design-system.md has a ## Palette / ## Tokens heading with
#                  ≥ 1 kit color reference (kc*/KitColors); bare presence is a
#                  rubber stamp
#
# Phase 3 wiring (pipeline.sh — NOT applied here; exact branding-gate pattern):
#   SHELL_STRUCTURE_GATE_DEFAULT="tools/shell_structure_gate.sh"
#   [ "$CONSUMER" = 0 ] && SHELL_STRUCTURE_GATE_DEFAULT="pass"   # app-only
#   SCAFFOLD_GATE_D="${PIPELINE_SHELL_STRUCTURE_GATE:-$SHELL_STRUCTURE_GATE_DEFAULT}"
#
# Usage:
#   shell_structure_gate.sh [app-root]     validate (exit 0 pass / 1 FAIL / 2 env)
#   shell_structure_gate.sh --self-test    hermetic fixture run
#
# bash 3.2-safe (no assoc arrays / mapfile). Deliberately NO `set -e` — a failed
# check is reported, not an abort (matches freeze_design.sh / branding_gate.sh).
set -uo pipefail

GATE_COMMON="$(cd "$(dirname "$0")/../_common" && pwd)"
# shellcheck source=../_common/sarif.sh
source "$GATE_COMMON/sarif.sh"

SELF="$(cd -P "$(dirname "$0")" && pwd)/$(basename "$0")"
FIXDIR="$(cd -P "$(dirname "$0")" && pwd)/fixtures/shell_structure"

# ---- self-test: good/bad fixtures + hermetic tmp cases ----
if [ "${1:-}" = "--self-test" ]; then
  P=0; Fc=0
  chk(){ [ "$1" = "$2" ] && P=$((P+1)) || { Fc=$((Fc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
  need(){ case "$1" in *"$2"*) P=$((P+1));; *) Fc=$((Fc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }
  not(){ case "$1" in *"$2"*) Fc=$((Fc+1)); echo "  FAIL: output should NOT mention [$2] — $3";; *) P=$((P+1));; esac; }

  [ -d "$FIXDIR" ] || { echo "FAIL: fixtures missing at $FIXDIR" >&2; exit 2; }

  # clean fixture: migrated shell, own overlays, shared-service import, plus a
  # benign import of a SHARED overlay that still lives globally (share_sheet) and
  # a cross-shell OVERLAY import (shop_shell's coupon sheet — overlay subdirs are
  # exempt from the cross-shell ban) → PASS, both overlay imports exempted.
  o=$(bash "$SELF" "$FIXDIR/clean" 2>&1); chk "$?" 0 "clean fixture passes"
  need "$o" "exempt" "clean fixture's shared global-overlay import is exempted (still global)"
  need "$o" "cross-shell overlay" "clean fixture's cross-shell overlay import is exempted (S2)"
  need "$o" "correctly placed" "clean fixture's facades/repos placed right + loose service legal (S5)"
  need "$o" "owns its widgets" "clean fixture's shell owns widgets/ (S6)"
  need "$o" "correctly placed or absent (SN)" "clean fixture reports SN placement verdict"
  need "$o" "no layout-swapping" "clean fixture's getValueForScreenType widget is allowed (S7 twin)"
  # dirty fixture: RELOCATED-overlay leak (rest_timer no longer at the global path,
  # moved in-shell) + cross-shell VIEW import + missing barrel + snackbars dir +
  # missing design-system.md → FAIL, naming each violation; its cross-shell
  # OVERLAY import (coupon) is exempt and must NOT be named.
  o=$(bash "$SELF" "$FIXDIR/dirty" 2>&1); chk "$?" 1 "dirty fixture fails"
  need "$o" "ui/bottom_sheets" "relocated-overlay leak is named"
  need "$o" "shop_shell" "cross-shell import is named"
  need "$o" "set_log_sheet.dart" "missing barrel file is named"
  # NOT `need "$o" "snackbars"` — the inverted SN's OK line also contains the word
  # "snackbars", so that assertion passed vacuously the moment the ban became a
  # placement rule. Assert the FAIL wording instead.
  need "$o" "snackbars/ in an unsanctioned location" "misplaced snackbars dir is named (SN)"
  not "$o" "lib/ui/snackbars —" "the app-level snackbars/ dir must NOT be flagged (SN is placement, not a ban)"
  need "$o" "design-system.md" "missing design-system.md is named"
  not "$o" "coupon" "dirty fixture's cross-shell overlay import is exempt (not named)"
  need "$o" "misplaced facade" "dirty fixture's misplaced facade (in-shell, not services/facades/) is named (S5)"
  need "$o" "ScreenTypeLayout in a shared widget" "dirty fixture's layout-swapping widget is named (S7)"
  not "$o" "no widgets/*.dart" "dirty fixture HAS widgets/ so S6 must not fire (S7 is the isolated failure)"

  T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
  # absent manifest → WARN + exit 0 (gate is a no-op until first migration)
  mkdir -p "$T/a/lib/ui/views"; printf 'name: appa\n' > "$T/a/pubspec.yaml"
  o=$(bash "$SELF" "$T/a" 2>&1); chk "$?" 0 "absent manifest is WARN not FAIL"
  need "$o" "WARN" "absent manifest warns"
  # S6: shell with view+viewmodel+design-system.md but NO widgets/ and NO
  # *_chrome.dart → FAIL. This is the sample-app train_shell shape that passed every gate
  # while tablet/desktop imported their row out of the mobile view file.
  mkdir -p "$T/w/lib/ui/views/train_shell"; printf 'name: appw\n' > "$T/w/pubspec.yaml"
  printf '{"selfContained": ["train_shell"], "notes": ""}' > "$T/w/lib/ui/views/.shell-structure.json"
  printf 'class TrainShellView {}\n' > "$T/w/lib/ui/views/train_shell/train_shell_view.dart"
  printf 'class TrainShellViewModel {}\n' > "$T/w/lib/ui/views/train_shell/train_shell_viewmodel.dart"
  printf '## Palette\nkcPrimaryColor\n' > "$T/w/lib/ui/views/train_shell/design-system.md"
  o=$(bash "$SELF" "$T/w" 2>&1); chk "$?" 1 "shell with no widgets/ and no chrome fails (S6)"
  need "$o" "no widgets/*.dart and no *_chrome.dart" "S6 names the missing widget home"
  # S6 twin: the SAME tree plus a *_chrome.dart → passes. Proves S6 checks the
  # widget home, not something incidental to the tree.
  cp -R "$T/w" "$T/w2"
  printf 'class TrainChrome {}\n' > "$T/w2/lib/ui/views/train_shell/train_chrome.dart"
  o=$(bash "$SELF" "$T/w2" 2>&1); chk "$?" 0 "same tree with a *_chrome.dart passes (S6 twin)"
  need "$o" "train_chrome.dart" "S6 names the chrome file that satisfied it"
  # S6 placement twins — the discriminating pair. S6 was originally written for
  # a bare <shell>/widgets/, which review_checklist.sh 1o/D REJECTS: the two
  # gates were mutually unsatisfiable and nothing here noticed, because every
  # assertion passed under both spellings. These two fixtures differ ONLY in
  # where the widget file sits.
  cp -R "$T/w" "$T/w3"
  mkdir -p "$T/w3/lib/ui/views/train_shell/widgets"
  printf 'class TrainRow {}\n' > "$T/w3/lib/ui/views/train_shell/widgets/train_row.dart"
  o=$(bash "$SELF" "$T/w3" 2>&1); chk "$?" 1 "a BARE <shell>/widgets/ does NOT satisfy S6 (1o/D forbids it)"
  need "$o" "rejected by review check 1o/D" "S6 points at the reviewer rule that owns placement"
  cp -R "$T/w" "$T/w4"
  mkdir -p "$T/w4/lib/ui/views/train_shell/shared/widgets"
  printf 'class TrainRow {}\n' > "$T/w4/lib/ui/views/train_shell/shared/widgets/train_row.dart"
  o=$(bash "$SELF" "$T/w4" 2>&1); chk "$?" 0 "<shell>/shared/widgets/ satisfies S6"
  cp -R "$T/w" "$T/w5"
  mkdir -p "$T/w5/lib/ui/views/train_shell/training_library/widgets"
  printf 'class TrainRow {}\n' > "$T/w5/lib/ui/views/train_shell/training_library/widgets/train_row.dart"
  o=$(bash "$SELF" "$T/w5" 2>&1); chk "$?" 0 "<shell>/<view>/widgets/ satisfies S6"

  # S8 WARN path: a registered Kit* service but NO .dart_tool/package_config.json
  # (deps never fetched). Must WARN and exit 0 — and must NOT print the OK line,
  # or "deps absent" would read as "peers verified".
  mkdir -p "$T/p8/lib/ui/views/train_shell" "$T/p8/lib/app"; printf 'name: appp8\n' > "$T/p8/pubspec.yaml"
  printf '{"selfContained": ["train_shell"], "notes": ""}' > "$T/p8/lib/ui/views/.shell-structure.json"
  printf 'class TrainShellView {}\n' > "$T/p8/lib/ui/views/train_shell/train_shell_view.dart"
  printf 'class TrainShellViewModel {}\n' > "$T/p8/lib/ui/views/train_shell/train_shell_viewmodel.dart"
  printf 'class TrainChrome {}\n' > "$T/p8/lib/ui/views/train_shell/train_chrome.dart"
  printf '## Palette\nkcPrimaryColor\n' > "$T/p8/lib/ui/views/train_shell/design-system.md"
  printf '@StackedApp(dependencies: [LazySingleton(classType: KitThemeService)])\nclass App {}\n' > "$T/p8/lib/app/app.dart"
  o=$(bash "$SELF" "$T/p8" 2>&1); chk "$?" 0 "missing package_config is WARN not FAIL (S8)"
  need "$o" "package_config" "S8 names the missing package_config"
  not "$o" "peer services registered for every" "S8 must NOT claim peers verified when it could not look"

  # S9: a form-factor VARIANT importing another variant fails, even though the
  # shell has a chrome file (so S6 passes) — proves S6 does not subsume S9.
  cp -R "$T/p8" "$T/p9"; mkdir -p "$T/p9/.dart_tool"
  printf '{"configVersion":2,"packages":[]}' > "$T/p9/.dart_tool/package_config.json"
  printf 'class LibViewMobile {}\nclass TrainingLibraryRow {}\n' > "$T/p9/lib/ui/views/train_shell/lib_view.mobile.dart"
  printf "import 'lib_view.mobile.dart';\nclass LibViewTablet { var x = TrainingLibraryRow(); }\n" > "$T/p9/lib/ui/views/train_shell/lib_view.tablet.dart"
  o=$(bash "$SELF" "$T/p9" 2>&1); chk "$?" 1 "variant cherry-picking a component from a variant fails (S9)"
  need "$o" "form-factor variant imports another variant" "S9 names the squatting import"
  need "$o" "TrainingLibraryRow" "S9 names WHICH symbol was cherry-picked"
  not "$o" "no widgets/*.dart" "S6 passes here (chrome present) so S9 is the isolated failure"
  # S9 delegation twin — the discriminator. Same import, but the importer uses
  # ONLY the imported variant's own View class: "wide tiers centre the phone
  # column" (showcase_notes_create_account_view.tablet.dart). That is one
  # layout being reused, which is exactly what S9's rule text permits; an
  # earlier revision flagged it and would have forced a pointless refactor of
  # the kit's own exemplar.
  cp -R "$T/p9" "$T/p9b"
  printf "import 'lib_view.mobile.dart';\nclass LibViewTablet { var x = LibViewMobile(); }\n" > "$T/p9b/lib/ui/views/train_shell/lib_view.tablet.dart"
  o=$(bash "$SELF" "$T/p9b" 2>&1); chk "$?" 0 "wholesale delegation to a variant's View class passes (S9 twin)"
  not "$o" "form-factor variant imports another variant" "S9 must not flag delegation"
  # S9 twin: the DISPATCHER importing its variants is required, must pass.
  rm "$T/p9/lib/ui/views/train_shell/lib_view.tablet.dart"
  printf "import 'lib_view.mobile.dart';\nclass Dispatch {}\n" > "$T/p9/lib/ui/views/train_shell/lib_view.dart"
  o=$(bash "$SELF" "$T/p9" 2>&1); chk "$?" 0 "dispatcher importing its variant passes (S9 twin)"

  # S8 comment blindness: a kit doc-comment demonstrating usage
  # (`/// final x = locator<HapticService>();`) must NOT be read as a real peer
  # edge. This regressed once already — the first S8 build flagged showcase_app,
  # the kit's own exemplar, off exactly such a comment.
  mkdir -p "$T/c8/lib/ui/views/train_shell" "$T/c8/lib/app" "$T/c8/.dart_tool" "$T/c8/fakekit/lib"
  printf 'name: appc8\n' > "$T/c8/pubspec.yaml"
  printf '{"selfContained": ["train_shell"], "notes": ""}' > "$T/c8/lib/ui/views/.shell-structure.json"
  printf 'class TrainShellView {}\n'      > "$T/c8/lib/ui/views/train_shell/train_shell_view.dart"
  printf 'class TrainShellViewModel {}\n' > "$T/c8/lib/ui/views/train_shell/train_shell_viewmodel.dart"
  printf 'class TrainChrome {}\n'         > "$T/c8/lib/ui/views/train_shell/train_chrome.dart"
  printf '## Palette\nkcPrimaryColor\n'   > "$T/c8/lib/ui/views/train_shell/design-system.md"
  printf '@StackedApp(dependencies: [LazySingleton(classType: KitDocOnlyService)])\nclass App {}\n' \
    > "$T/c8/lib/app/app.dart"
  printf '{"configVersion":2,"packages":[{"name":"stacked_kit_fake","rootUri":"../fakekit"}]}' \
    > "$T/c8/.dart_tool/package_config.json"
  printf '/// Example:\n///   final s = locator<GhostPeerService>();\nclass KitDocOnlyService {}\n' \
    > "$T/c8/fakekit/lib/kit_doc_only_service.dart"
  o=$(bash "$SELF" "$T/c8" 2>&1); chk "$?" 0 "a locator<> inside a doc comment is not a peer edge (S8)"
  not "$o" "GhostPeerService" "S8 must not demand a peer that only appears in a comment"
  # twin: the SAME call as real code must still fail, or the fixture proves nothing
  printf 'class KitDocOnlyService { final s = locator<GhostPeerService>(); }\n' \
    > "$T/c8/fakekit/lib/kit_doc_only_service.dart"
  o=$(bash "$SELF" "$T/c8" 2>&1); chk "$?" 1 "the same locator<> as real code still fails (S8 twin)"
  need "$o" "GhostPeerService" "S8 names the real peer edge"

  # S10: a sheet consumed by exactly ONE shell but parked in the global tree must
  # FAIL; the same tree with it moved in-shell must PASS. Consumers reference the
  # generated ENUM (never an import), which is why the check reads
  # app.bottomsheets.dart rather than counting imports.
  mk_s10(){ # $1=dir  $2=sheet path relative to lib/
    mkdir -p "$1/lib/ui/views/train_shell" "$1/lib/app" "$1/$(dirname "lib/$2")"
    printf 'name: apps10\n' > "$1/pubspec.yaml"
    printf '{"selfContained": ["train_shell"], "notes": ""}' > "$1/lib/ui/views/.shell-structure.json"
    printf 'class TrainShellView {}\n' > "$1/lib/ui/views/train_shell/train_shell_view.dart"
    printf 'class TrainShellViewModel {}\n' > "$1/lib/ui/views/train_shell/train_shell_viewmodel.dart"
    printf 'class TrainChrome {}\n' > "$1/lib/ui/views/train_shell/train_chrome.dart"
    printf '## Palette\nkcPrimaryColor\n' > "$1/lib/ui/views/train_shell/design-system.md"
    printf 'class MembershipSheet {}\n' > "$1/lib/$2"
    printf 'enum BottomSheetType { membership }\nvoid setup(){ BottomSheetType.membership: (c,r,x) => MembershipSheet(); }\n' \
      > "$1/lib/app/app.bottomsheets.dart"
    # the sole consumer: a train_shell viewmodel that shows it via the enum variant
    printf 'void show(){ sheet.showCustomSheet(variant: BottomSheetType.membership); }\n' \
      > "$1/lib/ui/views/train_shell/train_shell_uses_sheet.dart"
  }
  mk_s10 "$T/o1" "ui/bottom_sheets/membership/membership_sheet.dart"
  o=$(bash "$SELF" "$T/o1" 2>&1); chk "$?" 1 "sole-consumer sheet parked app-level fails (S10)"
  need "$o" "sole consumer" "S10 names the owning shell"
  need "$o" "belongs in its shell" "S10 says where it must go"
  # twin: same tree, sheet moved into the shell → PASS. Proves S10 checks placement
  # against consumer scope, not something incidental to the fixture.
  mk_s10 "$T/o2" "ui/views/train_shell/bottom_sheets/membership/membership_sheet.dart"
  o=$(bash "$SELF" "$T/o2" 2>&1); chk "$?" 0 "same sheet moved in-shell passes (S10 twin)"
  need "$o" "overlay ownership matches consumer scope" "S10 reports the pass verdict"
  # no generated file at all → N/A, never a silent claim of verification
  rm -f "$T/o2/lib/app/app.bottomsheets.dart"
  o=$(bash "$SELF" "$T/o2" 2>&1); chk "$?" 0 "absent generated overlay file is N/A (S10)"
  need "$o" "overlay-ownership check N/A" "S10 says it could not look"

  # empty selfContained → WARN + exit 0 (never false-fail, never rubber-stamp)
  mkdir -p "$T/b/lib/ui/views"; printf 'name: appb\n' > "$T/b/pubspec.yaml"
  printf '{"selfContained": [], "notes": ""}' > "$T/b/lib/ui/views/.shell-structure.json"
  o=$(bash "$SELF" "$T/b" 2>&1); chk "$?" 0 "empty selfContained is WARN not FAIL"
  need "$o" "WARN" "empty selfContained warns"
  # malformed manifest → FAIL (S0: MUST parse)
  mkdir -p "$T/c/lib/ui/views"; printf 'name: appc\n' > "$T/c/pubspec.yaml"
  printf '{oops' > "$T/c/lib/ui/views/.shell-structure.json"
  o=$(bash "$SELF" "$T/c" 2>&1); chk "$?" 1 "malformed manifest fails"
  # manifest naming a shell that doesn't exist → FAIL, naming it
  mkdir -p "$T/d/lib/ui/views"; printf 'name: appd\n' > "$T/d/pubspec.yaml"
  printf '{"selfContained": ["ghost_shell"], "notes": ""}' > "$T/d/lib/ui/views/.shell-structure.json"
  o=$(bash "$SELF" "$T/d" 2>&1); chk "$?" 1 "manifest naming a missing shell fails"
  need "$o" "ghost_shell" "missing shell is named"
  # no lib/ui/views at all (monorepo-root shape) → WARN + exit 0, app-only
  mkdir -p "$T/e"; printf 'name: appe\n' > "$T/e/pubspec.yaml"
  o=$(bash "$SELF" "$T/e" 2>&1); chk "$?" 0 "no views tree is WARN not FAIL"
  # S5: a *_repository.dart outside services/repositories/ FAILS even with no
  # manifest (placement is manifest-independent; S5 runs before the S0 early-exit).
  mkdir -p "$T/f/lib/ui/views" "$T/f/lib/data"; printf 'name: appf\n' > "$T/f/pubspec.yaml"
  printf 'class UserRepository {}\n' > "$T/f/lib/data/user_repository.dart"
  o=$(bash "$SELF" "$T/f" 2>&1); chk "$?" 1 "misplaced repository fails even with no manifest"
  need "$o" "misplaced repository" "misplaced repository is named (S5)"
  need "$o" "user_repository.dart" "the offending repo file is named (S5)"

  echo "self-test: $P passed, $Fc failed"
  [ "$Fc" -eq 0 ] && exit 0 || exit 1
fi

# ---- resolve the app tree ----
APP="${1:-$PWD}"
APP="$(cd "$APP" 2>/dev/null && pwd)" || { echo "FAIL: app root not found: ${1:-$PWD}" >&2; exit 2; }
VIEWS="$APP/lib/ui/views"
MANIFEST="$VIEWS/.shell-structure.json"

F=0
fail(){ echo "FAIL: $1" >&2; F=$((F+1)); sarif_result "scaffold" "error" "${APP:-}" "$1"; }
ok(){ echo "  ✓ $1"; }
warn(){ echo "WARN: $1"; }

# App-only: no views tree → nothing to check. (At the monorepo root pipeline.sh
# neutralizes this gate with the `pass` sentinel — Phase 3 wiring — but a direct
# run must not false-fail either.)
if [ ! -d "$VIEWS" ]; then
  warn "no $VIEWS — nothing to check (shell structure gate is app-only)"
  exit 0
fi

PKG="$(sed -n 's/^name:[[:space:]]*//p' "$APP/pubspec.yaml" 2>/dev/null | head -1)"
[ -n "$PKG" ] || { echo "FAIL: cannot read package name from $APP/pubspec.yaml" >&2; exit 2; }

# ---- SN: snackbars/ PLACEMENT (was: a blanket ban) ----
# The ban was wrong. stacked ships SnackbarService (stacked_services-1.6.0
# src/snackbar/snackbar_service.dart:12), the showcase registers it
# (showcase_app/lib/app/app.dart:82), and the kit ships setupKitSnackbars()
# (ui_library/lib/utils/kit_action/kit_snackbar_setup.dart) which registers a
# SnackbarConfig per KitSnackbarType. So the dir has real content and the owner's
# shell contract requires it. Inverted to a placement rule: a snackbars/ dir is
# legal app-level (lib/ui/snackbars/) or shell-local
# (lib/ui/views/<shell>/snackbars/), and nowhere else — the same shape as S5.
# NB the old check ended `[ "$F" -eq 0 ] && ok`, which reported SN's verdict from
# the GLOBAL failure count; that only worked because SN ran first. This one counts
# its own violations.
sn_bad=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  rel="${d#"$APP"/}"
  case "$rel" in
    lib/ui/snackbars) ;;                          # app-level: shared across shells
    lib/ui/views/*/snackbars) ;;                  # shell-local: shell-owned
    *) fail "snackbars/ in an unsanctioned location (SN): $rel — legal homes are lib/ui/snackbars/ (shared app-wide) or lib/ui/views/<shell>/snackbars/ (shell-owned)"
       sn_bad=$((sn_bad+1));;
  esac
done < <(find "$APP/lib/ui" -type d -name snackbars 2>/dev/null)
[ "$sn_bad" -eq 0 ] && ok "snackbars/ dirs correctly placed or absent (SN)"

# ---- S5: services placement (D10) — placement-not-existence. If a *_facade.dart
# or *_repository.dart exists ANYWHERE under lib/, it MUST live under a
# services/facades/ or services/repositories/ dir respectively. Loose
# *_service.dart is legal anywhere. Absence of facades/repos is NOT a violation —
# the gate asserts placement, never existence, so a host with no facades passes.
s5_bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    */services/facades/*) ;;
    *) fail "misplaced facade (S5): ${f#"$APP"/} — *_facade.dart must live under services/facades/"; s5_bad=$((s5_bad+1));;
  esac
done < <(find "$APP/lib" -name '*_facade.dart' -not -path '*/.*' 2>/dev/null)
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    */services/repositories/*) ;;
    *) fail "misplaced repository (S5): ${f#"$APP"/} — *_repository.dart must live under services/repositories/"; s5_bad=$((s5_bad+1));;
  esac
done < <(find "$APP/lib" -name '*_repository.dart' -not -path '*/.*' 2>/dev/null)
[ "$s5_bad" -eq 0 ] && ok "services placement: facades/repositories correctly placed or absent (S5)"

# ---- S8: peer-service registration. A kit service registered in @StackedApp
# whose OWN source resolves locator<Y>() needs Y registered too. Generic by
# construction: resolves each registered Kit* class to its kit source through
# .dart_tool/package_config.json, so it covers every kit service rather than a
# hardcoded pair. Found because sample-app registered KitNotificationService without
# SnackbarService (KitNotificationService:94 does locator<SnackbarService>()),
# which throws on Android and on any iOS call passing actionLabel.
# Degrades to WARN — never a silent pass — when python3 or package_config is
# absent, because "deps not fetched" must not read as "peers verified".
# NOT `have python3` — this gate defines no have(); that typo made S8 report a
# false "skipped" on every run (found by reading the gate's own output, line 176).
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 unavailable — peer-service check (S8) skipped"
else
  s8out="$(python3 - "$APP" <<'PY' 2>&1
import glob, json, os, re, sys, urllib.parse
app = sys.argv[1]

Q3D = chr(34) * 3
Q3S = chr(39) * 3

def strip_comments(src):
    # Blank Dart comment CONTENT, preserve newlines and code.
    # S8 is a pure SELECTOR (does this class resolve locator<X>?), so it must read
    # comment-free source. Without this, a kit doc-comment showing example usage --
    # `/// final _hapticService = locator<HapticService>();` at
    # haptics/lib/src/kit_haptic_service.dart:21 -- makes S8 demand a registration
    # the code never needs. That false positive fired on showcase_app, the kit's
    # own exemplar, on the first real run. Same defect class as review_checklist's
    # comment blindness; same fix. Single pass, because strings and comments
    # interleave: 'https://x' is not a comment, /* */ nests, raw+triple quotes exist.
    out = []; i = 0; n = len(src)
    while i < n:
        c = src[i]
        if c == chr(34) or c == chr(39):
            q = src[i:i+3] if src[i:i+3] in (Q3D, Q3S) else c
            out.append(src[i:i+len(q)]); i += len(q)
            while i < n:
                if src[i] == chr(92) and len(q) == 1:
                    out.append(src[i:i+2]); i += 2; continue
                if src.startswith(q, i):
                    out.append(q); i += len(q); break
                out.append(src[i]); i += 1
            continue
        if src.startswith('//', i):
            while i < n and src[i] != chr(10):
                i += 1
            continue
        if src.startswith('/*', i):
            depth = 1; i += 2
            while i < n and depth:
                if src.startswith('/*', i): depth += 1; i += 2
                elif src.startswith('*/', i): depth -= 1; i += 2
                else:
                    if src[i] == chr(10): out.append(chr(10))
                    i += 1
            continue
        out.append(c); i += 1
    return ''.join(out)
appdart = os.path.join(app, 'lib', 'app', 'app.dart')
if not os.path.exists(appdart):
    print('SKIP: no lib/app/app.dart'); sys.exit(0)
src = open(appdart, errors='ignore').read()
have = set(re.findall(r'classType:\s*([A-Za-z0-9_]+)', src)) | \
       set(re.findall(r'asType:\s*([A-Za-z0-9_]+)', src))
pc = os.path.join(app, '.dart_tool', 'package_config.json')
if not os.path.exists(pc):
    print('WARN: no .dart_tool/package_config.json — run flutter pub get; S8 not verified'); sys.exit(0)
try:
    pkgs = json.load(open(pc))['packages']
except Exception as e:
    print('WARN: package_config unreadable (%s) — S8 not verified' % e); sys.exit(0)
# Build one class -> (file, text) index across kit packages. Single pass: a
# per-service glob would re-read every kit file once per registered service.
index = {}
for p in pkgs:
    name = p.get('name', '')
    if not (name.startswith('stacked_kit') or name == 'ui_library'):
        continue
    raw = urllib.parse.urlparse(p.get('rootUri', '')).path
    root = raw if os.path.isabs(raw) else os.path.normpath(os.path.join(app, '.dart_tool', raw))
    for f in glob.glob(os.path.join(root, 'lib', '**', '*.dart'), recursive=True):
        try:
            t = open(f, errors='ignore').read()
        except OSError:
            continue
        for cls in re.findall(r'^\s*class\s+([A-Z][A-Za-z0-9_]*)', t, re.M):
            index.setdefault(cls, (f, t))
bad = 0
for kt in sorted(t for t in have if t.startswith('Kit')):
    hit = index.get(kt)
    if not hit:
        continue
    f, t = hit
    for peer in sorted(set(re.findall(r'locator<([A-Z][A-Za-z0-9_]*)>', strip_comments(t)))):
        if peer in have or peer == kt:
            continue
        print('FAIL: %s is registered but its peer %s is not (S8) — %s calls '
              'locator<%s>(); add LazySingleton(classType: %s) to @StackedApp '
              '[%s]' % (kt, peer, kt, peer, peer, os.path.basename(f)))
        bad += 1
# setupKitSnackbars(): the kit registers a SnackbarConfig per KitSnackbarType
# variant there. Asserting the CALL, not a main.dart template, because the
# scaffolder has no main.dart template to emit it from.
if 'KitNotificationService' in have:
    called = False
    for x in glob.glob(os.path.join(app, 'lib', '**', '*.dart'), recursive=True):
        try:
            if 'setupKitSnackbars' in open(x, errors='ignore').read():
                called = True; break
        except OSError:
            pass
    if not called:
        print('FAIL: KitNotificationService is registered but setupKitSnackbars() '
              'is never called in lib/ (S8) — the KitSnackbarType SnackbarConfig '
              'variants stay unregistered, so severity/position render as bare '
              'defaults (showcase_app/lib/main.dart:26 is the reference call site)')
        bad += 1
if bad == 0:
    print('OK: peer services registered for every Kit* service (S8)')
PY
)"
  case "$s8out" in
    *FAIL:*) while IFS= read -r l; do
               case "$l" in FAIL:*) fail "${l#FAIL: }";; esac
             done < <(printf '%s\n' "$s8out") ;;
    WARN:*)  warn "${s8out#WARN: }" ;;
    SKIP:*)  ok "peer-service check N/A (${s8out#SKIP: })" ;;
    *)       ok "peer services registered for every Kit* service (S8)" ;;
  esac
fi

# ---- S10: overlay OWNERSHIP by enum reference. Consumers never import an overlay
# — they call showCustomSheet(variant: BottomSheetType.x), so an importer-count
# test is vacuous (verified against showcase_app: NoticeSheet is imported only by
# itself, app.dart and the generated app.bottomsheets.dart). This follows the real
# call graph instead: resolve enum member -> class -> file via the GENERATED
# app.bottomsheets.dart / app.dialogs.dart, then count the distinct shells whose
# files reference that variant.
#   exactly 1 shell  -> sole consumer, the overlay MUST live in that shell
#   2+ shells        -> genuinely shared, app-level lib/ui/<kind>/ is correct
#   0 shells         -> registered but unconsumed: WARN, never FAIL
# WARNs (never silently passes) when the generated files are absent — build_runner
# not having run must not read as "ownership verified".
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 unavailable — overlay-ownership check (S10) skipped"
else
  s10out="$(python3 - "$APP" <<'PY' 2>&1
import glob, os, re, sys
app = sys.argv[1]
kinds = [('bottomsheets', 'BottomSheetType', 'bottom_sheets'),
         ('dialogs', 'DialogType', 'dialogs')]
gen = [k for k, _, _ in kinds if os.path.exists(os.path.join(app, 'lib', 'app', 'app.%s.dart' % k))]
if not gen:
    print('SKIP: no generated app.bottomsheets.dart / app.dialogs.dart — no overlays registered')
    sys.exit(0)
# class -> file index over the app's own lib/
decl = {}
for f in glob.glob(os.path.join(app, 'lib', '**', '*.dart'), recursive=True):
    try:
        t = open(f, errors='ignore').read()
    except OSError:
        continue
    for cls in re.findall(r'^\s*class\s+([A-Z][A-Za-z0-9_]*)', t, re.M):
        decl.setdefault(cls, f)
shell_re = re.compile(r'/lib/ui/views/([^/]+)/')
bad = 0
for key, enum, dirname in kinds:
    gpath = os.path.join(app, 'lib', 'app', 'app.%s.dart' % key)
    if not os.path.exists(gpath):
        continue
    gtext = open(gpath, errors='ignore').read()
    # Generated builder map entries look like:
    #   BottomSheetType.notice: (context, request, completer) => NoticeSheet(
    #       request: request, completer: completer),
    # The builder's parameter list CONTAINS commas and the entry spans lines, so a
    # `[^,]*?` bridge between the member and the class silently matches nothing
    # (found by the o1 fixture failing to fire). Anchor on the member, then look
    # ahead a bounded window for the `=> ClassName(` the map arrow guarantees.
    pairs = []
    for m in re.finditer(re.escape(enum) + r'\.([A-Za-z0-9_]+)\s*:', gtext):
        win = gtext[m.end():m.end() + 300]
        cm = re.search(r'=>\s*([A-Z][A-Za-z0-9_]*)\s*\(', win)
        if cm:
            pairs.append((m.group(1), cm.group(1)))
    for member, cls in pairs:
        f = decl.get(cls)
        if not f:
            continue
        consumers = set()
        for c in glob.glob(os.path.join(app, 'lib', '**', '*.dart'), recursive=True):
            if os.path.normpath(c) == os.path.normpath(f) or '/lib/app/' in c.replace(os.sep, '/'):
                continue   # the overlay itself and the generated registry are not consumers
            try:
                t = open(c, errors='ignore').read()
            except OSError:
                continue
            if '%s.%s' % (enum, member) in t:
                m = shell_re.search(c.replace(os.sep, '/'))
                consumers.add(m.group(1) if m else '<app-level>')
        rel = os.path.relpath(f, app)
        shells = {c for c in consumers if c != '<app-level>'}
        if not consumers:
            print('WARN: %s.%s (%s) is registered but no file references the variant '
                  '— unconsumed overlay' % (enum, member, cls))
        elif len(shells) == 1 and '<app-level>' not in consumers:
            owner = next(iter(shells))
            want = 'lib/ui/views/%s/%s/' % (owner, dirname)
            if not rel.replace(os.sep, '/').startswith(want):
                print('FAIL: %s is the sole consumer of %s.%s but %s lives at %s (S10) '
                      '— a sole-consumer overlay belongs in its shell: move it under %s'
                      % (owner, enum, member, cls, rel, want))
                bad += 1
        elif len(shells) >= 2:
            want = 'lib/ui/%s/' % dirname
            if not rel.replace(os.sep, '/').startswith(want):
                print('FAIL: %s.%s (%s) is consumed by %d shells (%s) but lives at %s '
                      '(S10) — a genuinely shared overlay belongs app-level under %s'
                      % (enum, member, cls, len(shells), ', '.join(sorted(shells)), rel, want))
                bad += 1
if bad == 0:
    print('OK: overlay ownership matches consumer scope (S10)')
PY
)"
  case "$s10out" in
    *FAIL:*) while IFS= read -r l; do
               case "$l" in FAIL:*) fail "${l#FAIL: }";; WARN:*) warn "${l#WARN: }";; esac
             done < <(printf '%s\n' "$s10out") ;;
    WARN:*)  warn "${s10out#WARN: }" ;;
    SKIP:*)  ok "overlay-ownership check N/A (${s10out#SKIP: })" ;;
    *)       ok "overlay ownership matches consumer scope (S10)" ;;
  esac
fi

# ---- S0: manifest shape ----
if [ ! -f "$MANIFEST" ]; then
  warn "no $MANIFEST — no shell has opted into the self-contained pattern yet; gate is a no-op until the first migration"
  [ "$F" -gt 0 ] && { echo "shell_structure_gate: $F failure(s)" >&2; exit 1; }
  exit 0
fi
out="$(python3 - "$MANIFEST" <<'PY' 2>&1
import json, sys
try:
    with open(sys.argv[1], encoding='utf-8') as f:
        d = json.load(f)
except Exception as e:
    print('does not parse as JSON: %s' % e); sys.exit(1)
sc = d.get('selfContained')
if not isinstance(sc, list) or not all(isinstance(x, str) for x in sc):
    print('selfContained must be a list of strings'); sys.exit(1)
for x in sc:
    print(x)
PY
)"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "manifest $MANIFEST: $out (S0)"
  echo "shell_structure_gate: $F failure(s)" >&2; exit 1
fi
SHELLS="$out"
ok "manifest parses"

if [ -z "$SHELLS" ]; then
  warn "selfContained is empty — no shell has opted in yet; S1–S4 skipped (populate via Phase 2 migrations)"
  [ "$F" -gt 0 ] && { echo "shell_structure_gate: $F failure(s)" >&2; exit 1; }
  exit 0
fi

# ---- per self-contained shell: S1 shape, S2 locality, S3 barrels, S4 doc ----
for s in $SHELLS; do
  dir="$VIEWS/$s"
  if [ ! -d "$dir" ]; then
    fail "manifest names '$s' but $dir does not exist (S0)"
    continue
  fi

  # S1 — ≥1 view with a matching viewmodel (flexible: never a count of 5)
  nviews="$(find "$dir" -name '*_view.dart' -not -path '*/.*' 2>/dev/null | grep -c . || true)"
  if [ "$nviews" -lt 1 ]; then
    fail "$s: no *_view.dart found (S1: a shell needs ≥ 1 view)"
  else
    pair=0
    while IFS= read -r v; do
      [ -f "${v%_view.dart}_viewmodel.dart" ] && pair=1
    done < <(find "$dir" -name '*_view.dart' 2>/dev/null)
    if [ "$pair" -eq 1 ]; then
      ok "$s: view + matching viewmodel present ($nviews view(s))"
    else
      fail "$s: no *_view.dart has a matching *_viewmodel.dart (S1)"
    fi
  fi

  # S1/S4 — design-system.md present and non-trivial
  ds="$dir/design-system.md"
  if [ ! -f "$ds" ]; then
    fail "$s: design-system.md missing (S1)"
  elif grep -qE '^##[[:space:]]+(Palette|Tokens)' "$ds" && grep -qE '(kc[A-Z][A-Za-z0-9]*|KitColors)' "$ds"; then
    ok "$s: design-system.md carries the palette vocabulary"
  else
    fail "$s: design-system.md lacks a '## Palette' / '## Tokens' heading with a kit color reference (kc*/KitColors) (S4)"
  fi

  # S2 — locality teeth: a global-overlay import is a violation ONLY when the
  # imported overlay no longer exists at the global path (it was relocated into a
  # shell — a stale/ownership leak). Shared overlays that STAY global resolve at
  # $APP/lib/<rel> (package:$PKG/<rel> → lib/<rel>) and are exempt.
  found_leak=0; exempted=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    # imported package sub-path: package:PKG/<rel> → APP/lib/<rel>
    rel="$(printf '%s\n' "$l" | sed -n "s|.*import[[:space:]]*'package:$PKG/\([^']*\)'.*|\1|p")"
    [ -n "$rel" ] || continue
    if [ -f "$APP/lib/$rel" ]; then
      exempted=$((exempted+1)); continue   # overlay still lives globally → shared, unmoved → exempt
    fi
    found_leak=1
    fail "$s: stale global-overlay import (S2) — overlay relocated, no longer at global path lib/$rel: ${l#"$APP"/}"
  done < <(grep -rnE "import[[:space:]]+'package:$PKG/ui/(bottom_sheets|dialogs|snackbars)/" "$dir" --include='*.dart' 2>/dev/null)
  if [ "$found_leak" -eq 0 ]; then
    if [ "$exempted" -gt 0 ]; then
      ok "$s: $exempted shared global-overlay import(s) exempt (still global), no relocated-overlay leaks"
    else
      ok "$s: no global overlay imports"
    fi
  fi
  # … and no cross-shell view-tree imports (shared services/models are fine).
  # Overlay subdirs (bottom_sheets|dialogs|snackbars) are EXEMPT — overlays are
  # shared app-wide (one global registration; show from anywhere via the enum
  # variant); view trees stay shell-private.
  ximp="$(grep -rnE "import[[:space:]]+'package:$PKG/ui/views/" "$dir" --include='*.dart' 2>/dev/null | grep -vE "package:$PKG/ui/views/$s/" | grep -vE "package:$PKG/ui/views/[^/]+/(bottom_sheets|dialogs|snackbars)/" || true)"
  xovl="$(grep -rnE "import[[:space:]]+'package:$PKG/ui/views/[^/]+/(bottom_sheets|dialogs|snackbars)/" "$dir" --include='*.dart' 2>/dev/null | grep -vE "package:$PKG/ui/views/$s/" || true)"
  if [ -n "$ximp" ]; then
    while IFS= read -r l; do
      [ -n "$l" ] && fail "$s: cross-shell import (S2): ${l#"$APP"/}"
    done < <(printf '%s\n' "$ximp")
  elif [ -n "$xovl" ]; then
    ok "$s: cross-shell overlay import(s) exempt (overlays shared app-wide), no cross-shell view imports"
  else
    ok "$s: no cross-shell imports"
  fi

  # S6 — Q1 (unconditional): a shell OWNS its widgets. A component two
  # form-factor files share must have a home that is not one of them; the
  # observed defect was tablet/desktop importing their row out of
  # <surface>_view.mobile.dart.
  #
  # The legal homes are the ones the kit already practises and documents —
  # NOT a bare <shell>/widgets/, which review_checklist.sh check 1o/D
  # explicitly REJECTS ("leaks widgets across the shell's views"):
  #
  #   <shell>/shared/widgets/       cross-view, shell-scoped
  #   <shell>/<view>/widgets/       view-specific
  #   <shell>/*_chrome.dart         the chrome convention (W35-CONTRACT:53)
  #
  # This check was originally written against `<shell>/widgets/` and so
  # contradicted 1o/D — one gate demanding the layout the other forbids, which
  # is unsatisfiable. The corpus settles it: showcase_app ships
  # showcase_notes_shell/shared/widgets/ plus per-view widgets/, and both
  # kit-feature-implementer/SKILL.md:82,87 and kit-reviewer/SKILL.md:45
  # document that split. S6 was the newer, wronger rule.
  # Collected once here and reused by S7 (bash 3.2: newline string, no arrays).
  WIDGET_DIRS=""
  nw=0
  for wdir in "$dir"/shared/widgets "$dir"/*/widgets; do
    [ -d "$wdir" ] || continue
    # `$dir/*/widgets` also matches `$dir/shared/widgets`, so the first arm
    # would be counted twice (and S7 would scan it twice).
    case "$WIDGET_DIRS" in *"$wdir
"*) continue;; esac
    WIDGET_DIRS="$WIDGET_DIRS$wdir
"
    nw=$((nw + $(find "$wdir" -name '*.dart' 2>/dev/null | grep -c . || true)))
  done
  chrome="$(find "$dir" -maxdepth 1 -name '*_chrome.dart' 2>/dev/null | head -1)"
  if [ "$nw" -gt 0 ] || [ -n "$chrome" ]; then
    # Report only what is actually present: "widgets/: 0 file(s)" implied a dir
    # that does not exist whenever the chrome file alone satisfied the check.
    if [ "$nw" -gt 0 ] && [ -n "$chrome" ]; then
      ok "$s: owns its widgets (S6) — widgets/: $nw file(s), $(basename "$chrome")"
    elif [ "$nw" -gt 0 ]; then
      ok "$s: owns its widgets (S6) — widgets/: $nw file(s)"
    else
      ok "$s: owns its widgets (S6) — $(basename "$chrome")"
    fi
  else
    fail "$s: no widgets/*.dart and no *_chrome.dart (S6) — a shell owns its widgets; legal homes are $s/shared/widgets/, $s/<view>/widgets/ or a *_chrome.dart (a bare $s/widgets/ is rejected by review check 1o/D)"
  fi

  # S7 — Q2: a shared widget may ADAPT its internals (getValueForScreenType /
  # ResponsiveBuilder / RefinedLayoutBuilder) but must never SWAP layouts.
  # ScreenTypeLayout dispatch stays in <surface>_view.dart, which keeps
  # anti-slop.md:43 intact (the three layouts stay genuinely different).
  s7=0
  while IFS= read -r wf; do
    [ -n "$wf" ] || continue
    if grep -qE '(^|[^A-Za-z0-9_])ScreenTypeLayout[[:space:]]*[.(]' "$wf" 2>/dev/null; then
      fail "$s: ScreenTypeLayout in a shared widget (S7): ${wf#"$APP"/} — widgets adapt internals via getValueForScreenType/ResponsiveBuilder; whole-layout dispatch belongs to <surface>_view.dart"
      s7=1
    fi
  done < <({ printf '%s' "$WIDGET_DIRS" | while IFS= read -r d7; do
               [ -n "$d7" ] && find "$d7" -name '*.dart' 2>/dev/null
             done
             find "$dir" -maxdepth 1 -name '*_chrome.dart' 2>/dev/null; })
  [ "$s7" -eq 0 ] && ok "$s: no layout-swapping in shared widgets (S7)"

  # S9 — Q1b, revived. S6 asserts a widget HOME exists; it does NOT assert the
  # squatting stopped. A shell could add <shell>_chrome.dart and still have
  # tablet/desktop importing <surface>_view.mobile.dart — S6 green, original
  # defect intact. A form-factor variant is ONE layout, never a component library.
  # Exempt by construction: <surface>_view.dart (the dispatcher) MUST import all
  # three variants for ScreenTypeLayout — only a VARIANT importing a variant fails.
  # Ceiling: this catches variant->variant. A different surface's dispatcher
  # importing a foreign variant is also wrong and is NOT caught here; widen the
  # importer pattern if that shows up in real output.
  s9=0
  while IFS= read -r vf; do
    [ -n "$vf" ] || continue
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      # WHOLESALE DELEGATION IS NOT SQUATTING. "one layout, not a component
      # library" is the rule; a variant that uses ONLY the imported variant's
      # own View class is using it as one layout — the documented
      # "wide tiers centre the phone column" idiom
      # (showcase_notes_create_account_view.tablet.dart). Cherry-picking any
      # OTHER symbol out of a variant is the real defect (sample-app's
      # TrainingLibraryRow), and still fails below.
      imp="$(printf '%s' "$l" | sed -E "s/.*'([^']*)'.*/\1/")"
      target="$(dirname "$vf")/$(basename "$imp")"
      if [ -f "$target" ]; then
        # Which of the imported variant's OWN classes does the importer use?
        # Its top-level View class (…ViewMobile/Tablet/Desktop) is delegation;
        # anything else is a component being cherry-picked out of a layout.
        squatted=""
        while IFS= read -r c; do
          [ -n "$c" ] || continue
          case "$c" in *ViewMobile|*ViewTablet|*ViewDesktop) continue;; esac
          grep -qE "(^|[^A-Za-z0-9_])${c}([^A-Za-z0-9_]|$)" \
            <(grep -v "^[[:space:]]*import[[:space:]]" "$vf") 2>/dev/null \
            && squatted="$squatted $c"
        done < <(grep -oE '^(abstract[[:space:]]+)?class[[:space:]]+[A-Z][A-Za-z0-9_]*' "$target" 2>/dev/null | awk '{print $NF}')
        [ -n "$squatted" ] || continue          # wholesale delegation — allowed
        l="$l (uses:$squatted)"
      fi
      fail "$s: form-factor variant imports another variant (S9): ${vf#"$APP"/} -> ${l}; move the shared component into widgets/ or *_chrome.dart — a *_view.{mobile,tablet,desktop}.dart is one layout, not a component library"
      s9=1
    done < <(grep -oE "import[[:space:]]+'[^']*_view\.(mobile|tablet|desktop)\.dart'" "$vf" 2>/dev/null)
  done < <(find "$dir" \( -name '*_view.mobile.dart' -o -name '*_view.tablet.dart' -o -name '*_view.desktop.dart' \) 2>/dev/null)
  [ "$s9" -eq 0 ] && ok "$s: no variant-to-variant component imports (S9)"

  # S3 — overlay barrel integrity
  for kind in bottom_sheets:sheet dialogs:dialog; do
    sub="${kind%%:*}"; suffix="${kind##*:}"
    [ -d "$dir/$sub" ] || continue
    for d2 in "$dir/$sub"/*/; do
      [ -d "$d2" ] || continue
      n="$(basename "$d2")"
      if [ -f "$d2${n}_${suffix}.dart" ]; then
        ok "$s: $sub/$n barrel present"
      else
        fail "$s: $sub/$n/ exists but ${n}_${suffix}.dart is missing (S3 barrel)"
      fi
    done
  done
done

if [ "$F" -gt 0 ]; then
  echo "shell_structure_gate: $F failure(s)" >&2
  exit 1
fi
echo "shell_structure_gate: PASS ($APP)"
exit 0
