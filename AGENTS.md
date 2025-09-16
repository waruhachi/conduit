# Repository Guidelines

## Project Structure & Module Organization
- `lib/` hosts Flutter code: `core/` for services, `features/` for screens and flows, `shared/` for reusable UI, `l10n/` for generated localization, and `main.dart` as the bootstrap entry.
- `assets/` contains bundled media referenced in `pubspec.yaml`; platform bits live inside `android/` and `ios/`. Release collateral is under `fastlane/`, while helper scripts sit in `scripts/`.

## Build, Test, and Development Commands
- `flutter pub get` installs pub dependencies after manifest edits.
- `flutter pub run build_runner build --delete-conflicting-outputs` regenerates serializers and other codegen output.
- `flutter run -d <device>` launches a debug build against an emulator or physical device (`-d ios`, `-d android`).
- `flutter analyze` executes static analysis checks; fix warnings before committing.
- `flutter build apk --release`, `flutter build appbundle --release`, and `flutter build ios --release` assemble store packages.
- `./scripts/release.sh` orchestrates the tagged release workflow once CI succeeds.

## Coding Style & Naming Conventions
- Use Flutter defaults: two-space indentation, `lowerCamelCase` for members, `UpperCamelCase` for types, and snake_case filenames across `lib/` and `test/`.
- Format code with `dart format .` and rely on `flutter analyze` to enforce `package:flutter_lints` (see `analysis_options.yaml`). Avoid `print`; prefer injected loggers or platform channels.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`) as in existing history. Keep subject lines ≤72 characters and add context in the body when behavior changes.
- Pull requests should outline the change, link issues, and list manual validation steps. Attach screenshots or recordings for UI updates.
- Rebase onto `main`, rerun codegen, and ensure CI is green before requesting review. Delete obsolete assets and localization strings in the same patch when touched.

## Localization & Configuration Notes
- Update generated delegates in `lib/l10n/` via Flutter’s localization toolchain (`flutter gen-l10n` from IDE or pub). Commit regenerated files with the feature change.
- Keep environment secrets outside source control; configuration surfaces and self-hosted setup notes live in `docs/`.
