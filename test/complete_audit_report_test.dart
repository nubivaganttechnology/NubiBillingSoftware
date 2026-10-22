import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/repositories/reports_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/domain/reports/report_models.dart';
import 'package:testflutter/presentation/reports/audit_report_dialog.dart';
import 'package:testflutter/presentation/reports/report_export_service.dart';

class _ForbiddenRemote implements FirestoreRestService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Forbidden network: ${invocation.memberName}');
}

class _Offline implements ConnectivityService {
  @override
  bool available = false;
  @override
  Future<void> start(void Function(bool) onChange) async {}
  @override
  Future<void> dispose() async {}
}

class _NoSync extends SyncEngine {
  _NoSync(FirestoreRestService remote)
    : super(remote, _Offline(), sessionProvider: () async => null);
  @override
  void schedule({bool pull = false, String reason = 'OUTBOX'}) {}
}

class _Fixture {
  _Fixture(
    this.directory,
    this.database,
    this.source,
    this.service,
    this.sync,
    this.uid,
  );
  final Directory directory;
  final LocalDatabase database;
  final LocalDataSource source;
  final OfflineFirestoreService service;
  final _NoSync sync;
  final String uid;
  String get token =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': EnvironmentConfig.projectId})))}.signature';
  static Future<_Fixture> create({String uid = 'owner'}) async {
    final dir = await Directory.systemTemp.createTemp(
      'nubi-financial-disposable-',
    );
    final db = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    final remote = _ForbiddenRemote();
    final sync = _NoSync(remote);
    final service = OfflineFirestoreService(db, remote, sync);
    await service.activate(uid);
    final source = LocalDataSource(
      await db.open(EnvironmentConfig.projectId, uid),
    );
    final f = _Fixture(dir, db, source, service, sync, uid);
    await f.seed('user', uid, {
      'uid': uid,
      'accountType': uid == 'owner' ? 'owner' : 'employee',
      'isActive': true,
      'name': 'Fixture user',
      'email': 'fixture@example.invalid',
    });
    await f.seed('permissions', 'reports', {
      'permissionId': 'reports',
      'status': 'ACTIVE',
    });
    await f.seed('businesses', 'b1', {
      'businessId': 'b1',
      'ownerUid': 'owner',
      'businessName': 'Suman Enterprises',
      'gstin': '19ABCDE1234F1Z5',
      'isActive': true,
    });
    await f.seed('outlets', 'o1', {
      'outletId': 'o1',
      'businessId': 'b1',
      'ownerUid': 'owner',
      'tenantId': 'owner',
      'outletName': 'Kolkata Hardware Shop',
      'isActive': true,
    });
    await f.seed('outlets', 'o2', {
      'outletId': 'o2',
      'businessId': 'b1',
      'ownerUid': 'owner',
      'tenantId': 'owner',
      'outletName': 'Historical outlet with a long descriptive name for the financial comparison table',
      'isActive': false,
    });
    if (uid != 'owner')
      await f.seed('employees', 'emp', {
        'uid': uid,
        'ownerUid': 'owner',
        'status': 'ACTIVE',
        'businessIds': ['b1'],
        'outletIds': ['o1'],
        'permissionIds': ['reports'],
      });
    for (final collection in LocalDatabase.tables.keys) {
      await source.db.insert('sync_queries', {
        'queryKey': 'fixture-$collection',
        'collectionName': collection,
        'queryJson': jsonEncode({'filters': []}),
        'lastSyncedAt': '2026-10-21T00:00:00Z',
        'cursor': 'preserve-$collection',
      });
    }
    return f;
  }

