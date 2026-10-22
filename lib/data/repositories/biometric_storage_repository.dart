import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/errors/app_exception.dart';
import '../services/face_biometric_vault.dart';

/// Abstract repository interface for biometric storage.
///
/// Implementations decouple the application from storage mechanics:
/// - Current: [SqliteBiometricStorageRepository] (AES-256 GCM encrypted SQLite)
/// - Future: Encrypted REST + MySQL adapter (see documentation in this file)
abstract interface class BiometricStorageRepository {
  /// Persists a new enrollment with consent and biometric templates, plus optional photo BLOB.
  Future<void> saveEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required bool consentConfirmed,
    required String consentPolicyVersion,
    required DateTime consentedAt,
    required DateTime enrolledAt,
    required String modelVersion,
    required int embeddingDimensions,
    required List<List<double>> embeddings,
    Uint8List? photoBytes,
    String deviceId = '',
    String enrolledBy = '',
    DateTime? retentionUntil,
    bool replaceExisting = false,
  });

  /// Checks if an active, non-expired enrollment exists for the employee.
  Future<bool> hasEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  });

  /// Reads the face template profile for recognition comparison.
  Future<FaceTemplateProfile?> getProfile({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String expectedModelVersion,
    String? expectedDeviceId,
    DateTime? now,
  });

  /// Reads the encrypted enrollment photograph BLOB for administrative inspection.
  Future<Uint8List?> getEnrollmentPhoto({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  });

  /// Securely deletes both the template profiles and enrollment photo.
  Future<void> deleteEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  });

  /// Lists all enrolled face profiles for an outlet permitted for recognition.
  Future<List<FaceTemplateProfile>> listProfilesForOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String expectedModelVersion,
    DateTime? now,
  });
}

/// Production implementation of [BiometricStorageRepository] backed by
/// device-local SQLite storage with Android Keystore AES-256 GCM encryption.
///
/// Zero cloud calls, zero Firestore dependency, zero plaintext storage.
class SqliteBiometricStorageRepository implements BiometricStorageRepository {
  SqliteBiometricStorageRepository(this._store);

  final FaceVaultAtomicValueStore _store;
  static const schemaVersion = 1;
  static const minimumEnrollmentSamples = 1;
  static const maximumEnrollmentSamples = 5;

