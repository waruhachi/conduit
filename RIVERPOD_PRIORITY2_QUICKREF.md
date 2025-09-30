# Priority 2 Migration Quick Reference

**Quick access guide for Priority 2 migration tasks**

---

## Quick Stats

- **Total Providers:** 39 providers to migrate
- **Estimated Effort:** 23-33 hours (4 weeks at 1-2 hours/day)
- **Risk Level:** 🟡 Medium
- **Phases:** 6 phases

---

## Migration Checklist by Phase

### Phase 1: Simple Notifiers (4-6 hours) 🟢

- [ ] `searchQueryProvider` → `SearchQuery`
- [ ] `selectedModelProvider` → `SelectedModel`
- [ ] `isManualModelSelectionProvider` → `IsManualModelSelection`
- [ ] `reviewerModeProvider` → `ReviewerMode`
- [ ] `batchModeProvider` → `BatchMode`
- [ ] `isLoadingConversationProvider` → `IsLoadingConversation`
- [ ] `prefilledInputTextProvider` → `PrefilledInputText`
- [ ] `inputFocusTriggerProvider` → `InputFocusTrigger`
- [ ] `composerHasFocusProvider` → `ComposerHasFocus`
- [ ] `reducedMotionProvider` → `ReducedMotion`

**File:** Various  
**Risk:** 🟢 Low  
**Provider Names:** Unchanged ✅

---

### Phase 2: FutureProvider Functions (6-8 hours) 🟢

- [ ] `serverConfigsProvider`
- [ ] `activeServerProvider`
- [ ] `currentUserProvider`
- [ ] `modelsProvider`
- [ ] `defaultModelProvider`
- [ ] `userSettingsProvider`
- [ ] `conversationSuggestionsProvider`
- [ ] `userPermissionsProvider`
- [ ] `foldersProvider`
- [ ] `userFilesProvider`
- [ ] `knowledgeBasesProvider`
- [ ] `availableVoicesProvider`
- [ ] `imageModelsProvider`
- [ ] `promptsListProvider`
- [ ] `toolsListProvider`

**File:** Mostly `app_providers.dart`  
**Risk:** 🟢 Low  
**Provider Names:** Unchanged ✅

---

### Phase 3: Family Providers (2-3 hours) 🟢

- [ ] `loadConversationProvider(id)`
- [ ] `serverSearchProvider(query)`
- [ ] `fileContentProvider(fileId)`
- [ ] `voiceInputAvailableProvider`

**File:** Various  
**Risk:** 🟡 Medium  
**Provider Names:** Unchanged ✅

---

### Phase 4: Name-Changing Providers (4-6 hours) ⚠️

- [ ] `themeModeProvider` → `appThemeModeProvider` ⚠️ BREAKING
- [ ] `localeProvider` → `appLocaleProvider` ⚠️ BREAKING

**File:** `app_providers.dart`  
**Risk:** 🟡 Medium  
**Provider Names:** CHANGED - requires bulk find/replace

**Migration Commands:**
```bash
# ThemeMode
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/themeModeProvider/appThemeModeProvider/g' {} +

# Locale
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/localeProvider/appLocaleProvider/g' {} +
```

---

### Phase 5: Complex Providers (6-8 hours) 🔴

- [ ] `conversationsProvider` (complex caching)
- [ ] `appSettingsProvider` (large class, high usage)
- [ ] `chatMessagesProvider` (2500+ lines, very complex)

**File:** Various  
**Risk:** 🔴 High  
**Strategy:** One at a time, extensive testing

---

### Phase 6: Internal Providers (1-2 hours) 🟢

- [ ] `_wasOfflineProvider` (private)
- [ ] `_conversationsCacheTimestampProvider` (private)

**File:** Various  
**Risk:** 🟢 Low (internal use only)

---

## Standard Migration Process

### 1. Preparation
```bash
git status                    # Clean state
flutter pub get               # Dependencies
flutter test                  # Baseline
grep -r "providerName" lib/   # Usage count
```

### 2. Code Changes

**For Notifier Classes:**
```dart
// BEFORE
final myProvider = NotifierProvider<MyNotifier, String>(MyNotifier.new);

class MyNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String value) => state = value;
}

// AFTER
@riverpod
class My extends _$My {
  @override
  String build() => '';
  void set(String value) => state = value;
}
// Generated: myProvider
```

**For FutureProvider Functions:**
```dart
// BEFORE
final myProvider = FutureProvider<String>((ref) async {
  return await fetchData();
});

// AFTER
@riverpod
Future<String> my(MyRef ref) async {
  return await fetchData();
}
// Generated: myProvider
```

