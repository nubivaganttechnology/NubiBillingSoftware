import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/android_sqlite_face_vault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nubibill/face_vault');
  const store = AndroidSqliteFaceVaultStore(tenantId: 'SYNTHETIC-TENANT');
  final calls = <MethodCall>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'read' => 'SYNTHETIC VALUE',
            'compareAndSwap' || 'checkClock' => true,
            'deviceId' => 'SYNTHETIC-DEVICE',
            'timeZoneId' => 'Asia/Kolkata',
            _ => null,
          };
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('Android adapter sends scoped lifecycle calls only to its local native channel', () async {
    expect(await store.read('face.template.v1.fixture'), 'SYNTHETIC VALUE');
    expect(
      await store.compareAndSwap(
        'face.template.v1.fixture',
        null,
        'SYNTHETIC VALUE',
      ),
      isTrue,
    );
    await store.delete('face.template.v1.fixture');
    expect(await store.deviceId(), 'SYNTHETIC-DEVICE');
    expect(await store.clockIsReliable(), isTrue);
    expect(await store.timeZoneId(), 'Asia/Kolkata');
    await store.confirmDeviceTime();
    await store.resetDeviceVault();
    expect(calls.map((c) => c.method), [
      'read',
      'compareAndSwap',
      'delete',
      'deviceId',
      'checkClock',
      'timeZoneId',
      'confirmDeviceTime',
      'reset',
    ]);
    expect(
      calls.every((c) => c.arguments['tenantId'] == 'SYNTHETIC-TENANT'),
      isTrue,
    );
  });
  test(
    'native key or decryption failure becomes a generic manual fallback error',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
              code: 'KEY_LOST',
              message: 'DO NOT EXPOSE SENSITIVE DETAIL',
            ),
          );
      await expectLater(
        store.read('face.template.v1.fixture'),
        throwsA(
          predicate(
            (Object e) =>
                e.toString().contains('manual attendance') &&
                !e.toString().contains('SENSITIVE DETAIL'),
          ),
        ),
      );
    },
  );
  test('non-Android platforms never call the protected vault', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await expectLater(store.deviceId(), throwsException);
    expect(calls, isEmpty);
  });
}