  Future<void> seed(String collection, String id, Map<String, dynamic> data) =>
      source.upsertRemote(collection, [
        {
          'name': '$collection/$id',
          'fields': FirestoreRestService.encodeFields({
            if (collection == 'inventory_batch_movements') ...{
              'variantId': 'v1',
              'referenceType': data['movementType'] == 'SALE'
                  ? 'SALES_INVOICE'
                  : data['movementType'] == 'PURCHASE_RECEIPT'
                  ? 'GOODS_RECEIPT'
                  : 'RETURN_OR_TRANSFER',
              'referenceId': data['movementType'] == 'SALE'
                  ? 'i1'
                  : data['movementType'] == 'PURCHASE_RECEIPT'
                  ? 'grn1'
                  : 'return',
            },
            ...data,
          }),
          'updateTime': '2026-10-21T00:00:00Z',
        },
      ]);
  Map<String, dynamic> scoped([String outlet = 'o1']) => {
    'tenantId': 'owner',
    'businessId': 'b1',
    'outletId': outlet,
  };
  Future<void> baseline({int soldQuantity = 2000}) async {
    await seed('invoices', 'i1', {
      ...scoped(),
      'invoiceNumber': 'INV-1',
      'createdAt': '2026-10-20T18:29:59.999999Z',
      'status': 'PAID',
      'taxablePaise': 680000,
      'discountPaise': 10000,
      'cgstPaise': 45000,
      'sgstPaise': 45000,
      'igstPaise': 0,
      'grandTotalPaise': 770000,
      'dueAmount': 0,
      'items': [
        {
          'variantId': 'v1',
          'hsn': '8201',
          'unit': 'NOS',
          'quantity': soldQuantity / 2000,
          'quantityBase': soldQuantity / 2000,
          'taxablePaise': 180000,
          'gstRateBps': 0,
          'taxClassification': 'NIL_RATED',
          'cgstPaise': 0,
          'sgstPaise': 0,
          'taxPaise': 0,
        },
        {
          'variantId': 'v1',
          'hsn': '8201',
          'unit': 'NOS',
          'quantity': soldQuantity / 2000,
          'quantityBase': soldQuantity / 2000,
          'taxablePaise': 500000,
          'gstRateBps': 1800,
          'cgstPaise': 45000,
          'sgstPaise': 45000,
          'taxPaise': 90000,
        },
      ],
    });
    await seed('purchase_bills', 'p1', {
      ...scoped(),
      'purchaseBillId': 'p1',
      'invoiceDate': '2026-10-01',
      'status': 'APPROVED',
      'taxableAmount': 100000,
      'cgstAmount': 9000,
      'sgstAmount': 9000,
      'igstAmount': 0,
      'chargesAmount': 0,
      'grandTotal': 118000,
      'outstandingAmount': 68000,
      'items': [
        {
          'goodsReceiptItemId': 'pi1',
          'variantId': 'v1',
          'quantity': 10000,
          'baseQuantity': 10000,
          'conversionFactor': 1000,
          'taxableAmount': 100000,
        },
      ],
    });
    await seed('goods_receipts', 'grn1', {
      ...scoped(),
      'goodsReceiptId': 'grn1',
      'status': 'APPROVED',
      'purchaseBillId': 'p1',
    });
    await seed('inventory_batches', 'batch1', {
      ...scoped(),
      'batchId': 'batch1',
      'purchaseId': 'p1',
      'purchaseItemId': 'pi1',
      'variantId': 'v1',
      'availableQty': 10000 - soldQuantity,
      'receivedQty': 10000,
      'status': 'AVAILABLE',
    });
    await seed('inventory_batch_movements', 'receipt', {
      ...scoped(),
      'batchId': 'batch1',
      'variantId': 'v1',
      'movementId': 'receipt',
      'quantity': 10000,
      'direction': 'IN',
      'movementType': 'PURCHASE_RECEIPT',
      'occurredAt': '2026-10-01',
      'status': 'POSTED',
    });
    await seed('inventory_batch_movements', 'sale', {
      ...scoped(),
      'batchId': 'batch1',
      'variantId': 'v1',
      'movementId': 'sale',
      'quantity': soldQuantity,
      'direction': 'OUT',
      'movementType': 'SALE',
      'occurredAt': '2026-10-20',
      'status': 'POSTED',
      'referenceId': 'i1',
    });
    await seed('stock_balances', 's1', {
      ...scoped(),
      'variantId': 'v1',
      'quantityOnHand': 10000 - soldQuantity,
    });
  }

  Future<FinancialAuditReportData> report({
    AuditScopeSelection scope = const AuditScopeSelection(),
    bool salary = true,
    String displayName = 'Suman Enterprises',
  }) => ReportsRepository(service).loadCompleteAuditReport(
    tenantId: 'owner',
    businessId: 'b1',
    outletId: 'o1',
    businessName: displayName,
    outletName: 'Kolkata Hardware Shop',
    dateRange: ReportDateRange(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 20),
      preset: DateRangePreset.custom,
    ),
    token: token,
    scope: scope,
    includeSalaryData: salary,
  );
  Future<String> databaseImage() async {
    final all = <String, Object?>{};
    for (final table in [
      ...LocalDatabase.tables.values,
      'sync_outbox',
      'sync_queries',
      'sync_conflicts',
    ]) {
      all[table] = await source.db.query(
        table,
        orderBy: table == 'sync_queries'
            ? 'queryKey'
            : table.startsWith('local_')
            ? 'remoteId'
            : 'id',
      );
    }
    return jsonEncode(all);
  }

  Future<void> close() async {
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
  }
}

