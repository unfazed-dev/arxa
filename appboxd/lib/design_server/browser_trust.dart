// The browser-trust guard for the design server.
//
// WHY THIS EXISTS. `appbox design serve` binds loopback and has always treated
// that as the security boundary. It is not one. Two attacks reach a
// loopback-bound HTTP server from a page the user merely visits:
//
//   1. DNS REBINDING. evil.example resolves to its own IP for the first
//      request, then re-resolves to 127.0.0.1. The browser now believes
//      http://evil.example IS the local server, so the same-origin policy
//      stops protecting it and the attacker's script can read every response.
//      The defense is a Host-header allowlist — the attacker controls the
//      name in `Host`, and it is never one of ours. This is not theoretical:
//      CVE-2025-66414 (Dec 2025) was exactly this against the MCP TypeScript
//      SDK's localhost server, fixed in @modelcontextprotocol/sdk 1.24.0 by
//      adding Host validation.
//
//   2. CSRF. `POST /__project_write` decodes its body as JSON regardless of
//      content type, so a cross-origin fetch with `Content-Type: text/plain`
//      is a CORS "simple request" — no preflight, the browser sends it, and
//      the write lands. The attacker cannot READ the reply, but it does not
//      need to: the write is the payload, and the file it writes into the
//      project is later imported by the worker. Any page in any tab could do
//      this. The defense is fetch-metadata + Origin validation.
//
// WHAT IT DOES NOT DO. There is no token, and requests carrying NEITHER
// `Sec-Fetch-Site` NOR `Origin` are allowed through. That is a decision, not
// an oversight — do not "fix" it by adding a token:
//
//   * Both headers are FORBIDDEN header names: page JavaScript cannot set or
//     remove them, and every browser since 2023 sends `Sec-Fetch-Site` on
//     every request. So "neither header" means "not a browser", and a browser
//     is the entire threat model here — the socket is loopback, so a remote
//     attacker has no path to it at all.
//   * The callers in that category are the appbox CLI, the probe suite, lens
//     and curl. A token would break all of them to defend against local code
//     that, by definition, already has the user's filesystem.
//
// OWASP's CSRF cheat sheet says not to fail open on absent fetch metadata;
// that guidance is written for a public server, where "no browser headers"
// means a scripted attacker. On loopback it means "the tool that ships with
// this server". The distinction is the whole reason this comment is here.
library;

/// The result of [BrowserTrust.check] for one request.
class TrustVerdict {
  const TrustVerdict._(this.status, this.reason, this.corsOrigin);

  /// The request may proceed. [corsOrigin] is the value to echo back in
  /// `Access-Control-Allow-Origin` — non-null only for a cross-origin request
  /// from an allowlisted origin, never `*`.
  const TrustVerdict.allow({String? corsOrigin}) : this._(0, null, corsOrigin);

  /// The request is refused with HTTP [status] ([reason] is for the serve log
  /// and the plain-text body; it never echoes anything the caller sent that
  /// could re-enter a page).
  const TrustVerdict.deny(int status, String reason)
      : this._(status, reason, null);

  /// 0 when allowed, otherwise the HTTP status to answer with.
  final int status;
  final String? reason;
  final String? corsOrigin;

  bool get allowed => status == 0;
}

/// Methods that cannot change server state, so they carry no CSRF risk on
/// their own. HEAD and OPTIONS included for completeness; the server does not
/// route them today.
const _safeMethods = {'GET', 'HEAD', 'OPTIONS'};

/// Loopback names, in the forms a `Host` header actually arrives in.
///
/// `*.localhost` is in here on purpose: RFC 6761 reserves the whole TLD for
/// loopback and every OS resolver and browser honours it natively, so an
/// attacker cannot be handed one — reaching `foo.localhost` means reaching
/// this machine.
bool _isLoopbackName(String h) =>
    h == 'localhost' ||
    h == '::1' ||
    h == '0:0:0:0:0:0:0:1' ||
    h.endsWith('.localhost') ||
    // The whole 127.0.0.0/8 block, not just 127.0.0.1.
    RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(h);

