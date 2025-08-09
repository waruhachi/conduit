import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/storage_service.dart';
// (removed duplicate) import '../services/optimized_storage_service.dart';
import '../services/api_service.dart';
import '../auth/auth_state_manager.dart';
import '../../features/auth/providers/unified_auth_providers.dart';
import '../services/attachment_upload_queue.dart';
import '../models/server_config.dart';
import '../models/user.dart';
import '../models/model.dart';
import '../models/conversation.dart';
import '../models/user_settings.dart';
import '../models/folder.dart';
import '../models/file_info.dart';
import '../models/knowledge_base.dart';
import '../services/optimized_storage_service.dart';

// Storage providers
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(
    secureStorage: ref.watch(secureStorageProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});

// Optimized storage service provider
final optimizedStorageServiceProvider = Provider<OptimizedStorageService>((
  ref,
) {
  return OptimizedStorageService(
    secureStorage: ref.watch(secureStorageProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
});

// Theme provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  final storage = ref.watch(optimizedStorageServiceProvider);
  return ThemeModeNotifier(storage);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final OptimizedStorageService _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _loadTheme();
  }

  void _loadTheme() {
    final mode = _storage.getThemeMode();
    if (mode != null) {
      state = ThemeMode.values.firstWhere(
        (e) => e.toString() == mode,
        orElse: () => ThemeMode.system,
      );
    }
  }

  void setTheme(ThemeMode mode) {
    state = mode;
    _storage.setThemeMode(mode.toString());
  }
}

// Server connection providers - optimized with caching
final serverConfigsProvider = FutureProvider<List<ServerConfig>>((ref) async {
  final storage = ref.watch(optimizedStorageServiceProvider);
  return storage.getServerConfigs();
});

final activeServerProvider = FutureProvider<ServerConfig?>((ref) async {
  final storage = ref.watch(optimizedStorageServiceProvider);
  final configs = await ref.watch(serverConfigsProvider.future);
  final activeId = await storage.getActiveServerId();

  if (activeId == null || configs.isEmpty) return null;

  return configs.firstWhere(
    (config) => config.id == activeId,
    orElse: () => configs.first,
  );
});

final serverConnectionStateProvider = Provider<bool>((ref) {
  final activeServer = ref.watch(activeServerProvider);
  return activeServer.maybeWhen(
    data: (server) => server != null,
    orElse: () => false,
  );
});

// API Service provider with unified auth integration
final apiServiceProvider = Provider<ApiService?>((ref) {
  // If reviewer mode is enabled, skip creating ApiService
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) {
    return null;
  }
  final activeServer = ref.watch(activeServerProvider);

  return activeServer.maybeWhen(
    data: (server) {
      if (server == null) return null;

      final apiService = ApiService(
        serverConfig: server,
        authToken: null, // Will be set by auth state manager
      );

      // Keep callbacks in sync so interceptor can notify auth manager
      apiService.setAuthCallbacks(
        onAuthTokenInvalid: () {},
        onTokenInvalidated: () async {
          final authManager = ref.read(authStateManagerProvider.notifier);
          await authManager.onTokenInvalidated();
        },
      );

      // Set up callback for unified auth state manager
      // (legacy properties kept during transition)
      apiService.onTokenInvalidated = () async {
        final authManager = ref.read(authStateManagerProvider.notifier);
        await authManager.onTokenInvalidated();
      };

      // Keep legacy callback for backward compatibility during transition
      apiService.onAuthTokenInvalid = () {
        // This will be removed once migration is complete
        debugPrint('DEBUG: Legacy auth invalidation callback triggered');
      };

      // Initialize with any existing token immediately
      final token = ref.read(authTokenProvider3);
      if (token != null && token.isNotEmpty) {
        apiService.updateAuthToken(token);
      }

      return apiService;
    },
    orElse: () => null,
  );
});

// Attachment upload queue provider
final attachmentUploadQueueProvider = Provider<AttachmentUploadQueue?>((ref) {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return null;

  final queue = AttachmentUploadQueue();
  // Initialize once; subsequent calls are no-ops due to singleton
  queue.initialize(
    onUpload: (filePath, fileName) => api.uploadFile(filePath, fileName),
  );

  return queue;
});

// Auth providers
// Auth token integration with API service - using unified auth system
final apiTokenUpdaterProvider = Provider<void>((ref) {
  // Listen to unified auth token changes and update API service
  ref.listen(authTokenProvider3, (previous, next) {
    final api = ref.read(apiServiceProvider);
    if (api != null && next != null && next.isNotEmpty) {
      api.updateAuthToken(next);
      debugPrint('DEBUG: Updated API service with unified auth token');
    }
  });
});

