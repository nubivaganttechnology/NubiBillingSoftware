import '../../core/constants/firebase_constants.dart';
import '../catalogue/system_catalogue_metadata.dart';
import '../models/product_master_value.dart';
import '../models/resolved_product_template.dart';
import 'firestore_data_service.dart';
import 'firestore_value_codec.dart';
import 'product_template_resolver.dart';

/// Exclusion reasons for category/subcategory selection filtering.
enum SelectionExclusionReason {
  none,
  excludedByBusinessType,
  missingTemplate,
  unavailableStatus,
  notTemplateSelectable,
  emptyCategory,
  duplicateShadowed,
  explicitlyExcluded,
}

/// Diagnostic item describing why a category/subcategory was included or excluded.
class CatalogueSelectionDiagnostic {
  const CatalogueSelectionDiagnostic({
    required this.recordId,
    required this.displayName,
    required this.type, // 'CATEGORY' or 'SUBCATEGORY'
    required this.scopeType, // 'SYSTEM' or 'BUSINESS'
    this.parentId,
    required this.eligible,
    required this.exclusionReason,
    this.message,
  });

  final String recordId;
  final String displayName;
  final String type;
  final String scopeType;
  final String? parentId;
  final bool eligible;
  final SelectionExclusionReason exclusionReason;
  final String? message;

  @override
  String toString() =>
      '[$type] $displayName ($recordId) - Eligible: $eligible (${exclusionReason.name}): ${message ?? 'OK'}';
}

/// Authoritative selection resolver for Categories and Subcategories in Create Product workflows.
class CatalogueSelectionResolver {
  CatalogueSelectionResolver(this.firestore);

  final FirestoreDataService firestore;

