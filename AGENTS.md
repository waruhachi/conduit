AGENTS GUIDE FOR THIS REPO

Build, lint, test
- Install: flutter pub get
- Generate code (required for freezed/json): flutter pub run build_runner build --delete-conflicting-outputs
- Analyze (lints): flutter analyze
- Format: dart format . --fix
- Run app: flutter run -d ios | -d android
- Build release: flutter build apk --release; flutter build appbundle --release; flutter build ios --release
- Run all tests: flutter test
- Run single test file: flutter test path/to/test.dart
- Run single test by name: flutter test path/to/test.dart --name "test name substring"

Code style
- Use Flutter lints (analysis_options.yaml includes package:flutter_lints/flutter.yaml); avoid print, prefer logging/services. Fix analyzer warnings before merging.
- Imports: prefer relative imports within lib/, package:conduit for cross-feature access. Group as: dart:*, package:*, third-party, project; alphabetize within groups; no unused imports.
- Formatting: run dart format .; keep lines readable (< 100–120 cols). No trailing whitespace. Use const where possible.
- Types and null safety: use sound null-safety; avoid dynamic; prefer explicit types for public APIs; use final for immutables.
- Naming: lowerCamelCase for variables/functions, UpperCamelCase for classes/types; file names snake_case.dart; private members with leading _.
- State management: use Riverpod providers in features/* and core/providers; avoid global singletons except services injected via providers.
- Data models: use freezed/json_serializable where applicable; regenerate with build_runner after model changes.
- Error handling: never swallow errors; convert Dio/network/storage errors into domain errors via core/error/* (api_error_handler.dart, user_friendly_error_handler.dart). Surface user-safe messages; log details via services.
- Async/streams: cancel subscriptions; handle connectivity changes via core/services; prefer Future<void> return for async methods.
- UI: keep widgets small and pure; move side effects to controllers/providers; respect theme in shared/theme/*; follow design tokens in shared/theme/app_theme.dart and shared/theme/theme_extensions.dart (Spacing, AppBorderRadius, Elevation, ConduitShadows, AppTypography).

Repo conventions
- Follow CI versions from .github/workflows/release.yml (Flutter stable 3.32.5, Java 21). Keep pubspec constraints aligned.
- No Cursor/Copilot rule files present. If added later (.cursor/rules or .github/copilot-instructions.md), mirror their guidance here.
