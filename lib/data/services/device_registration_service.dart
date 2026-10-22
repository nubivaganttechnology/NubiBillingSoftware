import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'face_biometric_vault.dart';

class EmployeeDeviceRegistration {
  const EmployeeDeviceRegistration({
    required this.employeeId,
    required this.deviceId,
    this.deviceModel = 'Android Device',
    required this.registeredAt,
    required this.status, // 'PENDING', 'APPROVED', 'REVOKED'
    this.approvedBy,
    this.approvedAt,
    this.keystoreProtected = true,
  });

  final String employeeId;
  final String deviceId;
  final String deviceModel;
  final DateTime registeredAt;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final bool keystoreProtected;

  bool get isApproved => status == 'APPROVED';
  bool get isRevoked => status == 'REVOKED';
  bool get isPending => status == 'PENDING';

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'deviceId': deviceId,
    'deviceModel': deviceModel,
    'registeredAt': registeredAt.toIso8601String(),
    'status': status,
    'approvedBy': approvedBy,
    'approvedAt': approvedAt?.toIso8601String(),
    'keystoreProtected': keystoreProtected,
  };

  factory EmployeeDeviceRegistration.fromJson(Map<String, dynamic> json) =>
      EmployeeDeviceRegistration(
        employeeId: json['employeeId'] as String,
        deviceId: json['deviceId'] as String,
        deviceModel: json['deviceModel'] as String? ?? 'Android Device',
        registeredAt: DateTime.parse(json['registeredAt'] as String),
        status: json['status'] as String? ?? 'PENDING',
        approvedBy: json['approvedBy'] as String?,
        approvedAt: json['approvedAt'] != null
            ? DateTime.parse(json['approvedAt'] as String)
            : null,
        keystoreProtected: json['keystoreProtected'] == true,
      );
}

class DeviceVerificationResult {
  const DeviceVerificationResult({
    required this.isRegistered,
    required this.isApproved,
    required this.matches,
    required this.status,
    this.fraudFlag,
    required this.requiresReview,
    this.registeredDeviceId,
  });

  final bool isRegistered;
  final bool isApproved;
  final bool matches;
  final String status;
  final String? fraudFlag;
  final bool requiresReview;
  final String? registeredDeviceId;
}

class DeviceRegistrationService {
  DeviceRegistrationService({
    this.vaultStore,
    this.clock = DateTime.now,
  });

  final FaceVaultValueStore? vaultStore;
  final DateTime Function() clock;

  static const String playIntegrityNote =
      'Play Integrity provides device and app binary authenticity attestations, but does NOT independently prove the physical authenticity of GPS signals.';

  String _key(String employeeId) => 'device.employee.$employeeId';

  Future<EmployeeDeviceRegistration?> getRegistration(String employeeId) async {
    if (vaultStore == null) return null;
    final raw = await vaultStore!.read(_key(employeeId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return EmployeeDeviceRegistration.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> registerDevice({
    required String employeeId,
    required String deviceId,
    String? deviceModel,
    bool autoApprove = false,
    String? approvedBy,
  }) async {
    final now = clock().toUtc();
    final reg = EmployeeDeviceRegistration(
      employeeId: employeeId,
      deviceId: deviceId,
      deviceModel: deviceModel ?? (kIsWeb ? 'Web' : defaultTargetPlatform.name),
      registeredAt: now,
      status: autoApprove ? 'APPROVED' : 'PENDING',
      approvedBy: autoApprove ? approvedBy : null,
      approvedAt: autoApprove ? now : null,
      keystoreProtected: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
    );
    if (vaultStore != null) {
      await vaultStore!.write(_key(employeeId), jsonEncode(reg.toJson()));
    }
  }

  Future<void> approveDevice({
    required String employeeId,
    required String approvedBy,
  }) async {
    final existing = await getRegistration(employeeId);
    if (existing == null) return;
    final now = clock().toUtc();
    final updated = EmployeeDeviceRegistration(
      employeeId: existing.employeeId,
      deviceId: existing.deviceId,
      deviceModel: existing.deviceModel,
      registeredAt: existing.registeredAt,
      status: 'APPROVED',
      approvedBy: approvedBy,
      approvedAt: now,
      keystoreProtected: existing.keystoreProtected,
    );
    if (vaultStore != null) {
      await vaultStore!.write(_key(employeeId), jsonEncode(updated.toJson()));
    }
  }

  Future<void> revokeDevice({
    required String employeeId,
    required String revokedBy,
  }) async {
    final existing = await getRegistration(employeeId);
    if (existing == null) return;
    final now = clock().toUtc();
    final updated = EmployeeDeviceRegistration(
      employeeId: existing.employeeId,
      deviceId: existing.deviceId,
      deviceModel: existing.deviceModel,
      registeredAt: existing.registeredAt,
      status: 'REVOKED',
      approvedBy: revokedBy,
      approvedAt: now,
      keystoreProtected: existing.keystoreProtected,
    );
    if (vaultStore != null) {
      await vaultStore!.write(_key(employeeId), jsonEncode(updated.toJson()));
    }
  }

  Future<DeviceVerificationResult> verifyDevice({
    required String employeeId,
    required String currentDeviceId,
  }) async {
    final reg = await getRegistration(employeeId);
    // Optional device registration: if not registered, it is permitted but marked un-registered
    if (reg == null) {
      return const DeviceVerificationResult(
        isRegistered: false,
        isApproved: false,
        matches: true,
        status: 'UNREGISTERED',
        fraudFlag: null,
        requiresReview: false,
      );
    }

    if (reg.isRevoked) {
      return DeviceVerificationResult(
        isRegistered: true,
        isApproved: false,
        matches: false,
        status: 'REVOKED',
        fraudFlag: 'DEVICE_REVOKED',
        requiresReview: true,
        registeredDeviceId: reg.deviceId,
      );
    }

    if (reg.isPending) {
      return DeviceVerificationResult(
        isRegistered: true,
        isApproved: false,
        matches: reg.deviceId == currentDeviceId,
        status: 'PENDING_APPROVAL',
        fraudFlag: 'DEVICE_PENDING_OWNER_APPROVAL',
        requiresReview: true,
        registeredDeviceId: reg.deviceId,
      );
    }

    if (reg.deviceId != currentDeviceId) {
      return DeviceVerificationResult(
        isRegistered: true,
        isApproved: true,
        matches: false,
        status: 'MISMATCH',
        fraudFlag: 'UNREGISTERED_DEVICE_DETECTED (Current: $currentDeviceId != Registered: ${reg.deviceId})',
        requiresReview: true,
        registeredDeviceId: reg.deviceId,
      );
    }

    return DeviceVerificationResult(
      isRegistered: true,
      isApproved: true,
      matches: true,
      status: 'APPROVED',
      fraudFlag: null,
      requiresReview: false,
      registeredDeviceId: reg.deviceId,
    );
  }
}
