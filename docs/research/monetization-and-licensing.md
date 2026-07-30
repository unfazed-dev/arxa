# Monetization and licensing for a local-first generator

Reading-research, not measured findings. Claim grades: **A** official
docs/statement, **B** corroborated secondary, **C** single source or reasoned
inference. Checked 2026-07-30. Builds on
[competitors-and-pricing.md](competitors-and-pricing.md) (pricing landscape,
BYO-key cost structure, the FlutterFlow export trap) — not repeated here.

## Verdict

1. **Charge for the tool, never for the output.** Encrypted generated code is
   the FlutterFlow one-way-export trap squared — the exact thing
   `competitors-and-pricing.md` positions app_box against. No precedent of
   users accepting it was found anywhere.
2. **Sell a flat annual license with a JetBrains-style perpetual fallback**
   (12 months paid → keep the last version forever). Everything granted
   upfront, the Shorebird lever. No per-seat, no usage credits — BYO-key means
   we carry no inference cost to meter.
3. **License = Ed25519-signed key with embedded expiry + grace period,
   verified fully offline** against an embedded public key. One online
   activation (or a signed license file for air-gapped), then never phone home
   except a soft annual refresh with a ≥30-day grace.
4. **Encrypt app_box's own vault** (BYO LLM keys, registry, design state) with
   age/XChaCha20-Poly1305 — unambiguous win, users expect it.
5. **Do not encrypt emitted targets.** If requirement (a) is truly mandatory,
   scope "all files app-box generates" to the daemon's internal state, which
   is the only reading users won't revolt against.
6. Client-side DRM is a speed bump, not a wall — design for "make paying
   easier than pirating", not for defeating crackers.

## 1. How local-first dev tools monetize (2026)