/// Lowercase the name and strip the port and any IPv6 brackets.
///
/// The port is deliberately dropped rather than compared. A `Host` of
/// `localhost` and one of `localhost:4319` name the same server, and an
/// allowlist that treats them as different is the mlflow bug (issue #22095):
/// valid clients rejected over a header form, which then gets "fixed" by
/// disabling the check. The port cannot be forged into anything useful anyway
/// — the request already arrived on our socket. Rebinding is about the NAME.
String normalizeHost(String raw) {
  var h = raw.trim().toLowerCase();
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    if (end > 0) return h.substring(1, end);
  }
  // An unbracketed IPv6 literal (`::1`) has more than one colon and no port —
  // it must survive whole. Only a single trailing `:digits` is a port.
  if (':'.allMatches(h).length > 1) return h;
  final colon = h.lastIndexOf(':');
  if (colon > 0 && int.tryParse(h.substring(colon + 1)) != null) {
    h = h.substring(0, colon);
  }
  return h;
}

/// Scheme + host + port, lowercased, with the default port left implicit —
/// the serialization the browser puts in `Origin`.
String normalizeOrigin(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null || u.scheme.isEmpty || u.host.isEmpty) {
    return raw.trim().toLowerCase();
  }
  final port = u.hasPort ? ':${u.port}' : '';
  final host = u.host.contains(':') ? '[${u.host}]' : u.host;
  return '${u.scheme.toLowerCase()}://${host.toLowerCase()}$port';
}

bool _isWildcardBind(String h) =>
    h == '0.0.0.0' || h == '::' || h == '*' || h.isEmpty;

/// Decides, per request, whether a browser is allowed to reach this server.
class BrowserTrust {
  BrowserTrust({
    required String boundHost,
    required this.port,
    Iterable<String> trustedHosts = const [],
    Iterable<String> trustedOrigins = const [],
  })  : wildcardBind = _isWildcardBind(boundHost),
        _extraHosts = {for (final h in trustedHosts) normalizeHost(h)},
        _boundHost = normalizeHost(boundHost),
        _extraOrigins = {for (final o in trustedOrigins) normalizeOrigin(o)};

  final int port;

  /// True when the operator explicitly bound a wildcard address. There is then
  /// no knowable set of names this server answers to — it was published on
  /// every interface on purpose — so the Host allowlist stands down. Callers
  /// should say so out loud at boot; see [wildcardWarning].
  final bool wildcardBind;

  final String _boundHost;
  final Set<String> _extraHosts;
  final Set<String> _extraOrigins;

  static const wildcardWarning =
      '[design-server] bound to a wildcard address: Host-header checking is '
      'off (no knowable names) and this server is reachable from the network. '
      'Pass --trusted-host to re-enable it.';

  /// The names a `Host` header may carry: loopback, whatever we were bound to,
  /// and anything `--trusted-host` added.
  bool hostAllowed(String? hostHeader) {
    if (wildcardBind) return true;
    // HTTP/1.1 requires Host and every browser sends it. Absent means an
    // HTTP/1.0 or hand-rolled client, which is not the rebinding attacker —
    // the attack REQUIRES their own name in this header.
    if (hostHeader == null || hostHeader.trim().isEmpty) return true;
    final h = normalizeHost(hostHeader);
    return _isLoopbackName(h) || h == _boundHost || _extraHosts.contains(h);
  }

  /// Origins allowed to make cross-origin requests: this very server under any
  /// of its loopback aliases, plus anything `--trusted-origin` added.
  ///
  /// Note the port IS compared here, unlike [hostAllowed]. `http://localhost`
  /// at our port is us; at port 8888 it is somebody else's dev server, and
  /// treating theirs as ours would make any local tool that renders untrusted
  /// HTML a springboard into this one.
  bool originAllowed(String origin) {
    final o = normalizeOrigin(origin);
    if (_extraOrigins.contains(o)) return true;
    final u = Uri.tryParse(o);
    if (u == null || u.scheme != 'http') return false;
    return u.hasPort && u.port == port && _isLoopbackName(u.host.toLowerCase());
  }

