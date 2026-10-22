import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/repositories/staff_salary_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';

class _UnusedFirestore implements FirestoreDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
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
}
