# Conduit

<div align="center">
  <a href="https://groups.google.com/g/conduit">
    <img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" style="height:80px; vertical-align:middle;"/>
  </a>
  <a href="https://apps.apple.com/us/app/conduit-open-webui-client/id6749840287">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height:56px; vertical-align:middle;"/>
  </a>
  <br><br>
</div>

<br>

<p align="center">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/1.png" alt="Screenshot 1" width="250" />
  
</p>

Conduit is an open-source, cross-platform mobile application for Open-WebUI, providing a native mobile experience for interacting with your self-hosted AI infrastructure.

## Features

### Core Features
- **Real-time Chat**: Stream responses from AI models in real-time
- **Model Selection**: Choose from available models on your server
- **Conversation Management**: Create, search, and manage chat histories
- **Markdown Rendering**: Full markdown support with syntax highlighting
- **Theme Support**: Light, Dark, and System themes

### Advanced Features
- **Voice Input**: Use speech-to-text for hands-free interaction
- **File Uploads**: Support for images and documents (RAG)
- **Multi-modal Support**: Work with vision models
- **Secure Storage**: Credentials stored securely using platform keychains

## Screenshots

<p align="center">
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/2.png" alt="Screenshot 2" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/3.png" alt="Screenshot 3" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/4.png" alt="Screenshot 4" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/5.png" alt="Screenshot 5" width="200" />
  <img src="fastlane/metadata/android/en-US/images/phoneScreenshots/6.png" alt="Screenshot 6" width="200" />
</p>

## Requirements

- Flutter SDK 3.0.0 or higher
- Android 6.0 (API 23) or higher
- iOS 12.0 or higher
- A running Open-WebUI instance

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/conduit.git
cd conduit
```

2. Install dependencies:
```bash
flutter pub get
```

3. Generate code:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

4. Run the app:
```bash
# For iOS
flutter run -d ios

# For Android
flutter run -d android
```

## Building for Release

### Android
```bash
flutter build apk --release
# or for App Bundle
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Configuration

### Android
The app requires the following permissions:
- Internet access
- Microphone (for voice input)
- Camera (for taking photos)
- Storage (for file selection)

### iOS
The app will request permissions for:
- Microphone access (voice input)
- Speech recognition
- Camera access
- Photo library access

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
- Prefer ICU plural/select syntax in ARB for quantities and genders.
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

## Architecture

The app follows a clean architecture pattern with:
- **Riverpod** for state management
- **Dio** for HTTP networking
- **WebSocket** for real-time streaming
- **Flutter Secure Storage** for credential management

### Project Structure
```
lib/
├── core/
│   ├── models/         # Data models
│   ├── services/       # API and storage services
│   ├── providers/      # Global state providers
│   └── utils/          # Utility functions
├── features/
│   ├── auth/           # Authentication feature
│   ├── chat/           # Chat interface feature
│   ├── server/         # Server connection feature
│   └── settings/       # Settings feature
└── shared/
    ├── theme/          # App theming
    ├── widgets/        # Shared widgets
    └── utils/          # Shared utilities
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the GPL3 License - see the LICENSE file for details.

## Acknowledgments

- Open-WebUI team for creating an amazing self-hosted AI interface
- Flutter team for the excellent mobile framework
- All contributors and users of Conduit

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/cogwheel0/conduit/issues) page.
