import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/geofence_service.dart';

void main() {
  group('GeofenceService - Distance & Haversine', () {
    test('same point returns zero distance', () {
      final dist = GeofenceService.haversineDistanceMeters(22.5726, 88.3639, 22.5726, 88.3639);
      expect(dist, closeTo(0.0, 0.001));
    });

    test('calculates accurate distance between known points', () {
      // Kolkata New Market to Victoria Memorial: approx 1.7km to 2.1km
      final dist = GeofenceService.haversineDistanceMeters(22.5601, 88.3512, 22.5448, 88.3426);
      expect(dist, greaterThan(1500));
      expect(dist, lessThan(2500));
    });
  });

  group('GeofenceService - Anti-Fraud Evaluation', () {
    final now = DateTime.utc(2026, 10, 22, 10, 0, 0);
    final outlet = OutletGeofence(
      outletId: 'OUT-001',
      businessId: 'BUS-001',
      latitude: 22.572646,
      longitude: 88.363895,
      radiusMeters: 100.0,
      updatedAt: now,
      configuredBy: 'OWNER',
    );

    test('valid fresh accurate location within geofence passes verification', () {
      final service = GeofenceService(clock: () => now);
      final loc = GpsLocation(
        latitude: 22.572650, // ~1-2 meters away
        longitude: 88.363900,
        accuracy: 8.0,
        timestamp: now.subtract(const Duration(seconds: 10)),
        isMock: false,
        provider: 'gps',
      );

      final eval = service.evaluate(location: loc, geofence: outlet);

      expect(eval.isWithinRadius, isTrue);
      expect(eval.isAccurate, isTrue);
      expect(eval.isFresh, isTrue);
      expect(eval.isMock, isFalse);
      expect(eval.isVerified, isTrue);
      expect(eval.requiresManagerReview, isFalse);
      expect(eval.fraudFlags, isEmpty);
      expect(eval.distanceMeters, lessThan(10.0));
    });

    test('location outside geofence is flagged with OUTSIDE_GEOFENCE and requires manager review', () {
      final service = GeofenceService(clock: () => now);
      // Coordinate approximately 500m away
      final loc = GpsLocation(
        latitude: 22.577000,
        longitude: 88.363895,
        accuracy: 10.0,
        timestamp: now.subtract(const Duration(seconds: 15)),
        isMock: false,
        provider: 'gps',
      );

      final eval = service.evaluate(location: loc, geofence: outlet);

      expect(eval.isWithinRadius, isFalse);
      expect(eval.isVerified, isFalse);
      expect(eval.requiresManagerReview, isTrue);
      expect(eval.fraudFlags, anyElement(contains('OUTSIDE_GEOFENCE')));
    });

    test('mock location is detected and flagged with MOCK_LOCATION_DETECTED', () {
      final service = GeofenceService(clock: () => now);
      final loc = GpsLocation(
        latitude: 22.572646,
        longitude: 88.363895,
        accuracy: 5.0,
        timestamp: now.subtract(const Duration(seconds: 5)),
        isMock: true,
        provider: 'mock-provider',
      );

      final eval = service.evaluate(location: loc, geofence: outlet);

      expect(eval.isMock, isTrue);
      expect(eval.isVerified, isFalse);
      expect(eval.requiresManagerReview, isTrue);
      expect(eval.fraudFlags, contains('MOCK_LOCATION_DETECTED'));
    });

    test('stale location older than maxAgeSeconds is flagged with STALE_GPS_LOCATION', () {
      final service = GeofenceService(clock: () => now);
      final loc = GpsLocation(
        latitude: 22.572646,
        longitude: 88.363895,
        accuracy: 10.0,
        timestamp: now.subtract(const Duration(minutes: 5)), // 300s old > 120s
        isMock: false,
        provider: 'gps',
      );

      final eval = service.evaluate(location: loc, geofence: outlet);

      expect(eval.isFresh, isFalse);
      expect(eval.isVerified, isFalse);
      expect(eval.requiresManagerReview, isTrue);
      expect(eval.fraudFlags, anyElement(contains('STALE_GPS_LOCATION')));
    });

    test('low accuracy above threshold is flagged with LOW_GPS_ACCURACY', () {
      final service = GeofenceService(clock: () => now);
      final loc = GpsLocation(
        latitude: 22.572646,
        longitude: 88.363895,
        accuracy: 85.0, // 85m > 50m max allowed
        timestamp: now.subtract(const Duration(seconds: 5)),
        isMock: false,
        provider: 'network',
      );

      final eval = service.evaluate(location: loc, geofence: outlet);

      expect(eval.isAccurate, isFalse);
      expect(eval.isVerified, isFalse);
      expect(eval.requiresManagerReview, isTrue);
      expect(eval.fraudFlags, anyElement(contains('LOW_GPS_ACCURACY')));
    });

    test('unconfigured outlet geofence flags OUTLET_GEOFENCE_NOT_CONFIGURED', () {
      final service = GeofenceService(clock: () => now);
      final loc = GpsLocation(
        latitude: 22.572646,
        longitude: 88.363895,
        accuracy: 15.0,
        timestamp: now.subtract(const Duration(seconds: 5)),
        isMock: false,
        provider: 'gps',
      );

      final eval = service.evaluate(location: loc, geofence: null);

      expect(eval.isVerified, isFalse);
      expect(eval.requiresManagerReview, isTrue);
      expect(eval.fraudFlags, contains('OUTLET_GEOFENCE_NOT_CONFIGURED'));
      expect(eval.radiusMeters, equals(100.0));
    });
  });

  group('GeofenceService - Model Serialization', () {
    test('OutletGeofence toJson and fromJson roundtrip', () {
      final original = OutletGeofence(
        outletId: 'OUT-123',
        businessId: 'BUS-456',
        latitude: 22.5726,
        longitude: 88.3639,
        radiusMeters: 150.0,
        updatedAt: DateTime.utc(2026, 10, 22, 9, 30),
        configuredBy: 'OPERATOR-1',
      );

      final json = original.toJson();
      final decoded = OutletGeofence.fromJson(json);

      expect(decoded.outletId, equals('OUT-123'));
      expect(decoded.businessId, equals('BUS-456'));
      expect(decoded.latitude, equals(22.5726));
      expect(decoded.longitude, equals(88.3639));
      expect(decoded.radiusMeters, equals(150.0));
      expect(decoded.configuredBy, equals('OPERATOR-1'));
    });

    test('GpsLocation fromMap with various timestamp types', () {
      final millis = DateTime.utc(2026, 10, 22, 9, 0).millisecondsSinceEpoch;
      final loc = GpsLocation.fromMap({
        'latitude': 22.5,
        'longitude': 88.5,
        'accuracy': 12.5,
        'time': millis,
        'isMock': true,
        'provider': 'fused',
      });

      expect(loc.latitude, equals(22.5));
      expect(loc.longitude, equals(88.5));
      expect(loc.accuracy, equals(12.5));
      expect(loc.isMock, isTrue);
      expect(loc.provider, equals('fused'));
    });
  });
}
