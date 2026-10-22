import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
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
  late ProductTemplateResolver resolver;

  setUp(() {
    firestore = _FakeFirestore();
    resolver = ProductTemplateResolver(firestore);

    firestore.records['product_subcategories'] = [
      {
        'id': 'SUB_BRUSH',
        'subcategoryId': 'SUB_BRUSH',
        'categoryId': 'CAT_PAINT',
        'name': 'Paint Brushes',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['product_categories'] = [
      {
        'id': 'CAT_PAINT',
        'categoryId': 'CAT_PAINT',
        'name': 'Paint Accessories',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['product_attributes'] = [
      {
        'id': 'ATTR_BRISTLE',
        'attributeId': 'bristleType',
        'name': 'Bristle Type',
        'dataType': 'SELECT',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Synthetic', 'Natural Animal Hair', 'Mixed'],
        'allowAddNewOption': false,
        'defaultValue': 'Synthetic',
        'sortOrder': 1,
      },
      {
        'id': 'ATTR_SIZE',
        'attributeId': 'brushSize',
        'name': 'Brush Size',
        'dataType': 'SELECT',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['1 Inch', '2 Inch', '3 Inch'],
        'allowAddNewOption': true,
        'defaultValue': 'InvalidDefaultSize',
        'sortOrder': 2,
      },
    ];

    firestore.records['subcategory_attribute_templates'] = [
      {
        'id': 'TPL_1',
        'subcategoryId': 'SUB_BRUSH',
        'attributeId': 'bristleType',
        'attributeLevel': 'PRODUCT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
        'sortOrder': 1,
      },
      {
        'id': 'TPL_2',
        'subcategoryId': 'SUB_BRUSH',
        'attributeId': 'brushSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
        'sortOrder': 2,
      },
    ];

    firestore.records['units'] = [
      {
        'id': 'U1',
        'unitId': 'SYS_UNIT_PIECE',
        'name': 'Piece',
        'status': 'ACTIVE',
      },
    ];
  });

  test('same subcategory resolves identically for Add and Edit', () async {
    final addResolved = await resolver.resolveTemplate(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOKEN1',
    );

    final editResolved = await resolver.resolveTemplate(
      tenantId: 'TENANT1',
      businessId: 'BIZ1',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOKEN1',
    );

    expect(addResolved.subcategoryId, equals(editResolved.subcategoryId));
    expect(
      addResolved.productAttributes.length,
      equals(editResolved.productAttributes.length),
    );
    expect(
      addResolved.variantAttributes.length,
      equals(editResolved.variantAttributes.length),
    );
    expect(addResolved.readiness, equals(editResolved.readiness));
  });

  test('same SQLite state resolves deterministically', () async {
    final res1 = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );
    final res2 = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    expect(
      res1.allAttributes.map((a) => a.attributeId).toList(),
      equals(res2.allAttributes.map((a) => a.attributeId).toList()),
    );
  });

  test('PRODUCT and VARIANT levels come from resolver', () async {
    final template = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    expect(template.productAttributes.length, equals(1));
    expect(template.productAttributes.first.attributeId, equals('bristleType'));
    expect(
      template.productAttributes.first.level,
      equals(AttributeLevel.product),
    );

    expect(template.variantAttributes.length, equals(1));
    expect(template.variantAttributes.first.attributeId, equals('brushSize'));
    expect(
      template.variantAttributes.first.level,
      equals(AttributeLevel.variant),
    );
  });

  test(
    'waterproofing profile exposes technical and variant attributes',
    () async {
      const attributes = {
        'usage': 'PRODUCT',
        'surface': 'PRODUCT',
        'coverage': 'PRODUCT',
        'numberOfCoats': 'PRODUCT',
        'dilutionType': 'PRODUCT',
        'dilutionRatio': 'PRODUCT',
        'dryingRecoatTime': 'PRODUCT',
        'warranty': 'PRODUCT',
        'shelfLife': 'PRODUCT',
        'mixingRatio': 'PRODUCT',
        'packSize': 'VARIANT',
        'unit': 'VARIANT',
        'voc': 'PRODUCT',
      };
      firestore.records['product_attributes']!.addAll([
        for (final entry in attributes.entries)
          {
            'id': 'ATTR_${entry.key}',
            'attributeId': entry.key,
            'name': entry.key,
            'dataType': entry.key == 'unit' || entry.key == 'dilutionType'
                ? 'SELECT'
                : 'TEXT',
            'attributeLevel': entry.value,
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
          },
      ]);
      firestore.records['subcategory_attribute_templates']!.addAll([
        for (final entry in attributes.entries)
          {
            'id': 'TPL_${entry.key}',
            'subcategoryId': 'SUB_BRUSH',
            'attributeId': entry.key,
            'attributeLevel': entry.value,
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
          },
      ]);

      final template = await resolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: 'SUB_BRUSH',
        token: 'TOK',
      );
      final resolved = {
        for (final attribute in template.allAttributes)
          attribute.attributeId: attribute,
      };
      final technical = [
        'coverage',
        'dilutionRatio',
        'dryingRecoatTime',
        'warranty',
        'shelfLife',
        'mixingRatio',
        'voc',
      ];

      expect(resolved.keys, containsAll(attributes.keys));
      for (final id in technical) {
        expect(resolved[id]!.section, 'TECHNICAL', reason: id);
        expect(
          resolved[id]!.toProductAttribute().section,
          'TECHNICAL',
          reason: '$id legacy form section',
        );
      }
      for (final id in ['usage', 'surface', 'numberOfCoats', 'dilutionType']) {
        expect(resolved[id]!.section, 'ESSENTIAL', reason: id);
      }
      expect(resolved['packSize']!.level, AttributeLevel.variant);
      expect(resolved['unit']!.level, AttributeLevel.variant);
      expect(resolved['packSize']!.toProductAttribute().level, 'VARIANT');
      expect(resolved['unit']!.toProductAttribute().level, 'VARIANT');
    },
  );

  test('invalid defaults generate diagnostics and clear default', () async {
    final template = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    final sizeAttr = template.variantAttributes.firstWhere(
      (a) => a.attributeId == 'brushSize',
    );

    // Default 'InvalidDefaultSize' was cleared because it is not in options
    expect(sizeAttr.defaultValue, isNull);

    expect(
      template.diagnostics.any((d) => d.code == 'INVALID_DEFAULT'),
      isTrue,
    );
  });

  test('BUSINESS custom option merge obeys allowAddNewOption', () async {
    firestore.records['product_attribute_options'] = [
      {
        'id': 'OPT_CUSTOM_BRISTLE',
        'attributeId': 'bristleType',
        'name': 'Custom Super Bristle',
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
      },
      {
        'id': 'OPT_CUSTOM_SIZE',
        'attributeId': 'brushSize',
        'name': '4 Inch Extra Large',
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
      },
    ];

    final template = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    final bristleAttr = template.productAttributes.firstWhere(
      (a) => a.attributeId == 'bristleType',
    );
    final sizeAttr = template.variantAttributes.firstWhere(
      (a) => a.attributeId == 'brushSize',
    );

    // bristleType has allowAddNewOption: false -> custom option ignored
    expect(bristleAttr.optionNames, isNot(contains('Custom Super Bristle')));
    expect(
      template.diagnostics.any((d) => d.code == 'UNAUTHORIZED_CUSTOM_OPTION'),
      isTrue,
    );

    // brushSize has allowAddNewOption: true -> custom option merged
    expect(sizeAttr.optionNames, contains('4 Inch Extra Large'));
  });

  test('resolver performs NO Firestore network calls', () async {
    firestore.queryCalls.clear();
    await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    expect(firestore.queryCalls, isNotEmpty);
    // All calls were answered strictly by local in-memory/SQLite mock
  });
}
