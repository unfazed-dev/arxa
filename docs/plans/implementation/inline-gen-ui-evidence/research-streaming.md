# dsh streaming transport for plugins (v0.1.0-rc.7)

Root: `~/.dsh/profiles/node_modules/@deepseek-ai/`. All paths below are relative to that
root unless absolute. Claims are from `lib/types/**/*.d.ts` and READMEs (authoritative)
plus the shipped `lib/index.js` / `lib/client.js` implementations. Anything not directly
read is marked **INFERRED**.

**Bottom line: yes — a plugin can serve its own SSE endpoint from its host half and
consume it with `EventSource` in its browser half. This is not a workaround; it is
exactly what the shipped HMR plugin does.**

---

## 1. `ctx.webServer.register` — full contract

Package: `dsh-host-webserver`. Underlying server is **`node:http`** (not Hono, not
Express) — README line 1: "a `node:http` server that listens on activation and provides
`ctx.webServer`". Only dependency is `@deepseek-ai/schemastery` (no HTTP framework).

Type declaration — `dsh-host-webserver/lib/types/index.d.ts`:

```ts
export type WebRouteKind = 'exact' | 'prefix';

export interface WebRoute {
    kind: WebRouteKind;
    /** Absolute pathname, no trailing slash. */
    path: string;
    /** Owns the full response lifecycle (may hold the response open, e.g. SSE). */
    handler: (req: IncomingMessage, res: ServerResponse) => void | Promise<void>;
}

export interface WebUpgradeRoute {
    /** Absolute pathname, no trailing slash. */
    path: string;
    /** Owns protocol negotiation and the upgraded socket after dispatch. */
    handler: (req: IncomingMessage, socket: Duplex, head: Buffer) => void | Promise<void>;
}

export interface Config {
    host: '127.0.0.1' | '0.0.0.0';   // only these two values
    port: number;                     // 0 = OS-assigned
}
```

`WebServer` surface (same file): `register(route): () => void`,
`registerUpgrade(route): () => void`, `registerFallback(handler)`, `tapIndex(transform)`,
`applyIndexTaps(html)`, `get port()`, `get host()`.

**Streaming answer.** The handler signature is raw `(req, res)` node:http — not a
Fetch-style `Request => Response`. There is therefore no `ReadableStream` body to return;
you stream by holding `res` open and calling `res.write()`. The doc comment on
`WebRoute.handler` states this outright: *"Owns the full response lifecycle (may hold the
response open, e.g. SSE)."* SSE and chunked transfer are both available. **INFERRED** (I did
not grep for `setTimeout` / `headersTimeout` / `requestTimeout` in
`dsh-host-webserver/lib/index.js`): no timeout is imposed on an open response. The actual
evidence is behavioural — HMR holds its connections open indefinitely, §2a.

**WebSocket upgrade: supported**, via a separate registry — `registerUpgrade`, exact-path
only. README: "Upgrades match exactly and unmatched connections are closed." The webserver
delivers only the raw socket; "the upgrade handler owns the protocol handshake and
connection contents."

**Match order is fixed and matters (see §2b):** exact over the whole table, then longest
prefix, then the fallback handler.

**Failure/teardown semantics.** A throwing HTTP handler is answered 400 (or the socket
destroyed if headers already went out) and logged as a warning — never exits the process.
An upgrade-handler exception or upgraded-socket transport error is logged and destroys its
socket. Disposal calls `close()` + `closeAllConnections()` and destroys every tracked
upgraded socket. A duplicate `(kind, path)` **throws** — route collisions are treated as
composition-time misconfiguration.

---

## 2. Server-Sent Events — viable, with a shipped existence proof

### 2a. The proof: `dsh-client-hmr`

Host half — `dsh-client-hmr/lib/index.js`:

```js
const EVENTS_ENDPOINT = "/plugins/events";

const connect = (res) => {
    res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "connection": "keep-alive"
    });
    res.write(": connected\n\n");
    res.write(sseData({ type: "graph", graph: ctx.clientModules.graph() }));
    connections.add(res);
    res.on("close", () => { connections.delete(res); });
};

ctx.effect(() => {
    const disposeRoute = ctx.webServer.register({
        kind: "exact",
        path: EVENTS_ENDPOINT,
        handler: (req, res) => {
            if (req.method !== "GET" && req.method !== "HEAD") { res.writeHead(405); res.end(); return; }
            connect(res);
        }
    });
    const unsubscribe = ctx.clientModules.onRebuilt((id, rev) => { /* broadcast */ });
    ...
});
```

