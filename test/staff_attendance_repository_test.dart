import 'support/synthetic_face_verification.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/repositories/staff_attendance_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';

class _Data implements FirestoreDataService {
  _Data(this.store);
  final _Store store;

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async => store.docs.entries
      .where((e) => e.key.startsWith('$collection/'))
      .where((e) => filters.every((f) => e.value[f.field] == f.value))
      .map((e) => {'name': e.key, 'fields': e.value})
      .toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Store implements FirestoreTransactionService {
  final docs = <String, Map<String, dynamic>>{
    'employees/EMP': {
      'ownerUid': 'TEN',
      'status': 'ACTIVE',
      'businessIds': ['BUS'],
      'outletIds': ['OUT'],
    },
    'outlets/OUT': {'tenantId': 'TEN', 'businessId': 'BUS'},
  };

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    final staged = {
      for (final e in docs.entries) e.key: Map<String, dynamic>.from(e.value),
    };
    final value = await action(_View(staged));
    docs
      ..clear()
      ..addAll(staged);
    return value;
  }
}

class _View implements FirestoreTransactionContext {
  _View(this.docs);
  final Map<String, Map<String, dynamic>> docs;
  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final value = docs['$collection/$id'];
    return FirestoreTransactionDocument(
      exists: value != null,
      fields: value ?? const {},
    );
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async => docs.entries
      .where((e) => e.key.startsWith('$collection/'))
      .map((e) => e.value)
      .where((row) => filters.every((f) => row[f.field] == f.value))
      .map((row) => FirestoreTransactionDocument(exists: true, fields: row))
      .toList();
  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    final key = '$collection/$id';
    if (docs.containsKey(key)) throw StateError('duplicate $key');
    docs[key] = Map<String, dynamic>.from(fields);
  }

  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) {
    docs['$collection/$id'] = {...?docs['$collection/$id'], ...fields};
  }

  @override
  void delete(String collection, String id, {required String? updateTime}) =>
      docs.remove('$collection/$id');
}

