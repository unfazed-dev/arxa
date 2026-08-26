# i18n

- **i18n**: when an artifact is localized, every chrome/surface string lives in
  `l10n/app_<locale>.arb` and renders via the `t` prop — never hardcode copy
  in views. Jargon variants are key suffixes (`keyPlain`/`keyTechnical`).
  Localized content is per-locale seeds (`<name>_seed.<locale>.json` is the
  SSOT) generating `<name>_fixtures.<locale>.json`. `arxa design pseudolocalize`
  derives the `qps-ploc` pseudo-locale from English — run it to catch
  truncation and hardcoded strings. Full contract: runtime/README.md "L10n".
