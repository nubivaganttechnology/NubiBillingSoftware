// Standalone, debug-only synthetic storage test. No AppController, account DB,
// employee data, camera capture, recognition model, payroll or network client.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'data/services/android_sqlite_face_vault_store.dart';
import 'data/services/face_biometric_vault.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _FixturePage()));
}

class _FixturePage extends StatefulWidget {
  const _FixturePage();
  @override
  State<_FixturePage> createState() => _FixturePageState();
}

class _FixturePageState extends State<_FixturePage> {
  static const _channel = MethodChannel('nubibill/face_vault');
  static const _tenant = 'SYNTHETIC-TENANT';
  static const _business = 'SYNTHETIC-BUSINESS';
  static const _outlet = 'SYNTHETIC-OUTLET';
  static const _employee = 'SYNTHETIC-EMPLOYEE';
  static const _model = 'SYNTHETIC-NO-FACE-MODEL';
  static const _sentinel = 'SYNTHETIC-ENCRYPTION-SENTINEL-LOCAL-ONLY';
  static const _store = AndroidSqliteFaceVaultStore(tenantId: _tenant);
  final _checks = <String, bool>{};
  String _status = 'Running synthetic native storage tests…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _check(String name, bool passes) {
    _checks[name] = passes;
    if (!passes) throw StateError('Synthetic fixture assertion failed: $name');
  }

  Future<bool> _rejects(Future<Object?> Function() action) async {
    try {
      await action();
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<T?> _native<T>(
    String method, [
    Map<String, Object?> args = const {},
  ]) => _channel.invokeMethod<T>(method, {'tenantId': _tenant, ...args});

  Future<void> _enroll(
    FaceBiometricVault vault,
    String device, {
    String employee = _employee,
    bool consent = true,
    DateTime? at,
  }) async {
    final date = at ?? DateTime.now().toUtc();
    final vectors = List.generate(5, (_) => [1.0, ...List.filled(15, 0.0)]);
    try {
      await vault.enroll(
        tenantId: _tenant,
        businessId: _business,
        outletId: _outlet,
        employeeId: employee,
        consentConfirmed: consent,
        consentPolicyVersion: 'SYNTHETIC-NO-PARTICIPANT',
        consentedAt: date,
        enrolledAt: date,
        modelVersion: _model,
        embeddingDimensions: 16,
        embeddings: vectors,
        deviceId: device,
        enrolledBy: 'SYNTHETIC-TEST-RUNNER',
      );
    } finally {
      for (final vector in vectors) {
        vector.fillRange(0, vector.length, 0);
      }
    }
  }

  Future<FaceTemplateProfile?> _profile(
    FaceBiometricVault vault,
    String device, {
    String employee = _employee,
  }) => vault.readProfile(
    tenantId: _tenant,
    businessId: _business,
    outletId: _outlet,
    employeeId: employee,
    expectedModelVersion: _model,
    expectedDeviceId: device,
  );

  Future<void> _run() async {
    final report = <String, Object?>{
      'syntheticOnly': true,
      'cameraOpened': false,
      'productionTouched': false,
      'checks': _checks,
    };
    try {
      if (!kDebugMode || !const bool.fromEnvironment('NUBIBILL_FACE_FIXTURE')) {
        throw StateError('Fixture build flag is required.');
      }
      // Native package/debug checks execute BEFORE opening/binding any vault.
      final environment = await _native<Map>('fixtureEnvironment');
      if (environment?['packageId'] !=
          'com.example.testflutter.attendancefixture') {
        throw StateError(
          'Refusing to run outside the isolated fixture package.',
        );
      }
      report['environment'] = environment;
      final vault = FaceBiometricVault(_store);
      final restarting = await _store.read('fixture.restart') == 'READY';
      report['phase'] = restarting
          ? 'AFTER_PROCESS_RESTART'
          : 'BEFORE_PROCESS_RESTART';
      if (!restarting) {
        await _store
            .resetDeviceVault(); // This package contains synthetic data only.
        final device = await _store.deviceId();
        _check(
          'clockRequiresOwnerConfirmation',
          !await _store.clockIsReliable(),
        );
        await _store.confirmDeviceTime();
        _check('confirmedClockAccepted', await _store.clockIsReliable());
        _check(
          'consentRequired',
          await _rejects(() => _enroll(vault, device, consent: false)),
        );
        await _enroll(vault, device);
        final profile = await _profile(vault, device);
        _check(
          'syntheticEnrollmentRoundTrip',
          profile?.templates.length == 5 && profile?.deviceId == device,
        );
        _check(
          'duplicateEnrollmentRejected',
          await _rejects(() => _enroll(vault, device)),
        );
        _check(
          'casCreate',
          await _store.compareAndSwap('fixture.cas', null, 'FIRST'),
        );
        _check(
          'casRejectsStaleValue',
          !await _store.compareAndSwap('fixture.cas', 'WRONG', 'SECOND'),
        );
        _check(
          'casUpdate',
          await _store.compareAndSwap('fixture.cas', 'FIRST', 'SECOND'),
        );
        _check('casPersisted', await _store.read('fixture.cas') == 'SECOND');
        _check(
          'otherTenantRefused',
          await _rejects(
            () => const AndroidSqliteFaceVaultStore(
              tenantId: 'OTHER-SYNTHETIC-TENANT',
            ).deviceId(),
          ),
        );
        report['keyInfo'] = await _native<Map>('fixtureKeyInfo');
        await _store.write('fixture.durable', _sentinel);
        await _store.write('fixture.deviceId', device);
        await _store.write('fixture.restart', 'READY');
        report['result'] = 'READY_FOR_PROCESS_RESTART';
      } else {
        final device = await _store.deviceId();
        _check(
          'encryptedValueSurvivesRestart',
          await _store.read('fixture.durable') == _sentinel,
        );
        _check(
          'deviceIdSurvivesRestart',
          await _store.read('fixture.deviceId') == device,
        );
        final profile = await _profile(vault, device);
        _check('enrollmentSurvivesRestart', profile?.templates.length == 5);
        _check('clockAnchorSurvivesAppRestart', await _store.clockIsReliable());
        report['keyInfo'] = await _native<Map>('fixtureKeyInfo');
        await vault.revoke(
          tenantId: _tenant,
          businessId: _business,
          outletId: _outlet,
          employeeId: _employee,
          revokedBy: 'SYNTHETIC-TEST-RUNNER',
          revokedAt: DateTime.now(),
        );
        _check(
          'withdrawalRemovesTemplate',
          await _profile(vault, device) == null,
        );
        const expiredEmployee = 'SYNTHETIC-EXPIRED';
        await _enroll(
          vault,
          device,
          employee: expiredEmployee,
          at: DateTime.now().subtract(const Duration(days: 100)),
        );
        await _store
            .deviceId(); // Native opening purges expired encrypted records.
        final scope = sha256.convert(
          utf8.encode([_tenant, _business, _outlet, expiredEmployee].join('|')),
        );
        _check(
          'nativeRetentionPurge',
          await _store.read('face.template.v1.$scope') == null,
        );
        await _store.write('fixture.tamper', _sentinel);
        await _native<void>('fixtureTamper', {'key': 'fixture.tamper'});
        _check(
          'tamperedCiphertextRejected',
          await _rejects(() => _store.read('fixture.tamper')),
        );
        await _store.write('fixture.source', 'SYNTHETIC-SOURCE');
        await _store.write('fixture.target', 'SYNTHETIC-TARGET');
        await _native<void>('fixtureTransplant', {
          'source': 'fixture.source',
          'target': 'fixture.target',
        });
        _check(
          'recordAadTransplantRejected',
          await _rejects(() => _store.read('fixture.target')),
        );
        await _native<void>('fixtureLoseKey');
        _check(
          'lostKeyReadFailsClosed',
          await _rejects(() => _store.read('fixture.durable')),
        );
        _check(
          'lostKeyWriteDoesNotReplaceKey',
          await _rejects(() => _store.write('fixture.new', 'SYNTHETIC')),
        );
        await _store.resetDeviceVault();
        final replacementDevice = await _store.deviceId();
        _check('lostKeyResetRecoversVault', replacementDevice.isNotEmpty);
        _check(
          'oldTemplateAbsentAfterReset',
          await _profile(vault, replacementDevice) == null,
        );
        await _enroll(vault, replacementDevice);
        _check(
          'syntheticReenrollmentAfterKeyLoss',
          await _profile(vault, replacementDevice) != null,
        );
        report['result'] = 'PASS';
      }
    } catch (_) {
      report['result'] =
          'FAIL'; // Deliberately omit raw exception/platform payloads.
    }
    final json = const JsonEncoder.withIndent('  ').convert(report);
    final directory = await getApplicationSupportDirectory();
    await File('${directory.path}/face_fixture_report.json')
        .writeAsString(json, flush: true);
    // Only nonbiometric synthetic test outcomes are printed.
    debugPrint('NUBIBILL_FACE_FIXTURE_REPORT=${jsonEncode(report)}');
    if (mounted) setState(() => _status = json);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synthetic storage tests')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        'Separate fixture application. No real employees or camera capture.\n\n$_status',
      ),
    ),
  );
}