**For Family Providers:**
```dart
// BEFORE
final myProvider = FutureProvider.family<String, int>((ref, id) async {
  return await fetchData(id);
});

// AFTER
@riverpod
Future<String> my(MyRef ref, int id) async {
  return await fetchData(id);
}
// Usage: ref.watch(myProvider(123))
```

### 3. Generate Code
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Verify
```bash
flutter analyze
dart run custom_lint
flutter test
flutter run    # Manual test
```

### 5. Commit
```bash
git add .
git commit -m "refactor: migrate myProvider to @riverpod

- Converted MyNotifier to My
- Provider name unchanged: myProvider
- Tests passing ✅"
```

---

## Quick Commands

### Build Runner
```bash
# One-time build
dart run build_runner build --delete-conflicting-outputs

# Watch mode (recommended)
dart run build_runner watch --delete-conflicting-outputs

# Clean
dart run build_runner clean
```

### Testing
```bash
# All checks
flutter analyze && dart run custom_lint && flutter test

# With coverage
flutter test --coverage

# Single file
flutter test test/path/to/test.dart
```

### Finding Usages
```bash
# Count usages
grep -r "providerName" lib/ --exclude="*.g.dart" | wc -l

# Find files
grep -r "providerName" lib/ --exclude="*.g.dart" -l

# Show context
grep -r "providerName" lib/ --exclude="*.g.dart" -C 2
```

### Bulk Replace
```bash
# Preview (dry run)
grep -r "oldName" lib/ --exclude="*.g.dart"

# Replace (macOS)
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i '' 's/oldName/newName/g' {} +

# Replace (Linux)
find lib -type f -name "*.dart" ! -name "*.g.dart" -exec sed -i 's/oldName/newName/g' {} +
```

---

## Common Issues & Solutions

### Issue: "_$ClassName not found"
```bash
# Run build_runner
dart run build_runner build --delete-conflicting-outputs
```

### Issue: "Provider name conflict"
```dart
// Rename class to avoid conflicts
@riverpod
class AppThemeMode extends _$AppThemeMode { // Not 'ThemeMode'
  // ...
}
```

### Issue: "Build runner errors"
```bash
# Clean and rebuild
flutter clean
flutter pub get
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Issue: "Tests failing"
```dart
// Check if provider name changed
// Update imports:
// OLD: import 'old_file.dart';
// NEW: import 'new_file.dart'; (if moved)
```

---

## Risk Levels

| Symbol | Risk | Description | Strategy |
|--------|------|-------------|----------|
| 🟢 | Low | Simple, low usage | Batch migrate, quick test |
| 🟡 | Medium | Breaking changes or moderate complexity | Migrate individually, thorough test |
| 🔴 | High | Complex, high usage | Extensive planning, staging deployment |

---

## Success Metrics

After each migration:
- ✅ Code compiles without errors
- ✅ No lint warnings
- ✅ All tests pass
- ✅ Manual test successful
- ✅ Performance unchanged

After each phase:
- ✅ All phase targets complete
- ✅ Full test suite passes
- ✅ Integration tests pass
- ✅ Multi-platform verification

---

## Rollback

### Single Provider
```bash
git revert HEAD
dart run build_runner build --delete-conflicting-outputs
flutter test
```

### Multiple Commits
```bash
git log --oneline
git reset --hard <commit-hash>
dart run build_runner build --delete-conflicting-outputs
flutter test
```

---

## Phase Progression

```
Phase 1 (Simple) ──→ Phase 2 (Functions) ──→ Phase 3 (Family)
                                                    ↓
Phase 6 (Private) ←── Phase 5 (Complex) ←── Phase 4 (Breaking)
```

**Recommendation:** Complete phases in order. Don't skip ahead to complex providers.

---

## Next Steps

1. **Review** the detailed plan: `RIVERPOD_PRIORITY2_PLAN.md`
2. **Start** with Phase 1: Simple notifiers
3. **Test** after each migration
4. **Commit** frequently
5. **Document** any issues or learnings

---

## References

- **Detailed Plan:** [RIVERPOD_PRIORITY2_PLAN.md](./RIVERPOD_PRIORITY2_PLAN.md)
- **Example Guide:** [docs/riverpod_migration_example.md](./docs/riverpod_migration_example.md)
- **Analysis:** [RIVERPOD_3_ANALYSIS.md](./RIVERPOD_3_ANALYSIS.md)
- **Priority 1:** [RIVERPOD_PRIORITY1_COMPLETED.md](./RIVERPOD_PRIORITY1_COMPLETED.md)

---

**Last Updated:** September 30, 2025  
**Status:** Ready for Implementation 🚀
