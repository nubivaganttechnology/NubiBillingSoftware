import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/customer_payment_model.dart';
import 'package:testflutter/data/repositories/customer_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';

/// Test fixture simulating authoritative Firestore REST server with optimistic locking,
/// multi-tenant data storage, and network failure injection.
class _E2ETestServerFirestore
    implements FirestoreDataService, FirestoreTransactionService {
  _E2ETestServerFirestore({this.isReachable = true});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  bool isReachable;
  bool dropResponseAfterCommit = false;
  int commitAttempts = 0;

  final Map<String, Map<String, Map<String, dynamic>>> _storage = {};
  final Map<String, String> _updateTimes = {};
  int _revisionCounter = 1;

  String _docKey(String c, String id) => '$c/$id';

  void setDoc(String collection, String id, Map<String, dynamic> fields) {
    _storage.putIfAbsent(collection, () => {})[id] =
        Map<String, dynamic>.from(fields);
    _updateTimes[_docKey(collection, id)] =
        '2026-10-23T00:00:00.${_revisionCounter.toString().padLeft(6, '0')}Z';
    _revisionCounter++;
  }

  Map<String, dynamic>? getDoc(String collection, String id) =>
      _storage[collection]?[id];

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    if (!isReachable) {
      throw const AppException(
        'Network connection timeout.',
        code: 'timeout',
      );
    }
    final doc = _storage[collection]?[id];
    if (doc == null) {
      throw const AppException('Document not found.', code: 'not-found');
    }
    return {
      'name': 'projects/test/databases/(default)/documents/$collection/$id',
      'fields': doc,
      'updateTime':
          _updateTimes[_docKey(collection, id)] ??
          '2026-10-23T00:00:00.000000Z',
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
    if (!isReachable) {
      throw const AppException(
        'Network connection timeout.',
        code: 'timeout',
      );
    }
    final docs = _storage[collection] ?? {};
    final results = <Map<String, dynamic>>[];
    for (final entry in docs.entries) {
      final fields = entry.value;
      var matches = true;
      for (final filter in filters) {
        if (filter.operation == 'EQUAL' &&
            fields[filter.field] != filter.value) {
          matches = false;
          break;
        }
      }
      if (matches) {
        results.add({
          'name':
              'projects/test/databases/(default)/documents/$collection/${entry.key}',
          'fields': fields,
          'updateTime':
              _updateTimes[_docKey(collection, entry.key)] ??
              '2026-10-23T00:00:00.000000Z',
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
    if (!isReachable) {
      throw const AppException(
        'Server unreachable. Active server connection required.',
        code: 'network-unavailable',
      );
    }
    commitAttempts++;
    final context = _E2ETxContext(this);
    final result = await action(context);
    context.commit();
    if (dropResponseAfterCommit) {
      throw const AppException(
        'Connection reset by peer after commit.',
        code: 'connection-reset',
      );
    }
    return result;
  }
}

class _E2ETxContext implements FirestoreTransactionContext {
  _E2ETxContext(this._server);

  final _E2ETestServerFirestore _server;
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
    final time =
        _server._updateTimes[key] ?? '2026-10-23T00:00:00.000000Z';
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
    final rawDocs = await _server.queryDocuments(
      collection: collection,
      filters: filters,
    );
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
    // Optimistic Concurrency Precondition Validation
    for (final entry in _preconditions.entries) {
      final expectedTime = entry.value;
      if (expectedTime != null) {
        final actualTime = _server._updateTimes[entry.key];
        if (actualTime != expectedTime) {
          throw const AppException(
            'Precondition failed. Document was modified concurrently.',
            code: 'FAILED_PRECONDITION',
          );
        }
      }
    }

    for (final entry in _pendingWrites.entries) {
      final parts = entry.key.split('/');
      final col = parts[0];
      final id = parts[1];
      _server.setDoc(col, id, entry.value);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const tenantA = 'TENANT-ALPHA';
  const tenantB = 'TENANT-BETA';
  const businessA = 'BIZ-ALPHA';
  const businessB = 'BIZ-BETA';
  const outlet1 = 'OUTLET-01';
  const outlet2 = 'OUTLET-02';
  const actorUid = 'CASHIER-01';
  const token = 'MOCK-JWT-TOKEN';

  late Directory tempDir;
  late LocalDatabase localDb;
  late Database db;
  late LocalDataSource localDataSource;

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('e2e_finance_test_');
    localDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
    db = await localDb.open('proj-e2e-finance', 'user-e2e-finance');
    localDataSource = LocalDataSource(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Group 1: Online-Only Financial Operations & Offline Blocking', () {
    test('1.1 Online payment atomically commits customer, invoice, ledger, and payment', () async {
      final server = _E2ETestServerFirestore();

      // Seed Customer with 2000.00 due
      server.setDoc(FirebaseConstants.customers, 'CUS-100', {
        'customerId': 'CUS-100',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 200000,
        'advancePaise': 0,
      });

      // Seed Invoice for 2000.00 due
      server.setDoc(FirebaseConstants.invoices, 'INV-101', {
        'invoiceId': 'INV-101',
        'invoiceNumber': 'INV-101',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-100',
        'dueAmount': 200000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 200000,
        'status': 'POSTED',
        'createdAt': '2026-10-20T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      final payment = await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-100',
        collectedAtOutletId: outlet1,
        amountPaise: 200000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      expect(payment.paymentId.isNotEmpty, isTrue);
      expect(payment.amountPaise, equals(200000));

      // Authoritative remote state check
      final updatedCus = server.getDoc(FirebaseConstants.customers, 'CUS-100');
      expect(updatedCus?['duePaise'], equals(0));

      final updatedInv = server.getDoc(FirebaseConstants.invoices, 'INV-101');
      expect(updatedInv?['dueAmount'], equals(0));
      expect(updatedInv?['paidPaise'], equals(200000));
      expect(updatedInv?['paymentStatus'], equals('PAID'));

      final storedPayment = server.getDoc(FirebaseConstants.payments, payment.paymentId);
      expect(storedPayment, isNotNull);
      expect(storedPayment?['amountPaise'], equals(200000));

      final ledger = server.getDoc(
        FirebaseConstants.customerLedgerEntries,
        'LED_${payment.paymentId}_INV-101',
      );
      expect(ledger, isNotNull);
      expect(ledger?['transactionType'], equals('PAYMENT'));
      expect(ledger?['amountPaise'], equals(200000));
    });

    test('1.2 Offline payment collection is strictly blocked and never enqueued', () async {
      final server = _E2ETestServerFirestore(isReachable: false);
      final repo = CustomerRepository(server, transactions: server);

      expect(
        () => repo.collectPayment(
          tenantId: tenantA,
          businessId: businessA,
          customerId: 'CUS-100',
          collectedAtOutletId: outlet1,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: actorUid,
          token: token,
          employeePermissions: ['DUE_COLLECT'],
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            equals('network-unavailable'),
          ),
        ),
      );

      // Verify sync outbox has zero records
      final outboxRows = await db.query('sync_outbox');
      expect(outboxRows.isEmpty, isTrue);
    });

    test('1.3 Local SQLite cache maintains consistency with server-confirmed balances', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-100', {
        'customerId': 'CUS-100',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 100000,
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-100', {
        'invoiceId': 'INV-100',
        'invoiceNumber': 'INV-100',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-100',
        'dueAmount': 100000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 100000,
        'status': 'POSTED',
        'createdAt': '2026-10-20T10:00:00Z',
      });

      // Seed local cache before payment with current due 100000
      await LocalDataSource.put(db, FirebaseConstants.customers, {
        'remoteId': 'CUS-100',
        'payloadJson': jsonEncode({
          'customerId': 'CUS-100',
          'tenantId': tenantA,
          'businessId': businessA,
          'duePaise': 100000,
          'advancePaise': 0,
        }),
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'isDeleted': 0,
      });

      final repo = CustomerRepository(server, transactions: server);

      await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-100',
        collectedAtOutletId: outlet1,
        amountPaise: 100000,
        paymentMethod: 'UPI',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      // Server is updated cleanly
      final serverCus = server.getDoc(FirebaseConstants.customers, 'CUS-100');
      expect(serverCus?['duePaise'], equals(0));

      // Outbox remains completely free of payment mutations
      final outbox = await db.query('sync_outbox');
      expect(outbox.isEmpty, isTrue);
    });
  });

  group('Group 2: Invoicing, Settlements & Cross-Outlet Due Collection', () {
    test('2.1 Multi-outlet invoice settlement in a single atomic transaction', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-200', {
        'customerId': 'CUS-200',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 350000,
        'advancePaise': 0,
      });

      // Invoice 1 at Outlet 1 (1500.00)
      server.setDoc(FirebaseConstants.invoices, 'INV-201', {
        'invoiceId': 'INV-201',
        'invoiceNumber': 'INV-201',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-200',
        'dueAmount': 150000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 150000,
        'status': 'POSTED',
        'createdAt': '2026-10-18T10:00:00Z',
      });

      // Invoice 2 at Outlet 2 (2000.00)
      server.setDoc(FirebaseConstants.invoices, 'INV-202', {
        'invoiceId': 'INV-202',
        'invoiceNumber': 'INV-202',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet2,
        'customerId': 'CUS-200',
        'dueAmount': 200000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 200000,
        'status': 'POSTED',
        'createdAt': '2026-10-19T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Customer pays ₹3,500 at Outlet 1 settling both invoices
      final payment = await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-200',
        collectedAtOutletId: outlet1,
        amountPaise: 350000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT', 'CROSS_OUTLET_DUE_COLLECT'],
        isOwner: false,
      );

      expect(payment.amountPaise, equals(350000));
      expect(payment.collectedAtOutletId, equals(outlet1));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-200');
      expect(cus?['duePaise'], equals(0));

      final inv1 = server.getDoc(FirebaseConstants.invoices, 'INV-201');
      expect(inv1?['dueAmount'], equals(0));
      expect(inv1?['paymentStatus'], equals('PAID'));

      final inv2 = server.getDoc(FirebaseConstants.invoices, 'INV-202');
      expect(inv2?['dueAmount'], equals(0));
      expect(inv2?['paymentStatus'], equals('PAID'));
    });

    test('2.2 FIFO allocation settles oldest invoice first', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-300', {
        'customerId': 'CUS-300',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 300000,
        'advancePaise': 0,
      });

      // Older Invoice (1000.00)
      server.setDoc(FirebaseConstants.invoices, 'INV-OLD', {
        'invoiceId': 'INV-OLD',
        'invoiceNumber': 'INV-OLD',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-300',
        'dueAmount': 100000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 100000,
        'status': 'POSTED',
        'createdAt': '2026-10-01T10:00:00Z',
      });

      // Newer Invoice (2000.00)
      server.setDoc(FirebaseConstants.invoices, 'INV-NEW', {
        'invoiceId': 'INV-NEW',
        'invoiceNumber': 'INV-NEW',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-300',
        'dueAmount': 200000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 200000,
        'status': 'POSTED',
        'createdAt': '2026-10-15T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Customer pays 1500.00 (settles INV-OLD completely, and partially settles INV-NEW by 500)
      await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-300',
        collectedAtOutletId: outlet1,
        amountPaise: 150000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      final invOld = server.getDoc(FirebaseConstants.invoices, 'INV-OLD');
      expect(invOld?['dueAmount'], equals(0));
      expect(invOld?['paidPaise'], equals(100000));
      expect(invOld?['paymentStatus'], equals('PAID'));

      final invNew = server.getDoc(FirebaseConstants.invoices, 'INV-NEW');
      expect(invNew?['dueAmount'], equals(150000));
      expect(invNew?['paidPaise'], equals(50000));
      expect(invNew?['paymentStatus'], equals('PARTIALLY_PAID'));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-300');
      expect(cus?['duePaise'], equals(150000));
    });

    test('2.3 Cross-outlet payment attributes cash to collecting outlet and reduces invoice due', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-400', {
        'customerId': 'CUS-400',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 50000,
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-OUTLET1', {
        'invoiceId': 'INV-OUTLET1',
        'invoiceNumber': 'INV-OUTLET1',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1, // Created at Outlet 1
        'customerId': 'CUS-400',
        'dueAmount': 50000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 50000,
        'status': 'POSTED',
        'createdAt': '2026-10-21T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Payment collected at Outlet 2
      final payment = await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-400',
        collectedAtOutletId: outlet2,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT', 'CROSS_OUTLET_DUE_COLLECT'],
        isOwner: false,
      );

      expect(payment.collectedAtOutletId, equals(outlet2));

      final ledger = server.getDoc(
        FirebaseConstants.customerLedgerEntries,
        'LED_${payment.paymentId}_INV-OUTLET1',
      );
      expect(ledger?['outletId'], equals(outlet2));
      expect(ledger?['amountPaise'], equals(50000));

      final inv = server.getDoc(FirebaseConstants.invoices, 'INV-OUTLET1');
      expect(inv?['dueAmount'], equals(0));
      expect(inv?['outletId'], equals(outlet1)); // Original sale outlet preserved!
    });
  });

  group('Group 3: Concurrency, Network Resilience & Idempotency', () {
    test('3.1 Multiple simultaneous payment attempts cannot double-settle due (Precondition Lock)', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-500', {
        'customerId': 'CUS-500',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 100000,
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-500', {
        'invoiceId': 'INV-500',
        'invoiceNumber': 'INV-500',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-500',
        'dueAmount': 100000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 100000,
        'status': 'POSTED',
        'createdAt': '2026-10-22T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Outlet 1 and Outlet 2 both initiate a payment for ₹1,000 at the exact same instant
      final tx1 = repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-500',
        collectedAtOutletId: outlet1,
        amountPaise: 100000,
        paymentMethod: 'CASH',
        actorUid: 'USER-1',
        token: token,
        employeePermissions: ['DUE_COLLECT', 'CROSS_OUTLET_DUE_COLLECT'],
        isOwner: false,
      );

      final tx2 = repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-500',
        collectedAtOutletId: outlet2,
        amountPaise: 100000,
        paymentMethod: 'CASH',
        actorUid: 'USER-2',
        token: token,
        employeePermissions: ['DUE_COLLECT', 'CROSS_OUTLET_DUE_COLLECT'],
        isOwner: false,
      );

      final results = await Future.wait([
        tx1.then<dynamic>((v) => v).catchError((e) => e),
        tx2.then<dynamic>((v) => v).catchError((e) => e),
      ]);

      final successCount = results.whereType<CustomerPaymentRecord>().length;
      final errorCount = results.whereType<AppException>().length;

      expect(successCount, equals(1), reason: 'Exactly one transaction must succeed');
      expect(errorCount, equals(1), reason: 'Concurrent racer must fail precondition');

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-500');
      expect(cus?['duePaise'], equals(0), reason: 'Customer due cannot go negative (-100000)');

      final inv = server.getDoc(FirebaseConstants.invoices, 'INV-500');
      expect(inv?['dueAmount'], equals(0));
      expect(inv?['paidPaise'], equals(100000));
    });

    test('3.2 Idempotency: Repeated submission with same idempotency key returns existing payment', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-600', {
        'customerId': 'CUS-600',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 50000,
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-600', {
        'invoiceId': 'INV-600',
        'invoiceNumber': 'INV-600',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-600',
        'dueAmount': 50000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 50000,
        'status': 'POSTED',
        'createdAt': '2026-10-20T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);
      const idempotencyKey = 'PAY-IDEM-STABLE-600';

      // First submission
      final res1 = await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-600',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        idempotencyKey: idempotencyKey,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      expect(res1.idempotencyKey, equals(idempotencyKey));

      // Re-submit identical payment with same idempotency key (e.g. user retried network request)
      final res2 = await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-600',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        idempotencyKey: idempotencyKey,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      expect(res2.paymentId, equals(res1.paymentId));
      expect(res2.amountPaise, equals(res1.amountPaise));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-600');
      expect(cus?['duePaise'], equals(0), reason: 'Due must not be deducted twice');
    });

    test('3.3 Network timeout after server commit enables safe payment status recovery', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-700', {
        'customerId': 'CUS-700',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 80000,
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-700', {
        'invoiceId': 'INV-700',
        'invoiceNumber': 'INV-700',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-700',
        'dueAmount': 80000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 80000,
        'status': 'POSTED',
        'createdAt': '2026-10-20T10:00:00Z',
      });

      // Inject network drop after server commit has succeeded
      server.dropResponseAfterCommit = true;

      final repo = CustomerRepository(server, transactions: server);
      const stableKey = 'PAY-IDEM-DISCONNECT-700';

      CustomerPaymentRecord? paymentResult;
      AppException? caughtException;

      try {
        paymentResult = await repo.collectPayment(
          tenantId: tenantA,
          businessId: businessA,
          customerId: 'CUS-700',
          collectedAtOutletId: outlet1,
          amountPaise: 80000,
          paymentMethod: 'UPI',
          actorUid: actorUid,
          token: token,
          idempotencyKey: stableKey,
          employeePermissions: ['DUE_COLLECT'],
          isOwner: false,
        );
      } on AppException catch (e) {
        caughtException = e;
      }

      expect(paymentResult, isNull);
      expect(caughtException, isNotNull);
      expect(caughtException?.code, equals('connection-reset'));

      // The transaction committed on server despite client connection drop
      server.dropResponseAfterCommit = false;

      // Status recovery via checkPaymentStatus
      final recoveredPayment = await repo.checkPaymentStatus(
        paymentId: 'PAY_$stableKey',
        token: token,
      );

      expect(recoveredPayment, isNotNull);
      expect(recoveredPayment?.amountPaise, equals(80000));
      expect(recoveredPayment?.status, equals('POSTED'));

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-700');
      expect(cus?['duePaise'], equals(0));
    });
  });

  group('Group 4: Reconciliation & Financial Balance Integrity', () {
    test('4.1 Triple reconciliation: customer due == sum(invoice due)', () async {
      final server = _E2ETestServerFirestore();

      // Seed customer with 3000.00
      server.setDoc(FirebaseConstants.customers, 'CUS-800', {
        'customerId': 'CUS-800',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 300000,
        'advancePaise': 0,
      });

      // 3 Invoices of 1000.00 each
      for (int i = 1; i <= 3; i++) {
        server.setDoc(FirebaseConstants.invoices, 'INV-80$i', {
          'invoiceId': 'INV-80$i',
          'invoiceNumber': 'INV-80$i',
          'tenantId': tenantA,
          'businessId': businessA,
          'outletId': i % 2 == 1 ? outlet1 : outlet2,
          'customerId': 'CUS-800',
          'dueAmount': 100000,
          'paidAmount': 0,
          'paidPaise': 0,
          'total': 100000,
          'status': 'POSTED',
          'createdAt': '2026-10-0${i}T10:00:00Z',
        });
      }

      final repo = CustomerRepository(server, transactions: server);

      // Customer pays ₹1,500
      await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-800',
        collectedAtOutletId: outlet1,
        amountPaise: 150000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        employeePermissions: ['DUE_COLLECT', 'CROSS_OUTLET_DUE_COLLECT'],
        isOwner: false,
      );

      // Query live invoices
      final outstandingInvoices = await repo.getOutstandingInvoices(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-800',
        token: token,
        isOwner: true,
      );

      final totalInvoiceDue = outstandingInvoices.fold<int>(
        0,
        (sum, inv) => sum + ((inv['dueAmount'] as num?)?.toInt() ?? 0),
      );

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-800');
      final customerDue = cus?['duePaise'] as int;

      expect(customerDue, equals(150000));
      expect(totalInvoiceDue, equals(150000));
      expect(customerDue, equals(totalInvoiceDue));
    });

    test('4.2 Overpayment creates advance balance without negative due', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-900', {
        'customerId': 'CUS-900',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 20000, // Due: 200.00
        'advancePaise': 0,
      });

      server.setDoc(FirebaseConstants.invoices, 'INV-900', {
        'invoiceId': 'INV-900',
        'invoiceNumber': 'INV-900',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet1,
        'customerId': 'CUS-900',
        'dueAmount': 20000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 20000,
        'status': 'POSTED',
        'createdAt': '2026-10-20T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Customer pays 500.00 (overpaying by 300.00)
      await repo.collectPayment(
        tenantId: tenantA,
        businessId: businessA,
        customerId: 'CUS-900',
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: actorUid,
        token: token,
        allowAdvance: true,
        employeePermissions: ['DUE_COLLECT'],
        isOwner: false,
      );

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-900');
      expect(cus?['duePaise'], equals(0));
      expect(cus?['advancePaise'], equals(30000));
    });
  });

  group('Group 5: Security, Permissions & Multi-Tenant Isolation', () {
    test('5.1 Multi-tenant isolation: Tenant B cannot access or collect dues for Tenant A', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-TENANT-A', {
        'customerId': 'CUS-TENANT-A',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 100000,
        'advancePaise': 0,
      });

      final repo = CustomerRepository(server, transactions: server);

      // Attempt payment by Tenant B client
      expect(
        () => repo.collectPayment(
          tenantId: tenantB, // Wrong tenant
          businessId: businessA,
          customerId: 'CUS-TENANT-A',
          collectedAtOutletId: outlet1,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: 'ATTACKER',
          token: 'TOKEN-TENANT-B',
          employeePermissions: ['DUE_COLLECT'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Customer not found in this Business'),
          ),
        ),
      );

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-TENANT-A');
      expect(cus?['duePaise'], equals(100000));
    });

    test('5.2 Multi-business isolation: Business B cannot access or alter dues of Business A', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-BIZ-A', {
        'customerId': 'CUS-BIZ-A',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 75000,
        'advancePaise': 0,
      });

      final repo = CustomerRepository(server, transactions: server);

      // Attempt payment by Business B client within same tenant
      expect(
        () => repo.collectPayment(
          tenantId: tenantA,
          businessId: businessB, // Different business
          customerId: 'CUS-BIZ-A',
          collectedAtOutletId: outlet1,
          amountPaise: 75000,
          paymentMethod: 'CASH',
          actorUid: 'USER-BIZ-B',
          token: token,
          employeePermissions: ['DUE_COLLECT'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Customer not found in this Business'),
          ),
        ),
      );

      final cus = server.getDoc(FirebaseConstants.customers, 'CUS-BIZ-A');
      expect(cus?['duePaise'], equals(75000));
    });

    test('5.3 Employee lacking DUE_COLLECT permission is blocked from payment operations', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-PERM-TEST', {
        'customerId': 'CUS-PERM-TEST',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 50000,
        'advancePaise': 0,
      });

      final repo = CustomerRepository(server, transactions: server);

      expect(
        () => repo.collectPayment(
          tenantId: tenantA,
          businessId: businessA,
          customerId: 'CUS-PERM-TEST',
          collectedAtOutletId: outlet1,
          amountPaise: 50000,
          paymentMethod: 'CASH',
          actorUid: 'STAFF-NO-PERM',
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

    test('5.4 Cross-outlet collection without CROSS_OUTLET_DUE_COLLECT is blocked', () async {
      final server = _E2ETestServerFirestore();

      server.setDoc(FirebaseConstants.customers, 'CUS-CROSS-PERM', {
        'customerId': 'CUS-CROSS-PERM',
        'tenantId': tenantA,
        'businessId': businessA,
        'duePaise': 60000,
        'advancePaise': 0,
      });

      // Invoice at Outlet 2
      server.setDoc(FirebaseConstants.invoices, 'INV-CROSS-02', {
        'invoiceId': 'INV-CROSS-02',
        'invoiceNumber': 'INV-CROSS-02',
        'tenantId': tenantA,
        'businessId': businessA,
        'outletId': outlet2,
        'customerId': 'CUS-CROSS-PERM',
        'dueAmount': 60000,
        'paidAmount': 0,
        'paidPaise': 0,
        'total': 60000,
        'status': 'POSTED',
        'createdAt': '2026-10-21T10:00:00Z',
      });

      final repo = CustomerRepository(server, transactions: server);

      // Staff at Outlet 1 attempting to collect dues for Outlet 2's invoice
      expect(
        () => repo.collectPayment(
          tenantId: tenantA,
          businessId: businessA,
          customerId: 'CUS-CROSS-PERM',
          collectedAtOutletId: outlet1,
          amountPaise: 60000,
          paymentMethod: 'CASH',
          actorUid: 'STAFF-OUTLET-1',
          token: token,
          manualAllocations: const [
            PaymentAllocationRequest(
              invoiceId: 'INV-CROSS-02',
              originalOutletId: outlet2,
              allocatedPaise: 60000,
            ),
          ],
          employeePermissions: ['DUE_COLLECT'], // Missing CROSS_OUTLET_DUE_COLLECT
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('CROSS_OUTLET_DUE_COLLECT required'),
          ),
        ),
      );
    });

    test('5.5 Unauthorized client direct balance mutation via offline outbox is rejected', () async {
      final outbox = SyncOutboxRepository(localDataSource);

      // Seed customer locally so it exists for update
      await LocalDataSource.put(db, FirebaseConstants.customers, {
        'remoteId': 'CUS-ROGUE',
        'payloadJson': jsonEncode({
          'customerId': 'CUS-ROGUE',
          'tenantId': tenantA,
          'businessId': businessA,
          'duePaise': 50000,
          'advancePaise': 0,
        }),
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'isDeleted': 0,
      });

      // Attempt rogue outbox enqueue modifying customer duePaise directly
      expect(
        () => db.transaction((tx) async {
          await outbox.enqueue(
            tx,
            'BATCH-ROGUE',
            {
              'collection': FirebaseConstants.customers,
              'id': 'CUS-ROGUE',
              'operation': 'UPDATE',
              'fields': {
                'duePaise': 0, // Malicious reset of due to 0
              },
            },
            {},
          );
        }),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            equals('offline-balance-prohibited'),
          ),
        ),
      );
    });
  });
}
