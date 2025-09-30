# Priority 2 Migration Plan - Code Generation Standardization

**Created:** September 30, 2025  
**Status:** 📋 Planning Phase  
**Estimated Effort:** 16-24 hours  
**Risk Level:** 🟡 Medium

---

## Table of Contents

1. [Overview](#overview)
2. [Providers to Migrate](#providers-to-migrate)
3. [Migration Strategy](#migration-strategy)
4. [Step-by-Step Instructions](#step-by-step-instructions)
5. [Testing Plan](#testing-plan)
6. [Rollback Plan](#rollback-plan)

---

## Overview

### Goals

Convert all manual `NotifierProvider` and `FutureProvider` declarations to use `@riverpod` annotation for:
- ✅ Consistency across the codebase
- ✅ Less boilerplate
- ✅ Better IDE support and type safety
- ✅ Easier future modifications (family, autoDispose, etc.)
- ✅ Automatic dependency tracking

### Scope

**Total Providers to Migrate:** 39 providers across 7 files

**Files Affected:**
1. `lib/core/providers/app_providers.dart` (26 providers)
2. `lib/features/chat/providers/chat_providers.dart` (5 providers)
3. `lib/core/services/settings_service.dart` (1 provider)
4. `lib/core/services/animation_service.dart` (1 provider)
5. `lib/features/chat/services/message_batch_service.dart` (1 provider)
6. `lib/features/prompts/providers/prompts_providers.dart` (1 provider)
7. `lib/features/tools/providers/tools_providers.dart` (1 provider)
8. `lib/shared/widgets/offline_indicator.dart` (1 provider)
9. `lib/features/chat/services/voice_input_service.dart` (1 provider)

---

## Providers to Migrate

### Category A: Simple Notifier Classes (Low Risk, High Priority)

These are straightforward state holders with minimal logic.

#### 1. `searchQueryProvider` / `SearchQueryNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 1200-1209)
**Complexity:** 🟢 Simple
**Usage Count:** ~5-10 files
**Dependencies:** None

**Current:**
```dart
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}
```

**After:**
```dart
@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

// Generated provider name: searchQueryProvider ✅ (same!)
```

**Migration Notes:**
- Class renamed from `SearchQueryNotifier` to `SearchQuery` (convention)
- Provider name stays identical
- No usage changes required

---

#### 2. `selectedModelProvider` / `SelectedModelNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 618-635)
**Complexity:** 🟢 Simple
**Usage Count:** ~15-20 files
**Dependencies:** None

**Current:**
```dart
final selectedModelProvider = NotifierProvider<SelectedModelNotifier, Model?>(
  SelectedModelNotifier.new,
);

class SelectedModelNotifier extends Notifier<Model?> {
  @override
  Model? build() => null;

  void set(Model? model) => state = model;

  void clear() => state = null;
}
```

**After:**
```dart
@riverpod
class SelectedModel extends _$SelectedModel {
  @override
  Model? build() => null;

  void set(Model? model) => state = model;

  void clear() => state = null;
}

// Generated provider name: selectedModelProvider ✅
```

---

#### 3. `isManualModelSelectionProvider` / `IsManualModelSelectionNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 623-642)
**Complexity:** 🟢 Simple
**Usage Count:** ~3-5 files
**Dependencies:** None

**Current:**
```dart
final isManualModelSelectionProvider =
    NotifierProvider<IsManualModelSelectionNotifier, bool>(
      IsManualModelSelectionNotifier.new,
    );

class IsManualModelSelectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}
```

**After:**
```dart
@riverpod
class IsManualModelSelection extends _$IsManualModelSelection {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

// Generated provider name: isManualModelSelectionProvider ✅
```

---

#### 4. `reviewerModeProvider` / `ReviewerModeNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 1415-1430)
**Complexity:** 🟢 Simple (has storage dependency)
**Usage Count:** ~5-8 files
**Dependencies:** `optimizedStorageServiceProvider`

**Current:**
```dart
final reviewerModeProvider = NotifierProvider<ReviewerModeNotifier, bool>(
  ReviewerModeNotifier.new,
);

class ReviewerModeNotifier extends Notifier<bool> {
  late final OptimizedStorageService _storage;

  @override
  bool build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    return _storage.getReviewerMode();
  }

  void set(bool value) {
    state = value;
    _storage.setReviewerMode(value);
  }
}
```

**After:**
```dart
@riverpod
class ReviewerMode extends _$ReviewerMode {
  late final OptimizedStorageService _storage;

  @override
  bool build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    return _storage.getReviewerMode();
  }

  void set(bool value) {
    state = value;
    _storage.setReviewerMode(value);
  }
}

// Generated provider name: reviewerModeProvider ✅
```

---

#### 5. `batchModeProvider` / `BatchModeNotifier`
**File:** `lib/features/chat/services/message_batch_service.dart` (lines 532-540)
**Complexity:** 🟢 Simple
**Usage Count:** ~3-5 files
**Dependencies:** None

---

#### 6. `reducedMotionProvider` / `ReducedMotionNotifier`
**File:** `lib/core/services/animation_service.dart` (lines 211-225)
**Complexity:** 🟢 Simple (has storage dependency)
**Usage Count:** ~5-10 files
**Dependencies:** `optimizedStorageServiceProvider`

---

### Category B: Storage-Backed Notifiers (Low-Medium Risk)

These manage persistent state with storage dependencies.

#### 7. `themeModeProvider` / `ThemeModeNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 71-95)
**Complexity:** 🟡 Medium
**Usage Count:** ~10-15 files
**Dependencies:** `optimizedStorageServiceProvider`

**Current:**
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

**After:**
```dart
@riverpod
class AppThemeMode extends _$AppThemeMode {
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

// Generated provider name: appThemeModeProvider
```

**⚠️ Important:**
- Class renamed from `ThemeModeNotifier` to `AppThemeMode` to avoid conflict with Flutter's `ThemeMode` enum
- Provider name changes from `themeModeProvider` to `appThemeModeProvider`
- **Requires bulk find-replace across codebase**

**Migration Command:**
```bash
# Find all usages first
grep -r "themeModeProvider" lib/ --exclude="*.g.dart" | wc -l

# Replace (use IDE refactoring or sed)
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/themeModeProvider/appThemeModeProvider/g' {} +
```

---

#### 8. `localeProvider` / `LocaleNotifier`
**File:** `lib/core/providers/app_providers.dart` (lines 98-119)
**Complexity:** 🟢 Simple (async method)
**Usage Count:** ~8-12 files
**Dependencies:** `optimizedStorageServiceProvider`

**Current:**
```dart
final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);

class LocaleNotifier extends Notifier<Locale?> {
  late final OptimizedStorageService _storage;

  @override
  Locale? build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    final code = _storage.getLocaleCode();
    if (code != null && code.isNotEmpty) {
      return Locale(code);
    }
    return null; // system default
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await _storage.setLocaleCode(locale?.languageCode);
  }
}
```

**After:**
```dart
@riverpod
class AppLocale extends _$AppLocale {
  late final OptimizedStorageService _storage;

  @override
  Locale? build() {
    _storage = ref.watch(optimizedStorageServiceProvider);
    final code = _storage.getLocaleCode();
    if (code != null && code.isNotEmpty) {
      return Locale(code);
    }
    return null; // system default
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await _storage.setLocaleCode(locale?.languageCode);
  }
}

// Generated provider name: appLocaleProvider
```

**⚠️ Important:**
- Class renamed from `LocaleNotifier` to `AppLocale` to avoid potential conflicts
- Provider name changes from `localeProvider` to `appLocaleProvider`
- **Requires bulk find-replace across codebase**

---

#### 9. `appSettingsProvider` / `AppSettingsNotifier`
**File:** `lib/core/services/settings_service.dart` (lines 407-500+)
**Complexity:** 🔴 Complex (large class with many methods)
**Usage Count:** ~20-30 files (high usage!)
**Dependencies:** `optimizedStorageServiceProvider`, `apiServiceProvider`

**Migration Strategy:**
- ⚠️ Save for **last** due to high complexity and usage
- Test extensively before committing
- Consider splitting into smaller providers if possible

---

### Category C: Chat-Specific Notifiers (Medium Risk)

#### 10. `isLoadingConversationProvider` / `IsLoadingConversationNotifier`
**File:** `lib/features/chat/providers/chat_providers.dart` (lines 30-57)
**Complexity:** 🟢 Simple
**Usage Count:** ~5-8 files

**After:**
```dart
@riverpod
class IsLoadingConversation extends _$IsLoadingConversation {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

// Generated provider name: isLoadingConversationProvider ✅
```

---

#### 11. `prefilledInputTextProvider` / `PrefilledInputTextNotifier`
**File:** `lib/features/chat/providers/chat_providers.dart` (lines 36-66)
**Complexity:** 🟢 Simple
**Usage Count:** ~3-5 files

**After:**
```dart
@riverpod
class PrefilledInputText extends _$PrefilledInputText {
  @override
  String? build() => null;

  void set(String? value) => state = value;

  void clear() => state = null;
}

// Generated provider name: prefilledInputTextProvider ✅
```

---

#### 12. `inputFocusTriggerProvider` / `InputFocusTriggerNotifier`
**File:** `lib/features/chat/providers/chat_providers.dart` (lines 42-79)
**Complexity:** 🟢 Simple
**Usage Count:** ~3-5 files

**After:**
```dart
@riverpod
class InputFocusTrigger extends _$InputFocusTrigger {
  @override
  int build() => 0;

  void set(int value) => state = value;

  int increment() {
    final next = state + 1;
    state = next;
    return next;
  }
}

// Generated provider name: inputFocusTriggerProvider ✅
```

---

#### 13. `composerHasFocusProvider` / `ComposerFocusNotifier`
**File:** `lib/features/chat/providers/chat_providers.dart` (lines 48-86)
**Complexity:** 🟢 Simple
**Usage Count:** ~3-5 files

**After:**
```dart
@riverpod
class ComposerHasFocus extends _$ComposerHasFocus {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

// Generated provider name: composerHasFocusProvider ✅
```

---

#### 14. `chatMessagesProvider` / `ChatMessagesNotifier`
**File:** `lib/features/chat/providers/chat_providers.dart` (lines 24-2532)
**Complexity:** 🔴 Very Complex (2500+ lines!)
**Usage Count:** ~15-20 files (high usage!)
**Dependencies:** Many (socket, API, storage, etc.)

**Migration Strategy:**
- ⚠️ Save for **last** due to extreme complexity
- Consider refactoring into smaller providers first
- Extensive testing required

---

### Category D: FutureProvider Functions (Low-Medium Risk)

These are stateless async computations that can be easily converted.

#### 15. `serverConfigsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 122-125)
**Complexity:** 🟢 Simple
**Usage Count:** ~5-10 files

**Current:**
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

// Generated provider name: serverConfigsProvider ✅
```

---

#### 16. `activeServerProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 127-141)
**Complexity:** 🟢 Simple

**After:**
```dart
@riverpod
Future<ServerConfig?> activeServer(ActiveServerRef ref) async {
  final storage = ref.watch(optimizedStorageServiceProvider);
  final configs = await ref.watch(serverConfigsProvider.future);
  final activeId = await storage.getActiveServerId();

  if (activeId == null || configs.isEmpty) return null;

  for (final config in configs) {
    if (config.id == activeId) {
      return config;
    }
  }

  return null;
}

// Generated provider name: activeServerProvider ✅
```

---

#### 17. `currentUserProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 549-568)
**Complexity:** 🟢 Simple

**After:**
```dart
@riverpod
Future<User?> currentUser(CurrentUserRef ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return null;

  try {
    final user = await api.getCurrentUser();
    return user;
  } catch (e) {
    DebugLogger.error('current-user-failed', scope: 'user', error: e);
    return null;
  }
}

// Generated provider name: currentUserProvider ✅
```

---

#### 18. `modelsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 570-615)
**Complexity:** 🟡 Medium (has caching logic)

**After:**
```dart
@riverpod
Future<List<Model>> models(ModelsRef ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    final models = await api.getModels();
    DebugLogger.log('models-fetched', scope: 'models', data: {'count': models.length});
    return models;
  } catch (e) {
    DebugLogger.error('models-fetch-failed', scope: 'models', error: e);
    return [];
  }
}

// Generated provider name: modelsProvider ✅
```

---

#### 19. `conversationsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 722-990+)
**Complexity:** 🔴 Complex (has custom caching, listeners)
**Usage Count:** ~10-15 files

**Migration Strategy:**
- ⚠️ Medium priority (moderate complexity)
- Keep caching behavior intact
- Test conversation list loading thoroughly

---

#### 20. `defaultModelProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1020-1050)
**Complexity:** 🟢 Simple

---

#### 21. `userSettingsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1450-1465)
**Complexity:** 🟢 Simple

**After:**
```dart
@riverpod
Future<UserSettings> userSettings(UserSettingsRef ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    return UserSettings.empty();
  }

  try {
    return await api.getUserSettings();
  } catch (e) {
    DebugLogger.error('user-settings-fetch-failed', scope: 'settings', error: e);
    return UserSettings.empty();
  }
}

// Generated provider name: userSettingsProvider ✅
```

---

#### 22. `conversationSuggestionsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1468-1480)
**Complexity:** 🟢 Simple

---

#### 23. `userPermissionsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1483-1500)
**Complexity:** 🟢 Simple

---

#### 24. `foldersProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1530-1555)
**Complexity:** 🟢 Simple

---

#### 25. `userFilesProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1560-1575)
**Complexity:** 🟢 Simple

---

#### 26. `knowledgeBasesProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1605-1625)
**Complexity:** 🟢 Simple

---

#### 27. `availableVoicesProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1649-1665)
**Complexity:** 🟢 Simple

---

#### 28. `imageModelsProvider`
**File:** `lib/core/providers/app_providers.dart` (lines 1667-1680)
**Complexity:** 🟢 Simple

---

### Category E: Family Providers (Medium Risk)

#### 29. `loadConversationProvider` (family)
**File:** `lib/core/providers/app_providers.dart` (lines 995-1015)
**Complexity:** 🟡 Medium
**Usage Count:** ~5-10 files

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
  // ... fetch logic
});
```

**After:**
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
  // ... fetch logic
}

// Usage stays the same:
// ref.watch(loadConversationProvider(conversationId))
```

---

#### 30. `serverSearchProvider` (family)
**File:** `lib/core/providers/app_providers.dart` (lines 1212-1250)
**Complexity:** 🟢 Simple

**After:**
```dart
@riverpod
Future<List<Conversation>> serverSearch(
  ServerSearchRef ref,
  String query,
) async {
  if (query.trim().isEmpty) {
    return [];
  }

  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    final trimmedQuery = query.trim();
    DebugLogger.log('server-search', scope: 'search', data: {'query': trimmedQuery});
    final results = await api.searchConversations(trimmedQuery);
    return results;
  } catch (e) {
    DebugLogger.error('server-search-failed', scope: 'search', error: e);
    return [];
  }
}

// Generated provider name: serverSearchProvider ✅
```

---

#### 31. `fileContentProvider` (family)
**File:** `lib/core/providers/app_providers.dart` (lines 1579-1600)
**Complexity:** 🟢 Simple

**After:**
```dart
@riverpod
Future<String> fileContent(
  FileContentRef ref,
  String fileId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return '';

  try {
    return await api.getFileContent(fileId);
  } catch (e) {
    DebugLogger.error('file-content-fetch-failed', scope: 'files', error: e);
    return '';
  }
}

// Generated provider name: fileContentProvider ✅
```

---

### Category F: Feature-Specific Providers (Low Risk)

#### 32. `promptsListProvider`
**File:** `lib/features/prompts/providers/prompts_providers.dart` (lines 6-15)
**Complexity:** 🟢 Simple
**Usage Count:** ~2-3 files

**After:**
```dart
@riverpod
Future<List<Prompt>> promptsList(PromptsListRef ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];
  
  try {
    return await api.getPrompts();
  } catch (e) {
    return [];
  }
}

// Generated provider name: promptsListProvider ✅
```

---

#### 33. `toolsListProvider`
**File:** `lib/features/tools/providers/tools_providers.dart` (lines 5-15)
**Complexity:** 🟢 Simple
**Usage Count:** ~2-3 files

**After:**
```dart
@riverpod
Future<List<Tool>> toolsList(ToolsListRef ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];
  
  try {
    return await api.getTools();
  } catch (e) {
    return [];
  }
}

// Generated provider name: toolsListProvider ✅
```

---

#### 34. `voiceInputAvailableProvider`
**File:** `lib/features/chat/services/voice_input_service.dart` (lines 325-330)
**Complexity:** 🟢 Simple
**Usage Count:** ~2-3 files

---

### Category G: Private/Internal Providers (Low Risk)

#### 35. `_wasOfflineProvider` / `_WasOfflineNotifier`
**File:** `lib/shared/widgets/offline_indicator.dart` (lines 55-65)
**Complexity:** 🟢 Simple
**Usage Count:** 1 file (internal)

**Note:** This is a private provider (starts with `_`). Can migrate but low priority.

---

#### 36. `_conversationsCacheTimestampProvider` (internal)
**File:** `lib/core/providers/app_providers.dart` (lines 709-718)
**Complexity:** 🟢 Simple
**Usage Count:** 1-2 files (internal)

**Note:** Internal caching helper. Can migrate alongside `conversationsProvider`.

---

## Migration Strategy

### Phase 1: Simple Wins (Week 1, 4-6 hours)

Migrate simple, low-usage providers to build confidence and establish patterns.

**Targets (10 providers):**
1. ✅ `searchQueryProvider`
2. ✅ `selectedModelProvider`
3. ✅ `isManualModelSelectionProvider`
4. ✅ `reviewerModeProvider`
5. ✅ `batchModeProvider`
6. ✅ `isLoadingConversationProvider`
7. ✅ `prefilledInputTextProvider`
8. ✅ `inputFocusTriggerProvider`
9. ✅ `composerHasFocusProvider`
10. ✅ `reducedMotionProvider`

**Process:**
1. Migrate one provider
2. Run `build_runner`
3. Test manually
4. Commit
5. Repeat

**Exit Criteria:**
- All 10 providers migrated
- All tests passing
- No regressions in functionality

---

### Phase 2: FutureProvider Functions (Week 2, 6-8 hours)

Convert simple async functions to @riverpod functions.

**Targets (15 providers):**
1. ✅ `serverConfigsProvider`
2. ✅ `activeServerProvider`
3. ✅ `currentUserProvider`
4. ✅ `modelsProvider`
5. ✅ `defaultModelProvider`
6. ✅ `userSettingsProvider`
7. ✅ `conversationSuggestionsProvider`
8. ✅ `userPermissionsProvider`
9. ✅ `foldersProvider`
10. ✅ `userFilesProvider`
11. ✅ `knowledgeBasesProvider`
12. ✅ `availableVoicesProvider`
13. ✅ `imageModelsProvider`
14. ✅ `promptsListProvider`
15. ✅ `toolsListProvider`

**Process:**
1. Migrate in batches of 3-5 providers
2. Run `build_runner` after each batch
3. Test affected features
4. Commit batch

---

### Phase 3: Family Providers (Week 2, 2-3 hours)

Convert family providers to @riverpod functions with parameters.

**Targets (4 providers):**
1. ✅ `loadConversationProvider`
2. ✅ `serverSearchProvider`
3. ✅ `fileContentProvider`
4. ✅ `voiceInputAvailableProvider`

**Process:**
1. Migrate one at a time
2. Pay attention to parameter types
3. Test with different parameter values
4. Commit individually

---

### Phase 4: Storage-Backed Notifiers (Week 3, 4-6 hours)

Migrate providers that require provider name changes (breaking changes).

**Targets (2 providers + bulk replace):**
1. ⚠️ `themeModeProvider` → `appThemeModeProvider`
2. ⚠️ `localeProvider` → `appLocaleProvider`

**Process:**
1. Migrate provider definition
2. Run `build_runner`
3. **Find and replace all usages** (use IDE refactoring)
4. Run tests
5. Manual testing on all platforms
6. Commit with clear message about breaking change

**Find/Replace Commands:**
```bash
# ThemeMode migration
grep -r "themeModeProvider" lib/ --exclude="*.g.dart" | wc -l
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/themeModeProvider/appThemeModeProvider/g' {} +

# Locale migration
grep -r "localeProvider" lib/ --exclude="*.g.dart" | wc -l
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/localeProvider/appLocaleProvider/g' {} +
```

---

### Phase 5: Complex Providers (Week 4, 6-8 hours)

Migrate complex, high-usage providers with extensive testing.

**Targets (3 providers):**
1. 🔴 `conversationsProvider` (complex caching)
2. 🔴 `appSettingsProvider` (large class, high usage)
3. 🔴 `chatMessagesProvider` (extremely complex, 2500+ lines)

**Process:**
1. **Read the entire class** to understand all dependencies
2. Create a test plan covering all methods
3. Migrate the provider
4. Run `build_runner`
5. Run all tests
6. Manual testing of all affected features
7. Commit with detailed migration notes

**Extra Caution:**
- Test on physical devices (iOS + Android)
- Check for memory leaks
- Monitor performance
- Have rollback plan ready

---

### Phase 6: Internal/Private Providers (Optional, 1-2 hours)

Migrate internal providers for completeness.

**Targets (2 providers):**
1. ✅ `_wasOfflineProvider`
2. ✅ `_conversationsCacheTimestampProvider`

**Process:**
- Low priority
- Can be done as cleanup task
- No external dependencies to worry about

---

## Step-by-Step Instructions

### For Each Provider Migration

#### Step 1: Prepare

```bash
# Ensure clean git state
git status

# Ensure packages are up to date
flutter pub get

# Run tests to establish baseline
flutter test

# (Optional) Find usage count
grep -r "providerName" lib/ --exclude="*.g.dart" | wc -l
```

---

#### Step 2: Migrate the Provider

**For Notifier Classes:**

1. Add `@riverpod` annotation
2. Change class name (remove `Notifier` suffix, handle conflicts)
3. Extend `_$ClassName`
4. Remove manual provider declaration
5. Keep all methods unchanged

**For FutureProvider Functions:**

1. Add `@riverpod` annotation
2. Convert to function with `Ref` parameter
3. Add family parameters as function parameters (if applicable)
4. Keep logic unchanged

---

#### Step 3: Generate Code

```bash
dart run build_runner build --delete-conflicting-outputs
```

**Watch for:**
- Build errors (fix immediately)
- Generated file created (`.g.dart`)
- Provider name in generated code (check if it matches expected)

---

#### Step 4: Update Usages (if needed)

**For providers with name changes only:**

```bash
# Example: themeModeProvider → appThemeModeProvider
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/themeModeProvider/appThemeModeProvider/g' {} +
```

**Or use IDE:**
1. Right-click on provider name
2. Refactor → Rename
3. Enter new name
4. Preview changes
5. Apply

---

#### Step 5: Verify

```bash
# Check for compilation errors
flutter analyze

# Run linter
dart run custom_lint

# Run tests
flutter test

# Manual smoke test
flutter run
```

---

#### Step 6: Commit

```bash
git add .
git commit -m "refactor: migrate providerName to @riverpod code generation

- Converted ProviderClass to use @riverpod annotation
- Provider name remains: providerNameProvider
- No breaking changes
- Tests passing ✅"
```

**For breaking changes:**

```bash
git commit -m "refactor!: migrate themeModeProvider to @riverpod

BREAKING CHANGE: Provider renamed from themeModeProvider to appThemeModeProvider

- Converted ThemeModeNotifier to AppThemeMode
- Updated all usages across codebase (N files)
- Tests passing ✅"
```

---

## Testing Plan

### Per-Provider Testing

After migrating each provider, perform:

1. **Compilation Check**
   ```bash
   flutter analyze
   ```

2. **Lint Check**
   ```bash
   dart run custom_lint
   ```

3. **Unit Tests**
   ```bash
   flutter test
   ```

4. **Manual Smoke Test**
   - Launch app
   - Navigate to feature using the provider
   - Verify behavior is unchanged

---

### Phase Testing

After completing each phase:

1. **Full Test Suite**
   ```bash
   flutter test --coverage
   ```

2. **Integration Testing**
   - Test all major user flows
   - Auth flow (login, logout, token refresh)
   - Chat flow (create, send, receive)
   - Settings (change theme, locale, models)
   - Navigation (all routes)

3. **Platform Testing**
   - iOS simulator
   - Android emulator
   - (Optional) Web browser
   - (Optional) Physical devices

4. **Performance Check**
   - App startup time
   - Navigation performance
   - Memory usage (DevTools)
   - Provider rebuild counts (DevTools)

---

### Final Testing (After All Phases)

1. **Regression Testing**
   - Run full test suite
   - Manual testing of all features
   - Test on multiple platforms
   - Check for memory leaks

2. **Code Quality**
   - Run analyzer
   - Run linter
   - Check code coverage
   - Review generated files

3. **Documentation**
   - Update README if needed
   - Update AGENTS.md if needed
   - Add migration notes to commits

---

## Rollback Plan

### Per-Provider Rollback

If a single provider migration causes issues:

```bash
# Revert the last commit
git revert HEAD

# Or reset to before migration
git reset --hard HEAD~1

# Regenerate code
dart run build_runner build --delete-conflicting-outputs

# Test
flutter test
```

---

### Phase Rollback

If an entire phase needs to be rolled back:

```bash
# Find the commit before phase started
git log --oneline

# Reset to that commit
git reset --hard <commit-hash>

# Regenerate code
dart run build_runner build --delete-conflicting-outputs

# Test
flutter test
```

---

### Emergency Rollback

If production issues arise after deployment:

1. **Immediate:**
   ```bash
   # Revert to last known good state
   git revert <range-of-commits>
   git push
   ```

2. **Rebuild and Deploy:**
   ```bash
   flutter clean
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter build <platform>
   # Deploy to stores
   ```

---

## Risk Mitigation

### Low-Risk Providers (Categories A, D, F)

**Mitigation:**
- Migrate in small batches
- Commit frequently
- Test after each migration

**Rollback:**
- Easy (single commit revert)

---

### Medium-Risk Providers (Categories B, C, E)

**Mitigation:**
- Migrate individually
- Extensive manual testing
- Update documentation

**Rollback:**
- Straightforward (commit revert)
- May need to update usages

---

### High-Risk Providers (appSettingsProvider, chatMessagesProvider, conversationsProvider)

**Mitigation:**
- Create detailed test plan
- Test on multiple platforms
- Have team review changes
- Deploy to staging first
- Monitor production closely

**Rollback:**
- More complex (many dependencies)
- May need coordinated revert
- Keep backup branch

---

## Success Criteria

### Phase Completion

Each phase is complete when:
- ✅ All targeted providers migrated
- ✅ All tests passing
- ✅ No analyzer/lint errors
- ✅ Manual testing successful
- ✅ Performance unchanged or improved
- ✅ Changes committed with clear messages

---

### Overall Completion

Priority 2 migration is complete when:
- ✅ All 39 providers migrated to @riverpod
- ✅ Codebase uses consistent provider pattern
- ✅ All tests passing
- ✅ No regressions identified
- ✅ Documentation updated
- ✅ Team trained on new patterns

---

## Timeline

### Estimated Schedule

| Phase | Providers | Effort | Timeline |
|-------|-----------|--------|----------|
| Phase 1 | 10 simple notifiers | 4-6 hours | Week 1 |
| Phase 2 | 15 future providers | 6-8 hours | Week 2 |
| Phase 3 | 4 family providers | 2-3 hours | Week 2 |
| Phase 4 | 2 storage notifiers | 4-6 hours | Week 3 |
| Phase 5 | 3 complex providers | 6-8 hours | Week 4 |
| Phase 6 | 2 private providers | 1-2 hours | Week 4 |
| **Total** | **36 providers** | **23-33 hours** | **4 weeks** |

**Note:** 3 providers (`activeConversationProvider`, `socketConnectionStreamProvider`, `conversationStreamProvider`) are already using @riverpod and don't need migration.

**Recommended Pace:**
- 1-2 hours per day
- 5-10 providers per week
- Don't rush high-risk migrations

---

## Resources

### Documentation

- [Riverpod 3.0 Code Generation Guide](https://riverpod.dev/docs/concepts/about_code_generation)
- [Riverpod Migration Guide](https://riverpod.dev/docs/3.0_migration)
- [docs/riverpod_migration_example.md](./docs/riverpod_migration_example.md) (this repo)

### Tools

- VS Code Riverpod snippets
- Android Studio Riverpod plugin
- `dart run build_runner watch` (auto-regenerate)

### Commands

```bash
# Build once
dart run build_runner build --delete-conflicting-outputs

# Watch mode (recommended during development)
dart run build_runner watch --delete-conflicting-outputs

# Clean generated files
flutter clean
dart run build_runner clean

# Run all checks
flutter analyze && dart run custom_lint && flutter test
```

---

## Notes

### Naming Conventions

**Class Names:**
- Remove `Notifier` suffix
- Use descriptive names
- Avoid conflicts with existing types (e.g., `AppThemeMode` instead of `ThemeMode`)

**Provider Names:**
- Auto-generated from class/function name
- Camel case with `Provider` suffix
- Examples:
  - Class `SearchQuery` → `searchQueryProvider`
  - Function `serverConfigs` → `serverConfigsProvider`

### Common Issues

**Issue 1: "_$ClassName not found"**
```bash
# Solution: Run build_runner
dart run build_runner build --delete-conflicting-outputs
```

**Issue 2: "Provider name already exists"**
```dart
// Solution: Rename the class to avoid conflicts
@riverpod
class AppThemeMode extends _$AppThemeMode { // ✅ Not 'ThemeMode'
  // ...
}
```

**Issue 3: "Tests failing after migration"**
```bash
# Solution: Check if provider name changed
# Update test imports and usages
```

---

## Conclusion

This Priority 2 migration plan provides a systematic approach to standardizing all providers in the Conduit codebase to use Riverpod 3.0 code generation.

**Key Principles:**
1. **Incremental:** Small, focused changes
2. **Safe:** Test after every change
3. **Reversible:** Clear commits, easy rollback
4. **Documented:** Clear migration notes

**Expected Benefits:**
- ✅ Consistent codebase
- ✅ Better IDE support
- ✅ Reduced boilerplate
- ✅ Easier future modifications
- ✅ Improved developer experience

**Risk Level:** 🟡 Medium (manageable with careful execution)

**Recommendation:** Proceed with Phase 1 to build confidence, then continue incrementally based on results.

---

**Status:** 📋 Ready for Implementation  
**Next Action:** Begin Phase 1 migrations

