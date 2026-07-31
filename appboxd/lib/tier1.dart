// tier1 — Tier-1 verification suites for payments + auth, plus SeedAuthBackend.
//
// Dart port of archives/tooling-pre-dart/tools/verification/tier1.py.
//
// Tier 1 (plan 13.4) answers one question: *do we call the SDK correctly, and
// handle its failures?* It answers it on every commit, with **no toolchain, no
// credentials, no device**.
//
// The pattern mirrors the deploy kit's `KitProcessRunner` /
// `ScriptedProcessRunner`: every external SDK is invoked through a
// `ProcessRunner`. The real runner shells out; the scripted runner is a fake
// that **asserts the command shape** and returns canned results. The suite
// injects the scripted runner, so the port is proven without the real SDK
// installed.
//
// SeedAuthBackend (13.7) is the exception: it has no external process, no
// device, and no accounts — so its suite tests the REAL backend, not a
// scripted fake. It is implemented first because it unblocks the seeded-data
// story and proves the tier-promotion path end to end.
//
// The Python original is self-contained (stdlib only) and does NOT import from
// the auth/payments kits — the per-provider call shapes live in this file as
// the spec under test. This Dart port keeps that property: no kit path
// dependencies, pure Dart. [runTier1Suites] is the bundled self-check the CLI
// gate runs (`appbox gate tier1`).

import 'dart:io';

// --------------------------------------------------------------------------- //
// Process runner port (mirrors the deploy kit's KitProcessRunner seam)
// --------------------------------------------------------------------------- //

/// Result of one SDK/CLI invocation — port of tier1.py's `CompletedProc`.
class CompletedProc {
  final int exitCode;
  final String stdout;
  final String stderr;

  const CompletedProc(this.exitCode, {this.stdout = '', this.stderr = ''});

  bool get ok => exitCode == 0;

  @override
  String toString() => 'CompletedProc(exit=$exitCode, stdout=$stdout, stderr=$stderr)';
}

/// Seam every SDK call routes through — port of the `ProcessRunner` protocol.
abstract class ProcessRunner {
  CompletedProc run(List<String> argv, {Map<String, String>? env});
}

/// Shells out to a real SDK/CLI. Unused by the suite (Tier 1 needs no
/// toolchain) — present so the port's real path is honest, not hidden.
class RealRunner implements ProcessRunner {
  const RealRunner();

  @override
  CompletedProc run(List<String> argv, {Map<String, String>? env}) {
    final r = Process.runSync(
      argv.first,
      argv.sublist(1),
      environment: env,
      runInShell: false,
    );
    return CompletedProc(
      r.exitCode,
      stdout: r.stdout as String,
      stderr: r.stderr as String,
    );
  }
}

/// Fake runner: preloaded with the exact commands the port must issue, in
/// order. Each [run] asserts the argv matches the next expectation and returns
/// its canned result. Proves the port calls the SDK correctly.
class ScriptedRunner implements ProcessRunner {
  final List<(List<String>, CompletedProc)> _expectations;
  var _i = 0;

  ScriptedRunner(this._expectations);

  /// Number of expectations consumed so far (mirrors the Python `_i` field).
  int get callCount => _i;

  @override
  CompletedProc run(List<String> argv, {Map<String, String>? env}) {
    if (_i >= _expectations.length) {
      throw StateError('port issued an unexpected extra command: $argv '
          '(suite expected only ${_expectations.length})');
    }
    final (wantPrefix, result) = _expectations[_i];
    if (!_startsWith(argv, wantPrefix)) {
      final got = argv.length < wantPrefix.length ? argv : argv.sublist(0, wantPrefix.length);
      throw StateError('port called the wrong command:\n'
          '  expected prefix $wantPrefix\n'
          '  got                  $got');
    }
    _i++;
    return result;
  }
}

bool _startsWith(List<String> a, List<String> prefix) {
  if (a.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (a[i] != prefix[i]) return false;
  }
  return true;
}

// --------------------------------------------------------------------------- //
// Provider ports — each builds the SDK command shape and interprets the result
// --------------------------------------------------------------------------- //

class PaymentResult {
  final bool ok;
  final String provider;
  final String? paymentIntentId;
  final String? error;

