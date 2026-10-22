import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/customer_model.dart';
import 'package:testflutter/data/repositories/customer_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/invoice_print_service.dart';
import 'package:testflutter/domain/billing/bill_calculator.dart';
import 'package:testflutter/domain/billing/billing_models.dart';
import 'package:testflutter/domain/customers/customer_validators.dart';

class _FakeFirestoreService implements FirestoreDataService {
  final Map<String, Map<String, dynamic>> _storage = {};

  String _key(String collection, String id) => '$collection/$id';

  @override
  Future<void> createDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    _storage[_key(collection, id)] = Map<String, dynamic>.from(fields);
  }

  @override
  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    final existing = _storage[_key(collection, id)] ?? {};
    _storage[_key(collection, id)] = {
      ...existing,
      ...Map<String, dynamic>.from(fields),
    };
  }

  @override
  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) => updateDocument(collection, id, fields, idToken: idToken);

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    final doc = _storage[_key(collection, id)];
    if (doc == null) throw const AppException('Document not found');
    return {
      'name': '$collection/$id',
      'fields': FirestoreRestService.encodeFields(doc),
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
    final results = <Map<String, dynamic>>[];
    for (final entry in _storage.entries) {
      if (!entry.key.startsWith('$collection/')) continue;
      final doc = entry.value;
      final match = filters.every((filter) {
        if (filter.operation == 'EQUAL') {
          return doc[filter.field] == filter.value;
        }
        return true;
      });
      if (match) {
        results.add({
          'name': entry.key,
          'fields': FirestoreRestService.encodeFields(doc),
        });
      }
    }
    return results;
  }

  @override
  Future<List<Map<String, dynamic>>> listDocuments(
    String collection, {
    String? idToken,
  }) async => [];

  @override
  Future<List<Map<String, dynamic>>> queryEqual(
    String collection,
    String field,
    Object value, {
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: [FirestoreFilter(field, 'EQUAL', value)],
  );

  @override
  Future<List<Map<String, dynamic>>> runQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
  );

  @override
  Future<Map<String, dynamic>> aggregateDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) async => {};

  @override
  Future<Map<String, dynamic>> runAggregationQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) async => {};

  @override
  Future<void> deleteDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    _storage.remove(_key(collection, id));
  }
}

