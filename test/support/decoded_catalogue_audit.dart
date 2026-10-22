import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';

const productionAccountPath =
    '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db';

/// The same SQL predicates, payload decoding and matching as runtime. No remote
/// client, bootstrap, migrations, query registration or write interface.
class ReadOnlyCatalogueService implements FirestoreDataService {
  ReadOnlyCatalogueService(this.source);
  final LocalDataSource source;

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => source.query(
    collection,
    filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Read-only catalogue audit');
}

Future<Database> openReadOnlyCatalogue(String path) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  await db.execute('PRAGMA query_only=ON');
  await db.execute('PRAGMA busy_timeout=5000');
  return db;
}

String normalizedName(dynamic value) =>
    value.toString().trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

Map<String, dynamic> resolvedAttribute(ResolvedTemplateAttribute a) => {
  'attributeId': a.attributeId,
  'displayName': a.displayName,
  'level': a.level.name,
  'dataType': a.dataType,
  'required': a.required,
  'defaultValue': a.defaultValue,
  'options': a.options.map((o) => o.toJson()).toList(),
  'technical': a.technical,
  'section': a.section,
  'sortOrder': a.sortOrder,
  'semanticRole': a.semanticRole,
  'measurementDimension': a.measurementDimension,
  'measurementUnitAttributeId': a.measurementUnitAttributeId,
  'minimumExclusive': a.minimumExclusive,
  'defaultRules': a.defaultRules,
  'visibleWhen': a.visibleWhen,
  'requiredWhen': a.requiredWhen,
  'allowAddNewOption': a.allowAddNewOption,
  'allowMultiple': a.allowMultiple,
  'conditions': [
    for (final c in a.conditions)
      {
        'targetAttributeId': c.targetAttributeId,
        'scope': c.scope.name,
        'operator': c.operator,
        'expectedValues': c.expectedValues,
      },
  ],
};