  const PaymentResult({
    required this.ok,
    required this.provider,
    this.paymentIntentId,
    this.error,
  });

  @override
  String toString() =>
      'PaymentResult(ok=$ok, provider=$provider, paymentIntentId=$paymentIntentId, error=$error)';
}

/// flutter_stripe SDK shape: init -> create payment intent -> present sheet.
/// `amountMinor` is in the smallest currency unit (e.g. cents).
PaymentResult stripePay(
  ProcessRunner runner,
  int amountMinor,
  String currency, {
  String customerId = 'cust_demo',
}) {
  runner.run(['stripe', 'init', '--publishable-key-env', 'STRIPE_PUBLISHABLE_KEY']);
  final init = runner.run([
    'stripe',
    'payment-intents',
    'create',
    '--amount',
    '$amountMinor',
    '--currency',
    currency,
    '--customer',
    customerId,
  ]);
  if (!init.ok) {
    return PaymentResult(ok: false, provider: 'Stripe', error: 'intent create failed: ${init.stderr}');
  }
  final intentId = init.stdout.trim();
  final sheet = runner.run(['stripe', 'payment-sheet', 'present']);
  if (!sheet.ok) {
    return PaymentResult(ok: false, provider: 'Stripe', error: 'sheet present failed: ${sheet.stderr}');
  }
  return PaymentResult(ok: true, provider: 'Stripe', paymentIntentId: intentId);
}

/// PayPal Orders v2 / Braintree shape: create order -> tokenize.
PaymentResult paypalOrder(ProcessRunner runner, int amountMinor, String currency) {
  final order = runner.run([
    'paypal',
    'orders',
    'create',
    '--amount',
    '$amountMinor',
    '--currency',
    currency,
  ]);
  if (!order.ok) {
    return PaymentResult(ok: false, provider: 'PayPal', error: 'order create failed: ${order.stderr}');
  }
  final orderId = order.stdout.trim();
  final tok = runner.run(['paypal', 'tokens', 'request', '--order', orderId]);
  if (!tok.ok) {
    return PaymentResult(ok: false, provider: 'PayPal', error: 'tokenize failed: ${tok.stderr}');
  }
  return PaymentResult(ok: true, provider: 'PayPal', paymentIntentId: orderId);
}

class AuthResult {
  final bool ok;
  final String provider;
  final String? userId;
  final String? email;
  final String? token;
  final String? error;

  const AuthResult({
    required this.ok,
    required this.provider,
    this.userId,
    this.email,
    this.token,
    this.error,
  });

  @override
  String toString() =>
      'AuthResult(ok=$ok, provider=$provider, userId=$userId, email=$email, token=$token, error=$error)';
}

/// Sign in with Apple SDK shape: request credential via the platform
/// authorization provider. Tier 1 asserts the call shape + capability probe;
/// Tier 2/3 add the real Apple ID (a missing capability fails SILENTLY —
/// recorded in the gate README).
AuthResult appleSignIn(ProcessRunner runner, String nonce) {
  final cap = runner.run(['apple', 'signin', 'capability-check']);
  if (!cap.ok) {
    return AuthResult(
      ok: false,
      provider: 'Apple SignIn',
      error: 'capability missing (fails silently at runtime)',
    );
  }
  final cred = runner.run(['apple', 'signin', 'authorize', '--nonce', nonce]);
  if (!cred.ok) {
    return AuthResult(ok: false, provider: 'Apple SignIn', error: 'authorize failed: ${cred.stderr}');
  }
  return AuthResult(
    ok: true,
    provider: 'Apple SignIn',
    userId: cred.stdout.trim().isEmpty ? 'apple_demo_user' : cred.stdout.trim(),
    email: 'relay@apple.example',
  );
}

/// Google Sign-In SDK shape: initialize -> authenticate.
AuthResult googleSignIn(ProcessRunner runner, String nonce) {
  runner.run(['google', 'signin', 'initialize', '--server-client-id-env', 'GOOGLE_SERVER_CLIENT_ID']);
  final auth = runner.run(['google', 'signin', 'authenticate', '--nonce', nonce]);
  if (!auth.ok) {
    return AuthResult(ok: false, provider: 'Google SignIn', error: 'authenticate failed: ${auth.stderr}');
  }
  return AuthResult(
    ok: true,
    provider: 'Google SignIn',
    userId: auth.stdout.trim().isEmpty ? 'google_demo_user' : auth.stdout.trim(),
    email: 'demo@google.example',
  );
}

