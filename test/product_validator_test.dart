import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_validator.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';

class _FakeFirestore implements FirestoreDataService {
  final records = <String, List<Map<String, dynamic>>>{};
  final queryCalls = <String>[];

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    queryCalls.add(collection);
    final items = records[collection] ?? <Map<String, dynamic>>[];
    final results = <Map<String, dynamic>>[];

    for (final data in items) {
      final matchesAll = filters.every((f) {
        final val = data[f.field];
        if (f.operation == 'EQUAL') {
          return val == f.value;
        }
        return true;
      });

      if (matchesAll) {
        results.add({
          'name': '$collection/${data['id'] ?? data['remoteId'] ?? 'doc'}',
          'fields': FirestoreRestService.encodeFields(data),
        });
      }
    }
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeFirestore firestore;
  late ProductValidator validator;

  setUp(() {
    firestore = _FakeFirestore();
    validator = ProductValidator(firestore);

    // Setup Category & Subcategory
    firestore.records['product_categories'] = [
      {
        'id': 'CAT_PAINTS',
        'categoryId': 'CAT_PAINTS',
        'name': 'Paints & Coatings',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['product_subcategories'] = [
      {
        'id': 'SUB_EMULSION',
        'subcategoryId': 'SUB_EMULSION',
        'categoryId': 'CAT_PAINTS',
        'name': 'Emulsion Paints',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'READY',
      },
      {
        'id': 'SUB_NO_TEMPLATE',
        'subcategoryId': 'SUB_NO_TEMPLATE',
        'categoryId': 'CAT_PAINTS',
        'name': 'No Template Subcat',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'SUB_LEGACY',
        'subcategoryId': 'SUB_LEGACY',
        'categoryId': 'CAT_PAINTS',
        'name': 'Legacy Subcategory',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'UNAVAILABLE',
      },
    ];

    // Setup Attributes
    firestore.records['product_attributes'] = [
      {
        'id': 'ATTR_FINISH',
        'attributeId': 'finish',
        'name': 'Finish',
        'dataType': 'SELECT',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Matt', 'Gloss'],
        'allowAddNewOption': false,
      },
      {
        'id': 'ATTR_SURFACE',
        'attributeId': 'surface',
        'name': 'Surface',
        'dataType': 'MULTI_SELECT',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Wall', 'Concrete', 'Metal'],
      },
      {
        'id': 'ATTR_PACK_SIZE',
        'attributeId': 'packSize',
        'name': 'Pack Size',
        'dataType': 'NUMBER',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'minimumExclusive': 0,
      },
      {
        'id': 'ATTR_UNIT',
        'attributeId': 'unit',
        'name': 'Unit',
        'dataType': 'SELECT',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Litre', 'Millilitre'],
      },
    ];

    firestore.records['subcategory_attribute_templates'] = [
      {
        'id': 'TPL_1',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'finish',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_2',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_3',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Litre', 'Millilitre'],
      },
      {
        'id': 'TPL_4',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'surface',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['units'] = [
      {'id': 'Litre', 'unitId': 'Litre', 'name': 'Litre', 'status': 'ACTIVE'},
      {
        'id': 'Millilitre',
        'unitId': 'Millilitre',
        'name': 'Millilitre',
        'status': 'ACTIVE',
      },
      {
        'id': 'Gallon',
        'unitId': 'Gallon',
        'name': 'Gallon',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['product_variants'] = [];
  });

  test(
    'reject create when subcategory missing template (MISSING_TEMPLATE)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Paint',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_NO_TEMPLATE',
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.code == 'MISSING_TEMPLATE'), isTrue);
    },
  );

  test(
    'explicitly unavailable subcategory remains blocked despite a ready template',
    () async {
      firestore.records['product_subcategories']!.firstWhere(
          (row) => row['subcategoryId'] == 'SUB_EMULSION',
        )
        ..['templateStatus'] = 'UNAVAILABLE'
        ..['templateSelectable'] = false;

      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {'finish': 'Matt'},
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1, 'unit': 'Litre'},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse, reason: result.errors.toString());
      expect(result.errors.any((error) => error.code == 'MISSING_TEMPLATE'), isTrue);
    },
  );

  test('canonical subcategory save remains valid beside active same-name legacy row', () async {
    const canonicalId =
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT';
    const legacyId = 'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS';
    const name = 'Interior Dampness Treatment';
    firestore.records['product_subcategories']!.addAll([
      {
        'id': canonicalId,
        'subcategoryId': canonicalId,
        'categoryId': 'CAT_PAINTS',
        'name': name,
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'unitRules': {
          'allowedPackUnits': ['Litre'],
          'allowedSellingUnits': ['Litre'],
          'allowedBaseUnits': <String>[],
          'defaultPackUnit': 'Litre',
          'conversionAllowed': false,
        },
      },
      {
        'id': legacyId,
        'subcategoryId': legacyId,
        'categoryId': 'CAT_PAINTS',
        'name': name,
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'unitRules': {
          'allowedPackUnits': ['Litre'],
          'allowedSellingUnits': ['Litre'],
          'allowedBaseUnits': <String>[],
          'defaultPackUnit': 'Litre',
          'conversionAllowed': false,
        },
      },
    ]);
    firestore.records['subcategory_attribute_templates']!.addAll([
      {
        'id': 'TPL_CANONICAL_FINISH',
        'subcategoryId': canonicalId,
        'attributeId': 'finish',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_CANONICAL_PACK_SIZE',
        'subcategoryId': canonicalId,
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_CANONICAL_UNIT',
        'subcategoryId': canonicalId,
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'TPL_LEGACY_FINISH',
        'subcategoryId': legacyId,
        'attributeId': 'finish',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_LEGACY_PACK_SIZE',
        'subcategoryId': legacyId,
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'TPL_LEGACY_UNIT',
        'subcategoryId': legacyId,
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ]);

    final resolvedTemplate = await ProductTemplateResolver(firestore)
        .resolveTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: canonicalId,
          token: 'TOK',
          categoryId: 'CAT_PAINTS',
        );
    expect(resolvedTemplate.readiness.name, 'ready');
    expect(resolvedTemplate.allAttributes, isNotEmpty);

    final exactEligibility = await CatalogueSelectionResolver(firestore)
        .evaluateSubcategoryEligibility(
          subcat: const ProductMasterValue(
            id: canonicalId,
            name: name,
            status: 'ACTIVE',
            scopeType: 'SYSTEM',
            categoryId: 'CAT_PAINTS',
          ),
          tenantId: 'T',
          businessId: 'B',
          token: 'TOK',
          businessTypeId: 'HARDWARE',
          businessSubTypeId: 'PAINTS',
          resolvedTemplate: resolvedTemplate,
        );
    expect(exactEligibility.eligible, isTrue);

    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Damp Proof',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': canonicalId,
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-CANONICAL',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
    );
    expect(result.isValid, isTrue, reason: result.errors.toString());

    final eligibleSubcategories = await CatalogueSelectionResolver(firestore)
        .getEligibleSubcategories(
          tenantId: 'T',
          businessId: 'B',
          categoryId: 'CAT_PAINTS',
          token: 'TOK',
        );
    final sameNameRows = eligibleSubcategories
        .where((subcategory) => subcategory.name == name)
        .toList();
    expect(sameNameRows, hasLength(1));
    expect(sameNameRows.single.id, canonicalId);
    expect(
      sameNameRows.any((subcategory) => subcategory.id == legacyId),
      isFalse,
    );
  });

