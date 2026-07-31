# pipeline/prototype — the prototype-serving runtime (plan 09)

Serves a frozen design over loopback HTTP and prints **one machine-readable
ready line** a UI spawns against. Host and port come from
`config/appbox.config.json` (`prototypeServer`), never literals — `port: 0`
asks the OS for a free one. This is the spawn target the desktop app (plan 08)
and the companion (plan 12) drive to preview a design.

```sh
python3 pipeline/prototype/serve.py appbox-app --json
```

## The spawn contract

A parent process reads **exactly one line from stdout** and knows the server is
*up*, not merely spawned. The JSON shape matches the designer's `serve` CLI so a
caller integrates against one contract for both servers:

```json
{"tag":"appbox-prototype-ready","url":"http://127.0.0.1:51234/","port":51234,"host":"127.0.0.1","pid":4321,"design":"appbox-app","artifact":"…/designs/appbox-app"}
```

- `url` is what a WebView loads. `port` is the port the OS actually bound (the
  only truth when `port: 0`).
- **Failures go to stderr and exit non-zero** — a caller parsing stdout for the
  ready line never sees a failure as a success record. An unknown design exits
  `66`; a bad port `64`; a bind failure `70`; malformed config `78`.
- `SIGTERM` / `SIGINT` stop the server cleanly and release the port.

| flag | default | note |
|---|---|---|
| `design` (positional) | — | a name under `designs/`, or a path; must contain `app.routes.js` |
| `--host` | `config.prototypeServer.host` (`127.0.0.1`) | loopback by default; unreleased client work |
| `--port` | `config.prototypeServer.port` (`0`) | `0` = OS-assigned |
| `--json` | off | emit the ready line above; otherwise two human lines |

## What is served

The design directory is the document root. `GET` / `HEAD` are served with
correct MIME types (`text/css`, `text/javascript`, `image/svg+xml`, …) and
`Cache-Control: no-store`. Paths are confined to the design root — traversal
out of it is refused with `404`, never followed. There is no directory listing.

Everything physically in the design tree resolves: `assets/css/app.css`,
`assets/images/*`, `ui/views/**` templates, `models/**`, `_ds/**` (consumed
design-system) if present.

## What is NOT served (and why)

This runtime is the **buildable subset** of plan 09. The plan's full design is a
Dart `HttpServer` + `flutter_js` server that *executes* the design's viewmodels,
so rendered pages and `POST` mutations come out byte-for-byte identical to the
Node producer. That engine lives in **`app/`**, which is fenced to plan 08 for
this build, so:

- **No viewmodel execution.** Routes like `/` or `/design` are *rendered* by
  the viewmodels, not static files, so they `404` here. Assets and raw templates
  resolve; rendered pages do not.
- **No `POST` handling.** Mutations (`hx-post`) need the engine.
- **No `/assets/vendor/*`** unless the design vendors its own copy. `base.html`
  references `/assets/vendor/htmx.min.js`; those libs live in the designer
  runtime today and are baked into the artifact at **freeze time** (plan 05).
  Pointing at the designer runtime would couple shipped code to a dev tool, so
  this server resolves vendor paths only against the design's own tree.

These are deliberate, fenced scope — not gaps to fill by reaching into `app/`.

## Done-when (plan 09) status

| # | assertion | status | reason |
|---|---|---|---|
| 1 | 37 surfaces render identically, engine vs Node | **env-blocked** | needs the embedded engine (steps 9.1–9.4), fenced to `app/` |
| 2 | a `POST` mutation updates a fragment | **env-blocked** | needs the engine to run viewmodel handlers |
| 3 | every asset resolves | **pass** | every file in `designs/appbox-app/assets` returns `200` with correct MIME — asserted by resolving each URL to a real file, not by grepping |
| 4 | added bundle size < ~5 MB | **pass** | the runtime is two text scripts (~10 KB); no binary, no runtime dep beyond `python3` (already required by `pipeline.sh`) |
| 5 | kill → dead on the channel within a heartbeat | **env-blocked** | needs the paired channel (plan 12); clean shutdown + port release *are* verified here |
| 6 | no Node on `PATH` → app still serves | **partial** | static serving + the spawn contract need zero Node; rendered pages need the engine (blocked) |

## Selftest (R5)

```sh
bash pipeline/prototype/selftest.sh
```

Proves the happy path **and** that the runtime fails for the right reasons:
unknown design exits non-zero with no ready line on stdout; an out-of-range port
is rejected; a missing asset `404`s; a path-traversal probe is refused.
