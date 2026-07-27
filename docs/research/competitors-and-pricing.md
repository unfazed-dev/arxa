# Competitors and pricing practice

## The comparable set

| product | what it is | pricing |
|---|---|---|
| **FlutterFlow** | visual Flutter builder, the incumbent | Free $0; paid tiers reported between **$30–39/mo** (Standard/Basic) and **$70/mo** Pro; **Teams ~$70/seat/mo**; **Business $150/seat/mo**. **Code download requires a paid tier.** |
| **Adalo** | no-code app builder | from **$45/mo**; Business **$200 for 10 seats** |
| **Lovable** | AI app generation | **~$25/mo**, not per-seat |
| **Cursor** | AI code editor | **$20/seat/mo** |
| **DreamFlow** | FlutterFlow's AI screen generator | bundled |
| **Nowa** | strongest Flutter alternative found in the spine research | no pricing surfaced |

**The loudest complaint in the market is per-seat pricing.** A five-person team
on FlutterFlow Business pays **$350/month**, against Lovable at $25 flat and
Cursor at $20/seat. FlutterFlow charging **$150 for one seat** while Adalo
charges **$200 for ten** is the specific comparison people make. Agencies are
exactly the buyer that comparison enrages — and agencies are persona P5.

## The structural advantage: BYO key

app_box's inference cost is the **user's**, because credentials are theirs
(`remote-control-and-chat.md`). Competitors bundling generation into a
subscription must price in model cost and margin; app_box does not. That argues
for a **flat licence or cheap seat**, not usage-based metering — and it means
undercutting the incumbent is not a loss-leader, it is the actual cost
structure.

Secondary: the **Firebase "bill shock"** critique of FlutterFlow (unoptimised
NoSQL queries producing surprise invoices) is a recurring complaint, with
Supabase/Postgres cited as the predictable alternative. Anything app_box
scaffolds for data should default to predictable-cost backends.

## The escape-hatch critique

The spine research already recorded FlutterFlow's **one-way export trap**. That
is the failure app_box is positioned against: output is ordinary stacked MVVM
in the user's own repo, gated by tests they can read. Worth making explicit in
positioning, because it is the thing the incumbent cannot copy without
abandoning its own lock-in.

## ❄️ Gap

Current authoritative **Shorebird** and **Codemagic** tiers did not surface —
returned figures came from third-party directories (Capterra, AlternativeTo)
that may lag. Check `shorebird.dev/pricing` and `codemagic.io/pricing` directly
before quoting them anywhere. Not a blocker: app_box *invokes* those tools with
the user's own account rather than reselling them.

Sources: [FlutterFlow pricing](https://www.flutterflow.io/pricing),
[Adalo pricing](https://www.adalo.com/pricing),
[Lovable pricing](https://lovable.dev/pricing),
[Cursor pricing](https://cursor.com/pricing),
[Shorebird](https://shorebird.dev/pricing),
[Codemagic](https://codemagic.io/pricing).
