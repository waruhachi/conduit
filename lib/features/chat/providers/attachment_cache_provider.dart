import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/debug_logger.dart';

// Global attachment cache state
class AttachmentCacheState {
  final Map<String, String> imageDataCache;
  final Map<String, bool> loadingStates;
  final Map<String, String> errorStates;

  AttachmentCacheState({
    required this.imageDataCache,
    required this.loadingStates,
    required this.errorStates,
  });

  AttachmentCacheState copyWith({
    Map<String, String>? imageDataCache,
    Map<String, bool>? loadingStates,
    Map<String, String>? errorStates,
  }) {
    return AttachmentCacheState(
      imageDataCache: imageDataCache ?? this.imageDataCache,
      loadingStates: loadingStates ?? this.loadingStates,
      errorStates: errorStates ?? this.errorStates,
    );
  }
}

class AttachmentCacheNotifier extends StateNotifier<AttachmentCacheState> {
  AttachmentCacheNotifier()
      : super(AttachmentCacheState(
          imageDataCache: {},
          loadingStates: {},
          errorStates: {},
        ));

  void cacheImageData(String attachmentId, String imageData) {
    DebugLogger.log('Caching image data for: $attachmentId');
    state = state.copyWith(
      imageDataCache: {
        ...state.imageDataCache,
        attachmentId: imageData,
      },
    );
    
    // Limit cache size to prevent memory issues
    if (state.imageDataCache.length > 100) {
      final newCache = Map<String, String>.from(state.imageDataCache);
      final keysToRemove = newCache.keys.take(20).toList();
      for (final key in keysToRemove) {
        newCache.remove(key);
        state.loadingStates.remove(key);
        state.errorStates.remove(key);
      }
      state = state.copyWith(imageDataCache: newCache);
    }
  }

  String? getCachedImageData(String attachmentId) {
    return state.imageDataCache[attachmentId];
  }

  void setLoadingState(String attachmentId, bool isLoading) {
    state = state.copyWith(
      loadingStates: {
        ...state.loadingStates,
        attachmentId: isLoading,
      },
    );
  }

  bool isLoading(String attachmentId) {
    return state.loadingStates[attachmentId] ?? false;
  }

  void setErrorState(String attachmentId, String? error) {
    if (error == null) {
      final newErrorStates = Map<String, String>.from(state.errorStates);
      newErrorStates.remove(attachmentId);
      state = state.copyWith(errorStates: newErrorStates);
    } else {
      state = state.copyWith(
        errorStates: {
          ...state.errorStates,
          attachmentId: error,
        },
      );
    }
  }

  String? getErrorState(String attachmentId) {
    return state.errorStates[attachmentId];
  }

  void clearCache() {
    state = AttachmentCacheState(
      imageDataCache: {},
      loadingStates: {},
      errorStates: {},
    );
  }

  void clearAttachmentCache(String attachmentId) {
    final newImageCache = Map<String, String>.from(state.imageDataCache);
    final newLoadingStates = Map<String, bool>.from(state.loadingStates);
    final newErrorStates = Map<String, String>.from(state.errorStates);
    
    newImageCache.remove(attachmentId);
    newLoadingStates.remove(attachmentId);
    newErrorStates.remove(attachmentId);
    
    state = AttachmentCacheState(
      imageDataCache: newImageCache,
      loadingStates: newLoadingStates,
      errorStates: newErrorStates,
    );
  }
}

final attachmentCacheProvider =
    StateNotifierProvider<AttachmentCacheNotifier, AttachmentCacheState>((ref) {
  return AttachmentCacheNotifier();
});

// Helper providers for easier access
final cachedImageDataProvider = Provider.family<String?, String>((ref, attachmentId) {
  final cache = ref.watch(attachmentCacheProvider);
  return cache.imageDataCache[attachmentId];
});

final attachmentLoadingStateProvider = Provider.family<bool, String>((ref, attachmentId) {
  final cache = ref.watch(attachmentCacheProvider);
  return cache.loadingStates[attachmentId] ?? false;
});

final attachmentErrorStateProvider = Provider.family<String?, String>((ref, attachmentId) {
  final cache = ref.watch(attachmentCacheProvider);
  return cache.errorStates[attachmentId];
});