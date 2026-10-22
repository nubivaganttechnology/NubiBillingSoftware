import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/face_biometric_vault.dart';

class _FakeSecretStore implements FaceVaultAtomicValueStore {
  final values = <String, String>{};
  final byteValues = <String, Uint8List>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async {
    values.remove(key);
    byteValues.remove(key);
  }
  @override
  Future<Uint8List?> readBytes(String key) async => byteValues[key];
  @override
  Future<void> writeBytes(String key, Uint8List bytes) async => byteValues[key] = bytes;
  @override
  Future<List<String>> listKeys(String prefix) async =>
      [...values.keys, ...byteValues.keys].where((k) => k.startsWith(prefix)).toList();
  @override
  Future<bool> compareAndSwap(
    String key,
    String? expected,
    String value,
  ) async {
    if (values[key] != expected) return false;
    values[key] = value;
    return true;
  }
}

void main() {
  late _FakeSecretStore store;
  late FaceBiometricVault vault;
  final scope = {
    'tenantId': 'TENANT-1',
    'businessId': 'BUSINESS-1',
    'outletId': 'OUTLET-1',
    'employeeId': 'EMPLOYEE-1',
  };
  List<List<double>> samples() => [
    List<double>.generate(192, (i) => i == 0 ? 1 : 0),
    List<double>.generate(192, (i) => i == 1 ? 2 : 0),
    List<double>.generate(192, (i) => i == 2 ? 3 : 0),
  ];
  Future<void> enroll({
    required bool consentConfirmed,
    required List<List<double>> embeddings,
    String modelVersion = 'test-model-1',
  }) => vault.enroll(
    tenantId: scope['tenantId']!,
    businessId: scope['businessId']!,
    outletId: scope['outletId']!,
    employeeId: scope['employeeId']!,
    consentConfirmed: consentConfirmed,
    consentPolicyVersion: 'consent-v1',
    consentedAt: DateTime.utc(2026, 10, 20),
    enrolledAt: DateTime.utc(2026, 10, 20),
    modelVersion: modelVersion,
    embeddingDimensions: 192,
    embeddings: embeddings,
  );
  Future<FaceTemplateProfile?> read(String modelVersion) => vault.readProfile(
    tenantId: scope['tenantId']!,
    businessId: scope['businessId']!,
    outletId: scope['outletId']!,
    employeeId: scope['employeeId']!,
    expectedModelVersion: modelVersion,
    now: DateTime.utc(2026, 10, 21),
  );

  setUp(() {
    store = _FakeSecretStore();
    vault = FaceBiometricVault(store);
  });

  test(
    'enrollment requires consent and stores only normalized embeddings',
    () async {
      await expectLater(
        enroll(consentConfirmed: false, embeddings: samples()),
        throwsException,
      );
      expect(store.values, isEmpty);

      await enroll(consentConfirmed: true, embeddings: samples());
      final key = store.values.keys.single;
      expect(key, startsWith('face.template.v1.'));
      expect(key, isNot(contains(scope['employeeId'])));
      final stored = jsonDecode(store.values.values.single) as Map;
      expect(stored.containsKey('rawImage'), isFalse);
      expect(stored.containsKey('imagePath'), isFalse);
      expect(stored['consentConfirmed'], isTrue);

      final profile = await read('test-model-1');
      expect(profile!.templates, hasLength(3));
      for (final vector in profile.templates) {
        final squaredNorm = vector.fold<double>(
          0,
          (sum, value) => sum + value * value,
        );
        expect(squaredNorm, closeTo(1, 1e-9));
      }
    },
  );

  test(
    'model changes require re-enrollment and withdrawal removes the template',
    () async {
      await enroll(consentConfirmed: true, embeddings: samples());
      await expectLater(read('test-model-2'), throwsException);

      await vault.revoke(
        tenantId: scope['tenantId']!,
        businessId: scope['businessId']!,
        outletId: scope['outletId']!,
        employeeId: scope['employeeId']!,
        revokedBy: 'OWNER-1',
        revokedAt: DateTime.utc(2026, 10, 21),
      );
      expect(store.values.keys, hasLength(1));
      final revocation = jsonDecode(store.values.values.single) as Map;
      expect(revocation['templateRemoved'], isTrue);
      expect(revocation.containsKey('templates'), isFalse);
      expect(await read('test-model-1'), isNull);
    },
  );

  test('invalid, non-finite or empty embedding samples are rejected', () async {
    await expectLater(
      enroll(
        consentConfirmed: true,
        embeddings: [
          List<double>.filled(192, 0),
          List<double>.filled(192, 0),
          List<double>.filled(192, double.infinity),
        ],
      ),
      throwsException,
    );
    expect(store.values, isEmpty);
  });

  test('duplicate enrollment needs explicit replacement and keeps a stable employee ID', () async {
    await enroll(consentConfirmed: true, embeddings: samples());
    final original = await read('test-model-1');
    await expectLater(
      enroll(consentConfirmed: true, embeddings: samples()),
      throwsException,
    );
    expect((await read('test-model-1'))!.enrollmentId, original!.enrollmentId);
    await vault.enroll(
      tenantId: scope['tenantId']!,
      businessId: scope['businessId']!,
      outletId: scope['outletId']!,
      employeeId: scope['employeeId']!,
      consentConfirmed: true,
      consentPolicyVersion: 'renewed-consent-v2',
      consentedAt: DateTime.utc(2026, 10, 21),
      enrolledAt: DateTime.utc(2026, 10, 21),
      modelVersion: 'test-model-1',
      embeddingDimensions: 192,
      embeddings: samples(),
      deviceId: 'DEVICE-1',
      replaceExisting: true,
    );
    final replacement = await read('test-model-1');
    expect(replacement!.employeeId, scope['employeeId']);
    expect(replacement.enrollmentId, isNot(original.enrollmentId));
    expect(replacement.consentPolicyVersion, 'renewed-consent-v2');
    await expectLater(
      vault.readProfile(
        tenantId: scope['tenantId']!,
        businessId: scope['businessId']!,
        outletId: scope['outletId']!,
        employeeId: scope['employeeId']!,
        expectedModelVersion: 'test-model-1',
        expectedDeviceId: 'OTHER',
        now: DateTime.utc(2026, 10, 21),
      ),
      throwsException,
    );
  });

  test(
    'expired templates are removed and unrelated scopes remain invisible',
    () async {
      await enroll(consentConfirmed: true, embeddings: samples());
      expect(
        await vault.readProfile(
          tenantId: scope['tenantId']!,
          businessId: scope['businessId']!,
          outletId: 'OTHER',
          employeeId: scope['employeeId']!,
          expectedModelVersion: 'test-model-1',
        ),
        isNull,
      );
      expect(
        await vault.readProfile(
          tenantId: scope['tenantId']!,
          businessId: scope['businessId']!,
          outletId: scope['outletId']!,
          employeeId: scope['employeeId']!,
          expectedModelVersion: 'test-model-1',
          now: DateTime.utc(2027, 2, 1),
        ),
        isNull,
      );
      expect(store.values, isEmpty);
    },
  );

  test('corrupt, nonfinite or oversized profiles are rejected without returning vectors', () async {
    await enroll(consentConfirmed: true, embeddings: samples());
    final key = store.values.keys.single;
    final json = jsonDecode(store.values[key]!) as Map<String, dynamic>;
    json['embeddingDimensions'] = 99999;
    store.values[key] = jsonEncode(json);
    await expectLater(read('test-model-1'), throwsException);
    store.values[key] = 'unreadable';
    await expectLater(read('test-model-1'), throwsException);
  });
}
