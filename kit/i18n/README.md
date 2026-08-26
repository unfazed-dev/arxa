# arxa_kit_i18n

Locale machinery for arxa_kit apps: a supported-language value type, a
persisted system+override locale model with live switching, intl-backed
formatting, a placeholder-parity guard, and an LLM locale directive for
generative UI. Ships English + Polish; works for any locales.

**The kit deliberately does NOT codegen translations.** The app owns its
gen-l10n `AppLocalizations`; this kit resolves *which* locale is active,
persists the user's choice, and formats values for it.

## Install

```yaml
dependencies:
  arxa_kit_i18n:
    path: ../i18n
```

## Usage

Register in the locator at startup and wire `MaterialApp`:

```dart
// main.dart — create once, load the persisted override before runApp.
final store = await SharedPreferencesArxaKitLocaleStore.create();
final i18n = ArxaKitI18n(
  store: store,
  systemLocale: WidgetsBinding.instance.platformDispatcher.locale,
);
await i18n.load();
locator.registerSingleton<ArxaKitI18n>(i18n);

// MaterialApp — listen so the app rebuilds live on setLocale().
MaterialApp(
  locale: i18n.locale,
  supportedLocales: const [Locale('en'), Locale('pl')],
  localizationsDelegates: const [
    AppLocalizations.delegate, // from the APP's gen-l10n output
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  // ...
);

// A settings toggle — persists + notifies:
await i18n.setLocale('pl');   // live switch, persisted
await i18n.clearOverride();   // back to the system locale
```

Formatting in the effective locale:

```dart
i18n.formatDate(DateTime.now());          // "30 lip 2026" under pl
i18n.formatNumber(1234.5);                // "1 234,5" under pl
i18n.formatCurrency(1234.5, 'PLN');       // "1234,50 zł" under pl
```

Translation review guard:

```dart
i18n.placeholderParity(
  'You have {COUNT} new messages, {name}',
  'Masz {COUNT} nowych wiadomości, {name}',
); // true — same token set (case-sensitive)
```

LLM locale directive (generative UI / chat surfaces):

```dart
i18n.doNotTranslate = ['Acme', 'ProPlan'];
final systemPrompt = '${i18n.llmLocaleDirective()}\n\n$restOfPrompt';
```

## Scope

- `ArxaKitLanguage` — value type: BCP-47 `tag`, `nameEn`, `nameNative`;
  `ArxaKitLanguage.supported` ships `en` + `pl`; `byTag` falls back to the base
  subtag (`'pl-PL'` → `'pl'`).
- `ArxaKitLocaleStore` — persistence port (`read`/`write`/`clear`);
  `SharedPreferencesArxaKitLocaleStore` is the shipped default.
- `ArxaKitI18n` — resolution (override → system → `en`), live switching via
  `ChangeNotifier`, intl formatting, `placeholderParity`,
  `llmLocaleDirective`.
- `arxa_kit_i18n/arxa_kit_testing.dart` — `FakeArxaKitLocaleStore` with a script queue
  and call counts; tests never touch platform channels.

## Gotchas

- **`intl: any` is never pinned** — its version is SDK-pinned through
  `flutter_localizations`. Adding a version constraint will conflict.
- **The model is system + override + live-switch.** `locale`/`bcp47` resolve
  override → system locale → English. `setLocale` persists *and* notifies, so
  wire `MaterialApp` to listen rather than restarting the app.
- **Translation strings live in the app.** The kit has no ARB/codegen; it
  expects the app's gen-l10n delegates to sit next to the
  `flutter_localizations` delegates.
- **`SharedPreferencesArxaKitLocaleStore.create()` is async** — create it once
  before `runApp`, not per viewmodel.
- **The LLM directive is a prompt block, not a translator** — it steers the
  model to answer in `languageNameEn`/`languageNameNative`, preserve
  `{placeholder}` tokens, and emit ISO 8601 / plain numbers so the app keeps
  formatting authority. `doNotTranslate` injects brand/product terms.
