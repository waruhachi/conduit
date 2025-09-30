# Riverpod 3.0 Quick Start Guide

## Immediate Actions (30 minutes)

### Step 1: Add riverpod_lint (5 minutes)

1. **Update `pubspec.yaml`:**

```bash
cd /Users/cogwheel/Documents/conduit
```

Add to `dev_dependencies` section:

```yaml
dev_dependencies:
  # ... existing dependencies ...
  riverpod_lint: ^3.0.0
  custom_lint: ^0.8.0
```

2. **Install packages:**

```bash
flutter pub get
```

3. **Update `analysis_options.yaml`:**

Add this at the top level (same level as `linter:`):

```yaml
analyzer:
  plugins:
    - custom_lint
```

Full file should look like:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  plugins:
    - custom_lint

linter:
  rules:
    avoid_print: true
```

4. **Run the linter:**

```bash
dart run custom_lint
```

This will show Riverpod-specific issues if any exist.

---

### Step 2: Fix Any Linter Issues (10 minutes)

The linter will identify issues like:

- ❌ Using `ref` outside of widgets/providers
- ❌ Missing `ref.mounted` checks
- ❌ Incorrect provider usage patterns

**Example Fix:**

If you see: `"ref should not be used outside of a widget/provider"`

```dart
// ❌ Bad
class MyService {
  void doSomething(WidgetRef ref) {  // ref as parameter
    ref.read(someProvider);
  }
}

// ✅ Good
@riverpod
class MyService extends _$MyService {
  @override
  void build() {}
  
  void doSomething() {
    ref.read(someProvider);  // ref is available in Notifier
  }
}
```

---

### Step 3: Update AGENTS.md (5 minutes)

Replace the state management section in `AGENTS.md`:

**Find (around line 166):**

```markdown
### State Management
* **Built-in Solutions:** Prefer Flutter's built-in state management solutions.
  Do not use a third-party package unless explicitly requested.
```

**Replace with:**

```markdown
### State Management
* **Riverpod 3.0:** This project uses Riverpod 3.0 for state management.
* **Code Generation:** Always use `@riverpod` annotation with code generation 
  for new providers. See existing examples in `lib/core/providers/`.
* **Notifier Classes:** Use `Notifier` and `AsyncNotifier` for mutable state:
  ```dart
  @riverpod
  class Counter extends _$Counter {
    @override
    int build() => 0;
    
    void increment() => state++;
  }
  ```
* **Provider Functions:** Use `@riverpod` functions for computed/derived state:
  ```dart
  @riverpod
  int doubled(DoubledRef ref) {
    final count = ref.watch(counterProvider);
    return count * 2;
  }
  ```
* **Keep Alive:** Use `@Riverpod(keepAlive: true)` for singletons:
  ```dart
  @Riverpod(keepAlive: true)
  class AuthManager extends _$AuthManager { ... }
  ```
* **Async Safety:** Always check `ref.mounted` before state updates in async ops:
  ```dart
  Future<void> loadData() async {
    final data = await fetchData();
    if (!ref.mounted) return;  // ✅ Prevent updates after disposal
    state = data;
  }
  ```
* **Automatic Retry:** Providers automatically retry on failure with exponential
  backoff. Customize if needed:
  ```dart
  @riverpod
  Future<Data> myData(MyDataRef ref) async {
    ref.onDispose(() {
      // Cleanup
    });
    return await fetchData();
  }
  ```
* **Lint Rules:** Use `custom_lint` with `riverpod_lint` to catch common mistakes.
  Run `dart run custom_lint` before committing.
```

---

## Validation (10 minutes)

### 1. Run All Checks

```bash
# Code generation (if needed)
dart run build_runner build --delete-conflicting-outputs

# Custom lint
dart run custom_lint

# Standard analysis
flutter analyze

# Tests
flutter test
```

### 2. Expected Results

All should pass ✅ without new errors. You may see some warnings from `riverpod_lint` which are informational.

### 3. Common Warnings and Fixes

#### Warning: "Provider could use autoDispose"

```dart
// Current
@riverpod
Future<Data> myData(MyDataRef ref) async {
  return await fetch();
}

// Suggested (if data is short-lived)
@riverpod
Future<Data> myData(MyDataRef ref) async {
  ref.cacheFor(const Duration(minutes: 5));  // Auto-dispose after 5 min
  return await fetch();
}
```

#### Warning: "Missing ref.mounted check"

```dart
// Current
Future<void> save() async {
  await someAsyncOp();
  state = newValue;  // ⚠️ Might be disposed
}

// Fixed
Future<void> save() async {
  await someAsyncOp();
  if (!ref.mounted) return;  // ✅
  state = newValue;
}
```

---

## Next Steps (Optional)

After completing the quick start, you can:

1. **Read the full analysis:** See `RIVERPOD_3_ANALYSIS.md`
2. **Start migration:** Follow Phase 2 in the analysis document
3. **Add provider docs:** Document provider purposes with dartdoc

---

## Troubleshooting

### Issue: `custom_lint` not found

```bash
# Reinstall
flutter pub get
flutter pub global activate custom_lint
```

### Issue: Analysis takes too long

```bash
# Restart Dart analysis server
# In VS Code: Cmd+Shift+P -> "Dart: Restart Analysis Server"
# In Android Studio: File -> Invalidate Caches / Restart
```

### Issue: Generated files out of sync

```bash
# Clean and rebuild
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

---

## Benefits You'll See Immediately

After adding `riverpod_lint`:

✅ **Compile-time safety** - Catch errors before runtime  
✅ **Better autocomplete** - IDE knows provider types  
✅ **Quick fixes** - Automatic solutions for common issues  
✅ **Consistency checks** - Enforced best practices  
✅ **Refactoring confidence** - Compiler catches all usages  

---

## Questions?

Refer to:
- Full analysis: `RIVERPOD_3_ANALYSIS.md`
- Official docs: https://riverpod.dev
- Linter docs: https://riverpod.dev/docs/concepts/about_riverpod_lint