`inject = ["clientModules", "webServer"]`; `sseData(frame)` is
`` `data: ${JSON.stringify(frame)}\n\n` ``.

Browser half — `dsh-client-hmr/lib/client.js:71` (inside `ctx.effect`):

```js
const source = new EventSource(EVENTS_ENDPOINT);
source.addEventListener("message", (event) => {
    let frame;
    try { frame = JSON.parse(event.data); } catch { ...warn...; return; }
    handle(frame);
});
return () => { source.close(); };
```

So the complete pattern — host `webServer.register` + `text/event-stream` + browser
`EventSource`, both wrapped in `ctx.effect` for disposal — is shipped, in-tree, and
plugin-authored. Note HMR's reconnect posture: on every connect it re-sends the **whole**
graph frame rather than using SSE `id:` / `Last-Event-ID` resume. Nothing in dsh
implements event-id resume; a plugin wanting replay must design it itself (a full-state
frame on connect is the shipped idiom, and matches the projection layer's whole-value
rule).

### 2b. Route collision — the first thing an implementer hits

`dsh-client-modules` already owns a **prefix** route on `/plugins`
(`dsh-client-modules/lib/index.js:158-160`, `kind: "prefix", path: "/plugins"`), serving
`/plugins/<id>/client.js` and its source maps (path handling at `:321-326`). Yet HMR
registers `kind: "exact", path: "/plugins/events"` on top of it without conflict, because
duplicate-detection is per `(kind, path)` and **exact beats longest-prefix at match time**.

Consequence: a plugin may legally register `kind: 'exact', path: '/plugins/<id>/stream'`
and it will win over the modules prefix route. Registering a *prefix* on `/plugins` would
throw. **INFERRED** (mechanically implied by the documented match order + per-(kind,path)
duplicate rule, not separately tested): any exact path under `/plugins/` is safe.

### 2c. The Host-header fence — a plugin's own route is NOT behind it

This was the specific question, and the answer is **no fence**.

`isTrustedApiRequest` lives in `dsh-client-connection/lib/index.js:184` and is applied at
these call sites, all owned by the connection plugin itself:

| Line | Guarded surface |
|---|---|
| `:237` | `/api` shared-channel interceptor with `authority: 'loopback'` → 403 |
| `:249` | **every `rpc.handle` channel route** → `res.writeHead(403)` |
| `:538` | privileged `/api` method set → 403 |
| `:554` | the `/api` route itself (`:552` `path: API_PATH`, registered `:562`) |
| `:570` | the two WebSocket upgrades (`registerUpgrade`, `:567`) |

The fence is a *property of the connection plugin's handlers*, not of the webserver. A
route registered directly through `ctx.webServer.register` runs no trust check at all —
which is why the shipped `/plugins` bundle route and `/plugins/events` SSE route have
none.

Two corollaries worth stating precisely:

- **`ctx.connection.rpc.handle` channels ARE fenced** (`:249`) even though they are just
  `kind: 'prefix'` webServer routes underneath. Its options carry
  `authority: 'trusted-host' | 'loopback'` (`lib/types/rpc.d.ts`). So the RPC channel is
  the *more* guarded surface, not the less.
- **`isTrustedApiRequest` is not exported.** The connection package's export list is
  `export { API_PATH, Config, HOST_EVENTS_PATH, HostConnectionService, MUX_EVENTS_PATH,
  apply, inject, name }` (`lib/index.js:588`), and `package.json` `exports` offers only
  `.`, `./invariant`, `./client`, `./src/*`. A plugin cannot import the fence helper.

**Proportionate reading:** an unfenced plugin SSE route has *exactly the same exposure as
the shipped `/plugins/<id>/client.js` bundle route*, under the default posture
`host: '127.0.0.1'` (loopback-only). `dsh web --host 0.0.0.0` is documented as
intentionally unsupported until an auth layer exists. So this is a known, accepted posture
— not a hole you must reimplement a fence to close. Reimplementing it would be reasonable
only if you serve genuinely sensitive data *and* expect a non-default bind.

