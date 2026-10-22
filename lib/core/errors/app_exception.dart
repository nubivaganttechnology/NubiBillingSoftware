class AppException implements Exception {
  const AppException(this.message, {this.code, this.details});
  final String message;
  final String? code;
  final Map<String, dynamic>? details;
  @override
  String toString() => message;
}