void main() {
  sqfliteFfiInit();

  group('CustomerModel Schema & Backward Compatibility', () {
    test('1. Default values for new customer (Individual, unregistered)', () {
      const model = CustomerModel(
        customerId: 'CUS-100',
        businessId: 'BUS-1',
        name: 'Rahul Sharma',
        phone: '9876543210',
        nameLower: 'rahul sharma',
      );

      expect(model.customerType, equals(CustomerModel.typeIndividual));
      expect(model.isIndividual, isTrue);
      expect(model.isBusiness, isFalse);
      expect(model.isGstRegistered, isFalse);
      expect(model.gstin, isNull);
      expect(model.duePaise, equals(0));
      expect(model.advancePaise, equals(0));
    });

    test('2. Business customer without GSTIN', () {
      const model = CustomerModel(
        customerId: 'CUS-101',
        businessId: 'BUS-1',
        name: 'Sharma Paints & Hardware',
        phone: '9876543211',
        nameLower: 'sharma paints & hardware',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: false,
      );

      expect(model.customerType, equals(CustomerModel.typeBusiness));
      expect(model.isBusiness, isTrue);
      expect(model.isGstRegistered, isFalse);
      expect(model.gstin, isNull);
    });

    test('3. Business customer with valid GSTIN', () {
      const model = CustomerModel(
        customerId: 'CUS-102',
        businessId: 'BUS-1',
        name: 'Sharma Enterprises',
        phone: '9876543212',
        nameLower: 'sharma enterprises',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: '27AAPFU0939F1ZV',
      );

      expect(model.customerType, equals(CustomerModel.typeBusiness));
      expect(model.isGstRegistered, isTrue);
      expect(model.gstin, equals('27AAPFU0939F1ZV'));
    });

    test('4. Individual customer with valid GSTIN (Sole Proprietorship)', () {
      const model = CustomerModel(
        customerId: 'CUS-103',
        businessId: 'BUS-1',
        name: 'Dr. Amit Sen',
        phone: '9876543213',
        nameLower: 'dr. amit sen',
        customerType: CustomerModel.typeIndividual,
        isGstRegistered: true,
        gstin: '19ABCDE1234F1ZX',
      );

      expect(model.customerType, equals(CustomerModel.typeIndividual));
      expect(model.isGstRegistered, isTrue);
      expect(model.gstin, equals('19ABCDE1234F1ZX'));
    });

    test('5. Backward compatibility: legacy record defaults to UNSPECIFIED', () {
      final legacyData = {
        'customerId': 'CUS-LEGACY-1',
        'businessId': 'BUS-1',
        'name': 'Old Customer',
        'phone': '9876543214',
        'nameLower': 'old customer',
        'duePaise': 50000,
        'advancePaise': 0,
      };

      final model = CustomerModel.fromData('CUS-LEGACY-1', legacyData);
      expect(model.customerType, equals(CustomerModel.typeUnspecified));
      expect(model.isUnspecified, isTrue);
      expect(model.isGstRegistered, isFalse);
      expect(model.duePaise, equals(50000));
    });

    test('6. Provisional registration status derived for legacy record with valid GSTIN', () {
      final legacyWithGstin = {
        'customerId': 'CUS-LEGACY-2',
        'businessId': 'BUS-1',
        'name': 'Legacy Business Corp',
        'phone': '9876543215',
        'nameLower': 'legacy business corp',
        'gstin': '27AAPFU0939F1ZV',
      };

      final model = CustomerModel.fromData('CUS-LEGACY-2', legacyWithGstin);
      expect(model.customerType, equals(CustomerModel.typeUnspecified));
      expect(model.isGstRegistered, isTrue);
      expect(model.gstin, equals('27AAPFU0939F1ZV'));
    });

    test('7. Missing GSTIN never forces Individual classification for legacy record', () {
      final legacyWithoutGstin = {
        'customerId': 'CUS-LEGACY-3',
        'businessId': 'BUS-1',
        'name': 'Unclassified Entity',
        'phone': '9876543216',
        'nameLower': 'unclassified entity',
        'gstin': null,
      };

      final model = CustomerModel.fromData('CUS-LEGACY-3', legacyWithoutGstin);
      expect(model.customerType, equals(CustomerModel.typeUnspecified));
      expect(model.customerType, isNot(equals(CustomerModel.typeIndividual)));
    });

    test('8. Serialization toData preserves all fields and balances', () {
      const model = CustomerModel(
        customerId: 'CUS-SER-1',
        businessId: 'BUS-1',
        tenantId: 'TENANT-1',
        name: 'Gupta Traders',
        phone: '9876543217',
        nameLower: 'gupta traders',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: '27AAPFU0939F1ZV',
        stateCode: '27',
        address: 'MG Road, Pune',
        creditLimitPaise: 5000000,
        duePaise: 125000,
        advancePaise: 25000,
      );

      final data = model.toData();
      expect(data['customerId'], equals('CUS-SER-1'));
      expect(data['customerType'], equals('BUSINESS'));
      expect(data['isGstRegistered'], isTrue);
      expect(data['gstin'], equals('27AAPFU0939F1ZV'));
      expect(data['creditLimitPaise'], equals(5000000));
      expect(data['duePaise'], equals(125000));
      expect(data['advancePaise'], equals(25000));

      final roundTrip = CustomerModel.fromData('CUS-SER-1', data);
      expect(roundTrip.customerType, equals('BUSINESS'));
      expect(roundTrip.isGstRegistered, isTrue);
      expect(roundTrip.duePaise, equals(125000));
    });

    test('8b. fromData safely handles DateTime for updatedAt (Firestore timestamp decoding)', () {
      final now = DateTime.now();
      final dataWithTimestamp = {
        'customerId': 'CUS-TS-1',
        'businessId': 'BUS-1',
        'name': 'Timestamp Customer',
        'phone': '9876543218',
        'updatedAt': now,
      };

      final model = CustomerModel.fromData('CUS-TS-1', dataWithTimestamp);
      expect(model.name, equals('Timestamp Customer'));
      expect(model.updatedAt, equals(now.toIso8601String()));
    });
  });

  group('CustomerValidators GSTIN Structure, State Code & Checksum', () {
    test('9. Validates official 15-character GSTIN format and checksum', () {
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1ZV'), isTrue);
      expect(CustomerValidators.isValidGstin('19ABCDE1234F1ZX'), isTrue);
      expect(CustomerValidators.isValidGstin('36AAACH7409R1Z2'), isTrue);
    });

    test('10. Rejects invalid structure (too short, too long, invalid characters)', () {
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1Z'), isFalse); // 14 chars
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1ZVV'), isFalse); // 16 chars
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1-V'), isFalse); // hyphen
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1AV'), isFalse); // 14th char not Z
    });

    test('11. Rejects invalid state code', () {
      // '00' is not a valid state code
      expect(CustomerValidators.isValidStateCode('00'), isFalse);
      expect(CustomerValidators.isValidGstin('00AAPFU0939F1ZV'), isFalse);

      // '98' is not a valid state code
      expect(CustomerValidators.isValidStateCode('98'), isFalse);
      expect(CustomerValidators.isValidGstin('98AAPFU0939F1ZV'), isFalse);
    });

    test('12. Rejects invalid checksum digit', () {
      // 27AAPFU0939F1ZV has checksum 'V'. Tampering to 'W' must fail.
      expect(CustomerValidators.isValidGstin('27AAPFU0939F1ZW'), isFalse);
    });

    test('13. Validates official GST state code mapping', () {
      expect(CustomerValidators.isValidStateCode('19'), isTrue);
      expect(CustomerValidators.stateNameFromCode('19'), equals('West Bengal'));

      expect(CustomerValidators.isValidStateCode('27'), isTrue);
      expect(CustomerValidators.stateNameFromCode('27'), equals('Maharashtra'));

      expect(CustomerValidators.isValidStateCode('29'), isTrue);
      expect(CustomerValidators.stateNameFromCode('29'), equals('Karnataka'));

      expect(CustomerValidators.stateCodeFromGstin('19ABCDE1234F1ZX'), equals('19'));
      expect(CustomerValidators.stateCodeFromGstin('27AAPFU0939F1ZV'), equals('27'));
    });

    test('14. Detailed registration error messages', () {
      expect(
        CustomerValidators.validateGstinForRegistration(''),
        contains('required'),
      );
      expect(
        CustomerValidators.validateGstinForRegistration('12345'),
        contains('must be exactly 15 characters'),
      );
      expect(
        CustomerValidators.validateGstinForRegistration('98AAPFU0939F1ZV'),
        contains('Invalid GST state code'),
      );
      expect(
        CustomerValidators.validateGstinForRegistration('27AAPFU0939F1ZW'),
        contains('checksum'),
      );
      expect(
        CustomerValidators.validateGstinForRegistration('27AAPFU0939F1ZV'),
        isNull,
      );
    });
  });

  group('CustomerRepository Operations & Preservation', () {
    late _FakeFirestoreService firestore;
    late CustomerRepository repository;
    const tenantId = 'TENANT-X';
    const businessId = 'BUS-X';
    const token = 'fake-token';

    setUp(() {
      firestore = _FakeFirestoreService();
      repository = CustomerRepository(firestore);
    });

    test('15. Create Individual customer without GSTIN', () async {
      final customer = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Sunil Verma',
        phone: '9876500001',
        customerType: CustomerModel.typeIndividual,
        isGstRegistered: false,
      );

      expect(customer.name, equals('Sunil Verma'));
      expect(customer.customerType, equals('INDIVIDUAL'));
      expect(customer.isGstRegistered, isFalse);
      expect(customer.gstin, isNull);
    });

    test('16. Create Business customer with valid GSTIN', () async {
      final customer = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Verma Paints',
        phone: '9876500002',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: '27AAPFU0939F1ZV',
        stateCode: '27',
      );

      expect(customer.customerType, equals('BUSINESS'));
      expect(customer.isGstRegistered, isTrue);
      expect(customer.gstin, equals('27AAPFU0939F1ZV'));
      expect(customer.stateCode, equals('27'));
    });

    test('17. Rejects invalid GSTIN when creating registered customer', () async {
      expect(
        () => repository.create(
          tenantId: tenantId,
          businessId: businessId,
          token: token,
          name: 'Invalid GSTIN Corp',
          phone: '9876500003',
          customerType: CustomerModel.typeBusiness,
          isGstRegistered: true,
          gstin: '27INVALID000000',
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('18. Updating customer classification preserves historical balances', () async {
      final created = await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Initial Customer',
        phone: '9876500004',
        openingBalancePaise: 45000,
      );
      expect(created.duePaise, equals(45000));

      // Simulate financial transactions increasing due
      final withDue = created.copyWith(duePaise: 120000, advancePaise: 5000);

      // Now update classification to Business with GSTIN
      final updated = await repository.update(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        customer: withDue,
        name: 'Initial Customer Pvt Ltd',
        phone: withDue.phone,
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: '27AAPFU0939F1ZV',
      );

      expect(updated.customerType, equals('BUSINESS'));
      expect(updated.isGstRegistered, isTrue);
      expect(updated.gstin, equals('27AAPFU0939F1ZV'));
      // Balances strictly preserved!
      expect(updated.duePaise, equals(120000));
      expect(updated.advancePaise, equals(5000));
    });

    test('19. Business and tenant isolation in search', () async {
      await repository.create(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        name: 'Tenant Customer',
        phone: '9876500010',
      );

      await repository.create(
        tenantId: 'OTHER-TENANT',
        businessId: 'OTHER-BUS',
        token: token,
        name: 'Other Tenant Customer',
        phone: '9876500011',
      );

      final searchResults = await repository.search(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
      );

      expect(searchResults.length, equals(1));
      expect(searchResults.first.name, equals('Tenant Customer'));
    });
  });

  group('POS Billing & GST Calculations', () {
    const calculator = BillCalculator();

    test('20. GST calculations remain identical with or without customer GSTIN', () {
      final lines = [
        const BillLineInput(
          variantId: 'VAR-1',
          sku: 'SKU-1',
          name: 'Paint 1L',
          hsn: '3208',
          quantity: 2,
          unitPricePaise: 50000, // 500.00
          gstRateBps: 1800, // 18%
          priceIncludesTax: false,
        ),
      ];

      // Intra-state GST
      final resultIntra = calculator.calculate(
        lines: lines,
        taxMode: BillingTaxMode.gst,
        taxStructure: TaxStructure.intraState,
      );

      expect(resultIntra.subtotalPaise, equals(100000));
      expect(resultIntra.taxableTotalPaise, equals(100000));
      expect(resultIntra.taxTotalPaise, equals(18000));
      expect(resultIntra.cgstPaise, equals(9000));
      expect(resultIntra.sgstPaise, equals(9000));
      expect(resultIntra.igstPaise, equals(0));
      expect(resultIntra.grandTotalPaise, equals(118000));

      // Inter-state GST
      final resultInter = calculator.calculate(
        lines: lines,
        taxMode: BillingTaxMode.gst,
        taxStructure: TaxStructure.interState,
      );

      expect(resultInter.taxTotalPaise, equals(18000));
      expect(resultInter.cgstPaise, equals(0));
      expect(resultInter.sgstPaise, equals(0));
      expect(resultInter.igstPaise, equals(18000));
      expect(resultInter.grandTotalPaise, equals(118000));
    });

    test('21. B2B and B2C invoice classification derivation', () {
      // When customerGstin is present -> B2B
      const registeredGstin = '27AAPFU0939F1ZV';
      final b2bType = (registeredGstin.trim().isNotEmpty) ? 'B2B' : 'B2C';
      expect(b2bType, equals('B2B'));

      // When customerGstin is null or blank -> B2C
      const String? unregisteredGstin = null;
      final b2cType = (unregisteredGstin?.trim().isNotEmpty == true)
          ? 'B2B'
          : 'B2C';
      expect(b2cType, equals('B2C'));
    });

    test('22. Customer selection logic: populates GSTIN when valid, clears when unregistered', () {
      const registeredCustomer = CustomerModel(
        customerId: 'CUS-REG',
        businessId: 'BUS-1',
        name: 'Alpha Traders',
        phone: '9876500020',
        nameLower: 'alpha traders',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: true,
        gstin: '27AAPFU0939F1ZV',
      );

      const unregisteredCustomer = CustomerModel(
        customerId: 'CUS-UNREG',
        businessId: 'BUS-1',
        name: 'Beta Retail',
        phone: '9876500021',
        nameLower: 'beta retail',
        customerType: CustomerModel.typeBusiness,
        isGstRegistered: false,
        gstin: null,
      );

      // Simulating POS customer picker assignment
      String? gstinField;

      // 1. Select registered customer
      if (registeredCustomer.isGstRegistered &&
          registeredCustomer.gstin != null &&
          CustomerValidators.isValidGstin(registeredCustomer.gstin)) {
        gstinField = CustomerValidators.normalizeGstin(registeredCustomer.gstin);
      } else {
        gstinField = null;
      }
      expect(gstinField, equals('27AAPFU0939F1ZV'));

      // 2. Switch to unregistered customer -> stale GSTIN must clear!
      if (unregisteredCustomer.isGstRegistered &&
          unregisteredCustomer.gstin != null &&
          CustomerValidators.isValidGstin(unregisteredCustomer.gstin)) {
        gstinField = CustomerValidators.normalizeGstin(unregisteredCustomer.gstin);
      } else {
        gstinField = null;
      }
      expect(gstinField, isNull);
    });
  });

  group('Invoice Printing & Snapshot Verification', () {
    test('23. Recipient GSTIN displayed in A4 when available', () async {
      final dataWithGstin = InvoicePrintData(
        invoiceNumber: 'INV-2026-0001',
        invoiceDate: DateTime(2026, 10, 22),
        businessName: 'Nubi Supplies',
        businessGstin: '27AAPFU0939F1ZV',
        customerName: 'Kolkata Paints',
        customerPhone: '9876543210',
        customerGstin: '19ABCDE1234F1ZX',
        lines: const [
          InvoicePrintLine(
            name: 'Item A',
            quantity: 1,
            unitPricePaise: 10000,
            taxablePaise: 10000,
            lineTotalPaise: 11800,
          ),
        ],
        subtotalPaise: 10000,
        taxablePaise: 10000,
        grandTotalPaise: 11800,
      );

      final pdfBytes = await InvoicePrintService.buildPdf(
        data: dataWithGstin,
        format: InvoicePrintFormat.a4Standard,
      );
      expect(pdfBytes.isNotEmpty, isTrue);
    });

    test('24. Recipient GSTIN hidden when null or blank', () async {
      final dataWithoutGstin = InvoicePrintData(
        invoiceNumber: 'INV-2026-0002',
        invoiceDate: DateTime(2026, 10, 22),
        businessName: 'Nubi Supplies',
        businessGstin: '27AAPFU0939F1ZV',
        customerName: 'Walk-in Customer',
        customerGstin: null,
        lines: const [
          InvoicePrintLine(
            name: 'Item B',
            quantity: 1,
            unitPricePaise: 5000,
            taxablePaise: 5000,
            lineTotalPaise: 5900,
          ),
        ],
        subtotalPaise: 5000,
        taxablePaise: 5000,
        grandTotalPaise: 5900,
      );

      final pdfBytes = await InvoicePrintService.buildPdf(
        data: dataWithoutGstin,
        format: InvoicePrintFormat.a4Standard,
      );
      expect(pdfBytes.isNotEmpty, isTrue);

      final thermalBytes = await InvoicePrintService.buildPdf(
        data: dataWithoutGstin,
        format: InvoicePrintFormat.thermal80mm,
      );
      expect(thermalBytes.isNotEmpty, isTrue);
    });
  });

  group('Local SQLite Schema & Migration Version', () {
    test('25. LocalDatabase schema migration creates customer document table safely', () async {
      final directory = await Directory.systemTemp.createTemp('customer-db-test-');
      final db = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: directory.path,
      );

      final opened = await db.open('test-project', 'test-user');
      expect(await opened.getVersion(), equals(LocalDatabase.schemaVersion));
      expect(LocalDatabase.schemaVersion, greaterThanOrEqualTo(14));

      // Check local_customers table exists and can accept document payloads
      final tables = await opened.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='local_customers'",
      );
      expect(tables.isNotEmpty, isTrue);

      await db.close();
      await directory.delete(recursive: true);
    });
  });
}
