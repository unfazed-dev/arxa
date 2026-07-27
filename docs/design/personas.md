# Personas

Two people. Everything app_box does serves one of them.

---

## Evan — founder, Totem Labs

Solo Dart/Rust/Flutter/Stacked developer. Builds bespoke apps for clients:
designs for them, then builds autonomously. app_box is both his tool and his
product.

**Context.** One person doing intake, design, architecture, build, review and
ship. No design partner to hand off to, no reviewer to catch mistakes, no QA.
The pipeline is the colleague he does not have.

**Goal.** Take a client conversation to a shipped, opinionated Stacked MVVM app
without the quality depending on how tired he was that week.

**He operates in four modes**, and the product should feel different in each:

| mode | doing | needs |
|---|---|---|
| **intake** | eliciting what the client actually wants | capture, not code; something the client can react to |
| **autonomous build** | letting the pipeline run | to walk away and trust the gates |
| **red-gate recovery** | something failed | the finding, the file, the line, and what would change |
| **ship** | releasing | to be *stopped* and made to confirm |

**Frustrations that must not recur.** Gates that pass while broken. Work
invented downstream because nobody captured it upstream. Two sources of truth
that silently drift.

**Abandons it if:** red stops meaning broken.

---

## Michelle — indie iOS + Android developer

Ships her own apps to both stores. Solo, unfunded, time-poor. Has no context on
any of this architecture and will not read the docs before trying it.

**Context.** Evaluates app_box against FlutterFlow on a Tuesday evening. Gives
it twenty minutes. Has been burned by a tool that made export a paid tier and
another whose generated code she could not extend.

**Goal.** Native-feeling apps on both platforms without hand-writing the same
scaffolding for the fifth time — and without betting her product on someone
else's runtime.

**What earns her trust, in order:**

1. **The showcase app launches on install.** She sees output quality before
   typing anything.
2. **The code is hers.** Ordinary Stacked MVVM in her own repo, readable and
   extensible. No one-way export.
3. **Nothing lies.** A kit listed as available works. If Stripe is a stub, the
   UI says so *before* she builds against it.
4. **The price is not per-seat theatre.** She has one seat and knows what a
   five-person team pays elsewhere.

**Frustrations that must not recur.** Discovering a limitation at build time
that was knowable at selection time. Paying to get her own code out.

**Abandons it if:** she hits `UnimplementedError` on something the UI offered
her — or if the free tier is crippled rather than merely smaller.

---

## What the split means

Evan needs **depth**: gates, ledgers, drift detection, escape hatches.
Michelle needs **honesty and a fast first win**, and will never see most of the
machinery.

Where the two conflict, Michelle wins on the **first ten minutes** and Evan
wins on **everything after**. A surface that serves neither is the one to cut.
