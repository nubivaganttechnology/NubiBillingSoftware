import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
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
  late _FakeFirestore firestore;
  late ProductTemplateResolver templateResolver;
  late ProductValidator validator;

  setUp(() {
    firestore = _FakeFirestore();
    templateResolver = ProductTemplateResolver(firestore);
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
        'id': 'SUB_PRIMER',
        'subcategoryId': 'SUB_PRIMER',
        'categoryId': 'CAT_PAINTS',
        'name': 'Interior Primer',
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
      {
        'id': 'ATTR_UNKNOWN_CUSTOM',
        'attributeId': 'unknownCustomField',
        'name': 'Unknown Custom Field',
        'dataType': 'TEXT',
        'attributeLevel': 'PRODUCT',
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
        'required': true,
      },
      {
        'id': 'T2',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'packSize',
        'attributeLevel': 'VARIANT',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'required': true,
      },
      {
        'id': 'T3',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'unknownCustomField',
        'attributeLevel': 'VARIANT', // Disagrees with definition level 'PRODUCT'
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['units'] = [
      {'id': 'Litre', 'unitId': 'Litre', 'name': 'Litre', 'status': 'ACTIVE'},
    ];
  });

  test('corrected PRODUCT field resolves only under productAttributes', () async {
    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    expect(
      template.productAttributes.any((a) => a.attributeId == 'usage'),
      isTrue,
    );
    expect(
      template.variantAttributes.any((a) => a.attributeId == 'usage'),
      isFalse,
    );
  });

  test('corrected VARIANT field resolves only under variantAttributes', () async {
    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    expect(
      template.variantAttributes.any((a) => a.attributeId == 'packSize'),
      isTrue,
    );
    expect(
      template.productAttributes.any((a) => a.attributeId == 'packSize'),
      isFalse,
    );
  });

  test('no attribute appears in both resolved productAttributes and variantAttributes', () async {
    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    final prodIds = template.productAttributes.map((a) => a.attributeId).toSet();
    final varIds = template.variantAttributes.map((a) => a.attributeId).toSet();

    final intersection = prodIds.intersection(varIds);
    expect(intersection, isEmpty);
  });

  test('placement is deterministic across repeated resolution', () async {
    final t1 = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    final t2 = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    expect(
      t1.productAttributes.map((a) => a.attributeId),
      equals(t2.productAttributes.map((a) => a.attributeId)),
    );
    expect(
      t1.variantAttributes.map((a) => a.attributeId),
      equals(t2.variantAttributes.map((a) => a.attributeId)),
    );
  });

  test('DOMAIN_REVIEW_REQUIRED diagnostic reported for non-canonical disagreements', () async {
    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );

    expect(
      template.diagnostics.any((d) => d.code == 'DOMAIN_REVIEW_REQUIRED' && d.attributeId == 'unknownCustomField'),
      isTrue,
    );
  });

  test('validator validates PRODUCT field once at product level and VARIANT field per variant', () async {
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Test Primer',
      productFields: {
        'categoryId': 'CAT_PAINTS',
        'subcategoryId': 'SUB_PRIMER',
        'attributeValues': {
          'usage': 'Interior Walls', // Product level
        },
      },
      variants: [
        {
          'sku': 'SKU-1',
          'packUnitId': 'Litre',
          'attributeValues': {
            // Missing required 'packSize'!
          },
        }
      ],
      token: 'TOK',
    );

    expect(result.isValid, isFalse);
    expect(
      result.errors.any((e) => e.code == 'MISSING_REQUIRED_ATTRIBUTE' && e.attributeId == 'packSize'),
      isTrue,
    );
  });

  test('automated placement audit across entire system catalogue snapshot', () async {
    final fixtureFile = File('test/fixtures/system_catalogue_v3.json');
    if (!fixtureFile.existsSync()) return;

    final jsonContent = await fixtureFile.readAsString();
    final decoded = jsonDecode(jsonContent) as Map<String, dynamic>;

    final auditFirestore = _FakeFirestore();

    for (final entry in decoded.entries) {
      if (entry.value is List) {
        auditFirestore.records[entry.key] = (entry.value as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    }

    final auditResolver = ProductTemplateResolver(auditFirestore);

    final subcats = auditFirestore.records['product_subcategories'] ?? [];
    final activeSubcats = subcats.where((s) => s['status'] == 'ACTIVE').toList();

    int totalSubcategoriesEvaluated = 0;
    int totalResolvedAttributesEvaluated = 0;
    int domainReviewRemaining = 0;
    int intersectionCount = 0;
    int cleanTemplatesAfter = 0;

    for (final sub in activeSubcats) {
      final subId = (sub['subcategoryId'] ?? sub['id']) as String?;
      if (subId == null || subId.isEmpty) continue;

      final resolved = await auditResolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: subId,
        token: 'TOK',
      );

      if (resolved.readiness == TemplateReadinessState.missingTemplate) continue;

      totalSubcategoriesEvaluated++;
      final allAttrs = [...resolved.productAttributes, ...resolved.variantAttributes];
      totalResolvedAttributesEvaluated += allAttrs.length;

      final prodIds = resolved.productAttributes.map((a) => a.attributeId).toSet();
      final varIds = resolved.variantAttributes.map((a) => a.attributeId).toSet();
      intersectionCount += prodIds.intersection(varIds).length;

      final domainReviewDiags = resolved.diagnostics.where((d) => d.code == 'DOMAIN_REVIEW_REQUIRED').toList();
      domainReviewRemaining += domainReviewDiags.length;

      if (domainReviewDiags.isEmpty) {
        cleanTemplatesAfter++;
      }
    }

    expect(intersectionCount, equals(0)); // Zero attributes appear at both levels!
    expect(totalSubcategoriesEvaluated, greaterThan(0));

    // Print Audit Metrics
    // ignore: avoid_print
    print('PLACEMENT_AUDIT_METRICS: ${jsonEncode({
      'subcategoriesEvaluated': totalSubcategoriesEvaluated,
      'resolvedAttributesEvaluated': totalResolvedAttributesEvaluated,
      'intersectionCount': intersectionCount,
      'domainReviewRemaining': domainReviewRemaining,
      'cleanTemplatesAfter': cleanTemplatesAfter,
    })}');
  });
}
