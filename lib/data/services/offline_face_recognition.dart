import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';
import 'face_biometric_vault.dart';

/// A model adapter must consume precisely this aligned RGB preprocessing.
/// Never derive identity vectors from ML Kit tracking IDs or face landmarks.
class AlignedFaceSample {
  const AlignedFaceSample(
    this.rgb,
    this.edge,
    this.preprocessingVersion, {
    this.capturedAt,
  });
  final Uint8List rgb;
  final int edge;
  final String preprocessingVersion;
  final DateTime? capturedAt;
}

abstract interface class FaceEmbeddingModel {
  String get version;
  String get preprocessingVersion;
  int get dimensions;

  /// Reviewed document covering exact weight SHA-256, redistribution and data provenance.
  String? get commercialLicenseReview;
  Future<List<double>> embed(AlignedFaceSample sample);
}

/// No inference runtime or weights are installed until exact weights are approved.
class UnavailableFaceEmbeddingModel implements FaceEmbeddingModel {
  const UnavailableFaceEmbeddingModel();
  @override
  String get version => 'UNAVAILABLE';
  @override
  String get preprocessingVersion => 'UNAVAILABLE';
  @override
  int get dimensions => 0;
  @override
  String? get commercialLicenseReview => null;
  @override
  Future<List<double>> embed(AlignedFaceSample sample) async =>
      throw const AppException(
        'A commercially reviewed recognition model is not installed.',
      );
}

enum PresentationAttackStatus { validatedLive, rejected, unavailable }

class PresentationAttackResult {
  const PresentationAttackResult(
    this.status,
    this.version,
    this.evaluationReport,
  );
  final PresentationAttackStatus status;
  final String version;
  final String? evaluationReport;
}

abstract interface class FacePresentationAttackDetector {
  /// Must bind the result to this capture, device and a validated challenge session.
  Future<PresentationAttackResult> evaluate(
    AlignedFaceSample sample,
    String deviceId,
  );
}

class UnavailablePresentationAttackDetector
    implements FacePresentationAttackDetector {
  const UnavailablePresentationAttackDetector();
  @override
  Future<PresentationAttackResult> evaluate(
    AlignedFaceSample sample,
    String deviceId,
  ) async => const PresentationAttackResult(
    PresentationAttackStatus.unavailable,
    'UNAVAILABLE',
    null,
  );
}

class FaceMatchingCalibration {
  const FaceMatchingCalibration({
    required this.modelVersion,
    required this.preprocessingVersion,
    required this.deviceId,
    required this.minimumCosine,
    required this.minimumMargin,
    required this.evaluationReport,
  });
  final String modelVersion, preprocessingVersion, deviceId, evaluationReport;
  final double minimumCosine, minimumMargin;
  bool get isUsable =>
      evaluationReport.trim().isNotEmpty &&
      minimumCosine.isFinite &&
      minimumCosine > 0 &&
      minimumCosine <= 1 &&
      minimumMargin.isFinite &&
      minimumMargin > 0 &&
      minimumMargin <= 2;
}

enum FaceMatchStatus { accepted, unknown, ambiguous, unavailable }

class FaceMatchResult {
  const FaceMatchResult(this.status, [this.employeeId, this.score]);
  final FaceMatchStatus status;
  final String? employeeId;
  final double? score;
}

/// Scores never leave this service or enter the ordinary attendance outbox.
class FaceEmbeddingMatcher {
  static List<double>? normalized(List<double> v) {
    if (v.isEmpty || v.any((n) => !n.isFinite)) return null;
    final norm = math.sqrt(v.fold<double>(0, (s, n) => s + n * n));
    if (!norm.isFinite || norm < 1e-12) return null;
    return v.map((n) => n / norm).toList(growable: false);
  }

  FaceMatchResult match(
    List<double> query,
    List<FaceTemplateProfile> profiles,
    FaceMatchingCalibration calibration,
    DateTime now,
  ) {
    final q = normalized(query);
    if (!calibration.isUsable || q == null) {
      return const FaceMatchResult(FaceMatchStatus.unavailable);
    }
    final scores = <String, double>{};
    for (final profile in profiles) {
      if (profile.modelVersion != calibration.modelVersion ||
          (profile.deviceId.isNotEmpty &&
              calibration.deviceId.isNotEmpty &&
              profile.deviceId != calibration.deviceId) ||
          profile.retentionUntil == null ||
          !profile.retentionUntil!.isAfter(now)) {
        continue;
      }
      for (final raw in profile.templates) {
        final vector = normalized(raw);
        if (vector == null || vector.length != q.length) {
          return const FaceMatchResult(FaceMatchStatus.unavailable);
        }
        var score = 0.0;
        for (var i = 0; i < q.length; i++) {
          score += q[i] * vector[i];
        }
        scores.update(
          profile.employeeId,
          (old) => math.max(old, score),
          ifAbsent: () => score,
        );
      }
    }
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty || ranked.first.value < calibration.minimumCosine) {
      return FaceMatchResult(
        FaceMatchStatus.unknown,
        null,
        ranked.firstOrNull?.value,
      );
    }
    if (ranked.length > 1 &&
        ranked.first.value - ranked[1].value < calibration.minimumMargin) {
      return FaceMatchResult(
        FaceMatchStatus.ambiguous,
        null,
        ranked.first.value,
      );
    }
    return FaceMatchResult(
      FaceMatchStatus.accepted,
      ranked.first.key,
      ranked.first.value,
    );
  }
}

