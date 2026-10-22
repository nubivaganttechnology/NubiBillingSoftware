import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import 'face_biometric_vault.dart';

class GpsLocation {
  const GpsLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    required this.isMock,
    this.provider = 'unknown',
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final bool isMock;
  final String provider;

  int ageSeconds([DateTime? now]) {
    final current = (now ?? DateTime.now()).toUtc();
    return current.difference(timestamp.toUtc()).inSeconds.abs();
  }

  Map<String, dynamic> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'timestamp': timestamp.toIso8601String(),
    'isMock': isMock,
    'provider': provider,
  };

  factory GpsLocation.fromMap(Map<dynamic, dynamic> map) {
    final timeRaw = map['time'];
    DateTime time;
    if (timeRaw is int) {
      time = DateTime.fromMillisecondsSinceEpoch(timeRaw, isUtc: true);
    } else if (timeRaw is String) {
      time = DateTime.parse(timeRaw).toUtc();
    } else {
      time = DateTime.now().toUtc();
    }

    return GpsLocation(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      accuracy: (map['accuracy'] as num).toDouble(),
      timestamp: time,
      isMock: map['isMock'] == true,
      provider: map['provider']?.toString() ?? 'unknown',
    );
  }
}

class OutletGeofence {
  const OutletGeofence({
    required this.outletId,
    required this.businessId,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100.0,
    required this.updatedAt,
    this.configuredBy = 'SYSTEM',
  });

  final String outletId;
  final String businessId;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime updatedAt;
  final String configuredBy;

  Map<String, dynamic> toJson() => {
    'outletId': outletId,
    'businessId': businessId,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'updatedAt': updatedAt.toIso8601String(),
    'configuredBy': configuredBy,
  };

  factory OutletGeofence.fromJson(Map<String, dynamic> json) => OutletGeofence(
    outletId: json['outletId'] as String,
    businessId: json['businessId'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 100.0,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    configuredBy: json['configuredBy'] as String? ?? 'SYSTEM',
  );
}

class GeofenceEvaluation {
  const GeofenceEvaluation({
    required this.location,
    this.outletGeofence,
    this.distanceMeters,
    required this.radiusMeters,
    required this.isWithinRadius,
    required this.isAccurate,
    required this.isFresh,
    required this.isMock,
    required this.isVerified,
    required this.requiresManagerReview,
    required this.fraudFlags,
    required this.statusMessage,
  });

  final GpsLocation location;
  final OutletGeofence? outletGeofence;
  final double? distanceMeters;
  final double radiusMeters;
  final bool isWithinRadius;
  final bool isAccurate;
  final bool isFresh;
  final bool isMock;
  final bool isVerified;
  final bool requiresManagerReview;
  final List<String> fraudFlags;
  final String statusMessage;
}

class GeofenceService {
  GeofenceService({
    this.vaultStore,
    this.channel = const MethodChannel('nubibill/location'),
    this.clock = DateTime.now,
  });

  final FaceVaultValueStore? vaultStore;
  final MethodChannel channel;
  final DateTime Function() clock;

  static const double defaultRadiusMeters = 100.0;
  static const double maxAcceptableAccuracyMeters = 50.0;
  static const int maxAcceptableAgeSeconds = 120; // 2 minutes

  /// Haversine formula calculation for WGS84 coordinates.
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<bool> checkPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>('checkPermission');
      return res?['hasFineLocation'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>('requestPermission');
      return res?['hasFineLocation'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<GpsLocation> getCurrentLocation({bool forceFresh = true}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      // Stub for non-Android environments/tests
      return GpsLocation(
        latitude: 22.5726,
        longitude: 88.3639,
        accuracy: 10.0,
        timestamp: clock().toUtc(),
        isMock: false,
        provider: 'host-simulation',
      );
    }
    try {
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getCurrentLocation',
        {'forceFresh': forceFresh},
      );
      if (res == null) {
        throw const AppException('Location signal unavailable. Turn on GPS and retry.');
      }
      return GpsLocation.fromMap(res);
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw const AppException('Location permission is required for attendance geofencing.');
      }
      if (e.code == 'LOCATION_DISABLED') {
        throw const AppException('Device location services are off. Enable GPS in Android Settings.');
      }
      throw AppException(e.message ?? 'GPS location acquisition failed.');
    }
  }

