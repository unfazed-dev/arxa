#!/usr/bin/env bash
# pipeline/prototype/selftest.sh -- R5 proof that the prototype runtime works
# AND can fail for the right reasons.
#
# Positive: serves the real appbox-app fixture, the ready line parses, the
# OS-assigned port is real, every design asset resolves through the server
# with the right MIME, and SIGTERM stops it cleanly.
# Negative: an unknown design name exits non-zero and prints NO ready line;
# a missing asset 404s; a path-traversal probe is refused.
# A selftest that proves only the happy path is rejected (R5).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SERVE="$HERE/serve.py"
ROOT="$(cd "$HERE/../.." && pwd)"
DESIGN="appbox"
DESIGN_DIR="$ROOT/designs/$DESIGN"

pass=0; failc=0
ok()  { echo "  PASS: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1"; failc=$((failc + 1)); }

command -v curl >/dev/null || { echo "selftest needs curl" >&2; exit 2; }

# --- negative 1: unknown design exits non-zero, emits no ready line ---------
# stderr (not stdout) carries the failure -- a parent parsing stdout for the
# ready line must never see a failure as a success record.
neg_err="$(python3 "$SERVE" no-such-design --json 2>&1 >/dev/null)"
neg_rc=$?
if [ "$neg_rc" -ne 0 ]; then ok "unknown design exits non-zero (rc=$neg_rc)"
else bad "unknown design should fail"; fi
if printf '%s' "$neg_err" | grep -q "no-such-design"; then ok "error names the missing design"
else bad "error should name the missing design"; fi
# stdout must be empty: no ready line on a failure path.
neg_out="$(python3 "$SERVE" no-such-design --json 2>/dev/null || true)"
if [ -z "$neg_out" ]; then ok "no ready line on failure (stdout empty)"
else bad "failure leaked to stdout: $neg_out"; fi

# --- negative 2: invalid port -----------------------------------------------
if python3 "$SERVE" "$DESIGN" --port 99999 --json >/dev/null 2>&1; then
  bad "port 99999 should be rejected"
else ok "port 99999 rejected"; fi

# --- positive: serve the real fixture ---------------------------------------
out="$(mktemp)"
trap 'rm -f "$out"; [ -n "${pid:-}" ] && kill -TERM "$pid" 2>/dev/null || true' EXIT
python3 "$SERVE" "$DESIGN" --json >"$out" 2>/dev/null &
pid=$!

# Wait for the ready line (the machine-readable spawn contract).
ready=""
for _ in $(seq 1 50); do
  if [ -s "$out" ]; then ready="$(head -1 "$out")"; break; fi
  sleep 0.1
done

if printf '%s' "$ready" | grep -q '"tag":"appbox-prototype-ready"'; then ok "ready line present"
else bad "no ready line"; cat "$out"; fi

read_field() { printf '%s' "$ready" | python3 -c "import sys,json;print(json.loads(sys.stdin.read())['$1'])" 2>/dev/null; }
url="$(read_field url)"
port="$(read_field port)"
rhost="$(read_field host)"

if [ -n "$port" ] && [ "$port" -gt 0 ]; then ok "OS-assigned port=$port"
else bad "no OS-assigned port"; fi

if [ -n "$rhost" ] && [ "$rhost" = "127.0.0.1" ]; then ok "bound to loopback (127.0.0.1)"
else bad "host should be loopback, got '${rhost:-<empty>}'"; fi

if [ -z "$url" ]; then bad "no url to probe"; exit 1; fi

# Every asset file that ships in the design resolves through the server with a
# 200 and the right content type (done-when #3: resolve each URL to a real
# file, do not just grep for leftover strings).
asset_fail=0
while IFS= read -r f; do
  rel="${f#"$DESIGN_DIR/"}"
  code="$(curl -s -o /dev/null -w '%{http_code}' "$url/$rel")"
  if [ "$code" != "200" ]; then
    bad "asset /$rel -> $code"; asset_fail=$((asset_fail + 1))
  fi
done < <(find "$DESIGN_DIR/assets" -type f 2>/dev/null)
[ "$asset_fail" -eq 0 ] && ok "all design assets resolve (200)"

ct_css="$(curl -s -o /dev/null -w '%{content_type}' "$url/assets/css/app.css")"
case "$ct_css" in text/css*) ok "css served as text/css ($ct_css)" ;; *) bad "css mime wrong: $ct_css" ;; esac

body_first="$(curl -s "$url/assets/css/app.css" | head -c 80)"
if [ -n "$body_first" ]; then ok "css body non-empty"
else bad "css body empty"; fi

# --- negative 3: a missing asset 404s ---------------------------------------
miss="$(curl -s -o /dev/null -w '%{http_code}' "$url/does-not-exist.css")"
if [ "$miss" = "404" ]; then ok "missing asset -> 404"
else bad "missing asset -> $miss"; fi

# --- negative 4: path traversal is refused ----------------------------------
trav="$(curl -s -o /dev/null -w '%{http_code}' "$url/../../../../etc/hosts")"
if [ "$trav" = "404" ]; then ok "path traversal refused (404)"
else bad "path traversal leaked: $trav"; fi

# --- clean shutdown: SIGTERM stops the server and releases the port ---------
if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
  kill -TERM "$pid"
  stopped=0
  for _ in $(seq 1 50); do
    kill -0 "$pid" 2>/dev/null || { stopped=1; break; }
    sleep 0.1
  done
  if [ "$stopped" = "1" ]; then ok "server stopped on SIGTERM"
  else bad "server did not stop on SIGTERM"; fi
  # The port should be free for reuse now.
  if [ -n "$port" ] && curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$port/" 2>/dev/null; then
    bad "port $port still answers after stop"
  else ok "port $port released after stop"; fi
fi

echo "---"
echo "selftest: $pass passed, $failc failed"
[ "$failc" -eq 0 ]
