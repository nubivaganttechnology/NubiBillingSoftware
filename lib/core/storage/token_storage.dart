import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';
import '../../data/models/auth_session_model.dart';

class TokenStorageService {
  TokenStorageService({FlutterSecureStorage? storage})
    : _s =
          storage ??
          const FlutterSecureStorage(
            // Use the user's legacy macOS Keychain. Data Protection Keychain
            // requires the signed entitlement that unsigned dev builds lack.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _s;
  Future<void> save(AuthSession x) => _storageOperation(() async {
    await _s.write(key: 'refresh', value: x.refreshToken);
    await _s.write(key: 'uid', value: x.uid);
    await _s.write(key: 'email', value: x.email);
    await _s.write(key: 'idToken', value: x.idToken);
    await _s.write(
      key: 'expiresAt',
      value: x.expiresAt.toUtc().toIso8601String(),
    );
  });

  Future<void> saveContext({String? businessId, String? outletId}) =>
      _storageOperation(() async {
        if (businessId == null) {
          await _s.delete(key: 'currentBusinessId');
        } else {
          await _s.write(key: 'currentBusinessId', value: businessId);
        }
        if (outletId == null) {
          await _s.delete(key: 'currentOutletId');
        } else {
          await _s.write(key: 'currentOutletId', value: outletId);
        }
      });

  Future<({String? businessId, String? outletId})> readContext() =>
      _storageOperation(
        () async => (
          businessId: await _s.read(key: 'currentBusinessId'),
          outletId: await _s.read(key: 'currentOutletId'),
        ),
      );

  Future<void> saveLanguage(String languageCode) => _storageOperation(() async {
        await _s.write(key: 'appLanguage', value: languageCode);
      });

  Future<String?> readLanguage() => _storageOperation(() async {
        return await _s.read(key: 'appLanguage');
      });

  Future<
    ({
      String token,
      String uid,
      String email,
      String? idToken,
      DateTime? expiresAt,
    })?
  >
  read() => _storageOperation(() async {
    final t = await _s.read(key: 'refresh');
    if (t == null) return null;
    return (
      token: t,
      uid: await _s.read(key: 'uid') ?? '',
      email: await _s.read(key: 'email') ?? '',
      idToken: await _s.read(key: 'idToken'),
      expiresAt: DateTime.tryParse(await _s.read(key: 'expiresAt') ?? ''),
    );
  });

  Future<void> clear() => _storageOperation(_s.deleteAll);

  Future<T> _storageOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'Secure local storage is unavailable. Check macOS Keychain access and try again.',
        code: 'secure-storage',
      );
    }
  }
}
