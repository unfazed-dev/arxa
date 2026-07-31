#!/usr/bin/env bash
# gates/scaffold/selftest.sh — R5 suite for the scaffold (shell-structure) gate.
# Happy path AND >=1 negative case. Plants a defect and asserts the gate exits 1
# and names the offending file. The vendored gate's own --self-test needs fixture
# trees that are not shipped, so this suite is self-contained: it builds a tmp app
# and exercises the gate's normal CLI.
set -uo pipefail
GATE="$(cd "$(dirname "$0")" && pwd)/scaffold.sh"
pass=0; failc=0
chk(){ [ "$1" = "$2" ] && pass=$((pass+1)) || { failc=$((failc+1)); echo "  FAIL: expected exit [$2] got [$1] — $3"; }; }
need(){ case "$1" in *"$2"*) pass=$((pass+1));; *) failc=$((failc+1)); echo "  FAIL: output should mention [$2] — $3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkapp(){ rm -rf "$T/a"; mkdir -p "$T/a/lib/ui/views"; printf 'name: scafapp\n' > "$T/a/pubspec.yaml"; }

# ---- HAPPY: an app with no manifest and no placement violations WARNs + exit 0
mkapp
o="$(bash "$GATE" "$T/a" 2>&1)"; chk "$?" 0 "happy: no violations -> exit 0"
need "$o" "WARN" "happy warns about the absent manifest (no-op, not a fail)"

# ---- NEGATIVE: a *_repository.dart outside services/repositories/ (S5) -------
# NEGATIVE: a misplaced repository file fails placement (S5), naming the file.
mkapp
mkdir -p "$T/a/lib/data"; printf 'class UserRepository {}\n' > "$T/a/lib/data/user_repository.dart"
o="$(bash "$GATE" "$T/a" 2>&1)"; chk "$?" 1 "negative: misplaced repository fails"
need "$o" "user_repository.dart" "negative names the offending repository file"

# ---- NEGATIVE: a *_facade.dart outside services/facades/ (S5) ----------------
# NEGATIVE: a misplaced facade file fails placement (S5), naming the file.
mkapp
mkdir -p "$T/a/lib/features"; printf 'class BillingFacade {}\n' > "$T/a/lib/features/billing_facade.dart"
o="$(bash "$GATE" "$T/a" 2>&1)"; chk "$?" 1 "negative: misplaced facade fails"
need "$o" "billing_facade.dart" "negative names the offending facade file"

echo "scaffold selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ] && exit 0 || exit 1
