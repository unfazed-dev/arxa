#!/usr/bin/env python3
"""tier1 — Tier-1 verification suites for payments + auth, plus SeedAuthBackend.

Tier 1 (plan 13.4) answers one question: *do we call the SDK correctly, and
handle its failures?* It answers it on every commit, with **no toolchain, no
credentials, no device**.

The pattern mirrors the deploy kit's `KitProcessRunner` / `ScriptedProcessRunner`:
every external SDK is invoked through a `ProcessRunner`. The real runner shells
out; the scripted runner is a fake that **asserts the command shape** and returns
canned results. The suite injects the scripted runner, so the port is proven
without the real SDK installed.

SeedAuthBackend (13.7) is the exception: it has no external process, no device,
and no accounts — so its suite tests the REAL backend, not a scripted fake. It
is implemented first because it unblocks the seeded-data story and proves the
tier-promotion path end to end.

  python3 tools/verification/tier1.py            # run all suites
  python3 tools/verification/tier1.py --promote  # run + set port-tested on pass

On `--promote`, every provider whose suite passed is set to `port-tested` in the
registry AND recorded in evidence.json — that is the ONLY path that writes a
tier (plan 13.3). Without --promote the suites run but write nothing.

Stdlib only.
"""
import argparse
import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REGISTRY = os.path.join(ROOT, "tools", "vendor", "kit_registry", "kit-registry.json")
EVIDENCE = os.path.join(HERE, "evidence.json")
SELF = os.path.join(HERE, "tier1.py")


# --------------------------------------------------------------------------- #
# Process runner port (mirrors the deploy kit's KitProcessRunner seam)
# --------------------------------------------------------------------------- #
class CompletedProc:
    def __init__(self, exit_code, stdout="", stderr=""):
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr

    @property
    def ok(self):
        return self.exit_code == 0


class RealRunner:
    """Shells out to a real SDK/CLI. Unused by the suite (Tier 1 needs no
    toolchain) — present so the port's real path is honest, not hidden."""

    def run(self, argv, env=None):
        import subprocess
        r = subprocess.run(argv, env=env, capture_output=True, text=True)
        return CompletedProc(r.returncode, r.stdout, r.stderr)


class ScriptedRunner:
    """Fake runner: preloaded with the exact commands the port must issue, in
    order. Each `run` asserts the argv matches the next expectation and returns
    its canned result. Proves the port calls the SDK correctly."""

    def __init__(self, expectations):
        # expectations: list of (argv_prefix, result)
        self._expectations = list(expectations)
        self._i = 0

    def run(self, argv, env=None):
        if self._i >= len(self._expectations):
            raise AssertionError(
                f"port issued an unexpected extra command: {argv} "
                f"(suite expected only {len(self._expectations)})")
        want_prefix, result = self._expectations[self._i]
        if list(argv[:len(want_prefix)]) != list(want_prefix):
            raise AssertionError(
                f"port called the wrong command:\n  expected prefix {want_prefix}\n"
                f"  got                  {argv[:len(want_prefix)]}")
        self._i += 1
        return result


# --------------------------------------------------------------------------- #
# Provider ports — each builds the SDK command shape and interprets the result
# --------------------------------------------------------------------------- #
class PaymentResult:
    def __init__(self, ok, provider, payment_intent_id=None, error=None):
        self.ok = ok
        self.provider = provider
        self.payment_intent_id = payment_intent_id
        self.error = error


def stripe_pay(runner, amount_minor, currency, customer_id="cust_demo"):
    """flutter_stripe SDK shape: init -> create payment intent -> present sheet.
    `amount_minor` is in the smallest currency unit (e.g. cents)."""
    runner.run(["stripe", "init",
                "--publishable-key-env", "STRIPE_PUBLISHABLE_KEY"])
    init = runner.run(["stripe", "payment-intents", "create",
                       "--amount", str(amount_minor),
                       "--currency", currency,
                       "--customer", customer_id])
    if not init.ok:
        return PaymentResult(False, "Stripe", error="intent create failed: " + init.stderr)
    intent_id = init.stdout.strip()
    sheet = runner.run(["stripe", "payment-sheet", "present"])
    if not sheet.ok:
        return PaymentResult(False, "Stripe", error="sheet present failed: " + sheet.stderr)
    return PaymentResult(True, "Stripe", payment_intent_id=intent_id)


