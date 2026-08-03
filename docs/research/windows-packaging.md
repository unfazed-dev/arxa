# Windows packaging research (D34 input)

Commissioned per `docs/plans/scaffold-shell-kit-picker-decisions.md` (t≈289):
no prior decision record exists for MSIX/winget/Azure Trusted Signing.
Windows/Linux distribution stays deferred per D23; this is groundwork for a
future revisit, not a shipping decision. Mirrors the structure of the macOS
baseline in `docs/plans/distribution-and-platforms.md` (D22: signed/notarized
installer, built-in auto-updater, Homebrew cask, Stripe-only billing outside
any app store).

All sources are official docs or primary vendor pages fetched 2026-08-03/04
unless marked otherwise. Anything I could not confirm against a primary
source is marked **UNVERIFIED**.

## 1. MSIX vs classic installer vs portable exe

[MS Learn: Package and deploy Windows apps overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/) maps distribution goals to packaging mode: MSIX for Store/enterprise-MDM (Intune/ConfigMgr) distribution; unpackaged + self-contained for direct-website download or xcopy/zip. [MS Learn: What is MSIX?](https://learn.microsoft.com/en-us/windows/msix/overview) cites a 99.96% install success rate, clean uninstall (no leftover files/registry), and differential updates (only changed 64 KB blocks re-downloaded) as MSIX's headline benefits.

**Corrected assumption on sandboxing.** The research brief asked whether MSIX sandboxing breaks apps that spawn local servers/headless Chrome. It does not, by default. [MS Learn: MSIX containerization overview](https://learn.microsoft.com/en-us/windows/msix/msix-containerization-overview) and [Understanding how packaged desktop apps run on Windows](https://learn.microsoft.com/en-us/windows/msix/desktop/desktop-to-uwp-behind-the-scenes) both state MSIX packages run at one of two trust levels: **full trust (mediumIL)** — same permissions as a normal desktop app, just with package identity and file/registry virtualization — or **AppContainer (partial trust)**, a strict sandbox. Full trust is "the default for apps converted from Win32 installers using the MSIX Packaging Tool" (i.e. exactly the Desktop Bridge path the Flutter `msix` package uses); AppContainer is opt-in via an explicit manifest declaration. So a Flutter-built appboxd equivalent spawning a local HTTP server and headless Chrome over CDP would keep working under a default MSIX package — the sandboxing risk only materializes if someone later opts into AppContainer for extra security guarantees.

What MSIX does change unconditionally: install location becomes `C:\Program Files\WindowsApps\<pkg>` (read-only to the app), and writes are redirected to per-user virtualized storage. Any code that assumes it can write next to its own executable, or to an arbitrary absolute path outside the per-user profile, needs auditing before MSIX packaging — this is a real migration cost, just not the sandboxing one that was assumed.

**Auto-update.** MSIX's native update paths are Store updates or the `App Installer` (`ms-appinstaller`) protocol for non-Store distribution. MS Learn's own overview page cross-references a "[current status of Windows app distribution features (including the ms-appinstaller protocol change)](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status)" page, which I did not fetch directly — **UNVERIFIED**: I cannot confirm the current security/availability posture of the `ms-appinstaller` protocol handler from a primary source in this pass, only that Microsoft's own docs flag it as having had a "change" worth a dedicated status page. Treat App-Installer-based auto-update as needing a fresh check immediately before any implementation decision, not as a stable baseline.

Classic installers (Inno Setup, NSIS, WiX/MSI) have no OS-native update mechanism — the app ships its own updater. [docs.flutter.dev's Windows deployment guide](https://docs.flutter.dev/deployment/windows) explicitly frames this as the alternative to MSIX+Store: "you are not required to publish Windows apps through the Microsoft Store... the Microsoft documentation includes more information about traditional installation approaches, including Windows Installer."

## 2. winget submission mechanics

[MS Learn: Create your package manifest](https://learn.microsoft.com/en-us/windows/package-manager/package/manifest) shows the manifest is a YAML file (`PackageIdentifier`, `PackageVersion`, `Publisher`, an `Installers` list with `Architecture`/`InstallerType`/`InstallerUrl`/`InstallerSha256`). Critically, **winget has no MSIX preference** — `InstallerType` is an enum covering `exe, msi, msix, inno, wix, nullsoft, appx, font`, each with documented silent-install switches (Inno: `/SILENT` or `/VERYSILENT`; Nullsoft/NSIS: `/S`; MSI: `/q`). Choosing a classic installer over MSIX does not exclude winget listing.

Submission is a pull request to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs), authored via the `wingetcreate` CLI (interactive `wingetcreate new`, or fully scripted with `--submit` for CI) or manually. [CONTRIBUTING.md](https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md) requires one package version per PR, no unrelated file changes, and a first-time-contributor checklist. A bot (`wingetbot`) scans for hash mismatches and files automated update PRs, but every PR — bot or human — needs a human moderator's final approval; community reports (GitHub issues, not official docs) describe multi-day merge latency and occasional bot outages. Recommended cadence for an ongoing product: trigger `wingetcreate submit` from CI on each release rather than relying on the bot to notice.

## 3. Azure Trusted Signing (now "Azure Artifact Signing") and cert alternatives

[MS Learn overview](https://learn.microsoft.com/en-us/azure/trusted-signing/overview) and [pricing page](https://azure.microsoft.com/en-us/pricing/details/trusted-signing/): two SKUs, **Basic $9.99/month** (5,000 signatures/month, 1 certificate profile per type) and **Premium $99.99/month** (100,000 signatures/month, 10 profiles per type), overage $0.005/signature, billed in full from account creation (not pro-rated).

**Eligibility is the real gate, not price.** Per multiple corroborating Microsoft Q&A threads (secondary but consistent, dated through mid-2026): since April 2, 2025, new-customer onboarding is restricted to **US/Canada-based organizations with 3+ years of verifiable operating history** (business registration, tax records, or DUNS number). Individual-developer onboarding, previously open in public preview, has been paused with no stated exception process and no ETA for wider availability. **UNVERIFIED for this project specifically:** whether Totem Labs qualifies (US/Canada legal entity, 3+ years registered) is not something I can check from documentation — this must be verified directly in the Azure portal before counting on Trusted Signing as the signing path.

SmartScreen reputation is identical across signing methods now: [Trusted Signing FAQ](https://learn.microsoft.com/en-us/azure/trusted-signing/faq) states reputation "builds up automatically" once a file hash has "sufficient download history" — there is no more instant-trust shortcut for EV certs. This tracks Microsoft's March 2024 SmartScreen policy change (per industry reporting, not re-verified against a Microsoft primary source here) that removed EV's old advantage. Practical implication: paying the EV premium buys a hardware-token-backed identity check, not faster SmartScreen trust.

Alternative OV/EV certs (reseller pricing via SignMyCode/CheapSSLWEB/CodeSignCert, checked 2026; **treat exact figures as approximate, sourced from resellers not CA list prices**): Sectigo OV ~$220–226/yr, Sectigo EV ~$280–297/yr; DigiCert OV ~$385/yr, DigiCert EV ~$560/yr. A CA/Browser Forum ballot (cited as CSC-31 by secondary sources) caps new code-signing certs at ~460 days validity starting roughly Feb–Mar 2026, ending the old multi-year discount pattern — annual renewal cost is now the norm industry-wide, which narrows Trusted Signing's cost advantage over a cheap OV cert once you factor in renewal admin overhead either way.

## 4. Precedent: comparable dev-tool products

| Product | Installer | Auto-update | Store presence |
|---|---|---|---|
| VS Code ([docs](https://code.visualstudio.com/docs/setup/windows)) | Per-user exe (no admin, recommended default) or system-level exe (admin) or ZIP | Per-user exe: background auto-update, smoothest path. System exe: updates need elevation. ZIP: manual only. | Not covered by the page I fetched — not claiming Store presence either way. |
| Figma (web search, forum + help-center sources) | Squirrel.Windows-based exe (consumer default, "Wizard-Free," no UAC) | Built-in Squirrel background updater with delta packages | Separate MSI for enterprise/Intune deployment — explicitly does **not** auto-update, admin-managed instead |
| FlutterFlow desktop | Plain `.exe` installer (~127 MB), consistent with Flutter's own Inno Setup guidance | **UNVERIFIED** — could not confirm an auto-updater from available sources | No evidence found of MSIX or Store listing |

The pattern across dev tools that spawn local processes (VS Code, Figma) is: classic installer as the default consumer channel with a self-built or Squirrel-style background updater, and MSIX/Store reserved for enterprise-managed deployment where auto-update is deliberately turned off in favor of admin push. That maps closely to appbox's own committed macOS posture (direct download + built-in updater, Stripe-only billing outside any store).

## Recommended default path (if/when Windows revisit triggers)

1. **Installer: classic (Inno Setup or WiX), not MSIX**, as the primary channel — mirrors the macOS D22 posture and the VS Code/Figma precedent, avoids the unresolved App-Installer-protocol question, and keeps billing/updates entirely outside Store review.
2. **Signing: Azure Trusted Signing if Totem Labs is eligible (verify US/Canada + 3-year org history first); Sectigo OV as the fallback** if not — EV is not obviously worth the premium now that SmartScreen reputation is cert-tier-agnostic.
3. **Auto-update: self-built (Squirrel-pattern or equivalent), not App Installer** — consistent with the already-committed macOS auto-updater and avoids depending on a distribution feature MS's own docs flag as recently changed.
4. **winget: pursue independently of the installer choice** — list the Inno/WiX exe via a `wingetcreate`-driven CI submission per release; budget for multi-day moderator latency, don't treat it as a synchronous release step.

## Explicit uncertainty flags

- Totem Labs' Azure Trusted Signing eligibility (US/Canada entity, 3+ year history) — **UNVERIFIED**, must be checked in-portal.
- Current safety/availability status of the `ms-appinstaller` protocol for non-Store MSIX auto-update — **UNVERIFIED**, MS Learn references a dedicated status page I did not fetch.
- Whether FlutterFlow's Windows exe has any auto-update mechanism — **UNVERIFIED**.
- Exact CA/Browser Forum ballot number/date for the 1-year cert validity cap — sourced from secondary reseller/blog content, **treat as approximate**.
- Reseller cert prices (Sectigo/DigiCert) are list-adjacent, not CA official pricing — **approximate**.
