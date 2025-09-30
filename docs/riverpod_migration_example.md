# Riverpod Migration Example

## Example: Migrating SearchQueryNotifier

This example shows step-by-step how to migrate a simple provider from manual declaration to code generation.

---

## Current Code (Manual NotifierProvider)

**File:** `lib/core/providers/app_providers.dart` (lines ~1200-1209)

```dart
// Manual provider declaration
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}
```

**Usage in code:**

```dart
// Reading value
final query = ref.watch(searchQueryProvider);

// Updating value
ref.read(searchQueryProvider.notifier).set('new search');
```

---

## Migrated Code (Code Generation)

**File:** `lib/core/providers/app_providers.dart`

### Step 1: Add annotation and extend generated class

```dart
@riverpod
class SearchQuery extends _$SearchQuery {  // Note: Class name changes
  @override
  String build() => '';

  void set(String query) => state = query;
}
```

### Step 2: Run build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

This generates `app_providers.g.dart` with:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$searchQueryHash() => r'...';

/// See also [SearchQuery].
@ProviderFor(SearchQuery)
final searchQueryProvider = AutoDisposeNotifierProvider<SearchQuery, String>.internal(
  SearchQuery.new,
  name: r'searchQueryProvider',
  debugGetCreateSourceHash: _$searchQueryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$SearchQuery = AutoDisposeNotifier<String>;
```

### Step 3: Update imports (if needed)

No changes needed! The provider name stays the same: `searchQueryProvider`

### Step 4: Usage remains identical

```dart
// Reading value - NO CHANGE
final query = ref.watch(searchQueryProvider);

// Updating value - NO CHANGE
ref.read(searchQueryProvider.notifier).set('new search');
```

---

## Benefits of Migration

### Before (Manual)

```dart
// 8 lines of boilerplate
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}
```

**Issues:**
- ❌ More verbose
- ❌ Need to manually create provider variable
- ❌ Easy to forget to update provider declaration when class changes
- ❌ No automatic dependency tracking

### After (Code Generation)

```dart
// 6 lines, cleaner
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}
```

**Benefits:**
- ✅ Less boilerplate
- ✅ Provider auto-generated
- ✅ Type-safe
- ✅ Better IDE support
- ✅ Automatic dependency tracking
- ✅ Easier to add `family` or modifiers later

---

## More Complex Example: ThemeModeNotifier

### Current Code (Manual)

```dart
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  late final OptimizedStorageService _storage;

  @override
  ThemeMode build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    final storedMode = _storage.getThemeMode();
    if (storedMode != null) {
      return ThemeMode.values.firstWhere(
        (e) => e.toString() == storedMode,
        orElse: () => ThemeMode.system,
      );
    }
    return ThemeMode.system;
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _storage.setThemeMode(mode.toString());
  }
}
```

### Migrated Code (Code Generation)

```dart
@riverpod
class AppThemeMode extends _$AppThemeMode {  // Renamed to avoid conflict with ThemeMode enum
  late final OptimizedStorageService _storage;

  @override
  ThemeMode build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    final storedMode = _storage.getThemeMode();
    if (storedMode != null) {
      return ThemeMode.values.firstWhere(
        (e) => e.toString() == storedMode,
        orElse: () => ThemeMode.system,
      );
    }
    return ThemeMode.system;
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _storage.setThemeMode(mode.toString());
  }
}

// Generated provider will be: appThemeModeProvider
```

**Important:** Class renamed from `ThemeModeNotifier` to `AppThemeMode` to avoid name conflict with the `ThemeMode` enum from Flutter.

### Update Usage

```dart
// Before
final mode = ref.watch(themeModeProvider);
ref.read(themeModeProvider.notifier).setTheme(ThemeMode.dark);

// After
final mode = ref.watch(appThemeModeProvider);
ref.read(appThemeModeProvider.notifier).setTheme(ThemeMode.dark);
```

**Migration tool can help:**

```bash
# Find all usages
grep -r "themeModeProvider" lib/

# Replace with IDE refactoring or:
find lib -type f -name "*.dart" -exec sed -i '' 's/themeModeProvider/appThemeModeProvider/g' {} +
```

---

## Provider Function Example

### FutureProvider to @riverpod function

**Before:**

```dart
final serverConfigsProvider = FutureProvider<List<ServerConfig>>((ref) async {
  final storage = ref.watch(optimizedStorageServiceProvider);
  return storage.getServerConfigs();
});
```

**After:**

```dart
@riverpod
Future<List<ServerConfig>> serverConfigs(ServerConfigsRef ref) async {
  final storage = ref.watch(optimizedStorageServiceProvider);
  return storage.getServerConfigs();
}

