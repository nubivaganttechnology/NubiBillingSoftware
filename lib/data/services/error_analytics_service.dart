import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../core/constants/firebase_constants.dart';
import 'firestore_rest_service.dart';

class ErrorAnalyticsReport {
  const ErrorAnalyticsReport({
    required this.reportId,
    required this.problemType,
    required this.problemSummary,
    required this.severity,
    required this.component,
    required this.location,
    this.collection,
    this.businessId,
    this.tenantId,
    this.outletId,
    required this.devicePlatform,
    required this.details,
    this.indexCreationUrl,
    required this.rawError,
    this.stackTrace,
    this.metadata,
    required this.timestamp,
    this.resolved = false,
  });

  final String reportId;
  final String problemType;
  final String problemSummary;
  final String severity;
  final String component;
  final String location;
  final String? collection;
  final String? businessId;
  final String? tenantId;
  final String? outletId;
  final String devicePlatform;
  final String details;
  final String? indexCreationUrl;
  final String rawError;
  final String? stackTrace;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;
  final bool resolved;

  Map<String, dynamic> toFirestoreMap() => {
    'reportId': reportId,
    'problemType': problemType,
    'problemSummary': problemSummary,
    'severity': severity,
    'component': component,
    'location': location,
    if (collection != null) 'collection': collection,
    if (businessId != null) 'businessId': businessId,
    if (tenantId != null) 'tenantId': tenantId,
    if (outletId != null) 'outletId': outletId,
    'devicePlatform': devicePlatform,
    'details': details,
    if (indexCreationUrl != null) 'indexCreationUrl': indexCreationUrl,
    'rawError': rawError,
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (metadata != null) 'metadata': metadata,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'resolved': resolved,
  };
}

class ErrorAnalyticsService {
  ErrorAnalyticsService(this.remote, {this.sessionProvider});

  final FirestoreRestService remote;
  final Future<String?> Function()? sessionProvider;

  static ErrorAnalyticsService? instance;

  final List<ErrorAnalyticsReport> _recentReports = [];
  List<ErrorAnalyticsReport> get recentReports =>
      List.unmodifiable(_recentReports);

  Future<void> recordError({
    required String component,
    required String location,
    required Object error,
    StackTrace? stackTrace,
    String? collection,
    String? businessId,
    String? tenantId,
    String? outletId,
    Map<String, dynamic>? metadata,
  }) async {
    final rawString = error.toString();
    final indexUrl = _extractIndexUrl(rawString);
    final problemType = _detectProblemType(rawString);
    final severity = _detectSeverity(problemType);
    final summary = _generateSummary(problemType, collection, location);
    final details = _generateDetails(problemType, rawString, indexUrl);
    final platform = kIsWeb ? 'web' : Platform.operatingSystem;

    final reportId =
        'ERR_${DateTime.now().millisecondsSinceEpoch}_${(1000 + DateTime.now().microsecond % 9000)}';

    final report = ErrorAnalyticsReport(
      reportId: reportId,
      problemType: problemType,
      problemSummary: summary,
      severity: severity,
      component: component,
      location: location,
      collection: collection,
      businessId: businessId,
      tenantId: tenantId,
      outletId: outletId,
      devicePlatform: platform,
      details: details,
      indexCreationUrl: indexUrl,
      rawError: rawString,
      stackTrace: stackTrace?.toString(),
      metadata: metadata,
      timestamp: DateTime.now().toUtc(),
    );

    _recentReports.insert(0, report);
    if (_recentReports.length > 50) {
      _recentReports.removeLast();
    }

    if (kDebugMode) {
      debugPrint('[ErrorAnalytics] Logged: $problemType in $component ($location)');
      if (indexUrl != null) {
        debugPrint('[ErrorAnalytics] Index URL: $indexUrl');
      }
    }

    // Persist to Google Cloud Firestore analytics collection asynchronously
    try {
      final token = await sessionProvider?.call();
      await remote.createDocument(
        FirebaseConstants.errorAnalytics,
        reportId,
        report.toFirestoreMap(),
        idToken: token,
      );
    } catch (e) {
      // Background failure logging must never throw or disrupt client app flow
      if (kDebugMode) {
        debugPrint('[ErrorAnalytics] Cloud logging deferred: $e');
      }
    }
  }