| tool | model | price | grade |
|---|---|---|---|
| **Cursor** | subscription + usage credits | $20/mo Pro = $20 of API credits; $60 Pro+; $200 Ultra | [A](https://cursor.com/blog/june-2025-pricing) |
| **Zed** | free editor, sub for hosted AI | Pro $20/mo incl. $20 token credits; prompt-based → token-based Oct 2025 | [A](https://zed.dev/blog/pricing-change-llm-usage-is-now-token-based) |
| **JetBrains** | subscription + perpetual fallback | e.g. PyCharm $89 yr 1 → $53 yr 3+ personal; fallback license after 12 consecutive months; continuity discount to 40% | [A](https://sales.jetbrains.com/hc/en-gb/articles/207240845-What-is-a-perpetual-fallback-license-and-how-do-I-use-one) |
| **TablePlus** | perpetual + paid update window | $99 one-time/1 device, 1 yr updates, ~$59 renewal; team $79/seat | [A](https://tableplus.com/pricing) |
| **Panic Nova** | perpetual + paid update window | $99 incl. 1 yr updates, $49/yr thereafter | [A](https://help.nova.app/faqs/purchasing/) |
| **Sublime Text** | perpetual + paid major upgrades | $99 personal per-user (all your machines); business moved to subscription | [A](https://www.sublimetext.com/sales_faq) |
| **Tower** | subscription | $79 perpetual → $69/yr in 2018, still $69/user/yr | [B](https://mjtsai.com/blog/2018/06/26/git-tower-3-switches-to-subscription/) |

**What the money says (B-grade).** No public conversion data exists for most
of these; the defensible pattern is structural, not numeric:

- **Tools whose vendor pays inference sell subscriptions + credits.** Cursor
  and Zed both landed on "$N/mo = $N of model credits at API prices." Cursor's
  June 2025 switch from 500 fixed requests to credit pools caused surprise
  bills, a public apology and refunds
  ([A](https://cursor.com/blog/june-2025-pricing),
  [B](https://techcrunch.com/2025/07/07/cursor-apologizes-for-unclear-pricing-changes-that-upset-users/)).
  Usage-credit complexity is the single biggest driver-frustration source in
  AI tooling ([B](https://www.cloudzero.com/blog/cursor-ai-pricing/)).
  **BYO-key removes the entire justification** — see
  `competitors-and-pricing.md` §BYO key.
- **Tools with no marginal cost converge on "own it + pay for an update
  window."** JetBrains fallback, TablePlus, Nova, Sublime are all variants of
  one idea: the customer never loses what they paid for; the vendor's
  recurring revenue is *updates*, not *access*. JetBrains announced
  subscription-only in Sept 2015, took heavy backlash, and within weeks added
  the perpetual fallback that made the model palatable
  ([B](https://adtmag.com/blogs/watersworks/2015/11/jetbrains-subscriptions.aspx),
  [B](https://www.i-programmer.info/news/90-tools/9004-jetbrains-responds-to-backlash.html)).
  A decade later it is the settled norm.
- **Per-seat is the loudest grievance in our own market** — already recorded
  in `competitors-and-pricing.md` (FlutterFlow $150/seat vs Lovable $25 flat).
- **The cautionary tale is Unity's Runtime Fee (2023):** retroactive,
  unpredictable metering of customer *output*. It was cancelled on
  2024-09-12 before ever being charged
  ([A](https://unity.com/blog/unity-is-canceling-the-runtime-fee)), CEO gone,
  and "what if my engine changes terms again" became a permanent buyer
  question ([B](https://gameworldobserver.com/2023/09/18/unity-apology-runtime-fee-devs-say-trust-is-broken),
  [B](https://arstechnica.com/civis/threads/unity-is-dropping-its-unpopular-per-install-runtime-fee.1502899/)).
  Charging against generated artifacts is the same shape of mistake.

## 2. Offline-capable licensing crypto

The settled pattern (all A-grade, [Keygen offline-licensing
docs](https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/)):

- **Signed keys.** Payload (JSON: expiry, entitlements, max app version,
  machine IDs) + Ed25519 signature, verified offline with an embedded public
  key. `ED25519_SIGN` is Keygen's recommended scheme; ECDSA-P256 for FIPS
  shops. Tamper-proof but not secret — anyone can read the payload.
- **License files.** Same idea as a transferable certificate: signed with
  Ed25519/RSA, optionally encrypted AES-256-GCM, handed to air-gapped machines
  by USB/email. This is the enterprise/air-gap answer.
- **Embedded datasets** commonly carry: expiry, offline-use duration (e.g.
  "1 year offline before reactivation"), **a fixed grace period (Keygen's own
  example: 5 days past expiry)**, max entitled app version, node-lock
  hardware IDs.
- **Activation norms (B, [LicenseSeat](https://licenseseat.com/license-key)):**
  2–3 activations per key (home + work machine), self-service deactivate
  portal, hybrid validation — online when reachable, signed local proof when
  not. Floating-license heartbeat grace is 1–2 *minutes*; offline grace for
  node-locked desktop tools runs *days to months*.

**Where the honesty line is.** Industry consensus, stated plainly by the
vendors themselves:

> License keys are a practical middle ground between no protection and
> heavy-handed DRM. The goal isn't to make piracy impossible; it's to make
> paying easier than pirating. — [LicenseSeat, B](https://licenseseat.com/license-key)

> If an attacker has full control of the machine, they can bypass any
> client-side check. — [Gatewarden (Keygen client) non-goals, B](https://github.com/Michael-A-Kuykendall/gatewarden)

What signed keys actually stop: casual key sharing, keygen forgery
(the checksum-era keygen is dead — you can't forge Ed25519 without the
private key), expired-access, seat overage. What they don't: binary patching
and memory patching, which remove the check regardless of the cryptography
([B, HISE audio forum — practitioners](https://forum.hise.audio/topic/8791/different-encryption-types-in-hise/25?page=1)).
For a tool aimed at *agencies* (P5), the realistic threat is unlicensed seat
sharing, not nation-state crackers — activation limits catch exactly that.

**Cost of infrastructure:** hosted Keygen starts ~$99/mo
([B](https://onetimesuite.com/comparison/keygen-alternative/)); Keygen CE is
free self-hosted but a Ruby+Postgres+Redis stack to run
([A](https://keygen.sh/docs/self-hosting/)). For app_box's volume, a signed
key is ~100 lines against an Ed25519 library plus a Stripe webhook — buying
the platform is premature (C, judgement).

## 3. Encrypting generated artifacts

**The crypto is easy; the product decision is not.**

Practical scheme, if ever needed: per-project random key, files encrypted
XChaCha20-Poly1305, project key *wrapped* to the license/device recipient —
this is exactly the [age](https://age-encryption.org) multi-recipient model
(A: spec, ChaCha20-Poly1305 payload, X25519 recipients, scrypt for
passphrases, multi-recipient wrapping native). Keygen's encrypted license
files (AES-256-GCM+Ed25519, A above) are the same construction for license
payloads. Transparent decrypt-on-unlock in the daemon is straightforward
*for files only the daemon reads*.

**Prior art for monetizing code generators — and nobody encrypts the
output:**

- **Cycling '74 RNBO/Max (the closest analog, A):** the *tool* is paid (Max
  license/subscription); generated C++ export is dual-licensed
  proprietary-or-GPLv3, free commercial use under $200k revenue
  ([license text](https://support.cycling74.com/hc/en-us/articles/10730031661587-Cycling-74-License-for-Max-Generated-Code-for-Export),
  [FAQ](https://support.cycling74.com/hc/en-us/articles/10730637742483-RNBO-Export-Licensing-FAQ)).
  Cycling '74 claims *copyright* on the generated code and rents the license —
  but the bytes are plaintext in the user's repo.
- **JUCE (A):** dual AGPL/commercial, $40/mo/dev indie, free tier shows a
  splash screen in *built apps* ([license](https://juce.com/legal/juce-6-license/)).
  Again: monetize via license terms on output, never via unreadable output.
- **Game engines/asset stores:** encrypted asset bundles ship inside *sold
  games* (end-user product), not into a developer's own working repo. No
  analogy to a dev tool's emitted source.

**Legal/ownership ground truth:** the US Copyright Office's Jan 2025 report
holds purely AI-generated output is not copyrightable without meaningful
human authorship ([B](https://www.mondaq.com/unitedstates/copyright/1580572/key-insights-on-copyright-and-ai-from-the-us-copyright-offices-2025-report)),
and every major AI vendor's terms assign output to the user (Anthropic,
JetBrains AI; [B](https://talkthinkdo.com/blog/who-owns-ai-written-code-what-ctos-developers-and-procurement-teams-need-to-know/)).
So the trained expectation of app_box's exact buyer is "**I own the output,
in my repo, in plaintext**" — that is also app_box's stated positioning
against FlutterFlow (`competitors-and-pricing.md` §escape-hatch).

**Community reaction evidence (the risky part).** No tool was found that
encrypts the source it generates into the customer's repo — the absence is
itself the finding (C). Adjacent evidence, all negative:

- FlutterFlow merely *paywalling code download* is already the market's
  loudest complaint (`competitors-and-pricing.md`). Encryption-at-rest of
  emitted code is that, plus breaking git/editors/CI.
- Software that encrypts a tree of user files pattern-matches to
  **ransomware** ([B](https://www.bleepingcomputer.com/news/security/the-locky-ransomware-encrypts-local-files-and-unmapped-network-shares/)) —
  expect both user revulsion and behavioral-AV/notarization friction (C).
- **Tailscale's 180-day node-key expiry** — a mild, security-justified
  version of "vendor controls your access" — generates a steady stream of
  "my servers died" UX complaints
  ([A](https://tailscale.com/docs/features/access-control/key-expiry),
  [B](https://github.com/tailscale/tailscale/issues/4854)). Users tolerate it
  because connectivity is the product. Generated code has no such excuse.

## 4. What NOT to do (backlash case file)

- **License-server dependency bricks the product.** Adobe retired CS3 /
  Acrobat 8 activation servers; paying customers permanently lost the ability
  to activate software they owned ([A, Adobe support forums](https://community.adobe.com/questions-617/cs3-acrobat-8-activation-servers-retired-536021)).
  Any app_box scheme must survive our death: offline-verifiable keys, and a
  published sunset plan (final build with checks removed, or key escrow).
- **Retroactive/unpredictable pricing on output:** Unity Runtime Fee, §1.
- **Surprise usage bills:** Cursor credits, §1.
- **License managers that hurt paying users:** iLok's 2013 License Manager
  update deleted customers' plugin licenses
  ([B](https://www.attackmagazine.com/news/ilok-license-manager-software-update-deletes-users-plugin-licences/));
  dongle resentment is endemic in pro audio (Gearspace, C). Copy protection
  that touches the *workflow* converts fans into pirates' advocates.
- **App Store entanglement:** serious dev tools distribute direct and skip
  the Mac App Store (Sublime: "no plans", [A](https://www.sublimetext.com/sales_faq))
  — IAP/reader-app rules don't fit license-key tooling. Direct distribution +
  notarization is the norm; nothing in our licensing scheme interacts with
  notarization *unless* it encrypts user file trees (§3, C).

## Comparison of licensing schemes

| scheme | crypto | offline | revocation | friction | stops | used by |
|---|---|---|---|---|---|---|
| Plain serial + server DB | none | never | instant | low until server dies | casual sharing | legacy tools |
| Checksum key | obscurity | yes | none | none | nothing (keygens) | pre-2000s software |
| **Ed25519 signed key** | asymmetric sig | **fully** | only via expiry embedded | paste once | sharing, forgery, expiry | Keygen, LicenseSeat |
| Signed+encrypted license file | Ed25519 + AES-256-GCM | air-gapped | file expiry | file transfer | same + payload secrecy | Keygen enterprise |
| Node-locked activation | sig + hw fingerprint | after 1st activation | on next check-in | transfer on new machine | seat overage | TablePlus, Cryptolens |
| Floating/heartbeat | sig + heartbeat | 1–2 min grace | instant | constant connection | concurrent overage | JetBrains enterprise |
| Dongle (iLok/eLicenser) | hardware | yes | physical | **hated** | all but determined crackers | pro audio (retreating) |

## Hard problems / what users will hate

- **Encrypting generated code breaks the toolchain.** git diff, editors,
  `flutter analyze`, CI — all expect plaintext. "Transparent decrypt" means a
  FUSE mount or daemon-served filesystem; both are fragile on macOS/Windows
  and indistinguishable from ransomware heuristics (C).
- **Any check can be patched out** of a local binary; the emitted Flutter
  code is Dart source anyway — there is no binary to protect. The license
  check can only live in appboxd/the pipeline.
- **Expiry requires a trustworthy clock and a grace story.** Keygen's own
  guidance: embed grace periods, expect clock manipulation, accept it (A).
- **Revocation vs offline is a real trade-off:** fully offline keys can't be
  revoked; chargeback handling relies on the next online refresh or the
  embedded expiry (A/B).
- **Company-death is a purchase objection**, not an edge case — Adobe CS3 and
  Unity made buyers ask it by default (§4). The answer must be designed in
  (fallback license + sunset plan), not FAQ'd.
- **Teams:** activation limits punish exactly the agency persona P5 if set
  naively; norm is 2–3 machines per human, self-service transfer (B).

## What we'd build / skip

**Build**

1. Flat **annual** license, everything granted upfront (Shorebird lever,
   `competitors-and-pricing.md`), **perpetual fallback after 12 paid months**
   (JetBrains pattern). No per-seat below a generous team size; no credits.
2. **Ed25519-signed license key** (payload: expiry, fallback-version
   watermark, grace 30 days, licensee email) verified offline in appboxd;
   one online activation against a tiny endpoint, 3 machines, self-service
   deactivate. Stripe webhook → key email. Signed license file for air-gap.
3. **Encryption where it belongs:** app_box's vault (BYO LLM keys — already
   flagged sensitive in `remote-control-and-chat.md` — registry, pipeline
   state) via age-format XChaCha20-Poly1305, daemon-held key in the OS
   keychain.
4. A written **sunset/escrow commitment** (final unprotected build or key
   release on wind-down). Costs nothing, closes the Adobe objection.

**Skip**

- Encrypting emitted targets / generated code (all of §3).
- Usage metering, credit pools, per-seat pricing below enterprise scale.
- Hosted licensing platforms at current volume; heavy DRM, dongles,
  phone-home-per-launch, heartbeat checks.

## Sources not linked inline

[Keygen offline licensing](https://keygen.sh/docs/choosing-a-licensing-model/offline-licenses/) ·
[Keygen cryptography API](https://keygen.sh/docs/api/cryptography/) ·
[Keygen pricing](https://keygen.sh/pricing/) ·
[LicenseSeat license keys](https://licenseseat.com/license-key) ·
[LicenseSeat floating license](https://licenseseat.com/floating-license) ·
[Cryptolens node-locked vs floating](https://cryptolens.io/2024/06/choosing-between-floating-and-node-locked-licenses/) ·
[age](https://age-encryption.org) ·
[Zed pricing](https://zed.dev/pricing) ·
[JetBrains subscription licensing](https://sales.jetbrains.com/hc/en-gb/articles/206544679-Subscription-based-licensing) ·
[RNBO export licensing FAQ](https://support.cycling74.com/hc/en-us/articles/10730637742483-RNBO-Export-Licensing-FAQ) ·
[JUCE license](https://juce.com/legal/juce-6-license/) ·
[Tailscale key expiry](https://tailscale.com/docs/features/access-control/key-expiry) ·
[Unity cancels Runtime Fee](https://unity.com/blog/unity-is-canceling-the-runtime-fee) ·
[Cursor pricing apology](https://cursor.com/blog/june-2025-pricing) ·
[TechCrunch on Cursor apology](https://techcrunch.com/2025/07/07/cursor-apologizes-for-unclear-pricing-changes-that-upset-users/) ·
[Adobe activation-server retirement](https://community.adobe.com/questions-617/cs3-acrobat-8-activation-servers-retired-536021) ·
[US Copyright Office 2025 AI report analysis](https://www.mondaq.com/unitedstates/copyright/1580572/key-insights-on-copyright-and-ai-from-the-us-copyright-offices-2025-report)
