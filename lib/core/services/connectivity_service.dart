import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers/app_providers.dart';

enum ConnectivityStatus { online, offline, checking }

class ConnectivityService {
  final Dio _dio;
  Timer? _connectivityTimer;
  final _connectivityController =
      StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _lastStatus = ConnectivityStatus.checking;

  ConnectivityService(this._dio) {
    _startConnectivityMonitoring();
  }

  Stream<ConnectivityStatus> get connectivityStream =>
      _connectivityController.stream;
  ConnectivityStatus get currentStatus => _lastStatus;

  void _startConnectivityMonitoring() {
    // Initial check after a brief delay to avoid showing offline during startup
    Timer(const Duration(milliseconds: 1000), () {
      _checkConnectivity();
    });

    // Check every 5 seconds
    _connectivityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      // DNS lookup is a lightweight, permission-free reachability check
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.online);
        return;
      }
    } catch (_) {
      // Swallow and continue to HTTP reachability check
    }

    // As a secondary check, hit a public 204 endpoint that returns quickly
    try {
      await _dio
          .get(
            'https://www.google.com/generate_204',
            options: Options(
              method: 'GET',
              sendTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
            ),
          )
          .timeout(const Duration(seconds: 3));
      _updateStatus(ConnectivityStatus.online);
    } catch (_) {
      _updateStatus(ConnectivityStatus.offline);
    }
  }

  void _updateStatus(ConnectivityStatus status) {
    if (_lastStatus != status) {
      _lastStatus = status;
      _connectivityController.add(status);
    }
  }

  Future<bool> checkConnectivity() async {
    await _checkConnectivity();
    return _lastStatus == ConnectivityStatus.online;
  }

  void dispose() {
    _connectivityTimer?.cancel();
    _connectivityController.close();
  }
}

// Providers
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final dio = ref.watch(dioProvider);
  final service = ConnectivityService(dio);
  ref.onDispose(() => service.dispose());
  return service;
});

final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.connectivityStream;
});

final isOnlineProvider = Provider<bool>((ref) {
  // In reviewer mode, treat app as online to enable flows
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) return true;
  final status = ref.watch(connectivityStatusProvider);
  return status.when(
    data: (status) => status == ConnectivityStatus.online,
    loading: () => true, // Assume online while checking
    error: (_, _) =>
        true, // Assume online on error to avoid false offline states
  );
});

// Dio provider (if not already defined elsewhere)
final dioProvider = Provider<Dio>((ref) {
  return Dio(); // This should be configured with your base URL
});
