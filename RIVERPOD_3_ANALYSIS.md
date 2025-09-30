# Riverpod 3.0 Alignment Analysis

## Executive Summary

The Conduit codebase is **well-aligned** with Riverpod 3.0 best practices. The project has already migrated to the new API and is using code generation in key areas. However, there are opportunities for improvement to achieve **full consistency** and leverage all Riverpod 3.0 features.

**Overall Grade: B+ (85/100)**

✅ **Strengths:**
- Already using Riverpod 3.0 packages
- No legacy providers (`StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider`)
- Using `@Riverpod` annotation with code generation for complex providers
- Proper use of `Notifier` and `AsyncNotifier` classes
- Good use of `ref.mounted` checks in async operations
- Proper `keepAlive` management for singleton providers

⚠️ **Areas for Improvement:**
- Mixed approach (code generation vs manual providers)
- Missing `riverpod_lint` for enhanced static analysis
- Some providers could benefit from code generation
- Inconsistent provider organization

---

## Current State Analysis

### 1. Package Dependencies ✅

```yaml
dependencies:
  flutter_riverpod: ^3.0.0          # ✅ Correct
  riverpod_annotation: ^3.0.0       # ✅ Correct

dev_dependencies:
  riverpod_generator: ^3.0.0        # ✅ Correct
  riverpod_lint: NOT PRESENT        # ⚠️ Missing
```

### 2. Provider Patterns

#### ✅ **Good: Code Generation Pattern**

Found in: `lib/core/auth/auth_state_manager.dart`, `lib/core/providers/app_providers.dart`

```dart
@Riverpod(keepAlive: true)
class AuthStateManager extends _$AuthStateManager {
  @override
  Future<AuthState> build() async {
    await _initialize();
    return _current;
  }
  
  // ... methods
}
```

**Benefits:**
- Type-safe
- Automatic provider generation
- Better refactoring support
- Family and autoDispose modifiers handled automatically

#### ⚠️ **Mixed: Manual NotifierProvider Pattern**

Found in: `lib/core/providers/app_providers.dart`, `lib/features/chat/providers/chat_providers.dart`

```dart
// Manual declaration
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  late final OptimizedStorageService _storage;

  @override
  ThemeMode build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    final storedMode = _storage.getThemeMode();
    // ...
    return ThemeMode.system;
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _storage.setThemeMode(mode.toString());
  }
}
```

**Issues:**
- Inconsistent with code generation approach
- More boilerplate
- Harder to add modifiers (family, autoDispose) later

### 3. Ref.mounted Usage ✅

**Good usage found in multiple files:**

```dart
// lib/core/providers/app_providers.dart
if (!ref.mounted) return;

// lib/core/services/settings_service.dart
if (!ref.mounted) {
  return;
}
```

**Recommendation:** Continue this pattern and apply it more broadly.

### 4. Analysis Options ⚠️

Current `analysis_options.yaml` is missing Riverpod-specific lints:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    avoid_print: true
```

**Missing:**
- `riverpod_lint` custom lints
- Provider-specific rules

---

## Detailed Recommendations

### 🔴 **Priority 1: Add riverpod_lint**

**Impact:** High | **Effort:** Low | **Risk:** None

Add the `riverpod_lint` package to catch common Riverpod mistakes at compile time.

#### Changes Required:

**1. Update `pubspec.yaml`:**

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.7.1
  freezed: ^3.2.0
  json_serializable: ^6.11.1
  flutter_native_splash: ^2.4.6
  riverpod_generator: ^3.0.0
  riverpod_lint: ^3.0.0  # ADD THIS
  custom_lint: ^0.8.0    # REQUIRED FOR riverpod_lint
```

**2. Update `analysis_options.yaml`:**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  plugins:
    - custom_lint

linter:
  rules:
    avoid_print: true
