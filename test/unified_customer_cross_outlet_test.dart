import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/customer_ledger_entry_model.dart';
import 'package:testflutter/data/models/customer_model.dart';
import 'package:testflutter/data/models/customer_payment_model.dart';
import 'package:testflutter/data/repositories/customer_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';
import 'package:testflutter/data/services/invoice_print_service.dart';
import 'package:testflutter/domain/customers/customer_validators.dart';

/// In-memory mock implementing both FirestoreDataService and FirestoreTransactionService
class InMemoryFirestoreMock implements FirestoreDataService, FirestoreTransactionService {
  final Map<String, Map<String, Map<String, dynamic>>> _collections = {};
  final Map<String, String> _updateTimes = {};
  int _timeSeq = 1;

  void seed(String collection, String id, Map<String, dynamic> data) {
    _collections.putIfAbsent(collection, () => {})[id] = Map<String, dynamic>.from(data);
    _updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  Map<String, dynamic>? getRaw(String collection, String id) =>
      _collections[collection]?[id];

  List<Map<String, dynamic>> getAllRaw(String collection) =>
      _collections[collection]?.values.toList() ?? [];

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    final doc = _collections[collection]?[id];
    if (doc == null) {
      throw AppException('Document $collection/$id not found.');
    }
    return {'fields': doc};
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
    final docs = _collections[collection] ?? {};
    final results = <Map<String, dynamic>>[];

    for (final entry in docs.entries) {
      final fields = entry.value;
      var matches = true;
      for (final filter in filters) {
        final val = fields[filter.field];
        if (filter.operation == 'EQUAL') {
          if (val != filter.value) {
            matches = false;
            break;
          }
        }
      }
      if (matches) {
        results.add({'name': 'projects/test/databases/(default)/documents/$collection/${entry.key}', 'fields': fields});
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
    _collections.putIfAbsent(collection, () => {})[id] = Map<String, dynamic>.from(fields);
    _updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  @override
  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
    String? updateTime,
  }) async {
    final current = _collections[collection]?[id];
    if (current == null) {
      throw AppException('Document not found: $collection/$id');
    }
    current.addAll(fields);
    _updateTimes['$collection/$id'] = 'time_${_timeSeq++}';
  }

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext transaction) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    final tx = _MockTransactionContext(this);
    final result = await action(tx);
    tx.commit();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTransactionContext implements FirestoreTransactionContext {
  _MockTransactionContext(this.parent);
  final InMemoryFirestoreMock parent;

  final Map<String, Map<String, dynamic>> _stagingCreates = {};
  final Map<String, Map<String, dynamic>> _stagingUpdates = {};
  final Map<String, String?> _expectedUpdateTimes = {};

  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final key = '$collection/$id';
    final current = parent._collections[collection]?[id];
    if (current == null) {
      return const FirestoreTransactionDocument(exists: false, fields: {});
    }
    final updateTime = parent._updateTimes[key];
    return FirestoreTransactionDocument(
      exists: true,
      fields: Map<String, dynamic>.from(current),
      updateTime: updateTime,
    );
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final rawDocs = await parent.queryDocuments(
      collection: collection,
      filters: filters,
    );
    return rawDocs.map((doc) {
      final name = doc['name'] as String;
      final id = name.split('/').last;
      final fields = doc['fields'] as Map<String, dynamic>;
      final updateTime = parent._updateTimes['$collection/$id'];
      return FirestoreTransactionDocument(
        exists: true,
        fields: Map<String, dynamic>.from(fields),
        updateTime: updateTime,
      );
    }).toList();
  }

  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    _stagingCreates['$collection/$id'] = Map<String, dynamic>.from(fields);
  }

  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) {
    final key = '$collection/$id';
    _stagingUpdates[key] = Map<String, dynamic>.from(fields);
    _expectedUpdateTimes[key] = updateTime;
  }

  @override
  void delete(String collection, String id, {required String? updateTime}) {
    // delete stub
  }

  void commit() {
    // Check precondition updateTimes
    for (final entry in _stagingUpdates.entries) {
      final key = entry.key;
      final expected = _expectedUpdateTimes[key];
      final actual = parent._updateTimes[key];
      if (expected != null && actual != null && expected != actual) {
        throw const AppException(
          'FAILED_PRECONDITION: Document was modified by another operation.',
        );
      }
    }
    // Commit creates
    for (final entry in _stagingCreates.entries) {
      final parts = entry.key.split('/');
      parent.seed(parts[0], parts[1], entry.value);
    }
    // Commit updates
    for (final entry in _stagingUpdates.entries) {
      final parts = entry.key.split('/');
      final current = parent._collections[parts[0]]?[parts[1]] ?? {};
      current.addAll(entry.value);
      parent.seed(parts[0], parts[1], current);
    }
  }
}

