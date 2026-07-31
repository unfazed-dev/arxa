#!/usr/bin/env python3
"""advertise — the one gate that stops a surface offering a provider above its
recorded verification tier.

RULE (plan 13.3), written into this gate:

    A provider's `verification` tier is set ONLY by a suite that ran at that
    tier. Tier 3 (device-verified) cannot be claimed by a simulator run, and no
    tier may be set by editing the registry by hand. The field is EVIDENCE, not
    a label — the same standard as structure.json.

The gate asserts two things, forever:

  1. EVIDENCE — every provider in the registry whose verification != 'stub'
     must carry a matching record in the evidence ledger (tier, suite path,
     content digest, run timestamp). The ledger is written ONLY by a tier suite
     (tools/verification/); the gate never writes it. Hand-editing a tier in the
     registry therefore fails: the bumped tier has no evidence to back it.

  2. OFFER — no surface may offer a provider above its recorded tier. Offering a
     'stub'-tier provider at any level fails outright (a stub can never be
     offered); offering a provider at a tier higher than its recorded tier fails.

Reads (defaults relative to repo root, overridable for the selftest):
  --registry  tools/vendor/kit_registry/kit-registry.json
  --evidence  tools/verification/evidence.json
  --offers    gates/advertise/offers.json

Exits 0 if honest, 1 naming the offending provider or surface. Stdlib only.
"""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEF_REGISTRY = os.path.join(ROOT, "tools", "vendor", "kit_registry", "kit-registry.json")
DEF_EVIDENCE = os.path.join(ROOT, "tools", "verification", "evidence.json")
DEF_OFFERS = os.path.join(HERE, "offers.json")

TIERS = ["stub", "port-tested", "sim-verified", "device-verified"]
RANK = {t: i for i, t in enumerate(TIERS)}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def provider_index(reg):
    """{(kit_dir, provider_name): verification} across all kits."""
    idx = {}
    for k in reg["kits"]:
        for p in k.get("providers", []):
            idx[(k["dir"], p["name"])] = p["verification"]
    return idx


def file_digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def check_evidence(reg, idx, evidence_path, root):
    """Every registry provider whose tier != stub must have a matching,
    suite-backed evidence record. Returns a list of error strings."""
    errs = []
    if not os.path.isfile(evidence_path):
        # No ledger at all: every non-stub provider is unsupported evidence.
        for (kit, name), tier in idx.items():
            if tier != "stub":
                errs.append(
                    f"{kit}/{name}: tier '{tier}' but no evidence ledger at "
                    f"{os.path.relpath(evidence_path, root)} — a tier is set "
                    f"only by a suite that ran (13.3); hand-edit rejected")
        return errs
    ledger = load(evidence_path).get("ledger", {})
    for (kit, name), tier in idx.items():
        if tier == "stub":
            continue
        key = f"{kit}/{name}"
        rec = ledger.get(key)
        if rec is None:
            errs.append(
                f"{kit}/{name}: tier '{tier}' but no evidence record — a tier "
                f"is set only by a suite that ran (13.3); hand-edit rejected")
            continue
        if rec.get("tier") != tier:
            errs.append(
                f"{kit}/{name}: registry tier '{tier}' != evidence tier "
                f"'{rec.get('tier')}' — registry was hand-edited away from "
                f"what the suite recorded")
            continue
        suite = rec.get("suite")
        suite_abs = os.path.join(root, suite) if not os.path.isabs(suite) else suite
        if not os.path.isfile(suite_abs):
            errs.append(
                f"{kit}/{name}: evidence points at suite '{suite}' which does "
                f"not exist — evidence is stale or forged")
            continue
        actual = file_digest(suite_abs)
        if rec.get("digest") != actual:
            errs.append(
                f"{kit}/{name}: suite '{suite}' changed since the tier was set "
                f"(digest {rec.get('digest')} -> {actual}) — re-run the suite "
                f"to re-record evidence at the new suite content")
    return errs


def check_offers(idx, offers_path, root):
    """No surface offers a provider above its recorded tier; a stub is never
    offered. Returns a list of error strings."""
    errs = []
    if not os.path.isfile(offers_path):
        # No offers manifest = nothing is advertised; vacuously honest.
        return errs
    offers = load(offers_path)
    for surf in offers.get("surfaces", []):
        sname = surf.get("name", "?")
        for off in surf.get("offers", []):
            kit = off.get("kit")
            prov = off.get("provider")
            otier = off.get("tier", "stub")
            key = (kit, prov)
            if key not in idx:
                errs.append(
                    f"surface '{sname}' offers {kit}/{prov} which is not in the "
                    f"registry — cannot advertise an unknown provider")
                continue
            rtier = idx[key]
            if rtier == "stub":
                errs.append(
                    f"surface '{sname}' offers {kit}/{prov} but its recorded "
                    f"tier is 'stub' — a stub may never be offered (13.2)")
                continue
            if RANK[otier] > RANK[rtier]:
                errs.append(
                    f"surface '{sname}' offers {kit}/{prov} at '{otier}' above "
                    f"its recorded tier '{rtier}' (13.2)")
    return errs


def main():
    ap = argparse.ArgumentParser(description="advertise gate (plan 13.2/13.3)")
    ap.add_argument("--registry", default=DEF_REGISTRY)
    ap.add_argument("--evidence", default=DEF_EVIDENCE)
    ap.add_argument("--offers", default=DEF_OFFERS)
    ap.add_argument("--root", default=ROOT,
                    help="repo root for resolving evidence suite paths "
                         "(selftest points this at a temp tree)")
    args = ap.parse_args()

    errs = []
    try:
        reg = load(args.registry)
    except OSError as e:
        print(f"FAIL: cannot read registry {args.registry} — {e}", file=sys.stderr)
        return 1
    idx = provider_index(reg)

    # validate the tier vocabulary itself (typo guard)
    for (kit, name), tier in idx.items():
        if tier not in RANK:
            errs.append(f"{kit}/{name}: unknown verification tier '{tier}' "
                        f"(must be one of {TIERS})")

    errs += check_evidence(reg, idx, args.evidence, args.root)
    errs += check_offers(idx, args.offers, args.root)

    if errs:
        print("advertise gate FAILED:", file=sys.stderr)
        for e in errs:
            print("  ✗ " + e, file=sys.stderr)
        return 1
    nprov = len(idx)
    nstub = sum(1 for t in idx.values() if t == "stub")
    print(f"advertise gate OK — {nprov} provider(s), {nstub} stub (not offered), "
          f"{nprov - nstub} evidence-backed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