**CSP: a grep found no header-setting code.** `content-security-policy` across every
package's `lib/index.js` returns no CSP header being set — the only hits are unrelated `ShellExecSpec` strings in
`dsh-tool-cordis`. Nothing blocks `EventSource` to a same-origin path. (Electron loads
dist over `file://` and carries fetch over an IPC bridge — **INFERRED** that a same-origin
`EventSource` to the HTTP server does not apply in the Electron shell; the web shell is
the target here.)

---

## 3. WebSocket — dsh already runs two, and they are the live-session transport

**The existence proof you asked for:** `/api/events.mux` and `/api/events.host`.

- Constants: `dsh-client-connection/lib/index.js:16` `MUX_EVENTS_PATH`, `:18`
  `HOST_EVENTS_PATH` (both `${API_PATH}/events.*`, `API_PATH = "/api"` at `:14`).
- Registered at `:567` via `apiCtx.webServer.registerUpgrade({...})`, fenced at `:570`.
- Implementation: `dsh-client-connection/lib/types/websocket-downlink.d.ts` — class
  `WebSocketDownlinks` with `handleMux(req, socket, head)`, `handleHost(req, socket, head)`,
  `close()`, plus `rejectWebSocketUpgrade(socket)`.
- Uses the real `ws` library: `dsh-client-connection/package.json` depends on `ws@^8.21.0`,
  hoisted to `~/.dsh/profiles/node_modules/ws`. The class holds a `private readonly server`
  — the `noServer: true` acceptor. **INFERRED** (the `noServer` detail is from the README's
  "the no-server acceptor" phrase + standard `ws` usage, not read from source).

**Semantics (from the connection README, "`/api` WebSocket downlinks"):** each socket
"send[s] only the corresponding `ServerRequest` text messages to the browser; the client
sends no application data over these sockets." The downlink d.ts is blunter: *"Client
messages are a protocol violation: upstream traffic remains on HTTP."* If either socket
ends, the connection generation fails and **both** streams rebuild; readiness needs both
sockets open *and* a successful `host.describe` HTTP call. Plain GETs to these paths return
**426**, with no SSE fallback (the SSE codec in `toFetchHandler` serves only the
in-process/Electron carrier).

**Can a plugin multiplex onto it? No.** The frames are minted by `dsh-host-apiproxy` from
its own typed event streams, and the browser-side reader dispatches on a closed frame-type
set. The only plugin-reachable frame types are the ones the framework itself mints
(`session/projection`, `session/event`, `session/jobs`, `host/remote-event`, …) — see §4.
There is no "publish an arbitrary frame onto the mux" API on `ctx`.

A plugin **can** stand up its own WebSocket via `registerUpgrade` + `ws` with
`noServer: true`. See the ranking in §6 for why that is not the recommendation.

---

## 4. `ctx.remote` — re-verified, genuinely closed

**Confirmed: the prior conclusion holds.** `ctx.remote.$on`'s legal key set is a
hard-coded array.

`dsh-api-remotes/lib/types/remote-events.d.ts` (and `.js`, and `lib/index.js:18`):

```ts
export declare const API_REMOTE_FORWARDED_EVENTS: readonly [
  "agent-preset/selected", "commands/change", "credentials/updated",
  "cordis/request-run", "cordis/request-run-resolved",
  "cordis/dynamic-package", "cordis/dynamic-retract",
  "cordis/inspect-query", "cordis/inspect-query-resolved",
  "llm/adapters-updated", "settings/document-updated",
];
```

Eleven events. The README is explicit that this is the whole control point: *"this array
is simultaneously the whole control point over what a consumer can receive and the legal
key set of `ctx.remote.$on`. Forwarding one more event is an entry here and nothing else."*
The Host face additionally asserts each name against `TypertForwardableEvent`, which
rejects a name that is not a declared event, one that binds an AgentScope, and one whose
shape is not one-way.

Delivery path, client side — `dsh-client-runtime/lib/client.js:10485`:
```js
if (frame.type === "host/remote-event") ctx.remote.$dispatch(frame.event, frame.args);
```

