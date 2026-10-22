import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network availability is a trigger only; REST responses decide reachability.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();
  final Connectivity _connectivity;
  bool available = true;
  bool _started = false;
  bool _disposed = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void> start(void Function(bool) onChange) async {
    if (_started || _disposed) return;
    _started = true;
    var initialized = false;
    void update(List<ConnectivityResult> results) {
      if (_disposed) return;
      final previous = available;
      available = results.any((r) => r != ConnectivityResult.none);
      if (!initialized || previous != available) {
        initialized = true;
        onChange(available);
      }
    }

    void unknown() {
      if (_disposed) return;
      if (!initialized) {
        initialized = true;
        onChange(available);
      }
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      update,
      onError: (Object _) => unknown(),
    );
    try {
      update(await _connectivity.checkConnectivity());
    } catch (_) {
      // A missing network signal does not prove the REST server is unreachable.
      unknown();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
  }
}