final currentUserProvider = FutureProvider<User?>((ref) async {
  final api = ref.read(apiServiceProvider);
  final isAuthenticated = ref.watch(isAuthenticatedProvider2);

  if (api == null || !isAuthenticated) return null;

  try {
    return await api.getCurrentUser();
  } catch (e) {
    return null;
  }
});

// Helper provider to force refresh auth state - now using unified system
final refreshAuthStateProvider = Provider<void>((ref) {
  // This provider can be invalidated to force refresh the unified auth system
  ref.read(refreshAuthProvider);
  return;
});

// Model providers
final modelsProvider = FutureProvider<List<Model>>((ref) async {
  // Reviewer mode returns mock models
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) {
    return [
      const Model(
        id: 'demo/gemma-2-mini',
        name: 'Gemma 2 Mini (Demo)',
        description: 'Demo model for reviewer mode',
        isMultimodal: true,
        supportsStreaming: true,
        supportedParameters: ['max_tokens', 'stream'],
      ),
      const Model(
        id: 'demo/llama-3-8b',
        name: 'Llama 3 8B (Demo)',
        description: 'Fast text model for demo',
        isMultimodal: false,
        supportsStreaming: true,
        supportedParameters: ['max_tokens', 'stream'],
      ),
    ];
  }
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    debugPrint('DEBUG: Fetching models from server');
    final models = await api.getModels();
    debugPrint('DEBUG: Successfully fetched ${models.length} models');
    return models;
  } catch (e) {
    debugPrint('ERROR: Failed to fetch models: $e');

    // If models endpoint returns 403, this should now clear auth token
    // and redirect user to login since it's marked as a core endpoint
    if (e.toString().contains('403')) {
      debugPrint(
        'DEBUG: Models endpoint returned 403 - authentication may be invalid',
      );
    }

    return [];
  }
});

final selectedModelProvider = StateProvider<Model?>((ref) => null);

// Conversation providers - Now using correct OpenWebUI API
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) {
    // Provide a simple local demo conversation list
    return [
      Conversation(
        id: 'demo-conv-1',
        title: 'Welcome to Conduit (Demo)',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        updatedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        messages: [],
      ),
    ];
  }
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    debugPrint('DEBUG: No API service available');
    return [];
  }

  try {
    debugPrint('DEBUG: Fetching conversations from OpenWebUI API...');
    final conversations = await api.getConversations(limit: 50);
    debugPrint(
      'DEBUG: Successfully fetched ${conversations.length} conversations',
    );
    return conversations;
  } catch (e, stackTrace) {
    debugPrint('DEBUG: Error fetching conversations: $e');
    debugPrint('DEBUG: Stack trace: $stackTrace');

    // If conversations endpoint returns 403, this should now clear auth token
    // and redirect user to login since it's marked as a core endpoint
    if (e.toString().contains('403')) {
      debugPrint(
        'DEBUG: Conversations endpoint returned 403 - authentication may be invalid',
      );
    }

    // Return empty list instead of re-throwing to allow app to continue functioning
    return [];
  }
});

final activeConversationProvider = StateProvider<Conversation?>((ref) => null);

// Provider to load full conversation with messages
final loadConversationProvider = FutureProvider.family<Conversation, String>((
  ref,
  conversationId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    throw Exception('No API service available');
  }

  debugPrint('DEBUG: Loading full conversation: $conversationId');
  final fullConversation = await api.getConversation(conversationId);
  debugPrint(
    'DEBUG: Loaded conversation with ${fullConversation.messages.length} messages',
  );

  return fullConversation;
});

// Provider to automatically load and set the default model from OpenWebUI
final defaultModelProvider = FutureProvider<Model?>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return null;

  try {
    // Get all available models first
    final models = await ref.read(modelsProvider.future);
    if (models.isEmpty) {
      debugPrint('DEBUG: No models available');
      return null;
    }

    // Check if a model is already selected
    final currentSelected = ref.read(selectedModelProvider);
    if (currentSelected != null) {
      debugPrint('DEBUG: Model already selected: ${currentSelected.name}');
      return currentSelected;
    }

    Model? selectedModel;

    // Try to get the server's default model configuration
    try {
      final defaultModelId = await api.getDefaultModel();

      if (defaultModelId != null && defaultModelId.isNotEmpty) {
        // Find the model that matches the default model ID
        try {
          selectedModel = models.firstWhere(
            (model) =>
                model.id == defaultModelId ||
                model.name == defaultModelId ||
                model.id.contains(defaultModelId) ||
                model.name.contains(defaultModelId),
          );
          debugPrint(
            'DEBUG: Found server default model: ${selectedModel.name}',
          );
        } catch (e) {
          debugPrint(
            'DEBUG: Default model "$defaultModelId" not found in available models',
          );
          selectedModel = models.first;
        }
      } else {
        // No server default, use first available model
        selectedModel = models.first;
        debugPrint(
          'DEBUG: No server default model, using first available: ${selectedModel.name}',
        );
      }
    } catch (apiError) {
      debugPrint('DEBUG: Failed to get default model from server: $apiError');
      // Use first available model as fallback
      selectedModel = models.first;
      debugPrint(
        'DEBUG: Using first available model as fallback: ${selectedModel.name}',
      );
    }

    // Set the selected model
    ref.read(selectedModelProvider.notifier).state = selectedModel;
    debugPrint('DEBUG: Set default model: ${selectedModel.name}');

    return selectedModel;
  } catch (e) {
    debugPrint('DEBUG: Error setting default model: $e');

    // Final fallback: try to select any available model
    try {
      final models = await ref.read(modelsProvider.future);
      if (models.isNotEmpty) {
        final fallbackModel = models.first;
        ref.read(selectedModelProvider.notifier).state = fallbackModel;
        debugPrint(
          'DEBUG: Fallback to first available model: ${fallbackModel.name}',
        );
        return fallbackModel;
      }
    } catch (fallbackError) {
      debugPrint('DEBUG: Error in fallback model selection: $fallbackError');
    }

    return null;
  }
});

