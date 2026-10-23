import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/offline_face_recognition.dart';

/// Manual, approval-based attendance stored through the existing SQLite
/// document cache and durable Firestore REST outbox.
class StaffAttendanceRepository {
  StaffAttendanceRepository(
    this.firestore,
    this.writes, {
    this.clock = DateTime.now,
  });

  final FirestoreDataService firestore;
  final FirestoreTransactionService writes;
  final DateTime Function() clock;

  static const statuses = {
    'PRESENT',
    'ABSENT',
    'HALF_DAY',
    'PAID_LEAVE',
    'UNPAID_LEAVE',
    'WEEKLY_OFF',
    'HOLIDAY',
  };

  static String _id(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(normalized)) {
      throw const AppException('A valid attendance identity is required.');
    }
    return normalized;
  }

  static bool _outletBelongsToTenant(
    Map<String, dynamic> fields,
    String tenantId,
  ) => (fields['tenantId'] ?? fields['ownerUid']) == tenantId;

  static String _dateKey(DateTime date) =>
      '${date.toUtc().year.toString().padLeft(4, '0')}'
      '${date.toUtc().month.toString().padLeft(2, '0')}'
      '${date.toUtc().day.toString().padLeft(2, '0')}';

  static String attendanceId({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required String outletId,
    required DateTime date,
  }) =>
      'ATT-${sha256.convert(utf8.encode([tenantId, businessId, employeeId, outletId, _dateKey(date)].join('|'))).toString().substring(0, 40)}';

  static String attendanceEventId({
    required String attendanceId,
    required String eventType,
  }) =>
      'ATTEVT-${sha256.convert(utf8.encode('$attendanceId|$eventType')).toString().substring(0, 40)}';

  /// Recombines approved shift fragments across outlets before applying the
  /// daily overtime threshold, so split shifts cannot hide overtime.
  static int calculateOvertimePaise(List<Map<String, dynamic>> rows) {
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final row in rows.where((r) => r['approvalStatus'] == 'APPROVED')) {
      final date = DateTime.tryParse(row['workDate']?.toString() ?? '');
      if (date == null) continue;
      byDay.putIfAbsent(_dateKey(date), () => []).add(row);
    }
    var total = 0;
    for (final entries in byDay.values) {
      final first = entries.first;
      final shift = (first['standardShiftMinutes'] as num?)?.toInt() ?? 480;
      final rate = (first['overtimeRatePaisePerHour'] as num?)?.toInt() ?? 0;
      final multiplier =
          (first['overtimeMultiplierBasisPoints'] as num?)?.toInt() ?? 10000;
      if (entries.any(
        (row) =>
            ((row['standardShiftMinutes'] as num?)?.toInt() ?? 480) != shift ||
            ((row['overtimeRatePaisePerHour'] as num?)?.toInt() ?? 0) != rate ||
            ((row['overtimeMultiplierBasisPoints'] as num?)?.toInt() ??
                    10000) !=
                multiplier,
      )) {
        throw const AppException(
          'Attendance rows for one date have different overtime policies.',
        );
      }
      final worked = entries.fold<int>(0, (sum, row) {
        final status = row['attendanceStatus'];
        final counts =
            status == 'PRESENT' ||
            status == 'HALF_DAY' ||
            ((status == 'WEEKLY_OFF' || status == 'HOLIDAY') &&
                row['includeOffDayAsPaidWork'] == true);
        return counts
            ? sum + ((row['workedMinutes'] as num?)?.toInt() ?? 0)
            : sum;
      });
      final overtimeMinutes = (worked - shift).clamp(0, 1 << 30);
      total += (rate * overtimeMinutes * multiplier + 300000) ~/ 600000;
    }
    return total;
  }

  Future<String> recordManualAttendance({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required DateTime workDate,
    required String status,
    required String recordedBy,
    DateTime? checkIn,
    DateTime? checkOut,
    bool includeOffDayAsPaidWork = false,
    String? notes,
    String? earlyCheckoutReason,
    String? attendanceMethod,
    double? latitude,
    double? longitude,
    double? gpsAccuracy,
    bool? isMockLocation,
    double? geofenceDistanceMeters,
    double? geofenceRadiusMeters,
    List<String>? livenessChallenges,
    List<String>? fraudFlags,
    String? verificationStatus,
    String? kioskDeviceId,
    required String token,
  }) async {
    final tenant = _id(tenantId),
        business = _id(businessId),
        outlet = _id(outletId),
        employeeIdSafe = _id(employeeId);
    if (!statuses.contains(status)) {
      throw const AppException('Select a valid attendance status.');
    }
    if (checkIn != null && checkOut != null && !checkOut.isAfter(checkIn)) {
      throw const AppException('Check-out must be later than check-in.');
    }
    final cleanedEarlyReason = earlyCheckoutReason?.trim() ?? '';
    if (checkOut != null &&
        checkIn != null &&
        checkOut.isBefore(checkIn.add(const Duration(minutes: 480))) &&
        cleanedEarlyReason.isEmpty) {
      throw const AppException(
        'Enter a reason for checking out before the standard 8-hour shift ends.',
      );
    }
    final date = DateTime.utc(workDate.year, workDate.month, workDate.day);
    final recordId = attendanceId(
      tenantId: tenant,
      businessId: business,
      employeeId: employeeIdSafe,
      outletId: outlet,
      date: date,
    );
    await writes.runAtomicOperation((tx) async {
      final emp = await tx.get(FirebaseConstants.employees, employeeIdSafe);
      final outletDoc = await tx.get(FirebaseConstants.outlets, outlet);
      if (!emp.exists || emp.fields['ownerUid'] != tenant) {
        throw const AppException(
          'The selected employee record was not found for this business owner.',
        );
      }
      if (!(emp.fields['businessIds'] as List? ?? const []).contains(
        business,
      )) {
        throw const AppException(
          'The selected employee is not assigned to this business. Update the employee’s business access and sync again.',
        );
      }
      if (!(emp.fields['outletIds'] as List? ?? const []).contains(outlet)) {
        throw const AppException(
          'The selected employee is not assigned to this outlet. Update the employee’s outlet access and sync again.',
        );
      }
      if (!outletDoc.exists ||
          !_outletBelongsToTenant(outletDoc.fields, tenant) ||
          outletDoc.fields['businessId'] != business) {
        throw const AppException(
          'The selected outlet does not belong to this business owner and business.',
        );
      }
      final existing = await tx.get(
        FirebaseConstants.staffAttendance,
        recordId,
      );
      final existingCheckIn = DateTime.tryParse(
        existing.fields['checkInAt']?.toString() ?? '',
      );
      final existingCheckOut = DateTime.tryParse(
        existing.fields['checkOutAt']?.toString() ?? '',
      );
      if (existing.exists) {
        final sameCheckIn =
            checkIn != null &&
            existingCheckIn != null &&
            checkIn.toUtc().isAtSameMomentAs(existingCheckIn.toUtc());
        final sameCheckOut =
            checkOut != null &&
            existingCheckOut != null &&
            checkOut.toUtc().isAtSameMomentAs(existingCheckOut.toUtc());
        if (existingCheckOut != null) {
          if (sameCheckIn && sameCheckOut) {
            return;
          }
          throw const AppException(
            'Attendance and checkout are already recorded for this employee today.',
          );
        }
        if (existingCheckIn == null) {
          throw const AppException(
            'Attendance is already recorded for this employee today.',
          );
        }
        if (checkOut == null) {
          throw const AppException(
            'Attendance is already recorded. Only one checkout can be added after check-in.',
          );
        }
        if (checkIn != null &&
            !checkIn.toUtc().isAtSameMomentAs(existingCheckIn.toUtc())) {
          throw const AppException(
            'Check-in is already recorded and cannot be changed.',
          );
        }
      } else if (checkOut != null && checkIn == null) {
        throw const AppException('Check in before checking out.');
      }
      if (existing.exists && existing.fields['approvalStatus'] == 'APPROVED') {
        throw const AppException(
          'Approved attendance requires an authorized correction.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final effectiveCheckIn = existingCheckIn ?? checkIn;
      if (checkOut != null &&
          effectiveCheckIn != null &&
          checkOut.isBefore(
            effectiveCheckIn.add(const Duration(minutes: 480)),
          ) &&
          cleanedEarlyReason.isEmpty) {
        throw const AppException(
          'Enter a reason for checking out before the standard 8-hour shift ends.',
        );
      }
      final payload = {
        'attendanceId': recordId,
        'recordId': recordId,
        'tenantId': tenant,
        'businessId': business,
        'outletId': outlet,
        'employeeId': employeeIdSafe,
        'workDate': date.toIso8601String(),
        'attendanceStatus': existing.exists
            ? existing.fields['attendanceStatus'] ?? status
            : status,
        'includeOffDayAsPaidWork': existing.exists
            ? existing.fields['includeOffDayAsPaidWork'] == true
            : includeOffDayAsPaidWork,
        'checkInAt': effectiveCheckIn?.toUtc().toIso8601String(),
        'checkOutAt': checkOut?.toUtc().toIso8601String(),
        'workedMinutes': effectiveCheckIn != null && checkOut != null
            ? checkOut.difference(effectiveCheckIn).inMinutes
            : 0,
        'earlyCheckoutReason': cleanedEarlyReason.isEmpty
            ? (existing.fields['earlyCheckoutReason'] as String?)
            : cleanedEarlyReason,
        'approvalStatus': 'PENDING',
        'notes': existing.exists ? existing.fields['notes'] : notes?.trim(),
        'recordedBy': existing.exists
            ? existing.fields['recordedBy'] ?? recordedBy
            : recordedBy,
        'checkOutRecordedBy': checkOut == null
            ? existing.fields['checkOutRecordedBy']
            : recordedBy,
        'attendanceMethod': existing.exists
            ? existing.fields['attendanceMethod'] ?? attendanceMethod ?? 'MANUAL'
            : attendanceMethod ?? 'MANUAL',
        if (latitude != null) 'gpsLatitude': latitude,
        if (longitude != null) 'gpsLongitude': longitude,
        if (gpsAccuracy != null) 'gpsAccuracy': gpsAccuracy,
        if (isMockLocation != null) 'isMockLocation': isMockLocation,
        if (geofenceDistanceMeters != null)
          'geofenceDistanceMeters': geofenceDistanceMeters,
        if (geofenceRadiusMeters != null)
          'geofenceRadiusMeters': geofenceRadiusMeters,
        if (livenessChallenges != null)
          'livenessChallenges': livenessChallenges,
        if (fraudFlags != null) 'fraudFlags': fraudFlags,
        if (verificationStatus != null) 'verificationStatus': verificationStatus,
        if (fraudFlags != null && fraudFlags.isNotEmpty)
          'requiresManagerReview': true,
        if (kioskDeviceId != null) 'kioskDeviceId': kioskDeviceId,
        'createdAt': existing.exists ? existing.fields['createdAt'] : now,
        'updatedAt': now,
      };
      if (existing.exists) {
        tx.update(
          FirebaseConstants.staffAttendance,
          recordId,
          payload,
          updateTime: existing.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.staffAttendance, recordId, payload);
      }
      if (attendanceMethod != null) {
        final eventType = checkOut != null ? 'CHECK_OUT' : 'CHECK_IN';
        final eventId = attendanceEventId(
          attendanceId: recordId,
          eventType: eventType,
        );
        tx.create(FirebaseConstants.staffAttendanceEvents, eventId, {
          'eventId': eventId,
          'recordId': recordId,
          'tenantId': tenant,
          'businessId': business,
          'outletId': outlet,
          'employeeId': employeeIdSafe,
          'eventType': eventType,
          'occurredAt': (checkOut ?? effectiveCheckIn ?? DateTime.now()).toUtc().toIso8601String(),
          'workDate': date.toIso8601String(),
          'attendanceMethod': attendanceMethod,
          'kioskDeviceId': kioskDeviceId ?? 'unknown',
          'gpsLatitude': latitude,
          'gpsLongitude': longitude,
          'gpsAccuracy': gpsAccuracy,
          'isMockLocation': isMockLocation ?? false,
          'geofenceDistanceMeters': geofenceDistanceMeters,
          'geofenceRadiusMeters': geofenceRadiusMeters,
          'livenessChallenges': livenessChallenges ?? const [],
          'verificationStatus': verificationStatus ??
              (fraudFlags != null && fraudFlags.isNotEmpty
                  ? 'FLAGGED_FOR_REVIEW'
                  : 'VERIFIED'),
          'flaggedReasons': fraudFlags ?? const [],
          'recordedBy': recordedBy,
          'createdAt': now,
          'immutable': true,
        });
      }
    }, idToken: token);
    return recordId;
  }

  /// Adds a face-kiosk check-in event and updates the Phase 2 daily attendance
  /// record in the same SQLite/outbox transaction. The camera/matcher must
  /// already have returned a unique, accepted identity and liveness result.
  Future<String> recordFaceCheckIn({
    FaceAttendanceVerification? verification,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
    required String recordedBy,
    required String token,
  }) => _recordFaceKioskEvent(
    verification: verification,
    eventType: 'CHECK_IN',
    tenantId: tenantId,
    businessId: businessId,
    outletId: outletId,
    employeeId: employeeId,
    workDate: workDate,
    occurredAt: occurredAt,
    timeZoneId: timeZoneId,
    kioskDeviceId: kioskDeviceId,
    modelVersion: modelVersion,
    livenessVersion: livenessVersion,
    recordedBy: recordedBy,
    token: token,
  );

  /// Adds a face-kiosk check-out event and closes the same pending daily row.
  /// It rejects missing, already-closed, reversed, and implausibly long shifts.
  Future<String> recordFaceCheckOut({
    FaceAttendanceVerification? verification,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
    required String recordedBy,
    required String token,
  }) => _recordFaceKioskEvent(
    verification: verification,
    eventType: 'CHECK_OUT',
    tenantId: tenantId,
    businessId: businessId,
    outletId: outletId,
    employeeId: employeeId,
    workDate: workDate,
    occurredAt: occurredAt,
    timeZoneId: timeZoneId,
    kioskDeviceId: kioskDeviceId,
    modelVersion: modelVersion,
    livenessVersion: livenessVersion,
    recordedBy: recordedBy,
    token: token,
  );

  Future<String> _recordFaceKioskEvent({
    required FaceAttendanceVerification? verification,
    required String eventType,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
    required String recordedBy,
    required String token,
  }) async {
    final tenant = _id(tenantId),
        business = _id(businessId),
        outlet = _id(outletId),
        employee = _id(employeeId),
        device = _id(kioskDeviceId);
    if (!{'CHECK_IN', 'CHECK_OUT'}.contains(eventType) ||
        timeZoneId.trim().isEmpty ||
        modelVersion.trim().isEmpty ||
        livenessVersion.trim().isEmpty) {
      throw const AppException('Face attendance verification is unavailable.');
    }
    final date = DateTime.utc(workDate.year, workDate.month, workDate.day);
    final recordId = attendanceId(
      tenantId: tenant,
      businessId: business,
      employeeId: employee,
      outletId: outlet,
      date: date,
    );
    final eventId = attendanceEventId(
      attendanceId: recordId,
      eventType: eventType,
    );
    final eventAt = occurredAt.toUtc();
    if (verification == null) {
      throw const AppException(
        'Validated identity and liveness evidence is required. Use manual attendance.',
      );
    }
    verification.consume(
      tenantId: tenant,
      businessId: business,
      outletId: outlet,
      employeeId: employee,
      deviceId: device,
      modelVersion: modelVersion,
      livenessVersion: livenessVersion,
      occurredAt: eventAt,
      now: clock(),
    );
    await writes.runAtomicOperation((tx) async {
      final employeeDoc = await tx.get(FirebaseConstants.employees, employee);
      final outletDoc = await tx.get(FirebaseConstants.outlets, outlet);
      if (!employeeDoc.exists ||
          employeeDoc.fields['ownerUid'] != tenant ||
          employeeDoc.fields['status']?.toString().toLowerCase() != 'active' ||
          !(employeeDoc.fields['businessIds'] as List? ?? const []).contains(
            business,
          ) ||
          !(employeeDoc.fields['outletIds'] as List? ?? const []).contains(
            outlet,
          ) ||
          !outletDoc.exists ||
          !_outletBelongsToTenant(outletDoc.fields, tenant) ||
          outletDoc.fields['businessId'] != business) {
        throw const AppException(
          'Employee is not assigned to this business and outlet.',
        );
      }
      final existingEvent = await tx.get(
        FirebaseConstants.staffAttendanceEvents,
        eventId,
      );
      if (existingEvent.exists) {
        throw AppException(
          eventType == 'CHECK_IN'
              ? 'This employee is already checked in for this workday.'
              : 'This employee is already checked out for this workday.',
        );
      }
      final current = await tx.get(FirebaseConstants.staffAttendance, recordId);
      final currentCheckIn = DateTime.tryParse(
        current.fields['checkInAt']?.toString() ?? '',
      );
      final currentCheckOut = DateTime.tryParse(
        current.fields['checkOutAt']?.toString() ?? '',
      );
      if (current.exists && current.fields['approvalStatus'] == 'APPROVED') {
        throw const AppException(
          'Approved attendance requires an authorized correction.',
        );
      }
      if (eventType == 'CHECK_IN') {
        final attendanceRows = await tx.query(
          FirebaseConstants.staffAttendance,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenant),
            FirestoreFilter('businessId', 'EQUAL', business),
            FirestoreFilter('employeeId', 'EQUAL', employee),
          ],
        );
        final hasOtherOpenSession = attendanceRows.any((row) {
          final fields = row.fields;
          return fields['attendanceId'] != recordId &&
              fields['checkInAt'] != null &&
              fields['checkOutAt'] == null;
        });
        if (hasOtherOpenSession) {
          throw const AppException(
            'This employee has an open attendance session that must be closed first.',
          );
        }
      }
      if (eventType == 'CHECK_IN' &&
          (currentCheckIn != null || currentCheckOut != null)) {
        throw const AppException(
          'An attendance session already exists for this workday.',
        );
      }
      if (eventType == 'CHECK_OUT' &&
          (currentCheckIn == null || currentCheckOut != null)) {
        throw const AppException(
          'There is no open attendance session to check out.',
        );
      }
      if (eventType == 'CHECK_OUT') {
        final minutes = eventAt.difference(currentCheckIn!.toUtc()).inMinutes;
        if (minutes <= 0 || minutes > 24 * 60) {
          throw const AppException(
            'Check-out time is invalid. Ask an authorized manager for help.',
          );
        }
      }

      final now = DateTime.now().toUtc().toIso8601String();
      final dailyFields = <String, dynamic>{
        'attendanceId': recordId,
        'recordId': recordId,
        'tenantId': tenant,
        'businessId': business,
        'outletId': outlet,
        'employeeId': employee,
        'workDate': date.toIso8601String(),
        'workTimeZoneId': timeZoneId,
        'attendanceStatus': 'PRESENT',
        'approvalStatus': 'PENDING',
        'attendanceMethod': 'FACE_KIOSK',
        'kioskDeviceId': device,
        'recognitionModelVersion': modelVersion,
        'livenessCheckVersion': livenessVersion,
        'recordedBy': recordedBy,
        'createdAt': current.exists ? current.fields['createdAt'] : now,
        'updatedAt': now,
        if (eventType == 'CHECK_IN') ...{
          'checkInAt': eventAt.toIso8601String(),
          'checkInEventId': eventId,
          'checkOutAt': null,
          'checkOutEventId': null,
          'workedMinutes': 0,
        } else ...{
          'checkOutAt': eventAt.toIso8601String(),
          'checkOutEventId': eventId,
          'workedMinutes': eventAt
              .difference(currentCheckIn!.toUtc())
              .inMinutes,
        },
      };
      if (current.exists) {
        tx.update(
          FirebaseConstants.staffAttendance,
          recordId,
          dailyFields,
          updateTime: current.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.staffAttendance, recordId, dailyFields);
      }
      tx.create(FirebaseConstants.staffAttendanceEvents, eventId, {
        'eventId': eventId,
        'recordId': recordId,
        'tenantId': tenant,
        'businessId': business,
        'outletId': outlet,
        'employeeId': employee,
        'eventType': eventType,
        'occurredAt': eventAt.toIso8601String(),
        'workDate': date.toIso8601String(),
        'workTimeZoneId': timeZoneId,
        'attendanceMethod': 'FACE_KIOSK',
        'kioskDeviceId': device,
        'recognitionModelVersion': modelVersion,
        'livenessCheckVersion': livenessVersion,
        'recordedBy': recordedBy,
        'createdAt': now,
        'immutable': true,
      });
    }, idToken: token);
    return recordId;
  }

  Future<void> approveAttendance({
    required String tenantId,
    required String businessId,
    required String attendanceId,
    required String approvedBy,
    int standardShiftMinutes = 480,
    int halfDayPayableUnitsMilli = 500,
    int? overtimeRatePaisePerHour,
    int overtimeMultiplierBasisPoints = 10000,
    required String token,
  }) async {
    if (standardShiftMinutes <= 0 ||
        halfDayPayableUnitsMilli < 0 ||
        halfDayPayableUnitsMilli > 1000 ||
        overtimeMultiplierBasisPoints <= 0 ||
        (overtimeRatePaisePerHour != null && overtimeRatePaisePerHour < 0)) {
      throw const AppException('Attendance wage settings are invalid.');
    }
    await writes.runAtomicOperation((tx) async {
      final record = await tx.get(
        FirebaseConstants.staffAttendance,
        _id(attendanceId),
      );
      if (!record.exists ||
          record.fields['tenantId'] != tenantId ||
          record.fields['businessId'] != businessId) {
        throw const AppException(
          'Attendance record is unavailable in this business.',
        );
      }
      if (record.fields['approvalStatus'] == 'APPROVED') return;
      final employee = await tx.get(
        FirebaseConstants.employees,
        record.fields['employeeId']?.toString() ?? '',
      );
      final outlet = await tx.get(
        FirebaseConstants.outlets,
        record.fields['outletId']?.toString() ?? '',
      );
      if (!employee.exists ||
          employee.fields['ownerUid'] != tenantId ||
          !(employee.fields['businessIds'] as List? ?? const []).contains(
            businessId,
          ) ||
          !(employee.fields['outletIds'] as List? ?? const []).contains(
            record.fields['outletId'],
          ) ||
          !outlet.exists ||
          !_outletBelongsToTenant(outlet.fields, tenantId) ||
          outlet.fields['businessId'] != businessId) {
        throw const AppException(
          'Attendance employee or outlet scope is invalid.',
        );
      }
      final status = record.fields['attendanceStatus']?.toString() ?? '';
      if (!statuses.contains(status)) {
        throw const AppException('Attendance status is invalid.');
      }
      final minutes = (record.fields['workedMinutes'] as num?)?.toInt() ?? 0;
      final includeOffDay = record.fields['includeOffDayAsPaidWork'] == true;
      final workUnits = switch (status) {
        'PRESENT' || 'PAID_LEAVE' => 1000,
        'WEEKLY_OFF' || 'HOLIDAY' when includeOffDay => 1000,
        'HALF_DAY' => halfDayPayableUnitsMilli,
        _ => 0,
      };
      final countsAsWork = status == 'PRESENT' || includeOffDay;
      final approvedOvertimeMinutes =
          countsAsWork && minutes > standardShiftMinutes
          ? minutes - standardShiftMinutes
          : 0;
      final overtime = overtimeRatePaisePerHour == null
          ? 0
          : (overtimeRatePaisePerHour *
                        approvedOvertimeMinutes *
                        overtimeMultiplierBasisPoints +
                    300000) ~/
                600000;
      final now = DateTime.now().toUtc().toIso8601String();
      tx.update(FirebaseConstants.staffAttendance, attendanceId, {
        'approvalStatus': 'APPROVED',
        'payableUnitsMilli': workUnits,
        'halfDayPayableUnitsMilli': halfDayPayableUnitsMilli,
        'standardShiftMinutes': standardShiftMinutes,
        'approvedOvertimeMinutes': approvedOvertimeMinutes,
        'overtimeRatePaisePerHour': overtimeRatePaisePerHour,
        'overtimeMultiplierBasisPoints': overtimeMultiplierBasisPoints,
        'overtimePaise': overtime,
        'approvedBy': approvedBy,
        'approvedAt': now,
        'updatedAt': now,
      }, updateTime: record.updateTime);
    }, idToken: token);
  }

  Future<List<Map<String, dynamic>>> listAttendance({
    required String tenantId,
    required String businessId,
    required DateTime from,
    required DateTime through,
    String? employeeId,
    String? outletId,
    String? token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.staffAttendance,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (employeeId != null)
          FirestoreFilter('employeeId', 'EQUAL', employeeId),
        if (outletId != null) FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    return docs
        .map((doc) => FirestoreRestServiceFields.decode(doc['fields']))
        .where((row) {
          final date = DateTime.tryParse(row['workDate']?.toString() ?? '');
          return date != null && !date.isBefore(from) && !date.isAfter(through);
        })
        .toList()
      ..sort(
        (a, b) => (a['workDate']?.toString() ?? '')
            .compareTo(b['workDate']?.toString() ?? ''),
      );
  }
}

// Kept local to this repository to avoid coupling a data repository to REST
// transport details in call sites.
class FirestoreRestServiceFields {
  static Map<String, dynamic> decode(dynamic fields) =>
      FirestoreRestService.decodeFields(fields);
}