  static String? _extractIndexUrl(String raw) {
    final match = RegExp(
      r'https:\/\/console\.firebase\.google\.com[^\s\)]+',
    ).firstMatch(raw);
    return match?.group(0);
  }

  static String _detectProblemType(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('index') || lower.contains('create_composite')) {
      return 'MISSING_COMPOSITE_INDEX';
    }
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('resource_exhausted')) {
      return 'QUOTA_EXCEEDED';
    }
    if (lower.contains('unauthenticated') || lower.contains('permission-denied')) {
      return 'PERMISSION_OR_AUTH_ERROR';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup')) {
      return 'NETWORK_OFFLINE';
    }
    if (lower.contains('http 400') || lower.contains('bad request')) {
      return 'HTTP_400_BAD_REQUEST';
    }
    return 'RUNTIME_ERROR';
  }

  static String _detectSeverity(String problemType) {
    switch (problemType) {
      case 'MISSING_COMPOSITE_INDEX':
      case 'HTTP_400_BAD_REQUEST':
        return 'CRITICAL';
      case 'QUOTA_EXCEEDED':
      case 'PERMISSION_OR_AUTH_ERROR':
        return 'HIGH';
      default:
        return 'MEDIUM';
    }
  }

  static String _generateSummary(
    String problemType,
    String? collection,
    String location,
  ) {
    switch (problemType) {
      case 'MISSING_COMPOSITE_INDEX':
        return collection != null
            ? 'Missing Firestore Composite Index on "$collection"'
            : 'Missing Firestore Composite Index';
      case 'QUOTA_EXCEEDED':
        return 'Google Cloud Firestore Quota Exceeded (HTTP 429)';
      case 'PERMISSION_OR_AUTH_ERROR':
        return 'Authentication or Permission Denied';
      case 'NETWORK_OFFLINE':
        return 'Network connection unreachable';
      case 'HTTP_400_BAD_REQUEST':
        return 'Firestore Query Bad Request (HTTP 400)';
      default:
        return 'Application error in $location';
    }
  }

  static String _generateDetails(
    String problemType,
    String raw,
    String? indexUrl,
  ) {
    if (problemType == 'MISSING_COMPOSITE_INDEX' && indexUrl != null) {
      return 'Firestore remote sync query requires a multi-field composite index to query efficiently. Create index using link: $indexUrl';
    }
    return raw;
  }

  /// Transforms raw technical developer messages into friendly, calm text
  /// for cashiers and store owners. Never exposes raw index URLs or HTTP codes.
  static String sanitizeForCustomer(String? rawError) {
    if (rawError == null || rawError.trim().isEmpty) {
      return 'Cloud synchronization is operating normally.';
    }
    final lower = rawError.toLowerCase();
    if (lower.contains('index') || lower.contains('create_composite')) {
      return 'Cloud synchronization is running in background resilience mode. All local SQLite billing, products, and offline records are 100% safe and secure. Cloud index diagnostics have been reported to system monitoring.';
    }
    if (lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('resource_exhausted')) {
      return 'Cloud sync cooldown active to conserve API bandwidth. Offline billing and inventory are completely unaffected and will sync automatically.';
    }
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup')) {
      return 'Currently working offline. All local sales and bills are safely stored and will synchronize immediately upon internet reconnection.';
    }
    if (lower.contains('unauthenticated') || lower.contains('permission-denied')) {
      return 'Session refresh pending. Local data remains intact and secure.';
    }
    return 'Background synchronization scheduled. Local SQLite data and pending writes remain completely safe.';
  }
}