void main() {
  test(
    'split outlet shifts combine before daily overtime threshold is applied',
    () {
      final overtime = StaffAttendanceRepository.calculateOvertimePaise([
        {
          'approvalStatus': 'APPROVED',
          'workDate': '2026-10-03T00:00:00.000Z',
          'attendanceStatus': 'PRESENT',
          'workedMinutes': 360,
          'standardShiftMinutes': 480,
          'overtimeRatePaisePerHour': 10000,
          'overtimeMultiplierBasisPoints': 15000,
        },
        {
          'approvalStatus': 'APPROVED',
          'workDate': '2026-10-03T00:00:00.000Z',
          'attendanceStatus': 'HALF_DAY',
          'workedMinutes': 240,
          'standardShiftMinutes': 480,
          'overtimeRatePaisePerHour': 10000,
          'overtimeMultiplierBasisPoints': 15000,
        },
      ]);
      expect(overtime, 30000);
    },
  );

  test('attendance is idempotent, approval calculates overtime, and approved rows cannot be overwritten', () async {
    final store = _Store();
    final repo = StaffAttendanceRepository(_Data(store), store);
    final date = DateTime.utc(2026, 10, 3);
    final id = await repo.recordManualAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: date,
      status: 'PRESENT',
      recordedBy: 'OWNER',
      checkIn: DateTime.utc(2026, 10, 3, 9),
      checkOut: DateTime.utc(2026, 10, 3, 19),
      token: 'token',
    );
    expect(
      await repo.recordManualAttendance(
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: date,
        status: 'PRESENT',
        recordedBy: 'OWNER',
        checkIn: DateTime.utc(2026, 10, 3, 9),
        checkOut: DateTime.utc(2026, 10, 3, 19),
        token: 'token',
      ),
      id,
    );
    await repo.approveAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      attendanceId: id,
      approvedBy: 'OWNER',
      standardShiftMinutes: 480,
      overtimeRatePaisePerHour: 10000,
      overtimeMultiplierBasisPoints: 15000,
      token: 'token',
    );
    final row = store.docs['staff_attendance/$id']!;
    expect(row['approvalStatus'], 'APPROVED');
    expect(row['payableUnitsMilli'], 1000);
    expect(row['approvedOvertimeMinutes'], 120);
    expect(row['overtimePaise'], 30000);
    await expectLater(
      repo.recordManualAttendance(
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: date,
        status: 'ABSENT',
        recordedBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('paid leave and half days produce explicit payable units; invalid check-out is rejected', () async {
    final store = _Store();
    final repo = StaffAttendanceRepository(_Data(store), store);
    final halfDay = await repo.recordManualAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: DateTime.utc(2026, 10, 4),
      status: 'HALF_DAY',
      recordedBy: 'OWNER',
      token: 'token',
    );
    final paidLeave = await repo.recordManualAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: DateTime.utc(2026, 10, 5),
      status: 'PAID_LEAVE',
      recordedBy: 'OWNER',
      token: 'token',
    );
    await repo.approveAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      attendanceId: halfDay,
      approvedBy: 'OWNER',
      token: 'token',
    );
    await repo.approveAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      attendanceId: paidLeave,
      approvedBy: 'OWNER',
      token: 'token',
    );
    expect(store.docs['staff_attendance/$halfDay']!['payableUnitsMilli'], 500);
    expect(
      store.docs['staff_attendance/$paidLeave']!['payableUnitsMilli'],
      1000,
    );
    await expectLater(
      repo.recordManualAttendance(
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: DateTime.utc(2026, 10, 6),
        status: 'PRESENT',
        recordedBy: 'OWNER',
        checkIn: DateTime.utc(2026, 10, 6, 18),
        checkOut: DateTime.utc(2026, 10, 6, 9),
        token: 'token',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('face kiosk check-in/out creates immutable idempotent events and pending payroll attendance', () async {
    final store = _Store();
    var eventClock = DateTime.utc(2026, 10, 20, 9);
    final repo = StaffAttendanceRepository(
      _Data(store),
      store,
      clock: () => eventClock,
    );
    final date = DateTime.utc(2026, 10, 20);
    final checkInAt = DateTime.utc(2026, 10, 20, 9);
    final checkOutAt = DateTime.utc(2026, 10, 20, 18);
    final rowId = await repo.recordFaceCheckIn(
      verification: await syntheticFaceVerification(
        at: checkInAt,
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        deviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
      ),
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: date,
      occurredAt: checkInAt,
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'KIOSK-1',
      modelVersion: 'MODEL-TEST',
      livenessVersion: 'PAD-TEST',
      recordedBy: 'OWNER',
      token: 'token',
    );
    expect(store.docs['staff_attendance/$rowId']!['approvalStatus'], 'PENDING');
    expect(
      store.docs['staff_attendance/$rowId']!['attendanceMethod'],
      'FACE_KIOSK',
    );
    expect(
      store.docs.keys.where(
        (key) => key.startsWith('staff_attendance_events/'),
      ),
      hasLength(1),
    );
    await expectLater(
      repo.recordFaceCheckIn(
        verification: await syntheticFaceVerification(
          at: checkInAt,
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          deviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
        ),
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: date,
        occurredAt: checkInAt,
        timeZoneId: 'Asia/Kolkata',
        kioskDeviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
        recordedBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      repo.recordFaceCheckIn(
        verification: await syntheticFaceVerification(
          at: DateTime.utc(2026, 10, 21, 9),
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          deviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
        ),
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: DateTime.utc(2026, 10, 21),
        occurredAt: DateTime.utc(2026, 10, 21, 9),
        timeZoneId: 'Asia/Kolkata',
        kioskDeviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
        recordedBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<Exception>()),
    );
    eventClock = checkOutAt;
    await repo.recordFaceCheckOut(
      verification: await syntheticFaceVerification(
        at: checkOutAt,
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        deviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
      ),
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: date,
      occurredAt: checkOutAt,
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'KIOSK-1',
      modelVersion: 'MODEL-TEST',
      livenessVersion: 'PAD-TEST',
      recordedBy: 'OWNER',
      token: 'token',
    );
    final row = store.docs['staff_attendance/$rowId']!;
    expect(row['workedMinutes'], 540);
    expect(row['approvalStatus'], 'PENDING');
    expect(
      store.docs.keys.where(
        (key) => key.startsWith('staff_attendance_events/'),
      ),
      hasLength(2),
    );
    await expectLater(
      repo.recordFaceCheckOut(
        verification: await syntheticFaceVerification(
          at: DateTime.utc(2026, 10, 20, 18, 1),
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          deviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
        ),
        tenantId: 'TEN',
        businessId: 'BUS',
        outletId: 'OUT',
        employeeId: 'EMP',
        workDate: date,
        occurredAt: DateTime.utc(2026, 10, 20, 18, 1),
        timeZoneId: 'Asia/Kolkata',
        kioskDeviceId: 'KIOSK-1',
        modelVersion: 'MODEL-TEST',
        livenessVersion: 'PAD-TEST',
        recordedBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('listAttendance returns attendance records matching business and date range', () async {
    final store = _Store();
    final repo = StaffAttendanceRepository(_Data(store), store);
    final date = DateTime.utc(2026, 10, 21);
    await repo.recordManualAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      outletId: 'OUT',
      employeeId: 'EMP',
      workDate: date,
      status: 'PRESENT',
      recordedBy: 'OWNER',
      checkIn: DateTime.utc(2026, 10, 21, 9),
      token: 'token',
    );

    final rows = await repo.listAttendance(
      tenantId: 'TEN',
      businessId: 'BUS',
      from: DateTime(2026, 10, 1),
      through: DateTime(2026, 10, 31, 23, 59, 59),
      outletId: null,
      token: 'token',
    );
    expect(rows, hasLength(1));
    expect(rows.first['approvalStatus'], 'PENDING');
    expect(rows.first['employeeId'], 'EMP');
  });

  test(
    'model and PAD version labels alone cannot record face attendance',
    () async {
      final store = _Store();
      final repo = StaffAttendanceRepository(_Data(store), store);
      final before = store.docs.length;
      await expectLater(
        repo.recordFaceCheckIn(
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          workDate: DateTime.utc(2026, 10, 21),
          occurredAt: DateTime.now(),
          timeZoneId: 'Asia/Kolkata',
          kioskDeviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
          recordedBy: 'OWNER',
          token: 'fixture',
        ),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('identity and liveness'),
          ),
        ),
      );
      expect(store.docs.length, before);
    },
  );

  test(
    'verified checkout needs an open session and inactive staff are rejected',
    () async {
      final store = _Store();
      final at = DateTime.utc(2026, 10, 21, 9);
      final repo = StaffAttendanceRepository(
        _Data(store),
        store,
        clock: () => at,
      );
      await expectLater(
        repo.recordFaceCheckOut(
          verification: await syntheticFaceVerification(at: at),
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          workDate: at,
          occurredAt: at,
          timeZoneId: 'Asia/Kolkata',
          kioskDeviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
          recordedBy: 'OWNER',
          token: 'fixture',
        ),
        throwsA(
          predicate(
            (Object e) => e.toString().contains('no open attendance session'),
          ),
        ),
      );
      store.docs['employees/EMP']!['status'] = 'INACTIVE';
      await expectLater(
        repo.recordFaceCheckIn(
          verification: await syntheticFaceVerification(at: at),
          tenantId: 'TEN',
          businessId: 'BUS',
          outletId: 'OUT',
          employeeId: 'EMP',
          workDate: at,
          occurredAt: at,
          timeZoneId: 'Asia/Kolkata',
          kioskDeviceId: 'KIOSK-1',
          modelVersion: 'MODEL-TEST',
          livenessVersion: 'PAD-TEST',
          recordedBy: 'OWNER',
          token: 'fixture',
        ),
        throwsA(predicate((Object e) => e.toString().contains('not assigned'))),
      );
      expect(
        store.docs.keys.where((k) => k.startsWith('staff_attendance')),
        isEmpty,
      );
    },
  );

  test(
    'overnight face checkout closes the original workday and cannot reopen it',
    () async {
      final store = _Store();
      var time = DateTime.utc(2026, 10, 21, 18);
      final workday = DateTime.utc(2026, 10, 21);
      final repo = StaffAttendanceRepository(
        _Data(store),
        store,
        clock: () => time,
      );
      Future<String> record(bool out) async {
        final proof = await syntheticFaceVerification(at: time);
        return out
            ? repo.recordFaceCheckOut(
                verification: proof,
                tenantId: 'TEN',
                businessId: 'BUS',
                outletId: 'OUT',
                employeeId: 'EMP',
                workDate: workday,
                occurredAt: time,
                timeZoneId: 'Asia/Kolkata',
                kioskDeviceId: 'KIOSK-1',
                modelVersion: 'MODEL-TEST',
                livenessVersion: 'PAD-TEST',
                recordedBy: 'OWNER',
                token: 'fixture',
              )
            : repo.recordFaceCheckIn(
                verification: proof,
                tenantId: 'TEN',
                businessId: 'BUS',
                outletId: 'OUT',
                employeeId: 'EMP',
                workDate: workday,
                occurredAt: time,
                timeZoneId: 'Asia/Kolkata',
                kioskDeviceId: 'KIOSK-1',
                modelVersion: 'MODEL-TEST',
                livenessVersion: 'PAD-TEST',
                recordedBy: 'OWNER',
                token: 'fixture',
              );
      }

      final id = await record(false);
      time = time.add(const Duration(hours: 9));
      expect(await record(true), id);
      expect(store.docs['staff_attendance/$id']!['workedMinutes'], 540);
      expect(store.docs['staff_attendance/$id']!['approvalStatus'], 'PENDING');
      await expectLater(
        record(true),
        throwsA(
          predicate((Object e) => e.toString().contains('already checked out')),
        ),
      );
      expect(
        store.docs.keys.where((k) => k.startsWith('staff_attendance_events/')),
        hasLength(2),
      );
    },
  );
}