/// Issued only after calibrated identity matching, licensed inference, a live
/// PAD result and clock validation. Short-lived, scope-bound, single-use.
class FaceAttendanceVerification {
  FaceAttendanceVerification._({
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.employeeId,
    required this.deviceId,
    required this.modelVersion,
    required this.livenessVersion,
    required this.verifiedAt,
  });
  final String tenantId, businessId, outletId, employeeId, deviceId;
  final String modelVersion, livenessVersion;
  final DateTime verifiedAt;
  bool _consumed = false;

  void consume({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String deviceId,
    required String modelVersion,
    required String livenessVersion,
    required DateTime occurredAt,
    required DateTime now,
  }) {
    final age = now.toUtc().difference(verifiedAt.toUtc());
    if (_consumed ||
        this.tenantId != tenantId ||
        this.businessId != businessId ||
        this.outletId != outletId ||
        this.employeeId != employeeId ||
        this.deviceId != deviceId ||
        this.modelVersion != modelVersion ||
        this.livenessVersion != livenessVersion ||
        age.isNegative ||
        age > const Duration(seconds: 30) ||
        occurredAt.difference(verifiedAt).abs() > const Duration(seconds: 30)) {
      throw const AppException(
        'Fresh identity and liveness verification is required. Use manual attendance.',
      );
    }
    _consumed = true;
  }
}

class OfflineFaceRecognition {
  const OfflineFaceRecognition({
    required this.model,
    required this.pad,
    this.calibration,
    this.clock = DateTime.now,
  });
  static const disabled = OfflineFaceRecognition(
    model: UnavailableFaceEmbeddingModel(),
    pad: UnavailablePresentationAttackDetector(),
  );
  final FaceEmbeddingModel model;
  final FacePresentationAttackDetector pad;
  final FaceMatchingCalibration? calibration;
  final DateTime Function() clock;
  bool get canEnroll =>
      model.commercialLicenseReview?.trim().isNotEmpty == true &&
      model.dimensions >= 16 &&
      model.dimensions <= 4096;

  Future<List<double>> embedding(AlignedFaceSample sample) async {
    if (!canEnroll ||
        sample.preprocessingVersion != model.preprocessingVersion ||
        sample.rgb.length != sample.edge * sample.edge * 3) {
      throw const AppException(
        'Recognition model or preprocessing has not been approved. Use manual attendance.',
      );
    }
    final vector = await model.embed(sample);
    final normalized = FaceEmbeddingMatcher.normalized(vector);
    if (vector.length != model.dimensions || normalized == null) {
      throw const AppException(
        'The recognition model returned an unusable template.',
      );
    }
    return normalized;
  }

  Future<FaceAttendanceVerification> verify({
    required AlignedFaceSample sample,
    required List<FaceTemplateProfile> profiles,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String deviceId,
    required bool clockReliable,
  }) async {
    final capturedAt = sample.capturedAt;
    bool fresh() =>
        capturedAt != null &&
        !clock().difference(capturedAt).isNegative &&
        clock().difference(capturedAt) <= const Duration(seconds: 30);
    if (!fresh()) {
      throw const AppException(
        'A fresh camera capture is required. Use manual attendance.',
      );
    }
    final settings = calibration;
    if (!clockReliable ||
        settings == null ||
        !settings.isUsable ||
        settings.modelVersion != model.version ||
        settings.deviceId != deviceId ||
        settings.preprocessingVersion != sample.preprocessingVersion) {
      throw const AppException(
        'Recognition calibration or device time is not verified. Use manual attendance.',
      );
    }
    final vector = await embedding(sample);
    final match = FaceEmbeddingMatcher().match(
      vector,
      profiles,
      settings,
      clock(),
    );
    if (match.status != FaceMatchStatus.accepted) {
      throw const AppException(
        'No unambiguous verified identity. Use manual attendance.',
      );
    }
    final live = await pad.evaluate(sample, deviceId);
    if (live.status != PresentationAttackStatus.validatedLive ||
        live.evaluationReport?.trim().isNotEmpty != true ||
        live.version.trim().isEmpty ||
        !fresh()) {
      throw const AppException(
        'Liveness is not verified. An authorized manager must use manual attendance.',
      );
    }
    return FaceAttendanceVerification._(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      employeeId: match.employeeId!,
      deviceId: deviceId,
      modelVersion: model.version,
      livenessVersion: live.version,
      verifiedAt: capturedAt!.toUtc(),
    );
  }
}