// --------------------------------------------------------------------------- //
// SeedAuthBackend (13.7) — the REAL backend, no scripted fake
// --------------------------------------------------------------------------- //

class _SeededUser {
  final String email;
  final String password;
  const _SeededUser(this.email, this.password);
}

class _Session {
  final String userId;
  final String email;
  final String token;
  const _Session(this.userId, this.email, this.token);
}

/// Default seed — deterministic local showcase credentials. Never a real
/// credential store.
const _defaultSeed = <String, _SeededUser>{
  'seed_alice': _SeededUser('alice@showcase.app', 'seed-alice'),
  'seed_bob': _SeededUser('bob@showcase.app', 'seed-bob'),
};

/// In-memory seeded auth backend. No device, no external process, no real
/// account. Powers the seeded-data story the product promises (the showcase
/// depends on it). The one provider whose Tier-1 suite tests the real thing.
///
/// A backend, not a port: it does not shell out, so there is no runner to fake.
/// Tokens are minted monotonically (`tok_1`, `tok_2`, …) so refresh rotation
/// is observable and deterministic.
class SeedAuthBackend {
  final Map<String, _SeededUser> _users = {};
  final Map<String, _Session> _sessionsByUid = {}; // userId -> session
  final Map<String, _Session> _sessionsByToken = {}; // token -> session
  var _tokenSeq = 0;
  var _uidSeq = 0;

  SeedAuthBackend() {
    _users.addAll(_defaultSeed);
  }

  /// Sign in an existing seed user. On success mints a fresh session token.
  AuthResult signIn(String email, String password) {
    String? uid;
    _SeededUser? rec;
    for (final entry in _users.entries) {
      if (entry.value.email == email) {
        uid = entry.key;
        rec = entry.value;
        break;
      }
    }
    if (rec == null) {
      return AuthResult(ok: false, provider: 'SeedAuthBackend', error: 'unknown user');
    }
    if (rec.password != password) {
      return AuthResult(ok: false, provider: 'SeedAuthBackend', error: 'wrong password');
    }
    final session = _openSession(uid!, email);
    return AuthResult(
      ok: true,
      provider: 'SeedAuthBackend',
      userId: uid,
      email: email,
      token: session.token,
    );
  }

  /// Register a brand-new user and open a session for them. Fails if the email
  /// is already taken (mirrors a real signup endpoint's conflict).
  AuthResult signUp(String email, String password) {
    for (final rec in _users.values) {
      if (rec.email == email) {
        return AuthResult(ok: false, provider: 'SeedAuthBackend', error: 'user already exists');
      }
    }
    final uid = 'user_${++_uidSeq}';
    _users[uid] = _SeededUser(email, password);
    final session = _openSession(uid, email);
    return AuthResult(
      ok: true,
      provider: 'SeedAuthBackend',
      userId: uid,
      email: email,
      token: session.token,
    );
  }

  /// Rotate a session token. The old token is invalidated; a fresh one is
  /// returned bound to the same user. Unknown/expired tokens fail.
  AuthResult refreshToken(String token) {
    final prev = _sessionsByToken.remove(token);
    if (prev == null) {
      return AuthResult(ok: false, provider: 'SeedAuthBackend', error: 'invalid or expired token');
    }
    final session = _openSession(prev.userId, prev.email);
    return AuthResult(
      ok: true,
      provider: 'SeedAuthBackend',
      userId: session.userId,
      email: session.email,
      token: session.token,
    );
  }

  /// Currently signed-in user for `uid`, or null if no live session.
  Map<String, String>? currentUser(String uid) {
    final s = _sessionsByUid[uid];
    if (s == null) return null;
    return {'user_id': s.userId, 'email': s.email};
  }

  /// End the session for `uid` (idempotent).
  void signOut(String uid) {
    final s = _sessionsByUid.remove(uid);
    if (s != null) _sessionsByToken.remove(s.token);
  }

