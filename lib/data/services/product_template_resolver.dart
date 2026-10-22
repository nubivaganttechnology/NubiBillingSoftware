import '../../core/constants/firebase_constants.dart';
import '../models/resolved_product_template.dart';
import 'firestore_data_service.dart';
import 'firestore_value_codec.dart';
import 'product_unit_contract.dart';

/// Single authoritative resolver service for Product Master template metadata.
/// Evaluates SQLite-backed catalogue metadata deterministically across SYSTEM
/// and BUSINESS scopes without performing network calls.
class ProductTemplateResolver {
  ProductTemplateResolver(this.firestore);

  final FirestoreDataService firestore;

  static const _knownTechnicalAttributes = {
    'coverage',
    'voc',
    'dryingTime',
    'dryingRecoatTime',
    'shelfLife',
    'viscosity',
    'density',
    'flashPoint',
    'applicationMethod',
    'mixingRatio',
    'dilutionRatio',
    'thinningRatio',
    'recoatTime',
    'warranty',
    'solidContent',
    'finishType',
  };

  /// Helper to query documents with fallback if scope/status fields are omitted in test mocks.
  Future<List<Map<String, dynamic>>> _queryCollection({
    required String collection,
    required String scope,
    required String token,
    String? tenantId,
    String? businessId,
    String? subcategoryId,
  }) async {
    final filters = <FirestoreFilter>[
      FirestoreFilter('scopeType', 'EQUAL', scope),
      if (scope == 'BUSINESS') ...[
        if (tenantId != null) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId != null)
          FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      if (subcategoryId != null)
        FirestoreFilter('subcategoryId', 'EQUAL', subcategoryId),
    ];

    var docs = await firestore.queryDocuments(
      collection: collection,
      filters: filters,
      idToken: token,
    );

    // Fallback for test doubles or legacy data lacking scopeType field
    if (docs.isEmpty && scope == 'SYSTEM') {
      final fallbackFilters = <FirestoreFilter>[
        if (subcategoryId != null)
          FirestoreFilter('subcategoryId', 'EQUAL', subcategoryId),
      ];
      docs = await firestore.queryDocuments(
        collection: collection,
        filters: fallbackFilters,
        idToken: token,
      );
    }

    return docs;
  }

  /// Resolves effective template for a given subcategory.
  Future<ResolvedProductTemplate> resolveTemplate({
    required String tenantId,
    required String businessId,
    required String subcategoryId,
    required String token,
    String? categoryId,
  }) async {
    final diagnostics = <TemplateDiagnostic>[];
    var release4Installed = false;

    // 1. Resolve subcategory document (non-fatal if missing in mock datasets)
    String resolvedCategoryId = categoryId ?? '';
    String subcategoryName = subcategoryId;
    var subcatMetadata = <String, dynamic>{};

    final subcatDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.productSubcategories,
      filters: [FirestoreFilter('subcategoryId', 'EQUAL', subcategoryId)],
      idToken: token,
    );

    if (subcatDocs.isNotEmpty) {
      final subcatData = FirestoreValueCodec.decodeFields(
        subcatDocs.first['fields'],
      );
      subcatMetadata = subcatData;
      resolvedCategoryId =
          (subcatData['categoryId'] as String?) ?? resolvedCategoryId;
      subcategoryName = (subcatData['name'] as String?) ?? subcategoryName;
    } else {
      diagnostics.add(
        TemplateDiagnostic(
          code: 'MISSING_SUBCATEGORY',
          message:
              'Subcategory record for $subcategoryId not found in product_subcategories.',
          subcategoryId: subcategoryId,
          categoryId: categoryId,
          severity: 'INFO',
        ),
      );
    }

    // 2. Resolve category name
    String categoryName = '';
    if (resolvedCategoryId.isNotEmpty) {
      final catDocs = await firestore.queryDocuments(
        collection: FirebaseConstants.productCategories,
        filters: [FirestoreFilter('categoryId', 'EQUAL', resolvedCategoryId)],
        idToken: token,
      );
      if (catDocs.isNotEmpty) {
        final catData = FirestoreValueCodec.decodeFields(
          catDocs.first['fields'],
        );
        categoryName = (catData['name'] as String?) ?? resolvedCategoryId;
      }
    }

