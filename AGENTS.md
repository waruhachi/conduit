# Conduit - Flutter Mobile App for Open-WebUI

## Build & Test Commands
```bash
flutter pub get                                    # Install dependencies
flutter pub run build_runner build --delete-conflicting-outputs  # Generate code
flutter analyze                                     # Run static analysis
flutter run -d ios/android                        # Run debug build
flutter build apk --release                       # Build Android release
flutter build ipa --release                       # Build iOS release
```

## Code Style Guidelines
- **State Management**: Use Riverpod providers in `providers/` folders
- **Architecture**: Follow clean architecture - `core/`, `features/`, `shared/`
- **Imports**: Group by package/relative, use absolute paths for project files
- **Models**: Use Freezed for data classes with `.freezed.dart` and `.g.dart` generated files
- **Error Handling**: Use ApiErrorHandler and error interceptors, avoid print statements
- **Naming**: snake_case files, PascalCase classes, camelCase methods/variables
- **Async**: Prefer async/await over raw Futures, handle errors with try-catch
- **Widgets**: Separate presentation (widgets/) from business logic (services/)
- **UI Design**: Use AppTheme colors/styles and ConduitThemeExtension for consistent design
- **Dependencies**: Check pubspec.yaml before adding packages - prefer existing solutions