import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/models/customer_model.dart';
import 'package:testflutter/data/models/customer_payment_model.dart';
import 'package:testflutter/data/repositories/billing_repository.dart';
import 'package:testflutter/data/repositories/customer_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';

class MockFirestoreService implements FirestoreDataService, FirestoreTransactionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final Map<String, Map<String, Map<String, dynamic>>> collections = {};
  final Map<String, String> updateTimes = {};
  int _timeSeq = 1;

  void seed(String collection, String id, Map<String, dynamic> data) {
    collections.putIfAbsent(collection, () => {})[id] =
        Map<String, dynamic>.from(data);
    updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  Map<String, dynamic>? getRaw(String collection, String id) =>
      collections[collection]?[id];

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    final doc = collections[collection]?[id];
    if (doc == null) {
      throw AppException('Document $collection/$id not found.');
    }
    return {'fields': doc, 'updateTime': updateTimes['$collection/$id'] ?? 'time_0'};
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
    final docs = collections[collection] ?? {};
    final results = <Map<String, dynamic>>[];

    for (final entry in docs.entries) {
      final fields = entry.value;
      var matches = true;
      for (final filter in filters) {
        final val = fields[filter.field];
        if (filter.operation == 'EQUAL' && val != filter.value) {
          matches = false;
          break;
        }
      }
      if (matches) {
        results.add({
          'name': 'projects/test/databases/(default)/documents/$collection/${entry.key}',
          'fields': fields,
          'updateTime': updateTimes['$collection/${entry.key}'] ?? 'time_0',
        });
      }
    }
    return results;
  }

  @override
  Future<List<Map<String, dynamic>>> queryEqual(
    String collection,
    String field,
    Object value, {
    String? idToken,
  }) =>
      queryDocuments(
        collection: collection,
        filters: [FirestoreFilter(field, 'EQUAL', value)],
        idToken: idToken,
      );

  @override
  Future<void> createDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    collections.putIfAbsent(collection, () => {})[id] =
        Map<String, dynamic>.from(fields);
    updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  @override
  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    final current = collections[collection]?[id];
    if (current == null) {
      throw AppException('Document $collection/$id not found.');
    }
    current.addAll(fields);
    updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext transaction) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    final ctx = _MockTxContext(this);
    final result = await action(ctx);
    ctx.commit();
    return result;
  }
}

class _MockTxContext implements FirestoreTransactionContext {
  _MockTxContext(this._db);
  final MockFirestoreService _db;
  final List<void Function()> _ops = [];

  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final doc = _db.collections[collection]?[id];
    if (doc == null) {
      return FirestoreTransactionDocument(id: id, exists: false, fields: const {});
    }
    return FirestoreTransactionDocument(
      id: id,
      exists: true,
      fields: Map<String, dynamic>.from(doc),
      updateTime: _db.updateTimes['$collection/$id'] ?? 'time_0',
    );
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final docs = await _db.queryDocuments(collection: collection, filters: filters);
    return docs.map((d) {
      final id = (d['name'] as String).split('/').last;
      return FirestoreTransactionDocument(
        id: id,
        exists: true,
        fields: Map<String, dynamic>.from(d['fields'] as Map),
        updateTime: d['updateTime'] as String? ?? 'time_0',
      );
    }).toList();
  }

  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    _ops.add(() => _db.createDocument(collection, id, fields));
  }

  @override
  void update(String collection, String id, Map<String, dynamic> fields, {String? updateTime}) {
    _ops.add(() => _db.updateDocument(collection, id, fields));
  }

  @override
  void delete(String collection, String id, {String? updateTime}) {
    _ops.add(() => _db.collections[collection]?.remove(id));
  }

  void commit() {
    for (final op in _ops) {
      op();
    }
  }
}

