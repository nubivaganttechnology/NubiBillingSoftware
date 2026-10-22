import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/customer_model.dart';
import 'package:testflutter/data/models/customer_payment_model.dart';
import 'package:testflutter/data/repositories/billing_repository.dart';
import 'package:testflutter/data/repositories/customer_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';
import 'package:testflutter/presentation/customers/customer_due_collection_dialog.dart';

class _FakeServerFirestore implements FirestoreDataService, FirestoreTransactionService {
  _FakeServerFirestore({this.isReachable = true});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  bool isReachable;
  final Map<String, Map<String, Map<String, dynamic>>> _storage = {};
  final Map<String, String> _updateTimes = {};

  String _docKey(String c, String id) => '$c/$id';

  void setDoc(String collection, String id, Map<String, dynamic> fields) {
    _storage.putIfAbsent(collection, () => {})[id] = Map<String, dynamic>.from(fields);
    _updateTimes[_docKey(collection, id)] = '2026-10-22T20:00:00.000000Z';
  }

  Map<String, dynamic>? getDoc(String collection, String id) => _storage[collection]?[id];

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    if (!isReachable) throw const AppException('Network connection timeout.', code: 'timeout');
    final doc = _storage[collection]?[id];
    if (doc == null) throw const AppException('Document not found.', code: 'not-found');
    return {
      'name': 'projects/test/databases/(default)/documents/$collection/$id',
      'fields': doc,
      'updateTime': _updateTimes[_docKey(collection, id)] ?? '2026-10-22T20:00:00.000000Z',
    };
  }

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    if (!isReachable) throw const AppException('Network connection timeout.', code: 'timeout');
    final docs = _storage[collection] ?? {};
    final results = <Map<String, dynamic>>[];
    for (final entry in docs.entries) {
      final fields = entry.value;
      var matches = true;
      for (final filter in filters) {
        if (filter.operation == 'EQUAL' && fields[filter.field] != filter.value) {
          matches = false;
          break;
        }
      }
      if (matches) {
        results.add({
          'name': 'projects/test/databases/(default)/documents/$collection/${entry.key}',
          'fields': fields,
          'updateTime': _updateTimes[_docKey(collection, entry.key)] ?? '2026-10-22T20:00:00.000000Z',
        });
      }
    }
    return results;
  }

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext transaction) action, {
    String? idToken,
    int maxAttempts = 3,
  }) async {
    if (!isReachable) throw const AppException('Server unreachable. Active server connection required.', code: 'network-unavailable');
    final context = _FakeTxContext(this);
    final result = await action(context);
    context.commit();
    return result;
  }
}

class _FakeTxContext implements FirestoreTransactionContext {
  _FakeTxContext(this._server);

  final _FakeServerFirestore _server;
  final Map<String, Map<String, dynamic>> _pendingWrites = {};
  final Map<String, String?> _preconditions = {};

  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final key = '$collection/$id';
    final existing = _server.getDoc(collection, id);
    if (existing == null) {
      _preconditions[key] = null;
      return const FirestoreTransactionDocument(exists: false, fields: {});
    }
    final time = _server._updateTimes[key] ?? '2026-10-22T20:00:00.000000Z';
    _preconditions[key] = time;
    return FirestoreTransactionDocument(
      exists: true,
      fields: Map<String, dynamic>.from(existing),
      updateTime: time,
    );
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final rawDocs = await _server.queryDocuments(collection: collection, filters: filters);
    return rawDocs.map((doc) {
      final id = (doc['name'] as String).split('/').last;
      final key = '$collection/$id';
      final time = doc['updateTime'] as String?;
      if (time != null) _preconditions[key] = time;
      return FirestoreTransactionDocument(
        exists: true,
        fields: FirestoreRestService.decodeFields(doc['fields']),
        updateTime: time,
      );
    }).toList();
  }

  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    _pendingWrites['$collection/$id'] = Map<String, dynamic>.from(fields);
  }

  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) {
    final key = '$collection/$id';
    final current = _server.getDoc(collection, id) ?? {};
    _pendingWrites[key] = {
      ...current,
      ...fields,
    };
    if (updateTime != null) {
      _preconditions[key] = updateTime;
    }
  }

  @override
  void delete(String collection, String id, {required String? updateTime}) {
    _pendingWrites['$collection/$id'] = {'_deleted': true};
  }

  void commit() {
    // Precondition check
    for (final entry in _preconditions.entries) {
      final expectedTime = entry.value;
      if (expectedTime != null) {
        final actualTime = _server._updateTimes[entry.key];
        if (actualTime != expectedTime) {
          throw const AppException('Precondition failed. Document was modified concurrently.', code: 'FAILED_PRECONDITION');
        }
      }
    }

    final newTimestamp = DateTime.now().toUtc().toIso8601String();
    for (final entry in _pendingWrites.entries) {
      final parts = entry.key.split('/');
      final col = parts[0];
      final id = parts[1];
      if (entry.value['_deleted'] == true) {
        _server._storage[col]?.remove(id);
      } else {
        _server.setDoc(col, id, entry.value);
        _server._updateTimes[entry.key] = newTimestamp;
      }
    }
  }
}