def paypal_order(runner, amount_minor, currency):
    """PayPal Orders v2 / Braintree shape: create order -> tokenize."""
    order = runner.run(["paypal", "orders", "create",
                        "--amount", str(amount_minor),
                        "--currency", currency])
    if not order.ok:
        return PaymentResult(False, "PayPal", error="order create failed: " + order.stderr)
    order_id = order.stdout.strip()
    tok = runner.run(["paypal", "tokens", "request", "--order", order_id])
    if not tok.ok:
        return PaymentResult(False, "PayPal", error="tokenize failed: " + tok.stderr)
    return PaymentResult(True, "PayPal", payment_intent_id=order_id)


class AuthResult:
    def __init__(self, ok, provider, user_id=None, email=None, error=None):
        self.ok = ok
        self.provider = provider
        self.user_id = user_id
        self.email = email
        self.error = error


def apple_signin(runner, nonce):
    """Sign in with Apple SDK shape: request credential via the platform
    authorization provider. Tier 1 asserts the call shape + capability probe;
    Tier 2/3 add the real Apple ID (a missing capability fails SILENTLY —
    recorded in the gate README)."""
    cap = runner.run(["apple", "signin", "capability-check"])
    if not cap.ok:
        return AuthResult(False, "Apple SignIn",
                          error="capability missing (fails silently at runtime)")
    cred = runner.run(["apple", "signin", "authorize", "--nonce", nonce])
    if not cred.ok:
        return AuthResult(False, "Apple SignIn", error="authorize failed: " + cred.stderr)
    return AuthResult(True, "Apple SignIn",
                      user_id=cred.stdout.strip() or "apple_demo_user",
                      email="relay@apple.example")


def google_signin(runner, nonce):
    """Google Sign-In SDK shape: initialize -> authenticate."""
    runner.run(["google", "signin", "initialize",
                "--server-client-id-env", "GOOGLE_SERVER_CLIENT_ID"])
    auth = runner.run(["google", "signin", "authenticate", "--nonce", nonce])
    if not auth.ok:
        return AuthResult(False, "Google SignIn", error="authenticate failed: " + auth.stderr)
    return AuthResult(True, "Google SignIn",
                      user_id=auth.stdout.strip() or "google_demo_user",
                      email="demo@google.example")


# --------------------------------------------------------------------------- #
# SeedAuthBackend (13.7) — the REAL backend, no scripted fake
# --------------------------------------------------------------------------- #
class SeedAuthBackend:
    """In-memory seeded auth backend. No device, no external process, no real
    account. Powers the seeded-data story the product promises (the showcase
    depends on it). The one provider whose Tier-1 suite tests the real thing.

    A backend, not a port: it does not shell out, so there is no runner to fake.
    """

    def __init__(self, seed=None):
        # password stored plaintext only because this is a deterministic seed
        # for a local showcase — never a real credential store.
        self._users = dict(seed or _DEFAULT_SEED)
        self._sessions = {}   # user_id -> email

    def sign_in(self, email, password):
        for uid, rec in self._users.items():
            if rec["email"] == email:
                if rec["password"] == password:
                    self._sessions[uid] = email
                    return AuthResult(True, "SeedAuthBackend",
                                      user_id=uid, email=email)
                return AuthResult(False, "SeedAuthBackend", error="wrong password")
        return AuthResult(False, "SeedAuthBackend", error="unknown user")

    def current_user(self, uid):
        email = self._sessions.get(uid)
        if email is None:
            return None
        return {"user_id": uid, "email": email}

    def sign_out(self, uid):
        self._sessions.pop(uid, None)

    def seed_users(self):
        return {uid: {"email": r["email"]} for uid, r in self._users.items()}


