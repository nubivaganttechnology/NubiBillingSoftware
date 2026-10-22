import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';

class Signals implements Connectivity {
  final controller = StreamController<List<ConnectivityResult>>();
  bool missingPlugin = false;
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    if (missingPlugin) throw StateError('Unavailable platform signal');
    return [ConnectivityResult.none];
  }
}

void main() {
  test(
    'duplicate network signals and stream errors do not generate reconnects',
    () async {
      final signals = Signals();
      final service = ConnectivityService(connectivity: signals);
      final events = <bool>[];
      await service.start(events.add);
      signals.controller.addError(StateError('Signal failure'));
      await Future<void>.delayed(Duration.zero);
      expect(service.available, false);
      expect(events, [false]);
      signals.controller.add([ConnectivityResult.wifi]);
      signals.controller.add([ConnectivityResult.wifi]);
      signals.controller.addError(StateError('Another signal failure'));
      await Future<void>.delayed(Duration.zero);
      expect(events, [false, true]);
      await service.dispose();
      await signals.controller.close();
    },
  );

  test(
    'unknown initial signal is reported once without repeated read triggers',
    () async {
      final signals = Signals()..missingPlugin = true;
      final service = ConnectivityService(connectivity: signals);
      final events = <bool>[];
      await service.start(events.add);
      signals.controller.addError(StateError('Missing plugin'));
      signals.controller.addError(StateError('Missing plugin again'));
      await Future<void>.delayed(Duration.zero);
      expect(events, [true]);
      await service.dispose();
      await signals.controller.close();
    },
  );
  test('starting connectivity twice registers only one listener', () async {
    final signals = Signals();
    final service = ConnectivityService(connectivity: signals);
    final events = <bool>[];
    await service.start(events.add);
    await service.start(events.add);
    signals.controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(events, [false, true]);
    await service.dispose();
    signals.controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(Duration.zero);
    expect(events, [false, true]);
    await signals.controller.close();
  });
}