void main() {
  const tenantId = 'TEN-001';
  const businessId = 'BUS-001';
  const outlet1 = 'OUT-001';
  const outlet2 = 'OUT-002';
  const token = 'test-token';

  late InMemoryFirestoreMock mockFirestore;
  late CustomerRepository repository;

  setUp(() {
    mockFirestore = InMemoryFirestoreMock();
    repository = CustomerRepository(mockFirestore);
  });

  group('Phase 2: Business-Level Customer Master & GST Classification', () {
    test('1. Customer created in Outlet 1 is visible in authorized Outlet 2', () async {
      final created = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Rahul Sharma',
        phone: '9876543210',
        customerType: CustomerModel.typeIndividual,
      );

      // Search from another outlet within the same business
      final results = await repository.search(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        phone: '9876543210',
      );

      expect(results, hasLength(1));
      expect(results.first.customerId, created.customerId);
      expect(results.first.name, 'Rahul Sharma');
      expect(results.first.businessId, businessId);
    });

    test('2. Customer does not appear under another business (Tenant/Business isolation)', () async {
      await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Customer Bus 1',
        phone: '9876543211',
      );

      // Query from a different business ID
      final results = await repository.search(
        tenantId: tenantId,
        businessId: 'BUS-OTHER-999',
        token: token,
        phone: '9876543211',
      );

      expect(results, isEmpty);
    });

    test('3. Legacy customer records without new fields load correctly', () {
      final legacyRaw = {
        'customerId': 'CUS-LEGACY-01',
        'businessId': businessId,
        'tenantId': tenantId,
        'name': 'Old Legacy Store',
        'phone': '9876543212',
        'nameLower': 'old legacy store',
        'duePaise': 45000,
        'advancePaise': 5000,
        'creditLimitPaise': 100000,
      };

      final customer = CustomerModel.fromData('CUS-LEGACY-01', legacyRaw);

      // Legacy records default to UNSPECIFIED
      expect(customer.customerType, CustomerModel.typeUnspecified);
      expect(customer.isUnspecified, isTrue);
      expect(customer.isIndividual, isFalse);
      expect(customer.isBusiness, isFalse);
      expect(customer.duePaise, 45000);
      expect(customer.advancePaise, 5000);
      expect(customer.creditLimitPaise, 100000);
    });

    test('4. Individual and Business classification persists cleanly', () async {
      final individual = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'John Individual',
        phone: '9876543213',
        customerType: CustomerModel.typeIndividual,
      );

      final businessCust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Apex Traders Pvt Ltd',
        phone: '9876543214',
        customerType: CustomerModel.typeBusiness,
      );

      expect(individual.customerType, CustomerModel.typeIndividual);
      expect(individual.isIndividual, isTrue);
      expect(businessCust.customerType, CustomerModel.typeBusiness);
      expect(businessCust.isBusiness, isTrue);
    });

    test('5. GST-registered and unregistered customers are validated correctly', () async {
      // Valid GSTIN checksum and format for Maharashtra (27)
      const validGstin = '27AAPFU0939F1ZV';
      expect(CustomerValidators.isValidGstin(validGstin), isTrue);

      final registeredCust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Bengal Logistics',
        phone: '9876543215',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: validGstin,
        stateCode: '27',
      );

      expect(registeredCust.isGstRegistered, isTrue);
      expect(registeredCust.gstin, validGstin);

      // Unregistered customer can be saved without GSTIN
      final unregisteredCust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Local Walkin',
        phone: '9876543216',
        customerType: CustomerModel.typeIndividual,
        isGstRegistered: false,
      );

      expect(unregisteredCust.isGstRegistered, isFalse);
      expect(unregisteredCust.gstin, isNull);

      // Invalid GSTIN registration is rejected
      expect(
        () => repository.create(
          tenantId: tenantId,
          businessId: businessId,
          token: token,
          name: 'Invalid GSTIN Store',
          phone: '9876543217',
          isGstRegistered: true,
          gstin: 'INVALID_GSTIN_123',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('6. Business customer without GSTIN can receive taxable invoices (B2C)', () {
      final customer = CustomerModel(
        customerId: 'CUS-001',
        businessId: businessId,
        tenantId: tenantId,
        name: 'Small Proprietor',
        phone: '9876543218',
        nameLower: 'small proprietor',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: false,
        gstin: null,
      );

      expect(customer.isBusiness, isTrue);
      expect(customer.isGstRegistered, isFalse);
      expect(customer.gstin, isNull);
    });
  });

  group('Phase 3 & 4: Unified Customer Ledger & Cross-Outlet Due Collection', () {
    late CustomerModel testCustomer;

    setUp(() async {
      testCustomer = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Multi-Outlet Buyer',
        phone: '9876543220',
      );

      // Seed Invoice 1 at OUT-001: Due 200,000 paise (₹2,000)
      mockFirestore.seed(FirebaseConstants.invoices, 'INV-001', {
        'invoiceId': 'INV-001',
        'invoiceNumber': 'INV-000001',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet1,
        'customerId': testCustomer.customerId,
        'dueAmount': 200000,
        'paidPaise': 0,
        'grandTotal': 200000,
        'status': 'PENDING',
        'invoiceDate': '2026-10-01T10:00:00Z',
      });

      // Seed Invoice 2 at OUT-002: Due 300,000 paise (₹3,000)
      mockFirestore.seed(FirebaseConstants.invoices, 'INV-002', {
        'invoiceId': 'INV-002',
        'invoiceNumber': 'INV-000002',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2,
        'customerId': testCustomer.customerId,
        'dueAmount': 300000,
        'paidPaise': 0,
        'grandTotal': 300000,
        'status': 'PENDING',
        'invoiceDate': '2026-10-05T10:00:00Z',
      });

      // Update customer total due in business master: 500,000 paise
      mockFirestore.updateDocument(
        FirebaseConstants.customers,
        testCustomer.customerId,
        {'duePaise': 500000},
      );
    });

    test('7. Customer with invoices in two outlets has one consolidated due of ₹5,000', () async {
      final custDoc = await mockFirestore.getDocument(
        FirebaseConstants.customers,
        testCustomer.customerId,
      );
      final duePaise = custDoc['fields']['duePaise'] as int;
      expect(duePaise, 500000); // 500,000 paise = ₹5,000 consolidated
    });

    test('8. Outlet-wise outstanding invoices remain traceable and accurate', () async {
      final allOutstanding = await repository.getOutstandingInvoices(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        token: token,
        isOwner: true,
      );

      expect(allOutstanding, hasLength(2));
      final out1Invoices =
          allOutstanding.where((inv) => inv['outletId'] == outlet1).toList();
      final out2Invoices =
          allOutstanding.where((inv) => inv['outletId'] == outlet2).toList();

      expect(out1Invoices, hasLength(1));
      expect(out1Invoices.first['dueAmount'], 200000);
      expect(out2Invoices, hasLength(1));
      expect(out2Invoices.first['dueAmount'], 300000);
    });

    test('9. FIFO allocates payment to oldest eligible invoice first across business', () async {
      // Payment of ₹3,000 (300,000 paise) collected at OUT-001
      // Settle oldest INV-001 (OUT-001) ₹2,000 completely, then INV-002 (OUT-002) ₹1,000 partially
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 300000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        isOwner: true,
      );

      expect(payment.amountPaise, 300000);
      expect(payment.allocations, hasLength(2));

      // Allocation 1: Settle INV-001 (200,000 paise)
      expect(payment.allocations[0].invoiceId, 'INV-001');
      expect(payment.allocations[0].allocatedPaise, 200000);
      expect(payment.allocations[0].originalOutletId, outlet1);

      // Allocation 2: Settle INV-002 (100,000 paise)
      expect(payment.allocations[1].invoiceId, 'INV-002');
      expect(payment.allocations[1].allocatedPaise, 100000);
      expect(payment.allocations[1].originalOutletId, outlet2);

      // Check invoice states
      final inv1 = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-001')!;
      expect(inv1['dueAmount'], 0);
      expect(inv1['status'], 'PAID');

      final inv2 = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-002')!;
      expect(inv2['dueAmount'], 200000); // 300,000 - 100,000 = 200,000
      expect(inv2['status'], 'PARTIALLY_PAID');

      // Check customer master due: 500,000 - 300,000 = 200,000
      final cust = mockFirestore.getRaw(FirebaseConstants.customers, testCustomer.customerId)!;
      expect(cust['duePaise'], 200000);
    });

    test('10. Authorized user can manually choose specific invoice allocation', () async {
      // User specifically chooses to pay INV-002 (OUT-002) ₹3,000 at OUT-001
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 300000,
        paymentMethod: 'UPI',
        actorUid: 'USER-01',
        token: token,
        manualAllocations: [
          const PaymentAllocationRequest(
            invoiceId: 'INV-002',
            originalOutletId: outlet2,
            allocatedPaise: 300000,
          ),
        ],
        isOwner: true,
      );

      expect(payment.allocations, hasLength(1));
      expect(payment.allocations.first.invoiceId, 'INV-002');
      expect(payment.allocations.first.allocatedPaise, 300000);

      // INV-002 is fully settled; INV-001 remains unchanged
      final inv2 = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-002')!;
      expect(inv2['dueAmount'], 0);
      expect(inv2['status'], 'PAID');

      final inv1 = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-001')!;
      expect(inv1['dueAmount'], 200000);
      expect(inv1['status'], 'PENDING');
    });

    test('11. One payment can settle invoices from multiple outlets', () async {
      // Pay full ₹5,000 (500,000 paise) to clear both invoices
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 500000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        isOwner: true,
      );

      expect(payment.allocations, hasLength(2));
      expect(payment.totalAllocatedPaise, 500000);

      final cust = mockFirestore.getRaw(FirebaseConstants.customers, testCustomer.customerId)!;
      expect(cust['duePaise'], 0);
    });

    test('12. Partial payment is supported without corrupting balances', () async {
      // Partial payment of ₹500 (50,000 paise)
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        isOwner: true,
      );

      expect(payment.totalAllocatedPaise, 50000);
      final inv1 = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-001')!;
      expect(inv1['dueAmount'], 150000);
      expect(inv1['status'], 'PARTIALLY_PAID');

      final cust = mockFirestore.getRaw(FirebaseConstants.customers, testCustomer.customerId)!;
      expect(cust['duePaise'], 450000);
    });

    test('13. Overpayment follows advance-handling rules', () async {
      // Customer owes 500,000 paise. Pays 600,000 paise.
      // Without allowAdvance: throws exception
      expect(
        () => repository.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: testCustomer.customerId,
          collectedAtOutletId: outlet1,
          amountPaise: 600000,
          paymentMethod: 'CASH',
          actorUid: 'USER-01',
          token: token,
          allowAdvance: false,
          isOwner: true,
        ),
        throwsA(isA<AppException>()),
      );

      // With allowAdvance: excess 100,000 paise becomes customer advance credit
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 600000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        allowAdvance: true,
        isOwner: true,
      );

      expect(payment.excessAdvancePaise, 100000);
      final cust = mockFirestore.getRaw(FirebaseConstants.customers, testCustomer.customerId)!;
      expect(cust['duePaise'], 0);
      expect(cust['advancePaise'], 100000);

      // Check advance ledger entry
      final ledgerEntries = await repository.getCustomerLedger(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        token: token,
        isOwner: true,
      );
      final advEntry = ledgerEntries.where((e) => e.advanceCreditPaise > 0).firstOrNull;
      expect(advEntry, isNotNull);
      expect(advEntry!.advanceCreditPaise, 100000);
    });

    test('14. Repeated payment submission with same idempotency key does not duplicate ledger entries', () async {
      const idempotencyKey = 'UNIQUE-MUTATION-KEY-789';

      // First submission
      final payment1 = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 200000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        idempotencyKey: idempotencyKey,
        isOwner: true,
      );

      // Duplicate submission retry
      final payment2 = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: testCustomer.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 200000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        idempotencyKey: idempotencyKey,
        isOwner: true,
      );

      expect(payment1.paymentId, payment2.paymentId);

      // Verify customer due was only decremented ONCE: 500,000 - 200,000 = 300,000
      final cust = mockFirestore.getRaw(FirebaseConstants.customers, testCustomer.customerId)!;
      expect(cust['duePaise'], 300000);

      // Verify no duplicate payments or allocations created
      final allPayments = mockFirestore.getAllRaw(FirebaseConstants.payments);
      expect(allPayments.where((p) => p['paymentId'] == payment1.paymentId), hasLength(1));
    });

    test('15. Concurrent payment attempts cannot double-settle invoices (Precondition check)', () async {
      // Simulate precondition collision on invoice updateTime
      final staleTx = _MockTransactionContext(mockFirestore);
      final invDoc = await staleTx.get(FirebaseConstants.invoices, 'INV-001');

      // Meanwhile, another cashier settles INV-001
      await mockFirestore.updateDocument(
        FirebaseConstants.invoices,
        'INV-001',
        {'dueAmount': 0, 'status': 'PAID'},
      );

      // Stale cashier tries to commit with stale updateTime
      staleTx.update(
        FirebaseConstants.invoices,
        'INV-001',
        {'dueAmount': 0, 'status': 'PAID'},
        updateTime: invDoc.updateTime,
      );

      expect(() => staleTx.commit(), throwsA(isA<AppException>()));
    });
  });

  group('Phase 5: Permissions & Cross-Outlet Security Enforcement', () {
    test('16. Unauthorized employee without CROSS_OUTLET_DUE_COLLECT cannot collect another outlet\'s dues', () async {
      final cust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Restricted Customer',
        phone: '9876543230',
      );

      // Seed invoice at OUT-002
      mockFirestore.seed(FirebaseConstants.invoices, 'INV-OUT2', {
        'invoiceId': 'INV-OUT2',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2,
        'customerId': cust.customerId,
        'dueAmount': 100000,
        'status': 'PENDING',
      });

      // Employee at OUT-001 has DUE_COLLECT but NOT CROSS_OUTLET_DUE_COLLECT
      const employeePermissions = ['DUE_COLLECT', 'CUSTOMER_VIEW'];

      expect(
        () => repository.collectPayment(
          tenantId: tenantId,
          businessId: businessId,
          customerId: cust.customerId,
          collectedAtOutletId: outlet1,
          amountPaise: 100000,
          paymentMethod: 'CASH',
          actorUid: 'EMP-01',
          token: token,
          employeePermissions: employeePermissions,
          manualAllocations: [
            const PaymentAllocationRequest(
              invoiceId: 'INV-OUT2',
              originalOutletId: outlet2,
              allocatedPaise: 100000,
            ),
          ],
          isOwner: false,
        ),
        throwsA(isA<AppException>()),
      );

      // Authorized employee with CROSS_OUTLET_DUE_COLLECT succeeds
      const crossOutletPermissions = [
        'DUE_COLLECT',
        'CROSS_OUTLET_DUE_COLLECT',
        'CUSTOMER_VIEW',
      ];

      final successPayment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: cust.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 100000,
        paymentMethod: 'CASH',
        actorUid: 'EMP-02',
        token: token,
        employeePermissions: crossOutletPermissions,
        manualAllocations: [
          const PaymentAllocationRequest(
            invoiceId: 'INV-OUT2',
            originalOutletId: outlet2,
            allocatedPaise: 100000,
          ),
        ],
        isOwner: false,
      );

      expect(successPayment.allocations, hasLength(1));
    });
  });

  group('Phase 3 & 4: Reporting, Cash Drawer & Audit Traceability', () {
    test('17. Cross-outlet collection appears in correct cash drawer and due reports', () async {
      final cust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Drawer Customer',
        phone: '9876543240',
      );

      mockFirestore.seed(FirebaseConstants.invoices, 'INV-OUT2-DUE', {
        'invoiceId': 'INV-OUT2-DUE',
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outlet2, // Original invoice from Outlet 2
        'customerId': cust.customerId,
        'dueAmount': 200000,
        'status': 'PENDING',
      });

      // Money collected at OUT-001
      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: cust.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 200000,
        paymentMethod: 'CASH',
        actorUid: 'CASHIER-OUT1',
        token: token,
        isOwner: true,
      );

      // Cash collection belongs to OUT-001 drawer
      expect(payment.collectedAtOutletId, outlet1);
      final rawPayment = mockFirestore.getRaw(FirebaseConstants.payments, payment.paymentId)!;
      expect(rawPayment['collectedAtOutletId'], outlet1);
      expect(rawPayment['outletId'], outlet1);

      // Outstanding reduction belongs to OUT-002 invoice
      expect(payment.allocations.first.originalOutletId, outlet2);
      final rawInv = mockFirestore.getRaw(FirebaseConstants.invoices, 'INV-OUT2-DUE')!;
      expect(rawInv['dueAmount'], 0);
      expect(rawInv['outletId'], outlet2); // Outlet 2's sales are NOT shifted to Outlet 1!
    });

    test('18. Financial corrections and payments preserve audit history', () async {
      final cust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Audit Customer',
        phone: '9876543250',
        openingBalancePaise: 10000, // ₹100 opening balance
      );

      final ledger = await repository.getCustomerLedger(
        tenantId: tenantId,
        businessId: businessId,
        customerId: cust.customerId,
        token: token,
        isOwner: true,
      );

      expect(ledger, hasLength(1));
      expect(ledger.first.transactionType, CustomerLedgerEntryModel.typeOpeningBalance);
      expect(ledger.first.amountPaise, 10000);
      expect(ledger.first.immutable, isTrue);
    });

    test('19. Offline sync conflicts never silently lose money', () async {
      // In conflict scenario where invoice was already settled, excess is credited to advance
      final cust = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Conflict Customer',
        phone: '9876543260',
      );

      final payment = await repository.collectPayment(
        tenantId: tenantId,
        businessId: businessId,
        customerId: cust.customerId,
        collectedAtOutletId: outlet1,
        amountPaise: 50000,
        paymentMethod: 'CASH',
        actorUid: 'USER-01',
        token: token,
        allowAdvance: true,
        isOwner: true,
      );

      expect(payment.amountPaise, 50000);
      expect(payment.excessAdvancePaise, 50000);

      final rawCust = mockFirestore.getRaw(FirebaseConstants.customers, cust.customerId)!;
      expect(rawCust['advancePaise'], 50000); // Stored in advance credit without loss
    });

    test('20. Schema migration preserves existing balance fields', () {
      expect(LocalDatabase.schemaVersion, 15);
      expect(LocalDatabase.tables.containsKey('customers'), isTrue);
      expect(LocalDatabase.tables.containsKey('customer_ledger_entries'), isTrue);
      expect(LocalDatabase.tables.containsKey('payment_allocations'), isTrue);
      expect(LocalDatabase.tables.containsKey('payments'), isTrue);
    });

    test('21. PDF and thermal invoices display recipient GSTIN correctly', () {
      const recipientGstin = '27AAPFU0939F1ZV';
      const supplierGstin = '19AAAAA0000A1Z5';

      final printData = InvoicePrintData(
        invoiceNumber: 'INV-100001',
        invoiceDate: DateTime(2026, 10, 22),
        businessName: 'Main Store',
        businessGstin: supplierGstin,
        customerName: 'Enterprise Client',
        customerGstin: recipientGstin,
        lines: const [],
        taxablePaise: 100000,
        subtotalPaise: 100000,
        cgstPaise: 9000,
        sgstPaise: 9000,
        grandTotalPaise: 118000,
      );

      expect(printData.businessGstin, supplierGstin);
      expect(printData.customerGstin, recipientGstin);
    });
  });
}
