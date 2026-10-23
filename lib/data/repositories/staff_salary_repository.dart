import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../local/local_data_source.dart';
import '../models/financial_transaction_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/firestore_value_codec.dart';
import '../services/offline_firestore_service.dart';
import 'staff_attendance_repository.dart';

/// Phase 1 salary records. Every write is staged through the existing local
/// transaction/outbox and reaches Firestore as one atomic repository batch.
class StaffSalaryRepository {
  StaffSalaryRepository(this.firestore, this.atomicWrites);

  final FirestoreDataService firestore;
  final FirestoreTransactionService atomicWrites;

  /// Authoritative server transaction runner for online-only financial operations.
  FirestoreTransactionService get serverTransactions {
    final aw = atomicWrites;
    if (aw is OfflineFirestoreService) {
      return aw.serverTransactions;
    }
    final fs = firestore;
    if (fs is OfflineFirestoreService) {
      return fs.serverTransactions;
    }
    return atomicWrites;
  }

  LocalDataSource? get _localSource {
    final aw = atomicWrites;
    if (aw is OfflineFirestoreService) {
      return aw.localDataSource;
    }
    final fs = firestore;
    if (fs is OfflineFirestoreService) {
      return fs.localDataSource;
    }
    return null;
  }

  Future<void> _updateLocalCache(
    List<({String collection, String id, Map<String, dynamic> fields})> entries,
  ) async {
    final local = _localSource;
    if (local == null) return;
    try {
      await local.db.transaction((localTx) async {
        for (final entry in entries) {
          await LocalDataSource.put(localTx, entry.collection, {
            'remoteId': entry.id,
            'payloadJson': jsonEncode(
              FirestoreValueCodec.encodeFields(entry.fields),
            ),
            ...LocalDataSource.scopeColumns(entry.fields),
            'syncStatus': 'SYNCED',
            'localUpdatedAt': LocalDataSource.now(),
            'isDeleted': 0,
          });
        }
      });
    } catch (e) {
      debugPrint('Failed to update local cache: $e');
    }
  }

  static const allocationTotalBasisPoints = 10000;

  static String _dateKey(DateTime value) =>
      '${value.toUtc().year.toString().padLeft(4, '0')}'
      '${value.toUtc().month.toString().padLeft(2, '0')}'
      '${value.toUtc().day.toString().padLeft(2, '0')}';

