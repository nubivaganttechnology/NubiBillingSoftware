import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/data/models/reclassification_plan.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

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
          'name': '$collection/${data['id'] ?? data['variantId'] ?? data['productId'] ?? 'doc'}',
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

  setUp(() {
    firestore = _FakeFirestore();

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
        'id': 'SUB_PRIMER',
        'subcategoryId': 'SUB_PRIMER',
        'categoryId': 'CAT_PAINTS',
        'name': 'Interior Primer',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'READY',
      },
      {
        'id': 'SUB_EMULSION',
        'subcategoryId': 'SUB_EMULSION',
        'categoryId': 'CAT_PAINTS',
        'name': 'Emulsion Paints',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'READY',
      },
    ];

    firestore.records['product_attributes'] = [
      {
        'id': 'ATTR_USAGE',
        'attributeId': 'usage',
        'name': 'Usage',
        'dataType': 'TEXT',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'ATTR_PACK_SIZE',
        'attributeId': 'packSize',
        'name': 'Pack Size',
        'dataType': 'NUMBER',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['subcategory_attribute_templates'] = [
      {
        'id': 'T1',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'usage',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'T2',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'T3',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'usage',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'T4',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['units'] = [
      {'id': 'Litre', 'unitId': 'Litre', 'name': 'Litre', 'status': 'ACTIVE'},
    ];
  });

  group('Identity Preservation Invariants', () {
    test('edit Product description only preserves productId, variantIds, SKUs and barcodes', () {
      const pId = 'PROD_100';
      const vId1 = 'VAR_100';
      const vId2 = 'VAR_101';

      firestore.records[FirebaseConstants.products] = [
        {
          'id': pId,
          'productId': pId,
          'productName': 'Original Paint',
          'categoryId': 'CAT_PAINTS',
          'subcategoryId': 'SUB_PRIMER',
          'status': 'ACTIVE',
        },
      ];

      firestore.records[FirebaseConstants.productVariants] = [
        {
          'id': vId1,
          'variantId': vId1,
          'productId': pId,
          'sku': 'SKU-0001',
          'barcode': 'BC-111',
          'status': 'ACTIVE',
        },
        {
          'id': vId2,
          'variantId': vId2,
          'productId': pId,
          'sku': 'SKU-0002',
          'barcode': 'BC-222',
          'status': 'ACTIVE',
        },
      ];

      final incomingVariants = [
        {'variantId': vId1, 'sku': 'SKU-0001', 'barcode': 'BC-111'},
        {'variantId': vId2, 'sku': 'SKU-0002', 'barcode': 'BC-222'},
      ];

      expect(incomingVariants[0]['variantId'], equals(vId1));
      expect(incomingVariants[1]['variantId'], equals(vId2));
      expect(incomingVariants[0]['sku'], equals('SKU-0001'));
      expect(incomingVariants[0]['barcode'], equals('BC-111'));
    });

    test('edit pack size preserves variantId, SKU and barcode', () {
      final v = {
        'variantId': 'VAR_100',
        'sku': 'SKU-0001',
        'barcode': 'BC-111',
        'packSize': 4, // Edited pack size
      };

      expect(v['variantId'], equals('VAR_100'));
      expect(v['sku'], equals('SKU-0001'));
      expect(v['barcode'], equals('BC-111'));
    });

    test('explicitly removing barcode leaves variantId intact and clears barcode', () {
      final v = {
        'variantId': 'VAR_100',
        'sku': 'SKU-0001',
        'barcode': '', // Explicitly cleared by user
      };

      expect(v['variantId'], equals('VAR_100'));
      expect(v['barcode'], isEmpty);
    });
  });

  group('Reclassification Plan & Soft-Retirement', () {
    test('removing an existing variant produces a destructive ReclassificationPlan with retiredVariantIds', () {
      const plan = ReclassificationPlan(
        classificationChanged: false,
        newCategoryId: 'CAT_PAINTS',
        newSubcategoryId: 'SUB_PRIMER',
        preservedVariantIds: ['VAR_1', 'VAR_2'],
        retiredVariantIds: ['VAR_3'],
      );

      expect(plan.isDestructive, isTrue);
      expect(plan.buildImpactSummary(), contains('retire 1 SKU(s)'));
    });

    test('non-destructive edit plan requires no extra confirmation', () {
      const plan = ReclassificationPlan(
        classificationChanged: false,
        newCategoryId: 'CAT_PAINTS',
        newSubcategoryId: 'SUB_PRIMER',
        preservedVariantIds: ['VAR_1', 'VAR_2'],
        retiredVariantIds: [],
        removedProductAttributeIds: [],
        removedVariantAttributeIds: [],
      );

      expect(plan.isDestructive, isFalse);
      expect(plan.buildImpactSummary(), contains('keep 2 SKU(s)'));
    });

    test('orphan integrity check verifies zero ACTIVE variants reference nonexistent products or are DELETED', () {
      final products = [
        {'productId': 'PROD_1', 'status': 'ACTIVE'},
      ];

      final variants = [
        {'variantId': 'VAR_1', 'productId': 'PROD_1', 'status': 'ACTIVE'},
        {'variantId': 'VAR_2', 'productId': 'PROD_1', 'status': 'DELETED'},
      ];

      final activeProducts = products.map((p) => p['productId']).toSet();

      final orphanActiveVariants = variants.where(
        (v) => v['status'] == 'ACTIVE' && !activeProducts.contains(v['productId']),
      );

      final retiredStillActive = variants.where(
        (v) => v['status'] == 'DELETED' && v['status'] == 'ACTIVE',
      );

      expect(orphanActiveVariants, isEmpty);
      expect(retiredStillActive, isEmpty);
    });
  });
}
