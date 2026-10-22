import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exception.dart';

/// Narrow value-store contract so the vault can be tested without using a
/// device keystore or handling real biometric material.
abstract interface class FaceVaultValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List bytes);
  Future<List<String>> listKeys(String prefix);
}

/// Production stores must enforce replacement atomically, across vault callers.
abstract interface class FaceVaultAtomicValueStore
    implements FaceVaultValueStore {
  Future<bool> compareAndSwap(String key, String? expected, String value);
}

/// Android implementation backed by flutter_secure_storage's Android Keystore
/// wrapped key and AES-GCM encrypted values. This is deliberately distinct
/// from the application's SQLite document database and outbox.
@Deprecated(
  'Legacy erasure only. Use AndroidSqliteFaceVaultStore for new records.',
)
class AndroidFaceVaultValueStore implements FaceVaultValueStore {
  AndroidFaceVaultValueStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              keyCipherAlgorithm:
                  KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
              storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
              // Preserve the original namespace solely to delete old templates.
              // ignore: deprecated_member_use
              sharedPreferencesName: 'NubiBillBiometricVault',
              preferencesKeyPrefix: 'nb_face_vault_',
            ),
          );

  final FlutterSecureStorage _storage;

  void _requireAndroid() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const AppException(
        'Biometric enrollment is supported only on the provisioned Android kiosk.',
      );
    }
  }

  @override
  Future<String?> read(String key) {
    _requireAndroid();
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    _requireAndroid();
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    _requireAndroid();
    return _storage.delete(key: key);
  }

  @override
  Future<Uint8List?> readBytes(String key) async => null;

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {}

  @override
  Future<List<String>> listKeys(String prefix) async => const [];
}

class FaceTemplateProfile {
  const FaceTemplateProfile({
    required this.employeeId,
    required this.modelVersion,
    required this.enrolledAt,
    required this.consentPolicyVersion,
    required this.templates,
    this.enrollmentId = '',
    this.deviceId = '',
    this.retentionUntil,
  });

  final String employeeId;
  final String modelVersion;
  final DateTime enrolledAt;
  final String consentPolicyVersion;
  final List<List<double>> templates;
  final String enrollmentId;
  final String deviceId;
  final DateTime? retentionUntil;
}

/// Device-local biometric template lifecycle. The caller supplies only
/// normalized embedding vectors; images and camera frames are not accepted or
/// serialized by this service.
class FaceBiometricVault {
  FaceBiometricVault(this._store);

  final FaceVaultValueStore _store;
  static const schemaVersion = 1;
  static const minimumEnrollmentSamples = 3;
  static const maximumEnrollmentSamples = 5;