  test('reject create when category and subcategory mismatch (CATEGORY_SUBCATEGORY_MISMATCH)', () async {
    firestore.records['product_categories']!.add({
      'id': 'CAT_HARDWARE',
      'categoryId': 'CAT_HARDWARE',
      'name': 'Hardware',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });

    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Paint',
      productFields: {
        'categoryId': 'CAT_HARDWARE', // Mismatched category
        'subcategoryId': 'SUB_EMULSION', // Belongs to CAT_PAINTS
        'attributeValues': {},
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any((e) => e.code == 'CATEGORY_SUBCATEGORY_MISMATCH'),
      isTrue,
    );
  });

  test(
    'reject required PRODUCT attribute missing (MISSING_REQUIRED_ATTRIBUTE)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {}, // 'finish' is required but missing!
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
              e.attributeId == 'finish',
        ),
        isTrue,
      );
    },
  );

  test(
    'reject required VARIANT attribute missing (MISSING_REQUIRED_ATTRIBUTE)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {'finish': 'Matt'},
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'attributeValues': {}, // 'packSize' is required on VARIANT level!
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
              e.attributeId == 'packSize',
        ),
        isTrue,
      );
    },
  );

  test('reject invalid SELECT option (INVALID_ATTRIBUTE_OPTION)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {
          'finish': 'Ultra Metallic Neon', // Not in ['Matt', 'Gloss']
        },
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any(
        (e) =>
            e.code == 'INVALID_ATTRIBUTE_OPTION' && e.attributeId == 'finish',
      ),
      isTrue,
    );
  });

  test(
    'reject invalid MULTI_SELECT option (INVALID_MULTI_SELECT_OPTION)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {
            'finish': 'Matt',
            'surface': ['Wall', 'Plastic'], // 'Plastic' is invalid
          },
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'INVALID_MULTI_SELECT_OPTION' &&
              e.attributeId == 'surface',
        ),
        isTrue,
      );
    },
  );

  test('reject invalid NUMBER value (INVALID_NUMERIC_VALUE)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': -5}, // Minimum exclusive is 0
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any(
        (e) => e.code == 'INVALID_NUMERIC_VALUE' && e.attributeId == 'packSize',
      ),
      isTrue,
    );
  });

  test('reject unit that exists globally but is not allowed by template (UNIT_NOT_ALLOWED)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId':
              'Gallon', // Exists globally in units, but not allowed by template
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.any((e) => e.code == 'UNIT_NOT_ALLOWED'), isTrue);
  });

  test('reject canonical packUnitId vs dynamic unit mismatch (CANONICAL_ATTRIBUTE_MISMATCH)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1, 'unit': 'Millilitre'}, // Mismatch!
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any((e) => e.code == 'CANONICAL_ATTRIBUTE_MISMATCH'),
      isTrue,
    );
  });

  test(
    'reject conversion enabled with missing baseUnitId (INVALID_UNIT)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {'finish': 'Matt'},
        },
        variants: [
          {
            'sku': 'SKU-1',
            'packUnitId': 'Litre',
            'commercialUnitId': 'Can',
            'baseUnitId': '', // Missing base unit!
            '_packaging': true,
            'baseQuantityPerCommercialUnit': 20,
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.code == 'INVALID_UNIT'), isTrue);
    },
  );

  test('reject conversion enabled with invalid conversionFactor (INVALID_CONVERSION_FACTOR)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'commercialUnitId': 'Litre',
          'baseUnitId': 'Millilitre',
          '_packaging': true,
          'baseQuantityPerCommercialUnit': 0, // Must be > 0
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any((e) => e.code == 'INVALID_CONVERSION_FACTOR'),
      isTrue,
    );
  });

  test('reject duplicate barcode within payload (DUPLICATE_BARCODE)', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Emulsion',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-100',
          'barcode': 'BC-888',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
        {
          'sku': 'SKU-101',
          'barcode': 'BC-888', // Duplicate barcode in same payload!
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 2},
        },
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.any((e) => e.code == 'DUPLICATE_BARCODE'), isTrue);
  });

  test(
    'reject barcode already existing in database (DUPLICATE_BARCODE)',
    () async {
      firestore.records['product_variants'] = [
        {
          'id': 'V_EXISTING',
          'productId': 'P_OTHER',
          'sku': 'SKU-OTHER',
          'barcode': 'BC-999',
          'tenantId': 'T',
          'businessId': 'B',
        },
      ];

      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {'finish': 'Matt'},
        },
        variants: [
          {
            'sku': 'SKU-NEW',
            'barcode': 'BC-999', // Already exists in database!
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.code == 'DUPLICATE_BARCODE'), isTrue);
    },
  );

  test(
    'reject duplicate variantId within payload (DUPLICATE_VARIANT_ID)',
    () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Test Emulsion',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_EMULSION',
          'attributeValues': {'finish': 'Matt'},
        },
        variants: [
          {
            'variantId': 'VAR_SAME',
            'sku': 'SKU-100',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
          {
            'variantId': 'VAR_SAME', // Duplicate variantId!
            'sku': 'SKU-101',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 2},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.code == 'DUPLICATE_VARIANT_ID'),
        isTrue,
      );
    },
  );

  test(
    'legacy edit with unchanged legacy classification remains loadable',
    () async {
      firestore.records['products'] = [
        {
          'id': 'P_LEGACY_1',
          'productId': 'P_LEGACY_1',
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_LEGACY',
          'tenantId': 'T',
          'businessId': 'B',
        },
      ];

      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Legacy Paint',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_LEGACY', // Unchanged legacy classification
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-LEGACY',
            'packUnitId': 'Litre',
            'attributeValues': {'packSize': 1},
          },
        ],
        token: 'TOK',
        isNew: false, // Edit mode
        currentProductId: 'P_LEGACY_1',
      );

      // Should not block save solely because historical subcategory is legacy
      expect(
        result.errors.any((e) => e.code == 'INVALID_SUBCATEGORY'),
        isFalse,
      );
    },
  );

  test('reclassification during Edit requires valid current classification', () async {
    firestore.records['products'] = [
      {
        'id': 'P_LEGACY_1',
        'productId': 'P_LEGACY_1',
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'tenantId': 'T',
        'businessId': 'B',
      },
    ];

    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Reclassified Paint',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId':
            'SUB_NO_TEMPLATE', // Reclassified to subcategory missing template!
        'attributeValues': {},
      },
      variants: [
        {
          'sku': 'SKU-RECLASS',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
      isNew: false, // Edit mode
      currentProductId: 'P_LEGACY_1',
    );

    expect(result.isValid, isFalse);
    expect(result.errors.any((e) => e.code == 'MISSING_TEMPLATE'), isTrue);
  });

  test('valid product satisfies all rules and returns success', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Valid Emulsion Paint',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_EMULSION',
        'attributeValues': {'finish': 'Matt'},
      },
      variants: [
        {
          'sku': 'SKU-VALID-1',
          'packUnitId': 'Litre',
          'attributeValues': {'packSize': 1},
        },
      ],
      token: 'TOK',
      isNew: true,
    );

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });
}
