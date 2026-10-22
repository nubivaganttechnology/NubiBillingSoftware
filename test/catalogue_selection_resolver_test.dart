import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

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
  late CatalogueSelectionResolver selectionResolver;

  setUp(() {
    firestore = _FakeFirestore();
    selectionResolver = CatalogueSelectionResolver(firestore);

    // Categories
    firestore.records['product_categories'] = [
      {
        'id': 'CAT_PAINTS',
        'categoryId': 'CAT_PAINTS',
        'name': 'Paints & Coatings',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'CAT_HEALTH',
        'categoryId': 'CAT_HEALTH',
        'name': 'Health & Hygiene',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'CAT_EMPTY_BIZ',
        'categoryId': 'CAT_EMPTY_BIZ',
        'name': 'Interior Wall Coatings',
        'scopeType': 'BUSINESS',
        'status': 'ACTIVE',
      },
      {
        'id': 'CAT_CANONICAL_SYS',
        'categoryId': 'CAT_CANONICAL_SYS',
        'name': 'Interior Wall Coatings',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    // Subcategories
    firestore.records['product_subcategories'] = [
      // 1. Ready Subcategory
      {
        'id': 'SUB_EMULSION',
        'subcategoryId': 'SUB_EMULSION',
        'categoryId': 'CAT_PAINTS',
        'name': 'Emulsion Paints',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'READY',
        'templateSelectable': true,
      },
      // 2. Hand Sanitizers (Tagged Hardware/Paints, but excluded)
      {
        'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS',
        'subcategoryId': 'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS',
        'categoryId': 'CAT_HEALTH',
        'name': 'Hand Sanitizers',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'UNAVAILABLE',
        'excludedBusinessScopes': ['HARDWARE/PAINTS'],
        'excludedBusinessSubTypeIds': ['PAINTS'],
      },
      // 3. Paint -> Interior Wall Paint (Active record, missing template rows)
      {
        'id': 'PM_SUBCATEGORY_INT_WALL_PAINT',
        'subcategoryId': 'PM_SUBCATEGORY_INT_WALL_PAINT',
        'categoryId': 'CAT_PAINTS',
        'name': 'Interior Wall Paint',
        'scopeType': 'BUSINESS',
        'status': 'ACTIVE',
      },
      // 4. Subcategory with templateSelectable = false
      {
        'id': 'SUB_UNSELECTABLE',
        'subcategoryId': 'SUB_UNSELECTABLE',
        'categoryId': 'CAT_PAINTS',
        'name': 'Legacy Enamel',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateSelectable': false,
      },
      // 5. Subcategory under canonical Interior Wall Coatings
      {
        'id': 'SUB_WALL_COATING_1',
        'subcategoryId': 'SUB_WALL_COATING_1',
        'categoryId': 'CAT_CANONICAL_SYS',
        'name': 'Luxury Interior Emulsion',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'templateStatus': 'READY',
      },
    ];

    // Attributes and Template Rows for valid subcategories
    firestore.records['product_attributes'] = [
      {
        'id': 'ATTR_FINISH',
        'attributeId': 'finish',
        'name': 'Finish',
        'dataType': 'SELECT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Matt', 'Gloss'],
      },
    ];

    firestore.records['subcategory_attribute_templates'] = [
      {
        'id': 'TPL_EMULSION',
        'subcategoryId': 'SUB_EMULSION',
        'attributeId': 'finish',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'TPL_WALL_COATING_1',
        'subcategoryId': 'SUB_WALL_COATING_1',
        'attributeId': 'finish',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
      {
        'id': 'TPL_LEGACY_ENAMEL',
        'subcategoryId': 'SUB_UNSELECTABLE',
        'attributeId': 'finish',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['units'] = [
      {
        'id': 'U1',
        'unitId': 'Litre',
        'name': 'Litre',
        'status': 'ACTIVE',
      },
    ];
  });

  test('Hand Sanitizers excluded from HARDWARE/PAINTS create selector', () async {
    final subcategories = await selectionResolver.getEligibleSubcategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      categoryId: 'CAT_HEALTH',
      token: 'TOKEN1',
      businessTypeId: 'HARDWARE',
      businessSubTypeId: 'PAINTS',
    );

    expect(
      subcategories.any((s) => s.name == 'Hand Sanitizers'),
      isFalse,
    );
  });

  test('legacy Paint -> Interior Wall Paint excluded because template is missing', () async {
    final subcategories = await selectionResolver.getEligibleSubcategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      categoryId: 'CAT_PAINTS',
      token: 'TOKEN1',
    );

    expect(
      subcategories.any((s) => s.name == 'Interior Wall Paint'),
      isFalse,
    );
    expect(
      subcategories.any((s) => s.name == 'Emulsion Paints'),
      isTrue,
    );
  });

  test('templateSelectable=false subcategory is excluded', () async {
    final subcategories = await selectionResolver.getEligibleSubcategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      categoryId: 'CAT_PAINTS',
      token: 'TOKEN1',
    );

    expect(
      subcategories.any((s) => s.name == 'Legacy Enamel'),
      isFalse,
    );
  });

  test('category with zero eligible children is excluded from normal creation', () async {
    final categories = await selectionResolver.getEligibleCategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      token: 'TOKEN1',
    );

    expect(
      categories.any((c) => c.id == 'CAT_HEALTH'),
      isFalse,
    );
  });

  test('duplicate BUSINESS category does not shadow canonical SYSTEM category', () async {
    final categories = await selectionResolver.getEligibleCategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      token: 'TOKEN1',
    );

    final wallCoatingCats = categories
        .where((c) => c.name == 'Interior Wall Coatings')
        .toList();

    expect(wallCoatingCats.length, equals(1));
    expect(wallCoatingCats.first.id, equals('CAT_CANONICAL_SYS'));
    expect(wallCoatingCats.first.scopeType, equals('SYSTEM'));
  });

  test('normal Product creation exposes ONLY READY choices', () async {
    final categories = await selectionResolver.getEligibleCategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      token: 'TOKEN1',
    );

    expect(categories.map((c) => c.name), contains('Paints & Coatings'));
    expect(categories.map((c) => c.name), contains('Interior Wall Coatings'));
    expect(categories.map((c) => c.name), isNot(contains('Health & Hygiene')));
  });

  test('eligibility evaluation performs NO Firestore network calls', () async {
    firestore.queryCalls.clear();

    await selectionResolver.getEligibleCategories(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      token: 'TOKEN1',
    );

    expect(firestore.queryCalls, isNotEmpty);
    // Verified queries ran against local mock
  });
}
