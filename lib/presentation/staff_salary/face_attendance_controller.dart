part of '../app_controller.dart';

/// Local biometric lifecycle is deliberately separate from attendance REST writes.
extension StaffFaceAttendanceActions on AppController {
  AndroidSqliteFaceVaultStore get faceVaultStore {
    final tenant = appContext?.ownerUid;
    if (tenant == null) {
      throw const AppException('An authorized tenant is required.');
    }
    return AndroidSqliteFaceVaultStore(tenantId: tenant);
  }

  FaceBiometricVault get faceVault => FaceBiometricVault(faceVaultStore);

  BiometricStorageRepository get biometricStorage =>
      SqliteBiometricStorageRepository(faceVaultStore);

  GeofenceService get geofenceService =>
      GeofenceService(vaultStore: faceVaultStore);

  DeviceRegistrationService get deviceRegistrationService =>
      DeviceRegistrationService(vaultStore: faceVaultStore);

  static const consentPolicyVersion = 'local-face-attendance-v1-90-days';

  Future<EmployeeModel> _authorizedFaceEmployee(
    String employeeId, {
    required bool revoke,
  }) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null ||
        !(revoke
            ? canRevokeBiometricAttendance()
            : canEnrollBiometricAttendance())) {
      throw const AppException(
        'Biometric permission and an assigned outlet are required.',
      );
    }
    final staff = await loadStaffKhataEmployees();
    final current = appContext;
    if (current != original ||
        !(revoke
            ? canRevokeBiometricAttendance()
            : canEnrollBiometricAttendance())) {
      throw const AppException('Workspace changed. Refresh before continuing.');
    }
    final matches = staff.where(
      (employee) =>
          employee.employeeId == employeeId &&
          employee.ownerUid == original.ownerUid &&
          employee.isActive &&
          employee.businessIds.contains(original.businessId) &&
          employee.outletIds.contains(original.outletId),
    );
    if (matches.length != 1) {
      throw const AppException('Employee is not active in this outlet.');
    }
    return matches.single;
  }

  Future<void> enrollStaffFace({
    required String employeeId,
    required bool consentConfirmed,
    required List<List<double>> embeddings,
    Uint8List? photoBytes,
    bool replaceExisting = false,
  }) async {
    if (!faceRecognition.canEnroll) {
      throw const AppException(
        'A commercially reviewed recognition model is not installed. Use manual attendance.',
      );
    }
    final original = appContext;
    await _authorizedFaceEmployee(employeeId, revoke: false);
    final device = await faceVaultStore.deviceId();
    if (!await faceVaultStore.clockIsReliable()) {
      throw const AppException(
        'An owner must confirm device time before enrollment. Use manual attendance.',
      );
    }
    if (appContext != original || !canEnrollBiometricAttendance()) {
      throw const AppException('Workspace or biometric permission changed.');
    }
    final now = DateTime.now().toUtc();
    await biometricStorage.saveEnrollment(
      tenantId: original!.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      employeeId: employeeId,
      consentConfirmed: consentConfirmed,
      consentPolicyVersion: consentPolicyVersion,
      consentedAt: now,
      enrolledAt: now,
      modelVersion: faceRecognition.model.version,
      embeddingDimensions: faceRecognition.model.dimensions,
      embeddings: embeddings,
      photoBytes: photoBytes,
      deviceId: device,
      enrolledBy: original.uid,
      retentionUntil: now.add(const Duration(days: 90)),
      replaceExisting: replaceExisting,
    );
  }

  Future<Uint8List?> getEnrolledPhoto(String employeeId) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null) {
      return null;
    }
    return biometricStorage.getEnrollmentPhoto(
      tenantId: original.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      employeeId: employeeId,
    );
  }

  Future<void> revokeStaffFace(String employeeId) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null ||
        !canRevokeBiometricAttendance()) {
      throw const AppException('Biometric revocation permission is required.');
    }
    await biometricStorage.deleteEnrollment(
      tenantId: original.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      employeeId: employeeId,
    );
    await faceVault.revoke(
      tenantId: original.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      employeeId: employeeId,
      revokedBy: original.uid,
      revokedAt: DateTime.now().toUtc(),
    );
    // ignore: deprecated_member_use
    await FaceBiometricVault(AndroidFaceVaultValueStore()).eraseLegacyRecords(
      tenantId: original.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      employeeId: employeeId,
    );
  }

  Future<FaceMatchResult> recognizeStaffFace(AlignedFaceSample sample) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null) {
      throw const AppException('Workspace context is required.');
    }
    final device = await faceVaultStore.deviceId();
    final staff = await loadStaffKhataEmployees();
    final profiles = await biometricStorage.listProfilesForOutlet(
      tenantId: original.ownerUid,
      businessId: original.businessId!,
      outletId: original.outletId!,
      expectedModelVersion: faceRecognition.model.version,
    );
    final activeIds = staff
        .where((e) =>
            e.isActive &&
            e.businessIds.contains(original.businessId) &&
            e.outletIds.contains(original.outletId))
        .map((e) => e.employeeId)
        .toSet();
    final filteredProfiles =
        profiles.where((p) => activeIds.contains(p.employeeId)).toList();

    final vector = await faceRecognition.embedding(sample);
    final calibration = FaceMatchingCalibration(
      modelVersion: SFaceEmbeddingModel.modelVersion,
      preprocessingVersion: FaceCaptureProcessor.preprocessingVersion,
      deviceId: device,
      minimumCosine: 0.363,
      minimumMargin: 0.05,
      evaluationReport:
          'OpenCV SFace 2021dec calibrated cosine threshold: 0.363 baseline',
    );
    return FaceEmbeddingMatcher().match(
      vector,
      filteredProfiles,
      calibration,
      DateTime.now(),
    );
  }

  Future<void> recordPrototypeTestAttendance({
    required String employeeId,
    required bool isCheckIn,
  }) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null) {
      throw const AppException('Workspace context is required.');
    }
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    if (isCheckIn) {
      await staffAttendanceRepository.recordManualAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        workDate: date,
        status: 'PRESENT',
        checkIn: now,
        recordedBy: original.uid,
        token: auth.currentSession?.idToken ?? '',
      );
    } else {
      final rows = await staffAttendanceRepository.listAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        from: now.subtract(const Duration(days: 2)),
        through: now,
        token: auth.currentSession?.idToken ?? '',
      );
      final open = rows
          .where(
            (r) =>
                r['approvalStatus'] == 'PENDING' &&
                r['checkInAt'] != null &&
                r['checkOutAt'] == null,
          )
          .toList();
      if (open.isEmpty) {
        throw const AppException('No open check-in session found to check out.');
      }
      final existingCheckIn = DateTime.parse(open.first['checkInAt'] as String);
      final existingWorkDate = DateTime.parse(open.first['workDate'] as String);
      await staffAttendanceRepository.recordManualAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        workDate: existingWorkDate,
        status: open.first['attendanceStatus'] as String? ?? 'PRESENT',
        checkIn: existingCheckIn,
        checkOut: now,
        earlyCheckoutReason: now.difference(existingCheckIn).inMinutes < 480
            ? 'Prototype face recognition test checkout'
            : null,
        recordedBy: original.uid,
        token: auth.currentSession?.idToken ?? '',
      );
    }
  }

  Future<void> recordMobileGeofenceAttendance({
    required String employeeId,
    required bool isCheckIn,
    required GpsLocation? location,
    required GeofenceEvaluation? geofenceEvaluation,
    required FaceLivenessResult? livenessResult,
    required DeviceVerificationResult? deviceResult,
  }) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null) {
      throw const AppException('Workspace context is required.');
    }
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    final device = await faceVaultStore.deviceId();

    final fraudFlags = <String>[
      if (geofenceEvaluation != null) ...geofenceEvaluation.fraudFlags,
      if (livenessResult != null && !livenessResult.passed)
        'LIVENESS_FAILED (${livenessResult.failureReason ?? "Incomplete"})',
      if (deviceResult != null && deviceResult.fraudFlag != null)
        deviceResult.fraudFlag!,
    ];

    final verificationStatus =
        fraudFlags.isEmpty ? 'VERIFIED' : 'FLAGGED_FOR_REVIEW';

    if (isCheckIn) {
      await staffAttendanceRepository.recordManualAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        workDate: date,
        status: 'PRESENT',
        checkIn: now,
        attendanceMethod: 'MOBILE_FACE_GEOFENCE',
        latitude: location?.latitude,
        longitude: location?.longitude,
        gpsAccuracy: location?.accuracy,
        isMockLocation: location?.isMock,
        geofenceDistanceMeters: geofenceEvaluation?.distanceMeters,
        geofenceRadiusMeters: geofenceEvaluation?.radiusMeters,
        livenessChallenges: livenessResult?.completedChallenges,
        fraudFlags: fraudFlags,
        verificationStatus: verificationStatus,
        kioskDeviceId: device,
        recordedBy: original.uid,
        token: auth.currentSession?.idToken ?? '',
      );
    } else {
      final rows = await staffAttendanceRepository.listAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        from: now.subtract(const Duration(days: 2)),
        through: now,
        token: auth.currentSession?.idToken ?? '',
      );
      final open = rows
          .where(
            (r) =>
                r['approvalStatus'] == 'PENDING' &&
                r['checkInAt'] != null &&
                r['checkOutAt'] == null,
          )
          .toList();
      if (open.isEmpty) {
        throw const AppException('No open check-in session found to check out.');
      }
      final existingCheckIn = DateTime.parse(open.first['checkInAt'] as String);
      final existingWorkDate = DateTime.parse(open.first['workDate'] as String);
      await staffAttendanceRepository.recordManualAttendance(
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        employeeId: employeeId,
        workDate: existingWorkDate,
        status: open.first['attendanceStatus'] as String? ?? 'PRESENT',
        checkIn: existingCheckIn,
        checkOut: now,
        earlyCheckoutReason: now.difference(existingCheckIn).inMinutes < 480
            ? 'Mobile face recognition test checkout'
            : null,
        attendanceMethod: 'MOBILE_FACE_GEOFENCE',
        latitude: location?.latitude,
        longitude: location?.longitude,
        gpsAccuracy: location?.accuracy,
        isMockLocation: location?.isMock,
        geofenceDistanceMeters: geofenceEvaluation?.distanceMeters,
        geofenceRadiusMeters: geofenceEvaluation?.radiusMeters,
        livenessChallenges: livenessResult?.completedChallenges,
        fraudFlags: fraudFlags,
        verificationStatus: verificationStatus,
        kioskDeviceId: device,
        recordedBy: original.uid,
        token: auth.currentSession?.idToken ?? '',
      );
    }
  }

  Future<FaceAttendanceVerification> verifyStaffFace(
    AlignedFaceSample sample,
  ) async {
    final original = appContext;
    if (original == null ||
        original.businessId == null ||
        original.outletId == null ||
        !canManageStaffAttendance()) {
      throw const AppException('Attendance management permission is required.');
    }
    final device = await faceVaultStore.deviceId();
    final staff = await loadStaffKhataEmployees();
    final profiles = <FaceTemplateProfile>[];
    try {
      for (final employee in staff) {
        final profile = await biometricStorage.getProfile(
          tenantId: original.ownerUid,
          businessId: original.businessId!,
          outletId: original.outletId!,
          employeeId: employee.employeeId,
          expectedModelVersion: faceRecognition.model.version,
          expectedDeviceId: device,
        );
        if (profile != null) profiles.add(profile);
      }
      final ticket = await faceRecognition.verify(
        sample: sample,
        profiles: profiles,
        tenantId: original.ownerUid,
        businessId: original.businessId!,
        outletId: original.outletId!,
        deviceId: device,
        clockReliable: await faceVaultStore.clockIsReliable(),
      );
      if (appContext != original || !canManageStaffAttendance()) {
        throw const AppException('Workspace or attendance permission changed.');
      }
      return ticket;
    } finally {
      for (final profile in profiles) {
        for (final vector in profile.templates) {
          vector.fillRange(0, vector.length, 0);
        }
      }
    }
  }

  Future<void> resetStaffFaceDeviceVault() async {
    if (appContext?.accountType != 'owner' || !canRevokeBiometricAttendance()) {
      throw const AppException('Only an owner may reset this device vault.');
    }
    await faceVaultStore.resetDeviceVault();
  }

  Future<void> confirmStaffFaceDeviceTime() async {
    if (appContext?.accountType != 'owner' || !canRevokeBiometricAttendance()) {
      throw const AppException('Only an owner may confirm device time.');
    }
    await faceVaultStore.confirmDeviceTime();
  }
}