// Background model loading provider that doesn't block UI
// This just schedules the loading, doesn't wait for it
final backgroundModelLoadProvider = Provider<void>((ref) {
  // Ensure API token updater is initialized
  ref.watch(apiTokenUpdaterProvider);

  // Schedule background loading without blocking
  Future.microtask(() async {
    // Wait a bit to ensure auth is complete
    await Future.delayed(const Duration(milliseconds: 1500));

    debugPrint('DEBUG: Starting background model loading');

    // Load default model in background
    try {
      await ref.read(defaultModelProvider.future);
      debugPrint('DEBUG: Background model loading completed');
    } catch (e) {
      // Ignore errors in background loading
      debugPrint('DEBUG: Background model loading failed: $e');
    }
  });

  // Return immediately, don't block the UI
  return;
});

// Search query provider
final searchQueryProvider = StateProvider<String>((ref) => '');

// Server-side search provider for chats
final serverSearchProvider = FutureProvider.family<List<Conversation>, String>((
  ref,
  query,
) async {
  if (query.trim().isEmpty) {
    // Return empty list for empty query instead of all conversations
    return [];
  }

  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    debugPrint('DEBUG: Performing server-side search for: "$query"');

    // Use the new server-side search API
    final searchResult = await api.searchChats(
      query: query.trim(),
      archived: false, // Only search non-archived conversations
      limit: 50,
      sortBy: 'updated_at',
      sortOrder: 'desc',
    );

    // Extract conversations from search result
    final List<dynamic> conversationsData = searchResult['conversations'] ?? [];

    // Convert to Conversation objects
    final List<Conversation> conversations = conversationsData.map((data) {
      return Conversation.fromJson(data as Map<String, dynamic>);
    }).toList();

    debugPrint('DEBUG: Server search returned ${conversations.length} results');
    return conversations;
  } catch (e) {
    debugPrint('DEBUG: Server search failed, fallback to local: $e');

    // Fallback to local search if server search fails
    final allConversations = await ref.read(conversationsProvider.future);
    return allConversations.where((conv) {
      return !conv.archived &&
          (conv.title.toLowerCase().contains(query.toLowerCase()) ||
              conv.messages.any(
                (msg) =>
                    msg.content.toLowerCase().contains(query.toLowerCase()),
              ));
    }).toList();
  }
});

final filteredConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversations = ref.watch(conversationsProvider);
  final query = ref.watch(searchQueryProvider);

  // Use server-side search when there's a query
  if (query.trim().isNotEmpty) {
    final searchResults = ref.watch(serverSearchProvider(query));
    return searchResults.maybeWhen(
      data: (results) => results,
      loading: () {
        // While server search is loading, show local filtered results
        return conversations.maybeWhen(
          data: (convs) => convs.where((conv) {
            return !conv.archived &&
                (conv.title.toLowerCase().contains(query.toLowerCase()) ||
                    conv.messages.any(
                      (msg) => msg.content.toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                    ));
          }).toList(),
          orElse: () => [],
        );
      },
      error: (_, stackTrace) {
        // On error, fallback to local search
        return conversations.maybeWhen(
          data: (convs) => convs.where((conv) {
            return !conv.archived &&
                (conv.title.toLowerCase().contains(query.toLowerCase()) ||
                    conv.messages.any(
                      (msg) => msg.content.toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                    ));
          }).toList(),
          orElse: () => [],
        );
      },
      orElse: () => [],
    );
  }

  // When no search query, show all non-archived conversations
  return conversations.maybeWhen(
    data: (convs) {
      if (ref.watch(reviewerModeProvider)) {
        return convs; // Already filtered above for demo
      }
      // Filter out archived conversations (they should be in a separate view)
      final filtered = convs.where((conv) => !conv.archived).toList();

      // Sort: pinned conversations first, then by updated date
      filtered.sort((a, b) {
        // Pinned conversations come first
        if (a.pinned && !b.pinned) return -1;
        if (!a.pinned && b.pinned) return 1;

        // Within same pin status, sort by updated date (newest first)
        return b.updatedAt.compareTo(a.updatedAt);
      });

      return filtered;
    },
    orElse: () => [],
  );
});