  /// Read-only view of the seeded users (no passwords).
  Map<String, Map<String, String>> seedUsers() {
    return {
      for (final e in _users.entries) e.key: {'email': e.value.email},
    };
  }

  _Session _openSession(String uid, String email) {
    final token = 'tok_${++_tokenSeq}';
    final session = _Session(uid, email, token);
    _sessionsByUid[uid] = session;
    _sessionsByToken[token] = session;
    return session;
  }
}

// --------------------------------------------------------------------------- //
// Suites — assert-based, runnable as a bundled self-check ([runTier1Suites])
// --------------------------------------------------------------------------- //

void _check(bool cond, String msg) {
  if (!cond) throw StateError(msg);
}

/// Run [action] against a freshly loaded [ScriptedRunner], returning both so
/// the caller can assert how many commands were consumed.
(ScriptedRunner, R) _scripted<R>(
  List<(List<String>, CompletedProc)> expectations,
  R Function(ProcessRunner) action,
) {
  final runner = ScriptedRunner(expectations);
  return (runner, action(runner));
}

void _suiteStripePort() {
  var (r, res) = _scripted(
    [
      (['stripe', 'init'], const CompletedProc(0)),
      (['stripe', 'payment-intents', 'create'], const CompletedProc(0, stdout: 'pi_demo_123')),
      (['stripe', 'payment-sheet', 'present'], const CompletedProc(0, stdout: 'succeeded')),
    ],
    (run) => stripePay(run, 1999, 'usd'),
  );
  _check(r.callCount == 3, 'stripe port did not issue all 3 commands');
  _check(res.ok && res.paymentIntentId == 'pi_demo_123', 'stripe: $res');

  // failure handling: the sheet present step fails
  (r, res) = _scripted(
    [
      (['stripe', 'init'], const CompletedProc(0)),
      (['stripe', 'payment-intents', 'create'], const CompletedProc(0, stdout: 'pi_demo_456')),
      (['stripe', 'payment-sheet', 'present'], const CompletedProc(1, stderr: 'user cancelled')),
    ],
    (run) => stripePay(run, 1999, 'usd'),
  );
  _check(!res.ok && res.error!.contains('user cancelled'), 'stripe failure: $res');
}

void _suitePaypalPort() {
  var (_, res) = _scripted(
    [
      (['paypal', 'orders', 'create'], const CompletedProc(0, stdout: 'order_demo_1')),
      (['paypal', 'tokens', 'request'], const CompletedProc(0, stdout: 'tok_demo_1')),
    ],
    (run) => paypalOrder(run, 4999, 'eur'),
  );
  _check(res.ok && res.paymentIntentId == 'order_demo_1', 'paypal: $res');

  (_, res) = _scripted(
    [
      (['paypal', 'orders', 'create'], const CompletedProc(1, stderr: 'network')),
    ],
    (run) => paypalOrder(run, 4999, 'eur'),
  );
  _check(!res.ok && res.error!.contains('network'), 'paypal failure: $res');
}

void _suiteAppleSigninPort() {
  var (_, res) = _scripted(
    [
      (['apple', 'signin', 'capability-check'], const CompletedProc(0)),
      (['apple', 'signin', 'authorize'], const CompletedProc(0, stdout: 'apple_uid')),
    ],
    (run) => appleSignIn(run, 'nonce-abc'),
  );
  _check(res.ok && res.userId == 'apple_uid', 'apple: $res');

  // the silent capability failure (Tier 1 must assert it, not just the happy path)
  (_, res) = _scripted(
    [
      (['apple', 'signin', 'capability-check'], const CompletedProc(1)),
    ],
    (run) => appleSignIn(run, 'nonce-abc'),
  );
  _check(!res.ok && res.error!.contains('capability'), 'apple capability failure: $res');
}