Adding an event means editing a shipped package's source array and rebuilding both
TypeScript faces (the file is deliberately listed in *both* `tsconfig.host.json` and
`tsconfig.client.json` `files` so the two faces cannot drift). **A third-party plugin
cannot do this.** No plugin-defined server→client event exists on this channel.

**Sanctioned server→client push that a plugin CAN emit: yes — session projections.** See §5b.
That is the real answer to "is there ANY sanctioned server→client event a plugin can
emit", and it is a genuine one, with an important constraint.

---

## 5. Client-side session hooks

### 5a. They are live-subscribed, not snapshots

Types — `dsh-client-ui-slots/lib/types/store.d.ts:7,14`:

```ts
export type SnapshotSelectorHook<T>      = <S>(sel: (s: T) => S, eq?: (a: S, b: S) => boolean) => S;
export type MaybeSnapshotSelectorHook<T> = <S>(sel: (s: T) => S, eq?: (a: S, b: S) => boolean) => S | undefined;
```

Standard-kit seats — `dsh-client-runtime/lib/types/client/index.d.ts:71-87`, merged into
`SessionStandardProps` / `SessionMaybeStandardProps` / `GlobalStandardProps`:

- `useSession: SnapshotSelectorHook<ConversationSnapshot>` (`:71`); the maybe-form at `:79`
- `useProjection: UseProjection` (`:75`, `:83`) — described in-source as *"the fifth
  framework hook seat: key-addressed projection reader (undefined = capability absent)"*
- `useSessions: SnapshotSelectorHook<SessionListState>` (`:87`), plus `useWorkspaces`
- `useInput: SnapshotSelectorHook<InputState>` — the composer's input state; the seat is
  declared in `dsh-cordis-client-runner/lib/client.js:2183,2215,2251,2299,2331` (and a
  `Maybe` form at `:2137`). Consumed e.g. `dsh-client-ui-conversation/lib/client.js:3360`
  `const input = useInput((s) => s);`

**Live.** The one hook constructor in the client stack is `bindSnapshotSelector` in
`dsh-client-web-react/lib/index.js:20-26`:

```js
function bindSnapshotSelector(w) {
    const subscribe   = (fn) => w.subscribe(fn);
    const getSnapshot = ()   => w.getSnapshot();
    return function useSelector(sel, eq) {
        return useSyncExternalStoreWithSelector(subscribe, getSnapshot, void 0, sel, eq);
    };
}
```

Its doc comment: *"uSES bridge: turns any bare observable snapshot source into a typed
selector hook… This is the ONE hook constructor in the client stack — engines and hosts
traffic in bare sources; binding happens on the React side."* Subscribe/getSnapshot are
captured once per source into stable closures so components never resubscribe across
renders; equality defaults to `Object.is`. So every one of these hooks re-renders on
server-pushed change, with selector-level change gating.

**What feeds them (the full chain):**
`/api/events.mux` + `/api/events.host` WebSocket downlinks → the connection plugin's
single-consumer stream loop → runtime stores (`dsh-client-runtime/lib/client.js:8302`
routes `session/projection` frames into `this.projectionStore(frame.sessionId).apply(...)`
then `this.notifier.markDirty()`) → `bindSnapshotSelector` uSES → your component.

### 5b. `useProjection` is a real plugin-extensible push channel — with one hard condition

`dsh-session-projection` owns `ctx.sessionProjections`. `SessionProjectionMap` is an
**empty, merge-extensible interface** (`lib/types/types.d.ts`) — *"Domain packages merge
their key here via declaration merging"* — so a plugin genuinely can add its own key and
have values pushed to the browser with zero transport code.

Public API (README):
- `ctx.sessionProjections.register(definition): () => void`
- `ctx.sessionProjections.onChanged(listener): () => void`
- `ctx.sessionProjections.snapshot(session): ProjectionSnapshot`

`ProjectionDefinition<K,S> = { key, schema, init(), apply(state, event), view(state), stateVersion }`.
Registration idiom (`dsh-tool-todo/lib/index.js:80-91`):
`ctx.inject(["sessionProjections"], (c) => c.sessionProjections.register({ ..., stateVersion: 2 }))`.
Ten shipped packages use it (`dsh-goal`, `dsh-plan-mode`, `dsh-session-title`,
`dsh-token-meter`, `dsh-subagent`, `dsh-session-stats`, …).