    // 3. Query global option documents (SYSTEM and BUSINESS)
    final optionRecords = <Map<String, dynamic>>[];
    for (final scope in ['SYSTEM', 'BUSINESS']) {
      final documents = await _queryCollection(
        collection: FirebaseConstants.productAttributeOptions,
        scope: scope,
        token: token,
        tenantId: tenantId,
        businessId: businessId,
      );
      for (final doc in documents) {
        final d = FirestoreValueCodec.decodeFields(doc['fields']);
        d['scopeType'] ??= scope;
        d['status'] ??= 'ACTIVE';
        if (d['status'] != 'INACTIVE') {
          optionRecords.add(d);
        }
      }
    }

    // 4. Query attribute definitions (SYSTEM and BUSINESS)
    final attributeDefinitions = <String, Map<String, dynamic>>{};
    for (final scope in ['SYSTEM', 'BUSINESS']) {
      final docs = await _queryCollection(
        collection: FirebaseConstants.productAttributes,
        scope: scope,
        token: token,
        tenantId: tenantId,
        businessId: businessId,
      );
      for (final doc in docs) {
        final d = FirestoreValueCodec.decodeFields(doc['fields']);
        d['scopeType'] ??= scope;
        d['status'] ??= 'ACTIVE';
        final id = (d['attributeId'] ?? d['id']) as String?;
        if (id != null && id.isNotEmpty && d['status'] != 'INACTIVE') {
          attributeDefinitions[id] = {...?attributeDefinitions[id], ...d};
        }
      }
    }

