import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/models/purchase_bill_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';

class _Firestore implements FirestoreDataService {
  final records = <String, List<Map<String, dynamic>>>{};
  final collections = <String>[];
  final queries = <List<FirestoreFilter>>[];
  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    queries.add(filters);
    collections.add(collection);
    return [
      for (final data in records[collection] ?? <Map<String, dynamic>>[])
        if (filters.every((f) => data[f.field] == f.value))
          {
            'name': '$collection/${data['id']}',
            'fields': FirestoreRestService.encodeFields(data),
          },
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Transactions
    implements FirestoreTransactionService, FirestoreTransactionContext {
  final documents = <String, Map<String, dynamic>>{};
  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) => action(this);
  @override
  Future<FirestoreTransactionDocument> get(
    String collection,
    String id,
  ) async => FirestoreTransactionDocument(
    exists: documents.containsKey('$collection/$id'),
    fields: documents['$collection/$id'] ?? {},
  );
  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    documents['$collection/$id'] = fields;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('business product model retains central master reference', () {
    final product = ProductModel.fromData({
      'productId': 'P',
      'tenantId': 'T',
      'businessId': 'B',
      'productName': 'Apex Ultima',
      'status': 'ACTIVE',
      'masterProductId': 'MASTER-APEX',
    });

    expect(product.masterProductId, 'MASTER-APEX');
    expect(product.toData()['masterProductId'], 'MASTER-APEX');
  });

  test('catalogue field hints and measurement dimensions survive template and master merging', () async {
    final source = _Firestore();
    source.records['product_attributes'] = [
      {
        'id': 'A',
        'attributeId': 'size',
        'name': 'Size',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'dataType': 'NUMBER',
        'hintText': 'Enter size',
        'exampleValue': 2,
        'measurementDimension': 'LENGTH',
      },
    ];
    source.records['subcategory_attribute_templates'] = [
      {
        'id': 'T',
        'attributeId': 'size',
        'subcategoryId': 'S',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];
    source.records['product_attribute_options'] = [
      {
        'id': 'O',
        'attributeId': 'size',
        'name': 'Example',
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
      },
    ];
    source.records['units'] = [
      {
        'id': 'INCH',
        'name': 'inch',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'measurementDimension': 'LENGTH',
      },
    ];
    final repo = ProductRepository(source, _Transactions());
    final attribute = (await repo.loadTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'S',
      token: 'TOKEN',
    )).single;
    expect(attribute.hintText, 'Enter size');
    expect(attribute.exampleValue, 2);
    expect(attribute.measurementDimension, 'LENGTH');
    expect(
      (await repo.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'UNIT',
        token: 'TOKEN',
      )).single.measurementDimension,
      'LENGTH',
    );
  });