  Future<void> saveOutletGeofence({
    required String outletId,
    required String businessId,
    required double latitude,
    required double longitude,
    double radiusMeters = defaultRadiusMeters,
    required String configuredBy,
  }) async {
    final geofence = OutletGeofence(
      outletId: outletId,
      businessId: businessId,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      updatedAt: clock().toUtc(),
      configuredBy: configuredBy,
    );
    final key = 'outlet.geofence.$outletId';
    if (vaultStore != null) {
      await vaultStore!.write(key, jsonEncode(geofence.toJson()));
    }
  }

  Future<OutletGeofence?> getOutletGeofence(String outletId) async {
    if (vaultStore == null) return null;
    final key = 'outlet.geofence.$outletId';
    final raw = await vaultStore!.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return OutletGeofence.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Evaluates GPS location against an outlet geofence with comprehensive anti-fraud checks.
  GeofenceEvaluation evaluate({
    required GpsLocation location,
    OutletGeofence? geofence,
    double? outletLat,
    double? outletLon,
    double? outletRadiusMeters,
  }) {
    final targetLat = geofence?.latitude ?? outletLat;
    final targetLon = geofence?.longitude ?? outletLon;
    final radius = geofence?.radiusMeters ?? outletRadiusMeters ?? defaultRadiusMeters;

    final fraudFlags = <String>[];
    double? distance;

    // 1. Check Mock Location signal
    if (location.isMock) {
      fraudFlags.add('MOCK_LOCATION_DETECTED');
    }

    // 2. Check GPS Freshness
    final age = location.ageSeconds(clock());
    final isFresh = age <= maxAcceptableAgeSeconds;
    if (!isFresh) {
      fraudFlags.add('STALE_GPS_LOCATION (${age}s old > ${maxAcceptableAgeSeconds}s limit)');
    }

    // 3. Check GPS Accuracy
    final isAccurate = location.accuracy <= maxAcceptableAccuracyMeters;
    if (!isAccurate) {
      fraudFlags.add('LOW_GPS_ACCURACY (±${location.accuracy.toStringAsFixed(1)}m > ${maxAcceptableAccuracyMeters.toInt()}m threshold)');
    }

    // 4. Geofence Distance Check
    bool isWithinRadius = false;
    if (targetLat != null && targetLon != null) {
      distance = haversineDistanceMeters(
        location.latitude,
        location.longitude,
        targetLat,
        targetLon,
      );
      isWithinRadius = distance <= radius;
      if (!isWithinRadius) {
        fraudFlags.add('OUTSIDE_GEOFENCE (${distance.toStringAsFixed(1)}m > ${radius.toInt()}m radius)');
      }
    } else {
      // Outlet location not yet configured
      fraudFlags.add('OUTLET_GEOFENCE_NOT_CONFIGURED');
    }

    final isVerified = fraudFlags.isEmpty;
    final requiresManagerReview = !isVerified;

    String statusMessage;
    if (isVerified) {
      statusMessage = 'Within Geofence (${distance?.toStringAsFixed(1)}m / ${radius.toInt()}m) · GPS Accuracy ±${location.accuracy.toStringAsFixed(1)}m';
    } else if (fraudFlags.contains('MOCK_LOCATION_DETECTED')) {
      statusMessage = 'Fake/Mock Location detected. Requires manager review.';
    } else if (!isWithinRadius && distance != null) {
      statusMessage = 'Outside outlet boundary (${distance.toStringAsFixed(1)}m > ${radius.toInt()}m). Requires manager review.';
    } else if (!isAccurate) {
      statusMessage = 'Low GPS accuracy (±${location.accuracy.toStringAsFixed(1)}m). Move to an open area or submit for review.';
    } else if (!isFresh) {
      statusMessage = 'Stale location cache (${age}s old). Acquire fresh GPS or submit for review.';
    } else {
      statusMessage = 'Geofence unverified: ${fraudFlags.join(', ')}';
    }

    return GeofenceEvaluation(
      location: location,
      outletGeofence: geofence,
      distanceMeters: distance,
      radiusMeters: radius,
      isWithinRadius: isWithinRadius,
      isAccurate: isAccurate,
      isFresh: isFresh,
      isMock: location.isMock,
      isVerified: isVerified,
      requiresManagerReview: requiresManagerReview,
      fraudFlags: fraudFlags,
      statusMessage: statusMessage,
    );
  }
}