AuditSchedule _section(FinancialAuditReportData r, String title) =>
    r.reconciliation!.schedules.firstWhere((s) => s.title == title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late _Fixture f;
  setUp(() async {
    f = await _Fixture.create();
  });
  tearDown(() => f.close());

  test('AUDIT-001/002 reference arithmetic exposes imbalance; missing source opening is never estimated', () async {
    expect(4250595000 + 5198136 - 5000700000, -744906864);
    expect(442000 - (-744906864), 745348864);
    await f.seed('stock_balances', 'legacy', {
      ...f.scoped(),
      'variantId': 'v1',
      'quantityOnHand': 50007000,
      'purchaseRate': 100,
    });
    final report = await f.report();
    expect(report.reconciliation!.metrics['Opening inventory'], isNull);
    expect(report.reconciliation!.metrics['Batch cost of sales'], isNull);
    expect(report.reconciliation!.metrics['Gross profit / loss'], isNull);
    expect(report.auditHealthScore, lessThan(100));
    expect(
      report.auditorExecutiveSummary,
      isNot(contains('Ready for Instant Filing')),
    );
  });
  test('AUDIT-003/004 complete embedded snapshots reconcile 6800 with all HSN/rate rows; discount is not subtracted twice', () async {
    await f.baseline();
    final r = await f.report();
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], 680000);
    expect(r.reconciliation!.metrics['Observed output GST'], 90000);
    expect(
      r.reconciliation!.metrics['Observed purchase GST (not eligible ITC)'],
      18000,
    );
    expect(r.reconciliation!.metrics['Eligible ITC'], isNull);
    final gst = _section(r, 'GST rate and classification reconciliation');
    expect(gst.rows.length, 3);
    expect(
      gst.rows.map((r) => r[2]),
      containsAll(['INR 1800.00', 'INR 5000.00']),
    );
    expect(
      _section(r, 'HSN / SAC reconciliation').rows.map((r) => r[1]).join(' '),
      contains('8201 / NOS / 1.0'),
    );
  });
  test('validated batch receipt costs yield independent COGS and balanced trading calculation', () async {
    await f.baseline();
    final r = await f.report();
    final m = r.reconciliation!.metrics;
    expect(m['Opening inventory'], 0);
    expect(m['Closing inventory'], 80000);
    expect(m['Batch cost of sales'], 20000);
    expect(m['Periodic inventory equation'], 20000);
    expect(m['COGS reconciliation difference'], 0);
    expect(m['Gross profit / loss'], 660000);
    expect(m['Total balance sheet assets'], isNull);
    expect(m['Capital and retained earnings'], isNull);
  });
  test('India date range includes final microsecond and excludes next day; undated sales block reliable revenue', () async {
    await f.baseline();
    await f.seed('invoices', 'next-day', {
      ...f.scoped(),
      'createdAt': '2026-10-20T18:30:00Z',
      'status': 'PAID',
      'taxablePaise': 999,
    });
    expect(
      (await f.report()).reconciliation!.metrics['Net revenue excluding GST'],
      680000,
    );
    await f.seed('invoices', 'undated', {
      ...f.scoped(),
      'status': 'PAID',
      'taxablePaise': 999,
    });
    expect(
      (await f.report()).reconciliation!.metrics['Net revenue excluding GST'],
      isNull,
    );
  });
  test('zero-sales empty synchronized period is zero observed activity and not certified balance sheet', () async {
    final r = await f.report();
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], 0);
    expect(r.reconciliation!.metrics['Batch cost of sales'], 0);
    expect(r.reconciliation!.metrics['Closing cash and bank'], isNull);
    expect(r.auditReadiness, 'INSUFFICIENT DATA');
    expect(r.auditHealthScore, lessThan(100));
  });
  test('missing synchronization evidence is not a zero-activity report and leaves cursors untouched', () async {
    await f.source.db.delete(
      'sync_queries',
      where: 'collectionName=?',
      whereArgs: ['invoices'],
    );
    final before = await f.databaseImage();
    final r = await f.report();
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], isNull);
    expect(await f.databaseImage(), before);
  });
  test('negative stock and mixed thousandths are exposed without silently scaling balances', () async {
    await f.baseline();
    await f.seed('stock_balances', 's1', {
      ...f.scoped(),
      'variantId': 'v1',
      'quantityOnHand': -1,
    });
    final r = await f.report();
    expect(r.reconciliation!.metrics['Closing inventory'], isNull);
    expect(
      _section(
        r,
        'Exceptions and unresolved differences',
      ).rows.any((r) => r[1] == 'STOCK_BATCH_QUANTITY_MISMATCH'),
      isTrue,
    );
  });
  test(
    'unknown GST never defaults to 0 or 18 and missing HSN remains visible',
    () async {
      await f.seed('invoices', 'missing-gst', {
        ...f.scoped(),
        'status': 'PAID',
        'createdAt': '2026-10-10',
        'taxablePaise': 10000,
        'grandTotalPaise': 10000,
        'cgstPaise': 0,
        'sgstPaise': 0,
        'igstPaise': 0,
        'items': [
          {'quantity': 1, 'taxablePaise': 10000},
        ],
      });
      final r = await f.report();
      expect(
        r.reconciliation!.checks
            .firstWhere((c) => c.id == 'GST and HSN completeness')
            .status,
        'NOT_VERIFIED',
      );
      expect(
        _section(r, 'GST rate and classification reconciliation').rows.first[1],
        'UNKNOWN',
      );
      expect(
        _section(r, 'HSN / SAC reconciliation').rows.first[1],
        contains('MISSING'),
      );
    },
  );
  test('all outlets include historical outlets and business rent once; single outlet does not invent allocation', () async {
    await f.baseline();
    await f.seed('expenses', 'rent', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'category': 'Rent & Lease',
      'amountPaise': 12000,
      'expenseDate': '2026-10-10',
      'status': 'ACTIVE',
      'paymentMode': 'BANK_TRANSFER',
    });
    final all = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(all.outletId.split(','), containsAll(['o1', 'o2']));
    expect(all.reconciliation!.metrics['Operating expenses'], 12000);
    expect(
      all
          .reconciliation!
          .metrics['Unallocated business overhead included once'],
      12000,
    );
    expect(
      (await f.report()).reconciliation!.metrics['Operating expenses'],
      isNull,
    );
  });
  test('approved salary is accrued once with saved 60/40 allocations; advances and settlements are cash/receivable events', () async {
    await f.baseline();
    await f.seed('salary_periods', 'period', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'periodId': 'period',
      'status': 'PARTIALLY_PAID',
      'periodStart': '2026-10-01',
      'periodEnd': '2026-10-20',
      'expenseAmountPaise': 30000,
      'netEarnedPaise': 30000,
      'outletExpensesPaise': {'o1': 18000, 'o2': 12000},
      'paidAmountPaise': 5000,
      'advanceAdjustedPaise': 2000,
    });
    for (final e in [
      ('advance', 'CASH_ADVANCE', 10000),
      ('salary', 'SALARY_PAYMENT', 5000),
      ('adjustment', 'ADVANCE_ADJUSTMENT', 2000),
      ('offset', 'STORE_CREDIT_ADJUSTMENT', 6000),
    ]) {
      final cash = e.$1 == 'advance' || e.$1 == 'salary';
      await f.seed('staff_khata_transactions', e.$1, {
        ...f.scoped(),
        'recordId': e.$1,
        'periodId': 'period',
        'status': 'POSTED',
        'transactionType': e.$2,
        'amountPaise': e.$3,
        'transactionDate': '2026-10-20',
        'paymentMode': cash ? 'CASH' : 'NON_CASH',
        'financialTransactionId': cash ? e.$1 : null,
      });
      if (cash)
        await f.seed('financial_transactions', e.$1, {
          ...f.scoped(),
          'transactionId': e.$1,
          'referenceId': e.$1,
          'transactionType': e.$1 == 'salary'
              ? 'SALARY_PAYMENT'
              : 'STAFF_ADVANCE',
          'amount': e.$3,
          'direction': 'OUT',
          'status': 'POSTED',
          'paymentMode': 'CASH',
          'transactionDate': '2026-10-20',
        });
    }
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(r.reconciliation!.metrics['Accrued salary expense'], 30000);
    expect(
      r.reconciliation!.metrics['Accrued salary payable (business scope only)'],
      17000,
    );
    expect(
      r
          .reconciliation!
          .metrics['Employee advance receivables (observed events)'],
      8000,
    );
    expect(
      r.reconciliation!.metrics['Observed cash / bank net movement'],
      -15000,
    );
    final outlet = _section(r, 'Outlet financial comparison');
    expect(
      outlet.rows.map((r) => r[4]),
      containsAll(['INR 180.00', 'INR 120.00']),
    );
  });
  test(
    'salary earning-period overlap is insufficient rather than prorated',
    () async {
      await f.seed('salary_periods', 'overlap', {
        'tenantId': 'owner',
        'businessId': 'b1',
        'status': 'APPROVED',
        'periodStart': '2026-09-20',
        'periodEnd': '2026-10-10',
        'expenseAmountPaise': 10000,
        'netEarnedPaise': 10000,
        'outletExpensesPaise': {'o1': 10000},
      });
      expect(
        (await f.report()).reconciliation!.metrics['Accrued salary expense'],
        isNull,
      );
    },
  );
  test('posted cash links are not double counted and staff purchase offsets are noncash', () async {
    await f.baseline();
    await f.seed('payments', 'cash', {
      'invoiceId': 'i1',
      'mode': 'CASH',
      'amountPaise': 20000,
      'createdAt': '2026-10-20',
    });
    await f.seed('payments', 'advance-offset', {
      'invoiceId': 'i1',
      'mode': 'ADVANCE',
      'amountPaise': 10000,
      'createdAt': '2026-10-20',
    });
    await f.seed('supplier_payments', 'pay', {
      ...f.scoped(),
      'paymentId': 'pay',
      'amount': 5000,
      'status': 'POSTED',
      'paymentDate': '2026-10-20',
      'paymentMode': 'UPI',
    });
    await f.seed('financial_transactions', 'fin', {
      ...f.scoped(),
      'referenceId': 'pay',
      'amount': 5000,
      'transactionType': 'SUPPLIER_PAYMENT',
      'direction': 'OUT',
      'status': 'POSTED',
      'transactionDate': '2026-10-20',
      'paymentMode': 'UPI',
    });
    expect(
      (await f.report())
          .reconciliation!
          .metrics['Observed cash / bank net movement'],
      15000,
    );
  });
  test('authorized selected outlets exclude unselected outlets and reject foreign outlet selection', () async {
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.selectedOutletsInBusiness,
        outletsByBusiness: {
          'b1': ['o2'],
        },
      ),
    );
    expect(r.outletId, 'o2');
    await expectLater(
      f.report(
        scope: const AuditScopeSelection(
          mode: AuditScopeMode.selectedOutletsInBusiness,
          outletsByBusiness: {
            'b1': ['foreign'],
          },
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      f.report(
        scope: const AuditScopeSelection(
          mode: AuditScopeMode.combinedAuthorizedBusinesses,
          outletsByBusiness: {'foreign': []},
        ),
      ),
      throwsStateError,
    );
  });
  test('employee reports respect outlet access and cannot include confidential payroll', () async {
    final staff = await _Fixture.create(uid: 'staff');
    try {
      await staff.seed('salary_periods', 'secret', {
        'tenantId': 'owner',
        'businessId': 'b1',
        'employeeId': 'SECRET_EMPLOYEE',
        'netEarnedPaise': 87654321,
      });
      final r = await staff.report(
        scope: const AuditScopeSelection(
          mode: AuditScopeMode.allOutletsInBusiness,
        ),
      );
      expect(r.outletId, 'o1');
      expect(r.reconciliation!.metrics['Accrued salary expense'], isNull);
      expect(
        jsonEncode(r.reconciliation!.schedules.map((s) => s.rows).toList()),
        isNot(contains('SECRET_EMPLOYEE')),
      );
      expect(
        _section(
          r,
          'Business and outlet inclusion',
        ).rows.any((r) => r[4] == 'EXCLUDED: no permission'),
        isTrue,
      );
    } finally {
      await staff.close();
    }
  });
  test('internal transfer without historical cost link is disclosed and never treated as external purchase', () async {
    await f.baseline();
    await f.seed('inventory_batch_movements', 'transfer', {
      ...f.scoped(),
      'batchId': 'batch1',
      'movementId': 'transfer',
      'quantity': 1000,
      'direction': 'OUT',
      'movementType': 'TRANSFER_OUT',
      'occurredAt': '2026-10-20',
      'status': 'POSTED',
      'referenceId': 'transfer1',
    });
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(_section(r, 'Internal transfer eliminations').rows, isNotEmpty);
    expect(r.reconciliation!.metrics['Net purchases excluding GST'], 100000);
    expect(r.reconciliation!.metrics['Batch cost of sales'], isNull);
  });
  test(
    'pending writes and cursors survive a full financial report unchanged',
    () async {
      await f.baseline();
      await f.source.db.update(
        'local_invoices',
        {'syncStatus': 'PENDING_UPDATE'},
        where: 'remoteId=?',
        whereArgs: ['i1'],
      );
      await f.source.db.insert('sync_outbox', {
        'batchId': 'pending',
        'entityType': 'invoices',
        'documentId': 'i1',
        'operation': 'UPDATE',
        'tenantId': 'owner',
        'businessId': 'b1',
        'outletId': 'o1',
        'payloadJson': '{}',
        'readSetJson': '{}',
        'localRevision': 1,
        'createdAt': '2026-10-21',
        'status': 'PENDING',
      });
      final before = await f.databaseImage();
      final r = await f.report();
      expect(r.reconciliation!.checks.last.status, 'NOT_VERIFIED');
      expect(await f.databaseImage(), before);
    },
  );
  test(
    'purchase and sales returns reverse revenue, input tax and batch cost once',
    () async {
      await f.baseline();
      await f.seed('invoices', 'return', {
        ...f.scoped(),
        'invoiceNumber': 'CR-1',
        'createdAt': '2026-10-20',
        'status': 'POSTED',
        'documentType': 'SALES_RETURN',
        'taxablePaise': 100000,
        'cgstPaise': 0,
        'sgstPaise': 0,
        'igstPaise': 0,
        'grandTotalPaise': 100000,
        'items': [
          {
            'hsn': '8201',
            'unit': 'NOS',
            'quantity': 0.5,
            'variantId': 'v1',
            'quantityBase': 0.5,
            'gstRateBps': 0,
            'taxClassification': 'NIL_RATED',
            'taxablePaise': 100000,
            'cgstPaise': 0,
            'sgstPaise': 0,
            'taxPaise': 0,
          },
        ],
      });
      await f.seed('purchase_returns', 'return', {
        ...f.scoped(),
        'returnDate': '2026-10-20',
        'status': 'APPROVED',
        'taxableAmount': 10000,
        'cgstAmount': 900,
        'sgstAmount': 900,
        'igstAmount': 0,
      });
      await f.seed('inventory_batch_movements', 'purchase-return', {
        ...f.scoped(),
        'batchId': 'batch1',
        'movementId': 'purchase-return',
        'quantity': 1000,
        'direction': 'OUT',
        'movementType': 'PURCHASE_RETURN',
        'occurredAt': '2026-10-20',
        'status': 'POSTED',
      });
      await f.seed('inventory_batch_movements', 'sale-return', {
        ...f.scoped(),
        'batchId': 'batch1',
        'movementId': 'sale-return',
        'quantity': 500,
        'direction': 'IN',
        'movementType': 'SALE_RETURN',
        'occurredAt': '2026-10-20',
        'status': 'POSTED',
      });
      await f.seed('inventory_batches', 'batch1', {
        ...f.scoped(),
        'batchId': 'batch1',
        'purchaseId': 'p1',
        'purchaseItemId': 'pi1',
        'variantId': 'v1',
        'availableQty': 7500,
        'status': 'AVAILABLE',
      });
      await f.seed('stock_balances', 's1', {
        ...f.scoped(),
        'variantId': 'v1',
        'quantityOnHand': 7500,
      });
      final m = (await f.report()).reconciliation!.metrics;
      expect(m['Net revenue excluding GST'], 580000);
      expect(m['Net purchases excluding GST'], 90000);
      expect(m['Observed purchase GST (not eligible ITC)'], 16200);
      expect(m['Batch cost of sales'], 15000);
      expect(m['COGS reconciliation difference'], 0);
    },
  );
  test('material trading discrepancy blocks a clean conclusion without fallback COGS', () async {
    await f.baseline();
    final row = await f.source.row('purchase_bills', 'p1');
    final bill = FirestoreRestService.decodeFields(
      jsonDecode(row!['payloadJson'] as String),
    );
    await f.source.db.update(
      'local_purchase_bills',
      {
        'payloadJson': jsonEncode(
          FirestoreRestService.encodeFields({
            ...bill,
            'invoiceDate': '2026-09-20',
          }),
        ),
      },
      where: 'remoteId=?',
      whereArgs: ['p1'],
    );
    final r = await f.report();
    expect(r.reconciliation!.metrics['Periodic inventory equation'], -80000);
    expect(
      r.reconciliation!.metrics['COGS reconciliation difference'],
      -100000,
    );
    expect(r.auditReadiness, 'NOT RECONCILED');
    expect(r.reconciliation!.metrics['Gross profit / loss'], isNull);
    expect(r.cogsPaise, 20000);
  });
  test(
    'zero closing stock remains zero with a complete batch history',
    () async {
      await f.baseline(soldQuantity: 10000);
      final r = await f.report();
      expect(r.reconciliation!.metrics['Closing inventory'], 0);
      expect(r.reconciliation!.metrics['Batch cost of sales'], 100000);
    },
  );
  test('explicit authorized businesses combine while distinct GST identities retain separate schedules', () async {
    await f.baseline();
    await f.seed('businesses', 'b2', {
      'businessId': 'b2',
      'ownerUid': 'owner',
      'businessName': 'Second authorized business',
      'gstin': '19ABCDE1234F1Z5',
    });
    await f.seed('outlets', 'o3', {
      'outletId': 'o3',
      'businessId': 'b2',
      'ownerUid': 'owner',
      'tenantId': 'owner',
      'outletName': 'Second business outlet',
    });
    await f.seed('invoices', 'i2', {
      'tenantId': 'owner',
      'businessId': 'b2',
      'outletId': 'o3',
      'invoiceNumber': 'INV-2',
      'createdAt': '2026-10-20',
      'status': 'POSTED',
      'taxablePaise': 50000,
      'cgstPaise': 0,
      'sgstPaise': 0,
      'igstPaise': 0,
      'grandTotalPaise': 50000,
      'items': [
        {
          'hsn': '8201',
          'unit': 'NOS',
          'quantity': 1,
          'quantityBase': 1,
          'taxablePaise': 50000,
          'cgstPaise': 0,
          'sgstPaise': 0,
          'taxPaise': 0,
          'gstRateBps': 0,
          'taxClassification': 'NIL_RATED',
        },
      ],
    });
    const scope = AuditScopeSelection(
      mode: AuditScopeMode.combinedAuthorizedBusinesses,
      outletsByBusiness: {'b1': [], 'b2': []},
    );
    final r = await f.report(scope: scope);
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], 730000);
    expect(r.outletId.split(','), containsAll(['o1', 'o2', 'o3']));
    await f.seed('businesses', 'b2', {
      'businessId': 'b2',
      'ownerUid': 'owner',
      'businessName': 'Second authorized business',
      'gstin': '27ABCDE1234F1Z5',
    });
    final distinct = await f.report(scope: scope);
    expect(distinct.gstin, contains('MULTIPLE GST IDENTITIES'));
    expect(
      _section(
        distinct,
        'GST rate and classification reconciliation',
      ).rows.map((r) => r[0]).join(' '),
      contains('b2'),
    );
  });
  test('unpaid salary accrues without cash outflow and missing approved profile coverage is disclosed', () async {
    await f.seed('salary_periods', 'unpaid', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'periodId': 'unpaid',
      'status': 'APPROVED',
      'periodStart': '2026-10-01',
      'periodEnd': '2026-10-20',
      'expenseAmountPaise': 20000,
      'netEarnedPaise': 20000,
      'outletExpensesPaise': {'o1': 20000},
    });
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(r.reconciliation!.metrics['Accrued salary expense'], 20000);
    expect(
      r.reconciliation!.metrics['Accrued salary payable (business scope only)'],
      20000,
    );
    expect(r.reconciliation!.metrics['Observed cash / bank net movement'], 0);
    await f.seed('employee_salary_profiles', 'profile', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'profileId': 'profile',
      'effectiveFrom': '2026-10-01',
      'status': 'ACTIVE',
    });
    expect(
      (await f.report()).reconciliation!.metrics['Accrued salary expense'],
      isNull,
    );
  });
  test('internal transfer invoice and bill are excluded from external totals while persisted GST is retained', () async {
    await f.baseline();
    await f.seed('invoices', 'transfer-sale', {
      ...f.scoped(),
      'invoiceNumber': 'TR-1',
      'createdAt': '2026-10-20',
      'status': 'PENDING',
      'isInternalTransfer': true,
      'taxablePaise': 50000,
      'cgstPaise': 4500,
      'sgstPaise': 4500,
      'igstPaise': 0,
      'grandTotalPaise': 59000,
      'dueAmount': 59000,
      'items': [
        {
          'variantId': 'v1',
          'hsn': '8201',
          'unit': 'NOS',
          'quantity': 1,
          'quantityBase': 1,
          'gstRateBps': 1800,
          'taxablePaise': 50000,
          'cgstPaise': 4500,
          'sgstPaise': 4500,
          'taxPaise': 9000,
        },
      ],
    });
    await f.seed('purchase_bills', 'transfer-purchase', {
      ...f.scoped('o2'),
      'purchaseBillId': 'transfer-purchase',
      'invoiceDate': '2026-10-20',
      'status': 'APPROVED',
      'isInternalTransfer': true,
      'taxableAmount': 50000,
      'cgstAmount': 4500,
      'sgstAmount': 4500,
      'igstAmount': 0,
      'chargesAmount': 0,
      'grandTotal': 59000,
      'outstandingAmount': 59000,
    });
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], 680000);
    expect(r.reconciliation!.metrics['Net purchases excluding GST'], 100000);
    expect(r.reconciliation!.metrics['Observed output GST'], 99000);
    expect(_section(r, 'Internal transfer eliminations').rows.length, 2);
    expect(_section(r, 'Customer receivables and aging').rows, isEmpty);
    expect(_section(r, 'Supplier payables and aging').rows.length, 1);
  });
  test(
    'void financial reference does not suppress a posted supplier payment',
    () async {
      await f.seed('supplier_payments', 'real', {
        ...f.scoped(),
        'paymentId': 'real',
        'amount': 5000,
        'status': 'POSTED',
        'paymentDate': '2026-10-20',
        'paymentMode': 'UPI',
      });
      await f.seed('financial_transactions', 'void', {
        ...f.scoped(),
        'referenceId': 'real',
        'amount': 5000,
        'direction': 'OUT',
        'status': 'VOID',
        'transactionDate': '2026-10-20',
        'paymentMode': 'UPI',
      });
      expect(
        (await f.report())
            .reconciliation!
            .metrics['Observed cash / bank net movement'],
        -5000,
      );
    },
  );
  test('pending deletion and limited sync downloads are disclosed without clearing the outbox', () async {
    await f.source.db.insert('sync_outbox', {
      'batchId': 'delete',
      'entityType': 'invoices',
      'documentId': 'gone',
      'operation': 'DELETE',
      'tenantId': 'owner',
      'businessId': 'b1',
      'outletId': 'o1',
      'payloadJson': '{}',
      'readSetJson': '{}',
      'localRevision': 1,
      'createdAt': '2026-10-21',
      'status': 'PENDING',
    });
    await f.source.db.update(
      'sync_queries',
      {
        'queryJson': jsonEncode({'filters': [], 'limit': 10}),
      },
      where: 'collectionName=?',
      whereArgs: ['invoices'],
    );
    final before = await f.databaseImage();
    final r = await f.report();
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], isNull);
    expect(
      _section(
        r,
        'Data completeness and sync checkpoints',
      ).rows.any((r) => r[0] == 'b1/o1/invoices' && r[4] == '1 / 0'),
      isTrue,
    );
    expect(await f.databaseImage(), before);
  });
  test(
    'disabled reporting permission and empty selected outlet lists fail closed',
    () async {
      await expectLater(
        f.report(
          scope: const AuditScopeSelection(
            mode: AuditScopeMode.selectedOutletsInBusiness,
          ),
        ),
        throwsArgumentError,
      );
      final staff = await _Fixture.create(uid: 'staff');
      try {
        await staff.seed('permissions', 'reports', {
          'permissionId': 'reports',
          'status': 'INACTIVE',
        });
        await expectLater(staff.report(), throwsStateError);
      } finally {
        await staff.close();
      }
    },
  );
  test('post-period invoice edit cannot be presented as a verified historical amount', () async {
    await f.baseline();
    final row = await f.source.row('invoices', 'i1');
    final invoice = FirestoreRestService.decodeFields(
      jsonDecode(row!['payloadJson'] as String),
    );
    await f.seed('invoices', 'i1', {
      ...invoice,
      'updatedAt': '2026-10-21T00:00:00Z',
    });
    final r = await f.report();
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], isNull);
    expect(
      _section(
        r,
        'Exceptions and unresolved differences',
      ).rows.any((r) => r[1] == 'POST_PERIOD_INVOICE_CHANGE'),
      isTrue,
    );
  });
  test(
    'scope choices include historical outlets and enforce employee assignments',
    () async {
      final choices = await ReportsRepository(f.service)
          .loadAuditScopeOptions(tenantId: 'owner', token: f.token);
      expect(choices.outlets.any((o) => o.id == 'o2' && !o.isActive), isTrue);
      final staff = await _Fixture.create(uid: 'staff');
      try {
        final allowed = await ReportsRepository(staff.service)
            .loadAuditScopeOptions(tenantId: 'owner', token: staff.token);
        expect(allowed.outlets.map((o) => o.id), ['o1']);
      } finally {
        await staff.close();
      }
    },
  );
  test('unallocated operating rent does not invalidate independently supported trading costs', () async {
    await f.baseline();
    await f.seed('expenses', 'business-rent', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'category': 'Rent & Lease',
      'amountPaise': 12000,
      'expenseDate': '2026-10-20',
      'status': 'ACTIVE',
    });
    final r = await f.report();
    expect(r.reconciliation!.metrics['Operating expenses'], isNull);
    expect(r.reconciliation!.metrics['Gross profit / loss'], 660000);
  });
  test('assigned staff without payroll setup prevent an assumed zero salary expense', () async {
    await f.seed('employees', 'unconfigured', {
      'employeeId': 'unconfigured',
      'uid': 'staff2',
      'ownerUid': 'owner',
      'businessIds': ['b1'],
      'outletIds': ['o1'],
      'status': 'ACTIVE',
    });
    expect(
      (await f.report()).reconciliation!.metrics['Accrued salary expense'],
      isNull,
    );
  });
  test('actual Staff Khata PAY-SP and FIN-SPAY cash collection contracts are counted once', () async {
    await f.baseline();
    await f.seed('payments', 'PAY-SP-request1', {
      ...f.scoped(),
      'paymentId': 'PAY-SP-request1',
      'invoiceId': 'i1',
      'employeeId': 'emp',
      'mode': 'CASH',
      'amountPaise': 15000,
      'createdAt': '2026-10-20',
    });
    await f.seed('financial_transactions', 'FIN-SPAY-request1', {
      ...f.scoped(),
      'transactionId': 'FIN-SPAY-request1',
      'referenceType': 'INVOICE',
      'referenceId': 'i1',
      'transactionType': 'STAFF_PURCHASE_PAYMENT',
      'direction': 'IN',
      'amount': 15000,
      'paymentMode': 'CASH',
      'transactionDate': '2026-10-20',
      'status': 'POSTED',
    });
    expect(
      (await f.report())
          .reconciliation!
          .metrics['Observed cash / bank net movement'],
      15000,
    );
  });
  test('cancelled invoice authorization does not erase a persisted real cash receipt', () async {
    await f.seed('invoices', 'cancelled', {
      ...f.scoped(),
      'status': 'CANCELLED',
      'createdAt': '2026-10-10',
      'cancelledAt': '2026-10-20',
    });
    await f.seed('payments', 'receipt', {
      'invoiceId': 'cancelled',
      'mode': 'CASH',
      'amountPaise': 10000,
      'createdAt': '2026-10-10',
    });
    final r = await f.report();
    expect(
      r.reconciliation!.metrics['Observed cash / bank net movement'],
      10000,
    );
    expect(r.reconciliation!.metrics['Net revenue excluding GST'], 0);
  });
  test('business non-operating expenses are separated and included once without inventing net profit', () async {
    await f.seed('expenses', 'non-operating', {
      'tenantId': 'owner',
      'businessId': 'b1',
      'accountingClass': 'NON_OPERATING',
      'amountPaise': 20000,
      'expenseDate': '2026-10-20',
      'status': 'ACTIVE',
      'category': 'Recorded finance expense',
    });
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
    );
    expect(r.reconciliation!.metrics['Non-operating expenses'], 20000);
    expect(r.reconciliation!.metrics['Operating expenses'], 0);
    expect(r.reconciliation!.metrics['Profit before tax'], isNull);
  });
  test('A4 PDF and Excel export retain large schedules and limitations without certification', () async {
    await f.baseline();
    final r = await f.report(
      scope: const AuditScopeSelection(
        mode: AuditScopeMode.allOutletsInBusiness,
      ),
      displayName: 'DISPOSABLE TEST FIXTURE - Suman Enterprises',
    );
    final review = r.reconciliation!;
    review.schedules.add(
      AuditSchedule(
        'Large printable evidence fixture',
        ['Reference', 'Product / outlet description', 'Amount'],
        [
          for (var i = 0; i < 180; i++)
            [
              'EVIDENCE-$i',
              'Lengthy product name and historical outlet description that should wrap safely across lines and repeat headers on A4 pages',
              'INR 123456.78',
            ],
        ],
      ),
    );
    final bytes = await ReportExportService.generateAuditPdf(r);
    expect(bytes.length, greaterThan(10000));
    expect(
      ReportExportService.generateAuditWorkbook(r).length,
      greaterThan(5000),
    );
    final output = Directory('output/pdf');
    await output.create(recursive: true);
    await File('${output.path}/financial_reconciliation_disposable_fixture.pdf')
        .writeAsBytes(bytes);
  });
  testWidgets(
    'reconciliation dialog exposes evidence sections and explicit limitations',
    (tester) async {
      final r = (await tester.runAsync(() async {
        await f.baseline();
        return f.report();
      }))!;
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuditReportDialog(audit: r)),
        ),
      );
      expect(find.text(FinancialReconciliation.title), findsOneWidget);
      expect(find.textContaining('Not a statutory audit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reconciliation dialog handles empty and mismatched schedules without crashes or overflows on mobile',
    (tester) async {
      final r = (await tester.runAsync(() async {
        await f.baseline();
        return f.report();
      }))!;
      r.reconciliation!.schedules.clear();
      r.reconciliation!.schedules.addAll([
        AuditSchedule('Empty Schedule', const [], const []),
        AuditSchedule(
          'Mismatched Schedule',
          const ['Col 1', 'Col 2', 'Col 3'],
          const [
            ['Short row'],
            ['Long row 1', 'Long row 2', 'Long row 3', 'Long row 4'],
          ],
        ),
      ]);
      await tester.binding.setSurfaceSize(const Size(412, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AuditReportDialog(audit: r)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(FinancialReconciliation.title), findsOneWidget);
      expect(find.text('No observed records. See source coverage.'), findsOneWidget);
      final ex = tester.takeException();
      if (ex != null) {

File('error.txt').writeAsStringSync((ex as FlutterError).toDiagnosticsNode().toStringDeep());

      }
      expect(ex, isNull);
    },
  );
}
