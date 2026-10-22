import 'dart:convert';
import 'dart:io';

import '../test/support/synthetic_face_verification.dart';

import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/repositories/staff_attendance_repository.dart';
import 'package:testflutter/data/repositories/staff_salary_repository.dart';
import 'package:testflutter/data/services/firebase_auth_rest_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

/// Isolated end-to-end SQLite -> sync outbox -> Firestore REST smoke test.
/// Run only against local emulators, with FIRESTORE_EMULATOR_HOST and
/// FIREBASE_AUTH_EMULATOR_HOST explicitly set. It creates throwaway users and
/// documents in the demo project and a SQLite file under system temp.
class _EmulatorRoutingClient extends http.BaseClient {
  _EmulatorRoutingClient(this.inner, this.firestoreHost, this.authHost);
  final http.Client inner;
  final String firestoreHost;
  final String authHost;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    late final Uri target;
    if (uri.host == 'firestore.googleapis.com') {
      target = Uri.parse(
        'http://$firestoreHost${uri.path}?${uri.hasQuery ? uri.query : ''}',
      );
    } else if (uri.host == 'identitytoolkit.googleapis.com') {
      target = Uri.parse(
        'http://$authHost/identitytoolkit.googleapis.com${uri.path}?${uri.hasQuery ? uri.query : ''}',
      );
    } else if (uri.host == 'securetoken.googleapis.com') {
      target = Uri.parse(
        'http://$authHost/securetoken.googleapis.com${uri.path}?${uri.query}',
      );
    } else {
      throw StateError(
        'Emulator smoke test refused an unexpected remote host.',
      );
    }
    final routed = http.Request(request.method, target)
      ..headers.addAll(request.headers)
      ..bodyBytes = await request.finalize().toBytes();
    return inner.send(routed);
  }

  @override
  void close() => inner.close();
}

class _OfflineConnectivity extends ConnectivityService {
  _OfflineConnectivity() {
    available = false;
  }
}