  /// The `Content-Security-Policy: frame-ancestors` value — who may put this
  /// server in an `<iframe>`.
  ///
  /// This exists because `dart:io` sets `X-Frame-Options: SAMEORIGIN` on every
  /// response by ITS OWN default (`HttpServer.defaultResponseHeaders`), which
  /// no grep of this repo will ever find. That default refuses the arxa design
  /// panel and the `gen_ui` RungLadder outright: both frame us from
  /// `arxa.studio.localhost`, a different origin. X-Frame-Options has no
  /// allowlist form — `ALLOW-FROM` is obsolete and modern browsers ignore the
  /// whole header when they see it (MDN) — so the header must be REMOVED and
  /// this directive must take over in the same change. Removing it alone would
  /// let any page on the web frame this server.
  ///
  /// The allowlist mirrors [originAllowed] deliberately: one operator lever
  /// (`~/.appbox/trusted-origins` + `--trusted-origin`) governs both who may
  /// call us and who may frame us. The three loopback spellings are listed
  /// explicitly because a directive cannot express "any `*.localhost` name at
  /// our port" the way [originAllowed] can; `'self'` covers whatever alias the
  /// document was actually loaded under, which is the case that matters.
  String get frameAncestors => [
        "'self'",
        'http://127.0.0.1:$port',
        'http://localhost:$port',
        'http://[::1]:$port',
        ..._extraOrigins,
      ].join(' ');

  /// True when this request must clear the origin check.
  ///
  /// Every state-changing method, plus every `/__*` endpoint whatever the
  /// method — the resource-isolation policy OWASP's XS-Leaks sheet describes.
  /// `GET /__projects` enumerates every project in ~/.appbox; a cross-site
  /// page cannot read that body today, but there is no reason to serve it at
  /// all and blocking costs nothing. Artifact files and the design's own
  /// routes stay unguarded on GET so the panel's iframe and a hand-typed
  /// `http://127.0.0.1:4319/` both keep working with zero configuration.
  static bool guardedRequest(String method, String path) =>
      !_safeMethods.contains(method.toUpperCase()) || path.startsWith('/__');

  TrustVerdict check({
    required String method,
    required String path,
    String? host,
    String? origin,
    String? secFetchSite,
  }) {
    if (!hostAllowed(host)) {
      // 421 Misdirected Request: this connection is not for the authority the
      // request named. Same status the MCP SDK and mlflow settled on.
      return const TrustVerdict.deny(
          421, 'Host header is not a name this design server answers to.');
    }
    if (!guardedRequest(method, path)) return const TrustVerdict.allow();

    final allowedOrigin =
        origin != null && originAllowed(origin) ? origin : null;

    if (secFetchSite != null) {
      // A browser, and it told us where the request came from. `none` is a
      // user-initiated load (typed URL, bookmark, CDP Page.navigate — which
      // is how the worker tab reaches /__worker_page).
      const ownPage = {'same-origin', 'same-site', 'none'};
      if (!ownPage.contains(secFetchSite) && allowedOrigin == null) {
        return const TrustVerdict.deny(
            403,
            'Cross-site request refused. Add the origin to '
            '~/.appbox/trusted-origins (one per line), or pass '
            '--trusted-origin <origin>.');
      }
    } else if (origin != null && allowedOrigin == null) {
      // Older browser: no fetch metadata, but Origin is still unforgeable.
      return const TrustVerdict.deny(
          403,
          'Cross-origin request refused. Add the origin to '
          '~/.appbox/trusted-origins (one per line), or pass '
          '--trusted-origin <origin>.');
    }
    return TrustVerdict.allow(corsOrigin: allowedOrigin);
  }
}