  /// Delete prototype records without importing them into the SQLite vault.
  Future<void> eraseLegacyRecords({
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
    await _store.delete('face.revocation.v$schemaVersion.$scope');
  }

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
      final expiry = DateTime.tryParse(
        data['retentionUntil']?.toString() ?? '',
      );
      if (expiry != null && !expiry.isAfter(DateTime.now())) {
        await _store.delete(key);
        return false;
      }
      return data['consentConfirmed'] == true;
    } catch (_) {
      throw const AppException(
        'Local enrollment is unreadable. Use manual attendance.',
      );
    }
  }

  String _scopeKey({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
  }) {
    final ids = [tenantId, businessId, outletId, employeeId];
    if (ids.any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id))) {
      throw const AppException(
        'A valid employee and outlet scope is required.',
      );
    }
    final scope = ids.join('|');
    return sha256.convert(utf8.encode(scope)).toString();
  }

  Future<void> enroll({
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
    final scopeKey = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final key = 'face.template.v$schemaVersion.$scopeKey';
    final previous = await _store.read(key);
    if (previous != null && !replaceExisting) {
      throw const AppException(
        'An enrollment already exists. Use authorized replacement.',
      );
    }
    final enrollmentId = List.generate(
      16,
      (_) => math.Random.secure().nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
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
    });
    final store = _store;
    if (store is FaceVaultAtomicValueStore) {
      if (!await store.compareAndSwap(key, previous, payload)) {
        throw const AppException(
          'Enrollment changed. Refresh before trying again.',
        );
      }
    } else {
      await store.write(key, payload);
    }
  }

  Future<FaceTemplateProfile?> readProfile({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String expectedModelVersion,
    String? expectedDeviceId,
    DateTime? now,
  }) async {
    final scopeKey = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    final raw = await _store.read('face.template.v$schemaVersion.$scopeKey');
    if (raw == null) return null;
    try {
      final record = jsonDecode(raw) as Map<String, dynamic>;
      if (record['schemaVersion'] != schemaVersion ||
          record['consentConfirmed'] != true ||
          record['tenantId'] != tenantId ||
          record['businessId'] != businessId ||
          record['outletId'] != outletId ||
          record['employeeId'] != employeeId) {
        return null;
      }
      if (record['modelVersion'] != expectedModelVersion) {
        throw const AppException(
          'This enrollment uses a different recognition model. Re-enrollment is required.',
        );
      }
      if (expectedDeviceId != null && record['deviceId'] != expectedDeviceId) {
        throw const AppException(
          'This enrollment belongs to a different device.',
        );
      }
      final retention = DateTime.tryParse(
        record['retentionUntil']?.toString() ?? '',
      );
      if (retention != null && !retention.isAfter(now ?? DateTime.now())) {
        await _store.delete('face.template.v$schemaVersion.$scopeKey');
        return null;
      }
      final templates = (record['templates'] as List)
          .map(
            (rawSample) => (rawSample as List)
                .map((value) => (value as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false);
      final dimensions = record['embeddingDimensions'];
      if (dimensions is! int ||
          dimensions < 16 ||
          dimensions > 4096 ||
          templates.length < minimumEnrollmentSamples ||
          templates.length > maximumEnrollmentSamples ||
          templates.any((v) => v.length != dimensions)) {
        throw const FormatException('Invalid local profile');
      }
      for (final vector in templates) {
        _normalized(vector);
      }
      return FaceTemplateProfile(
        employeeId: employeeId,
        modelVersion: expectedModelVersion,
        enrolledAt: DateTime.parse(record['enrolledAt'] as String),
        consentPolicyVersion: record['consentPolicyVersion'] as String,
        templates: templates,
        enrollmentId: record['enrollmentId'] as String? ?? '',
        deviceId: record['deviceId'] as String? ?? '',
        retentionUntil: retention,
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'The local face enrollment is unreadable. Re-enroll this employee.',
      );
    }
  }

  /// Removes the template value and records a non-template revocation marker
  /// in the same encrypted, device-local store.
  Future<void> revoke({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String revokedBy,
    required DateTime revokedAt,
  }) async {
    final scopeKey = _scopeKey(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
    );
    await _store.delete('face.template.v$schemaVersion.$scopeKey');
    await _store.write(
      'face.revocation.v$schemaVersion.$scopeKey',
      jsonEncode({
        'schemaVersion': schemaVersion,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'employeeId': employeeId,
        'revokedBy': revokedBy,
        'revokedAt': revokedAt.toUtc().toIso8601String(),
        'templateRemoved': true,
        'retentionUntil': revokedAt
            .add(const Duration(days: 90))
            .toUtc()
            .toIso8601String(),
        'retentionUntilEpochMillis': revokedAt
            .add(const Duration(days: 90))
            .millisecondsSinceEpoch,
      }),
    );
  }

  List<double> _normalized(List<double> vector) {
    if (vector.any((value) => !value.isFinite)) {
      throw const AppException('Face embedding contains invalid values.');
    }
    final norm = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (!norm.isFinite || norm < 1e-12) {
      throw const AppException('Face embedding has no usable signal.');
    }
    return vector.map((value) => value / norm).toList(growable: false);
  }
}
