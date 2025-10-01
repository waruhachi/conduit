import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/app_providers.dart';

part 'connectivity_service.g.dart';

enum ConnectivityStatus { online, offline, checking }

class ConnectivityService {
  final Dio _dio;
  final Ref _ref;
  Timer? _connectivityTimer;
  final _connectivityController =
      StreamController<ConnectivityStatus>.broadcast();
  ConnectivityStatus _lastStatus = ConnectivityStatus.checking;
  int _recentFailures = 0;
  Duration _interval = const Duration(seconds: 10);
  int _lastLatencyMs = -1;

  ConnectivityService(this._dio, this._ref) {
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
    final serverReachability = await _probeActiveServer();
    if (serverReachability != null) {
      if (serverReachability) {
        _updateStatus(ConnectivityStatus.online);
      } else {
        _lastLatencyMs = -1;
        _updateStatus(ConnectivityStatus.offline);
      }
      return;
    }

    final fallbackReachability = await _probeAnyKnownServer();
    if (fallbackReachability != null) {
      if (fallbackReachability) {
        _updateStatus(ConnectivityStatus.online);
      } else {
        _lastLatencyMs = -1;
        _updateStatus(ConnectivityStatus.offline);
      }
      return;
    }

    // No configured server to probe; assume usable connectivity so setup flows continue.
    _lastLatencyMs = -1;
    _updateStatus(ConnectivityStatus.online);
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

  Future<bool?> _probeActiveServer() async {
    final healthUri = _resolveHealthUri();
    if (healthUri == null) return null;

    return _probeHealthEndpoint(healthUri, updateLatency: true);
  }

  Future<bool?> _probeAnyKnownServer() async {
    try {
      final configs = await _ref.read(serverConfigsProvider.future);
      for (final config in configs) {
        final uri = _buildHealthUri(config.url);
        if (uri == null) continue;
        final result = await _probeHealthEndpoint(uri);
        if (result != null) {
          return result;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool?> _probeHealthEndpoint(
    Uri uri, {
    bool updateLatency = false,
  }) async {
    try {
      final start = DateTime.now();
      final response = await _dio
          .getUri(
            uri,
            options: Options(
              method: 'GET',
              sendTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
            ),
          )
          .timeout(const Duration(seconds: 4));

      final isHealthy =
          response.statusCode == 200 && _responseIndicatesHealth(response.data);
      if (isHealthy && updateLatency) {
        _lastLatencyMs = DateTime.now().difference(start).inMilliseconds;
      }
      return isHealthy;
    } catch (_) {
      // Treat as unreachable.
      return false;
    }
  }

  Uri? _resolveHealthUri() {
    final api = _ref.read(apiServiceProvider);
    if (api != null) {
      return _buildHealthUri(api.baseUrl);
    }

    final activeServer = _ref.read(activeServerProvider);
    return activeServer.maybeWhen(
      data: (server) => server != null ? _buildHealthUri(server.url) : null,
      orElse: () => null,
    );
  }

  Uri? _buildHealthUri(String baseUrl) {
    if (baseUrl.isEmpty) return null;

    Uri? parsed = Uri.tryParse(baseUrl.trim());
    if (parsed == null) return null;

    if (!parsed.hasScheme) {
      parsed =
          Uri.tryParse('https://$baseUrl') ?? Uri.tryParse('http://$baseUrl');
    }
    if (parsed == null) return null;

    return parsed.resolve('health');
  }

  bool _responseIndicatesHealth(dynamic data) {
    if (data is Map) {
      final dynamic status = data['status'];
      if (status is bool) return status;
      if (status is num) return status != 0;
    }
    return true;
  }
}

// Providers
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  // Use a lightweight Dio instance only for connectivity checks
  final dio = Dio();
  final service = ConnectivityService(dio, ref);
  ref.onDispose(() => service.dispose());
  return service;
});

@Riverpod(keepAlive: true)
class ConnectivityStatusNotifier extends _$ConnectivityStatusNotifier {
  StreamSubscription<ConnectivityStatus>? _subscription;

  @override
  FutureOr<ConnectivityStatus> build() {
    final service = ref.watch(connectivityServiceProvider);

    _subscription?.cancel();
    _subscription = service.connectivityStream.listen(
      (status) => state = AsyncValue.data(status),
      onError: (error, stackTrace) =>
          state = AsyncValue.error(error, stackTrace),
    );

    ref.onDispose(() {
      _subscription?.cancel();
      _subscription = null;
    });

    return service.currentStatus;
  }
}

final isOnlineProvider = Provider<bool>((ref) {
  // In reviewer mode, treat app as online to enable flows
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) return true;
  final status = ref.watch(connectivityStatusProvider);
  return status.when(
    data: (status) => status != ConnectivityStatus.offline,
    loading: () => true, // Assume online while checking
    error: (_, _) =>
        true, // Assume online on error to avoid false offline states
  );
});

// Dio provider (if not already defined elsewhere)
// Removed unused Dio provider to avoid confusion. Use ApiService instead.
