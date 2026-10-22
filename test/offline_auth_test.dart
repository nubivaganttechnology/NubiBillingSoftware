import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/core/storage/token_storage.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/repositories/auth_repository.dart';
import 'package:testflutter/data/services/firebase_auth_rest_service.dart';

class OfflineAuth extends FirebaseAuthRestService {
  OfflineAuth() : super(ApiClient());
  int refreshes = 0;
  @override
  Future<AuthSession> refresh(String token, String email) async {
    refreshes++;
    throw const AppException('No internet', code: 'network');
  }
}

AuthSession rememberedSession() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final claims = {
    'aud': '',
    'iss': 'https://securetoken.google.com/',
    'sub': 'USER',
    'user_id': 'USER',
    'iat': now - 7200,
    'auth_time': now - 7200,
    'exp': now - 3600,
  };
  final token =
      'header.${base64Url.encode(utf8.encode(jsonEncode(claims)))}.signature';
  return AuthSession(
    idToken: token,
    refreshToken: 'secure-refresh',
    uid: 'USER',
    email: 'test@example.com',
    expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('remembered offline restart restores secure session without erasing expired credentials', () async {
    final storage = TokenStorageService();
    final original = rememberedSession();
    await storage.save(original);
    await storage.saveContext(businessId: 'B', outletId: 'O');
    final remote = OfflineAuth();
    final repo = AuthRepository(remote, storage)
      ..networkAvailable = () => false;
    final restored = await repo.restore();
    expect(restored!.uid, 'USER');
    expect(remote.refreshes, 0);
    expect((await repo.ensureValidSession())!.refreshToken, 'secure-refresh');
    expect((await repo.readContext()).outletId, 'O');
    expect((await storage.read())!.idToken, original.idToken);
  });
  test('refresh network failure retains credentials and backs off repeated local reads', () async {
    final storage = TokenStorageService();
    await storage.save(rememberedSession());
    final remote = OfflineAuth();
    final repo = AuthRepository(remote, storage);
    expect((await repo.restore())!.uid, 'USER');
    expect((await repo.ensureValidSession())!.uid, 'USER');
    final attempts = remote.refreshes;
    expect((await repo.ensureValidSession())!.uid, 'USER');
    expect(remote.refreshes, attempts);
    expect((await storage.read())!.token, 'secure-refresh');
  });
  test(
    'legacy refresh-only secure storage can still restore after online refresh',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'refresh': 'legacy',
        'uid': 'USER',
        'email': 'test@example.com',
      });
      final read = await TokenStorageService().read();
      expect(read!.token, 'legacy');
      expect(read.idToken, isNull);
    },
  );
}