  /// Returns eligible Categories for normal Product Creation.
  Future<List<ProductMasterValue>> getEligibleCategories({
    required String tenantId,
    required String businessId,
    required String token,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
  }) async {
    final diagnostics = <CatalogueSelectionDiagnostic>[];
    final allCategories = await _loadRawMasters(
      collection: FirebaseConstants.productCategories,
      idField: 'categoryId',
      type: 'CATEGORY',
      tenantId: tenantId,
      businessId: businessId,
      token: token,
    );

    final allSubcategories = await _loadRawMasters(
      collection: FirebaseConstants.productSubcategories,
      idField: 'subcategoryId',
      type: 'SUBCATEGORY',
      tenantId: tenantId,
      businessId: businessId,
      token: token,
    );

    // Evaluate subcategory eligibility
    final eligibleSubcategories = <ProductMasterValue>[];
    for (final subcat in allSubcategories) {
      final diag = await evaluateSubcategoryEligibility(
        subcat: subcat,
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        businessTypeId: businessTypeId,
        businessSubTypeId: businessSubTypeId,
      );
      diagnostics.add(diag);
      if (diag.eligible) {
        eligibleSubcategories.add(subcat);
      }
    }

    // A Category is eligible if active and has at least one eligible subcategory child
    final eligibleCategoriesMap = <String, ProductMasterValue>{};
    for (final cat in allCategories) {
      if (cat.status != 'ACTIVE') {
        diagnostics.add(
          CatalogueSelectionDiagnostic(
            recordId: cat.id,
            displayName: cat.name,
            type: 'CATEGORY',
            scopeType: cat.scopeType,
            eligible: false,
            exclusionReason: SelectionExclusionReason.unavailableStatus,
            message: 'Category status is ${cat.status}',
          ),
        );
        continue;
      }

      final hasEligibleChildren = eligibleSubcategories.any(
        (sub) => sub.categoryId == cat.id,
      );

      if (!hasEligibleChildren) {
        diagnostics.add(
          CatalogueSelectionDiagnostic(
            recordId: cat.id,
            displayName: cat.name,
            type: 'CATEGORY',
            scopeType: cat.scopeType,
            eligible: false,
            exclusionReason: SelectionExclusionReason.emptyCategory,
            message: 'Category has no eligible active subcategory children.',
          ),
        );
        continue;
      }

      // Deduplication & canonical SYSTEM preference
      final normalizedKey = cat.name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      final existing = eligibleCategoriesMap[normalizedKey];
      if (existing == null || cat.scopeType == 'SYSTEM') {
        if (existing != null && existing.scopeType == 'BUSINESS') {
          diagnostics.add(
            CatalogueSelectionDiagnostic(
              recordId: existing.id,
              displayName: existing.name,
              type: 'CATEGORY',
              scopeType: existing.scopeType,
              eligible: false,
              exclusionReason: SelectionExclusionReason.duplicateShadowed,
              message: 'Duplicate BUSINESS category shadowed by canonical SYSTEM category.',
            ),
          );
        }
        eligibleCategoriesMap[normalizedKey] = cat;
      } else if (existing.scopeType == 'SYSTEM' &&
          cat.scopeType == 'BUSINESS') {
        diagnostics.add(
          CatalogueSelectionDiagnostic(
            recordId: cat.id,
            displayName: cat.name,
            type: 'CATEGORY',
            scopeType: cat.scopeType,
            eligible: false,
            exclusionReason: SelectionExclusionReason.duplicateShadowed,
            message: 'BUSINESS duplicate category shadowed by canonical SYSTEM category.',
          ),
        );
      }
    }

    final result = eligibleCategoriesMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  /// Returns eligible Subcategories for normal Product Creation under a given category.
  Future<List<ProductMasterValue>> getEligibleSubcategories({
    required String tenantId,
    required String businessId,
    required String categoryId,
    required String token,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
    ResolvedProductTemplate? resolvedTemplate,
  }) async {
    final allSubcategories = await _loadRawMasters(
      collection: FirebaseConstants.productSubcategories,
      idField: 'subcategoryId',
      type: 'SUBCATEGORY',
      tenantId: tenantId,
      businessId: businessId,
      token: token,
      categoryId: categoryId,
    );

    final eligibleSubcategoriesMap = <String, ProductMasterValue>{};

    for (final subcat in allSubcategories) {
      final diag = await evaluateSubcategoryEligibility(
        subcat: subcat,
        tenantId: tenantId,
        businessId: businessId,
        token: token,
        businessTypeId: businessTypeId,
        businessSubTypeId: businessSubTypeId,
        resolvedTemplate: subcat.id == resolvedTemplate?.subcategoryId
            ? resolvedTemplate
            : null,
      );

      if (!diag.eligible) continue;

      final normalizedKey = subcat.name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      final existing = eligibleSubcategoriesMap[normalizedKey];

      if (existing == null ||
          (subcat.scopeType == 'SYSTEM' && existing.scopeType != 'SYSTEM') ||
          (_isCanonicalSystemSubcategory(subcat) &&
              !_isCanonicalSystemSubcategory(existing))) {
        eligibleSubcategoriesMap[normalizedKey] = subcat;
      }
    }

    final result = eligibleSubcategoriesMap.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  bool _isCanonicalSystemSubcategory(ProductMasterValue subcategory) =>
      subcategory.scopeType == 'SYSTEM' &&
      subcategory.id.startsWith('SYS_SUBCATEGORY_SYS_CATEGORY_');

  /// Detailed evaluation of subcategory eligibility.
  Future<CatalogueSelectionDiagnostic> evaluateSubcategoryEligibility({
    required ProductMasterValue subcat,
    required String tenantId,
    required String businessId,
    required String token,
    required String businessTypeId,
    required String businessSubTypeId,
    ResolvedProductTemplate? resolvedTemplate,
  }) async {
    final diagnostic = await _evaluateSubcategoryEligibility(
      subcat: subcat,
      tenantId: tenantId,
      businessId: businessId,
      token: token,
      businessTypeId: businessTypeId,
      businessSubTypeId: businessSubTypeId,
      resolvedTemplate: resolvedTemplate,
    );
    return diagnostic;
  }

  Future<CatalogueSelectionDiagnostic> _evaluateSubcategoryEligibility({
    required ProductMasterValue subcat,
    required String tenantId,
    required String businessId,
    required String token,
    required String businessTypeId,
    required String businessSubTypeId,
    ResolvedProductTemplate? resolvedTemplate,
  }) async {
    if (subcat.status != 'ACTIVE') {
      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.unavailableStatus,
        message: 'Status is ${subcat.status}',
      );
    }

    final data = subcat.rawFields ?? {};

    // Business Scope / Exclusion check (Hand Sanitizers, etc.)
    final scopeTag = '$businessTypeId/$businessSubTypeId';
    final excludedScopes = _listValues(data['excludedBusinessScopes']);
    final excludedSubTypes = _listValues(data['excludedBusinessSubTypeIds']);

    final isHandSanitizers =
        subcat.id ==
            'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS' ||
        subcat.name.toLowerCase() == 'hand sanitizers';

    if (isHandSanitizers && businessSubTypeId == 'PAINTS') {
      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.excludedByBusinessType,
        message: 'Hand Sanitizers is explicitly excluded from Paints business context.',
      );
    }

    if (excludedScopes.contains(scopeTag) ||
        excludedScopes.contains(businessTypeId) ||
        excludedSubTypes.contains(businessSubTypeId)) {
      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.excludedByBusinessType,
        message: 'Record is explicitly excluded from $scopeTag scope.',
      );
    }

