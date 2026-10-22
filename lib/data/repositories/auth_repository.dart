import '../../core/config/environment_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/storage/token_storage.dart';
import '../models/auth_session_model.dart';
import '../services/firebase_auth_rest_service.dart';

class AuthRepository {
  AuthRepository(this.auth, this.storage);
  final FirebaseAuthRestService auth;
  final TokenStorageService storage;
  bool Function()? networkAvailable;
  DateTime? _refreshRetryAt;
  AuthSession? session;
  AuthSession? get currentSession => session;

  Future<({String? businessId, String? outletId})> readContext() =>
      storage.readContext();

  Future<void> saveContext({String? businessId, String? outletId}) =>
      storage.saveContext(businessId: businessId, outletId: outletId);

  Future<String?> readLanguage() => storage.readLanguage();

  Future<void> saveLanguage(String languageCode) =>
      storage.saveLanguage(languageCode);
  Future<AuthSession> signIn(
    String e,
    String p, {
    required bool remember,
  }) async {
    final s = await auth.signIn(e, p);
    _verifyProject(s);
    try {
      if (remember) {
        await storage.save(s);
      } else {
        await storage.clear();
      }
    } catch (_) {
      session = null;
      rethrow;
    }
    session = s;
    return s;
  }

  Future<AuthSession> createEmployeeIdentity(String email, String password) =>
      auth.createEmailPasswordAccount(email, password);

  Future<AuthSession?> restore() async {
    final s = await storage.read();
    if (s == null) return null;
    final cached = s.idToken == null || s.expiresAt == null
        ? null
        : AuthSession(
            idToken: s.idToken!,
            refreshToken: s.token,
            uid: s.uid,
            email: s.email,
            expiresAt: s.expiresAt!,
          );
    if (cached != null) {
      _verifyProject(cached);
      _verifyClaims(cached, allowExpired: true);
      if (!cached.isExpired || networkAvailable?.call() == false) {
        session = cached;
        return cached;
      }
    }
    AuthSession refreshed;
    try {
      refreshed = await auth.refresh(s.token, s.email);
      if (refreshed.uid != s.uid) {
        throw const AppException('Stored login belongs to a different user.');
      }
      _verifyProject(refreshed);
      _verifyClaims(refreshed);
    } on AppException catch (error) {
      if (error.code == 'network' && cached != null) {
        session = cached;
        return cached;
      }
      await storage.clear();
      session = null;
      return null;
    }
    await storage.save(refreshed);
    session = refreshed;
    return refreshed;
  }

  Future<AuthSession?> ensureValidSession() async {
    final active = session;
    if (active == null) return null;
    _verifyProject(active);
    _verifyClaims(active, allowExpired: true);
    if (!active.isExpired || networkAvailable?.call() == false) return active;
    if (_refreshRetryAt?.isAfter(DateTime.now()) == true) return active;
    try {
      final refreshed = await auth.refresh(active.refreshToken, active.email);
      if (refreshed.uid != active.uid) {
        throw const AppException(
          'The refreshed session belongs to another user. Please sign in again.',
        );
      }
      _verifyProject(refreshed);
      _verifyClaims(refreshed);
      final stored = await storage.read();
      if (stored?.uid == active.uid) {
        await storage.save(refreshed);
      }
      _refreshRetryAt = null;
      session = refreshed;
      return refreshed;
    } on AppException catch (error) {
      if (error.code == 'network') {
        _refreshRetryAt = DateTime.now().add(const Duration(seconds: 30));
        return active;
      }
      if (error.code == 'secure-storage') rethrow;
      session = null;
      await storage.clear();
      throw const AppException(
        'Your session expired. Please sign in again.',
        code: 'unauthenticated',
      );
    }
  }

  void _verifyProject(AuthSession value) {
    final tokenProjectId = value.tokenProjectId;
    if (tokenProjectId == null) {
      throw const AppException(
        'Firebase returned an invalid ID token. Please sign in again.',
        code: 'invalid-id-token',
      );
    }
    if (EnvironmentConfig.projectId.isNotEmpty &&
        tokenProjectId != EnvironmentConfig.projectId) {
      throw const AppException(
        'Firebase Authentication and Firestore are configured for different projects.',
        code: 'project-mismatch',
      );
    }
  }

  void _verifyClaims(AuthSession value, {bool allowExpired = false}) {
    final claims = value.tokenClaims;
    final projectId = EnvironmentConfig.projectId;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final exp = claims?['exp'];
    final iat = claims?['iat'];
    final authTime = claims?['auth_time'];
    final issuer = claims?['iss'];
    if (claims == null ||
        claims['aud'] != projectId ||
        issuer != 'https://securetoken.google.com/$projectId' ||
        claims['sub'] != value.uid ||
        (claims['user_id'] != null && claims['user_id'] != value.uid) ||
        exp is! int ||
        iat is! int ||
        authTime is! int ||
        (!allowExpired && exp <= now) ||
        iat > now + 300 ||
        authTime > now + 300) {
      throw const AppException(
        'Firebase returned an invalid or expired ID token. Please sign in again.',
        code: 'invalid-id-token',
      );
    }
  }

  Future<void> logout() async {
    session = null;
    await storage.clear();
  }
}
