class EnvironmentConfig {
  EnvironmentConfig._();
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0+1',
  );
  static bool get isConfigured => projectId.isNotEmpty && apiKey.isNotEmpty;

  static Map<String, Object> diagnostics() => {
    'requiredDefines': const [
      'FIREBASE_PROJECT_ID',
      'FIREBASE_API_KEY',
      'APP_VERSION',
    ],
    // Firebase project IDs are identifiers, not credentials. Reporting the
    // configured value lets support compare machine builds without exposing
    // the API key or tokens.
    'firebaseProjectId': projectId.isEmpty ? '(unset)' : projectId,
    'firebaseProjectConfigured': projectId.isNotEmpty,
    'firebaseApiKeyConfigured': apiKey.isNotEmpty,
    'appVersion': appVersion,
  };

  static String redactDiagnosticText(String value) => value
      .replaceAll(
        RegExp(
          r'(api[_-]?key|key|authorization|token|password|secret)(\s*[:=]\s*)[^\s,;]+',
          caseSensitive: false,
        ),
        r'$1$2[redacted]',
      )
      .replaceAll(
        RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
        'Bearer [redacted]',
      )
      .replaceAll(RegExp(r'\b[^\s@]+@[^\s@]+\.[^\s@]+\b'), '[redacted-email]')
      .replaceAll(RegExp(r'\b[A-Za-z0-9_-]{32,}\b'), '[redacted-id]');
}
