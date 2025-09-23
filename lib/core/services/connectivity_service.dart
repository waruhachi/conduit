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
  int _recentFailures = 0;
  Duration _interval = const Duration(seconds: 10);
  int _lastLatencyMs = -1;

  ConnectivityService(this._dio) {
    _startConnectivityMonitoring();
  }

  Stream<ConnectivityStatus> get connectivityStream =>
      _connectivityController.stream;
  ConnectivityStatus get currentStatus => _lastStatus;
  int get lastLatencyMs => _lastLatencyMs;

  /// Stream that emits true when connected, false when offline
  Stream<bool> get isConnected =>
      connectivityStream.map((status) => status == ConnectivityStatus.online);

  /// Check if currently connected
  bool get isCurrentlyConnected => _lastStatus == ConnectivityStatus.online;

  void _startConnectivityMonitoring() {
    // Initial check after a brief delay to avoid showing offline during startup
    Timer(const Duration(milliseconds: 800), () {
      _checkConnectivity();
    });

    // Check periodically; interval adapts to recent failures
    _connectivityTimer = Timer.periodic(_interval, (_) {
      _checkConnectivity();
    });
  }

  Future<void> _checkConnectivity() async {
    try {
      // DNS lookup is a lightweight, permission-free reachability check
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 2));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.online);
        return;
      }
    } catch (_) {
      // Swallow and continue to HTTP reachability check
    }

    // As a secondary check, hit a public 204 endpoint that returns quickly
    try {
      final start = DateTime.now();
      await _dio
          .get(
            'https://www.google.com/generate_204',
            options: Options(
              method: 'GET',
              sendTimeout: const Duration(seconds: 2),
              receiveTimeout: const Duration(seconds: 2),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 400,
            ),
          )
          .timeout(const Duration(seconds: 2));
      _lastLatencyMs = DateTime.now().difference(start).inMilliseconds;
      _updateStatus(ConnectivityStatus.online);
    } catch (_) {
      _lastLatencyMs = -1;
      _updateStatus(ConnectivityStatus.offline);
    }
  }

  void _updateStatus(ConnectivityStatus status) {
    if (_lastStatus != status) {
      _lastStatus = status;
      _connectivityController.add(status);
    }

    // Adapt polling interval based on recent failures to reduce battery/CPU
    if (status == ConnectivityStatus.offline) {
      _recentFailures = (_recentFailures + 1).clamp(0, 10);
    } else if (status == ConnectivityStatus.online) {
      _recentFailures = 0;
    }

    final newInterval = _recentFailures >= 3
        ? const Duration(seconds: 20)
        : _recentFailures == 2
        ? const Duration(seconds: 15)
        : const Duration(seconds: 10);

    if (newInterval != _interval) {
      _interval = newInterval;
      _connectivityTimer?.cancel();
      _connectivityTimer = Timer.periodic(
        _interval,
        (_) => _checkConnectivity(),
      );
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
  // Use a lightweight Dio instance only for connectivity checks
  final dio = Dio();
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
// Removed unused Dio provider to avoid confusion. Use ApiService instead.
