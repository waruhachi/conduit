# Priority 2 Migration Progress Tracker

**Track your progress through the Priority 2 migration**

Last Updated: September 30, 2025

---

## Overall Progress

```
Total: 39 providers
├── Phase 1: 0/10 providers ░░░░░░░░░░ 0%
├── Phase 2: 0/15 providers ░░░░░░░░░░ 0%
├── Phase 3: 0/4 providers  ░░░░░░░░░░ 0%
├── Phase 4: 0/2 providers  ░░░░░░░░░░ 0%
├── Phase 5: 0/3 providers  ░░░░░░░░░░ 0%
└── Phase 6: 0/2 providers  ░░░░░░░░░░ 0%

Overall: 0/36 providers (0%)
```

**Note:** 3 providers already use @riverpod and don't need migration:
- ✅ `activeConversationProvider`
- ✅ `socketConnectionStreamProvider`
- ✅ `conversationStreamProvider`

---

## Phase 1: Simple Notifiers 🟢

**Status:** Not Started  
**Progress:** 0/10 (0%)  
**Estimated Time:** 4-6 hours  
**Files Modified:** 0/5

### Providers

| # | Provider | Class | File | Status | Notes |
|---|----------|-------|------|--------|-------|
| 1 | `searchQueryProvider` | `SearchQuery` | `app_providers.dart` | ⬜ Not Started | |
| 2 | `selectedModelProvider` | `SelectedModel` | `app_providers.dart` | ⬜ Not Started | |
| 3 | `isManualModelSelectionProvider` | `IsManualModelSelection` | `app_providers.dart` | ⬜ Not Started | |
| 4 | `reviewerModeProvider` | `ReviewerMode` | `app_providers.dart` | ⬜ Not Started | |
| 5 | `batchModeProvider` | `BatchMode` | `message_batch_service.dart` | ⬜ Not Started | |
| 6 | `isLoadingConversationProvider` | `IsLoadingConversation` | `chat_providers.dart` | ⬜ Not Started | |
| 7 | `prefilledInputTextProvider` | `PrefilledInputText` | `chat_providers.dart` | ⬜ Not Started | |
| 8 | `inputFocusTriggerProvider` | `InputFocusTrigger` | `chat_providers.dart` | ⬜ Not Started | |
| 9 | `composerHasFocusProvider` | `ComposerHasFocus` | `chat_providers.dart` | ⬜ Not Started | |
| 10 | `reducedMotionProvider` | `ReducedMotion` | `animation_service.dart` | ⬜ Not Started | |

### Checklist

- [ ] All providers migrated
- [ ] Build runner completed successfully
- [ ] All tests passing
- [ ] Manual testing completed
- [ ] No lint errors
- [ ] Changes committed

---

## Phase 2: FutureProvider Functions 🟢

**Status:** Not Started  
**Progress:** 0/15 (0%)  
**Estimated Time:** 6-8 hours  
**Files Modified:** 0/5

### Batch 1: Core Providers

| # | Provider | File | Status | Notes |
|---|----------|------|--------|-------|
| 1 | `serverConfigsProvider` | `app_providers.dart` | ⬜ Not Started | |
| 2 | `activeServerProvider` | `app_providers.dart` | ⬜ Not Started | |
| 3 | `currentUserProvider` | `app_providers.dart` | ⬜ Not Started | |
| 4 | `modelsProvider` | `app_providers.dart` | ⬜ Not Started | |
| 5 | `defaultModelProvider` | `app_providers.dart` | ⬜ Not Started | |

### Batch 2: Settings & User Data

| # | Provider | File | Status | Notes |
|---|----------|------|--------|-------|
| 6 | `userSettingsProvider` | `app_providers.dart` | ⬜ Not Started | |
| 7 | `conversationSuggestionsProvider` | `app_providers.dart` | ⬜ Not Started | |
| 8 | `userPermissionsProvider` | `app_providers.dart` | ⬜ Not Started | |

### Batch 3: Resources

| # | Provider | File | Status | Notes |
|---|----------|------|--------|-------|
| 9 | `foldersProvider` | `app_providers.dart` | ⬜ Not Started | |
| 10 | `userFilesProvider` | `app_providers.dart` | ⬜ Not Started | |
| 11 | `knowledgeBasesProvider` | `app_providers.dart` | ⬜ Not Started | |
| 12 | `availableVoicesProvider` | `app_providers.dart` | ⬜ Not Started | |
| 13 | `imageModelsProvider` | `app_providers.dart` | ⬜ Not Started | |