// Provider for archived conversations
final archivedConversationsProvider = Provider<List<Conversation>>((ref) {
  final conversations = ref.watch(conversationsProvider);

  return conversations.maybeWhen(
    data: (convs) {
      if (ref.watch(reviewerModeProvider)) {
        return convs.where((c) => c.archived).toList();
      }
      // Only show archived conversations
      final archived = convs.where((conv) => conv.archived).toList();

      // Sort by updated date (newest first)
      archived.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return archived;
    },
    orElse: () => [],
  );
});

// Reviewer mode provider (persisted)
final reviewerModeProvider = StateNotifierProvider<ReviewerModeNotifier, bool>(
  (ref) => ReviewerModeNotifier(ref.watch(optimizedStorageServiceProvider)),
);

class ReviewerModeNotifier extends StateNotifier<bool> {
  final OptimizedStorageService _storage;
  ReviewerModeNotifier(this._storage) : super(false) {
    _load();
  }
  Future<void> _load() async {
    final enabled = await _storage.getReviewerMode();
    state = enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _storage.setReviewerMode(enabled);
  }

  Future<void> toggle() => setEnabled(!state);
}

// User Settings providers
final userSettingsProvider = FutureProvider<UserSettings>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) {
    // Return default settings if no API
    return const UserSettings();
  }

  try {
    final settingsData = await api.getUserSettings();
    return UserSettings.fromJson(settingsData);
  } catch (e) {
    debugPrint('DEBUG: Error fetching user settings: $e');
    // Return default settings on error
    return const UserSettings();
  }
});

// Server Banners provider
final serverBannersProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    return await api.getBanners();
  } catch (e) {
    debugPrint('DEBUG: Error fetching banners: $e');
    return [];
  }
});

// Conversation Suggestions provider
final conversationSuggestionsProvider = FutureProvider<List<String>>((
  ref,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    return await api.getSuggestions();
  } catch (e) {
    debugPrint('DEBUG: Error fetching suggestions: $e');
    return [];
  }
});

// Folders provider
final foldersProvider = FutureProvider<List<Folder>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    final foldersData = await api.getFolders();
    return foldersData
        .map((folderData) => Folder.fromJson(folderData))
        .toList();
  } catch (e) {
    debugPrint('DEBUG: Error fetching folders: $e');
    return [];
  }
});

// Files provider
final userFilesProvider = FutureProvider<List<FileInfo>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    final filesData = await api.getUserFiles();
    return filesData.map((fileData) => FileInfo.fromJson(fileData)).toList();
  } catch (e) {
    debugPrint('DEBUG: Error fetching files: $e');
    return [];
  }
});

// File content provider
final fileContentProvider = FutureProvider.family<String, String>((
  ref,
  fileId,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) throw Exception('No API service available');

  try {
    return await api.getFileContent(fileId);
  } catch (e) {
    debugPrint('DEBUG: Error fetching file content: $e');
    throw Exception('Failed to load file content: $e');
  }
});

// Knowledge Base providers
final knowledgeBasesProvider = FutureProvider<List<KnowledgeBase>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    final kbData = await api.getKnowledgeBases();
    return kbData.map((data) => KnowledgeBase.fromJson(data)).toList();
  } catch (e) {
    debugPrint('DEBUG: Error fetching knowledge bases: $e');
    return [];
  }
});

final knowledgeBaseItemsProvider =
    FutureProvider.family<List<KnowledgeBaseItem>, String>((ref, kbId) async {
      final api = ref.watch(apiServiceProvider);
      if (api == null) return [];

      try {
        final itemsData = await api.getKnowledgeBaseItems(kbId);
        return itemsData
            .map((data) => KnowledgeBaseItem.fromJson(data))
            .toList();
      } catch (e) {
        debugPrint('DEBUG: Error fetching knowledge base items: $e');
        return [];
      }
    });

// Audio providers
final availableVoicesProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    return await api.getAvailableVoices();
  } catch (e) {
    debugPrint('DEBUG: Error fetching voices: $e');
    return [];
  }
});

// Image Generation providers
final imageModelsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return [];

  try {
    return await api.getImageModels();
  } catch (e) {
    debugPrint('DEBUG: Error fetching image models: $e');
    return [];
  }
});
