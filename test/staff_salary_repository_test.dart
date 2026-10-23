import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/repositories/staff_salary_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';

class _UnusedFirestore implements FirestoreDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeOfflineWithServerTx implements OfflineFirestoreService {
  _FakeOfflineWithServerTx(this._server);
  final FirestoreTransactionService _server;

  @override
  FirestoreTransactionService get serverTransactions => _server;

  @override
  LocalDataSource? get localDataSource => null;

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    throw const AppException(
      'Financial transactions must be confirmed directly by the server and cannot run in offline mode.',
      code: 'offline-financial-prohibited',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Transactions implements FirestoreTransactionService {
  final docs = <String, Map<String, dynamic>>{};
  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    final staged = Map<String, Map<String, dynamic>>.fromEntries(
      docs.entries.map(
        (e) => MapEntry(e.key, Map<String, dynamic>.from(e.value)),
      ),
    );
    final context = _TransactionView(staged);
    final result = await action(context);
    docs
      ..clear()
      ..addAll(staged);
    return result;
  }
}

class _TransactionView implements FirestoreTransactionContext {
  _TransactionView(this.docs);
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
      .where((value) => filters.every((f) => value[f.field] == f.value))
      .map((value) => FirestoreTransactionDocument(exists: true, fields: value))
      .toList();
  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    final key = '$collection/$id';
    if (docs.containsKey(key)) throw StateError('duplicate document $key');
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
    'monthly and daily calculations use integer paise and rounded work units',
    () {
      expect(
        StaffSalaryRepository.calculate(
          salaryType: 'MONTHLY',
          baseRatePaise: 3000000,
          monthlyBaseForPeriodPaise: 3000000,
          bonusPaise: 10000,
          overtimePaise: 5000,
          approvedDeductionsPaise: 2500,
        ),
        {
          'baseEarningsPaise': 3000000,
          'grossEarningsPaise': 3015000,
          'approvedDeductionsPaise': 2500,
          'netEarnedPaise': 3012500,
        },
      );
      final daily = StaffSalaryRepository.calculate(
        salaryType: 'DAILY',
        baseRatePaise: 125000,
        workUnitsMilli: 4500,
      );
      expect(daily['baseEarningsPaise'], 562500);
      expect(
        StaffSalaryRepository.previewPeriodCalculation(
          salaryType: 'MONTHLY',
          baseRatePaise: 3100000,
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 2, 28),
          workUnitsMilli: 0,
        )['baseEarningsPaise'],
          3100000,
      );
    },
  );

  test('effective outlet allocations reject any basis point total other than 10000', () async {
    final tx = _Transactions();
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    await expectLater(
      repo.saveOutletAllocation(
        tenantId: 'TENANT',
        businessId: 'BIZ',
        employeeId: 'EMP-1',
        effectiveFrom: DateTime.utc(2026, 10, 1),
        outletBasisPoints: {'OUT-1': 7000, 'OUT-2': 2999},
        createdBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<AppException>()),
    );
    expect(tx.docs, isEmpty);
  });

  test('salary profile IDs include business scope for employees shared across businesses', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
      'ownerUid': 'TENANT',
      'businessIds': ['BIZ-1', 'BIZ-2'],
      'outletIds': [],
    };
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    Future<String> profile(String businessId) => repo.saveSalaryProfile(
      tenantId: 'TENANT',
      businessId: businessId,
      employeeId: 'EMP-1',
      salaryType: 'DAILY',
      baseRatePaise: 100000,
      paymentCycle: 'WEEKLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: 'OWNER',
      token: 'token',
    );
    final first = await profile('BIZ-1');
    final second = await profile('BIZ-2');
    expect(first, isNot(second));
  });

  test(
    'approving the same earned period is idempotent and allocates expense once',
    () async {
      final tx = _Transactions();
      tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
        'ownerUid': 'TENANT',
        'businessIds': ['BIZ'],
        'outletIds': ['OUT'],
      };
      tx.docs['${FirebaseConstants.outlets}/OUT'] = {
        'tenantId': 'TENANT',
        'businessId': 'BIZ',
      };
      final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
      final profileId = await repo.saveSalaryProfile(
        tenantId: 'TENANT',
        businessId: 'BIZ',
        employeeId: 'EMP-1',
        salaryType: 'DAILY',
        baseRatePaise: 10000,
        paymentCycle: 'WEEKLY',
        effectiveFrom: DateTime.utc(2026, 10, 1),
        createdBy: 'OWNER',
        token: 'token',
      );
      final autoAllocation = tx.docs.values.singleWhere(
        (doc) => doc['allocationId'] is String,
      );
      expect(autoAllocation['outletBasisPoints'], {'OUT': 10000});
      Future<String> approve() => repo.approveSalaryPeriod(
        tenantId: 'TENANT',
        businessId: 'BIZ',
        employeeId: 'EMP-1',
        profileId: profileId,
        periodStart: DateTime.utc(2026, 10, 1),
        periodEnd: DateTime.utc(2026, 10, 7),
        workUnitsMilli: 5000,
        approvedBy: 'OWNER',
        token: 'token',
      );
      final periodId = await approve();
      expect(await approve(), periodId);
      final period = tx.docs['${FirebaseConstants.salaryPeriods}/$periodId']!;
      expect(period['expenseAmountPaise'], 50000);
      expect((period['outletExpensesPaise'] as Map).values.single, 50000);
      expect(
        tx.docs.keys.where(
          (key) => key.startsWith('${FirebaseConstants.salaryPeriods}/'),
        ),
        hasLength(1),
      );
      expect(
        tx.docs.keys.where(
          (key) =>
              key.startsWith('${FirebaseConstants.financialTransactions}/'),
        ),
        isEmpty,
      );
    },
  );

  test('salary period accepts approved attendance snapshot once and blocks reuse', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
      'ownerUid': 'TENANT',
      'businessIds': ['BIZ'],
      'outletIds': ['OUT'],
    };
    tx.docs['${FirebaseConstants.outlets}/OUT'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
    };
    tx.docs['${FirebaseConstants.staffAttendance}/ATT-1'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
      'employeeId': 'EMP-1',
      'workDate': DateTime.utc(2026, 10, 3).toIso8601String(),
      'approvalStatus': 'APPROVED',
      'payableUnitsMilli': 1000,
      'overtimePaise': 2000,
    };
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    final profileId = await repo.saveSalaryProfile(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      employeeId: 'EMP-1',
      salaryType: 'DAILY',
      baseRatePaise: 10000,
      paymentCycle: 'WEEKLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: 'OWNER',
      token: 'token',
    );
    final periodId = await repo.approveSalaryPeriod(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      employeeId: 'EMP-1',
      profileId: profileId,
      periodStart: DateTime.utc(2026, 10, 1),
      periodEnd: DateTime.utc(2026, 10, 7),
      workUnitsMilli: 1000,
      overtimePaise: 2000,
      attendanceRecordIds: ['ATT-1'],
      approvedBy: 'OWNER',
      token: 'token',
    );
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/$periodId']!['attendanceRecordIds'],
      ['ATT-1'],
    );
    await expectLater(
      repo.approveSalaryPeriod(
        tenantId: 'TENANT',
        businessId: 'BIZ',
        employeeId: 'EMP-1',
        profileId: profileId,
        periodStart: DateTime.utc(2026, 10, 2),
        periodEnd: DateTime.utc(2026, 10, 8),
        workUnitsMilli: 1000,
        overtimePaise: 2000,
        attendanceRecordIds: ['ATT-1'],
        approvedBy: 'OWNER',
        token: 'token',
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('staff invoice payments and salary offsets keep cash and payable separate', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
      'ownerUid': 'TENANT',
      'businessIds': ['BIZ'],
      'outletIds': ['OUT'],
    };
    tx.docs['${FirebaseConstants.outlets}/OUT'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
    };
    tx.docs['${FirebaseConstants.invoices}/INV-1'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
      'outletId': 'OUT',
      'employeeId': 'EMP-1',
      'outstandingAmount': 50000,
      'paidAmount': 0,
    };
    tx.docs['${FirebaseConstants.staffKhataTransactions}/PUR-1'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
      'employeeId': 'EMP-1',
      'transactionType': 'STORE_PURCHASE',
      'amountPaise': 50000,
      'status': 'POSTED',
    };
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    await repo.recordStaffPurchasePayment(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      outletId: 'OUT',
      employeeId: 'EMP-1',
      invoiceId: 'INV-1',
      amountPaise: 20000,
      paymentMode: 'CASH',
      requestId: 'PAY-1',
      recordedBy: 'OWNER',
      token: 'token',
    );
    await repo.recordStaffPurchasePayment(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      outletId: 'OUT',
      employeeId: 'EMP-1',
      invoiceId: 'INV-1',
      amountPaise: 20000,
      paymentMode: 'CASH',
      requestId: 'PAY-1',
      recordedBy: 'OWNER',
      token: 'token',
    );
    expect(
      tx.docs['${FirebaseConstants.invoices}/INV-1']!['outstandingAmount'],
      30000,
    );
    expect(
      tx.docs['${FirebaseConstants.financialTransactions}/FIN-SPAY-PAY-1']!['direction'],
      'IN',
    );
    expect(
      tx.docs['${FirebaseConstants.financialTransactions}/FIN-SPAY-PAY-1']!['amount'],
      20000,
    );
    final profileId = await repo.saveSalaryProfile(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      employeeId: 'EMP-1',
      salaryType: 'DAILY',
      baseRatePaise: 100000,
      paymentCycle: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: 'OWNER',
      token: 'token',
    );
    final periodId = await repo.approveSalaryPeriod(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      employeeId: 'EMP-1',
      profileId: profileId,
      periodStart: DateTime.utc(2026, 10, 1),
      periodEnd: DateTime.utc(2026, 10, 31),
      workUnitsMilli: 1000,
      approvedBy: 'OWNER',
      token: 'token',
    );
    await repo.adjustStaffPurchasesAgainstSalary(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      outletId: 'OUT',
      employeeId: 'EMP-1',
      periodId: periodId,
      amountPaise: 10000,
      requestId: 'OFF-1',
      approvedBy: 'OWNER',
      token: 'token',
    );
    await repo.adjustStaffPurchasesAgainstSalary(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      outletId: 'OUT',
      employeeId: 'EMP-1',
      periodId: periodId,
      amountPaise: 10000,
      requestId: 'OFF-1',
      approvedBy: 'OWNER',
      token: 'token',
    );
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/$periodId']!['staffPurchaseAdjustedPaise'],
      10000,
    );
    expect(
      tx.docs.keys.where(
        (key) => key.startsWith('${FirebaseConstants.financialTransactions}/'),
      ),
      hasLength(1),
    );
  });

  test(
    'advance creates one cash event; replaying its request cannot duplicate it',
    () async {
      final tx = _Transactions();
      tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
        'ownerUid': 'TENANT',
        'businessIds': ['BIZ'],
        'outletIds': ['OUT'],
      };
      final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
      final args = {
        'tenantId': 'TENANT',
        'businessId': 'BIZ',
        'outletId': 'OUT',
        'employeeId': 'EMP-1',
        'amountPaise': 25000,
        'date': DateTime.utc(2026, 10, 1),
        'paymentMode': 'CASH',
        'requestId': 'ADV-REQ-1',
        'createdBy': 'OWNER',
        'token': 'token',
      };
      Future<void> record() => repo.recordAdvance(
        tenantId: args['tenantId'] as String,
        businessId: args['businessId'] as String,
        outletId: args['outletId'] as String,
        employeeId: args['employeeId'] as String,
        amountPaise: args['amountPaise'] as int,
        date: args['date'] as DateTime,
        paymentMode: args['paymentMode'] as String,
        requestId: args['requestId'] as String,
        createdBy: args['createdBy'] as String,
        token: args['token'] as String,
      );
      await record();
      await record();
      expect(
        tx.docs.keys
            .where(
              (key) => key.startsWith(
                '${FirebaseConstants.staffKhataTransactions}/',
              ),
            )
            .length,
        1,
      );
      expect(
        tx.docs.keys
            .where(
              (key) =>
                  key.startsWith('${FirebaseConstants.financialTransactions}/'),
            )
            .length,
        1,
      );
    },
  );

  test('salary payments support partial settlement and request replay is idempotent', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-1'] = {
      'ownerUid': 'TENANT',
      'businessIds': ['BIZ'],
      'outletIds': ['OUT'],
    };
    tx.docs['${FirebaseConstants.outlets}/OUT'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
    };
    tx.docs['${FirebaseConstants.salaryPeriods}/PER-1'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
      'employeeId': 'EMP-1',
      'netEarnedPaise': 100000,
      'paidAmountPaise': 0,
      'advanceAdjustedPaise': 0,
      'status': 'APPROVED',
    };
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    Future<void> pay(String req, int amount) => repo.recordSalaryPayment(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      outletId: 'OUT',
      employeeId: 'EMP-1',
      periodId: 'PER-1',
      amountPaise: amount,
      date: DateTime.utc(2026, 10, 2),
      paymentMode: 'UPI',
      requestId: req,
      paidBy: 'OWNER',
      token: 'token',
    );
    await pay('PAY-1', 30000);
    await pay('PAY-1', 30000);
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['paidAmountPaise'],
      30000,
    );
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['status'],
      'PARTIALLY_PAID',
    );
    await pay('PAY-2', 70000);
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['paidAmountPaise'],
      100000,
    );
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['status'],
      'PAID',
    );
    expect(
      tx.docs.keys
          .where(
            (key) =>
                key.startsWith('${FirebaseConstants.financialTransactions}/'),
          )
          .length,
      2,
    );
    await expectLater(pay('PAY-3', 1), throwsA(isA<AppException>()));
    expect(
      tx.docs.keys
          .where(
            (key) =>
                key.startsWith('${FirebaseConstants.financialTransactions}/'),
          )
          .length,
      2,
    );
  });

  test('employee acknowledgment is recorded once and cannot be silently overwritten', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.salaryPeriods}/PER-1'] = {
      'tenantId': 'TENANT',
      'businessId': 'BIZ',
      'employeeId': 'EMP-1',
      'status': 'APPROVED',
    };
    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);
    Future<void> acknowledge(String name) => repo.acknowledgeSalaryStatement(
      tenantId: 'TENANT',
      businessId: 'BIZ',
      employeeId: 'EMP-1',
      periodId: 'PER-1',
      acknowledgedByName: name,
      recordedBy: 'OWNER',
      token: 'token',
    );
    await acknowledge('Worker');
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['employeeAcknowledgmentName'],
      'Worker',
    );
    await expectLater(
      acknowledge('Different name'),
      throwsA(isA<AppException>()),
    );
    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/PER-1']!['employeeAcknowledgmentName'],
      'Worker',
    );
  });

  test('outlets using ownerUid fallback rather than tenantId are accepted across salary operations', () async {
    final tx = _Transactions();
    // Employee with ownerUid, businessIds, outletIds
    tx.docs['${FirebaseConstants.employees}/EMP-MIRZA'] = {
      'ownerUid': 'TENANT-123',
      'businessIds': ['BIZ-1'],
      'outletIds': ['OUT-MIRZA'],
    };
    // Outlet with ownerUid (NO tenantId field), businessId
    tx.docs['${FirebaseConstants.outlets}/OUT-MIRZA'] = {
      'ownerUid': 'TENANT-123',
      'businessId': 'BIZ-1',
    };

    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);

    // 1. saveSalaryProfile with auto-allocation (no initial split provided)
    final profileId = await repo.saveSalaryProfile(
      tenantId: 'TENANT-123',
      businessId: 'BIZ-1',
      employeeId: 'EMP-MIRZA',
      salaryType: 'MONTHLY',
      baseRatePaise: 2500000,
      paymentCycle: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: 'OWNER-1',
      token: 'token',
    );
    expect(profileId, isNotEmpty);

    // Auto-allocation should have created 100% split for OUT-MIRZA
    final autoAllocations = tx.docs.values
        .where((d) => d['employeeId'] == 'EMP-MIRZA' && d['allocationId'] != null)
        .toList();
    expect(autoAllocations, hasLength(1));
    expect(autoAllocations.first['outletBasisPoints'], {'OUT-MIRZA': 10000});

    // 2. saveOutletAllocation with explicit split
    await repo.saveOutletAllocation(
      tenantId: 'TENANT-123',
      businessId: 'BIZ-1',
      employeeId: 'EMP-MIRZA',
      effectiveFrom: DateTime.utc(2026, 11, 1),
      outletBasisPoints: {'OUT-MIRZA': 10000},
      createdBy: 'OWNER-1',
      token: 'token',
    );

    // 3. approveSalaryPeriod
    final periodId = await repo.approveSalaryPeriod(
      tenantId: 'TENANT-123',
      businessId: 'BIZ-1',
      employeeId: 'EMP-MIRZA',
      profileId: profileId,
      periodStart: DateTime.utc(2026, 10, 1),
      periodEnd: DateTime.utc(2026, 10, 31),
      workUnitsMilli: 1000,
      approvedBy: 'OWNER-1',
      token: 'token',
    );
    expect(periodId, isNotEmpty);

    // 4. recordSalaryPayment
    await repo.recordSalaryPayment(
      tenantId: 'TENANT-123',
      businessId: 'BIZ-1',
      outletId: 'OUT-MIRZA',
      employeeId: 'EMP-MIRZA',
      periodId: periodId,
      amountPaise: 2500000,
      date: DateTime.utc(2026, 11, 1),
      paymentMode: 'CASH',
      requestId: 'REQ-1',
      paidBy: 'OWNER-1',
      token: 'token',
    );

    expect(
      tx.docs['${FirebaseConstants.salaryPeriods}/$periodId']!['status'],
      'PAID',
    );
  });

  test('advances set UPI_ADVANCE and BANK_ADVANCE khata transaction types according to paymentMode', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-UPI'] = {
      'ownerUid': 'TENANT-1',
      'businessIds': ['BIZ-1'],
      'outletIds': ['OUT-1'],
    };
    tx.docs['${FirebaseConstants.outlets}/OUT-1'] = {
      'ownerUid': 'TENANT-1',
      'businessId': 'BIZ-1',
    };

    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);

    await repo.recordAdvance(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      outletId: 'OUT-1',
      employeeId: 'EMP-UPI',
      amountPaise: 50000,
      date: DateTime.utc(2026, 10, 15),
      paymentMode: 'UPI',
      requestId: 'REQ-UPI-1',
      createdBy: 'OWNER-1',
      token: 'token',
    );

    final upiKhata = tx.docs.values.firstWhere(
      (d) => d['employeeId'] == 'EMP-UPI' && d['amountPaise'] == 50000,
    );
    expect(upiKhata['transactionType'], 'UPI_ADVANCE');

    await repo.recordAdvance(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      outletId: 'OUT-1',
      employeeId: 'EMP-UPI',
      amountPaise: 75000,
      date: DateTime.utc(2026, 10, 16),
      paymentMode: 'BANK_TRANSFER',
      requestId: 'REQ-BANK-1',
      createdBy: 'OWNER-1',
      token: 'token',
    );

    final bankKhata = tx.docs.values.firstWhere(
      (d) => d['employeeId'] == 'EMP-UPI' && d['amountPaise'] == 75000,
    );
    expect(bankKhata['transactionType'], 'BANK_ADVANCE');
  });

  test('outlet allocations and salary profiles allow updating existing records and ignore 0% splits', () async {
    final tx = _Transactions();
    tx.docs['${FirebaseConstants.employees}/EMP-ALLOC'] = {
      'ownerUid': 'TENANT-1',
      'businessIds': ['BIZ-1'],
      'outletIds': ['OUT-1', 'OUT-2'],
    };
    tx.docs['${FirebaseConstants.outlets}/OUT-1'] = {
      'ownerUid': 'TENANT-1',
      'businessId': 'BIZ-1',
    };
    tx.docs['${FirebaseConstants.outlets}/OUT-2'] = {
      'ownerUid': 'TENANT-1',
      'businessId': 'BIZ-1',
    };

    final repo = StaffSalaryRepository(_UnusedFirestore(), tx);

    // Initial allocation with 100% to OUT-1 and 0% to OUT-2
    await repo.saveOutletAllocation(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      employeeId: 'EMP-ALLOC',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      outletBasisPoints: {'OUT-1': 10000, 'OUT-2': 0},
      createdBy: 'OWNER-1',
      token: 'token',
    );

    final allocs = tx.docs.values
        .where((d) => d['employeeId'] == 'EMP-ALLOC' && d['allocationId'] != null)
        .toList();
    expect(allocs, hasLength(1));
    expect(allocs.first['outletBasisPoints'], {'OUT-1': 10000});

    // Update same allocation with 60% OUT-1 and 40% OUT-2 without throwing "already exists"
    await repo.saveOutletAllocation(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      employeeId: 'EMP-ALLOC',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      outletBasisPoints: {'OUT-1': 6000, 'OUT-2': 4000},
      createdBy: 'OWNER-1',
      token: 'token',
    );

    final updatedAllocs = tx.docs.values
        .where((d) => d['employeeId'] == 'EMP-ALLOC' && d['allocationId'] != null)
        .toList();
    expect(updatedAllocs, hasLength(1));
    expect(updatedAllocs.first['outletBasisPoints'], {'OUT-1': 6000, 'OUT-2': 4000});

    // Initial profile
    final profileId = await repo.saveSalaryProfile(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      employeeId: 'EMP-ALLOC',
      salaryType: 'MONTHLY',
      baseRatePaise: 3000000,
      paymentCycle: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      initialOutletBasisPoints: {'OUT-1': 10000, 'OUT-2': 0},
      createdBy: 'OWNER-1',
      token: 'token',
    );
    expect(profileId, isNotEmpty);

    // Update profile rate without throwing "already exists"
    await repo.saveSalaryProfile(
      tenantId: 'TENANT-1',
      businessId: 'BIZ-1',
      employeeId: 'EMP-ALLOC',
      salaryType: 'MONTHLY',
      baseRatePaise: 3500000,
      paymentCycle: 'MONTHLY',
      effectiveFrom: DateTime.utc(2026, 10, 1),
      createdBy: 'OWNER-1',
      token: 'token',
    );

    final prof = tx.docs['${FirebaseConstants.employeeSalaryProfiles}/$profileId'];
    expect(prof!['baseRatePaise'], 3500000);
  });

  test('financial salary operations route to serverTransactions and bypass offline outbox financial block', () async {
    final serverTx = _Transactions();
    serverTx.docs['${FirebaseConstants.employees}/EMP-FIN'] = {
      'tenantId': 'TENANT-FIN',
      'businessId': 'BIZ-FIN',
      'businessIds': ['BIZ-FIN'],
      'outletId': 'OUT-FIN',
      'outletIds': ['OUT-FIN'],
    };
    serverTx.docs['${FirebaseConstants.outlets}/OUT-FIN'] = {
      'tenantId': 'TENANT-FIN',
      'businessId': 'BIZ-FIN',
    };
    serverTx.docs['${FirebaseConstants.salaryPeriods}/PER-FIN'] = {
      'tenantId': 'TENANT-FIN',
      'businessId': 'BIZ-FIN',
      'employeeId': 'EMP-FIN',
      'status': 'APPROVED',
      'netEarnedPaise': 3000000,
      'paidAmountPaise': 0,
      'advanceAdjustedPaise': 0,
      'staffPurchaseAdjustedPaise': 0,
    };

    final offlineWithBlock = _FakeOfflineWithServerTx(serverTx);
    final repo = StaffSalaryRepository(offlineWithBlock, offlineWithBlock);

    // 1. Advance: would throw offline-financial-prohibited if called via atomicWrites, but succeeds via serverTransactions
    final advEventId = await repo.recordAdvance(
      tenantId: 'TENANT-FIN',
      businessId: 'BIZ-FIN',
      outletId: 'OUT-FIN',
      employeeId: 'EMP-FIN',
      amountPaise: 500000,
      date: DateTime.utc(2026, 10, 10),
      paymentMode: 'CASH',
      requestId: 'ADV-REQ-1',
      createdBy: 'OWNER-FIN',
      token: 'token',
    );
    expect(advEventId, 'SKH-ADV-ADV-REQ-1');
    expect(
      serverTx.docs['${FirebaseConstants.financialTransactions}/FIN-$advEventId']!['amount'],
      500000,
    );

    // 2. Salary Payment: would throw offline-financial-prohibited if called via atomicWrites, but succeeds via serverTransactions
    final payEventId = await repo.recordSalaryPayment(
      tenantId: 'TENANT-FIN',
      businessId: 'BIZ-FIN',
      outletId: 'OUT-FIN',
      employeeId: 'EMP-FIN',
      periodId: 'PER-FIN',
      amountPaise: 2500000,
      date: DateTime.utc(2026, 10, 15),
      paymentMode: 'UPI',
      requestId: 'SAL-PAY-REQ-1',
      paidBy: 'OWNER-FIN',
      token: 'token',
    );
    expect(payEventId, 'SKH-PAY-SAL-PAY-REQ-1');
    expect(
      serverTx.docs['${FirebaseConstants.salaryPeriods}/PER-FIN']!['paidAmountPaise'],
      2500000,
    );
    expect(
      serverTx.docs['${FirebaseConstants.salaryPeriods}/PER-FIN']!['status'],
      'PARTIALLY_PAID',
    );
    expect(
      serverTx.docs['${FirebaseConstants.financialTransactions}/FIN-SAL-SAL-PAY-REQ-1']!['amount'],
      2500000,
    );
  });
}
