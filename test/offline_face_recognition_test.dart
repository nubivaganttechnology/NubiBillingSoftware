import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/face_biometric_vault.dart';
import 'package:testflutter/data/services/offline_face_recognition.dart';

import 'support/synthetic_face_verification.dart';

void main() {
  final at = DateTime.utc(2026, 10, 21, 9);
  final query = [1.0, ...List.filled(15, 0.0)];
  FaceTemplateProfile profile(String employee, [List<double>? vector]) =>
      syntheticProfile(
        employeeId: employee,
        deviceId: 'KIOSK-1',
        at: at,
        vector: vector,
      );
  final calibration = syntheticCalibration();
  final matcher = FaceEmbeddingMatcher();

  test('synthetic cosine matching accepts a unique match only', () {
    final result = matcher.match(
      query,
      [
        profile('EMP'),
        profile('OTHER', [0, 1, ...List.filled(14, 0.0)]),
      ],
      calibration,
      at,
    );
    expect(result.status, FaceMatchStatus.accepted);
    expect(result.employeeId, 'EMP');
  });
  test('unknown is rejected instead of selecting the nearest employee', () {
    expect(
      matcher
          .match(
            query,
            [
              profile('OTHER', [0, 1, ...List.filled(14, 0.0)]),
            ],
            calibration,
            at,
          )
          .status,
      FaceMatchStatus.unknown,
    );
  });
  test(
    'two identities above threshold without a safe margin are ambiguous',
    () {
      final result = matcher.match(
        query,
        [profile('EMP'), profile('OTHER')],
        calibration,
        at,
      );
      expect(result.status, FaceMatchStatus.ambiguous);
      expect(result.employeeId, isNull);
    },
  );
  test(
    'zero, nonfinite, dimension-mismatched and expired templates fail safely',
    () {
      expect(
        matcher
            .match(List.filled(16, 0), [profile('EMP')], calibration, at)
            .status,
        FaceMatchStatus.unavailable,
      );
      expect(
        matcher.match([double.nan], [profile('EMP')], calibration, at).status,
        FaceMatchStatus.unavailable,
      );
      expect(
        matcher
            .match(
              query,
              [
                profile('EMP', [1, 2]),
              ],
              calibration,
              at,
            )
            .status,
        FaceMatchStatus.unavailable,
      );
      expect(
        matcher
            .match(
              query,
              [profile('EMP')],
              calibration,
              at.add(const Duration(days: 2)),
            )
            .status,
        FaceMatchStatus.unknown,
      );
    },
  );
  test('a different device or model cannot supply a matching identity', () {
    expect(
      matcher
          .match(
            query,
            [syntheticProfile(employeeId: 'EMP', deviceId: 'OTHER', at: at)],
            calibration,
            at,
          )
          .status,
      FaceMatchStatus.unknown,
    );
    expect(
      matcher
          .match(
            query,
            [
              syntheticProfile(
                employeeId: 'EMP',
                deviceId: 'KIOSK-1',
                at: at,
                modelVersion: 'OTHER',
              ),
            ],
            calibration,
            at,
          )
          .status,
      FaceMatchStatus.unknown,
    );
  });
  test(
    'production recognizer has no model, weights or recognition fallback',
    () async {
      expect(OfflineFaceRecognition.disabled.canEnroll, isFalse);
      await expectLater(
        OfflineFaceRecognition.disabled.embedding(syntheticSample()),
        throwsException,
      );
    },
  );
  for (final status in [
    PresentationAttackStatus.unavailable,
    PresentationAttackStatus.rejected,
  ]) {
    test(
      'identity without $status PAD cannot create an attendance ticket',
      () async {
        final engine = OfflineFaceRecognition(
          model: SyntheticEmbeddingModel(),
          pad: SyntheticPad(status: status),
          calibration: calibration,
          clock: () => at,
        );
        await expectLater(
          engine.verify(
            sample: syntheticSample(at),
            profiles: [profile('EMP')],
            tenantId: 'TEN',
            businessId: 'BUS',
            outletId: 'OUT',
            deviceId: 'KIOSK-1',
            clockReliable: true,
          ),
          throwsException,
        );
      },
    );
  }
  test('missing calibration, wrong preprocessing and suspect device clock fail closed', () async {
    final model = SyntheticEmbeddingModel();
    for (final settings in [null, calibration]) {
      final engine = OfflineFaceRecognition(
        model: model,
        pad: const SyntheticPad(),
        calibration: settings,
      );
      await expectLater(
        engine.verify(
          sample: syntheticSample(at),
          profiles: [profile('EMP')],
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          deviceId: 'KIOSK-1',
          clockReliable: false,
        ),
        throwsException,
      );
    }
    final engine = OfflineFaceRecognition(
      model: model,
      pad: const SyntheticPad(),
      calibration: calibration,
    );
    await expectLater(
      engine.embedding(
        AlignedFaceSample(Uint8List(3), 1, 'wrong-preprocessing'),
      ),
      throwsException,
    );
  });
  test(
    'ticket is scope-bound, fresh, capture-time-bound and single use',
    () async {
      Future<FaceAttendanceVerification> ticket() =>
          syntheticFaceVerification(at: at);
      void consume(
        FaceAttendanceVerification proof, {
        String employeeId = 'EMP',
        DateTime? now,
        DateTime? occurredAt,
      }) => proof.consume(
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: employeeId,
        deviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
        occurredAt: occurredAt ?? at,
        now: now ?? at,
      );
      final first = await ticket();
      expect(() => consume(first, employeeId: 'OTHER'), throwsException);
      consume(first);
      expect(() => consume(first), throwsException);
      final expired = await ticket();
      expect(
        () => consume(expired, now: at.add(const Duration(seconds: 31))),
        throwsException,
      );
      final reversed = await ticket();
      expect(
        () => consume(reversed, now: at.subtract(const Duration(seconds: 1))),
        throwsException,
      );
      final backdated = await ticket();
      expect(
        () => consume(
          backdated,
          occurredAt: at.subtract(const Duration(hours: 1)),
        ),
        throwsException,
      );
    },
  );
}
