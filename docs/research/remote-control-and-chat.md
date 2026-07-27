# Remote control, device preview, and the chat surface

Research for: an iOS companion that pairs to the desktop app by QR, so app_box
can be driven remotely — and an industry-standard LLM chat inside the desktop
app.

## The reframe: these are two features, and one of them needs no app

The htmx producer is **already a local HTTP server** (`server.js`, `harness.js`,
`app.routes.js`). So "view the prototype on a phone" is not an app-building
problem — it is a URL. The Expo ecosystem arrived at exactly this split and
names it explicitly: dual-QR, where *"one QR launches as a PWA, the other inside
Expo Go — the Expo Go QR suits developers, the PWA QR suits clients and
non-technical stakeholders."*

| capability | needs the iOS app? | mechanism |
|---|---|---|
| **View / use the prototype on a real device** | **no** | QR → Safari → `http://<desktop>.local:PORT` |
| Hand a client a prototype in a meeting | no | same QR, any phone, zero install |
| **Control the desktop** — chat, run the pipeline, approve gates | **yes** | paired companion |
| Push notification when a gate goes red | yes | companion |

**Ship the zero-install path first.** It is a QR of a LAN URL, it works for
every client on any phone, and it delivers most of the value the companion was
being proposed for. The companion is then a genuinely separate product decision
rather than a prerequisite.

**It also dents the responsive hole.** Reviewing on a real iPhone and a real
iPad gives true widths. That is not a substitute for freezing at 390/744/1280 —
the generator still needs frozen input — but it makes the tablet and desktop
layouts *reviewable by a human*, which today they are not.

## 🔥 QR pairing — the attack to design against

QR device-linking is well-trodden (WhatsApp Web multi-device). It has a known
attack: the attacker opens the *real* web client, **captures the QR, embeds it
in a fake page**, and gets the victim to scan it — the victim links the
attacker's session. Reported mitigations:

| control | why |
|---|---|
| **Bind the QR payload to your own origin; refuse foreign codes** | directly defeats the embedded-QR relay |
| Rotate the QR every ~20–30 s, single-use nonce | bounds replay/capture |
| Device metadata + explicit confirm screen before linking | the human sees *what* they are linking |
| Linked-devices list with remote revoke | recovery |
| Idle-companion auto-expiry | mirrors WhatsApp's inactivity logout |
| Biometric/PIN before approving | blocks opportunistic physical access |
| Treat numeric pairing-code fallback as high risk | it is the weaker path |

**app_box's case is materially easier and should stay that way.** Pairing is
**LAN-local, with no cloud relay** — so the phishing shape above (a public web
client whose QR can be lifted) does not exist unless we build it. Concretely:

- QR carries `host`, `port`, a **short-lived nonce**, and the **fingerprint of
  the desktop's ephemeral TLS key**.
- Companion pins that fingerprint; a relayed QR points at the attacker's host
  and fails the pin.
- Desktop shows a confirm dialog naming the device before the link completes.
- Never add a cloud relay for convenience without redoing this analysis — it
  reintroduces exactly the attack the LAN constraint removes.

## 🔥 iOS local-network ceremony (concrete, and it validates §11)

An iOS app that discovers a desktop over mDNS **must** declare, or it fails
with `NSNetServicesErrorCode: -72008`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Used to find your desktop app on this network for pairing.</string>
<key>NSBonjourServices</key>
<array><string>_appbox._tcp</string></array>
```

This is precisely the *platform-conditional ceremony* §11 argued for: a value
in `--targets` (here `ios`) turning on required platform files. It is the first
concrete instance found outside the corpus.

## 🔥 The chat surface — MCP is the standard, and the shape is settled

Host application runs an **MCP client**; each integration is an **MCP server**.

**Transports** — and this is the design decision:
- **stdio** — local process, no network overhead, optimal for a desktop app.
- **Streamable HTTP + SSE** — remote, supports bearer tokens / API keys /
  custom headers.

A desktop app generally needs **both**: most existing MCP servers are stdio, but
remote integrations want HTTP.

**Tool registry pattern:** fetch tools from all connected servers, combine into
one registry the model sees.

**Reference implementations worth reading before writing any of this:**

| project | what to take |
|---|---|
| `chat-mcp` (Electron, BYO key) | dynamic provider config for anything OpenAI-SDK-compatible; UI extractable for web so desktop and web share interaction logic |
| RecurseChat | per-server **connection-state visualisation**; imports Claude Desktop config |
| Azure MCP CLI Client | JSON-config schema registration; **interactive vs batch mode split** — directly relevant to app_box being both a GUI and a harness plugin |
| Cherry Studio / LM Studio / Kiln | multi-provider + local-model coverage |

**🌡️ The scaling problem to plan for now: tool-context bloat.** As users add
servers, the combined registry eats the context window. One approach in the
wild is an MCP proxy filtering tool exposure with local embeddings. app_box is
especially exposed here because the pipeline itself wants to be a tool surface.

**❄️ Gap in the research: BYO-key credential storage.** The search did not
surface a settled pattern for desktop (OS keychain vs encrypted local config vs
proxy relay). MCP pushes credentials to the transport layer as bearer
tokens/headers, and OAuth 2.1 with a backend relay appeared for remote servers.
For a *paid* product this is a real open question — flagging it as unresolved
rather than guessing.

## How this lands on the human gates

The grill already settled that the person holds both gates and an agent can
reach one but never mint the approval token. A paired phone is an unusually
good surface for exactly that: a push when a gate goes red, the finding list,
the rendered surface, and Approve/Reject. It makes "the human decided" a
defensible claim rather than a convention — which is the same standard §14
applied to `structure.json`.

Sources: [MCP architecture](https://modelcontextprotocol.io/docs/learn/architecture),
[awesome-mcp-clients](https://github.com/punkpeye/awesome-mcp-clients),
[PulseMCP client index](https://www.pulsemcp.com/clients),
[LLM chat UIs supporting MCP](https://clickhouse.com/blog/llm-chat-mcp-support),
[MCP introduction](https://stytch.com/blog/model-context-protocol-introduction/),
[chat-mcp](https://github.com/AI-QL/chat-mcp),
[Glama client directory](https://glama.ai/mcp/clients).