### Batch 4: Feature Providers

| # | Provider | File | Status | Notes |
|---|----------|------|--------|-------|
| 14 | `promptsListProvider` | `prompts_providers.dart` | ⬜ Not Started | |
| 15 | `toolsListProvider` | `tools_providers.dart` | ⬜ Not Started | |

### Checklist

- [ ] Batch 1 complete (5 providers)
- [ ] Batch 2 complete (3 providers)
- [ ] Batch 3 complete (5 providers)
- [ ] Batch 4 complete (2 providers)
- [ ] All tests passing
- [ ] Manual testing completed
- [ ] Changes committed

---

## Phase 3: Family Providers 🟡

**Status:** Not Started  
**Progress:** 0/4 (0%)  
**Estimated Time:** 2-3 hours  
**Files Modified:** 0/3

### Providers

| # | Provider | Parameters | File | Status | Notes |
|---|----------|------------|------|--------|-------|
| 1 | `loadConversationProvider` | `String id` | `app_providers.dart` | ⬜ Not Started | |
| 2 | `serverSearchProvider` | `String query` | `app_providers.dart` | ⬜ Not Started | |
| 3 | `fileContentProvider` | `String fileId` | `app_providers.dart` | ⬜ Not Started | |
| 4 | `voiceInputAvailableProvider` | (none) | `voice_input_service.dart` | ⬜ Not Started | |

### Checklist

- [ ] All providers migrated
- [ ] Parameter types verified
- [ ] Usage patterns tested
- [ ] All tests passing
- [ ] Changes committed

---

## Phase 4: Name-Changing Providers ⚠️

**Status:** Not Started  
**Progress:** 0/2 (0%)  
**Estimated Time:** 4-6 hours  
**Files Modified:** 0/1

### Providers

| # | Old Name | New Name | Class | Usages | Status | Notes |
|---|----------|----------|-------|--------|--------|-------|
| 1 | `themeModeProvider` | `appThemeModeProvider` | `AppThemeMode` | ~10-15 | ⬜ Not Started | Breaking change |
| 2 | `localeProvider` | `appLocaleProvider` | `AppLocale` | ~8-12 | ⬜ Not Started | Breaking change |

### Checklist

- [ ] `themeModeProvider` migrated
  - [ ] Class renamed to `AppThemeMode`
  - [ ] Generated code verified
  - [ ] All usages found (run: `grep -r "themeModeProvider" lib/`)
  - [ ] Bulk replace completed
  - [ ] Tests passing
  - [ ] Manual testing on iOS
  - [ ] Manual testing on Android
- [ ] `localeProvider` migrated
  - [ ] Class renamed to `AppLocale`
  - [ ] Generated code verified
  - [ ] All usages found (run: `grep -r "localeProvider" lib/`)
  - [ ] Bulk replace completed
  - [ ] Tests passing
  - [ ] Manual testing on iOS
  - [ ] Manual testing on Android
- [ ] Integration testing
- [ ] Changes committed with BREAKING CHANGE message

---

## Phase 5: Complex Providers 🔴

**Status:** Not Started  
**Progress:** 0/3 (0%)  
**Estimated Time:** 6-8 hours  
**Files Modified:** 0/3

### Providers

| # | Provider | Complexity | Lines | Usages | Status | Notes |
|---|----------|------------|-------|--------|--------|-------|
| 1 | `conversationsProvider` | High | ~300 | ~10-15 | ⬜ Not Started | Complex caching |
| 2 | `appSettingsProvider` | High | ~100 | ~20-30 | ⬜ Not Started | Large class, high usage |
| 3 | `chatMessagesProvider` | Very High | ~2500 | ~15-20 | ⬜ Not Started | Extremely complex |

### `conversationsProvider` Checklist

- [ ] Code review completed
- [ ] Test plan created
- [ ] Migration completed
- [ ] Build runner successful
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Manual testing:
  - [ ] List conversations
  - [ ] Create conversation
  - [ ] Delete conversation
  - [ ] Search conversations
  - [ ] Folder operations
- [ ] Performance check (DevTools)
- [ ] Committed

