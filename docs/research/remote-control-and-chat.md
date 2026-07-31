# Remote control, device preview, and the chat surface

Research for: an iOS companion that pairs to the desktop app by QR, so appbox
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

**appbox's case is materially easier and should stay that way.** Pairing is
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
| Azure MCP CLI Client | JSON-config schema registration; **interactive vs batch mode split** — directly relevant to appbox being both a GUI and a harness plugin |
| Cherry Studio / LM Studio / Kiln | multi-provider + local-model coverage |

**🌡️ The scaling problem to plan for now: tool-context bloat.** As users add
servers, the combined registry eats the context window. One approach in the
wild is an MCP proxy filtering tool exposure with local embeddings. appbox is
especially exposed here because the pipeline itself wants to be a tool surface.

## 🔥 BYO-key credential storage — CLOSED

Previously flagged unresolved. Researched; the answer is settled, and the
threat model is the part that makes it obvious.

**Reframe first: for BYO-key, you are not hiding the key from the user.** It is
*their* key. The Keychain protects secrets at rest but does not make a key
secret from the person operating the machine — and it does not need to. The
real threats are **other apps and other users on that machine**, backup and
sync leakage, and accidental disclosure through logs, crash reports and screen
sharing. Design against those.

**The decision: OS vault, never hand-rolled crypto.** `flutter_secure_storage`
(Keychain on macOS/iOS, DPAPI-backed on Windows). Electron's equivalent is
`safeStorage`. An encrypted config file is a *fallback*, and only if its
encryption key itself lives in the vault — a file encrypted with a key stored
beside it is theatre.

### macOS pitfalls that will cost a day each if unknown

| pitfall | symptom | fix |
|---|---|---|
| Keychain Sharing capability missing | `-34018 errSecMissingEntitlement` | add to **both** `macos/Runner/DebugProfile.entitlements` *and* `Release.entitlements` |
| App Group not in `keychain-access-groups` | **writes silently succeed and store nothing** | add `$(AppIdentifierPrefix)<group>` |
| Signed + notarized build with hardened runtime | **reads silently return `null`** — works in `flutter run --release`, fails after notarisation | the code signature identity is part of the keychain ACL; **test against a signed, notarised build** |
| Plugin-side Darwin bug (reported on v10.0.0) | `-34018` *despite* correct entitlements | check the patched release before burning hours on entitlement permutations |
| Wrong accessibility class | silent read failure on autostart | default is `unlocked`; an app that starts before interaction needs `first_unlock` |

**Two of these fail silently and green.** A write that stores nothing and a
read that returns null after notarisation are exactly the stale-green shape
this project keeps finding. The check must be: write, restart, read back, **in
a notarised build** — not "the call did not throw."

### Linux: be honest in the UI

There is no single standard vault. Electron's `safeStorage` can fall back to
`basic_text` when no keyring is detected — obfuscation, not encryption. Detect
the backend at runtime and **say which tier is active**: *"stored in the macOS
Keychain"* vs *"encrypted file — no system keyring detected."* For a paid
product handling credentials with real billing consequences, that disclosure is
both a security and an honesty requirement.

### Handling rules

- Load the key, use it, drop it — minimise residency in memory.
- Vault holds the key only. Chat history and settings go in the normal store;
  secure storage is not a database.
- Never log it, never include it in crash reports or telemetry.

**And it is a third platform-conditional ceremony.** Keychain Sharing
entitlements in two files are turned on by `--targets macos`, exactly as
`NSLocalNetworkUsageDescription` is turned on by `--targets ios`. Three
independent instances now support §11's derivation model.

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
