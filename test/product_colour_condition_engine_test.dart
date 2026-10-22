import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_validator.dart';

class _FakeFirestore implements FirestoreDataService {
  final records = <String, List<Map<String, dynamic>>>{};

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
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
  group('Condition Evaluator Engine Scopes', () {
    test('PRODUCT condition evaluates product values', () {
      const cond = ResolvedCondition(
        targetAttributeId: 'finish',
        operator: 'IN',
        expectedValues: ['Matt', 'Gloss'],
        scope: ConditionScope.product,
      );

      final productValues = {'finish': 'Matt'};
      expect(cond.evaluate(productValues), isTrue);

      final wrongValues = {'finish': 'Satin'};
      expect(cond.evaluate(wrongValues), isFalse);
    });

    test('VARIANT condition evaluates current variant', () {
      const cond = ResolvedCondition(
        targetAttributeId: 'packSize',
        operator: 'IN',
        expectedValues: [1, 4, 20],
        scope: ConditionScope.variant,
      );

      final productValues = {'finish': 'Matt'};
      final variantValues = {'packSize': 4};

      expect(cond.evaluate(productValues, variantValues), isTrue);

      final invalidVariant = {'packSize': 10};
      expect(cond.evaluate(productValues, invalidVariant), isFalse);
    });

    test(
      'ANY_VARIANT condition evaluates true when at least one variant matches',
      () {
        const cond = ResolvedCondition(
          targetAttributeId: 'colourType',
          operator: 'IN',
          expectedValues: ['Fixed Colour'],
          scope: ConditionScope.anyVariant,
        );

        final productValues = <String, dynamic>{};
        final variants = [
          {'colourType': 'Multiple Ready Colours'},
          {'colourType': 'Fixed Colour'},
          {'colourType': 'Tintable Base'},
        ];

        expect(cond.evaluate(productValues, null, variants), isTrue);
      },
    );

    test('ANY_VARIANT condition evaluates false when no variant matches', () {
      const cond = ResolvedCondition(
        targetAttributeId: 'colourType',
        operator: 'IN',
        expectedValues: ['Fixed Colour'],
        scope: ConditionScope.anyVariant,
      );

      final productValues = <String, dynamic>{};
      final variants = [
        {'colourType': 'Multiple Ready Colours'},
        {'colourType': 'Tintable Base'},
      ];

      expect(cond.evaluate(productValues, null, variants), isFalse);
    });

    test(
      'ALL_VARIANTS condition evaluates true only when all variants match',
      () {
        const cond = ResolvedCondition(
          targetAttributeId: 'colourType',
          operator: 'IN',
          expectedValues: ['Tintable Base'],
          scope: ConditionScope.allVariants,
        );

        final productValues = <String, dynamic>{};

        final allMatching = [
          {'colourType': 'Tintable Base'},
          {'colourType': 'Tintable Base'},
        ];
        expect(cond.evaluate(productValues, null, allMatching), isTrue);

        final mixedVariants = [
          {'colourType': 'Tintable Base'},
          {'colourType': 'Fixed Colour'},
        ];
        expect(cond.evaluate(productValues, null, mixedVariants), isFalse);
      },
    );
  });