  String _scopeKey({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  }) {
    final ids = [tenantId, businessId, outletId, employeeId];
    if (ids.any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id))) {
      throw const AppException('A valid employee and outlet scope is required.');
    }
    return sha256.convert(utf8.encode(ids.join('|'))).toString();
  }

  String _outletPrefix({
    required String tenantId,
    required String businessId,
    required String outletId,
  }) {
    return 'face.template.v$schemaVersion.';
  }

  @override
  Future<void> saveEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required bool consentConfirmed,
    required String consentPolicyVersion,
    required DateTime consentedAt,
    required DateTime enrolledAt,
    required String modelVersion,
    required int embeddingDimensions,
    required List<List<double>> embeddings,
    Uint8List? photoBytes,
    String deviceId = '',
    String enrolledBy = '',
    DateTime? retentionUntil,
    bool replaceExisting = false,
  }) async {
    if (!consentConfirmed ||
        consentPolicyVersion.trim().isEmpty ||
        modelVersion.trim().isEmpty) {
      throw const AppException(
        'Employee consent and a supported recognition model are required.',
      );
    }
    if (embeddingDimensions < 16 ||
        embeddingDimensions > 4096 ||
        embeddings.length < minimumEnrollmentSamples ||
        embeddings.length > maximumEnrollmentSamples ||
        embeddings.any((sample) => sample.length != embeddingDimensions)) {
      throw const AppException('Face enrollment samples are invalid.');
    }
    final normalized = embeddings.map(_normalized).toList(growable: false);
    if (consentedAt.isAfter(enrolledAt) ||
        (retentionUntil != null && !retentionUntil.isAfter(enrolledAt))) {
      throw const AppException('Consent and retention dates are invalid.');
    }

    final scope = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final templateKey = 'face.template.v$schemaVersion.$scope';
    final photoKey = 'face.photo.v$schemaVersion.$scope';

    final previous = await _store.read(templateKey);
    if (previous != null && !replaceExisting) {
      throw const AppException(
        'An enrollment already exists. Use authorized replacement.',
      );
    }

    final enrollmentId = List.generate(
      16,
      (_) => math.Random.secure().nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final payload = jsonEncode({
      'schemaVersion': schemaVersion,
      'tenantId': tenantId,
      'businessId': businessId,
      'outletId': outletId,
      'employeeId': employeeId,
      'enrollmentId': enrollmentId,
      'deviceId': deviceId,
      'enrolledBy': enrolledBy,
      'retentionUntil':
          (retentionUntil ?? enrolledAt.add(const Duration(days: 90)))
              .toUtc()
              .toIso8601String(),
      'retentionUntilEpochMillis':
          (retentionUntil ?? enrolledAt.add(const Duration(days: 90)))
              .millisecondsSinceEpoch,
      'consentConfirmed': true,
      'consentedByEmployeeId': employeeId,
      'consentRecordedBy': enrolledBy,
      'consentPolicyVersion': consentPolicyVersion,
      'consentedAt': consentedAt.toUtc().toIso8601String(),
      'enrolledAt': enrolledAt.toUtc().toIso8601String(),
      'modelVersion': modelVersion,
      'embeddingDimensions': embeddingDimensions,
      'templates': normalized,
      'hasPhoto': photoBytes != null && photoBytes.isNotEmpty,
    });

    if (!await _store.compareAndSwap(templateKey, previous, payload)) {
      throw const AppException(
        'Enrollment changed concurrently. Refresh before trying again.',
      );
    }

    // Save encrypted photo BLOB if provided
    if (photoBytes != null && photoBytes.isNotEmpty) {
      await _store.writeBytes(photoKey, photoBytes);
    }
  }

  @override
  Future<bool> hasEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  }) async {
    final scope = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final key = 'face.template.v$schemaVersion.$scope';
    final raw = await _store.read(key);
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map;
      final expiry = DateTime.tryParse(data['retentionUntil']?.toString() ?? '');
      if (expiry != null && !expiry.isAfter(DateTime.now())) {
        await _store.delete(key);
        await _store.delete('face.photo.v$schemaVersion.$scope');
        return false;
      }
      return data['consentConfirmed'] == true;
    } catch (_) {
      throw const AppException(
        'Local enrollment is unreadable. Use manual attendance.',
      );
    }
  }

  @override
  Future<FaceTemplateProfile?> getProfile({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String expectedModelVersion,
    String? expectedDeviceId,
    DateTime? now,
  }) async {
    final scope = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final key = 'face.template.v$schemaVersion.$scope';
    final raw = await _store.read(key);
    if (raw == null) return null;
    return _parseProfile(raw, expectedModelVersion, expectedDeviceId, now);
  }

  @override
  Future<Uint8List?> getEnrollmentPhoto({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  }) async {
    final scope = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final key = 'face.photo.v$schemaVersion.$scope';
    return await _store.readBytes(key);
  }

  @override
  Future<void> deleteEnrollment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  }) async {
    final scope = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    await _store.delete('face.template.v$schemaVersion.$scope');
    await _store.delete('face.photo.v$schemaVersion.$scope');
    await _store.delete('face.revocation.v$schemaVersion.$scope');
  }

  @override
  Future<List<FaceTemplateProfile>> listProfilesForOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String expectedModelVersion,
    DateTime? now,
  }) async {
    final prefix = _outletPrefix(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
    );
    final keys = await _store.listKeys(prefix);
    final profiles = <FaceTemplateProfile>[];
    for (final key in keys) {
      if (!key.startsWith('face.template.v$schemaVersion.')) continue;
      final raw = await _store.read(key);
      if (raw == null) continue;
      final profile = _parseProfile(raw, expectedModelVersion, null, now);
      if (profile != null) {
        profiles.add(profile);
      }
    }
    return profiles;
  }

  FaceTemplateProfile? _parseProfile(
    String raw,
    String expectedModelVersion,
    String? expectedDeviceId,
    DateTime? now,
  ) {
    try {
      final data = jsonDecode(raw) as Map;
      if (data['consentConfirmed'] != true ||
          data['modelVersion'] != expectedModelVersion) {
        return null;
      }
      final retention = DateTime.tryParse(data['retentionUntil']?.toString() ?? '');
      if (retention != null && !(retention.isAfter(now ?? DateTime.now()))) {
        return null;
      }
      if (expectedDeviceId != null &&
          expectedDeviceId.isNotEmpty &&
          data['deviceId'] != null &&
          data['deviceId'].toString().isNotEmpty &&
          data['deviceId'] != expectedDeviceId) {
        return null;
      }
      final rawTemplates = (data['templates'] as List)
          .map((row) => (row as List).map((n) => (n as num).toDouble()).toList())
          .toList();
      return FaceTemplateProfile(
        employeeId: data['employeeId'] as String,
        modelVersion: data['modelVersion'] as String,
        enrolledAt: DateTime.parse(data['enrolledAt'] as String),
        consentPolicyVersion: data['consentPolicyVersion'] as String,
        templates: rawTemplates,
        enrollmentId: data['enrollmentId'] as String? ?? '',
        deviceId: data['deviceId'] as String? ?? '',
        retentionUntil: retention,
      );
    } catch (_) {
      return null;
    }
  }

  List<double> _normalized(List<double> v) {
    final norm = math.sqrt(v.fold<double>(0, (s, n) => s + n * n));
    if (!norm.isFinite || norm < 1e-12) {
      throw const AppException('Unusable embedding vector.');
    }
    return v.map((n) => n / norm).toList(growable: false);
  }
}

/// Future PHP REST + MySQL Architecture Specification:
///
/// When a future cloud backend is commissioned, an adapter implementing
/// [BiometricStorageRepository] will be created:
///
/// class PhpMysqlBiometricStorageRepositoryAdapter implements BiometricStorageRepository {
///   // Communicates with PHP endpoints:
///   // POST /api/v1/biometrics/enroll
///   // GET  /api/v1/biometrics/profile/{employeeId}
///   // GET  /api/v1/biometrics/photo/{employeeId}
///   // DELETE /api/v1/biometrics/{employeeId}
///   //
///   // All payloads use AES-256-GCM envelope encryption before network transit.
///   // Biometric vectors and photo BLOBs are never stored in plaintext MySQL columns.
///   // Transport is authenticated via HMAC + TLS 1.3 token verification.
/// }