_DEFAULT_SEED = {
    "seed_alice": {"email": "alice@showcase.app", "password": "seed-alice"},
    "seed_bob": {"email": "bob@showcase.app", "password": "seed-bob"},
}


# --------------------------------------------------------------------------- #
# Suites — assert-based, no framework (one runnable self-check)
# --------------------------------------------------------------------------- #
def _expect_scripted(expectations, action):
    r = ScriptedRunner(expectations)
    return r, action(r)


def test_stripe_port():
    r, res = _expect_scripted([
        (["stripe", "init"], CompletedProc(0)),
        (["stripe", "payment-intents", "create"], CompletedProc(0, "pi_demo_123")),
        (["stripe", "payment-sheet", "present"], CompletedProc(0, "succeeded")),
    ], lambda run: stripe_pay(run, 1999, "usd"))
    assert r._i == 3, "stripe port did not issue all 3 commands"
    assert res.ok and res.payment_intent_id == "pi_demo_123", res.__dict__
    # failure handling: the sheet present step fails
    r, res = _expect_scripted([
        (["stripe", "init"], CompletedProc(0)),
        (["stripe", "payment-intents", "create"], CompletedProc(0, "pi_demo_456")),
        (["stripe", "payment-sheet", "present"], CompletedProc(1, stderr="user cancelled")),
    ], lambda run: stripe_pay(run, 1999, "usd"))
    assert not res.ok and "user cancelled" in res.error, res.__dict__


def test_paypal_port():
    r, res = _expect_scripted([
        (["paypal", "orders", "create"], CompletedProc(0, "order_demo_1")),
        (["paypal", "tokens", "request"], CompletedProc(0, "tok_demo_1")),
    ], lambda run: paypal_order(run, 4999, "eur"))
    assert res.ok and res.payment_intent_id == "order_demo_1", res.__dict__
    r, res = _expect_scripted([
        (["paypal", "orders", "create"], CompletedProc(1, stderr="network")),
    ], lambda run: paypal_order(run, 4999, "eur"))
    assert not res.ok and "network" in res.error, res.__dict__


def test_apple_signin_port():
    r, res = _expect_scripted([
        (["apple", "signin", "capability-check"], CompletedProc(0)),
        (["apple", "signin", "authorize"], CompletedProc(0, "apple_uid")),
    ], lambda run: apple_signin(run, "nonce-abc"))
    assert res.ok and res.user_id == "apple_uid", res.__dict__
    # the silent capability failure (Tier 1 must assert it, not just the happy path)
    r, res = _expect_scripted([
        (["apple", "signin", "capability-check"], CompletedProc(1)),
    ], lambda run: apple_signin(run, "nonce-abc"))
    assert not res.ok and "capability" in res.error, res.__dict__


def test_google_signin_port():
    r, res = _expect_scripted([
        (["google", "signin", "initialize"], CompletedProc(0)),
        (["google", "signin", "authenticate"], CompletedProc(0, "google_uid")),
    ], lambda run: google_signin(run, "nonce-xyz"))
    assert res.ok and res.user_id == "google_uid", res.__dict__
    r, res = _expect_scripted([
        (["google", "signin", "initialize"], CompletedProc(0)),
        (["google", "signin", "authenticate"], CompletedProc(1, stderr="cancelled")),
    ], lambda run: google_signin(run, "nonce-xyz"))
    assert not res.ok and "cancelled" in res.error, res.__dict__


