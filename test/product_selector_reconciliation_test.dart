import 'package:flutter_test/flutter_test.dart';

import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
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
  group('Selector Eligibility & Parent-Aware Rules', () {
    late _FakeFirestore firestore;
    late CatalogueSelectionResolver selector;

    setUp(() {
      firestore = _FakeFirestore();
      selector = CatalogueSelectionResolver(firestore);

      firestore.records['product_categories'] = [
        {
          'id': 'CAT_PAINTS',
          'categoryId': 'CAT_PAINTS',
          'name': 'Paints',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'CAT_WOOD',
          'categoryId': 'CAT_WOOD',
          'name': 'Wood Finishes',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
      ];

      firestore.records['product_subcategories'] = [
        {
          'id': 'SUB_PAINT_PRIMER',
          'subcategoryId': 'SUB_PAINT_PRIMER',
          'categoryId': 'CAT_PAINTS',
          'name': 'Primer',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'SUB_WOOD_PRIMER',
          'subcategoryId': 'SUB_WOOD_PRIMER',
          'categoryId': 'CAT_WOOD',
          'name': 'Primer', // Same display name 'Primer' under CAT_WOOD!
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'SUB_HAND_SANITIZER',
          'subcategoryId':
              'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS',
          'categoryId': 'CAT_PAINTS',
          'name': 'Hand Sanitizers',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'SUB_NO_TMPL',
          'subcategoryId': 'SUB_NO_TMPL',
          'categoryId': 'CAT_PAINTS',
          'name': 'Legacy Missing Template Paint',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
      ];

      firestore.records['subcategory_attribute_templates'] = [
        {
          'id': 'T1',
          'subcategoryId': 'SUB_PAINT_PRIMER',
          'attributeId': 'usage',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
        {
          'id': 'T2',
          'subcategoryId': 'SUB_WOOD_PRIMER',
          'attributeId': 'usage',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
        },
      ];

      firestore.records['units'] = [
        {'id': 'Litre', 'unitId': 'Litre', 'name': 'Litre', 'status': 'ACTIVE'},
      ];
    });

    test('eligible selector rows match the independent deterministic fixture', () async {
      final paint = await selector.getEligibleSubcategories(
        tenantId: 'T', businessId: 'B', categoryId: 'CAT_PAINTS', token: 'TOK',
      );
      final wood = await selector.getEligibleSubcategories(
        tenantId: 'T', businessId: 'B', categoryId: 'CAT_WOOD', token: 'TOK',
      );
      expect(
        paint.map((s) => '${s.id}:${s.name}').toSet(),
        {'SUB_PAINT_PRIMER:Primer'},
      );
      expect(
        wood.map((s) => '${s.id}:${s.name}').toSet(),
        {'SUB_WOOD_PRIMER:Primer'},
      );
    });

    test('same display name under different parent categories is not collapsed globally', () async {
      final paintSubcats = await selector.getEligibleSubcategories(
        tenantId: 'T',
        businessId: 'B',
        categoryId: 'CAT_PAINTS',
        token: 'TOK',
      );

      final woodSubcats = await selector.getEligibleSubcategories(
        tenantId: 'T',
        businessId: 'B',
        categoryId: 'CAT_WOOD',
        token: 'TOK',
      );

      expect(
        paintSubcats.any(
          (s) => s.id == 'SUB_PAINT_PRIMER' && s.name == 'Primer',
        ),
        isTrue,
      );
      expect(
        woodSubcats.any((s) => s.id == 'SUB_WOOD_PRIMER' && s.name == 'Primer'),
        isTrue,
      );
    });

    test('missing templateSelectable or templateStatus metadata does not exclude READY template', () async {
      final sub = const ProductMasterValue(
        id: 'SUB_PAINT_PRIMER',
        name: 'Primer',
        status: 'ACTIVE',
        categoryId: 'CAT_PAINTS',
        scopeType: 'SYSTEM',
        rawFields: {}, // No templateSelectable or templateStatus fields!
      );

      final diag = await selector.evaluateSubcategoryEligibility(
        subcat: sub,
        tenantId: 'T',
        businessId: 'B',
        token: 'TOK',
        businessTypeId: 'HARDWARE',
        businessSubTypeId: 'PAINTS',
      );

      expect(diag.eligible, isTrue);
    });

    test('Hand Sanitizers remains excluded from Paints context', () async {
      final sub = const ProductMasterValue(
        id: 'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS',
        name: 'Hand Sanitizers',
        status: 'ACTIVE',
        categoryId: 'CAT_PAINTS',
        scopeType: 'SYSTEM',
      );

      final diag = await selector.evaluateSubcategoryEligibility(
        subcat: sub,
        tenantId: 'T',
        businessId: 'B',
        token: 'TOK',
        businessTypeId: 'HARDWARE',
        businessSubTypeId: 'PAINTS',
      );

      expect(diag.eligible, isFalse);
      expect(
        diag.exclusionReason,
        equals(SelectionExclusionReason.excludedByBusinessType),
      );
    });

    test('legacy subcategory missing template rows remains excluded', () async {
      final sub = const ProductMasterValue(
        id: 'SUB_NO_TMPL',
        name: 'Legacy Missing Template Paint',
        status: 'ACTIVE',
        categoryId: 'CAT_PAINTS',
        scopeType: 'SYSTEM',
      );

      final diag = await selector.evaluateSubcategoryEligibility(
        subcat: sub,
        tenantId: 'T',
        businessId: 'B',
        token: 'TOK',
        businessTypeId: 'HARDWARE',
        businessSubTypeId: 'PAINTS',
      );

      expect(diag.eligible, isFalse);
      expect(
        diag.exclusionReason,
        equals(SelectionExclusionReason.missingTemplate),
      );
    });
  });
}