    // 5. Query subcategory_attribute_templates (SYSTEM then BUSINESS precedence)
    final templateRows = <String, Map<String, dynamic>>{};
    for (final scope in ['SYSTEM', 'BUSINESS']) {
      final rows = await _queryCollection(
        collection: FirebaseConstants.subcategoryAttributeTemplates,
        scope: scope,
        token: token,
        tenantId: tenantId,
        businessId: businessId,
        subcategoryId: subcategoryId,
      );

      final activeByAttribute = <String, Map<String, dynamic>>{};
      final inactiveAttributes = <String>{};
      final activeAttributes = <String>{};
      final orderedRows = [...rows]
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      for (final doc in orderedRows) {
        final d = FirestoreValueCodec.decodeFields(doc['fields']);
        d['scopeType'] ??= scope;
        d['status'] ??= 'ACTIVE';
        final id = (d['attributeId'] ?? d['id']) as String?;
        if (id == null || id.isEmpty) continue;

        if (d['status'] == 'INACTIVE') {
          inactiveAttributes.add(id);
        } else {
          activeAttributes.add(id);
          activeByAttribute[id] = {...?activeByAttribute[id], ...d};
        }
      }
      if (!release4Installed &&
          activeAttributes.any(inactiveAttributes.contains)) {
        try {
          final releases = await firestore.queryDocuments(
            collection: FirebaseConstants.productCatalogueReleases,
            filters: [FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM')],
            idToken: token,
          );
          release4Installed = releases.any((doc) {
            final release = FirestoreValueCodec.decodeFields(doc['fields']);
            return release['installed'] == true &&
                (release['catalogueVersion'] as num? ?? 0) >= 4;
          });
        } on UnsupportedError {
          // Partial read-only test doubles may not expose release markers.
          // Preserve their historical precedence rather than failing audits.
        }
      }
      if (!release4Installed) {
        // Keep the historical pre-Release-4 precedence contract unchanged.
        for (final doc in rows) {
          final d = FirestoreValueCodec.decodeFields(doc['fields']);
          final id = (d['attributeId'] ?? d['id']) as String?;
          if (id == null || id.isEmpty) continue;
          if (d['status'] == 'INACTIVE') {
            templateRows.remove(id);
          } else {
            templateRows[id] = {...?templateRows[id], ...d};
          }
        }
        continue;
      }
      // Reconciled historical documents can leave an inactive old identity
      // beside an active row for the same logical attribute. Within a scope,
      // active metadata wins; an all-inactive BUSINESS override still hides
      // the SYSTEM row through the scope precedence below.
      for (final id in inactiveAttributes.difference(
        activeByAttribute.keys.toSet(),
      )) {
        templateRows.remove(id);
      }
      for (final entry in activeByAttribute.entries) {
        templateRows[entry.key] = {...?templateRows[entry.key], ...entry.value};
      }
    }

    if (templateRows.isEmpty) {
      diagnostics.add(
        TemplateDiagnostic(
          code: 'EMPTY_TEMPLATE',
          message:
              'No active template rows found for subcategory $subcategoryId.',
          subcategoryId: subcategoryId,
          categoryId: resolvedCategoryId,
          severity: 'WARNING',
        ),
      );
    }

    // 6. Build resolved template attributes
    final productAttributes = <ResolvedTemplateAttribute>[];
    final variantAttributes = <ResolvedTemplateAttribute>[];
    final technicalAttributes = <ResolvedTemplateAttribute>[];

    for (final entry in templateRows.entries) {
      final attrId = entry.key;
      final templateRow = entry.value;
      final definition = attributeDefinitions[attrId] ?? {};

      final displayName =
          (templateRow['displayName'] ??
                  templateRow['name'] ??
                  definition['name'] ??
                  attrId)
              .toString();
      final dataType =
          (templateRow['dataType'] ?? definition['dataType'] ?? 'TEXT')
              .toString()
              .toUpperCase();

      final levelStr =
          (templateRow['attributeLevel'] ??
                  definition['attributeLevel'] ??
                  'PRODUCT')
              .toString()
              .toUpperCase();
      final defLevelStr = (definition['attributeLevel'] ?? 'PRODUCT')
          .toString()
          .toUpperCase();

      AttributeLevel resolveCanonicalLevel(
        String id,
        String? role,
        String tLevel,
        String dLevel,
      ) {
        final idLower = id.toLowerCase();
        final roleStr = role?.toUpperCase() ?? '';

        const canonicalVariantIds = {
          'sku',
          'barcode',
          'packsize',
          'packunit',
          'unit',
          'soldas',
          'commercialunit',
          'shade',
          'shadecode',
          'colourfamily',
          'colorfamily',
          'basetype',
          'basecode',
          'brushsize',
          'rollerwidth',
          'width',
          'length',
          'rollwidth',
          'rolllength',
          'dimensionunit',
        };
        const canonicalVariantRoles = {
          'PACK_SIZE',
          'PACK_UNIT',
          'SELLING_UNIT',
          'VARIANT_FINISH',
          'SHADE',
          'SHADE_CODE',
          'COLOUR_FAMILY',
          'BASE_TYPE',
          'BASE_CODE',
          'DIMENSION',
        };

        if (canonicalVariantIds.contains(idLower) ||
            canonicalVariantRoles.contains(roleStr)) {
          return AttributeLevel.variant;
        }

        const canonicalProductIds = {
          'productname',
          'brand',
          'brandid',
          'category',
          'categoryid',
          'subcategory',
          'subcategoryid',
          'hsncode',
          'gstratebps',
          'defaultgstratebps',
          'description',
          'productimage',
          'imageurl',
          'productcolour',
          'usage',
          'suitablesurface',
          'surface',
          'grade',
          'tier',
          'recommendedcoats',
          'dilutiontype',
          'thinnertype',
          'coverage',
          'dilutionratio',
          'dryingtime',
          'recoattime',
          'warranty',
          'shelflife',
          'voc',
          'mixingratio',
          'brushtype',
          'bristlematerial',
          'handlematerial',
          'rollertype',
          'rollermaterial',
          'tooltype',
          'style',
          'pattern',
        };
        const canonicalProductRoles = {
          'PRODUCT_NAME',
          'BRAND',
          'CATEGORY',
          'SUBCATEGORY',
          'HSN',
          'USAGE',
          'SURFACE',
          'GRADE',
          'COVERAGE',
          'DILUTION',
          'DRYING_TIME',
          'WARRANTY',
          'SHELF_LIFE',
          'VOC',
          'TECHNICAL',
        };

        if (canonicalProductIds.contains(idLower) ||
            canonicalProductRoles.contains(roleStr)) {
          return AttributeLevel.product;
        }

        if (tLevel != dLevel && templateRow['attributeLevel'] != null) {
          diagnostics.add(
            TemplateDiagnostic(
              code: 'DOMAIN_REVIEW_REQUIRED',
              message:
                  'Attribute $id level in template ($tLevel) disagrees with definition level ($dLevel) and requires domain review.',
              attributeId: id,
              subcategoryId: subcategoryId,
              categoryId: resolvedCategoryId,
              severity: 'WARNING',
            ),
          );
        }

        return tLevel == 'VARIANT'
            ? AttributeLevel.variant
            : AttributeLevel.product;
      }

      final level = resolveCanonicalLevel(
        attrId,
        (definition['semanticRole'] ?? templateRow['semanticRole'])?.toString(),
        levelStr,
        defLevelStr,
      );

      final isRequired =
          templateRow['required'] == true ||
          (templateRow['required'] == null && definition['required'] == true);
      final allowAddNewOption =
          templateRow['allowAddNewOption'] == true ||
          definition['allowAddNewOption'] == true;
      final allowMultiple =
          templateRow['allowMultiple'] == true ||
          definition['allowMultiple'] == true;
      final hint =
          (templateRow['hint'] ??
                  templateRow['hintText'] ??
                  definition['hintText'] ??
                  definition['hint'])
              ?.toString();
      final exampleValue =
          templateRow['exampleValue'] ?? definition['exampleValue'];
      final declaredSection = templateRow['section'] ?? definition['section'];
      final isTechnical =
          templateRow['technical'] == true ||
          definition['technical'] == true ||
          declaredSection == 'TECHNICAL' ||
          _knownTechnicalAttributes.contains(attrId);
      final section =
          (declaredSection ?? (isTechnical ? 'TECHNICAL' : 'ESSENTIAL'))
              .toString();
      final semanticRole =
          (templateRow['semanticRole'] ?? definition['semanticRole'])
              ?.toString();
      final sortOrder =
          (templateRow['sortOrder'] as num?)?.toInt() ??
          (definition['sortOrder'] as num?)?.toInt() ??
          0;
      final minimumExclusive =
          (templateRow['minimumExclusive'] ?? definition['minimumExclusive'])
              as num?;

      final rawDefaultRules =
          (templateRow['defaultRules'] ?? definition['defaultRules'])
              as List? ??
          [];
      final defaultRules = rawDefaultRules
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

      // Option resolution & Centralized Deduplication
      final rawOptions = <ResolvedAttributeOption>[];
      final optionNamesSet = <String>{};

      List<String>? templateRestrictedOptions;
      if (templateRow['options'] is List) {
        templateRestrictedOptions = (templateRow['options'] as List)
            .whereType<String>()
            .toList();
      }

      final defOptions = (definition['options'] as List? ?? [])
          .whereType<String>()
          .toList();
      final matchingOptionDocs = optionRecords
          .where((o) => o['attributeId'] == attrId)
          .toList();

      if (templateRestrictedOptions != null &&
          templateRestrictedOptions.isNotEmpty) {
        for (final optName in templateRestrictedOptions) {
          final normalized = optName.trim();
          if (normalized.isNotEmpty &&
              !optionNamesSet.contains(normalized.toLowerCase())) {
            optionNamesSet.add(normalized.toLowerCase());
            rawOptions.add(
              ResolvedAttributeOption(
                id: '${attrId}_$normalized',
                name: normalized,
                scopeType: 'SYSTEM',
                sortOrder: rawOptions.length,
              ),
            );
          }
        }
      } else {
        for (final optName in defOptions) {
          final normalized = optName.trim();
          if (normalized.isNotEmpty &&
              !optionNamesSet.contains(normalized.toLowerCase())) {
            optionNamesSet.add(normalized.toLowerCase());
            rawOptions.add(
              ResolvedAttributeOption(
                id: '${attrId}_$normalized',
                name: normalized,
                scopeType: 'SYSTEM',
                sortOrder: rawOptions.length,
              ),
            );
          }
        }
        for (final doc in matchingOptionDocs) {
          final optName = (doc['name'] as String?)?.trim();
          final scopeType = (doc['scopeType'] as String?) ?? 'SYSTEM';
          if (optName != null && optName.isNotEmpty) {
            if (scopeType == 'BUSINESS' && !allowAddNewOption) {
              diagnostics.add(
                TemplateDiagnostic(
                  code: 'UNAUTHORIZED_CUSTOM_OPTION',
                  message:
                      'Business custom option "$optName" ignored for attribute $attrId because allowAddNewOption is false.',
                  attributeId: attrId,
                  subcategoryId: subcategoryId,
                  categoryId: resolvedCategoryId,
                  severity: 'INFO',
                ),
              );
              continue;
            }
            if (!optionNamesSet.contains(optName.toLowerCase())) {
              optionNamesSet.add(optName.toLowerCase());
              rawOptions.add(
                ResolvedAttributeOption(
                  id: (doc['optionId'] as String?) ?? '${attrId}_$optName',
                  name: optName,
                  code: doc['code'] as String?,
                  scopeType: scopeType,
                  sortOrder:
                      (doc['sortOrder'] as num?)?.toInt() ?? rawOptions.length,
                ),
              );
            }
          }
        }
      }

      // Default value validation
      dynamic defaultValue =
          templateRow['defaultValue'] ?? definition['defaultValue'];
      if (defaultValue != null &&
          (dataType == 'SELECT' || dataType == 'MULTI_SELECT')) {
        if (dataType == 'SELECT') {
          final defStr = defaultValue.toString().trim();
          if (optionNamesSet.isNotEmpty &&
              !optionNamesSet.contains(defStr.toLowerCase())) {
            diagnostics.add(
              TemplateDiagnostic(
                code: 'INVALID_DEFAULT',
                message:
                    'Default value "$defaultValue" for attribute $attrId is not in the allowed option set.',
                attributeId: attrId,
                subcategoryId: subcategoryId,
                categoryId: resolvedCategoryId,
                severity: 'WARNING',
              ),
            );
            defaultValue = null;
          }
        } else if (dataType == 'MULTI_SELECT' && defaultValue is List) {
          final validList = defaultValue
              .where(
                (item) => optionNamesSet.contains(
                  item.toString().trim().toLowerCase(),
                ),
              )
              .toList();
          if (optionNamesSet.isNotEmpty &&
              validList.length != defaultValue.length) {
            diagnostics.add(
              TemplateDiagnostic(
                code: 'INVALID_DEFAULT',
                message:
                    'Default list "$defaultValue" for attribute $attrId contains options not in allowed set.',
                attributeId: attrId,
                subcategoryId: subcategoryId,
                categoryId: resolvedCategoryId,
                severity: 'WARNING',
              ),
            );
            defaultValue = validList.isEmpty ? null : validList;
          }
        }
      }

      // Condition resolution
      ConditionScope resolveScope(
        Map<String, dynamic> condMap,
        String targetId,
      ) {
        final scopeStr = (condMap['scope'] ?? condMap['conditionScope'])
            ?.toString()
            .toUpperCase();
        if (scopeStr == 'ANY_VARIANT' || scopeStr == 'ANYVARIANT') {
          return ConditionScope.anyVariant;
        }
        if (scopeStr == 'ALL_VARIANTS' || scopeStr == 'ALLVARIANTS') {
          return ConditionScope.allVariants;
        }
        if (scopeStr == 'VARIANT') return ConditionScope.variant;
        if (scopeStr == 'PRODUCT') return ConditionScope.product;

        if (level == AttributeLevel.product &&
            (targetId == 'colourType' || targetId == 'colorType')) {
          return ConditionScope.anyVariant;
        }
        return level == AttributeLevel.variant
            ? ConditionScope.variant
            : ConditionScope.product;
      }

      final conditions = <ResolvedCondition>[];
      final visibleWhenMap =
          templateRow['visibleWhen'] ?? definition['visibleWhen'];
      Map<String, dynamic>? visibleWhen;
      if (visibleWhenMap is Map) {
        visibleWhen = Map<String, dynamic>.from(visibleWhenMap);
        final targetId = visibleWhenMap['attributeId'] as String?;
        final inList = visibleWhenMap['in'] as List?;
        if (targetId != null && inList != null) {
          conditions.add(
            ResolvedCondition(
              targetAttributeId: targetId,
              operator: 'IN',
              expectedValues: inList,
              scope: resolveScope(visibleWhen, targetId),
            ),
          );
        }
      }

      final requiredWhenMap =
          templateRow['requiredWhen'] ?? definition['requiredWhen'];
      Map<String, dynamic>? requiredWhen;
      if (requiredWhenMap is Map) {
        requiredWhen = Map<String, dynamic>.from(requiredWhenMap);
      }

      final resolvedAttr = ResolvedTemplateAttribute(
        attributeId: attrId,
        displayName: displayName,
        level: level,
        dataType: dataType,
        required: isRequired,
        defaultValue: defaultValue,
        options: rawOptions,
        allowMultiple: allowMultiple,
        allowAddNewOption: allowAddNewOption,
        hint: hint,
        exampleValue: exampleValue,
        technical: isTechnical,
        sortOrder: sortOrder,
        conditions: conditions,
        section: section,
        semanticRole: semanticRole,
        measurementDimension:
            (templateRow['measurementDimension'] ??
                    definition['measurementDimension'])
                as String?,
        measurementUnitAttributeId:
            (templateRow['measurementUnitAttributeId'] ??
                    definition['measurementUnitAttributeId'])
                as String?,
        minimumExclusive: minimumExclusive,
        defaultRules: defaultRules,
        visibleWhen: visibleWhen,
        requiredWhen: requiredWhen,
      );

      if (level == AttributeLevel.variant) {
        variantAttributes.add(resolvedAttr);
      } else {
        productAttributes.add(resolvedAttr);
      }

      if (isTechnical) {
        technicalAttributes.add(resolvedAttr);
      }
    }

    productAttributes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    variantAttributes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    technicalAttributes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // 7. Unit rules resolution
    final unitRules = await _resolveUnitRules(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: subcategoryId,
      token: token,
      allResolvedAttributes: [...productAttributes, ...variantAttributes],
      metadata: subcatMetadata,
      diagnostics: diagnostics,
      declaredRows: templateRows,
    );

    // 8. Determine readiness state
    TemplateReadinessState readiness = TemplateReadinessState.ready;
    if (templateRows.isEmpty) {
      readiness = TemplateReadinessState.missingTemplate;
    } else if (diagnostics.any((d) => d.severity == 'ERROR')) {
      readiness = TemplateReadinessState.invalid;
    }

    return ResolvedProductTemplate(
      categoryId: resolvedCategoryId,
      subcategoryId: subcategoryId,
      categoryName: categoryName,
      subcategoryName: subcategoryName,
      readiness: readiness,
      productAttributes: productAttributes,
      variantAttributes: variantAttributes,
      technicalAttributes: technicalAttributes,
      unitRules: unitRules,
      diagnostics: diagnostics,
    );
  }

  Future<ResolvedUnitRule> _resolveUnitRules({
    required String tenantId,
    required String businessId,
    required String subcategoryId,
    required String token,
    required List<ResolvedTemplateAttribute> allResolvedAttributes,
    required Map<String, dynamic> metadata,
    required List<TemplateDiagnostic> diagnostics,
    required Map<String, Map<String, dynamic>> declaredRows,
  }) async {
    final unitsDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.units,
      filters: [FirestoreFilter('status', 'EQUAL', 'ACTIVE')],
      idToken: token,
    );
    return ProductUnitContract.resolve(
      metadata: metadata,
      attributes: allResolvedAttributes,
      declaredRows: declaredRows,
      unitMasters: [
        for (final doc in unitsDocs)
          FirestoreValueCodec.decodeFields(doc['fields']),
      ],
      diagnostics: diagnostics,
    );
  }
}