```

**3. Run:**

```bash
dart pub get
dart run custom_lint
```

**Benefits:**
- Catches `ref` usage outside widgets/providers
- Warns about missing `ref.mounted` checks
- Detects provider misuse patterns
- Automatic quick-fixes for common issues

---

### 🟡 **Priority 2: Standardize on Code Generation**

**Impact:** Medium | **Effort:** Medium | **Risk:** Low

Convert manual `NotifierProvider` declarations to use `@riverpod` annotation for consistency.

#### Files to Refactor:

1. **`lib/core/providers/app_providers.dart`**
   - `themeModeProvider` / `ThemeModeNotifier`
   - `localeProvider` / `LocaleNotifier`
   - `selectedModelProvider` / `SelectedModelNotifier`
   - `isManualModelSelectionProvider` / `IsManualModelSelectionNotifier`
   - `searchQueryProvider` / `SearchQueryNotifier`
   - `activeConversationProvider` / `ActiveConversationNotifier`
   - `reviewerModeProvider` / `ReviewerModeNotifier`

2. **`lib/features/chat/providers/chat_providers.dart`**
   - `chatMessagesProvider` / `ChatMessagesNotifier`
   - `isLoadingConversationProvider` / `IsLoadingConversationNotifier`
   - `prefilledInputTextProvider` / `PrefilledInputTextNotifier`
   - `inputFocusTriggerProvider` / `InputFocusTriggerNotifier`
   - `composerHasFocusProvider` / `ComposerFocusNotifier`
   - Multiple other simple notifiers

#### Example Refactoring:

**Before (Manual):**

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

**After (Code Generation):**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_providers.g.dart';

@riverpod
class ThemeMode extends _$ThemeMode {
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

// Usage changes from:
// ref.watch(themeModeProvider)
// ref.read(themeModeProvider.notifier).setTheme(mode)

// To:
// ref.watch(themeModeProvider)
// ref.read(themeModeProvider.notifier).setTheme(mode)
// (Same API!)
```

**Benefits:**
- Consistent codebase
- Less boilerplate
- Better IDE support
- Easier to add `family` or `autoDispose` modifiers later

---

### 🟡 **Priority 3: Optimize Provider Families**

**Impact:** Medium | **Effort:** Low | **Risk:** None

Some `FutureProvider.family` can benefit from better caching and disposal strategies.

#### Example: `loadConversationProvider`

**Current:**

```dart
final loadConversationProvider = FutureProvider.family<Conversation, String>((
  ref,
  conversationId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No API service available');
  }
  // ...
});
```

**Recommendation:**

```dart
@riverpod
Future<Conversation> loadConversation(
  LoadConversationRef ref,
  String conversationId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No API service available');
  }
  
  // Automatic disposal when no longer used
  // Better caching behavior
  final conversation = await api.getConversation(conversationId);
  
  return conversation;
}
```

---

### 🟢 **Priority 4: Improve AsyncValue Handling**

**Impact:** Low | **Effort:** Low | **Risk:** None

Some providers use `maybeWhen` where `when` might be more appropriate for exhaustive handling.

#### Example from `lib/features/auth/providers/unified_auth_providers.dart`:

**Current:**

```dart
final isAuthenticatedProvider2 = Provider<bool>((ref) {
  final authState = ref.watch(authStateManagerProvider);
  return authState.maybeWhen(
    data: (state) => state.isAuthenticated,
    orElse: () => false,
  );
});
```

**Better:**

```dart
final isAuthenticatedProvider2 = Provider<bool>((ref) {
  final authState = ref.watch(authStateManagerProvider);
  return authState.when(
    data: (state) => state.isAuthenticated,
    loading: () => false,
    error: (_, __) => false,
  );
});
```

**Benefits:**
- Explicit handling of all states
- Better error visibility
- Compiler-enforced exhaustiveness

---

### 🟢 **Priority 5: Add Provider Documentation**

**Impact:** Low | **Effort:** Low | **Risk:** None