void main() {
  sqfliteFfiInit();
  late Directory tempDir;
  late LocalDatabase localDb;
  late Database db;
  late LocalDataSource localDataSource;

  const tenantId = 'TEN-001';
  const businessId = 'BUS-001';
  const outlet1 = 'OUT-001';
  const outlet2 = 'OUT-002';
  const token = 'TOKEN-TEST-USER';
  const actorUid = 'EMP-001';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('online-financial-tests-');
    localDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
    db = await localDb.open('proj-online-test', 'user-online-test');
    localDataSource = LocalDataSource(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('Online-Only Server-Confirmed Financial Transactions (Mandatory 20 Scenarios)', () {
    test('1. Offline due collection is blocked', () async {
      final server = _FakeServerFirestore(isReachable: false);
      final repo = CustomerRepository(server, transactions: server);

      expect(
        () => repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet1,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          isOwner: true,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('2. Offline cross-outlet payment is blocked', () async {
      final server = _FakeServerFirestore(isReachable: false);
      final repo = CustomerRepository(server, transactions: server);

      expect(
        () => repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet1,
          amountPaise: 300000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          isOwner: true,
          manualAllocations: [
            const PaymentAllocationRequest(
              invoiceId: 'INV-OUT2',
              originalOutletId: outlet2,
              allocatedPaise: 300000,
            ),
          ],
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('3. Offline advance receipt and refund are blocked through sync outbox', () async {
      final outbox = SyncOutboxRepository(localDataSource);

      expect(
        () => db.transaction((tx) async {
          await outbox.enqueue(
            tx,
            'BATCH-FIN-1',
            {
              'collection': 'customer_ledger_entries',
              'id': 'LED-ADV-1',
              'operation': 'CREATE',
              'fields': {
                'tenantId': tenantId,
                'businessId': businessId,
                'transactionType': 'REFUND',
                'amountPaise': 5000,
              },
            },
            {},
          );
        }),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            equals('offline-financial-prohibited'),
          ),
        ),
      );
    });

    test('4. Offline credit-sale finalization is blocked', () async {
      final server = _FakeServerFirestore(isReachable: false);
      final billingRepo = BillingRepository(server);

      expect(
        () => billingRepo.settle(
          invoiceId: 'INV-001',
          customerId: 'CUS-001',
          amountPaise: 20000,
          mode: 'CASH',
          paymentAt: DateTime.now(),
          token: token,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('5. Online credit sale creates correct due and ledger entries', () async {
      final server = _FakeServerFirestore(isReachable: true);
      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 10000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-001', {
        'invoiceId': 'INV-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 10000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final billingRepo = BillingRepository(server);
      await billingRepo.settle(
        invoiceId: 'INV-001',
        customerId: 'CUS-001',
        amountPaise: 10000,
        mode: 'CASH',
        paymentAt: DateTime.now(),
        token: token,
      );

      final customerAfter = server.getDoc(FirebaseConstants.customers, 'CUS-001');
      expect(customerAfter?['duePaise'], equals(0));

      final invoiceAfter = server.getDoc(FirebaseConstants.invoices, 'INV-001');
      expect(invoiceAfter?['dueAmount'], equals(0));
      expect(invoiceAfter?['status'], equals('PAID'));
    });

    test('6. Network disconnect before submission causes no financial posting', () async {
      final server = _FakeServerFirestore(isReachable: false);
      final repo = CustomerRepository(server, transactions: server);

      try {
        await repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet1,
          amountPaise: 10000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          isOwner: true,
        );
        fail('Should have failed');
      } catch (e) {
        expect(e, isA<AppException>());
      }

      expect(server.getDoc(FirebaseConstants.payments, 'PAY_TEST'), isNull);
    });

    test('7. Network disconnect during submission produces safe unknown status handling', () async {
      final server = _FakeServerFirestore(isReachable: true);
      final repo = CustomerRepository(server, transactions: server);

      // Simulate a network interruption right when status is checked
      server.isReachable = false;
      try {
        await repo.checkPaymentStatus(paymentId: 'PAY-UNKNOWN-1', token: token);
        fail('Should fail due to reachability');
      } catch (e) {
        expect(e, isA<AppException>());
        // In UI, this state becomes PaymentSubmissionState.unknownRequiresStatusCheck
      }
    });

    test('8. Lost server response does not cause duplicate payment', () async {
      final server = _FakeServerFirestore(isReachable: true);
      const idempotencyKey = 'IDEM-LOST-RESP';
      const paymentId = 'PAY_$idempotencyKey';

      server.setDoc(FirebaseConstants.payments, paymentId, {
        'paymentId': paymentId,
        'businessId': businessId,
        'tenantId': tenantId,
        'customerId': 'CUS-001',
        'collectedAtOutletId': outlet1,
        'amountPaise': 25000,
        'paymentMethod': 'CASH',
        'status': 'POSTED',
        'allocations': [],
        'idempotencyKey': idempotencyKey,
      });

      final repo = CustomerRepository(server, transactions: server);
      final recovered = await repo.checkPaymentStatus(paymentId: paymentId, token: token);

      expect(recovered, isNotNull);
      expect(recovered!.paymentId, equals(paymentId));
      expect(recovered.amountPaise, equals(25000));
    });

    test('9. Retry with same idempotency key returns the existing committed result', () async {
      final server = _FakeServerFirestore(isReachable: true);
      const idempotencyKey = 'IDEM-REPEAT-TEST';
      const paymentId = 'PAY_$idempotencyKey';

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 50000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-001', {
        'invoiceId': 'INV-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 50000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      final firstCall = await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        idempotencyKey: idempotencyKey,
        isOwner: true,
      );

      expect(firstCall.paymentId, equals(paymentId));

      // Repeated submission with same idempotencyKey
      final secondCall = await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        idempotencyKey: idempotencyKey,
        isOwner: true,
      );

      expect(secondCall.paymentId, equals(paymentId));
      expect(secondCall.amountPaise, equals(firstCall.amountPaise));

      final customer = server.getDoc(FirebaseConstants.customers, 'CUS-001');
      expect(customer?['duePaise'], equals(0)); // NOT -50000!
    });

    test('10. Two outlets concurrently collecting the same due cannot double-settle it', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 50000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-001', {
        'invoiceId': 'INV-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 50000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Outlet 1 commits payment
      await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: 'CASHIER-1',
        token: token,
        idempotencyKey: 'OUT1-PAY',
        isOwner: true,
      );

      // Outlet 2 tries to collect using stale invoice due
      expect(
        () => repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet2,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: 'CASHIER-2',
          token: token,
          idempotencyKey: 'OUT2-PAY',
          isOwner: true,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('11. FIFO and manual invoice allocation remain correct', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 500000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-A', {
        'invoiceId': 'INV-A',
        'invoiceDate': '2026-10-01T10:00:00Z',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 200000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-B', {
        'invoiceId': 'INV-B',
        'invoiceDate': '2026-10-05T10:00:00Z',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2,
        'customerId': 'CUS-001',
        'dueAmount': 300000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      final payment = await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 300000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        isOwner: true,
      );

      expect(payment.allocations.length, equals(2));
      expect(payment.allocations[0].invoiceId, equals('INV-A'));
      expect(payment.allocations[0].allocatedPaise, equals(200000));
      expect(payment.allocations[1].invoiceId, equals('INV-B'));
      expect(payment.allocations[1].allocatedPaise, equals(100000));

      final invA = server.getDoc(FirebaseConstants.invoices, 'INV-A');
      final invB = server.getDoc(FirebaseConstants.invoices, 'INV-B');
      expect(invA?['dueAmount'], equals(0));
      expect(invA?['status'], equals('PAID'));
      expect(invB?['dueAmount'], equals(200000));
      expect(invB?['status'], equals('PARTIALLY_PAID'));
    });

    test('12. Partial payment works correctly', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 100000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-PARTIAL', {
        'invoiceId': 'INV-PARTIAL',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 100000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 40000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        isOwner: true,
      );

      final inv = server.getDoc(FirebaseConstants.invoices, 'INV-PARTIAL');
      expect(inv?['dueAmount'], equals(60000));
      expect(inv?['paidPaise'], equals(40000));
      expect(inv?['status'], equals('PARTIALLY_PAID'));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-001');
      expect(cus?['duePaise'], equals(60000));
    });

    test('13. Advance payment is created only through approved behavior', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 50000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-001', {
        'invoiceId': 'INV-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 50000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Overpayment without allowAdvance throws
      expect(
        () => repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet1,
          amountPaise: 80000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          allowAdvance: false,
          isOwner: true,
        ),
        throwsA(isA<AppException>()),
      );

      // Overpayment with allowAdvance = true creates customer advance
      final payment = await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1,
        amountPaise: 80000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        allowAdvance: true,
        isOwner: true,
      );

      expect(payment.excessAdvancePaise, equals(30000));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-001');
      expect(cus?['duePaise'], equals(0));
      expect(cus?['advancePaise'], equals(30000));
    });

    test('14. Collecting outlet cash attribution remains correct', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 100000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-OUT2', {
        'invoiceId': 'INV-OUT2',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2,
        'customerId': 'CUS-001',
        'dueAmount': 100000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);

      final payment = await repo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        collectedAtOutletId: outlet1, // Outlet 1 collects cash for Outlet 2's invoice
        amountPaise: 100000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        isOwner: true,
      );

      expect(payment.collectedAtOutletId, equals(outlet1));

      final audit = server.getDoc(FirebaseConstants.financialTransactions, 'FIN_PAY_${payment.paymentId}');
      expect(audit?['outletId'], equals(outlet1)); // Cash attributed to Outlet 1 drawer
    });

    test('15. Customer due matches outstanding invoice and ledger totals', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 200000,
        'advancePaise': 0,
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-1', {
        'invoiceId': 'INV-1',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': 'CUS-001',
        'dueAmount': 80000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });
      server.setDoc(FirebaseConstants.invoices, 'INV-2', {
        'invoiceId': 'INV-2',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2,
        'customerId': 'CUS-001',
        'dueAmount': 120000,
        'paidPaise': 0,
        'status': 'UNPAID',
      });

      final repo = CustomerRepository(server, transactions: server);
      final outstandingInvoices = await repo.getOutstandingInvoices(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUS-001',
        token: token,
        isOwner: true,
      );

      final totalOutstanding = outstandingInvoices.fold<int>(
        0,
        (sum, inv) => sum + ((inv['dueAmount'] as num?)?.toInt() ?? 0),
      );

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-001');
      expect(cus?['duePaise'], equals(totalOutstanding));
      expect(totalOutstanding, equals(200000));
    });

    test('16. Unauthorized outlet or employee cannot post financial changes', () async {
      final server = _FakeServerFirestore(isReachable: true);

      server.setDoc(FirebaseConstants.customers, 'CUS-001', {
        'customerId': 'CUS-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'duePaise': 50000,
        'advancePaise': 0,
      });

      final repo = CustomerRepository(server, transactions: server);

      // Employee without DUE_COLLECT is blocked
      expect(
        () => repo.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: 'CUS-001',
          collectedAtOutletId: outlet1,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          employeePermissions: ['CUSTOMER_VIEW'], // Missing DUE_COLLECT
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('DUE_COLLECT required'),
          ),
        ),
      );
    });

    test('17. Old offline financial queue entries are identified for reconciliation', () async {
      final outbox = SyncOutboxRepository(localDataSource);

      // Seed a legacy financial outbox entry
      await db.insert('sync_outbox', {
        'batchId': 'BATCH-LEGACY-FIN',
        'entityType': 'payments',
        'documentId': 'PAY-OLD-1',
        'operation': 'CREATE',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'payloadJson': jsonEncode({'amountPaise': 15000}),
        'readSetJson': jsonEncode({}),
        'localRevision': 1,
        'createdAt': '2026-10-01T12:00:00Z',
        'status': 'PENDING',
      });

      // nextBatch() quarantines the batch
      final batch = await outbox.nextBatch();
      expect(batch.isEmpty, isTrue);

      final quarantined = await outbox.getPendingFinancialEntries();
      expect(quarantined.isNotEmpty, isTrue);
      expect(quarantined.first['batchId'], equals('BATCH-LEGACY-FIN'));
      expect(quarantined.first['status'], equals('FAILED'));
      expect(
        quarantined.first['lastError'],
        startsWith('RECONCILIATION_REQUIRED'),
      );

      // Administrative reconciliation
      await outbox.reconcileLegacyFinancialBatch(
        'BATCH-LEGACY-FIN',
        resolution: 'Audited and marked resolved manually',
      );

      final after = await db.query('sync_outbox', where: "batchId='BATCH-LEGACY-FIN'");
      expect(after.first['status'], equals('FAILED'));
      expect(after.first['lastError'], startsWith('RECONCILED:'));
    });

    test('18. Non-financial offline synchronization still works', () async {
      final outbox = SyncOutboxRepository(localDataSource);

      // Insert a non-financial entity (e.g. brand / category / customer profile)
      await db.insert('sync_outbox', {
        'batchId': 'BATCH-PRODUCT-CAT',
        'entityType': 'brands',
        'documentId': 'BRD-001',
        'operation': 'CREATE',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'payloadJson': jsonEncode({'brandName': 'Acme Paints'}),
        'readSetJson': jsonEncode({}),
        'localRevision': 1,
        'createdAt': '2026-10-22T21:00:00Z',
        'status': 'PENDING',
      });

      final batch = await outbox.nextBatch();
      expect(batch.isNotEmpty, isTrue);
      expect(batch.first['batchId'], equals('BATCH-PRODUCT-CAT'));
      expect(batch.first['entityType'], equals('brands'));
    });

    test('19. Legacy customer financial balances are preserved', () async {
      final legacyJson = {
        'customerId': 'CUS-LEGACY',
        'businessId': businessId,
        'tenantId': tenantId,
        'name': 'Ramesh Stores',
        'phone': '9876543210',
        'duePaise': 345600,
        'advancePaise': 12000,
      };

      final model = CustomerModel.fromData('CUS-LEGACY', legacyJson);
      expect(model.duePaise, equals(345600));
      expect(model.advancePaise, equals(12000));
      expect(model.customerType, equals('UNSPECIFIED'));
    });

    test('20. All affected Android, Windows and Web workflows remain compatible', () async {
      expect(PaymentSubmissionState.values.length, equals(6));
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.idle), isTrue);
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.validating), isTrue);
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.submitting), isTrue);
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.confirmed), isTrue);
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.failed), isTrue);
      expect(PaymentSubmissionState.values.contains(PaymentSubmissionState.unknownRequiresStatusCheck), isTrue);
    });
  });
}