  group('Colour Mode Validation & Resets', () {
    late _FakeFirestore firestore;
    late ProductValidator validator;

    setUp(() {
      firestore = _FakeFirestore();
      validator = ProductValidator(firestore);

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
          'id': 'SUB_PAINT',
          'subcategoryId': 'SUB_PAINT',
          'categoryId': 'CAT_PAINTS',
          'name': 'Wall Paint',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'templateStatus': 'READY',
          'unitRules': {
            'allowedPackUnits': ['Litre', 'Millilitre'],
            'defaultPackUnit': 'Litre',
            'allowedSellingUnits': ['Litre', 'Can'],
            'defaultSellingUnit': 'Can',
            'allowedBaseUnits': ['Litre', 'Millilitre'],
            'defaultBaseUnit': 'Litre',
            'conversionAllowed': true,
            'conversionDimension': 'VOLUME',
          },
        },
      ];

      firestore.records['product_attributes'] = [
        {
          'id': 'ATTR_COLOUR_TYPE',
          'attributeId': 'colourType',
          'name': 'Colour Type',
          'dataType': 'SELECT',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'options': [
            'Fixed Colour',
            'Multiple Ready Colours',
            'Tintable Base',
            'Clear / Transparent',
            'Not Applicable',
          ],
        },
        {
          'id': 'ATTR_PROD_COLOUR',
          'attributeId': 'productColour',
          'name': 'Product Colour',
          'dataType': 'TEXT',
          'attributeLevel': 'PRODUCT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'ATTR_SHADE',
          'attributeId': 'shade',
          'name': 'Shade / Colour',
          'dataType': 'TEXT',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'ATTR_BASE_TYPE',
          'attributeId': 'baseType',
          'name': 'Base Type',
          'dataType': 'SELECT',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'options': ['White Base', 'Pastel Base', 'Deep Base', 'Accent Base'],
        },
      ];

      firestore.records['subcategory_attribute_templates'] = [
        {
          'id': 'T_1',
          'subcategoryId': 'SUB_PAINT',
          'attributeId': 'colourType',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'required': true,
        },
        {
          'id': 'T_2',
          'subcategoryId': 'SUB_PAINT',
          'attributeId': 'productColour',
          'attributeLevel': 'PRODUCT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'required': true,
          'visibleWhen': {
            'attributeId': 'colourType',
            'in': ['Fixed Colour'],
            'scope': 'ANY_VARIANT',
          },
        },
        {
          'id': 'T_3',
          'subcategoryId': 'SUB_PAINT',
          'attributeId': 'shade',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'required': true,
          'visibleWhen': {
            'attributeId': 'colourType',
            'in': ['Multiple Ready Colours'],
            'scope': 'VARIANT',
          },
        },
        {
          'id': 'T_4',
          'subcategoryId': 'SUB_PAINT',
          'attributeId': 'baseType',
          'attributeLevel': 'VARIANT',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'required': true,
          'visibleWhen': {
            'attributeId': 'colourType',
            'in': ['Tintable Base'],
            'scope': 'VARIANT',
          },
        },
      ];

      firestore.records['units'] = [
        for (final name in ['Litre', 'Millilitre', 'Can'])
          {'id': name, 'unitId': name, 'name': name, 'status': 'ACTIVE'},
      ];
    });

    test('reject Fixed Colour without Product Colour', () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Fixed Colour Primer',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PAINT',
          'attributeValues': {}, // Missing Product Colour!
        },
        variants: [
          {
            'sku': 'SKU-FIXED-1',
            'packUnitId': 'Litre',
            'attributeValues': {'colourType': 'Fixed Colour'},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
              e.attributeId == 'productColour',
        ),
        isTrue,
      );
    });

    test('reject Multiple Ready Colours without required Shade', () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Ready Colour Paint',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PAINT',
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-READY-1',
            'packUnitId': 'Litre',
            'attributeValues': {
              'colourType': 'Multiple Ready Colours',
              // Missing shade!
            },
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
              e.attributeId == 'shade',
        ),
        isTrue,
      );
    });

    test('reject Tintable Base without Base Type', () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Tintable Paint',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PAINT',
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-BASE-1',
            'packUnitId': 'Litre',
            'attributeValues': {
              'colourType': 'Tintable Base',
              // Missing baseType!
            },
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
              e.attributeId == 'baseType',
        ),
        isTrue,
      );
    });

    test('accept Clear/Transparent without colour fields', () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Clear Wood Finish',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PAINT',
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-CLEAR-1',
            'packUnitId': 'Litre',
            'attributeValues': {'colourType': 'Clear / Transparent'},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isTrue);
    });

    test('accept Not Applicable without colour fields', () async {
      final result = await validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Neutral Surface Cleaner',
        productFields: {
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PAINT',
          'attributeValues': {},
        },
        variants: [
          {
            'sku': 'SKU-NA-1',
            'packUnitId': 'Litre',
            'attributeValues': {'colourType': 'Not Applicable'},
          },
        ],
        token: 'TOK',
      );

      expect(result.isValid, isTrue);
    });
  });
}
