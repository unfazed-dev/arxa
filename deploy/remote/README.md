# deploy/remote — arxa self-host remote access

The R2 "Anywhere" pack (consolidation plan, decision 10). LAN-only QR pairing
stays the default; this pack is for reaching your daemon from any network
without a Totem Cloud. Shape: headscale coordination server (the **only**
public surface, TLS'd by Caddy + Let's Encrypt) + a private mesh CA whose
wildcard leaf gives the daemon's web builder browser-trusted HTTPS origins
over the tailnet. No app traffic is ever public.

## What you need

- A $5 VPS (any 1 vCPU / 1 GB box, Ubuntu 24.04) with Docker + compose plugin.
- A domain you control.
- openssl 3.x locally (for the mesh-CA step; on macOS `brew install openssl`).

## Flow

1. **DNS** — two records pointing at the VPS:
   - `A  hs.example.com → <vps-ip>` (the enrollment door)
   - (optional) `AAAA hs.example.com → <vps-ipv6>`

2. **Configure + launch:**

   ```bash
   cd deploy/remote
   cp .env.example .env   # set HEADSCALE_DOMAIN + ACME_EMAIL
   docker compose up -d
   docker compose logs -f caddy   # wait for the LE cert
   ```

3. **Create a user and a single-use, short-lived pre-auth key** (this key is
   what travels in the arxa pairing QR — treat it like a password):

   ```bash
   docker compose exec headscale headscale users create alice
   docker compose exec headscale headscale preauthkeys create \
     --user alice --reusable=false --expiration 1h --tags tag:arxa
   ```

4. **Pair** — in the arxa app, choose "Remote (self-host)", enter
   `https://hs.example.com` as the login server and the pre-auth key. The app
   renders the pairing QR; the companion device scans it and enrolls its
   Tailscale client at your headscale. The key is dead after one use / 1 hour.

5. **Mesh CA** — issue the wildcard leaf on the daemon host (or anywhere with
   openssl 3, then copy):

   ```bash
   ./scripts/gen-mesh-cert.sh mybox ~/.arxa/mesh-ca
   ```

   The daemon's web builder serves `leaf.crt`/`leaf.key` for
   `*.<slug>.arxa` origins (`https://app.mybox.arxa/…`). Install
   `ca.crt` on each client at pairing: macOS/Windows/Linux import into the
   system trust store; **iOS** gets it as a config profile — install the
   profile, then Settings → General → About → Certificate Trust Settings →
   enable full trust (one-time).

6. **Verify:**

   ```bash
   docker compose exec headscale headscale nodes list     # devices enrolled
   tailscale status                                        # on a client
   curl -I https://hs.example.com                          # LE cert, door up
   openssl s_client -connect app.mybox.arxa:443 -servername app.mybox.arxa </dev/null
   ```

## Honesty box — what the operator (you, on this VPS) can see

- **Sees:** enrolled node public keys, mesh IPs, hostnames, last-seen times —
  and can admit/revoke nodes. Coordination metadata only.
- **Never sees:** traffic. Node-to-node is WireGuard end-to-end encrypted;
  when NAT forces a DERP relay, the relay forwards ciphertext it cannot read.
- **Never has:** the mesh-CA private key (stays on the daemon host), pairing
  session contents, or any app data. Compromise of this VPS = re-pair
  everyone, not data loss.

## Files

- `docker-compose.yml` — headscale 0.29.2 (pinned) + Caddy 2.10 (pinned), named volumes.
- `Caddyfile` — public LE TLS for the headscale endpoint only.
- `headscale/config.yaml` — sane defaults; env-expanded `HEADSCALE_DOMAIN`.
- `scripts/gen-mesh-cert.sh` — mesh-CA root + `*.<slug>.arxa` wildcard leaf
  (EC P-256, serverAuth, 825-day, idempotent root, re-runnable for leaf rotation).
- `.env.example` — the two knobs.

## Notes

- Rotating a leaf: re-run `gen-mesh-cert.sh <slug> <dir>` — the CA root is
  reused, clients keep trusting, only the leaf is replaced.
- Prefer hosted Tailscale instead? Skip this whole pack; set the app's login
  server to the Tailscale control plane and enroll normally. Zero client-code
  difference — decision 10 guarantees that.
- Windows daemon hosts use the system tailscaled; the Dart `package:tailscale`
  (tsnet) path covers the rest in-process.
