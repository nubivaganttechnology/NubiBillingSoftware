import 'dart:convert';

class AuthSession {
  const AuthSession({
    required this.idToken,
    required this.refreshToken,
    required this.uid,
    required this.email,
    required this.expiresAt,
  });
  final String idToken, refreshToken, uid, email;
  final DateTime expiresAt;
  bool get isExpired {
    final exp = tokenClaims?['exp'];
    final tokenExpiry = exp is int
        ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
        : expiresAt;
    return DateTime.now().isAfter(
      tokenExpiry.subtract(const Duration(minutes: 1)),
    );
  }

  String? get tokenProjectId {
    return tokenClaims?['aud'] as String?;
  }

  Map<String, dynamic>? get tokenClaims {
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic> ? payload : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  factory AuthSession.signIn(Map<String, dynamic> j) => AuthSession(
    idToken: j['idToken'] as String,
    refreshToken: j['refreshToken'] as String,
    uid: j['localId'] as String,
    email: j['email'] as String,
    expiresAt: DateTime.now().add(
      Duration(seconds: int.tryParse('${j['expiresIn']}') ?? 3600),
    ),
  );
  factory AuthSession.refreshed(
    Map<String, dynamic> j,
    String previous,
    String email,
  ) => AuthSession(
    idToken: j['id_token'] as String,
    refreshToken: (j['refresh_token'] as String?) ?? previous,
    uid: j['user_id'] as String,
    email: email,
    expiresAt: DateTime.now().add(
      Duration(seconds: int.tryParse('${j['expires_in']}') ?? 3600),
    ),
  );
}