    // These are explicit catalogue eligibility controls. A valid resolved
    // template cannot override an explicitly unavailable or disabled subcategory record.
    final templateStatus = (data['templateStatus'] as String?)?.toUpperCase();
    if (templateStatus == 'UNAVAILABLE' || templateStatus == 'INVALID') {
      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.unavailableStatus,
        message: 'templateStatus is $templateStatus',
      );
    }

    final isExplicitReady =
        (data['profileId'] == 'EXPLICIT_METADATA' ||
            SystemCatalogueMetadata.legacyExplicitSubcategories
                .contains(subcat.id)) &&
        templateStatus == 'READY';

    if (!isExplicitReady &&
        (data['templateSelectable'] == false ||
            data['templateSelectable'] == 'false')) {
      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.notTemplateSelectable,
        message: 'templateSelectable is false',
      );
    }

    // Exact-ID resolution is authoritative; cached readiness hints may be stale.
    final template =
        resolvedTemplate ??
        await ProductTemplateResolver(firestore).resolveTemplate(
          tenantId: tenantId,
          businessId: businessId,
          subcategoryId: subcat.id,
          token: token,
          categoryId: subcat.categoryId,
        );

    if (template.subcategoryId != subcat.id ||
        template.readiness != TemplateReadinessState.ready ||
        template.allAttributes.isEmpty) {
      if (template.readiness == TemplateReadinessState.missingTemplate ||
          template.allAttributes.isEmpty) {
        return CatalogueSelectionDiagnostic(
          recordId: subcat.id,
          displayName: subcat.name,
          type: 'SUBCATEGORY',
          scopeType: subcat.scopeType,
          parentId: subcat.categoryId,
          eligible: false,
          exclusionReason: SelectionExclusionReason.missingTemplate,
          message: 'Subcategory has no active template rows in database.',
        );
      }

      if (template.readiness == TemplateReadinessState.invalid) {
        return CatalogueSelectionDiagnostic(
          recordId: subcat.id,
          displayName: subcat.name,
          type: 'SUBCATEGORY',
          scopeType: subcat.scopeType,
          parentId: subcat.categoryId,
          eligible: false,
          exclusionReason: SelectionExclusionReason.unavailableStatus,
          message: 'Subcategory resolved template is invalid.',
        );
      }

      return CatalogueSelectionDiagnostic(
        recordId: subcat.id,
        displayName: subcat.name,
        type: 'SUBCATEGORY',
        scopeType: subcat.scopeType,
        parentId: subcat.categoryId,
        eligible: false,
        exclusionReason: SelectionExclusionReason.unavailableStatus,
        message: 'Subcategory resolved template is unavailable.',
      );
    }

    return CatalogueSelectionDiagnostic(
      recordId: subcat.id,
      displayName: subcat.name,
      type: 'SUBCATEGORY',
      scopeType: subcat.scopeType,
      parentId: subcat.categoryId,
      eligible: true,
      exclusionReason: SelectionExclusionReason.none,
      message: 'Eligible for normal Product Creation.',
    );
  }

  /// Helper to load raw master records from Firestore/SQLite layer.
  Future<List<ProductMasterValue>> _loadRawMasters({
    required String collection,
    required String idField,
    required String type,
    required String tenantId,
    required String businessId,
    required String token,
    String? categoryId,
  }) async {
    var systemDocs = await firestore.queryDocuments(
      collection: collection,
      filters: [
        FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        if (categoryId != null)
          FirestoreFilter('categoryId', 'EQUAL', categoryId),
      ],
      idToken: token,
    );

    // Fallback if scopeType field was omitted in test mocks
    if (systemDocs.isEmpty) {
      systemDocs = await firestore.queryDocuments(
        collection: collection,
        filters: [
          if (categoryId != null)
            FirestoreFilter('categoryId', 'EQUAL', categoryId),
        ],
        idToken: token,
      );
    }

    final businessDocs = await firestore.queryDocuments(
      collection: collection,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (categoryId != null)
          FirestoreFilter('categoryId', 'EQUAL', categoryId),
      ],
      idToken: token,
    );

    final list = <ProductMasterValue>[];
    final idsSeen = <String>{};

    for (final doc in systemDocs) {
      final d = FirestoreValueCodec.decodeFields(doc['fields']);
      final id =
          (d[idField] as String?) ??
          (d['id'] as String?) ??
          (doc['name'] as String).split('/').last;
      if (!idsSeen.contains(id)) {
        idsSeen.add(id);
        list.add(
          ProductMasterValue(
            id: id,
            name: (d['name'] ?? d['subcategoryName'] ?? id).toString(),
            status: (d['status'] as String?) ?? 'ACTIVE',
            scopeType: (d['scopeType'] as String?) ?? 'SYSTEM',
            categoryId: d['categoryId'] as String?,
            rawFields: d,
          ),
        );
      }
    }

    for (final doc in businessDocs) {
      final d = FirestoreValueCodec.decodeFields(doc['fields']);
      final id =
          (d[idField] as String?) ??
          (d['id'] as String?) ??
          (doc['name'] as String).split('/').last;
      if (!idsSeen.contains(id)) {
        idsSeen.add(id);
        list.add(
          ProductMasterValue(
            id: id,
            name: (d['name'] ?? d['subcategoryName'] ?? id).toString(),
            status: (d['status'] as String?) ?? 'ACTIVE',
            scopeType: 'BUSINESS',
            categoryId: d['categoryId'] as String?,
            rawFields: d,
          ),
        );
      }
    }

    return list;
  }

  List<String> _listValues(dynamic val) {
    if (val == null) return const [];
    if (val is List) return val.map((v) => v.toString()).toList();
    if (val is Map && val['arrayValue'] is Map) {
      final items = val['arrayValue']['values'] as List? ?? [];
      return items
          .map((i) => i['stringValue']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