Future<void> runStaffSalaryFirestoreEmulatorSmoke() async {
  // flutter_test normally replaces dart:io HttpClient with a fake that returns
  // 400. This opt-in test deliberately talks only to local emulator hosts.
  HttpOverrides.global = null;
  final firestoreHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final authHost = Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'];
  if (firestoreHost == null ||
      authHost == null ||
      !EnvironmentConfig.isConfigured) {
    throw StateError(
      'Set both emulator hosts and FIREBASE_PROJECT_ID/API_KEY dart defines.',
    );
  }
  if (!EnvironmentConfig.projectId.startsWith('demo-')) {
    throw StateError(
      'Refusing to run unless FIREBASE_PROJECT_ID starts with demo-.',
    );
  }
  for (final host in [firestoreHost, authHost]) {
    final uri = Uri.parse('http://$host');
    if (!{'127.0.0.1', 'localhost', '::1'}.contains(uri.host) ||
        !uri.hasPort ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'This fixture only accepts explicitly configured loopback emulator hosts.',
      );
    }
  }

  sqfliteFfiInit();
  final directory = await Directory.systemTemp.createTemp(
    'nubibill-salary-rest-',
  );
  final routedClient = _EmulatorRoutingClient(
    http.Client(),
    firestoreHost,
    authHost,
  );
  final api = ApiClient(client: routedClient);
  final authService = FirebaseAuthRestService(api);
  final owner = await authService.createEmailPasswordAccount(
    'salary-owner-${DateTime.now().microsecondsSinceEpoch}@example.test',
    'Salary-Test-Password-123!',
  );
  final other = await authService.createEmailPasswordAccount(
    'salary-other-${DateTime.now().microsecondsSinceEpoch}@example.test',
    'Salary-Test-Password-123!',
  );
  final rest = FirestoreRestService(api);
  final database = LocalDatabase(
    factory: databaseFactoryFfi,
    directory: directory.path,
  );
  final connectivity = _OfflineConnectivity();
  final sync = SyncEngine(
    rest,
    connectivity,
    sessionProvider: () async => owner,
  );
  final offline = OfflineFirestoreService(database, rest, sync);
  try {
    await offline.activate(owner.uid);
    sync.beginScopeChange();
    final source = LocalDataSource(
      await database.open(EnvironmentConfig.projectId, owner.uid),
    );
    final runId = DateTime.now().microsecondsSinceEpoch.toString();
    final businessId = 'REST-DEMO-BIZ-$runId';
    final outletId = 'REST-DEMO-OUT-$runId';
    final employeeId = 'REST-DEMO-EMP-$runId';

    await rest.createDocument('employees', employeeId, {
      'employeeId': employeeId,
      'ownerUid': owner.uid,
      'tenantId': owner.uid,
      'businessIds': [businessId],
      'outletIds': [outletId],
      'name': 'Disposable emulator employee',
      'status': 'ACTIVE',
      'updatedAt': DateTime.now().toUtc(),
    }, idToken: owner.idToken);
    await rest.createDocument('outlets', outletId, {
      'outletId': outletId,
      'tenantId': owner.uid,
      'businessId': businessId,
      'name': 'Disposable emulator outlet',
      'updatedAt': DateTime.now().toUtc(),
    }, idToken: owner.idToken);
    // Exercise real REST reads and seed only this disposable local SQLite file.
    await source.upsertRemote('employees', [
      await rest.getDocument('employees', employeeId, idToken: owner.idToken),
    ]);
    await source.upsertRemote('outlets', [
      await rest.getDocument('outlets', outletId, idToken: owner.idToken),
    ]);

    final repository = StaffSalaryRepository(offline, offline);
    final profileId = await repository.saveSalaryProfile(
      tenantId: owner.uid,
      businessId: businessId,
      employeeId: employeeId,
      salaryType: 'MONTHLY',
      baseRatePaise: 3250000,
      paymentCycle: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: owner.uid,
      token: owner.idToken,
    );
    final localProfile = await source.row(
      'employee_salary_profiles',
      profileId,
    );
    if (localProfile == null) {
      throw StateError('Salary profile was not persisted locally.');
    }
    final pendingBeforePush = await source.db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox',
    );
    if ((pendingBeforePush.single['c'] as int) == 0) {
      throw StateError('Salary profile write did not persist an outbox event.');
    }

    final periodId = await repository.approveSalaryPeriod(
      tenantId: owner.uid,
      businessId: businessId,
      employeeId: employeeId,
      profileId: profileId,
      periodStart: DateTime.utc(2026, 10, 1),
      periodEnd: DateTime.utc(2026, 10, 31),
      workUnitsMilli: 0,
      approvedBy: owner.uid,
      token: owner.idToken,
    );

    var eventClock = DateTime.utc(2026, 10, 20, 9);
    final attendanceRepository = StaffAttendanceRepository(
      offline,
      offline,
      clock: () => eventClock,
    );
    final workDate = DateTime.utc(2026, 10, 20);
    final attendanceId = await attendanceRepository.recordFaceCheckIn(
      verification: await syntheticFaceVerification(
        at: eventClock,
        tenantId: owner.uid,
        businessId: businessId,
        outletId: outletId,
        employeeId: employeeId,
        deviceId: 'EMULATOR-KIOSK',
        modelVersion: 'EMULATOR-FIXTURE',
        livenessVersion: 'EMULATOR-FIXTURE',
      ),
      tenantId: owner.uid,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
      workDate: workDate,
      occurredAt: DateTime.utc(2026, 10, 20, 9),
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'EMULATOR-KIOSK',
      modelVersion: 'EMULATOR-FIXTURE',
      livenessVersion: 'EMULATOR-FIXTURE',
      recordedBy: owner.uid,
      token: owner.idToken,
    );
    eventClock = DateTime.utc(2026, 10, 20, 18);
    await attendanceRepository.recordFaceCheckOut(
      verification: await syntheticFaceVerification(
        at: eventClock,
        tenantId: owner.uid,
        businessId: businessId,
        outletId: outletId,
        employeeId: employeeId,
        deviceId: 'EMULATOR-KIOSK',
        modelVersion: 'EMULATOR-FIXTURE',
        livenessVersion: 'EMULATOR-FIXTURE',
      ),
      tenantId: owner.uid,
      businessId: businessId,
      outletId: outletId,
      employeeId: employeeId,
      workDate: workDate,
      occurredAt: DateTime.utc(2026, 10, 20, 18),
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'EMULATOR-KIOSK',
      modelVersion: 'EMULATOR-FIXTURE',
      livenessVersion: 'EMULATOR-FIXTURE',
      recordedBy: owner.uid,
      token: owner.idToken,
    );
    final localAttendance = await source.row('staff_attendance', attendanceId);
    if (localAttendance == null) {
      throw StateError('Attendance was not persisted in local SQLite.');
    }
    // A repeated save uses the existing stable employee/outlet/day identity;
    // it must not create a second local daily attendance document.
    final duplicateBlocked = await attendanceRepository
        .recordFaceCheckIn(
          verification: await syntheticFaceVerification(
            at: eventClock,
            tenantId: owner.uid,
            businessId: businessId,
            outletId: outletId,
            employeeId: employeeId,
            deviceId: 'EMULATOR-KIOSK',
            modelVersion: 'EMULATOR-FIXTURE',
            livenessVersion: 'EMULATOR-FIXTURE',
          ),
          tenantId: owner.uid,
          businessId: businessId,
          outletId: outletId,
          employeeId: employeeId,
          workDate: workDate,
          occurredAt: eventClock,
          timeZoneId: 'Asia/Kolkata',
          kioskDeviceId: 'EMULATOR-KIOSK',
          modelVersion: 'EMULATOR-FIXTURE',
          livenessVersion: 'EMULATOR-FIXTURE',
          recordedBy: owner.uid,
          token: owner.idToken,
        )
        .then((_) => false, onError: (_) => true);
    if (!duplicateBlocked) {
      throw StateError('Duplicate face kiosk check-in was not blocked.');
    }

    final staffPurchaseId = 'SKH-REST-PUR-$runId';
    await offline.runAtomicOperation((transaction) async {
      transaction.create('staff_khata_transactions', staffPurchaseId, {
        'recordId': staffPurchaseId,
        'tenantId': owner.uid,
        'businessId': businessId,
        'outletId': outletId,
        'employeeId': employeeId,
        'transactionType': 'STORE_PURCHASE',
        'amountPaise': 12500,
        'referenceType': 'INVOICE',
        'referenceId': 'EMULATOR-INVOICE-$runId',
        'status': 'POSTED',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }, idToken: owner.idToken);
    if (await source.row('staff_khata_transactions', staffPurchaseId) == null) {
      throw StateError('Staff purchase was not persisted in local SQLite.');
    }

    connectivity.available = true;
    await sync.sync(pull: false);
    final remoteProfile = await rest.getDocument(
      'employee_salary_profiles',
      profileId,
      idToken: owner.idToken,
    );
    final remoteProfileFields = FirestoreRestService.decodeFields(
      remoteProfile['fields'],
    );
    if (remoteProfileFields['baseRatePaise'] != 3250000 ||
        remoteProfileFields['employeeId'] != employeeId) {
      throw StateError(
        'Firestore REST returned a different salary profile payload.',
      );
    }
    final remotePeriod = await rest.getDocument(
      'salary_periods',
      periodId,
      idToken: owner.idToken,
    );
    final remotePeriodFields = FirestoreRestService.decodeFields(
      remotePeriod['fields'],
    );
    if (remotePeriodFields['status'] != 'APPROVED' ||
        remotePeriodFields['employeeId'] != employeeId ||
        remotePeriodFields['expenseAmountPaise'] != 3250000 ||
        (remotePeriodFields['outletBasisPoints'] as Map?)?[outletId] != 10000) {
      throw StateError(
        'Firestore REST returned a different approved salary period.',
      );
    }
    final remoteAttendance = await rest.getDocument(
      'staff_attendance',
      attendanceId,
      idToken: owner.idToken,
    );
    final remoteAttendanceFields = FirestoreRestService.decodeFields(
      remoteAttendance['fields'],
    );
    if (remoteAttendanceFields['attendanceId'] != attendanceId ||
        remoteAttendanceFields['employeeId'] != employeeId ||
        remoteAttendanceFields['businessId'] != businessId ||
        remoteAttendanceFields['outletId'] != outletId ||
        remoteAttendanceFields['attendanceStatus'] != 'PRESENT' ||
        remoteAttendanceFields['workedMinutes'] != 540) {
      throw StateError(
        'Firestore REST returned a different attendance record.',
      );
    }
    final checkInEventId = StaffAttendanceRepository.attendanceEventId(
      attendanceId: attendanceId,
      eventType: 'CHECK_IN',
    );
    final checkOutEventId = StaffAttendanceRepository.attendanceEventId(
      attendanceId: attendanceId,
      eventType: 'CHECK_OUT',
    );
    final checkInRemote = FirestoreRestService.decodeFields(
      (await rest.getDocument(
        'staff_attendance_events',
        checkInEventId,
        idToken: owner.idToken,
      ))['fields'],
    );
    final checkOutRemote = FirestoreRestService.decodeFields(
      (await rest.getDocument(
        'staff_attendance_events',
        checkOutEventId,
        idToken: owner.idToken,
      ))['fields'],
    );
    if (checkInRemote['eventType'] != 'CHECK_IN' ||
        checkOutRemote['eventType'] != 'CHECK_OUT' ||
        checkInRemote['immutable'] != true ||
        checkOutRemote['immutable'] != true) {
      throw StateError('Firestore REST returned different attendance events.');
    }
    final remoteStaffPurchase = FirestoreRestService.decodeFields(
      (await rest.getDocument(
        'staff_khata_transactions',
        staffPurchaseId,
        idToken: owner.idToken,
      ))['fields'],
    );
    if (remoteStaffPurchase['transactionType'] != 'STORE_PURCHASE' ||
        remoteStaffPurchase['employeeId'] != employeeId ||
        remoteStaffPurchase['amountPaise'] != 12500) {
      throw StateError('Firestore REST returned a different staff purchase.');
    }
    final pendingAfterPush = await source.db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox',
    );
    if ((pendingAfterPush.single['c'] as int) != 0) {
      throw StateError(
        'Confirmed REST write did not acknowledge its SQLite outbox batch.',
      );
    }

    var denied = false;
    try {
      await rest.getDocument(
        'employee_salary_profiles',
        profileId,
        idToken: other.idToken,
      );
    } on Exception {
      denied = true;
    }
    if (!denied) {
      throw StateError('Rules emulator allowed cross-owner salary read.');
    }
    denied = false;
    try {
      await rest.getDocument(
        'staff_attendance',
        attendanceId,
        idToken: other.idToken,
      );
    } on Exception {
      denied = true;
    }
    if (!denied) {
      throw StateError('Rules emulator allowed cross-owner attendance read.');
    }

    stdout.writeln(
      jsonEncode({
        'result': 'PASS',
        'mode': 'Firestore/Auth emulator over REST',
        'projectId': EnvironmentConfig.projectId,
        'salaryProfileId': profileId,
        'salaryPeriodId': periodId,
        'attendanceId': attendanceId,
        'attendanceEventsVerified': true,
        'staffPurchaseId': staffPurchaseId,
        'localOutboxAcknowledged': true,
        'ownerCanReadRemoteRecord': true,
        'otherUserDenied': denied,
        'productionTouched': false,
      }),
    );
  } finally {
    sync.dispose();
    await database.close();
    routedClient.close();
    await directory.delete(recursive: true);
  }
}
