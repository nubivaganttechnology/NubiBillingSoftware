import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import 'face_biometric_vault.dart';

/// Native SQLite stores opaque keys, random IVs and AES-GCM ciphertext only.
/// This adapter has no Firestore, analytics, image or outbox dependency.
class AndroidSqliteFaceVaultStore implements FaceVaultAtomicValueStore {
  const AndroidSqliteFaceVaultStore({required this.tenantId});
  final String tenantId;
  static const _channel = MethodChannel('nubibill/face_vault');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const AppException('The protected face vault requires Android.');
    }
    try {
      return await _channel.invokeMethod<T>(method, {
        'tenantId': tenantId,
        ...?args,
      });
    } on PlatformException {
      throw const AppException(
        'The protected face vault is unavailable. Use manual attendance. '
        'An owner may reset the device vault and arrange re-enrollment.',
      );
    }
  }

  @override
  Future<String?> read(String key) => _call<String>('read', {'key': key});
  @override
  Future<void> write(String key, String value) async {
    await _call<void>('write', {'key': key, 'value': value});
  }

  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async =>
      await _call<bool>('compareAndSwap', {
        'key': key,
        'expected': expected,
        'value': value,
      }) ??
      false;
  @override
  Future<void> delete(String key) async {
    await _call<void>('delete', {'key': key});
  }

  @override
  Future<Uint8List?> readBytes(String key) =>
      _call<Uint8List>('readBytes', {'key': key});

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    await _call<void>('writeBytes', {'key': key, 'bytes': bytes});
  }

  @override
  Future<List<String>> listKeys(String prefix) async {
    final list = await _call<List<dynamic>>('listKeys', {'prefix': prefix});
    return list?.map((e) => e.toString()).toList() ?? const [];
  }

  Future<String> deviceId() async => (await _call<String>('deviceId'))!;
  Future<String> timeZoneId() async => (await _call<String>('timeZoneId'))!;

  /// Owner-only UI calls this after explicit confirmation. There is no export.
  Future<void> resetDeviceVault() async {
    await _call<void>('reset');
  }

  /// Monotonic-vs-wall-clock guard persists across application restarts.
  Future<bool> clockIsReliable() async =>
      await _call<bool>('checkClock') ?? false;
  Future<void> confirmDeviceTime() async {
    await _call<void>('confirmDeviceTime');
  }
}