Add dartdoc comments to providers explaining their purpose and refresh behavior.

**Example:**

```dart
/// Manages the current theme mode (light/dark/system).
/// 
/// Persists the selection using [OptimizedStorageService].
/// This provider is kept alive for the app lifetime.
@riverpod
class ThemeMode extends _$ThemeMode {
  // ...
}

/// The currently active conversation being displayed in the chat view.
/// 
/// Set to `null` when no conversation is active (e.g., on the home screen).
/// Watching this provider will trigger a rebuild when the conversation changes.
@riverpod
class ActiveConversation extends _$ActiveConversation {
  // ...
}
```

---

## Migration Plan

### Phase 1: Low-Risk Improvements (Week 1)

1. ✅ Add `riverpod_lint` and `custom_lint` packages
2. ✅ Update `analysis_options.yaml`
3. ✅ Run linter and fix any immediate issues
4. ✅ Add provider documentation

**Estimated Time:** 4-6 hours  
**Risk Level:** 🟢 Low

### Phase 2: Code Generation Migration (Week 2-3)

1. ⚠️ Convert simple `Notifier` classes to `@riverpod` (low risk)
   - Start with leaf nodes (no dependents)
   - Test thoroughly after each conversion
2. ⚠️ Convert `Provider` declarations to `@riverpod` functions
3. ⚠️ Regenerate code with `build_runner`
4. ⚠️ Update all references (IDE should help with renames)

**Estimated Time:** 16-24 hours  
**Risk Level:** 🟡 Medium

### Phase 3: Optimization (Week 4)

1. 🔵 Optimize `FutureProvider.family` patterns
2. 🔵 Improve `AsyncValue` handling
3. 🔵 Add caching strategies where appropriate
4. 🔵 Review and optimize `keepAlive` usage

**Estimated Time:** 8-12 hours  
**Risk Level:** 🟢 Low

---

## Testing Strategy

### Before Each Change:

```bash
# 1. Ensure all tests pass
flutter test

# 2. Run code generation
dart run build_runner build --delete-conflicting-outputs

# 3. Run custom lint
dart run custom_lint

# 4. Analyze code
flutter analyze

# 5. Manual testing on at least 2 platforms (iOS + Android)
flutter run
```

### After Migration:

1. **Functional Testing:**
   - Test all auth flows (login, logout, token refresh)
   - Test chat functionality
   - Test settings persistence
   - Test navigation flows

2. **Performance Testing:**
   - Monitor build times
   - Check app startup time
   - Profile provider rebuilds (DevTools)

3. **Regression Testing:**
   - Run full test suite
   - Test on physical devices
   - Check for memory leaks

---

## Code Examples

### Example 1: Simple Notifier Migration

**File:** `lib/features/chat/providers/chat_providers.dart`

**Before:**

```dart
final isLoadingConversationProvider =
    NotifierProvider<IsLoadingConversationNotifier, bool>(
      IsLoadingConversationNotifier.new,
    );

class IsLoadingConversationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
```

**After:**

```dart
@riverpod
class IsLoadingConversation extends _$IsLoadingConversation {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

// Usage remains the same:
// ref.watch(isLoadingConversationProvider)
// ref.read(isLoadingConversationProvider.notifier).set(true)
```

### Example 2: Provider to Function

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