### `appSettingsProvider` Checklist

- [ ] Code review completed
- [ ] Test plan created
- [ ] Migration completed
- [ ] Build runner successful
- [ ] Unit tests passing
- [ ] Manual testing:
  - [ ] Read settings
  - [ ] Update settings
  - [ ] Persist settings
  - [ ] Default model selection
  - [ ] Theme changes
  - [ ] Voice settings
- [ ] Committed

### `chatMessagesProvider` Checklist

- [ ] Code review completed (entire 2500 lines!)
- [ ] All dependencies documented
- [ ] Test plan created (comprehensive)
- [ ] Migration completed
- [ ] Build runner successful
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Manual testing:
  - [ ] Load conversation
  - [ ] Send message
  - [ ] Receive message
  - [ ] Stream processing
  - [ ] Tool calls
  - [ ] Attachments
  - [ ] Error handling
  - [ ] Typing indicators
  - [ ] Message regeneration
  - [ ] Batch operations
- [ ] Performance check (memory, rebuilds)
- [ ] Memory leak check
- [ ] Committed
- [ ] Team review

---

## Phase 6: Internal Providers 🟢

**Status:** Not Started  
**Progress:** 0/2 (0%)  
**Estimated Time:** 1-2 hours  
**Files Modified:** 0/2

### Providers

| # | Provider | Visibility | File | Status | Notes |
|---|----------|------------|------|--------|-------|
| 1 | `_wasOfflineProvider` | Private | `offline_indicator.dart` | ⬜ Not Started | Internal only |
| 2 | `_conversationsCacheTimestampProvider` | Private | `app_providers.dart` | ⬜ Not Started | Internal only |

### Checklist

- [ ] Both providers migrated
- [ ] Tests passing
- [ ] Changes committed

---

## Testing Checklist

### Per-Provider Testing

After each provider migration:

- [ ] Compilation check: `flutter analyze`
- [ ] Lint check: `dart run custom_lint`
- [ ] Unit tests: `flutter test`
- [ ] Manual smoke test: `flutter run`

### Phase Testing

After each phase:

- [ ] Full test suite: `flutter test --coverage`
- [ ] Integration testing (all major flows)
- [ ] iOS simulator testing
- [ ] Android emulator testing
- [ ] Performance check (DevTools)
- [ ] Memory check (DevTools)

### Final Testing

After all phases:

- [ ] Full regression testing
- [ ] All platforms tested
- [ ] Performance benchmarked
- [ ] Memory profiled
- [ ] Code coverage checked
- [ ] Documentation updated

---

## Issues Log

Track any issues encountered during migration:

| Date | Provider | Issue | Solution | Time Lost |
|------|----------|-------|----------|-----------|
| | | | | |

---

## Notes & Learnings

Document any insights or patterns discovered:

### Patterns Discovered

- 

### Common Mistakes to Avoid

- 

### Tips & Tricks

- 

---

## Time Tracking

| Phase | Estimated | Actual | Difference | Notes |
|-------|-----------|--------|------------|-------|
| Phase 1 | 4-6h | | | |
| Phase 2 | 6-8h | | | |
| Phase 3 | 2-3h | | | |
| Phase 4 | 4-6h | | | |
| Phase 5 | 6-8h | | | |
| Phase 6 | 1-2h | | | |
| **Total** | **23-33h** | | | |

---

## Commit Log

Track commits for easy rollback:

| Date | Phase | Providers | Commit Hash | Notes |
|------|-------|-----------|-------------|-------|
| | | | | |

---

## Status Legend

- ⬜ Not Started
- 🔄 In Progress
- ✅ Complete
- ⚠️ Blocked
- ❌ Failed/Rolled Back

---

## Quick Commands Reference

```bash
# Start working
git status
flutter pub get
dart run build_runner watch --delete-conflicting-outputs

# After migration
flutter analyze && dart run custom_lint && flutter test

# Find usages
grep -r "providerName" lib/ --exclude="*.g.dart" | wc -l

# Commit
git add .
git commit -m "refactor: migrate providerName to @riverpod"
```

---

**Remember:**
1. ✅ Test after each migration
2. ✅ Commit frequently
3. ✅ Take breaks between complex providers
4. ✅ Ask for help if stuck
5. ✅ Document any issues or learnings

**Good luck! 🚀**