  test('canonical SYSTEM subcategory remains authoritative over same-name legacy row', () async {
    final source = _Firestore();
    const canonicalId =
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT';
    const legacyId = 'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS';
    source.records['product_subcategories'] = [
      {
        'id': canonicalId,
        'subcategoryId': canonicalId,
        'categoryId': 'SYS_CATEGORY_WATERPROOFING',
        'name': 'Interior Dampness Treatment',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': legacyId,
        'subcategoryId': legacyId,
        'categoryId': 'SYS_CATEGORY_WATERPROOFING',
        'name': 'Interior Dampness Treatment',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    final values = await ProductRepository(source, _Transactions())
        .getMasterValues(
          tenantId: 'T',
          businessId: 'B',
          masterType: 'SUBCATEGORY',
          token: 'TOKEN',
          categoryId: 'SYS_CATEGORY_WATERPROOFING',
        );

    final matching = values
        .where((value) => value.name == 'Interior Dampness Treatment')
        .toList();
    expect(matching, hasLength(1));
    expect(matching.single.id, canonicalId);
    expect(matching.any((value) => value.id == legacyId), isFalse);
  });

  test('masters do not gain fabricated variants when explicit variants are deleted', () async {
    final source = _Firestore();
    source.records['products'] = [
      for (final id in ['EMPTY', 'EMPTY_WITH_UNIT', 'REMOVED', 'LEGACY'])
        {
          'id': id,
          if (id != 'LEGACY') 'productId': id,
          'name': id,
          'tenantId': 'T',
          'businessId': 'B',
          if (id != 'EMPTY') 'baseUnitId': 'PIECE',
        },
    ];
    source.records['product_variants'] = [
      {
        'id': 'D',
        'variantId': 'D',
        'productId': 'REMOVED',
        'status': 'DELETED',
        'tenantId': 'T',
        'businessId': 'B',
      },
    ];
    final products = await ProductRepository(
      source,
      _Transactions(),
    ).getProducts(tenantId: 'T', businessId: 'B', token: 'TOKEN');
    expect(
      products.singleWhere((p) => p.productId == 'EMPTY').variants,
      isEmpty,
    );
    expect(
      products.singleWhere((p) => p.productId == 'REMOVED').variants,
      isEmpty,
    );
    expect(
      products.singleWhere((p) => p.productId == 'EMPTY_WITH_UNIT').variants,
      isEmpty,
    );
    expect(
      products.singleWhere((p) => p.productId == 'LEGACY').variants.length,
      1,
    );
  });
  test('legacy dynamic HSN falls back into the canonical field without appearing twice', () async {
    final remote = _Firestore();
    remote.records['products'] = [
      {
        'id': 'P',
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Legacy',
        'hsnCode': '',
        'attributeValues': {'hsnCode': '960340', 'custom': 'keep'},
      },
    ];
    final products = await ProductRepository(
      remote,
      _Transactions(),
    ).getProducts(tenantId: 'T', businessId: 'B', token: 'TOKEN');
    expect(products.single.hsnCode, '960340');
    expect(products.single.attributeValues.containsKey('hsnCode'), false);
    expect(products.single.attributeValues['custom'], 'keep');
  });
  test(
    'new brand IDs include the name and retain business isolation',
    () async {
      final transactions = _Transactions();
      final repo = ProductRepository(_Firestore(), transactions);
      Future<dynamic> create(String business, String name) =>
          repo.createMasterValue(
            tenantId: 'T',
            businessId: business,
            masterType: 'BRAND',
            name: name,
            actorUid: 'OWNER',
            token: 'TOKEN',
          );
      final a = await create('A', ' Example / Brand ');
      final b = await create('B', 'Example / Brand');
      expect(a.id, startsWith('PM_BRAND_EXAMPLE_BRAND_T_A_BRAND_'));
      expect(a.id, isNot(b.id));
      expect(a.id, isNot(contains('/')));
      expect(
        transactions.documents['brands/${a.id}']!['name'],
        'Example / Brand',
      );
      expect(
        transactions.documents['brands/${a.id}']!['scopeType'],
        'BUSINESS',
      );
      await expectLater(create('A', 'example / brand'), throwsException);
    },
  );
  test(
    'all master queries are SYSTEM scoped or tenant and business isolated',
    () async {
      final firestore = _Firestore();
      final repo = ProductRepository(firestore, _Transactions());
      await repo.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'CATEGORY',
        token: 'TOKEN',
      );
      for (final filters in firestore.queries) {
        final f = {for (final v in filters) v.field: v.value};
        expect(
          f['scopeType'] == 'SYSTEM' ||
              f['tenantId'] == 'T' && f['businessId'] == 'B',
          isTrue,
        );
        expect(f['status'], 'ACTIVE');
      }
    },
  );
  test('custom master IDs do not collide between businesses and central duplicates are rejected', () async {
    final transactions = _Transactions();
    final firestore = _Firestore();
    firestore.records['product_categories'] = [
      {
        'id': 'CENTRAL',
        'categoryId': 'CENTRAL',
        'name': 'Central Category',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];
    final repo = ProductRepository(firestore, transactions);
    Future<dynamic> create(String business, String name) =>
        repo.createMasterValue(
          tenantId: 'T',
          businessId: business,
          masterType: 'CATEGORY',
          name: name,
          actorUid: 'OWNER',
          token: 'TOKEN',
        );
    final a = await create('A', ' Special Coatings ');
    final b = await create('B', 'Special Coatings');
    expect(a.id, isNot(b.id));
    expect(
      transactions.documents.values.every(
        (v) => v['scopeType'] == 'BUSINESS' && v['tenantId'] == 'T',
      ),
      isTrue,
    );
    await expectLater(create('A', 'special   coatings'), throwsException);
    await expectLater(create('A', 'Central Category'), throwsException);
  });
  test(
    'empty Firestore produces no masters or templates or release queries',
    () async {
      final db = _Firestore();
      final repo = ProductRepository(db, _Transactions());
      for (final type in ['BRAND', 'CATEGORY', 'SUBCATEGORY', 'UNIT']) {
        expect(
          await repo.getMasterValues(
            tenantId: 'T',
            businessId: 'B',
            masterType: type,
            categoryId: 'C',
            token: 'TOKEN',
          ),
          isEmpty,
        );
      }
      expect(
        await repo.loadTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: 'S',
          token: 'TOKEN',
        ),
        isEmpty,
      );
      expect(db.collections, isNot(contains('product_catalogue_releases')));
    },
  );
  test(
    'Firestore templates preserve dynamic behavior and business options',
    () async {
      final db = _Firestore();
      db.records['product_attributes'] = [
        for (final id in ['A', 'Z'])
          {
            'id': id,
            'attributeId': id,
            'name': id,
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'dataType': id == 'A' ? 'MULTI_SELECT' : 'SELECT',
            'allowAddNewOption': true,
          },
      ];
      db.records['subcategory_attribute_templates'] = [
        for (final id in ['A', 'Z'])
          {
            'id': id,
            'attributeId': id,
            'subcategoryId': 'S',
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'attributeLevel': id == 'A' ? 'VARIANT' : 'PRODUCT',
            'required': true,
            'sortOrder': id == 'A' ? 2 : 1,
            'defaultValue': id == 'A' ? ['Central'] : 'Central',
          },
      ];
      db.records['product_attribute_options'] = [
        for (final id in ['A', 'Z'])
          {
            'id': id,
            'attributeId': id,
            'name': 'Central',
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
          },
        {
          'id': 'CUSTOM',
          'attributeId': 'A',
          'name': 'Custom',
          'scopeType': 'BUSINESS',
          'status': 'ACTIVE',
          'tenantId': 'T',
          'businessId': 'B',
        },
        {
          'id': 'OTHER',
          'attributeId': 'A',
          'name': 'Other business',
          'scopeType': 'BUSINESS',
          'status': 'ACTIVE',
          'tenantId': 'T',
          'businessId': 'OTHER',
        },
      ];
      final repo = ProductRepository(db, _Transactions());
      final attrs = await repo.loadTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: 'S',
        token: 'TOKEN',
      );
      expect(attrs.map((a) => a.id), ['Z', 'A']);
      expect(attrs.first.dataType, 'SELECT');
      final a = attrs.last;
      expect(a.dataType, 'MULTI_SELECT');
      expect(a.level, 'VARIANT');
      expect(a.required, isTrue);
      expect(a.defaultValue, ['Central']);
      expect(a.allowAddNewOption, isTrue);
      expect(a.options, ['Central', 'Custom']);
      db.records['subcategory_attribute_templates']!.add({
        'id': 'HIDE',
        'attributeId': 'A',
        'subcategoryId': 'S',
        'scopeType': 'BUSINESS',
        'status': 'INACTIVE',
        'tenantId': 'T',
        'businessId': 'B',
      });
      expect(
        (await repo.loadTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: 'S',
          token: 'TOKEN',
        )).map((a) => a.id),
        ['Z'],
      );
    },
  );
  test('template option restrictions override global master options', () async {
    final db = _Firestore();
    db.records['product_attributes'] = [
      {
        'id': 'usage',
        'attributeId': 'usage',
        'name': 'Usage',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'dataType': 'SELECT',
      },
    ];
    db.records['subcategory_attribute_templates'] = [
      {
        'id': 'S_usage',
        'attributeId': 'usage',
        'subcategoryId': 'S',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'defaultValue': 'Exterior',
        'options': ['Exterior'],
        'attributeLevel': 'PRODUCT',
      },
    ];
    db.records['product_attribute_options'] = [
      for (final option in ['Interior', 'Exterior', 'Both'])
        {
          'id': option,
          'attributeId': 'usage',
          'name': option,
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
    ];
    final attributes = await ProductRepository(db, _Transactions())
        .loadTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: 'S',
          token: 'TOKEN',
        );
    expect(attributes.single.options, ['Exterior']);
    expect(attributes.single.defaultValue, 'Exterior');
  });

  test(
    'master IDs override and subcategory parent filtering is preserved',
    () async {
      final db = _Firestore();
      db.records['product_subcategories'] = [
        {
          'id': 'S',
          'subcategoryId': 'S',
          'categoryId': 'C',
          'name': 'Central',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'OVERRIDE',
          'subcategoryId': 'S',
          'categoryId': 'C',
          'name': 'Business',
          'scopeType': 'BUSINESS',
          'status': 'ACTIVE',
          'tenantId': 'T',
          'businessId': 'B',
        },
        {
          'id': 'OTHER',
          'categoryId': 'OTHER',
          'name': 'Other parent',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
      ];
      final values = await ProductRepository(db, _Transactions())
          .getMasterValues(
            tenantId: 'T',
            businessId: 'B',
            masterType: 'SUBCATEGORY',
            categoryId: 'C',
            token: 'TOKEN',
          );
      expect(values.single.id, 'S');
      expect(values.single.name, 'Business');
    },
  );
  test('purchase snapshots preserve commercial quantity and calculated base quantity', () {
    const item = PurchaseBillItemModel(
      goodsReceiptItemId: 'L',
      variantId: 'SKU',
      productName: 'Paint',
      unitId: 'Litre',
      commercialUnitId: 'Pack',
      conversionFactor: 10000,
      quantity: 55000,
      rate: 10000,
      gstRateBps: 0,
      taxableAmount: 550000,
      taxAmount: 0,
    );
    final data = item.toData();
    expect(data['commercialQuantity'], 55000);
    expect(data['baseQuantity'], 550000);
    expect(PurchaseBillItemModel.fromData(data).baseQuantity, 550000);
    expect(PurchaseBillItemModel.fromData(data).commercialUnitId, 'Pack');
  });
}
