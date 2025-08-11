import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

/// Enhanced secure credential storage with platform-specific optimizations
class SecureCredentialStorage {
  late final FlutterSecureStorage _secureStorage;

  SecureCredentialStorage() {
    _secureStorage = FlutterSecureStorage(
      aOptions: _getAndroidOptions(),
      iOptions: _getIOSOptions(),
    );
  }

  static const String _credentialsKey = 'user_credentials_v2';
  static const String _serverConfigsKey = 'server_configs_v2';
  static const String _authTokenKey = 'auth_token_v2';

  /// Get Android-specific secure storage options
  AndroidOptions _getAndroidOptions() {
    return const AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'conduit_secure_prefs',
      preferencesKeyPrefix: 'conduit_',
      resetOnError: true,
      // Use more compatible encryption algorithms
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
    );
  }

  /// Get iOS-specific secure storage options
  IOSOptions _getIOSOptions() {
    return const IOSOptions(
      accountName: 'conduit_secure_storage',
      synchronizable: false,
    );
  }

  /// Save user credentials securely
  Future<void> saveCredentials({
    required String serverId,
    required String username,
    required String password,
  }) async {
    try {
      // First check if secure storage is available
      final isAvailable = await isSecureStorageAvailable();
      if (!isAvailable) {
        throw Exception('Secure storage is not available on this device');
      }

      final credentials = {
        'serverId': serverId,
        'username': username,
        'password': password,
        'savedAt': DateTime.now().toIso8601String(),
        'deviceId': await _getDeviceFingerprint(),
        'version': '2.0', // Version for migration purposes
      };

      final encryptedData = await _encryptData(jsonEncode(credentials));
      await _secureStorage.write(key: _credentialsKey, value: encryptedData);

      // Verify the save was successful by attempting to read it back
      final verifyData = await _secureStorage.read(key: _credentialsKey);
      if (verifyData == null || verifyData.isEmpty) {
        throw Exception(
          'Failed to verify credential save - storage returned null',
        );
      }

      debugPrint('DEBUG: Credentials saved and verified securely');
    } catch (e) {
      debugPrint('ERROR: Failed to save credentials: $e');
      rethrow;
    }
  }

  /// Retrieve saved credentials
  Future<Map<String, String>?> getSavedCredentials() async {
    try {
      final encryptedData = await _secureStorage.read(key: _credentialsKey);
      if (encryptedData == null || encryptedData.isEmpty) {
        return null;
      }

      final jsonString = await _decryptData(encryptedData);
      final decoded = jsonDecode(jsonString);

      if (decoded is! Map<String, dynamic>) {
        debugPrint('Warning: Invalid credentials format');
        await deleteSavedCredentials();
        return null;
      }

      // Validate device fingerprint for additional security, but be more lenient
      final savedDeviceId = decoded['deviceId']?.toString();
      if (savedDeviceId != null) {
        final currentDeviceId = await _getDeviceFingerprint();

        if (savedDeviceId != currentDeviceId) {
          debugPrint(
            'Info: Device fingerprint changed, but allowing credential access for better UX',
          );
          // Don't clear credentials immediately - allow the user to continue
          // They can re-login if needed, which will update the fingerprint
        }
      }

      // Validate required fields
      if (!decoded.containsKey('serverId') ||
          !decoded.containsKey('username') ||
          !decoded.containsKey('password')) {
        debugPrint(
          'Warning: Invalid saved credentials format - missing required fields',
        );
        await deleteSavedCredentials();
        return null;
      }

      // Check if credentials are too old (optional expiration)
      final savedAt = decoded['savedAt']?.toString();
      if (savedAt != null) {
        try {
          final savedTime = DateTime.parse(savedAt);
          final now = DateTime.now();
          final daysSinceCreated = now.difference(savedTime).inDays;

          // Warn if credentials are very old (but don't delete them)
          if (daysSinceCreated > 90) {
            debugPrint(
              'Info: Saved credentials are $daysSinceCreated days old',
            );
          }
        } catch (e) {
          debugPrint('Warning: Could not parse savedAt timestamp: $e');
        }
      }

      return {
        'serverId': decoded['serverId']?.toString() ?? '',
        'username': decoded['username']?.toString() ?? '',
        'password': decoded['password']?.toString() ?? '',
        'savedAt': decoded['savedAt']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('ERROR: Failed to retrieve credentials: $e');
      // Don't delete credentials on retrieval errors - they might be recoverable
      return null;
    }
  }

  /// Delete saved credentials
  Future<void> deleteSavedCredentials() async {
    try {
      await _secureStorage.delete(key: _credentialsKey);
      debugPrint('DEBUG: Credentials deleted');
    } catch (e) {
      debugPrint('ERROR: Failed to delete credentials: $e');
    }
  }

  /// Save auth token securely
  Future<void> saveAuthToken(String token) async {
    try {
      final encryptedToken = await _encryptData(token);
      await _secureStorage.write(key: _authTokenKey, value: encryptedToken);
    } catch (e) {
      debugPrint('ERROR: Failed to save auth token: $e');
      rethrow;
    }
  }

  /// Get auth token
  Future<String?> getAuthToken() async {
    try {
      final encryptedToken = await _secureStorage.read(key: _authTokenKey);
      if (encryptedToken == null) return null;

      return await _decryptData(encryptedToken);
    } catch (e) {
      debugPrint('ERROR: Failed to retrieve auth token: $e');
      return null;
    }
  }

  /// Delete auth token
  Future<void> deleteAuthToken() async {
    try {
      await _secureStorage.delete(key: _authTokenKey);
    } catch (e) {
      debugPrint('ERROR: Failed to delete auth token: $e');
    }
  }

  /// Save server configurations securely
  Future<void> saveServerConfigs(String configsJson) async {
    try {
      final encryptedConfigs = await _encryptData(configsJson);
      await _secureStorage.write(
        key: _serverConfigsKey,
        value: encryptedConfigs,
      );
    } catch (e) {
      debugPrint('ERROR: Failed to save server configs: $e');
      rethrow;
    }
  }

  /// Get server configurations
  Future<String?> getServerConfigs() async {
    try {
      final encryptedConfigs = await _secureStorage.read(
        key: _serverConfigsKey,
      );
      if (encryptedConfigs == null) return null;

      return await _decryptData(encryptedConfigs);
    } catch (e) {
      debugPrint('ERROR: Failed to retrieve server configs: $e');
      return null;
    }
  }

  /// Check if secure storage is available
  Future<bool> isSecureStorageAvailable() async {
    try {
      // Test write and read
      const testKey = 'test_availability';
      const testValue = 'test';

      await _secureStorage.write(key: testKey, value: testValue);
      final result = await _secureStorage.read(key: testKey);
      await _secureStorage.delete(key: testKey);

      return result == testValue;
    } catch (e) {
      debugPrint('WARNING: Secure storage not available: $e');
      return false;
    }
  }

  /// Clear all secure data
  Future<void> clearAll() async {
    try {
      await _secureStorage.deleteAll();
      debugPrint('DEBUG: All secure data cleared');
    } catch (e) {
      debugPrint('ERROR: Failed to clear secure data: $e');
    }
  }

  /// Encrypt data using additional layer of encryption
  Future<String> _encryptData(String data) async {
    try {
      // For now, return the data as-is since FlutterSecureStorage already provides encryption
      // In a more advanced implementation, you could add an additional layer of AES encryption
      return data;
    } catch (e) {
      debugPrint('ERROR: Failed to encrypt data: $e');
      rethrow;
    }
  }

  /// Decrypt data
  Future<String> _decryptData(String encryptedData) async {
    try {
      // For now, return the data as-is since FlutterSecureStorage handles decryption
      // This matches the encryption method above
      return encryptedData;
    } catch (e) {
      debugPrint('ERROR: Failed to decrypt data: $e');
      rethrow;
    }
  }

  /// Generate a device fingerprint for additional security
  Future<String> _getDeviceFingerprint() async {
    try {
      // Create a more stable device fingerprint
      final platformInfo = {
        'platform': Platform.operatingSystem,
        // Use only major version to avoid fingerprint changes on minor updates
        'majorVersion': Platform.operatingSystemVersion.split('.').first,
        'isPhysicalDevice': true, // In a real implementation, you'd detect this
        // Add a static component to ensure consistency
        'appId': 'conduit_app_v1',
      };

      final fingerprintData = jsonEncode(platformInfo);
      final bytes = utf8.encode(fingerprintData);
      final digest = sha256.convert(bytes);

      return digest.toString();
    } catch (e) {
      debugPrint('WARNING: Failed to generate device fingerprint: $e');
      // Return a consistent fallback fingerprint
      return 'stable_fallback_device_id';
    }
  }

  /// Migrate from old storage format if needed
  Future<void> migrateFromOldStorage(
    Map<String, String>? oldCredentials,
  ) async {
    if (oldCredentials == null) return;

    try {
      await saveCredentials(
        serverId: oldCredentials['serverId'] ?? '',
        username: oldCredentials['username'] ?? '',
        password: oldCredentials['password'] ?? '',
      );
      debugPrint(
        'DEBUG: Successfully migrated credentials to new secure format',
      );
    } catch (e) {
      debugPrint('ERROR: Failed to migrate credentials: $e');
    }
  }
}
