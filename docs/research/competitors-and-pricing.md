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

appbox's inference cost is the **user's**, because credentials are theirs
(`remote-control-and-chat.md`). Competitors bundling generation into a
subscription must price in model cost and margin; appbox does not. That argues
for a **flat licence or cheap seat**, not usage-based metering — and it means
undercutting the incumbent is not a loss-leader, it is the actual cost
structure.

Secondary: the **Firebase "bill shock"** critique of FlutterFlow (unoptimised
NoSQL queries producing surprise invoices) is a recurring complaint, with
Supabase/Postgres cited as the predictable alternative. Anything appbox
scaffolds for data should default to predictable-cost backends.

## The escape-hatch critique

The spine research already recorded FlutterFlow's **one-way export trap**. That
is the failure appbox is positioned against: output is ordinary stacked MVVM
in the user's own repo, gated by tests they can read. Worth making explicit in
positioning, because it is the thing the incumbent cannot copy without
abandoning its own lock-in.

## The deploy-tool tiers (gap now closed)

Previously flagged unresolved. Both matter because `appbox-deployer` invokes
them **with the user's own account** — appbox never resells them, so these are
costs the buyer already carries or chooses.

**Shorebird** (code push / OTA patching) — free tier for getting started;
paid plans metered on **patch installs**, with the pricing model itself being
the interesting part:

- **Monthly**: overage billing is *optional and off by default*; spending
  limits are set in the console. Credits historically **did not roll over**
  between months.
- **Annual**: the whole year's patch allowance is **credited upfront on day
  one**, usable whenever — what you pay upfront is the total, no surprise
  charges. The non-rollover problem on monthly plans is why annual exists.

**Codemagic** (CI/CD) — free tier of build minutes per month, then per-minute
or per-user team billing, **no minimum contract**, cancel anytime, pay only for
used minutes. Higher tiers offer **unlimited build minutes** on macOS (Apple
Silicon), Linux and Windows. **Enterprise starts around $12,000**, and is
purchasable through AWS or Google Cloud Marketplace. Free accounts for
teachers, students and non-profits. Machine lineup includes macOS M2 and M4,
with M4 Max reserved for annual/Enterprise — **M2 is the entry machine, not the
top one**.

*Independently checked around 2026-07-19; vendor tiers move. Re-verify at
`shorebird.dev/pricing` and `codemagic.io/pricing` before quoting in anything
customer-facing.*

**The design lesson worth stealing:** Shorebird's annual plan solves a real
customer grievance (expiring credits) by changing *when* the allowance lands,
not by discounting. For appbox's own licence, that is a better lever than
price — a flat annual with everything granted upfront reads as generous and
costs nothing extra, given BYO-key means we carry no marginal inference cost.

Sources: [FlutterFlow pricing](https://www.flutterflow.io/pricing),
[Adalo pricing](https://www.adalo.com/pricing),
[Lovable pricing](https://lovable.dev/pricing),
[Cursor pricing](https://cursor.com/pricing),
[Shorebird](https://shorebird.dev/pricing),
[Codemagic](https://codemagic.io/pricing).
