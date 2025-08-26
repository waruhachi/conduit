## Localization (i18n)

- Supported locales: `en`, `de`, `fr`, `it`.
- Uses Flutter's `gen_l10n` with ARB files and the `intl` package for date/number formatting.

### Install & Generate

- Install packages:
  - `flutter_localizations` (Flutter SDK)
  - `intl: ^0.20.2`
- Files are under `lib/l10n/*.arb`. The template is `app_en.arb`.
- Generate localizations:
  - `flutter gen-l10n`
  - or run a full build: `flutter pub get && flutter gen-l10n`

### Usage Examples

- Basic text:
  - `Text(AppLocalizations.of(context)!.appTitle)`
- With placeholder:
  - `Text(AppLocalizations.of(context)!.dynamicContentWithPlaceholder('Alex'))`
- Pluralization:
  - `Text(AppLocalizations.of(context)!.itemsCount(3))`
- Date/time formatting:
  - `final dateText = DateFormat.yMMMMEEEEd(Localizations.localeOf(context).toString()).format(DateTime.now());`
  - `Text(dateText)`
- Number formatting:
  - `final price = NumberFormat.currency(locale: Localizations.localeOf(context).toString(), symbol: '€').format(1234.56);`
  - `Text(price)`

### Add a New Language

- Create a new ARB file in `lib/l10n/`, e.g. `app_es.arb`.
- Copy keys from `app_en.arb` and provide translated values.
- Ensure placeholders and plural rules match the template.
- Add the locale to `supportedLocales` in `MaterialApp` (see `lib/main.dart`).
- Regenerate: `flutter gen-l10n`.

### Best Practices

- Key naming: use lowerCamelCase (e.g., `loginButton`, `errorMessage`).
- Include `@` metadata with `description` for context and `placeholders` with examples.
- Prefer ICU plural/select syntax for quantities and genders.
- Avoid concatenating strings at runtime; use placeholders in ARB.

### In‑App Locale Switching

- Open the Profile page → Settings tile → choose `System`, `English`, `Deutsch`, `Français`, or `Italiano`.
- Selection persists across app launches.

### Troubleshooting

- Build fails with ARB placeholder errors:
  - Ensure every placeholder has an example string and correct type.
- Missing translation at runtime:
  - Flutter falls back to English; search for hard‑coded strings and replace with `AppLocalizations`.
- iOS strings not changing:
  - Restart the app after changing system language or use the in‑app language selector.

### References

- Flutter localization: https://docs.flutter.dev/ui/accessibility-and-localization/internationalization
- Intl package: https://pub.dev/packages/intl


