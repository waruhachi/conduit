import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';
import '../models/conversation.dart';
import 'secure_credential_storage.dart';
import '../utils/debug_logger.dart';

class StorageService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;
  final SecureCredentialStorage _secureCredentialStorage;

  StorageService({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences prefs,
  }) : _secureStorage = secureStorage,
       _prefs = prefs,
       _secureCredentialStorage = SecureCredentialStorage(
         instance: secureStorage,
       );

  // Secure storage keys
  static const String _authTokenKey = 'auth_token';
  static const String _serverConfigsKey = 'server_configs';
  static const String _activeServerIdKey = 'active_server_id';
  static const String _credentialsKey = 'saved_credentials';
  static const String _rememberCredentialsKey = 'remember_credentials';

  // Shared preferences keys
  static const String _themeModeKey = 'theme_mode';
  static const String _localConversationsKey = 'local_conversations';

  // Auth token management - using enhanced secure storage
  Future<void> saveAuthToken(String token) async {
    // Try enhanced secure storage first, fallback to legacy if needed
    try {
      await _secureCredentialStorage.saveAuthToken(token);
    } catch (e) {
      DebugLogger.log(
        'Enhanced secure storage failed, using fallback: $e',
        scope: 'storage',
      );
      await _secureStorage.write(key: _authTokenKey, value: token);
    }
  }

  Future<String?> getAuthToken() async {
    // Try enhanced secure storage first, fallback to legacy if needed
    try {
      final token = await _secureCredentialStorage.getAuthToken();
      if (token != null) return token;
    } catch (e) {
      DebugLogger.log(
        'Enhanced secure storage failed, using fallback: $e',
        scope: 'storage',
      );
    }

    // Fallback to legacy storage
    return await _secureStorage.read(key: _authTokenKey);
  }

  Future<void> deleteAuthToken() async {
    // Clear from both storages to ensure complete cleanup
    try {
      await _secureCredentialStorage.deleteAuthToken();
    } catch (e) {
      DebugLogger.log(
        'Failed to delete from enhanced storage: $e',
        scope: 'storage',
      );
    }

    await _secureStorage.delete(key: _authTokenKey);
  }

  // Credential management for auto-login - using enhanced secure storage
  Future<void> saveCredentials({
    required String serverId,
    required String username,
    required String password,
  }) async {
    // Try enhanced secure storage first, fallback to legacy if needed
    try {
      // Check if enhanced secure storage is available
      final isSecureAvailable = await _secureCredentialStorage
          .isSecureStorageAvailable();
      if (!isSecureAvailable) {
        DebugLogger.log(
          'Enhanced secure storage not available, using legacy storage',
          scope: 'storage',
        );
        throw Exception('Enhanced secure storage not available');
      }

      await _secureCredentialStorage.saveCredentials(
        serverId: serverId,
        username: username,
        password: password,
      );
      DebugLogger.log(
        'Credentials saved using enhanced secure storage',
        scope: 'storage',
      );
    } catch (e) {
      DebugLogger.log(
        'Enhanced secure storage failed, using fallback: $e',
        scope: 'storage',
      );

      // Fallback to legacy storage
      try {
        final credentials = {
          'serverId': serverId,
          'username': username,
          'password': password,
          'savedAt': DateTime.now().toIso8601String(),
        };

        await _secureStorage.write(
          key: _credentialsKey,
          value: jsonEncode(credentials),
        );

        // Verify the fallback save
        final verifyData = await _secureStorage.read(key: _credentialsKey);
        if (verifyData == null || verifyData.isEmpty) {
          throw Exception(
            'Failed to save credentials even with fallback storage',
          );
        }

        DebugLogger.log(
          'Credentials saved using fallback storage',
          scope: 'storage',
        );
      } catch (fallbackError) {
        DebugLogger.log(
          'Both enhanced and fallback credential storage failed: $fallbackError',
          scope: 'storage',
        );
        rethrow;
      }
    }
  }

  Future<Map<String, String>?> getSavedCredentials() async {
    // Try enhanced secure storage first
    try {
      final credentials = await _secureCredentialStorage.getSavedCredentials();
      if (credentials != null) {
        return credentials;
      }
    } catch (e) {
      DebugLogger.log(
        'Enhanced secure storage failed, using fallback: $e',
        scope: 'storage',
      );
    }

    // Fallback to legacy storage and migrate if found
    try {
      final jsonString = await _secureStorage.read(key: _credentialsKey);
      if (jsonString == null || jsonString.isEmpty) return null;

      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) return null;

      // Validate that credentials have required fields
      if (!decoded.containsKey('serverId') ||
          !decoded.containsKey('username') ||
          !decoded.containsKey('password')) {
        DebugLogger.log('Invalid saved credentials format', scope: 'storage');
        await deleteSavedCredentials();
        return null;
      }

      final legacyCredentials = {
        'serverId': decoded['serverId']?.toString() ?? '',
        'username': decoded['username']?.toString() ?? '',
        'password': decoded['password']?.toString() ?? '',
        'savedAt': decoded['savedAt']?.toString() ?? '',
      };

      // Attempt to migrate to enhanced storage
      try {
        await _secureCredentialStorage.migrateFromOldStorage(legacyCredentials);
        // If migration successful, clean up legacy storage
        await _secureStorage.delete(key: _credentialsKey);
        DebugLogger.log(
          'Successfully migrated credentials to enhanced storage',
          scope: 'storage',
        );
      } catch (e) {
        DebugLogger.log('Failed to migrate credentials: $e', scope: 'storage');
      }

      return legacyCredentials;
    } catch (e) {
      DebugLogger.log('Error loading saved credentials: $e', scope: 'storage');
      return null;
    }
  }

  Future<void> deleteSavedCredentials() async {
    // Clear from both storages to ensure complete cleanup
    try {
      await _secureCredentialStorage.deleteSavedCredentials();
    } catch (e) {
      DebugLogger.log(
        'Failed to delete from enhanced storage: $e',
        scope: 'storage',
      );
    }

    await _secureStorage.delete(key: _credentialsKey);
    await setRememberCredentials(false);
  }

  // Remember credentials preference
  Future<void> setRememberCredentials(bool remember) async {
    await _prefs.setBool(_rememberCredentialsKey, remember);
  }

  bool getRememberCredentials() {
    return _prefs.getBool(_rememberCredentialsKey) ?? false;
  }

  // Server configuration management
  Future<void> saveServerConfigs(List<ServerConfig> configs) async {
    final json = configs.map((c) => c.toJson()).toList();
    await _secureStorage.write(key: _serverConfigsKey, value: jsonEncode(json));
  }

  Future<List<ServerConfig>> getServerConfigs() async {
    try {
      final jsonString = await _secureStorage.read(key: _serverConfigsKey);
      if (jsonString == null || jsonString.isEmpty) return [];

      final decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        DebugLogger.log(
          'Server configs data is not a list, resetting',
          scope: 'storage',
        );
        return [];
      }

      final configs = <ServerConfig>[];
      for (final item in decoded) {
        try {
          if (item is Map<String, dynamic>) {
            // Validate required fields before parsing
            if (item.containsKey('id') &&
                item.containsKey('name') &&
                item.containsKey('url')) {
              configs.add(ServerConfig.fromJson(item));
            } else {
              DebugLogger.log(
                'Skipping invalid server config: missing required fields',
                scope: 'storage',
              );
            }
          }
        } catch (e) {
          DebugLogger.log(
            'Failed to parse server config: $e',
            scope: 'storage',
          );
          // Continue with other configs
        }
      }

      return configs;
    } catch (e) {
      DebugLogger.log('Error loading server configs: $e', scope: 'storage');
      return [];
    }
  }

  Future<void> setActiveServerId(String? serverId) async {
    if (serverId == null) {
      await _secureStorage.delete(key: _activeServerIdKey);
    } else {
      await _secureStorage.write(key: _activeServerIdKey, value: serverId);
    }
  }

  Future<String?> getActiveServerId() async {
    return await _secureStorage.read(key: _activeServerIdKey);
  }

  // Theme management
  String? getThemeMode() {
    return _prefs.getString(_themeModeKey);
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_themeModeKey, mode);
  }

  // Local conversation management
  Future<List<Conversation>> getLocalConversations() async {
    final jsonString = _prefs.getString(_localConversationsKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        DebugLogger.log(
          'Local conversations data is not a list, resetting',
          scope: 'storage',
        );
        return [];
      }

      final conversations = <Conversation>[];
      for (final item in decoded) {
        try {
          if (item is Map<String, dynamic>) {
            // Validate required fields before parsing
            if (item.containsKey('id') &&
                item.containsKey('title') &&
                item.containsKey('createdAt') &&
                item.containsKey('updatedAt')) {
              conversations.add(Conversation.fromJson(item));
            } else {
              DebugLogger.log(
                'Skipping invalid conversation: missing required fields',
                scope: 'storage',
              );
            }
          }
        } catch (e) {
          DebugLogger.log('Failed to parse conversation: $e', scope: 'storage');
          // Continue with other conversations
        }
      }

      return conversations;
    } catch (e) {
      DebugLogger.log(
        'Error parsing local conversations: $e',
        scope: 'storage',
      );
      return [];
    }
  }

  Future<void> saveLocalConversations(List<Conversation> conversations) async {
    try {
      final json = conversations.map((c) => c.toJson()).toList();
      await _prefs.setString(_localConversationsKey, jsonEncode(json));
    } catch (e) {
      DebugLogger.log('Error saving local conversations: $e', scope: 'storage');
    }
  }

  Future<void> addLocalConversation(Conversation conversation) async {
    final conversations = await getLocalConversations();
    conversations.add(conversation);
    await saveLocalConversations(conversations);
  }

  Future<void> updateLocalConversation(Conversation conversation) async {
    final conversations = await getLocalConversations();
    final index = conversations.indexWhere((c) => c.id == conversation.id);
    if (index != -1) {
      conversations[index] = conversation;
      await saveLocalConversations(conversations);
    }
  }

  Future<void> deleteLocalConversation(String conversationId) async {
    final conversations = await getLocalConversations();
    conversations.removeWhere((c) => c.id == conversationId);
    await saveLocalConversations(conversations);
  }

  // Clear all data
  Future<void> clearAll() async {
    // Clear enhanced secure storage
    try {
      await _secureCredentialStorage.clearAll();
    } catch (e) {
      DebugLogger.log('Failed to clear enhanced storage: $e', scope: 'storage');
    }

    // Clear legacy storage
    await _secureStorage.deleteAll();
    await _prefs.clear();

    DebugLogger.log('All storage cleared', scope: 'storage');
  }

  // Clear only auth-related data (keeping server configs and other settings)
  Future<void> clearAuthData() async {
    await deleteAuthToken();
    await deleteSavedCredentials();
    DebugLogger.log('Auth data cleared', scope: 'storage');
  }

  /// Check if enhanced secure storage is available
  Future<bool> isEnhancedSecureStorageAvailable() async {
    try {
      return await _secureCredentialStorage.isSecureStorageAvailable();
    } catch (e) {
      DebugLogger.log(
        'Failed to check enhanced storage availability: $e',
        scope: 'storage',
      );
      return false;
    }
  }
}
