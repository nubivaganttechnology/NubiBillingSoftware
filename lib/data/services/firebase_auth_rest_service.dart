import 'dart:convert';

import '../../core/config/environment_config.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../models/auth_session_model.dart';

class FirebaseAuthRestService {
  FirebaseAuthRestService(this.api);
  final ApiClient api;
  Uri _uri(String m) =>
      Uri.parse('${FirebaseConstants.auth}/$m?key=${EnvironmentConfig.apiKey}');
  Future<AuthSession> signIn(String e, String p) async {
    if (!EnvironmentConfig.isConfigured) {
      throw const AppException('Firebase is not configured.');
    }
    try {
      return AuthSession.signIn(
        await api.post(
          _uri('accounts:signInWithPassword'),
          body: jsonEncode({
            'email': e,
            'password': p,
            'returnSecureToken': true,
          }),
          headers: {'Content-Type': 'application/json'},
        ),
      );
    } on AppException catch (x) {
      throw _map(x);
    }
  }

  Future<AuthSession> createEmailPasswordAccount(
    String email,
    String password,
  ) async {
    if (!EnvironmentConfig.isConfigured) {
      throw const AppException('Firebase is not configured.');
    }
    try {
      final data = await api.post(
        _uri('accounts:signUp'),
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'password': password,
          'returnSecureToken': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      return AuthSession.signIn(data);
    } on AppException catch (error) {
      if (error.message.toUpperCase().contains('EMAIL_EXISTS')) {
        throw const AppException('An account already exists for this email.');
      }
      if (error.message.toUpperCase().contains('WEAK_PASSWORD')) {
        throw const AppException('Use a password with at least 6 characters.');
      }
      rethrow;
    }
  }

  Future<AuthSession> refresh(String token, String email) async {
    try {
      return AuthSession.refreshed(
        await api.post(
          Uri.parse(
            '${FirebaseConstants.token}?key=${EnvironmentConfig.apiKey}',
          ),
          body: {'grant_type': 'refresh_token', 'refresh_token': token},
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
        token,
        email,
      );
    } on AppException catch (x) {
      throw _map(x);
    }
  }

  AppException _map(AppException x) {
    if (x.code == 'network') return x;
    switch (x.message.toUpperCase()) {
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_PASSWORD':
        return const AppException('Email or password is incorrect.');
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return const AppException(
          'Too many login attempts. Please wait and try again later.',
        );
      case 'USER_DISABLED':
        return const AppException(
          'This account is currently disabled. Please contact the administrator.',
        );
      case 'OPERATION_NOT_ALLOWED':
        return const AppException(
          'Email and password sign-in is not enabled for this Firebase project.',
        );
      case 'API_KEY_INVALID':
      case 'API_KEY_EXPIRED':
        return const AppException(
          'Firebase sign-in is misconfigured. Check the Firebase API key.',
        );
      case 'PROJECT_NOT_FOUND':
        return const AppException(
          'Firebase sign-in is misconfigured. Check the Firebase project ID.',
        );
      case 'INVALID_EMAIL':
        return const AppException('Enter a valid email address.');
      default:
        if (x.code == null) return x;
        // Firebase returns stable identifier strings here (for example,
        // CONFIGURATION_NOT_FOUND). Surface only those identifiers so setup
        // failures can be diagnosed without exposing response payloads.
        final identifier = x.message.toUpperCase();
        if (RegExp(r'^[A-Z0-9_]+$').hasMatch(identifier)) {
          return AppException(
            'Firebase sign-in failed ($identifier). Check Firebase Authentication settings.',
            code: identifier,
          );
        }
        return AppException(
          'Something went wrong. Please try again.',
          code: x.message,
        );
    }
  }
}