Client side: seeded by the history tail page's projections block, updated by
`session/projection` push frames, **higher seq wins**; per-key uSES binding, so
`useProjection('yourKey')` re-renders live.

**The hard condition — and it is what rules this out as the primary answer.** The
framework subscribes to `session/event` once and drives every unit's `apply(state, event)`
over **committed session events**. A domain holds no subscriptions and owns only pure
mathematics. `init`/`apply`/`view` **must be synchronous** and state must be plain JSON.
So a projection can only express *a fold over the session event log*. Out-of-band data —
a generator running on its own clock, a file watcher, an HTTP poll — has no event to fold,
and minting synthetic session events to carry it would pollute the conversation log that
the transcript, persistence, and every other projection read from.

Two further documented limits (README, "Known Limitations"): the whole-value rule means
every update ships the complete current state rather than a delta, and *"every tail page
carries every registered key — there is no per-key opt-out… revisit if a domain's value
grows large"* — which names a growing streaming payload as the case it does not cover.
Also, the unit table is process-wide, so key presence is not a per-session capability
signal; clients must read the value, not treat an absent key as feature-absence.

---

## 6. Ranked recommendation

**#1 — Your own SSE route: `ctx.webServer.register({ kind: 'exact', path: '/plugins/<id>/stream' })`
+ `new EventSource(...)` in the browser half.**

Why it wins: it is the only option that is simultaneously (a) shipped and proven in-tree by
`dsh-client-hmr`, (b) unconstrained in cadence, shape, and data source — no session-event
coupling, no synchronous-pure-function rule, deltas allowed, (c) zero protocol code, since
the browser's `EventSource` handles framing *and* auto-reconnect, and (d) exactly matched
to the need, which is a one-way host→browser push. Hold `res` open, `res.write()` per
update, track connections in a `Set`, clean up on `res.on('close')`, and wrap both halves
in `ctx.effect` for disposal. Send a full-state frame on connect (HMR's idiom) since dsh
implements no `Last-Event-ID` resume.

**#2 — Session projection (`ctx.sessionProjections.register` + `useProjection`) — but only
if your updates are already a fold over committed session events.** If the generated UI is
derived from the agent's own tool calls and messages, this is strictly better than #1: it
is the framework-sanctioned path, it rides the existing WebSocket downlink, it survives
reconnect and restart via the tail-page baseline and the persisted checkpoint cache, and
it costs you no transport code at all. It loses the top slot only because out-of-band
generation has nothing to fold, and because the whole-value + every-tail-page-carries-every-key
rules make a large or fast-moving payload the documented non-goal.

**#3 — Your own WebSocket (`ctx.webServer.registerUpgrade` + `ws`).** Rejected because you
would take on protocol negotiation, framing, heartbeat, and reconnect logic — all of which
`EventSource` gives you free — to buy a client→server direction you do not need (dsh's own
downlinks call client messages "a protocol violation" and keep upstream on HTTP). If you
later need genuine bidirectionality, this is the correct escalation. Caveat: `ws` resolves
today only because it is `dsh-client-connection`'s dependency hoisted to the profile root —
**INFERRED-fragile**; declare your own `ws` dependency rather than relying on hoisting.

**#4 — `ctx.remote.$on`.** Rejected on re-verification, not assumption: the key set is the
11-entry `API_REMOTE_FORWARDED_EVENTS` array, enforced on both compiler faces, and
extending it means editing and rebuilding a shipped package. No plugin-defined event can
ride it.

**#5 — `ctx.connection.rpc.handle` + client polling.** Rejected because `ConnectionRpcHandler`
returns `Promise<RpcResult<unknown>>` — strictly unary. Polling it would add latency and
load for no gain over #1. Its one advantage is that it is the only plugin-facing surface
that inherits the Host-header trust fence (`lib/index.js:249`) with a declarable
`authority: 'trusted-host' | 'loopback'` — worth remembering if you ever need a *guarded*
plugin endpoint, since the fence helper is not exported for reuse elsewhere.