// Generated provider name: serverConfigsProvider (same!)
```

**Usage - NO CHANGE:**

```dart
final configs = ref.watch(serverConfigsProvider);
// or
final configs = await ref.read(serverConfigsProvider.future);
```

---

## Family Provider Example

### Before (Manual)

```dart
final loadConversationProvider = FutureProvider.family<Conversation, String>((
  ref,
  conversationId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No API service available');
  }
  return await api.getConversation(conversationId);
});
```

### After (Code Generation)

```dart
@riverpod
Future<Conversation> loadConversation(
  LoadConversationRef ref,
  String conversationId,  // Family parameter
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No API service available');
  }
  return await api.getConversation(conversationId);
}

// Usage stays the same!
// ref.watch(loadConversationProvider(conversationId))
```

**Benefits:**
- ✅ Automatic `.family` modifier handling
- ✅ Type-safe parameters
- ✅ Better parameter completion in IDE
- ✅ Can add multiple parameters easily

---

## Keep Alive Example

### Before

```dart
@Riverpod(keepAlive: true)
class AuthStateManager extends _$AuthStateManager {
  // ...
}
```

### After

**No change needed!** Already using code generation correctly. ✅

---

## Migration Checklist

For each provider to migrate:

- [ ] Identify the provider type (Notifier, AsyncNotifier, function)
- [ ] Check for name conflicts (e.g., `ThemeModeNotifier` vs `ThemeMode`)
- [ ] Add `@riverpod` annotation
- [ ] Change class to extend `_$ClassName`
- [ ] Remove manual provider declaration
- [ ] Run `dart run build_runner build`
- [ ] Update all usages (IDE refactoring recommended)
- [ ] Test the provider functionality
- [ ] Commit the change

---

## Testing After Migration

### Unit Test Example

**Before:**

```dart
test('searchQuery updates correctly', () {
  final container = ProviderContainer();
  
  expect(container.read(searchQueryProvider), '');
  
  container.read(searchQueryProvider.notifier).set('test');
  
  expect(container.read(searchQueryProvider), 'test');
});
```

**After:**

```dart
test('searchQuery updates correctly', () {
  final container = ProviderContainer();
  
  // Same test code - no changes needed!
  expect(container.read(searchQueryProvider), '');
  
  container.read(searchQueryProvider.notifier).set('test');
  
  expect(container.read(searchQueryProvider), 'test');
});
```

Tests remain identical! ✅

---

## Common Pitfalls

### 1. Class Name Conflicts

**Problem:**

```dart
@riverpod
class ThemeMode extends _$ThemeMode {  // ❌ Conflicts with Flutter's ThemeMode
  // ...
}
```

**Solution:**

```dart
@riverpod
class AppThemeMode extends _$AppThemeMode {  // ✅ Unique name
  // ...
}
```

### 2. Forgetting to Run Build Runner

**Problem:** After adding `@riverpod`, code doesn't compile.

```
Error: The getter '_$SearchQuery' isn't defined for the class 'SearchQuery'.
```

**Solution:**

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Mixing Manual and Generated Providers

**Problem:** Some providers use `@riverpod`, others use manual `NotifierProvider`.

**Solution:** Be consistent! Migrate all providers in a file together to maintain consistency.

---

## IDE Support

### VS Code

Add to `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build_runner watch",
      "type": "shell",
      "command": "dart run build_runner watch --delete-conflicting-outputs",
      "isBackground": true,
      "problemMatcher": []
    }
  ]
}
```

Run with `Cmd+Shift+P` → "Tasks: Run Task" → "build_runner watch"

### Android Studio / IntelliJ

1. Run → Edit Configurations
2. Add new "Shell Script" configuration
3. Script text: `dart run build_runner watch --delete-conflicting-outputs`
4. Working directory: `$ProjectFileDir$`

---

## Summary

**Effort per provider:** ~5-10 minutes  
**Risk level:** 🟢 Low (tests verify behavior)  
**Benefit:** High (consistency, maintainability, developer experience)

**Recommended order:**

1. Start with simple `Notifier` classes (like `SearchQueryNotifier`)
2. Move to `FutureProvider` functions
3. Then tackle complex `AsyncNotifier` classes
4. Keep `@Riverpod(keepAlive: true)` providers for last (already correct)

**Total providers to migrate:** ~30-40 (based on codebase analysis)  
**Estimated total time:** 5-8 hours spread across multiple sessions
