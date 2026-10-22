import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/device_registration_service.dart';
import 'package:testflutter/data/services/face_biometric_vault.dart';

class _InMemoryValueStore implements FaceVaultValueStore {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(String key) async => _storage[key];

  @override
  Future<void> write(String key, String value) async => _storage[key] = value;

  @override
  Future<void> delete(String key) async => _storage.remove(key);

  @override
  Future<Uint8List?> readBytes(String key) async => null;

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {}

  @override
  Future<List<String>> listKeys(String prefix) async =>
      _storage.keys.where((k) => k.startsWith(prefix)).toList();
}

void main() {
  group('DeviceRegistrationService - Lifecycle & Anti-Fraud Verification', () {
    late _InMemoryValueStore store;
    late DeviceRegistrationService service;
    final testTime = DateTime.utc(2026, 10, 22, 10, 0, 0);

    setUp(() {
      store = _InMemoryValueStore();
      service = DeviceRegistrationService(
        vaultStore: store,
        clock: () => testTime,
      );
    });

    test('unregistered device returns UNREGISTERED status without blocking attendance', () async {
      final verification = await service.verifyDevice(
        employeeId: 'EMP-001',
        currentDeviceId: 'DEVICE-UNKNOWN',
      );

      expect(verification.isRegistered, isFalse);
      expect(verification.isApproved, isFalse);
      expect(verification.status, equals('UNREGISTERED'));
      expect(verification.fraudFlag, isNull);
      expect(verification.requiresReview, isFalse); // Optional registration: does not block
    });

    test('registering device with autoApprove sets status to APPROVED', () async {
      await service.registerDevice(
        employeeId: 'EMP-001',
        deviceId: 'PIXEL-6A-SECURE-KEYSTORE',
        deviceModel: 'Google Pixel 6a',
        autoApprove: true,
        approvedBy: 'OWNER-1',
      );

      final reg = await service.getRegistration('EMP-001');
      expect(reg, isNotNull);
      expect(reg!.employeeId, equals('EMP-001'));
      expect(reg.deviceId, equals('PIXEL-6A-SECURE-KEYSTORE'));
      expect(reg.deviceModel, equals('Google Pixel 6a'));
      expect(reg.status, equals('APPROVED'));
      expect(reg.approvedBy, equals('OWNER-1'));
      expect(reg.approvedAt, equals(testTime));

      final verification = await service.verifyDevice(
        employeeId: 'EMP-001',
        currentDeviceId: 'PIXEL-6A-SECURE-KEYSTORE',
      );

      expect(verification.isRegistered, isTrue);
      expect(verification.isApproved, isTrue);
      expect(verification.matches, isTrue);
      expect(verification.fraudFlag, isNull);
      expect(verification.requiresReview, isFalse);
    });

    test('pending device registration flags DEVICE_PENDING_OWNER_APPROVAL and requires review', () async {
      await service.registerDevice(
        employeeId: 'EMP-002',
        deviceId: 'PIXEL-6A-PENDING',
        deviceModel: 'Google Pixel 6a',
        autoApprove: false,
      );

      final verification = await service.verifyDevice(
        employeeId: 'EMP-002',
        currentDeviceId: 'PIXEL-6A-PENDING',
      );

      expect(verification.isRegistered, isTrue);
      expect(verification.isApproved, isFalse);
      expect(verification.matches, isTrue);
      expect(verification.fraudFlag, equals('DEVICE_PENDING_OWNER_APPROVAL'));
      expect(verification.requiresReview, isTrue);

      // Owner approves device
      await service.approveDevice(
        employeeId: 'EMP-002',
        approvedBy: 'STORE-MANAGER',
      );

      final postApproval = await service.verifyDevice(
        employeeId: 'EMP-002',
        currentDeviceId: 'PIXEL-6A-PENDING',
      );
      expect(postApproval.isApproved, isTrue);
      expect(postApproval.fraudFlag, isNull);
      expect(postApproval.requiresReview, isFalse);
    });

    test('device mismatch flags UNREGISTERED_DEVICE_DETECTED and requires manager review', () async {
      await service.registerDevice(
        employeeId: 'EMP-003',
        deviceId: 'AUTHORIZED-HARDWARE-ID',
        autoApprove: true,
        approvedBy: 'OWNER',
      );

      // Attempt attendance from a different phone/kiosk
      final verification = await service.verifyDevice(
        employeeId: 'EMP-003',
        currentDeviceId: 'UNAUTHORIZED-PHONE-ID',
      );

      expect(verification.isRegistered, isTrue);
      expect(verification.isApproved, isTrue);
      expect(verification.matches, isFalse);
      expect(verification.fraudFlag, contains('UNREGISTERED_DEVICE_DETECTED'));
      expect(verification.requiresReview, isTrue);
    });

    test('revoked device flags DEVICE_REVOKED and requires manager review', () async {
      await service.registerDevice(
        employeeId: 'EMP-004',
        deviceId: 'DEVICE-TO-REVOKE',
        autoApprove: true,
        approvedBy: 'OWNER',
      );

      await service.revokeDevice(
        employeeId: 'EMP-004',
        revokedBy: 'OWNER',
      );

      final verification = await service.verifyDevice(
        employeeId: 'EMP-004',
        currentDeviceId: 'DEVICE-TO-REVOKE',
      );

      expect(verification.isApproved, isFalse);
      expect(verification.fraudFlag, equals('DEVICE_REVOKED'));
      expect(verification.requiresReview, isTrue);
    });

    test('playIntegrityNote documents GPS authenticity limitations', () {
      expect(
        DeviceRegistrationService.playIntegrityNote,
        contains('does NOT independently prove the physical authenticity of GPS signals'),
      );
    });
  });
}