Future<Map<String, dynamic>> auditDecodedCatalogue(Database db) async {
  final service = ReadOnlyCatalogueService(LocalDataSource(db));
  final selector = CatalogueSelectionResolver(service);
  final resolver = ProductTemplateResolver(service);
  final activeRows = await db.query(
    'local_product_subcategories',
    where: "status='ACTIVE' AND isDeleted=0",
    orderBy: 'remoteId',
  );
  final categoryDocs = await service.queryDocuments(
    collection: 'product_categories',
    filters: [],
  );
  final categoryNames = {
    for (final d in categoryDocs)
      (d['name'] as String).split('/').last: FirestoreRestService.decodeFields(
        d['fields'],
      )['name'],
  };
  final memberships = <String, List<String>>{};
  for (final row in activeRows) {
    final f = FirestoreRestService.decodeFields(
      jsonDecode(row['payloadJson'] as String),
    );
    final key = jsonEncode([
      row['categoryId'],
      row['scopeType'],
      row['catalogueId'],
      row['businessTypeId'],
      row['businessSubTypeId'],
      normalizedName(f['name']),
    ]);
    memberships.putIfAbsent(key, () => []).add(row['remoteId'] as String);
  }
  final duplicateGroups = [
    for (final e in memberships.entries)
      if (e.value.length > 1) {'groupKey': e.key, 'documentIds': e.value},
  ];
  final records = <Map<String, dynamic>>[];
  for (final row in activeRows) {
    final documentId = row['remoteId'] as String;
    final f = FirestoreRestService.decodeFields(
      jsonDecode(row['payloadJson'] as String),
    );
    // Runtime master loader uses the payload ID; preserve the separate document
    // ID for exact row accounting and explicit mismatch review.
    final payloadId = (f['subcategoryId'] ?? f['id'] ?? documentId).toString();
    final categoryId = f['categoryId']?.toString() ?? '';
    final scope =
        (f['scopeType'] ?? (f['businessId'] != null ? 'BUSINESS' : 'SYSTEM'))
            .toString();
    final sub = ProductMasterValue(
      id: payloadId,
      name: (f['name'] ?? f['subcategoryName'] ?? documentId).toString(),
      status: (f['status'] ?? row['status']).toString(),
      scopeType: scope,
      categoryId: categoryId,
      rawFields: f,
    );
    final eligibility = await selector.evaluateSubcategoryEligibility(
      subcat: sub,
      tenantId: 'T',
      businessId: 'B',
      token: 'READ_ONLY',
      businessTypeId: 'HARDWARE',
      businessSubTypeId: 'PAINTS',
    );
    final template = await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: payloadId,
      categoryId: categoryId,
      token: 'READ_ONLY',
    );
    final templateRows = await db.query(
      'local_subcategory_attribute_templates',
      where: 'subcategoryId=? AND isDeleted=0',
      whereArgs: [payloadId],
    );
    final group = duplicateGroups
        .where((g) => (g['documentIds'] as List).contains(documentId))
        .firstOrNull;
    final explicitScopeExclusion =
        sub.name.toLowerCase() == 'hand sanitizers' ||
        (f['excludedBusinessSubTypeIds'] as List? ?? []).contains('PAINTS') ||
        (f['excludedBusinessScopes'] as List? ?? []).contains(
          'HARDWARE/PAINTS',
        );
    String classification;
    if (payloadId != documentId) {
      classification = 'IDENTITY_MISMATCH_REVIEW';
    } else if (group != null) {
      classification = 'DUPLICATE_REVIEW';
    } else if (explicitScopeExclusion) {
      classification = 'BUSINESS_SCOPE_EXCLUDED';
    } else if (template.readiness == TemplateReadinessState.missingTemplate) {
      classification = 'MISSING_TEMPLATE';
    } else if (f['templateStatus'] == 'UNAVAILABLE' ||
        template.readiness == TemplateReadinessState.unavailable) {
      classification = 'UNAVAILABLE';
    } else if (f['templateSelectable'] == false ||
        f['templateSelectable'] == 'false') {
      // A disabling flag proves current behavior, not intentional domain design.
      classification = 'OTHER_DOMAIN_REVIEW';
    } else if (eligibility.eligible) {
      classification = 'SELECTABLE_READY';
    } else {
      classification = 'OTHER_DOMAIN_REVIEW';
    }
    records.add({
      'documentId': documentId,
      'payloadSubcategoryId': payloadId,
      'categoryId': categoryId,
      'categoryName': categoryNames[categoryId],
      'subcategoryName': sub.name,
      'scope': scope,
      'profile': f['templateProfile'],
      'profileId': f['profileId'],
      'rawFields': f,
      'templateSelectable': f['templateSelectable'],
      'templateStatus': f['templateStatus'],
      'templateIssues': f['templateIssues'],
      'templateRowCount': templateRows.length,
      'activeTemplateRowCount': templateRows
          .where((r) => r['status'] == 'ACTIVE')
          .length,
      'resolvedReadiness': template.readiness.name,
      'selectorEligible': eligibility.eligible,
      'selectorExclusionReason': eligibility.exclusionReason.name,
      'selectorExplanation': eligibility.message,
      'duplicateGroup': group?['groupKey'],
      'classification': classification,
      'productAttributes': template.productAttributes
          .map(resolvedAttribute)
          .toList(),
      'variantAttributes': template.variantAttributes
          .map(resolvedAttribute)
          .toList(),
      'resolvedUnitRules': {
        'allowedPackUnits': template.unitRules.allowedPackUnits,
        'defaultPackUnit': template.unitRules.defaultPackUnit,
        'allowedSoldAsUnits': template.unitRules.allowedSoldAsUnits,
        'defaultSoldAsUnit': template.unitRules.defaultSoldAsUnit,
        'allowedBaseUnits': template.unitRules.allowedBaseUnits,
        'conversionAllowed': template.unitRules.conversionAllowed,
      },
      'resolverDiagnostics': [
        for (final d in template.diagnostics)
          {
            'code': d.code,
            'attributeId': d.attributeId,
            'message': d.message,
            'severity': d.severity,
          },
      ],
    });
  }
  final categories = await selector.getEligibleCategories(
    tenantId: 'T',
    businessId: 'B',
    token: 'READ_ONLY',
  );
  final selectable = <Map<String, dynamic>>[];
  for (final category in categories) {
    final subs = await selector.getEligibleSubcategories(
      tenantId: 'T',
      businessId: 'B',
      categoryId: category.id,
      token: 'READ_ONLY',
    );
    for (final sub in subs) {
      selectable.add({
        'categoryId': category.id,
        'payloadSubcategoryId': sub.id,
        'subcategoryName': sub.name,
        'normalizedName': normalizedName(sub.name),
      });
    }
  }
  final classificationCounts = <String, int>{};
  for (final r in records) {
    final key = r['classification'] as String;
    classificationCounts[key] = (classificationCounts[key] ?? 0) + 1;
  }
  return {
    'activeRows': activeRows.length,
    'records': records,
    'eligibleRecords': records
        .where((r) => r['selectorEligible'] == true)
        .length,
    'selectableEntries': selectable,
    'selectableEntryCount': selectable.length,
    'eligibleCategoryCount': categories.length,
    'duplicateGroups': duplicateGroups,
    'classificationCounts': classificationCounts,
  };
}