void main() {
  group('Arnaw Kolkata-to-Howrah Cross-Outlet Due Collection Test', () {
    late MockFirestoreService mockDb;
    late CustomerRepository customerRepo;
    late BillingRepository billingRepo;

    const tenantId = 'TENANT_01';
    const businessId = 'BIZ_01';
    const kolkataOutlet = 'kolkata_outlet';
    const howrahOutlet = 'howrah_outlet';
    const token = 'test-token';

    setUp(() {
      mockDb = MockFirestoreService();
      customerRepo = CustomerRepository(mockDb, transactions: mockDb);
      billingRepo = BillingRepository(mockDb);

      // Seed customer "Arnaw" with ₹450 due (45,000 paise)
      mockDb.seed(FirebaseConstants.customers, 'CUST_ARNAW', {
        'customerId': 'CUST_ARNAW',
        'tenantId': tenantId,
        'businessId': businessId,
        'name': 'Arnaw',
        'phone': '9876543210',
        'duePaise': 45000,
        'advancePaise': 0,
        'status': 'ACTIVE',
      });

      // Seed invoice created from Kolkata outlet with ₹450 due
      mockDb.seed(FirebaseConstants.invoices, 'INV_KOL_001', {
        'invoiceId': 'INV_KOL_001',
        'invoiceNumber': 'INV-KOL-2026-001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': kolkataOutlet,
        'customerId': 'CUST_ARNAW',
        'customerName': 'Arnaw',
        'customerPhone': '9876543210',
        'grandTotalPaise': 45000,
        'paidPaise': 0,
        'dueAmount': 45000,
        'status': 'PENDING',
        'createdAt': '2026-10-20T10:00:00Z',
      });
    });

    test('1. Outstanding invoices for Arnaw include Kolkata invoice when viewed from Howrah', () async {
      final invoices = await customerRepo.getOutstandingInvoices(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUST_ARNAW',
        token: token,
        employeeOutletId: howrahOutlet,
        isOwner: true,
      );

      expect(invoices, hasLength(1));
      expect(invoices.first['invoiceId'], 'INV_KOL_001');
      expect(invoices.first['outletId'], kolkataOutlet);
      expect(invoices.first['dueAmount'], 45000);
    });

    test('2. Settle Arnaw due as CASH at Howrah outlet via CustomerRepository', () async {
      final payment = await customerRepo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUST_ARNAW',
        collectedAtOutletId: howrahOutlet,
        amountPaise: 45000,
        paymentMethod: 'CASH',
        actorUid: 'CASHIER_HOWRAH',
        token: token,
        isOwner: true,
      );

      expect(payment.amountPaise, 45000);
      expect(payment.collectedAtOutletId, howrahOutlet);
      expect(payment.allocations, hasLength(1));
      expect(payment.allocations.first.invoiceId, 'INV_KOL_001');
      expect(payment.allocations.first.originalOutletId, kolkataOutlet);
      expect(payment.allocations.first.allocatedPaise, 45000);

      // Verify invoice is settled
      final inv = mockDb.getRaw(FirebaseConstants.invoices, 'INV_KOL_001')!;
      expect(inv['dueAmount'], 0);
      expect(inv['paidPaise'], 45000);
      expect(inv['status'], 'PAID');

      // Verify customer due is completely cleared (0 due)
      final cust = mockDb.getRaw(FirebaseConstants.customers, 'CUST_ARNAW')!;
      expect(cust['duePaise'], 0);
      expect(cust['advancePaise'], 0);

      // Verify payment document attributes
      final payDoc = mockDb.getRaw(FirebaseConstants.payments, payment.paymentId)!;
      expect(payDoc['collectedAtOutletId'], howrahOutlet);

      // Verify customer ledger entry records both collecting and selling outlets
      final ledgers = mockDb.collections[FirebaseConstants.customerLedgerEntries]?.values.toList() ?? [];
      expect(ledgers, hasLength(1));
      expect(ledgers.first['outletId'], howrahOutlet);
      expect(ledgers.first['originalOutletId'], kolkataOutlet);
      expect(ledgers.first['creditPaise'], 45000);
    });

    test('3. Settle Arnaw due using UPI at Howrah outlet via BillingRepository', () async {
      await billingRepo.settle(
        invoiceId: 'INV_KOL_001',
        customerId: 'CUST_ARNAW',
        amountPaise: 45000,
        mode: 'UPI',
        paymentAt: DateTime.now(),
        collectedAtOutletId: howrahOutlet,
        token: token,
      );

      // Verify invoice is settled
      final inv = mockDb.getRaw(FirebaseConstants.invoices, 'INV_KOL_001')!;
      expect(inv['dueAmount'], 0);
      expect(inv['paidPaise'], 45000);
      expect(inv['status'], 'PAID');

      // Verify customer due is cleared
      final cust = mockDb.getRaw(FirebaseConstants.customers, 'CUST_ARNAW')!;
      expect(cust['duePaise'], 0);
      expect(cust['advancePaise'], 0);

      // Verify payment collectedAtOutletId records Howrah
      final payments = mockDb.collections[FirebaseConstants.payments]?.values.toList() ?? [];
      expect(payments, hasLength(1));
      expect(payments.first['collectedAtOutletId'], howrahOutlet);
      expect(payments.first['mode'], 'UPI');

      // Verify ledger records Howrah as collecting outlet and Kolkata as origin
      final ledgers = mockDb.collections[FirebaseConstants.customerLedgerEntries]?.values.toList() ?? [];
      expect(ledgers, hasLength(1));
      expect(ledgers.first['outletId'], howrahOutlet);
      expect(ledgers.first['originalOutletId'], kolkataOutlet);
    });

    test('4. Settle Arnaw due when invoice fields omit invoiceId (doc ID only, e.g. SUMANE-26-00005)', () async {
      // Clear previous invoices and seed invoice WITHOUT 'invoiceId' in its fields map
      mockDb.collections[FirebaseConstants.invoices]?.clear();
      mockDb.seed(FirebaseConstants.invoices, 'REQ_SUMANE_26_00005', {
        'invoiceNumber': 'SUMANE-26-00005',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': kolkataOutlet,
        'customerId': 'CUST_ARNAW',
        'customerName': 'Arnaw',
        'customerPhone': '7319842283',
        'grandTotalPaise': 45000,
        'paidPaise': 0,
        'dueAmount': 45000,
        'status': 'PENDING',
        'createdAt': '2026-10-22T10:00:00Z',
      });

      // Reset customer due
      mockDb.seed(FirebaseConstants.customers, 'CUST_ARNAW', {
        'customerId': 'CUST_ARNAW',
        'tenantId': tenantId,
        'businessId': businessId,
        'name': 'Arnaw',
        'phone': '7319842283',
        'duePaise': 45000,
        'advancePaise': 0,
        'status': 'ACTIVE',
      });

      // Must succeed without throwing "Bad state: No element"
      final payment = await customerRepo.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: 'CUST_ARNAW',
        collectedAtOutletId: howrahOutlet,
        amountPaise: 45000,
        paymentMethod: 'CASH',
        actorUid: 'CASHIER_HOWRAH',
        token: token,
        isOwner: true,
      );

      expect(payment.amountPaise, 45000);

      // Verify invoice was updated
      final inv = mockDb.getRaw(FirebaseConstants.invoices, 'REQ_SUMANE_26_00005')!;
      expect(inv['dueAmount'], 0);
      expect(inv['paidPaise'], 45000);
      expect(inv['status'], 'PAID');

      // Verify customer due is 0
      final cust = mockDb.getRaw(FirebaseConstants.customers, 'CUST_ARNAW')!;
      expect(cust['duePaise'], 0);
      expect(cust['advancePaise'], 0);
    });
  });
}
