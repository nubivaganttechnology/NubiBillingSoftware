import '../../core/constants/firebase_constants.dart';
import '../models/product_master_value.dart';
import '../models/product_validation_result.dart';
import '../models/resolved_product_template.dart';
import 'catalogue_selection_resolver.dart';
import 'firestore_data_service.dart';
import 'firestore_rest_service.dart';
import 'product_template_resolver.dart';

/// Central repository safety validator executing comprehensive Product & Variant
/// validation prior to local database write or synchronization.
class ProductValidator {
  ProductValidator(this.firestore);

  final FirestoreDataService firestore;

  /// Executes authoritative product validation.
  Future<ProductValidationResult> validateProduct({
    required String tenantId,
    required String businessId,
    required String productName,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
    required String token,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
    bool isNew = true,
    String? currentProductId,
  }) async {
    final errors = <ProductValidationError>[];
    final warnings = <String>[];

    // 1. Basic Name & Payload Structure Check
    final cleanName = productName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.length < 2) {
      errors.add(
        const ProductValidationError(
          code: 'INVALID_ATTRIBUTE_TYPE',
          message: 'Product Name must be at least 2 characters.',
          field: 'productName',
        ),
      );
    }

    if (variants.isEmpty) {
      errors.add(
        const ProductValidationError(
          code: 'MISSING_REQUIRED_ATTRIBUTE',
          message: 'At least one sellable Variant is required.',
          field: 'variants',
        ),
      );
    }

    final categoryId = (productFields['categoryId'] as String?)?.trim() ?? '';
    final subcategoryId =
        (productFields['subcategoryId'] as String?)?.trim() ?? '';

    if (categoryId.isEmpty) {
      errors.add(
        const ProductValidationError(
          code: 'INVALID_CATEGORY',
          message: 'Select a Category.',
          field: 'categoryId',
        ),
      );
    }

    if (subcategoryId.isEmpty) {
      errors.add(
        const ProductValidationError(
          code: 'INVALID_SUBCATEGORY',
          message: 'Select a Subcategory.',
          field: 'subcategoryId',
        ),
      );
    }

    if (errors.isNotEmpty) {
      return ProductValidationResult.failure(errors, warnings);
    }

