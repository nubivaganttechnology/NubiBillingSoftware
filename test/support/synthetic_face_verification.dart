// Synthetic control-flow fixtures only. No face model, image, license clearance,
// biometric accuracy or PAD capability is established by these adapters.
import 'dart:typed_data';

import 'package:testflutter/data/services/face_biometric_vault.dart';
import 'package:testflutter/data/services/offline_face_recognition.dart';

class SyntheticEmbeddingModel implements FaceEmbeddingModel {
  SyntheticEmbeddingModel({this.version = 'MODEL-TEST', List<double>? output})
    : output = output ?? [1, ...List.filled(15, 0.0)];
  final List<double> output;
  @override
  final String version;
  @override
  String get preprocessingVersion => 'SYNTHETIC-NO-IMAGE';
  @override
  int get dimensions => 16;
  @override
  String? get commercialLicenseReview => 'SYNTHETIC TEST ADAPTER ONLY';
  @override
  Future<List<double>> embed(AlignedFaceSample sample) async => List.of(output);
}

class SyntheticPad implements FacePresentationAttackDetector {
  const SyntheticPad({
    this.version = 'PAD-TEST',
    this.status = PresentationAttackStatus.validatedLive,
  });
  final String version;
  final PresentationAttackStatus status;
  @override
  Future<PresentationAttackResult> evaluate(
    AlignedFaceSample sample,
    String deviceId,
  ) async => PresentationAttackResult(
    status,
    version,
    'SYNTHETIC CONTROL-FLOW FIXTURE ONLY',
  );
}

AlignedFaceSample syntheticSample([DateTime? at]) => AlignedFaceSample(
  Uint8List(3),
  1,
  'SYNTHETIC-NO-IMAGE',
  capturedAt: at ?? DateTime.now(),
);

FaceTemplateProfile syntheticProfile({
  required String employeeId,
  required String deviceId,
  required DateTime at,
  String modelVersion = 'MODEL-TEST',
  List<double>? vector,
}) => FaceTemplateProfile(
  employeeId: employeeId,
  modelVersion: modelVersion,
  deviceId: deviceId,
  enrollmentId: 'SYNTHETIC-ENROLLMENT',
  enrolledAt: at,
  retentionUntil: at.add(const Duration(days: 1)),
  consentPolicyVersion: 'SYNTHETIC',
  templates: List.generate(
    3,
    (_) => List.of(vector ?? [1, ...List.filled(15, 0.0)]),
  ),
);

FaceMatchingCalibration syntheticCalibration({
  String modelVersion = 'MODEL-TEST',
  String deviceId = 'KIOSK-1',
}) => FaceMatchingCalibration(
  modelVersion: modelVersion,
  preprocessingVersion: 'SYNTHETIC-NO-IMAGE',
  deviceId: deviceId,
  minimumCosine: 0.85,
  minimumMargin: 0.12,
  evaluationReport: 'SYNTHETIC THRESHOLDS; NOT A DEVICE CALIBRATION',
);

Future<FaceAttendanceVerification> syntheticFaceVerification({
  required DateTime at,
  String tenantId = 'TEN',
  String businessId = 'BUS',
  String outletId = 'OUT',
  String employeeId = 'EMP',
  String deviceId = 'KIOSK-1',
  String modelVersion = 'MODEL-TEST',
  String livenessVersion = 'PAD-TEST',
}) =>
    OfflineFaceRecognition(
      model: SyntheticEmbeddingModel(version: modelVersion),
      pad: SyntheticPad(version: livenessVersion),
      calibration: syntheticCalibration(
        modelVersion: modelVersion,
        deviceId: deviceId,
      ),
      clock: () => at,
    ).verify(
      sample: syntheticSample(at),
      profiles: [
        syntheticProfile(
          employeeId: employeeId,
          deviceId: deviceId,
          at: at,
          modelVersion: modelVersion,
        ),
      ],
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      deviceId: deviceId,
      clockReliable: true,
    );
