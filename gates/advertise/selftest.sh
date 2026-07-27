#!/usr/bin/env bash
# gates/advertise/selftest.sh — R5 proof that the advertise gate can fail.
# Plants each defect in an isolated temp tree and asserts the gate exits 1 AND
# names the offending provider/surface. A selftest that proves only the happy
# path is rejected at review (R5).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/advertise.py"

pass=0; failc=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; failc=$((failc + 1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# A fake "suite" file whose digest the evidence ledger will record. The gate
# resolves --root-relative suite paths, so we point evidence at this file.
printf '#!/usr/bin/env python3\nprint("fake suite")\n' > "$TMP/fake_suite.py"
DIGEST="$(python3 -c 'import hashlib,sys;print("sha256:"+hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$TMP/fake_suite.py")"

write_registry() {
  # $1 = verification tier for SeedAuthBackend; everything else stub.
  local tier="$1"
  python3 - "$TMP/registry.json" "$tier" <<'PY'
import json, sys
path, tier = sys.argv[1], sys.argv[2]
json.dump({"version": 1, "kits": [
  {"dir": "auth", "package": "stacked_kit_auth", "capabilities": [], "topology": "standalone",
   "playbook": "auth/auth_playbook.mdx", "hasSkill": False, "provides": {}, "providers": [
     {"name": "SeedAuthBackend", "verification": tier},
     {"name": "Apple SignIn", "verification": "stub"},
   ]},
  {"dir": "payments", "package": "stacked_kit_payments", "capabilities": [], "topology": "standalone",
   "playbook": "payments/payments_playbook.mdx", "hasSkill": False, "provides": {}, "providers": [
     {"name": "Stripe", "verification": "stub"},
   ]},
]}, open(path, "w"), indent=2)
PY
}

write_evidence() {
  # $1 = tier recorded in evidence for SeedAuthBackend ("" = write no ledger)
  local tier="$1"
  if [ -z "$tier" ]; then return; fi
  python3 - "$TMP/evidence.json" "$tier" "$DIGEST" <<'PY'
import json, sys
path, tier, digest = sys.argv[1], sys.argv[2], sys.argv[3]
json.dump({"ledger": {"auth/SeedAuthBackend": {
    "tier": tier, "suite": "fake_suite.py", "digest": digest, "ran_at": "2026-07-27T00:00:00Z",
}}}, open(path, "w"), indent=2)
PY
}

write_offers() {
  # $1 = json array of offers
  python3 - "$TMP/offers.json" "$1" <<'PY'
import json, sys
path, offers = sys.argv[1], sys.argv[2]
json.dump({"surfaces": [{"name": "showcase.seed", "offers": json.loads(offers)}]},
          open(path, "w"), indent=2)
PY
}

# 0 — happy path: SeedAuthBackend port-tested, evidence-backed, offered at tier.
write_registry port-tested
write_evidence port-tested
write_offers '[{"kit":"auth","provider":"SeedAuthBackend","tier":"port-tested"}]'
if python3 "$GATE" --registry "$TMP/registry.json" --evidence "$TMP/evidence.json" \
     --offers "$TMP/offers.json" --root "$TMP" >/tmp/adv0 2>&1; then
  ok "happy path: evidence-backed offer at tier passes"
else bad "honest tree should pass"; cat /tmp/adv0; fi

# 1 — NEGATIVE: a stub-tier provider is offered.
write_registry port-tested
write_evidence port-tested
write_offers '[{"kit":"payments","provider":"Stripe","tier":"port-tested"}]'
if python3 "$GATE" --registry "$TMP/registry.json" --evidence "$TMP/evidence.json" \
     --offers "$TMP/offers.json" --root "$TMP" >/tmp/adv1 2>&1; then
  bad "offering a stub provider was not detected"
elif grep -q "Stripe" /tmp/adv1 && grep -qi "stub" /tmp/adv1; then ok "NEGATIVE: stub provider offered -> FAIL named"
else bad "stub-offer failed but did not name the provider"; cat /tmp/adv1; fi

# 2 — NEGATIVE: hand-edited tier (registry bumped, no evidence record).
write_registry port-tested        # Apple SignIn bumped to port-tested below
python3 - "$TMP/registry.json" <<'PY'
import json, sys
p = sys.argv[1]
r = json.load(open(p))
# hand-edit Apple SignIn from stub -> device-verified with NO evidence
for k in r["kits"]:
    for pr in k.get("providers", []):
        if pr["name"] == "Apple SignIn":
            pr["verification"] = "device-verified"
json.dump(r, open(p, "w"), indent=2)
PY
write_evidence port-tested        # ledger only has SeedAuthBackend, not Apple SignIn
write_offers '[]'
if python3 "$GATE" --registry "$TMP/registry.json" --evidence "$TMP/evidence.json" \
     --offers "$TMP/offers.json" --root "$TMP" >/tmp/adv2 2>&1; then
  bad "hand-edited tier was not detected"
elif grep -q "Apple SignIn" /tmp/adv2 && grep -qi "hand-edit" /tmp/adv2; then ok "NEGATIVE: hand-edited tier -> FAIL named"
else bad "hand-edit failed but did not name it"; cat /tmp/adv2; fi

# 3 — NEGATIVE: offer above recorded tier.
write_registry port-tested
write_evidence port-tested
write_offers '[{"kit":"auth","provider":"SeedAuthBackend","tier":"device-verified"}]'
if python3 "$GATE" --registry "$TMP/registry.json" --evidence "$TMP/evidence.json" \
     --offers "$TMP/offers.json" --root "$TMP" >/tmp/adv3 2>&1; then
  bad "offer above recorded tier was not detected"
elif grep -q "SeedAuthBackend" /tmp/adv3 && grep -qi "above" /tmp/adv3; then ok "NEGATIVE: offer above tier -> FAIL named"
else bad "above-tier offer failed but did not name it"; cat /tmp/adv3; fi

# 4 — NEGATIVE: stale evidence (suite digest changed since tier was set).
write_registry port-tested
printf '#!/usr/bin/env python3\nprint("CHANGED suite")\n' > "$TMP/fake_suite.py"
write_evidence port-tested        # digest still records the OLD content
write_offers '[]'
if python3 "$GATE" --registry "$TMP/registry.json" --evidence "$TMP/evidence.json" \
     --offers "$TMP/offers.json" --root "$TMP" >/tmp/adv4 2>&1; then
  bad "stale evidence (suite changed) was not detected"
elif grep -qi "changed" /tmp/adv4; then ok "NEGATIVE: stale evidence -> FAIL named"
else bad "stale evidence failed but did not name it"; cat /tmp/adv4; fi

echo "---"
echo "selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ]