    // 2. Local Category & Subcategory Existence Check
    final catDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.productCategories,
      filters: [FirestoreFilter('categoryId', 'EQUAL', categoryId)],
      idToken: token,
    );

    if (catDocs.isEmpty) {
      warnings.add(
        'Category $categoryId not found in local product_categories cache.',
      );
    }

    final subcatDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.productSubcategories,
      filters: [FirestoreFilter('subcategoryId', 'EQUAL', subcategoryId)],
      idToken: token,
    );

    ProductMasterValue? selectedSubcategory;
    if (subcatDocs.isEmpty) {
      warnings.add(
        'Subcategory $subcategoryId not found in local product_subcategories cache.',
      );
    } else {
      final subcatData = FirestoreRestService.decodeFields(
        subcatDocs.first['fields'],
      );
      final parentCatId = (subcatData['categoryId'] as String?) ?? '';
      if (parentCatId.isNotEmpty && parentCatId != categoryId) {
        errors.add(
          ProductValidationError(
            code: 'CATEGORY_SUBCATEGORY_MISMATCH',
            message:
                'Subcategory $subcategoryId belongs to category $parentCatId, not $categoryId.',
            field: 'subcategoryId',
          ),
        );
      }
      selectedSubcategory = ProductMasterValue(
        id: (subcatData['subcategoryId'] as String?) ?? subcategoryId,
        name:
            (subcatData['name'] ??
                    subcatData['subcategoryName'] ??
                    subcategoryId)
                .toString(),
        status: (subcatData['status'] as String?) ?? 'ACTIVE',
        scopeType: (subcatData['scopeType'] as String?) ?? 'BUSINESS',
        categoryId: parentCatId.isEmpty ? categoryId : parentCatId,
        rawFields: subcatData,
      );
    }

    if (errors.isNotEmpty) {
      return ProductValidationResult.failure(errors, warnings);
    }

    // Resolve the exact selected subcategory once and use that result for both
    // eligibility and the remaining template-backed validation.
    final templateResolver = ProductTemplateResolver(firestore);
    late final ResolvedProductTemplate resolvedTemplate;
    resolvedTemplate = await templateResolver.resolveTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: subcategoryId,
      token: token,
      categoryId: categoryId,
    );

    // 3. Evaluate the exact selected subcategory for normal Product creation.
    if (isNew) {
      final isCentralProduct = productFields['masterProductId'] != null &&
          productFields['masterProductId'].toString().trim().isNotEmpty;
      final selectionResolver = CatalogueSelectionResolver(firestore);
      final eligibility = selectedSubcategory == null
          ? null
          : await selectionResolver.evaluateSubcategoryEligibility(
              subcat: selectedSubcategory,
              tenantId: tenantId,
              businessId: businessId,
              token: token,
              businessTypeId: businessTypeId,
              businessSubTypeId: businessSubTypeId,
              resolvedTemplate: resolvedTemplate,
            );
      var eligible = eligibility?.eligible ?? false;

      // Central master product adoption: the manufacturer product is already catalogued
      // and verified. If its resolved template is ready, do not block adoption
      // even if the subcategory was marked notTemplateSelectable for generic custom creation.
      if (!eligible && isCentralProduct) {
        if (resolvedTemplate.readiness == TemplateReadinessState.ready &&
            resolvedTemplate.allAttributes.isNotEmpty &&
            eligibility?.exclusionReason ==
                SelectionExclusionReason.notTemplateSelectable) {
          eligible = true;
        }
      }

      if (!eligible) {
        errors.add(
          ProductValidationError(
            code: 'MISSING_TEMPLATE',
            message:
                'Selected subcategory $subcategoryId is unavailable or missing a valid template for Product creation.',
            field: 'subcategoryId',
          ),
        );
      }
    }

    if (errors.isNotEmpty) {
      return ProductValidationResult.failure(errors, warnings);
    }

    // 4. Template Readiness Check
    if (resolvedTemplate.readiness == TemplateReadinessState.missingTemplate ||
        resolvedTemplate.allAttributes.isEmpty) {
      errors.add(
        ProductValidationError(
          code: 'MISSING_TEMPLATE',
          message:
              'Subcategory $subcategoryId has no active attribute template rows.',
          field: 'subcategoryId',
        ),
      );
    }

    if (resolvedTemplate.readiness == TemplateReadinessState.invalid) {
      errors.add(
        ProductValidationError(
          code: 'INVALID_TEMPLATE',
          message: 'Subcategory $subcategoryId template contract is invalid.',
          field: 'subcategoryId',
        ),
      );
    }

    if (resolvedTemplate.readiness == TemplateReadinessState.unavailable) {
      errors.add(
        ProductValidationError(
          code: 'UNAVAILABLE_TEMPLATE',
          message: 'Subcategory $subcategoryId template is unavailable.',
          field: 'subcategoryId',
        ),
      );
    }

    if (errors.isNotEmpty) {
      return ProductValidationResult.failure(errors, warnings);
    }

    final unitRules = resolvedTemplate.unitRules;
    warnings.addAll(
      resolvedTemplate.diagnostics
          .where((d) => d.code == 'UNIT_CONTRACT_MISSING')
          .map((d) => d.message),
    );
    final productAttrValues = Map<String, dynamic>.from(
      productFields['attributeValues'] as Map? ?? {},
    );

    _normalizeColourAliases(productAttrValues, null);

    // 5. Unknown Dynamic Attributes Check
    final allKnownAttrIds = resolvedTemplate.allAttributes
        .map((a) => a.attributeId)
        .toSet();

    for (final key in productAttrValues.keys) {
      if (!key.startsWith('_') &&
          key != 'hsnCode' &&
          key != 'colourMode' &&
          !allKnownAttrIds.contains(key)) {
        if (isNew) {
          errors.add(
            ProductValidationError(
              code: 'UNKNOWN_ATTRIBUTE',
              message:
                  'Unknown attribute $key is not in the subcategory template.',
              attributeId: key,
            ),
          );
        } else {
          warnings.add('Legacy attribute $key ignored in edit.');
        }
      }
    }

    // 6. Product Level Attributes Validation
    for (final a in resolvedTemplate.productAttributes) {
      final val = productAttrValues[a.attributeId];
      final isVisible = _evaluateConditions(
        a.conditions,
        productAttrValues,
        null,
        variants,
      );

      if (isVisible && a.required) {
        if (val == null ||
            (val is String && val.trim().isEmpty) ||
            (val is List && val.isEmpty)) {
          errors.add(
            ProductValidationError(
              code: 'MISSING_REQUIRED_ATTRIBUTE',
              message: '${a.displayName} is required.',
              attributeId: a.attributeId,
            ),
          );
        }
      }

      if (val != null) {
        _validateAttributeValue(a, val, errors, variantIndex: null);
      }
    }

    // 7. Variant Level Validation
    final variantIdsSeen = <String>{};
    final skusSeen = <String>{};
    final barcodesSeen = <String>{};

    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final variantId = v['variantId'] as String?;
      if (variantId != null && variantId.isNotEmpty) {
        if (variantIdsSeen.contains(variantId)) {
          errors.add(
            ProductValidationError(
              code: 'DUPLICATE_VARIANT_ID',
              message: 'Duplicate variant ID $variantId in payload.',
              variantIdOrIndex: i,
            ),
          );
        }
        variantIdsSeen.add(variantId);
      }

      final sku = (v['sku'] ?? v['_sku'] as String?)?.toString().trim() ?? '';
      if (sku.isNotEmpty) {
        if (skusSeen.contains(sku.toLowerCase())) {
          errors.add(
            ProductValidationError(
              code: 'DUPLICATE_SKU',
              message: 'Duplicate SKU "$sku" in save payload.',
              field: 'sku',
              variantIdOrIndex: i,
            ),
          );
        }
        skusSeen.add(sku.toLowerCase());
      }

      final barcode = (v['barcode'] as String?)?.trim() ?? '';
      if (barcode.isNotEmpty) {
        if (barcodesSeen.contains(barcode.toLowerCase())) {
          errors.add(
            ProductValidationError(
              code: 'DUPLICATE_BARCODE',
              message: 'Duplicate barcode "$barcode" in save payload.',
              field: 'barcode',
              variantIdOrIndex: i,
            ),
          );
        }
        barcodesSeen.add(barcode.toLowerCase());
      }

      final variantAttrValues = Map<String, dynamic>.from(
        v['attributeValues'] as Map? ?? {},
      );

      _normalizeColourAliases(variantAttrValues, productAttrValues);
      _normalizeSoldAsAlias(v, variantAttrValues, resolvedTemplate);

      // Validate Variant Attributes
      for (final a in resolvedTemplate.variantAttributes) {
        final val = variantAttrValues[a.attributeId];
        final isVisible = _evaluateConditions(
          a.conditions,
          productAttrValues,
          variantAttrValues,
          variants,
        );

        if (isVisible && a.required) {
          if (val == null ||
              (val is String && val.trim().isEmpty) ||
              (val is List && val.isEmpty)) {
            errors.add(
              ProductValidationError(
                code: 'MISSING_REQUIRED_ATTRIBUTE',
                message: '${a.displayName} is required for Variant ${i + 1}.',
                attributeId: a.attributeId,
                variantIdOrIndex: i,
              ),
            );
          }
        }

        if (val != null) {
          final unitChoices =
              {'unit', 'packUnit'}.contains(a.attributeId) ||
                  a.semanticRole == 'PACK_UNIT'
              ? unitRules.allowedPackUnits
              : {
                      'soldAs',
                      'sellingUnit',
                      'commercialUnit',
                    }.contains(a.attributeId) ||
                    a.semanticRole == 'SELLING_UNIT'
              ? unitRules.allowedSellingUnits
              : null;
          if (unitChoices != null) {
            if (!unitRules.allows(val, unitChoices)) {
              errors.add(
                ProductValidationError(
                  code: 'UNIT_NOT_ALLOWED',
                  message:
                      'Dynamic unit is outside the resolved unit contract.',
                  attributeId: a.attributeId,
                  variantIdOrIndex: i,
                ),
              );
            }
          } else {
            _validateAttributeValue(a, val, errors, variantIndex: i);
          }
        }
      }

      // Canonical vs Dynamic Unit Consistency
      final packUnitId =
          (v['packUnitId'] ??
                  v['unitId'] ??
                  variantAttrValues['unit'] ??
                  variantAttrValues['packUnit'])
              ?.toString();
      final dynamicUnitVal =
          (variantAttrValues['unit'] ?? variantAttrValues['packUnit'])
              ?.toString();

      if (packUnitId != null &&
          dynamicUnitVal != null &&
          unitRules.canonicalUnit(packUnitId) !=
              unitRules.canonicalUnit(dynamicUnitVal)) {
        errors.add(
          ProductValidationError(
            code: 'CANONICAL_ATTRIBUTE_MISMATCH',
            message:
                'Variant ${i + 1} pack unit "$packUnitId" disagrees with dynamic unit "$dynamicUnitVal".',
            field: 'packUnitId',
            variantIdOrIndex: i,
          ),
        );
      }

      // Unit Membership Validation against Template Rules
      if (packUnitId != null) {
        if (!unitRules.allows(packUnitId, unitRules.allowedPackUnits)) {
          errors.add(
            ProductValidationError(
              code: 'UNIT_NOT_ALLOWED',
              message:
                  'Unit "$packUnitId" is not allowed for subcategory $subcategoryId.',
              field: 'packUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
      }

      // Conversion Boundary Validation
      final commercialUnitId =
          (v['commercialUnitId'] ??
                  variantAttrValues['sellingUnit'] ??
                  variantAttrValues['soldAs'])
              ?.toString();
      final baseUnitId = v['baseUnitId']?.toString();
      final rawFactor = v['baseQuantityPerCommercialUnit'];
      final conversionFactor = rawFactor is num ? rawFactor.toDouble() : null;

      final conversionEnabled =
          v['_packaging'] == true ||
          (conversionFactor != null && conversionFactor != 1.0) ||
          (commercialUnitId != null &&
              baseUnitId != null &&
              unitRules.canonicalUnit(commercialUnitId) !=
                  unitRules.canonicalUnit(baseUnitId));

      if (commercialUnitId != null &&
          !unitRules.allows(commercialUnitId, unitRules.allowedSellingUnits)) {
        errors.add(
          ProductValidationError(
            code: 'UNIT_NOT_ALLOWED',
            message: 'Selling unit is outside the resolved unit contract.',
            field: 'commercialUnitId',
            variantIdOrIndex: i,
          ),
        );
      }
      if (conversionEnabled) {
        if (!unitRules.conversionAllowed) {
          errors.add(
            ProductValidationError(
              code: 'CONVERSION_NOT_ALLOWED',
              message: 'Conversion is not enabled by the resolved template contract.',
              field: 'baseUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
        if (baseUnitId != null &&
            baseUnitId.isNotEmpty &&
            !unitRules.allows(baseUnitId, unitRules.allowedBaseUnits)) {
          errors.add(
            ProductValidationError(
              code: 'UNIT_NOT_ALLOWED',
              message: 'Base unit is outside the resolved unit contract.',
              field: 'baseUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
        if (unitRules.conversionAllowed &&
            (unitRules.dimensionOf(baseUnitId) !=
                    unitRules.conversionDimension ||
                unitRules.isContainer(baseUnitId) ||
                (unitRules.isMeasurement(commercialUnitId) &&
                    unitRules.dimensionOf(commercialUnitId) !=
                        unitRules.conversionDimension) ||
                (unitRules.isMeasurement(packUnitId) &&
                    unitRules.dimensionOf(packUnitId) !=
                        unitRules.conversionDimension))) {
          errors.add(
            ProductValidationError(
              code: 'INCOMPATIBLE_UNIT_DIMENSION',
              message: 'Conversion units must match the template measurement dimension.',
              field: 'baseUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
        if (commercialUnitId == null || commercialUnitId.trim().isEmpty) {
          errors.add(
            ProductValidationError(
              code: 'INVALID_UNIT',
              message: 'Selling Unit is required for conversion.',
              field: 'commercialUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
        if (baseUnitId == null || baseUnitId.trim().isEmpty) {
          errors.add(
            ProductValidationError(
              code: 'INVALID_UNIT',
              message: 'Base Unit is required when unit conversion is enabled.',
              field: 'baseUnitId',
              variantIdOrIndex: i,
            ),
          );
        }
        if (conversionFactor == null ||
            !conversionFactor.isFinite ||
            conversionFactor <= 0) {
          errors.add(
            ProductValidationError(
              code: 'INVALID_CONVERSION_FACTOR',
              message: 'Conversion factor must be greater than zero.',
              field: 'baseQuantityPerCommercialUnit',
              variantIdOrIndex: i,
            ),
          );
        }
      }
    }

    // 8. Database Barcode & SKU Uniqueness Checks
    await _validateDatabaseUniqueness(
      tenantId: tenantId,
      businessId: businessId,
      skus: skusSeen,
      barcodes: barcodesSeen,
      token: token,
      errors: errors,
      currentProductId: currentProductId,
    );

    if (errors.isNotEmpty) {
      return ProductValidationResult.failure(errors, warnings);
    }

    return ProductValidationResult.success(warnings);
  }

  void _normalizeColourAliases(
    Map<String, dynamic> values,
    Map<String, dynamic>? fallback,
  ) {
    if (values['colourMode'] == null) {
      final ct = values['colourType'] ?? fallback?['colourType'];
      if (ct == 'Ready Colour') {
        values['colourMode'] = 'Multiple Ready Colours';
      } else if (ct == 'Tintable Base') {
        values['colourMode'] = 'Tintable Base';
      } else if (ct == 'Not Applicable' || ct == 'Clear / Transparent') {
        values['colourMode'] = ct;
      } else if (fallback?['colourMode'] != null) {
        values['colourMode'] = fallback!['colourMode'];
      }
    }
    if (values['colourType'] == null) {
      final cm = values['colourMode'] ?? fallback?['colourMode'];
      if (cm == 'Multiple Ready Colours') {
        values['colourType'] = 'Ready Colour';
      } else if (cm == 'Tintable Base') {
        values['colourType'] = 'Tintable Base';
      } else if (cm == 'Not Applicable' || cm == 'Clear / Transparent') {
        values['colourType'] = cm;
      } else if (fallback?['colourType'] != null) {
        values['colourType'] = fallback!['colourType'];
      }
    }
  }

  void _normalizeSoldAsAlias(
    Map<String, dynamic> variant,
    Map<String, dynamic> values,
    ResolvedProductTemplate template,
  ) {
    if (values['soldAs'] == null) {
      final soldAsAttr = template.variantAttributes
          .where((a) => a.attributeId == 'soldAs')
          .firstOrNull;
      if (soldAsAttr != null) {
        values['soldAs'] =
            soldAsAttr.defaultValue ??
            variant['commercialUnitName'] ??
            variant['commercialUnitId'] ??
            values['unit'];
      }
    }
  }

  void _validateAttributeValue(
    ResolvedTemplateAttribute a,
    dynamic val,
    List<ProductValidationError> errors, {
    int? variantIndex,
  }) {
    if (a.dataType == 'NUMBER') {
      final number = val is num ? val : num.tryParse(val.toString());
      if (number == null || !number.isFinite) {
        errors.add(
          ProductValidationError(
            code: 'INVALID_NUMERIC_VALUE',
            message: '${a.displayName} must be a valid numeric value.',
            attributeId: a.attributeId,
            variantIdOrIndex: variantIndex,
          ),
        );
      } else if (a.minimumExclusive != null && number <= a.minimumExclusive!) {
        errors.add(
          ProductValidationError(
            code: 'INVALID_NUMERIC_VALUE',
            message: '${a.displayName} must be greater than zero.',
            attributeId: a.attributeId,
            variantIdOrIndex: variantIndex,
          ),
        );
      }
    } else if (a.dataType == 'SELECT') {
      final strVal = val.toString().trim();
      final optionNamesLower = a.options
          .map((o) => o.name.toLowerCase())
          .toSet();
      if (optionNamesLower.isNotEmpty &&
          !optionNamesLower.contains(strVal.toLowerCase()) &&
          !a.allowAddNewOption) {
        errors.add(
          ProductValidationError(
            code: 'INVALID_ATTRIBUTE_OPTION',
            message:
                'Selected value "$strVal" for ${a.displayName} is not an allowed option.',
            attributeId: a.attributeId,
            variantIdOrIndex: variantIndex,
          ),
        );
      }
    } else if (a.dataType == 'MULTI_SELECT') {
      if (val is! List) {
        errors.add(
          ProductValidationError(
            code: 'INVALID_ATTRIBUTE_TYPE',
            message: '${a.displayName} must be a list.',
            attributeId: a.attributeId,
            variantIdOrIndex: variantIndex,
          ),
        );
      } else {
        final optionNamesLower = a.options
            .map((o) => o.name.toLowerCase())
            .toSet();
        for (final item in val) {
          final itemStr = item.toString().trim();
          if (optionNamesLower.isNotEmpty &&
              !optionNamesLower.contains(itemStr.toLowerCase()) &&
              !a.allowAddNewOption) {
            errors.add(
              ProductValidationError(
                code: 'INVALID_MULTI_SELECT_OPTION',
                message:
                    'Option "$itemStr" is not allowed for ${a.displayName}.',
                attributeId: a.attributeId,
                variantIdOrIndex: variantIndex,
              ),
            );
          }
        }
      }
    }
  }

  bool _evaluateConditions(
    List<ResolvedCondition> conditions,
    Map<String, dynamic> productValues,
    Map<String, dynamic>? variantValues, [
    List<Map<String, dynamic>>? allVariantValues,
  ]) {
    if (conditions.isEmpty) return true;
    for (final cond in conditions) {
      if (!cond.evaluate(productValues, variantValues, allVariantValues)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _validateDatabaseUniqueness({
    required String tenantId,
    required String businessId,
    required Set<String> skus,
    required Set<String> barcodes,
    required String token,
    required List<ProductValidationError> errors,
    String? currentProductId,
  }) async {
    if (skus.isEmpty && barcodes.isEmpty) return;

    final existingVariants = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );

    for (final doc in existingVariants) {
      final d = FirestoreRestService.decodeFields(doc['fields']);
      final parentProductId = d['productId'] as String?;
      if (currentProductId != null && parentProductId == currentProductId) {
        continue;
      }

      final dbSku = (d['sku'] as String?)?.trim().toLowerCase();
      final dbBarcode = (d['barcode'] as String?)?.trim().toLowerCase();

      if (dbSku != null && skus.contains(dbSku)) {
        errors.add(
          ProductValidationError(
            code: 'DUPLICATE_SKU',
            message: 'SKU "${d['sku']}" already exists in database.',
            field: 'sku',
          ),
        );
      }

      if (dbBarcode != null &&
          dbBarcode.isNotEmpty &&
          barcodes.contains(dbBarcode)) {
        errors.add(
          ProductValidationError(
            code: 'DUPLICATE_BARCODE',
            message:
                'Barcode "${d['barcode']}" / barcode already exists in database.',
            field: 'barcode',
          ),
        );
      }
    }
  }
}
