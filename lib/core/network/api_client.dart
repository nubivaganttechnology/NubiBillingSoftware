import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const timeout = Duration(seconds: 15);
  static const _debugMode =
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.vm.profile');
  Future<Map<String, dynamic>> get(Uri uri, {String? token}) async {
    final watch = Stopwatch()..start();
    var count = 0;
    try {
      final result = _decode(
        await _client
            .get(
              uri,
              headers: {
                'Accept': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
              },
            )
            .timeout(timeout),
      );
      count = 1;
      return result;
    } on TimeoutException {
      throw const AppException(
        'The request timed out. Please try again.',
        code: 'network',
      );
    } on http.ClientException {
      throw const AppException(
        'Unable to connect to the server. Check your internet connection.',
        code: 'network',
      );
    } finally {
      _logRead(uri, null, watch.elapsedMilliseconds, count);
    }
  }

  Future<Map<String, dynamic>> post(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    try {
      final requestHeaders = {'Accept': 'application/json', ...?headers};
      final response = await _client
          .post(uri, headers: requestHeaders, body: body)
          .timeout(timeout);
      return _decode(response);
    } on TimeoutException {
      throw const AppException(
        'The request timed out. Please try again.',
        code: 'network',
      );
    } on http.ClientException {
      throw const AppException(
        'Unable to connect to the server. Check your internet connection.',
        code: 'network',
      );
    }
  }

  Future<List<Map<String, dynamic>>> postList(
    Uri uri, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final watch = Stopwatch()..start();
    int? count;
    try {
      final requestHeaders = {'Accept': 'application/json', ...?headers};
      final response = await _client
          .post(uri, headers: requestHeaders, body: body)
          .timeout(timeout);
      dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? <dynamic>[]
            : jsonDecode(response.body);
      } on FormatException {
        throw const AppException('The server returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppException(
          _errorMessage(decoded, response.body),
          code: '${response.statusCode}',
        );
      }
      if (decoded is! List) {
        throw const AppException('The server returned an invalid response.');
      }
      count = decoded
          .whereType<Map>()
          .where((r) => r['document'] != null)
          .length;
      return decoded.whereType<Map<String, dynamic>>().toList(growable: false);
    } on TimeoutException {
      throw const AppException(
        'The request timed out. Please try again.',
        code: 'network',
      );
    } on http.ClientException {
      throw const AppException(
        'Unable to connect to the server. Check your internet connection.',
        code: 'network',
      );
    } finally {
      _logRead(uri, body, watch.elapsedMilliseconds, count);
    }
  }

  Future<Map<String, dynamic>> patch(
    Uri uri, {
    Object? body,
    String? token,
    Map<String, String>? headers,
  }) async {
    try {
      return _decode(
        await _client
            .patch(
              uri,
              headers: {
                'Accept': 'application/json',
                if (token != null) 'Authorization': 'Bearer $token',
                ...?headers,
              },
              body: body,
            )
            .timeout(timeout),
      );
    } on TimeoutException {
      throw const AppException(
        'The request timed out. Please try again.',
        code: 'network',
      );
    } on http.ClientException {
      throw const AppException(
        'Unable to connect to the server. Check your internet connection.',
        code: 'network',
      );
    }
  }

  Future<void> delete(Uri uri, {String? token}) async {
    try {
      final response = await _client
          .delete(
            uri,
            headers: {
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _decode(response);
      }
    } on TimeoutException {
      throw const AppException(
        'The request timed out. Please try again.',
        code: 'network',
      );
    } on http.ClientException {
      throw const AppException(
        'Unable to connect to the server. Check your internet connection.',
        code: 'network',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> d = {};
    if (r.body.isNotEmpty) {
      try {
        d = jsonDecode(r.body) as Map<String, dynamic>;
      } on FormatException {
        throw const AppException('The server returned an invalid response.');
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return d;
    throw AppException(_errorMessage(d, r.body), code: '${r.statusCode}');
  }

  void _logRead(Uri uri, Object? body, int milliseconds, int? count) {
    if (!_debugMode || uri.host != 'firestore.googleapis.com') return;
    String collection =
        uri.path
            .split('/documents')
            .last
            .split('/')
            .where((p) => p.isNotEmpty)
            .firstOrNull ??
        'unknown';
    final scope = <String, Object?>{};
    if (body is String) {
      try {
        final data = jsonDecode(body) as Map;
        final query =
            data['structuredQuery'] ??
            (data['structuredAggregationQuery'] as Map?)?['structuredQuery'];
        if (query is Map) {
          collection =
              ((query['from'] as List).first as Map)['collectionId'] as String;
          void visit(Object? node) {
            if (node is! Map) return;
            final f = node['fieldFilter'];
            if (f is Map &&
                const [
                  'tenantId',
                  'businessId',
                  'outletId',
                  'scopeType',
                ].contains((f['field'] as Map)['fieldPath'])) {
              scope[(f['field'] as Map)['fieldPath'] as String] = f['value'];
            }
            final children = (node['compositeFilter'] as Map?)?['filters'];
            if (children is List) {
              for (final child in children) {
                visit(child);
              }
            }
          }

          visit(query['where']);
        }
      } catch (_) {
        /* Instrumentation never changes request behavior. */
      }
    }
    developer.log(
      'Firestore READ collection=$collection context=${Zone.current[#firestoreReadContext] ?? 'EXPLICIT_READ query=$collection#${body?.hashCode ?? 0} cursor=none'} scope=$scope documents=$count durationMs=$milliseconds',
      name: 'nubibill.api',
    );
  }

  String _errorMessage(dynamic decoded, String body) {
    final message = _messageFromError(decoded);
    if (message.isNotEmpty) return message;

    final responseBody = body.trim();
    if (responseBody.isEmpty) {
      return 'The server returned no error details.';
    }
    const maxLength = 800;
    return responseBody.length <= maxLength
        ? responseBody
        : '${responseBody.substring(0, maxLength)}…';
  }

  String _messageFromError(dynamic decoded) {
    if (decoded is List) {
      for (final item in decoded) {
        final message = _messageFromError(item);
        if (message.isNotEmpty) return message;
      }
      return '';
    }
    if (decoded is! Map) return '';

    final error = decoded['error'];
    if (error is Map) {
      final message = '${error['message'] ?? ''}'.trim();
      if (message.isNotEmpty) return message;
    }
    return '';
  }
}