void _suiteGoogleSigninPort() {
  var (_, res) = _scripted(
    [
      (['google', 'signin', 'initialize'], const CompletedProc(0)),
      (['google', 'signin', 'authenticate'], const CompletedProc(0, stdout: 'google_uid')),
    ],
    (run) => googleSignIn(run, 'nonce-xyz'),
  );
  _check(res.ok && res.userId == 'google_uid', 'google: $res');

  (_, res) = _scripted(
    [
      (['google', 'signin', 'initialize'], const CompletedProc(0)),
      (['google', 'signin', 'authenticate'], const CompletedProc(1, stderr: 'cancelled')),
    ],
    (run) => googleSignIn(run, 'nonce-xyz'),
  );
  _check(!res.ok && res.error!.contains('cancelled'), 'google failure: $res');
}

void _suiteSeedAuth() {
  final backend = SeedAuthBackend();
  final users = backend.seedUsers();
  _check(users['seed_alice']?['email'] == 'alice@showcase.app', 'seedUsers: $users');

  // valid sign-in → success + token
  var res = backend.signIn('alice@showcase.app', 'seed-alice');
  _check(res.ok && res.userId == 'seed_alice' && res.token != null, 'signIn ok: $res');
  _check(backend.currentUser('seed_alice')?['email'] == 'alice@showcase.app', 'currentUser');

  // wrong password
  res = backend.signIn('alice@showcase.app', 'nope');
  _check(!res.ok && res.error == 'wrong password', 'wrong password: $res');

  // unknown user
  res = backend.signIn('nobody@showcase.app', 'x');
  _check(!res.ok && res.error == 'unknown user', 'unknown user: $res');

  // sign out clears the session
  backend.signOut('seed_alice');
  _check(backend.currentUser('seed_alice') == null, 'signOut cleared session');

  // sign-up creates a new user
  res = backend.signUp('carol@showcase.app', 'pw-carol');
  _check(res.ok && res.token != null, 'signUp: $res');
  final newUid = res.userId;
  _check(newUid != null && backend.currentUser(newUid)?['email'] == 'carol@showcase.app',
      'signUp session');
  // duplicate signup is rejected
  _check(!backend.signUp('carol@showcase.app', 'x').ok, 'duplicate signUp rejected');
  // the new user can sign in independently
  _check(backend.signIn('carol@showcase.app', 'pw-carol').ok, 'new user can signIn');

  // token refresh: valid token rotates, old token dies, bogus fails
  final auth = backend.signIn('bob@showcase.app', 'seed-bob');
  _check(auth.ok && auth.token != null, 'bob signIn for refresh: $auth');
  final refreshed = backend.refreshToken(auth.token!);
  _check(refreshed.ok && refreshed.token != null && refreshed.token != auth.token,
      'refresh rotated: $refreshed');
  _check(!backend.refreshToken(auth.token!).ok, 'old token dead after refresh');
  _check(!backend.refreshToken('bogus').ok, 'bogus token rejected');
}

/// One provider's Tier-1 suite: its `(kitDir, name)` key plus the entrypoint.
typedef Tier1Suite = (String kitDir, String name, void Function() body);

/// Every Tier-1 suite, in registry order (matches tier1.py's SUITES).
final List<Tier1Suite> tier1Suites = <Tier1Suite>[
  ('payments', 'Stripe', _suiteStripePort),
  ('payments', 'PayPal', _suitePaypalPort),
  ('auth', 'Apple SignIn', _suiteAppleSigninPort),
  ('auth', 'Google SignIn', _suiteGoogleSigninPort),
  ('auth', 'SeedAuthBackend', _suiteSeedAuth),
];

/// Outcome of running every Tier-1 suite.
class Tier1SuiteResult {
  final List<String> passed; // "kitDir/name"
  final List<String> failed; // "kitDir/name: <error>"

  Tier1SuiteResult(this.passed, this.failed);

  bool get allPassed => failed.isEmpty;
}

/// Run every Tier-1 suite, catching failures per provider so one break does
/// not mask the rest. Mirrors tier1.py's `main()` loop (without `--promote` —
/// tier promotion stays a registry concern, out of scope for the self-check).
Tier1SuiteResult runTier1Suites() {
  final passed = <String>[];
  final failed = <String>[];
  for (final (kitDir, name, body) in tier1Suites) {
    try {
      body();
      passed.add('$kitDir/$name');
    } catch (e) {
      failed.add('$kitDir/$name: $e');
    }
  }
  return Tier1SuiteResult(passed, failed);
}