def test_seed_auth():
    backend = SeedAuthBackend()
    users = backend.seed_users()
    assert users["seed_alice"]["email"] == "alice@showcase.app", users
    # valid sign-in
    res = backend.sign_in("alice@showcase.app", "seed-alice")
    assert res.ok and res.user_id == "seed_alice", res.__dict__
    assert backend.current_user("seed_alice")["email"] == "alice@showcase.app"
    # wrong password
    res = backend.sign_in("alice@showcase.app", "nope")
    assert not res.ok and res.error == "wrong password", res.__dict__
    # unknown user
    res = backend.sign_in("nobody@showcase.app", "x")
    assert not res.ok and res.error == "unknown user", res.__dict__
    # sign out clears the session
    backend.sign_out("seed_alice")
    assert backend.current_user("seed_alice") is None


SUITES = [
    ("payments", "Stripe", test_stripe_port),
    ("payments", "PayPal", test_paypal_port),
    ("auth", "Apple SignIn", test_apple_signin_port),
    ("auth", "Google SignIn", test_google_signin_port),
    ("auth", "SeedAuthBackend", test_seed_auth),
]


# --------------------------------------------------------------------------- #
# Promotion — the ONLY path that writes a tier (plan 13.3)
# --------------------------------------------------------------------------- #
def _file_digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def promote(passed):
    """Set verification='port-tested' for each passed provider in the registry,
    and record evidence (suite path + content digest + timestamp) in the ledger.
    Idempotent: re-running with the same suite content leaves both files stable."""
    with open(REGISTRY, encoding="utf-8") as f:
        reg = json.load(f)
    rel_suite = os.path.relpath(SELF, ROOT)
    digest = _file_digest(SELF)
    ran_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    bumped = 0
    for kit in reg["kits"]:
        for p in kit.get("providers", []):
            if (kit["dir"], p["name"]) in passed:
                if p["verification"] != "port-tested":
                    p["verification"] = "port-tested"
                    bumped += 1
    with open(REGISTRY, "w", encoding="utf-8") as f:
        f.write(json.dumps(reg, indent=2, ensure_ascii=False) + "\n")

    ledger = {}
    if os.path.isfile(EVIDENCE):
        with open(EVIDENCE, encoding="utf-8") as f:
            ledger = json.load(f).get("ledger", {})
    for (kit_dir, name) in passed:
        key = f"{kit_dir}/{name}"
        prev = ledger.get(key, {})
        # Preserve ran_at when nothing material changed, so re-running a stable
        # suite does not churn the committed evidence (byte-stable no-op).
        same = prev.get("tier") == "port-tested" and prev.get("digest") == digest
        ledger[key] = {
            "tier": "port-tested",
            "suite": rel_suite,
            "digest": digest,
            "ran_at": prev.get("ran_at") if same else ran_at,
        }
    with open(EVIDENCE, "w", encoding="utf-8") as f:
        f.write(json.dumps({"ledger": ledger}, indent=2, ensure_ascii=False) + "\n")
    return bumped


def main():
    ap = argparse.ArgumentParser(description="Tier-1 verification suites (plan 13.4/13.7)")
    ap.add_argument("--promote", action="store_true",
                    help="on a green run, set port-tested + record evidence "
                         "(the only path that writes a tier, 13.3)")
    args = ap.parse_args()

    passed, failed = set(), []
    for kit_dir, name, fn in SUITES:
        try:
            fn()
            passed.add((kit_dir, name))
            print(f"  PASS  {kit_dir}/{name}")
        except Exception as e:
            failed.append(f"{kit_dir}/{name}: {type(e).__name__}: {e}")
            print(f"  FAIL  {kit_dir}/{name}: {e}", file=sys.stderr)

    print(f"tier1: {len(passed)} passed, {len(failed)} failed")
    if failed:
        for f in failed:
            print("  ✗ " + f, file=sys.stderr)
        return 1
    if args.promote:
        bumped = promote(passed)
        print(f"promote: {len(passed)} provider(s) at port-tested "
              f"({bumped} registry field(s) changed); evidence recorded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