// Usage remains identical:
// ref.watch(serverConfigsProvider)
// ref.read(serverConfigsProvider.future)
```

### Example 3: Keep Alive Provider

**Before:**

```dart
@Riverpod(keepAlive: true)
class AuthStateManager extends _$AuthStateManager {
  // ...
}
```

**After (same - already correct!):**

```dart
@Riverpod(keepAlive: true)
class AuthStateManager extends _$AuthStateManager {
  // ...
}
```

---

## Potential Issues & Solutions

### Issue 1: Breaking Changes

**Problem:** Renaming providers may break existing code.

**Solution:**
1. Use IDE's "Find and Replace" with regex
2. Create deprecation aliases during transition
3. Update incrementally, one provider at a time

```dart
// Temporary compatibility
@Deprecated('Use themeModeProvider instead')
final oldThemeModeProvider = themeModeProvider;
```

### Issue 2: Complex State Logic

**Problem:** Some `Notifier` classes have complex initialization.

**Solution:** Code generation supports complex logic—no changes needed!

```dart
@riverpod
class ChatMessages extends _$ChatMessages {
  StreamSubscription? _messageStream;
  ProviderSubscription? _conversationListener;
  // ... all existing fields and initialization work fine
  
  @override
  List<ChatMessage> build() {
    if (!_initialized) {
      _initialized = true;
      _conversationListener = ref.listen(activeConversationProvider, /* ... */);
    }
    // ... existing logic
  }
}
```

### Issue 3: Build Runner Performance

**Problem:** Code generation might slow down development.

**Solution:**
1. Use `watch` mode during development:
   ```bash
   dart run build_runner watch --delete-conflicting-outputs
   ```
2. Exclude generated files from version control (already done)
3. Consider CI/CD optimizations for parallel builds

---

## Performance Considerations

### Current Performance: ✅ Good

The codebase already uses:
- `keepAlive` for singleton providers
- `ref.mounted` checks for async operations
- Proper disposal in `ref.onDispose`

### After Migration: ✅ Better

Code generation will:
- Reduce runtime overhead (compile-time generation)
- Enable better tree-shaking
- Improve IDE performance with generated code

**Expected Impact:**
- Build time: +5-10 seconds (one-time per build)
- Runtime performance: Neutral to +2% faster
- Memory usage: Neutral
- Developer experience: Significantly better

---

## Conflict with AGENTS.md Rules

### Current Rule in AGENTS.md:

```markdown
### State Management
* **Built-in Solutions:** Prefer Flutter's built-in state management solutions.
  Do not use a third-party package unless explicitly requested.
```

### Recommendation: Update AGENTS.md

The project has **already adopted Riverpod**, which contradicts this rule. The rule should be updated to reflect the current architecture:

```markdown
### State Management
* **Riverpod:** This project uses Riverpod 3.0 for state management.
* **Code Generation:** Prefer using `@riverpod` annotation with code generation 
  for all new providers.
* **Notifier Classes:** Use `Notifier` and `AsyncNotifier` for mutable state.
* **Provider Functions:** Use `@riverpod` functions for computed/derived state.
* **Keep Alive:** Use `@Riverpod(keepAlive: true)` for singletons and app-wide state.
* **Ref.mounted:** Always check `ref.mounted` before state updates in async operations.
```

---

## Resources

### Official Riverpod 3.0 Documentation

- [Riverpod 3.0 Migration Guide](https://riverpod.dev/docs/3.0_migration)
- [Code Generation Guide](https://riverpod.dev/docs/concepts/about_code_generation)
- [Riverpod Lint Rules](https://riverpod.dev/docs/concepts/about_riverpod_lint)

### Community Resources

- [Riverpod 3.0 Announcement](https://medium.com/@ishuprabhakar/riverpod-3-0-1c0e247bfb2f)
- [Migration Tutorial](https://codewithandrea.com/articles/flutter-state-management-riverpod/)

---

## Conclusion

The Conduit codebase is **in good shape** regarding Riverpod 3.0 alignment. The main improvements are:

1. **Add `riverpod_lint`** for better static analysis (Priority 1)
2. **Standardize on code generation** for consistency (Priority 2)
3. **Optimize provider patterns** where applicable (Priority 3)

**Total Estimated Effort:** 28-42 hours  
**Risk Level:** 🟡 Medium  
**Expected Benefits:** High (better maintainability, consistency, developer experience)

The migration can be done incrementally with minimal risk if following the phased approach outlined above.