  static String _safeId(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(normalized)) {
      throw const AppException('A valid employee or request ID is required.');
    }
    return normalized;
  }

  static String _scopedId(String prefix, List<String> components) =>
      '$prefix-${sha256.convert(utf8.encode(components.join('|'))).toString().substring(0, 40)}';

  static void _scope(
    Map<String, dynamic> fields, {
    required String tenantId,
    required String businessId,
    required String employeeId,
  }) {
    final docTenant = fields['tenantId'] ?? fields['ownerUid'];
    if (docTenant != tenantId ||
        fields['businessId'] != businessId ||
        fields['employeeId'] != employeeId) {
      throw const AppException(
        'This salary record is outside the active business.',
      );
    }
  }

  /// Saves a new rate version; the ID is based on its effective start date.
  /// Existing versions are never overwritten, preserving historical rates.
  Future<String> saveSalaryProfile({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required String salaryType,
    required int baseRatePaise,
    required String paymentCycle,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    Map<String, int>? initialOutletBasisPoints,
    required String createdBy,
    required String token,
  }) async {
    final emp = _safeId(employeeId);
    if (baseRatePaise <= 0 ||
        !{'MONTHLY', 'DAILY', 'HOURLY', 'SHIFT_BASED'}.contains(salaryType) ||
        !{'WEEKLY', 'FORTNIGHTLY', 'MONTHLY'}.contains(paymentCycle) ||
        (effectiveTo != null && !effectiveTo.isAfter(effectiveFrom))) {
      throw const AppException(
        'Enter a valid salary rate and effective period.',
      );
    }
    final Map<String, int>? cleanedInitialWeights =
        initialOutletBasisPoints == null
            ? null
            : Map<String, int>.fromEntries(
                initialOutletBasisPoints.entries.where((e) => e.value > 0),
              );
    if (cleanedInitialWeights != null &&
        (cleanedInitialWeights.isEmpty ||
            cleanedInitialWeights.values.fold<int>(
                  0,
                  (sum, value) => sum + value,
                ) !=
                allocationTotalBasisPoints)) {
      throw const AppException('Outlet allocations must total exactly 100%.');
    }
    final profileId = _scopedId('SALP', [
      tenantId,
      businessId,
      emp,
      _dateKey(effectiveFrom),
    ]);
    await atomicWrites.runAtomicOperation((tx) async {
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final employeeBusinesses =
          (employee.fields['businessIds'] as List? ?? [
            if (employee.fields['businessId'] is String)
              employee.fields['businessId'],
          ]).whereType<String>().toSet();
      if (!employee.exists ||
          employeeTenant != tenantId ||
          !employeeBusinesses.contains(businessId)) {
        throw const AppException(
          'Select an employee assigned to this business.',
        );
      }
      final profiles = await tx.query(
        FirebaseConstants.employeeSalaryProfiles,
        [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('employeeId', 'EQUAL', emp),
        ],
      );
      for (final record in profiles.where((record) => record.exists)) {
        final data = record.fields;
        final start = DateTime.tryParse(data['effectiveFrom'] as String? ?? '');
        final end = DateTime.tryParse(data['effectiveTo'] as String? ?? '');
        if (start == null) continue;
        final overlaps =
            (effectiveTo == null || start.isBefore(effectiveTo)) &&
            (end == null || end.isAfter(effectiveFrom));
        if (overlaps && data['profileId'] != profileId) {
          if (start.isBefore(effectiveFrom) &&
              (end == null || end.isAfter(effectiveFrom))) {
            tx.update(
              FirebaseConstants.employeeSalaryProfiles,
              data['profileId'] as String,
              {
                'effectiveTo': effectiveFrom.toUtc().toIso8601String(),
                'updatedAt': DateTime.now().toUtc().toIso8601String(),
              },
              updateTime: record.updateTime,
            );
          } else {
            throw const AppException(
              'Salary profile effective dates cannot overlap.',
            );
          }
        }
      }
      final existing = await tx.get(
        FirebaseConstants.employeeSalaryProfiles,
        profileId,
      );
      if (existing.exists) {
        tx.update(
          FirebaseConstants.employeeSalaryProfiles,
          profileId,
          {
            'salaryType': salaryType,
            'baseRatePaise': baseRatePaise,
            'paymentCycle': paymentCycle,
            if (effectiveTo != null)
              'effectiveTo': effectiveTo.toUtc().toIso8601String(),
            'status': 'ACTIVE',
            'updatedBy': createdBy,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          updateTime: existing.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.employeeSalaryProfiles, profileId, {
          'profileId': profileId,
          'tenantId': tenantId,
          'businessId': businessId,
          'employeeId': emp,
          'salaryType': salaryType,
          'baseRatePaise': baseRatePaise,
          'paymentCycle': paymentCycle,
          'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
          if (effectiveTo != null)
            'effectiveTo': effectiveTo.toUtc().toIso8601String(),
          'status': 'ACTIVE',
          'createdBy': createdBy,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
      final employeeOutlets =
          (employee.fields['outletIds'] as List? ?? [
            if (employee.fields['outletId'] is String)
              employee.fields['outletId'],
          ]).whereType<String>().toSet();
      Map<String, int>? allocationBasisPoints = cleanedInitialWeights;
      if (allocationBasisPoints == null && employeeOutlets.isNotEmpty) {
        final businessOutletIds = <String>[];
        for (final oid in employeeOutlets) {
          final oDoc = await tx.get(FirebaseConstants.outlets, _safeId(oid));
          final oTenant = oDoc.fields['tenantId'] ?? oDoc.fields['ownerUid'];
          if (oDoc.exists &&
              oDoc.fields['businessId'] == businessId &&
              oTenant == tenantId) {
            businessOutletIds.add(oid);
          }
        }
        if (businessOutletIds.length == 1) {
          allocationBasisPoints = {
            businessOutletIds.single: allocationTotalBasisPoints,
          };
        }
      }
      if (allocationBasisPoints != null) {
        if (allocationBasisPoints.isEmpty ||
            allocationBasisPoints.values.fold<int>(
                  0,
                  (sum, value) => sum + value,
                ) !=
                allocationTotalBasisPoints) {
          throw const AppException(
            'Outlet allocations must total exactly 100%.',
          );
        }
        final assigned = employeeOutlets;
        for (final outletId in allocationBasisPoints.keys) {
          final outlet = await tx.get(
            FirebaseConstants.outlets,
            _safeId(outletId),
          );
          final outletTenant =
              outlet.fields['tenantId'] ?? outlet.fields['ownerUid'];
          if (!assigned.contains(outletId) ||
              !outlet.exists ||
              outlet.fields['businessId'] != businessId ||
              outletTenant != tenantId) {
            throw const AppException(
              'Every allocated outlet must be assigned to the employee and business.',
            );
          }
        }
        final allocationId = _scopedId('SALA', [
          tenantId,
          businessId,
          emp,
          _dateKey(effectiveFrom),
        ]);
        final priorAllocations = await tx.query(
          FirebaseConstants.employeeOutletAllocations,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('employeeId', 'EQUAL', emp),
          ],
        );
        for (final record in priorAllocations.where(
          (record) => record.exists,
        )) {
          final start = DateTime.tryParse(
            record.fields['effectiveFrom'] as String? ?? '',
          );
          final end = DateTime.tryParse(
            record.fields['effectiveTo'] as String? ?? '',
          );
          if (start != null &&
              record.fields['allocationId'] != allocationId &&
              (effectiveTo == null || start.isBefore(effectiveTo)) &&
              (end == null || end.isAfter(effectiveFrom))) {
            if (start.isBefore(effectiveFrom) &&
                (end == null || end.isAfter(effectiveFrom))) {
              tx.update(
                FirebaseConstants.employeeOutletAllocations,
                record.fields['allocationId'] as String,
                {
                  'effectiveTo': effectiveFrom.toUtc().toIso8601String(),
                  'updatedAt': DateTime.now().toUtc().toIso8601String(),
                },
                updateTime: record.updateTime,
              );
            } else {
              throw const AppException(
                'Outlet allocation effective dates cannot overlap.',
              );
            }
          }
        }
        final priorAllocation = await tx.get(
          FirebaseConstants.employeeOutletAllocations,
          allocationId,
        );
        if (priorAllocation.exists) {
          tx.update(
            FirebaseConstants.employeeOutletAllocations,
            allocationId,
            {
              'outletBasisPoints': allocationBasisPoints,
              'allocationTotalBasisPoints': allocationTotalBasisPoints,
              if (effectiveTo != null)
                'effectiveTo': effectiveTo.toUtc().toIso8601String(),
              'status': 'ACTIVE',
              'updatedBy': createdBy,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
            updateTime: priorAllocation.updateTime,
          );
        } else {
          tx.create(FirebaseConstants.employeeOutletAllocations, allocationId, {
            'allocationId': allocationId,
            'tenantId': tenantId,
            'businessId': businessId,
            'employeeId': emp,
            'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
            if (effectiveTo != null)
              'effectiveTo': effectiveTo.toUtc().toIso8601String(),
            'outletBasisPoints': allocationBasisPoints,
            'allocationTotalBasisPoints': allocationTotalBasisPoints,
            'status': 'ACTIVE',
            'createdBy': createdBy,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
    }, idToken: token);
    return profileId;
  }

  /// Writes a complete effective-dated outlet allocation set. Percentages are
  /// stored as basis points, so the total is exactly 100.00% without float drift.
  Future<String> saveOutletAllocation({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    required Map<String, int> outletBasisPoints,
    required String createdBy,
    required String token,
  }) async {
    final emp = _safeId(employeeId);
    final cleanedWeights = Map<String, int>.fromEntries(
      outletBasisPoints.entries.where((e) => e.value > 0),
    );
    if (cleanedWeights.isEmpty ||
        cleanedWeights.values.fold<int>(0, (sum, value) => sum + value) !=
            allocationTotalBasisPoints ||
        (effectiveTo != null && !effectiveTo.isAfter(effectiveFrom))) {
      throw const AppException('Outlet allocations must total exactly 100%.');
    }
    final allocationId = _scopedId('SALA', [
      tenantId,
      businessId,
      emp,
      _dateKey(effectiveFrom),
    ]);
    await atomicWrites.runAtomicOperation((tx) async {
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final employeeBusinesses =
          (employee.fields['businessIds'] as List? ?? [
            if (employee.fields['businessId'] is String)
              employee.fields['businessId'],
          ]).whereType<String>().toSet();
      if (!employee.exists ||
          employeeTenant != tenantId ||
          !employeeBusinesses.contains(businessId)) {
        throw const AppException(
          'Select an employee assigned to this business.',
        );
      }
      final assigned = (employee.fields['outletIds'] as List? ?? [
        if (employee.fields['outletId'] is String)
          employee.fields['outletId'],
      ]).whereType<String>().toSet();
      for (final outletId in cleanedWeights.keys) {
        final outlet = await tx.get(
          FirebaseConstants.outlets,
          _safeId(outletId),
        );
        final outletTenant =
            outlet.fields['tenantId'] ?? outlet.fields['ownerUid'];
        if (!assigned.contains(outletId) ||
            !outlet.exists ||
            outlet.fields['businessId'] != businessId ||
            outletTenant != tenantId) {
          throw const AppException(
            'Every allocated outlet must be assigned to the employee and business.',
          );
        }
      }
      final allocations = await tx.query(
        FirebaseConstants.employeeOutletAllocations,
        [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('employeeId', 'EQUAL', emp),
        ],
      );
      for (final record in allocations.where((record) => record.exists)) {
        final fields = record.fields;
        final start = DateTime.tryParse(
          fields['effectiveFrom'] as String? ?? '',
        );
        final end = DateTime.tryParse(fields['effectiveTo'] as String? ?? '');
        if (start != null &&
            record.fields['allocationId'] != allocationId &&
            (effectiveTo == null || start.isBefore(effectiveTo)) &&
            (end == null || end.isAfter(effectiveFrom))) {
          if (start.isBefore(effectiveFrom) &&
              (end == null || end.isAfter(effectiveFrom))) {
            tx.update(
              FirebaseConstants.employeeOutletAllocations,
              record.fields['allocationId'] as String,
              {
                'effectiveTo': effectiveFrom.toUtc().toIso8601String(),
                'updatedAt': DateTime.now().toUtc().toIso8601String(),
              },
              updateTime: record.updateTime,
            );
          } else {
            throw const AppException(
              'Outlet allocation effective dates cannot overlap.',
            );
          }
        }
      }
      final existing = await tx.get(
        FirebaseConstants.employeeOutletAllocations,
        allocationId,
      );
      if (existing.exists) {
        tx.update(
          FirebaseConstants.employeeOutletAllocations,
          allocationId,
          {
            'outletBasisPoints': cleanedWeights,
            'allocationTotalBasisPoints': allocationTotalBasisPoints,
            if (effectiveTo != null)
              'effectiveTo': effectiveTo.toUtc().toIso8601String(),
            'status': 'ACTIVE',
            'updatedBy': createdBy,
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          updateTime: existing.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.employeeOutletAllocations, allocationId, {
          'allocationId': allocationId,
          'tenantId': tenantId,
          'businessId': businessId,
          'employeeId': emp,
          'effectiveFrom': effectiveFrom.toUtc().toIso8601String(),
          if (effectiveTo != null)
            'effectiveTo': effectiveTo.toUtc().toIso8601String(),
          'outletBasisPoints': cleanedWeights,
          'allocationTotalBasisPoints': allocationTotalBasisPoints,
          'status': 'ACTIVE',
          'createdBy': createdBy,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        });
      }
    }, idToken: token);
    return allocationId;
  }

  /// Preview and approval use integer paise throughout. `workUnitsMilli` is
  /// thousandths of a payable day, hour, or shift according to the profile.
  static Map<String, int> calculate({
    required String salaryType,
    required int baseRatePaise,
    int? monthlyBaseForPeriodPaise,
    int workUnitsMilli = 0,
    int bonusPaise = 0,
    int overtimePaise = 0,
    int approvedDeductionsPaise = 0,
  }) {
    if (baseRatePaise < 0 ||
        workUnitsMilli < 0 ||
        bonusPaise < 0 ||
        overtimePaise < 0 ||
        approvedDeductionsPaise < 0) {
      throw const AppException('Salary calculation values cannot be negative.');
    }
    final base = salaryType == 'MONTHLY'
        ? monthlyBaseForPeriodPaise ?? baseRatePaise
        : (baseRatePaise * workUnitsMilli + 500) ~/ 1000;
    final gross = base + bonusPaise + overtimePaise;
    final net = gross - approvedDeductionsPaise;
    if (net < 0) {
      throw const AppException('Approved deductions exceed earnings.');
    }
    return {
      'baseEarningsPaise': base,
      'grossEarningsPaise': gross,
      'approvedDeductionsPaise': approvedDeductionsPaise,
      'netEarnedPaise': net,
    };
  }

  static int _monthlyRateForPeriod(
    int monthlyRatePaise,
    DateTime start,
    DateTime end,
  ) {
    var cursor = DateTime.utc(start.year, start.month, start.day);
    final last = DateTime.utc(end.year, end.month, end.day);
    var total = 0;
    while (!cursor.isAfter(last)) {
      final nextMonth = DateTime.utc(cursor.year, cursor.month + 1, 1);
      final monthLast = nextMonth.subtract(const Duration(days: 1));
      final segmentLast = monthLast.isBefore(last) ? monthLast : last;
      final days = segmentLast.difference(cursor).inDays + 1;
      final daysInMonth = DateTime.utc(cursor.year, cursor.month + 1, 0).day;
      total += (monthlyRatePaise * days + daysInMonth ~/ 2) ~/ daysInMonth;
      cursor = segmentLast.add(const Duration(days: 1));
    }
    return total;
  }

  static Map<String, int> previewPeriodCalculation({
    required String salaryType,
    required int baseRatePaise,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int workUnitsMilli,
    int bonusPaise = 0,
    int overtimePaise = 0,
    int approvedDeductionsPaise = 0,
  }) => calculate(
    salaryType: salaryType,
    baseRatePaise: baseRatePaise,
    monthlyBaseForPeriodPaise: salaryType == 'MONTHLY'
        ? _monthlyRateForPeriod(baseRatePaise, periodStart, periodEnd)
        : null,
    workUnitsMilli: workUnitsMilli,
    bonusPaise: bonusPaise,
    overtimePaise: overtimePaise,
    approvedDeductionsPaise: approvedDeductionsPaise,
  );

  /// Approves one salary period and records its outlet allocated accrual once.
  /// Reports treat the approved gross amount as expense; actual cash flow is
  /// recorded later by `recordSalaryPayment` only. Keeping the accrual on the
  /// protected salary period prevents general expense sync from exposing pay.
  Future<String> approveSalaryPeriod({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required String profileId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int workUnitsMilli,
    int bonusPaise = 0,
    int overtimePaise = 0,
    int approvedDeductionsPaise = 0,
    List<String>? attendanceRecordIds,
    Map<String, int>? fallbackOutletBasisPoints,
    required String approvedBy,
    required String token,
  }) async {
    final emp = _safeId(employeeId);
    if (periodEnd.isBefore(periodStart)) {
      throw const AppException('Salary period dates are invalid.');
    }
    final periodId = _scopedId('SALPER', [
      tenantId,
      businessId,
      emp,
      _dateKey(periodStart),
      _dateKey(periodEnd),
    ]);
    await atomicWrites.runAtomicOperation((tx) async {
      final prior = await tx.get(FirebaseConstants.salaryPeriods, periodId);
      if (prior.exists) {
        final same =
            prior.fields['tenantId'] == tenantId &&
            prior.fields['businessId'] == businessId &&
            prior.fields['employeeId'] == emp &&
            prior.fields['profileId'] == profileId &&
            prior.fields['periodStart'] ==
                periodStart.toUtc().toIso8601String() &&
            prior.fields['periodEnd'] == periodEnd.toUtc().toIso8601String() &&
            (prior.fields['workUnitsMilli'] as num?)?.toInt() ==
                workUnitsMilli &&
            (prior.fields['bonusPaise'] as num?)?.toInt() == bonusPaise &&
            (prior.fields['overtimePaise'] as num?)?.toInt() == overtimePaise &&
            (prior.fields['approvedDeductionsPaise'] as num?)?.toInt() ==
                approvedDeductionsPaise &&
            (attendanceRecordIds == null ||
                (prior.fields['attendanceRecordIds'] as List? ?? const [])
                        .toSet()
                        .containsAll(attendanceRecordIds) &&
                    attendanceRecordIds.toSet().containsAll(
                      (prior.fields['attendanceRecordIds'] as List? ?? const [])
                          .whereType<String>(),
                    ));
        if (!same) {
          throw const AppException(
            'This salary period ID has conflicting details.',
          );
        }
        return;
      }
      final profile = await tx.get(
        FirebaseConstants.employeeSalaryProfiles,
        _safeId(profileId),
      );
      if (!profile.exists) {
        throw const AppException(
          'The effective salary profile is unavailable.',
        );
      }
      _scope(
        profile.fields,
        tenantId: tenantId,
        businessId: businessId,
        employeeId: emp,
      );
      final salaryType = profile.fields['salaryType'] as String? ?? '';
      if (attendanceRecordIds != null) {
        final ids = attendanceRecordIds.map(_safeId).toSet();
        if (ids.length != attendanceRecordIds.length) {
          throw const AppException('An attendance record is duplicated.');
        }
        var attendanceUnits = 0;
        final attendanceRows = <Map<String, dynamic>>[];
        for (final id in ids) {
          final attendance = await tx.get(
            FirebaseConstants.staffAttendance,
            id,
          );
          final date = DateTime.tryParse(
            attendance.fields['workDate']?.toString() ?? '',
          );
          if (!attendance.exists ||
              attendance.fields['tenantId'] != tenantId ||
              attendance.fields['businessId'] != businessId ||
              attendance.fields['employeeId'] != emp ||
              attendance.fields['approvalStatus'] != 'APPROVED' ||
              date == null ||
              date.isBefore(periodStart) ||
              date.isAfter(periodEnd)) {
            throw const AppException(
              'Salary includes attendance that is unapproved or outside this period.',
            );
          }
          final payableUnits =
              (attendance.fields['payableUnitsMilli'] as num?)?.toInt() ?? 0;
          attendanceRows.add(attendance.fields);
          if (salaryType == 'HOURLY' && payableUnits > 0) {
            final minutes =
                (attendance.fields['workedMinutes'] as num?)?.toInt() ?? 0;
            attendanceUnits += (minutes * 1000 + 30) ~/ 60;
          } else {
            attendanceUnits += payableUnits;
          }
        }
        final attendanceOvertime =
            StaffAttendanceRepository.calculateOvertimePaise(attendanceRows);
        if (attendanceUnits != workUnitsMilli ||
            attendanceOvertime > overtimePaise) {
          throw const AppException(
            'Salary work units or overtime do not match approved attendance.',
          );
        }
        final priorPeriods = await tx.query(FirebaseConstants.salaryPeriods, [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('employeeId', 'EQUAL', emp),
        ]);
        final alreadyUsed = priorPeriods
            .where((record) => record.exists)
            .expand(
              (record) =>
                  (record.fields['attendanceRecordIds'] as List? ?? const [])
                      .whereType<String>(),
            )
            .toSet();
        if (ids.any(alreadyUsed.contains)) {
          throw const AppException(
            'Approved attendance has already been included in another salary period.',
          );
        }
      }
      final effectiveFrom = DateTime.tryParse(
        profile.fields['effectiveFrom'] as String? ?? '',
      );
      final effectiveTo = DateTime.tryParse(
        profile.fields['effectiveTo'] as String? ?? '',
      );
      if (effectiveFrom == null ||
          periodStart.isBefore(effectiveFrom) ||
          (effectiveTo != null && periodEnd.isAfter(effectiveTo))) {
        throw const AppException(
          'The salary profile does not cover this period.',
        );
      }
      final baseRate = (profile.fields['baseRatePaise'] as num?)?.toInt() ?? 0;
      final calc = previewPeriodCalculation(
        salaryType: salaryType,
        baseRatePaise: baseRate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        workUnitsMilli: workUnitsMilli,
        bonusPaise: bonusPaise,
        overtimePaise: overtimePaise,
        approvedDeductionsPaise: approvedDeductionsPaise,
      );
      final allocations = await tx.query(
        FirebaseConstants.employeeOutletAllocations,
        [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('employeeId', 'EQUAL', emp),
        ],
      );
      final valid = allocations.where((record) {
        if (!record.exists) return false;
        final start = DateTime.tryParse(
          record.fields['effectiveFrom'] as String? ?? '',
        );
        final end = DateTime.tryParse(
          record.fields['effectiveTo'] as String? ?? '',
        );
        return start != null &&
            !periodStart.isBefore(start) &&
            (end == null || !periodEnd.isAfter(end));
      }).toList();
      Map<String, int> outletWeights;
      if (valid.length > 1) {
        throw const AppException(
          'Overlapping outlet allocations need correction.',
        );
      }
      if (valid.length == 1) {
        final raw = valid.single.fields['outletBasisPoints'];
        outletWeights = raw is Map
            ? raw.map(
                (key, value) =>
                    MapEntry(key.toString(), (value as num).toInt()),
              )
            : {};
      } else {
        final activeAllocations = allocations.where((record) {
          if (!record.exists) return false;
          final status = record.fields['status'] as String? ?? 'ACTIVE';
          return status == 'ACTIVE';
        }).toList();
        if (activeAllocations.isNotEmpty) {
          final sorted = activeAllocations..sort((a, b) {
            final aStart = a.fields['effectiveFrom']?.toString() ?? '';
            final bStart = b.fields['effectiveFrom']?.toString() ?? '';
            return bStart.compareTo(aStart);
          });
          final raw = sorted.first.fields['outletBasisPoints'];
          outletWeights = raw is Map
              ? raw.map(
                  (key, value) =>
                      MapEntry(key.toString(), (value as num).toInt()),
                )
              : (fallbackOutletBasisPoints ?? {});
        } else {
          outletWeights = fallbackOutletBasisPoints ?? {};
        }
      }
      outletWeights = Map<String, int>.fromEntries(
        outletWeights.entries.where((e) => e.value > 0),
      );
      if (outletWeights.isEmpty ||
          outletWeights.values.fold<int>(0, (sum, value) => sum + value) !=
              allocationTotalBasisPoints) {
        throw const AppException(
          'Outlet allocations must total exactly 100% before salary approval.',
        );
      }
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final assignedOutlets =
          (employee.fields['outletIds'] as List? ?? [
            if (employee.fields['outletId'] is String)
              employee.fields['outletId'],
          ]).whereType<String>().toSet();
      for (final outletId in outletWeights.keys) {
        final outlet = await tx.get(
          FirebaseConstants.outlets,
          _safeId(outletId),
        );
        final outletTenant =
            outlet.fields['tenantId'] ?? outlet.fields['ownerUid'];
        if (!employee.exists ||
            employeeTenant != tenantId ||
            !assignedOutlets.contains(outletId) ||
            !outlet.exists ||
            outletTenant != tenantId ||
            outlet.fields['businessId'] != businessId) {
          throw const AppException(
            'Salary allocation references an outlet outside the employee business.',
          );
        }
      }
      final expenseAmount = calc['grossEarningsPaise']!;
      var allocatedSoFar = 0;
      final outlets = outletWeights.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final outletExpenses = <String, int>{};
      for (var i = 0; i < outlets.length; i++) {
        final entry = outlets[i];
        final allocated = i == outlets.length - 1
            ? expenseAmount - allocatedSoFar
            : (expenseAmount * entry.value) ~/ allocationTotalBasisPoints;
        allocatedSoFar += allocated;
        outletExpenses[entry.key] = allocated;
      }
      final now = DateTime.now().toUtc().toIso8601String();
      tx.create(FirebaseConstants.salaryPeriods, periodId, {
        'periodId': periodId,
        'tenantId': tenantId,
        'businessId': businessId,
        'employeeId': emp,
        'profileId': profileId,
        'periodStart': periodStart.toUtc().toIso8601String(),
        'periodEnd': periodEnd.toUtc().toIso8601String(),
        ...calc,
        'expenseAmountPaise': expenseAmount,
        'workUnitsMilli': workUnitsMilli,
        ...attendanceRecordIds == null
            ? const <String, dynamic>{}
            : {'attendanceRecordIds': attendanceRecordIds},
        'bonusPaise': bonusPaise,
        'overtimePaise': overtimePaise,
        'outletExpensesPaise': outletExpenses,
        'outletBasisPoints': outletWeights,
        'paidAmountPaise': 0,
        'advanceAdjustedPaise': 0,
        'staffPurchaseAdjustedPaise': 0,
        'status': 'APPROVED',
        'approvedBy': approvedBy,
        'approvedAt': now,
        'createdAt': now,
        'updatedAt': now,
      });
    }, idToken: token);
    return periodId;
  }

  /// Records a real advance disbursement and its single cash/bank event.
  Future<String> recordAdvance({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required int amountPaise,
    required DateTime date,
    required String paymentMode,
    required String requestId,
    required String createdBy,
    String? referenceNo,
    String? notes,
    required String token,
  }) async {
    final emp = _safeId(employeeId),
        request = _safeId(requestId),
        outlet = _safeId(outletId);
    if (amountPaise <= 0 ||
        !{
          'CASH',
          'UPI',
          'BANK_TRANSFER',
          'CHEQUE',
          'CARD',
        }.contains(paymentMode)) {
      throw const AppException(
        'Enter a positive advance and valid payment method.',
      );
    }
    final eventId = 'SKH-ADV-$request';
    final financialId = 'FIN-$eventId';
    late Map<String, dynamic> khataFields;
    late Map<String, dynamic> financeFields;
    var isDuplicate = false;

    await serverTransactions.runAtomicOperation((tx) async {
      final existing = await tx.get(
        FirebaseConstants.staffKhataTransactions,
        eventId,
      );
      if (existing.exists) {
        if (existing.fields['employeeId'] != emp ||
            existing.fields['businessId'] != businessId ||
            existing.fields['outletId'] != outlet ||
            existing.fields['paymentMode'] != paymentMode ||
            (existing.fields['amountPaise'] as num?)?.toInt() != amountPaise ||
            existing.fields['transactionDate'] !=
                date.toUtc().toIso8601String()) {
          throw const AppException(
            'This request ID was already used for different advance details.',
          );
        }
        isDuplicate = true;
        return;
      }
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final employeeBusinesses =
          (employee.fields['businessIds'] as List? ?? [
            if (employee.fields['businessId'] is String)
              employee.fields['businessId'],
          ]).whereType<String>().toSet();
      final employeeOutlets =
          (employee.fields['outletIds'] as List? ?? [
            if (employee.fields['outletId'] is String)
              employee.fields['outletId'],
          ]).whereType<String>().toSet();
      if (!employee.exists ||
          employeeTenant != tenantId ||
          !employeeBusinesses.contains(businessId) ||
          !employeeOutlets.contains(outlet)) {
        throw const AppException('Employee is not assigned to this outlet.');
      }
      final now = DateTime.now().toUtc();
      final khataType = paymentMode == 'UPI'
          ? 'UPI_ADVANCE'
          : (paymentMode == 'BANK_TRANSFER' || paymentMode == 'CHEQUE'
              ? 'BANK_ADVANCE'
              : 'CASH_ADVANCE');
      khataFields = {
        'recordId': eventId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'employeeId': emp,
        'transactionType': khataType,
        'amountPaise': amountPaise,
        'paymentMode': paymentMode,
        'transactionDate': date.toUtc().toIso8601String(),
        'financialTransactionId': financialId,
        'requestId': request,
        'referenceNo': referenceNo?.trim(),
        'notes': notes?.trim(),
        'status': 'POSTED',
        'createdBy': createdBy,
        'createdAt': now.toIso8601String(),
      };
      tx.create(FirebaseConstants.staffKhataTransactions, eventId, khataFields);
      final finModel = FinancialTransactionModel(
        transactionId: financialId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet,
        direction: 'OUT',
        transactionType: 'STAFF_ADVANCE',
        partyType: 'EMPLOYEE',
        partyId: emp,
        amount: amountPaise,
        paymentMode: paymentMode,
        referenceType: 'STAFF_KHATA',
        referenceId: eventId,
        transactionDate: date,
        createdByUid: createdBy,
        createdAt: now,
        status: 'POSTED',
        referenceNo: referenceNo,
        notes: notes,
      );
      financeFields = finModel.toData();
      tx.create(
        FirebaseConstants.financialTransactions,
        financialId,
        financeFields,
      );
    }, idToken: token);

    if (!isDuplicate) {
      await _updateLocalCache([
        (
          collection: FirebaseConstants.staffKhataTransactions,
          id: eventId,
          fields: khataFields,
        ),
        (
          collection: FirebaseConstants.financialTransactions,
          id: financialId,
          fields: financeFields,
        ),
      ]);
    }
    return eventId;
  }

  /// Supports partial payments; each request ID can post once, and each post
  /// updates payable and cash movement atomically with its immutable event.
  Future<String> recordSalaryPayment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String periodId,
    required int amountPaise,
    required DateTime date,
    required String paymentMode,
    required String requestId,
    required String paidBy,
    String? referenceNo,
    String? notes,
    required String token,
  }) async {
    final emp = _safeId(employeeId),
        request = _safeId(requestId),
        outlet = _safeId(outletId);
    if (amountPaise <= 0 ||
        !{
          'CASH',
          'UPI',
          'BANK_TRANSFER',
          'CHEQUE',
          'CARD',
        }.contains(paymentMode)) {
      throw const AppException(
        'Enter a positive payment and valid payment method.',
      );
    }
    final eventId = 'SKH-PAY-$request', financialId = 'FIN-SAL-$request';
    late Map<String, dynamic> updatedPeriodFields;
    late Map<String, dynamic> khataFields;
    late Map<String, dynamic> financeFields;
    var isDuplicate = false;

    await serverTransactions.runAtomicOperation((tx) async {
      final duplicate = await tx.get(
        FirebaseConstants.staffKhataTransactions,
        eventId,
      );
      if (duplicate.exists) {
        if (duplicate.fields['employeeId'] != emp ||
            duplicate.fields['periodId'] != periodId ||
            duplicate.fields['outletId'] != outlet ||
            duplicate.fields['paymentMode'] != paymentMode ||
            (duplicate.fields['amountPaise'] as num?)?.toInt() != amountPaise ||
            duplicate.fields['transactionDate'] !=
                date.toUtc().toIso8601String()) {
          throw const AppException(
            'This payment request ID was already used for different details.',
          );
        }
        isDuplicate = true;
        return;
      }
      final period = await tx.get(
        FirebaseConstants.salaryPeriods,
        _safeId(periodId),
      );
      if (!period.exists ||
          period.fields['tenantId'] != tenantId ||
          period.fields['businessId'] != businessId ||
          period.fields['employeeId'] != emp ||
          !{'APPROVED', 'PARTIALLY_PAID'}.contains(period.fields['status'])) {
        throw const AppException('Approved salary payable was not found.');
      }
      final outletDoc = await tx.get(FirebaseConstants.outlets, outlet);
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final outletTenant =
          outletDoc.fields['tenantId'] ?? outletDoc.fields['ownerUid'];
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final employeeOutlets =
          (employee.fields['outletIds'] as List? ?? [
            if (employee.fields['outletId'] is String)
              employee.fields['outletId'],
          ]).whereType<String>().toSet();
      if (!outletDoc.exists ||
          outletTenant != tenantId ||
          outletDoc.fields['businessId'] != businessId ||
          !employee.exists ||
          employeeTenant != tenantId ||
          !employeeOutlets.contains(outlet)) {
        throw const AppException(
          'Payment outlet is not assigned to this employee and business.',
        );
      }
      final earned = (period.fields['netEarnedPaise'] as num?)?.toInt() ?? 0;
      final paid = (period.fields['paidAmountPaise'] as num?)?.toInt() ?? 0;
      final advances =
          (period.fields['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
      final purchases =
          (period.fields['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
      if (amountPaise > earned - paid - advances - purchases) {
        throw const AppException('Payment exceeds remaining salary payable.');
      }
      final now = DateTime.now().toUtc();
      final nowIso = now.toIso8601String();
      final nextPaid = paid + amountPaise;
      final newStatus = nextPaid + advances + purchases == earned
          ? 'PAID'
          : 'PARTIALLY_PAID';

      updatedPeriodFields = {
        ...period.fields,
        'paidAmountPaise': nextPaid,
        'status': newStatus,
        'updatedAt': nowIso,
      };

      tx.update(FirebaseConstants.salaryPeriods, periodId, {
        'paidAmountPaise': nextPaid,
        'status': newStatus,
        'updatedAt': nowIso,
      }, updateTime: period.updateTime);

      khataFields = {
        'recordId': eventId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'employeeId': emp,
        'periodId': periodId,
        'transactionType': 'SALARY_PAYMENT',
        'amountPaise': amountPaise,
        'paymentMode': paymentMode,
        'transactionDate': date.toUtc().toIso8601String(),
        'financialTransactionId': financialId,
        'requestId': request,
        'referenceNo': referenceNo?.trim(),
        'notes': notes?.trim(),
        'status': 'POSTED',
        'createdBy': paidBy,
        'createdAt': nowIso,
      };
      tx.create(FirebaseConstants.staffKhataTransactions, eventId, khataFields);

      final finModel = FinancialTransactionModel(
        transactionId: financialId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet,
        direction: 'OUT',
        transactionType: 'SALARY_PAYMENT',
        partyType: 'EMPLOYEE',
        partyId: emp,
        amount: amountPaise,
        paymentMode: paymentMode,
        referenceType: 'SALARY_PERIOD',
        referenceId: periodId,
        transactionDate: date,
        createdByUid: paidBy,
        createdAt: now,
        status: 'POSTED',
        referenceNo: referenceNo,
        notes: notes,
      );
      financeFields = finModel.toData();
      tx.create(
        FirebaseConstants.financialTransactions,
        financialId,
        financeFields,
      );
    }, idToken: token);

    if (!isDuplicate) {
      await _updateLocalCache([
        (
          collection: FirebaseConstants.salaryPeriods,
          id: periodId,
          fields: updatedPeriodFields,
        ),
        (
          collection: FirebaseConstants.staffKhataTransactions,
          id: eventId,
          fields: khataFields,
        ),
        (
          collection: FirebaseConstants.financialTransactions,
          id: financialId,
          fields: financeFields,
        ),
      ]);
    }
    return eventId;
  }

  /// Applies an already-disbursed advance against an approved salary payable.
  /// This is a non-cash ledger event and deliberately creates no finance row.
  Future<String> adjustAdvanceAgainstSalary({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String periodId,
    required int amountPaise,
    required String requestId,
    required String approvedBy,
    required String token,
  }) async {
    final emp = _safeId(employeeId),
        request = _safeId(requestId),
        outlet = _safeId(outletId);
    if (amountPaise <= 0) {
      throw const AppException('Enter a positive advance adjustment.');
    }
    final eventId = 'SKH-ADJ-$request';
    await atomicWrites.runAtomicOperation((tx) async {
      final duplicate = await tx.get(
        FirebaseConstants.staffKhataTransactions,
        eventId,
      );
      if (duplicate.exists) {
        if (duplicate.fields['employeeId'] != emp ||
            duplicate.fields['periodId'] != periodId ||
            (duplicate.fields['amountPaise'] as num?)?.toInt() != amountPaise) {
          throw const AppException(
            'This adjustment request ID was already used for different details.',
          );
        }
        return;
      }
      final period = await tx.get(
        FirebaseConstants.salaryPeriods,
        _safeId(periodId),
      );
      if (!period.exists ||
          period.fields['tenantId'] != tenantId ||
          period.fields['businessId'] != businessId ||
          period.fields['employeeId'] != emp ||
          !{'APPROVED', 'PARTIALLY_PAID'}.contains(period.fields['status'])) {
        throw const AppException('Approved salary payable was not found.');
      }
      final outletDoc = await tx.get(FirebaseConstants.outlets, outlet);
      final employee = await tx.get(FirebaseConstants.employees, emp);
      final outletTenant =
          outletDoc.fields['tenantId'] ?? outletDoc.fields['ownerUid'];
      final employeeTenant =
          employee.fields['tenantId'] ?? employee.fields['ownerUid'];
      final employeeOutlets =
          (employee.fields['outletIds'] as List? ?? [
            if (employee.fields['outletId'] is String)
              employee.fields['outletId'],
          ]).whereType<String>().toSet();
      if (!outletDoc.exists ||
          outletTenant != tenantId ||
          outletDoc.fields['businessId'] != businessId ||
          !employee.exists ||
          employeeTenant != tenantId ||
          !employeeOutlets.contains(outlet)) {
        throw const AppException(
          'Adjustment outlet is not assigned to this employee and business.',
        );
      }
      final events = await tx.query(FirebaseConstants.staffKhataTransactions, [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('employeeId', 'EQUAL', emp),
      ]);
      var advanceBalance = 0;
      for (final record in events.where((record) => record.exists)) {
        final amount = (record.fields['amountPaise'] as num?)?.toInt() ?? 0;
        if (record.fields['status'] != 'POSTED') continue;
        if (record.fields['transactionType'] == 'CASH_ADVANCE' ||
            record.fields['transactionType'] == 'UPI_ADVANCE' ||
            record.fields['transactionType'] == 'BANK_ADVANCE') {
          advanceBalance += amount;
        }
        if (record.fields['transactionType'] == 'ADVANCE_ADJUSTMENT') {
          advanceBalance -= amount;
        }
      }
      final earned = (period.fields['netEarnedPaise'] as num?)?.toInt() ?? 0;
      final paid = (period.fields['paidAmountPaise'] as num?)?.toInt() ?? 0;
      final adjusted =
          (period.fields['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
      final purchaseAdjusted =
          (period.fields['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
      if (amountPaise > advanceBalance ||
          amountPaise > earned - paid - adjusted - purchaseAdjusted) {
        throw const AppException(
          'Advance adjustment exceeds the advance balance or salary payable.',
        );
      }
      final nextAdjusted = adjusted + amountPaise;
      final now = DateTime.now().toUtc();
      tx.update(FirebaseConstants.salaryPeriods, periodId, {
        'advanceAdjustedPaise': nextAdjusted,
        'status': paid + nextAdjusted + purchaseAdjusted == earned
            ? 'PAID'
            : 'PARTIALLY_PAID',
        'updatedAt': now.toIso8601String(),
      }, updateTime: period.updateTime);
      tx.create(FirebaseConstants.staffKhataTransactions, eventId, {
        'recordId': eventId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'employeeId': emp,
        'periodId': periodId,
        'transactionType': 'ADVANCE_ADJUSTMENT',
        'amountPaise': amountPaise,
        'paymentMode': 'NON_CASH',
        'transactionDate': now.toIso8601String(),
        'requestId': request,
        'status': 'POSTED',
        'approvedBy': approvedBy,
        'createdBy': approvedBy,
        'createdAt': now.toIso8601String(),
      });
    }, idToken: token);
    return eventId;
  }

  Future<List<Map<String, dynamic>>> getKhataTransactions({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.staffKhataTransactions,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('employeeId', 'EQUAL', _safeId(employeeId)),
      ],
      idToken: token,
    );
    return docs
        .map(
          (doc) => FirestoreRestService.decodeFields(doc['fields']),
        )
        .toList()
      ..sort(
        (a, b) => (b['transactionDate']?.toString() ?? '').compareTo(
          a['transactionDate']?.toString() ?? '',
        ),
      );
  }

  /// Applies money received against an employee's posted POS invoice. The
  /// invoice balance, immutable khata event, payment receipt and cash-in event
  /// are staged in one local SQLite/outbox transaction.
  Future<String> recordStaffPurchasePayment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String invoiceId,
    required int amountPaise,
    required String paymentMode,
    required String requestId,
    required String recordedBy,
    required String token,
  }) async {
    final employee = _safeId(employeeId),
        invoiceKey = _safeId(invoiceId),
        request = _safeId(requestId),
        outlet = _safeId(outletId);
    if (amountPaise <= 0 ||
        !{
          'CASH',
          'UPI',
          'BANK_TRANSFER',
          'CHEQUE',
          'CARD',
        }.contains(paymentMode)) {
      throw const AppException(
        'Enter a positive payment and valid payment method.',
      );
    }
    final eventId = 'SKH-PURPAY-$request';
    final financeId = 'FIN-SPAY-$request';
    final paymentId = 'PAY-SP-$request';
    late Map<String, dynamic> updatedInvoiceFields;
    late Map<String, dynamic> paymentFields;
    late Map<String, dynamic> khataFields;
    late Map<String, dynamic> financeFields;
    var isDuplicate = false;

    await serverTransactions.runAtomicOperation((tx) async {
      final duplicate = await tx.get(
        FirebaseConstants.staffKhataTransactions,
        eventId,
      );
      if (duplicate.exists) {
        if (duplicate.fields['employeeId'] != employee ||
            duplicate.fields['referenceId'] != invoiceKey ||
            (duplicate.fields['amountPaise'] as num?)?.toInt() != amountPaise ||
            duplicate.fields['paymentMode'] != paymentMode) {
          throw const AppException(
            'This purchase payment request ID was already used.',
          );
        }
        isDuplicate = true;
        return;
      }
      final invoice = await tx.get(FirebaseConstants.invoices, invoiceKey);
      final person = await tx.get(FirebaseConstants.employees, employee);
      final invoiceTenant =
          invoice.fields['tenantId'] ?? invoice.fields['ownerUid'];
      final personTenant =
          person.fields['tenantId'] ?? person.fields['ownerUid'];
      if (!invoice.exists ||
          invoice.fields['employeeId'] != employee ||
          invoiceTenant != tenantId ||
          invoice.fields['businessId'] != businessId ||
          invoice.fields['outletId'] != outlet ||
          !person.exists ||
          personTenant != tenantId) {
        throw const AppException(
          'Staff invoice is unavailable in this outlet.',
        );
      }
      final due = (invoice.fields['outstandingAmount'] as num?)?.toInt() ?? 0;
      if (due <= 0 || amountPaise > due) {
        throw const AppException('Payment exceeds the staff invoice balance.');
      }
      final remaining = due - amountPaise;
      final now = DateTime.now().toUtc();
      final nowIso = now.toIso8601String();
      final newPaidAmount =
          ((invoice.fields['paidAmount'] as num?)?.toInt() ?? 0) +
          amountPaise;
      final newPaymentStatus = remaining == 0 ? 'PAID' : 'PARTIALLY_PAID';

      updatedInvoiceFields = {
        ...invoice.fields,
        'paidAmount': newPaidAmount,
        'outstandingAmount': remaining,
        'paymentStatus': newPaymentStatus,
        'updatedAt': nowIso,
      };

      tx.update(FirebaseConstants.invoices, invoiceKey, {
        'paidAmount': newPaidAmount,
        'outstandingAmount': remaining,
        'paymentStatus': newPaymentStatus,
        'updatedAt': nowIso,
      }, updateTime: invoice.updateTime);

      paymentFields = {
        'paymentId': paymentId,
        'invoiceId': invoiceKey,
        'employeeId': employee,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'mode': paymentMode,
        'amountPaise': amountPaise,
        'appliedPaise': amountPaise,
        'createdByUid': recordedBy,
        'createdAt': nowIso,
        'immutable': true,
      };
      tx.create(FirebaseConstants.payments, paymentId, paymentFields);

      khataFields = {
        'recordId': eventId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'employeeId': employee,
        'transactionType': 'STORE_CREDIT_ADJUSTMENT',
        'amountPaise': amountPaise,
        'paymentMode': paymentMode,
        'referenceType': 'INVOICE',
        'referenceId': invoiceKey,
        'requestId': request,
        'status': 'POSTED',
        'createdBy': recordedBy,
        'createdAt': nowIso,
      };
      tx.create(FirebaseConstants.staffKhataTransactions, eventId, khataFields);

      final finModel = FinancialTransactionModel(
        transactionId: financeId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet,
        direction: 'IN',
        transactionType: 'STAFF_PURCHASE_PAYMENT',
        partyType: 'EMPLOYEE',
        partyId: employee,
        amount: amountPaise,
        paymentMode: paymentMode,
        referenceType: 'INVOICE',
        referenceId: invoiceKey,
        transactionDate: now,
        createdByUid: recordedBy,
        createdAt: now,
        status: 'POSTED',
      );
      financeFields = finModel.toData();
      tx.create(
        FirebaseConstants.financialTransactions,
        financeId,
        financeFields,
      );
    }, idToken: token);

    if (!isDuplicate) {
      await _updateLocalCache([
        (
          collection: FirebaseConstants.invoices,
          id: invoiceKey,
          fields: updatedInvoiceFields,
        ),
        (
          collection: FirebaseConstants.payments,
          id: paymentId,
          fields: paymentFields,
        ),
        (
          collection: FirebaseConstants.staffKhataTransactions,
          id: eventId,
          fields: khataFields,
        ),
        (
          collection: FirebaseConstants.financialTransactions,
          id: financeId,
          fields: financeFields,
        ),
      ]);
    }
    return eventId;
  }

  /// Settles an authorized portion of posted staff-purchase receivables against
  /// salary earned. It changes no cash balance and creates no salary expense.
  Future<String> adjustStaffPurchasesAgainstSalary({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String employeeId,
    required String periodId,
    required int amountPaise,
    required String requestId,
    required String approvedBy,
    required String token,
  }) async {
    final employee = _safeId(employeeId),
        request = _safeId(requestId),
        outlet = _safeId(outletId),
        eventId = 'SKH-POFF-$request';
    if (amountPaise <= 0) {
      throw const AppException('Enter a positive purchase offset.');
    }
    await atomicWrites.runAtomicOperation((tx) async {
      final duplicate = await tx.get(
        FirebaseConstants.staffKhataTransactions,
        eventId,
      );
      if (duplicate.exists) {
        if (duplicate.fields['employeeId'] != employee ||
            duplicate.fields['periodId'] != periodId ||
            (duplicate.fields['amountPaise'] as num?)?.toInt() != amountPaise) {
          throw const AppException(
            'This purchase offset request ID was already used.',
          );
        }
        return;
      }
      final period = await tx.get(
        FirebaseConstants.salaryPeriods,
        _safeId(periodId),
      );
      final periodTenant =
          period.fields['tenantId'] ?? period.fields['ownerUid'];
      if (!period.exists ||
          periodTenant != tenantId ||
          period.fields['businessId'] != businessId ||
          period.fields['employeeId'] != employee ||
          !{'APPROVED', 'PARTIALLY_PAID'}.contains(period.fields['status'])) {
        throw const AppException('Approved salary payable was not found.');
      }
      final records = await tx.query(FirebaseConstants.staffKhataTransactions, [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('employeeId', 'EQUAL', employee),
      ]);
      var receivable = 0;
      for (final row in records.where(
        (row) => row.exists && row.fields['status'] == 'POSTED',
      )) {
        final value = (row.fields['amountPaise'] as num?)?.toInt() ?? 0;
        if (row.fields['transactionType'] == 'STORE_PURCHASE') {
          receivable += value;
        }
        if (row.fields['transactionType'] == 'STORE_CREDIT_ADJUSTMENT') {
          receivable -= value;
        }
      }
      final earned = (period.fields['netEarnedPaise'] as num?)?.toInt() ?? 0;
      final paid = (period.fields['paidAmountPaise'] as num?)?.toInt() ?? 0;
      final advances =
          (period.fields['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
      final purchases =
          (period.fields['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
      if (amountPaise > receivable ||
          amountPaise > earned - paid - advances - purchases) {
        throw const AppException(
          'Purchase offset exceeds the receivable or salary payable.',
        );
      }
      final nextPurchases = purchases + amountPaise;
      final nextStatus = paid + advances + nextPurchases == earned
          ? 'PAID'
          : 'PARTIALLY_PAID';
      final now = DateTime.now().toUtc().toIso8601String();
      tx.update(FirebaseConstants.salaryPeriods, periodId, {
        'staffPurchaseAdjustedPaise': nextPurchases,
        'status': nextStatus,
        'updatedAt': now,
      }, updateTime: period.updateTime);
      tx.create(FirebaseConstants.staffKhataTransactions, eventId, {
        'recordId': eventId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet,
        'employeeId': employee,
        'periodId': periodId,
        'transactionType': 'STORE_CREDIT_ADJUSTMENT',
        'amountPaise': amountPaise,
        'paymentMode': 'NON_CASH',
        'referenceType': 'SALARY_PERIOD',
        'referenceId': periodId,
        'requestId': request,
        'status': 'POSTED',
        'approvedBy': approvedBy,
        'createdBy': approvedBy,
        'createdAt': now,
      });
    }, idToken: token);
    return eventId;
  }

  Future<List<Map<String, dynamic>>> _businessRecords({
    required String collection,
    required String tenantId,
    required String businessId,
    required String token,
    String? employeeId,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: collection,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (employeeId != null)
          FirestoreFilter('employeeId', 'EQUAL', employeeId),
      ],
      idToken: token,
    );
    return docs
        .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getSalaryProfiles({
    required String tenantId,
    required String businessId,
    required String token,
    String? employeeId,
  }) => _businessRecords(
    collection: FirebaseConstants.employeeSalaryProfiles,
    tenantId: tenantId,
    businessId: businessId,
    token: token,
    employeeId: employeeId,
  );

  Future<List<Map<String, dynamic>>> getSalaryPeriods({
    required String tenantId,
    required String businessId,
    required String token,
    String? employeeId,
  }) => _businessRecords(
    collection: FirebaseConstants.salaryPeriods,
    tenantId: tenantId,
    businessId: businessId,
    token: token,
    employeeId: employeeId,
  );

  Future<List<Map<String, dynamic>>> getOutletAllocations({
    required String tenantId,
    required String businessId,
    required String token,
    String? employeeId,
  }) => _businessRecords(
    collection: FirebaseConstants.employeeOutletAllocations,
    tenantId: tenantId,
    businessId: businessId,
    token: token,
    employeeId: employeeId,
  );

  /// Records an employee's in-person acknowledgment on the approved salary
  /// period. The first acknowledgment is immutable; corrections need a new
  /// auditable payroll adjustment rather than overwriting the receipt.
  Future<void> acknowledgeSalaryStatement({
    required String tenantId,
    required String businessId,
    required String employeeId,
    required String periodId,
    required String acknowledgedByName,
    required String recordedBy,
    required String token,
  }) async {
    final emp = _safeId(employeeId);
    final name = acknowledgedByName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      throw const AppException('Enter the employee acknowledgment name.');
    }
    await atomicWrites.runAtomicOperation((tx) async {
      final period = await tx.get(
        FirebaseConstants.salaryPeriods,
        _safeId(periodId),
      );
      final periodTenant =
          period.fields['tenantId'] ?? period.fields['ownerUid'];
      if (!period.exists ||
          periodTenant != tenantId ||
          period.fields['businessId'] != businessId ||
          period.fields['employeeId'] != emp) {
        throw const AppException(
          'Salary statement not found for this employee.',
        );
      }
      if (period.fields['employeeAcknowledgedAt'] != null) {
        throw const AppException(
          'This salary statement has already been acknowledged.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      tx.update(FirebaseConstants.salaryPeriods, periodId, {
        'employeeAcknowledgedAt': now,
        'employeeAcknowledgmentName': name,
        'employeeAcknowledgmentMethod': 'IN_PERSON',
        'employeeAcknowledgmentRecordedBy': recordedBy,
        'updatedAt': now,
      }, updateTime: period.updateTime);
    }, idToken: token);
  }
}
