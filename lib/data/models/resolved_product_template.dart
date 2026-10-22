import 'product_attribute.dart';

/// State of subcategory template readiness.
enum TemplateReadinessState { ready, unavailable, invalid, missingTemplate }

/// Level assignment for a product attribute in effective metadata.
enum AttributeLevel { product, variant }

/// Scope of condition evaluation.
enum ConditionScope { product, variant, anyVariant, allVariants }

/// Authoritative representation of a resolved attribute option.
class ResolvedAttributeOption {
  const ResolvedAttributeOption({
    required this.id,
    required this.name,
    this.code,
    this.scopeType = 'SYSTEM',
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? code;
  final String scopeType;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (code != null) 'code': code,
    'scopeType': scopeType,
    'sortOrder': sortOrder,
  };
}

/// Evaluator interface for visibility or requirement conditions.
class ResolvedCondition {
  const ResolvedCondition({
    required this.targetAttributeId,
    required this.operator,
    required this.expectedValues,
    this.scope = ConditionScope.product,
  });

  final String targetAttributeId;
  final String operator; // 'EQUALS', 'IN', 'NOT_IN'
  final List<dynamic> expectedValues;
  final ConditionScope scope;

  bool _matchSingleValue(dynamic value) {
    if (value == null) return operator == 'NOT_IN';
    final valStr = value.toString().trim().toLowerCase();
    final expectedStrs = expectedValues
        .map((e) => e.toString().trim().toLowerCase())
        .toSet();

    bool isAliasMatch() {
      if (valStr.contains('fixed') &&
          expectedStrs.any((e) => e.contains('fixed'))) {
        return true;
      }
      if ((valStr.contains('ready') || valStr.contains('multiple')) &&
          expectedStrs.any(
            (e) => e.contains('ready') || e.contains('multiple'),
          )) {
        return true;
      }
      if ((valStr.contains('tintable') || valStr.contains('base')) &&
          expectedStrs.any(
            (e) => e.contains('tintable') || e.contains('base'),
          )) {
        return true;
      }
      if ((valStr.contains('clear') || valStr.contains('transparent')) &&
          expectedStrs.any(
            (e) => e.contains('clear') || e.contains('transparent'),
          )) {
        return true;
      }
      if ((valStr.contains('not applicable') || valStr.contains('n/a')) &&
          expectedStrs.any(
            (e) => e.contains('not applicable') || e.contains('n/a'),
          )) {
        return true;
      }
      return false;
    }

    if (operator == 'EQUALS' || operator == 'IN') {
      if (expectedValues.contains(value) ||
          expectedStrs.contains(valStr) ||
          isAliasMatch()) {
        return true;
      }
      return false;
    } else if (operator == 'NOT_IN') {
      return !expectedValues.contains(value) &&
          !expectedStrs.contains(valStr) &&
          !isAliasMatch();
    }
    return true;
  }

  bool evaluate(
    Map<String, dynamic> productValues, [
    Map<String, dynamic>? variantValues,
    List<Map<String, dynamic>>? allVariantValues,
  ]) {
    switch (scope) {
      case ConditionScope.product:
        return _matchSingleValue(productValues[targetAttributeId]);

      case ConditionScope.variant:
        final val =
            variantValues != null &&
                variantValues.containsKey(targetAttributeId)
            ? variantValues[targetAttributeId]
            : productValues[targetAttributeId];
        return _matchSingleValue(val);

      case ConditionScope.anyVariant:
        final variants =
            allVariantValues ?? (variantValues != null ? [variantValues] : []);
        if (variants.isEmpty) {
          return _matchSingleValue(productValues[targetAttributeId]);
        }
        return variants.any((v) {
          final attrValues = v['attributeValues'] is Map
              ? Map<String, dynamic>.from(v['attributeValues'] as Map)
              : v;
          final val = attrValues.containsKey(targetAttributeId)
              ? attrValues[targetAttributeId]
              : (v.containsKey(targetAttributeId)
                    ? v[targetAttributeId]
                    : productValues[targetAttributeId]);
          return _matchSingleValue(val);
        });

      case ConditionScope.allVariants:
        final variants =
            allVariantValues ?? (variantValues != null ? [variantValues] : []);
        if (variants.isEmpty) {
          return _matchSingleValue(productValues[targetAttributeId]);
        }
        return variants.every((v) {
          final attrValues = v['attributeValues'] is Map
              ? Map<String, dynamic>.from(v['attributeValues'] as Map)
              : v;
          final val = attrValues.containsKey(targetAttributeId)
              ? attrValues[targetAttributeId]
              : (v.containsKey(targetAttributeId)
                    ? v[targetAttributeId]
                    : productValues[targetAttributeId]);
          return _matchSingleValue(val);
        });
    }
  }
}

/// Unit rules exposed by the template resolver.
class ResolvedUnitRule {
  const ResolvedUnitRule({
    this.allowedPackUnits = const [],
    this.defaultPackUnit,
    List<String> allowedSellingUnits = const [],
    String? defaultSellingUnit,
    List<String>? allowedSoldAsUnits,
    String? defaultSoldAsUnit,
    this.allowedBaseUnits = const [],
    this.defaultBaseUnit,
    this.conversionAllowed = false,
    this.conversionDimension,
    this.conversionRequiresExplicitFactor = true,
    this.unitAliases = const {},
    this.unitDimensions = const {},
    this.explicitContract = false,
  }) : allowedSellingUnits = allowedSoldAsUnits ?? allowedSellingUnits,
       defaultSellingUnit = defaultSoldAsUnit ?? defaultSellingUnit;

  final List<String> allowedPackUnits;
  final String? defaultPackUnit;
  final List<String> allowedSellingUnits;
  final String? defaultSellingUnit;
  final List<String> allowedBaseUnits;
  final String? defaultBaseUnit;
  final bool conversionAllowed;
  final String? conversionDimension;
  final bool conversionRequiresExplicitFactor;
  final bool explicitContract;
  // Local master IDs/names resolve to their own display identity. This does not
  // approve Phase 8 aliases or migrate any saved unit reference.
  final Map<String, String> unitAliases;
  final Map<String, String> unitDimensions;

  List<String> get allowedSoldAsUnits => allowedSellingUnits;
  String? get defaultSoldAsUnit => defaultSellingUnit;

  static const measurementDimensions = {
    'litre': 'VOLUME',
    'millilitre': 'VOLUME',
    'kilogram': 'MASS',
    'gram': 'MASS',
  };
  static const containers = {
    'cartridge',
    'tube',
    'pouch',
    'can',
    'bag',
    'bucket',
    'bottle',
    'jar',
    'drum',
    'pack',
    'box',
    'set',
    'tin',
    'barrel',
  };

  String canonicalUnit(Object? value) {
    final key = value?.toString().trim().toLowerCase() ?? '';
    return (unitAliases[key] ?? key).toLowerCase();
  }

  bool allows(Object? value, List<String> allowed) =>
      value != null &&
      allowed.any((u) => canonicalUnit(u) == canonicalUnit(value));

  String? dimensionOf(Object? value) {
    final key = canonicalUnit(value);
    return unitDimensions[key] ?? measurementDimensions[key];
  }

  bool isMeasurement(Object? value) =>
      !isContainer(value) &&
      !{'piece', 'sheet', 'roll', 'pair'}.contains(canonicalUnit(value)) &&
      {'MASS', 'VOLUME'}.contains(dimensionOf(value));

  bool isContainer(Object? value) => containers.contains(canonicalUnit(value));

  /// Shared form transition: only approved defaults survive a new classification.
  /// It never changes variantId/SKU/barcode or invents a conversion factor.
  void reconcileVariantState(
    Map<String, dynamic> row, {
    bool reset = false,
    bool preserveExisting = false,
  }) {
    // An existing converted variant needs metadata review, not an implicit
    // rewrite to unconverted stock while editing unrelated Product fields.
    if (preserveExisting &&
        !reset &&
        row['_packaging'] == true &&
        (!conversionAllowed ||
            !allows(row['_baseUnit'], allowedBaseUnits) ||
            !allows(row['unit'] ?? row['_packUnit'], allowedPackUnits) ||
            !allows(
              row['soldAs'] ?? row['_commercialUnit'],
              allowedSellingUnits,
            ))) {
      return;
    }
    if (reset) {
      for (final key in [
        'unit',
        'packUnit',
        'soldAs',
        'sellingUnit',
        '_packUnit',
        '_commercialUnit',
        '_baseUnit',
        '_conversion',
      ]) {
        row.remove(key);
      }
      row['_packaging'] = false;
    }
    final pack = row['unit'] ?? row['packUnit'] ?? row['_packUnit'];
    if (!allows(pack, allowedPackUnits)) {
      row['unit'] = defaultPackUnit;
      row.remove('packUnit');
    }
    if (row['unit'] == null && allows(pack, allowedPackUnits)) {
      row['unit'] = pack;
    }
    row['_packUnit'] = allows(row['unit'] ?? row['packUnit'], allowedPackUnits)
        ? row['unit'] ?? row['packUnit']
        : null;
    final selling =
        row['sellingUnit'] ?? row['soldAs'] ?? row['_commercialUnit'];
    if (row.containsKey('sellingUnit') &&
        !allows(selling, allowedSellingUnits)) {
      row['sellingUnit'] = defaultSellingUnit;
    }
    row['soldAs'] = allows(selling, allowedSellingUnits)
        ? selling
        : defaultSellingUnit;
    if (row['soldAs'] == null && allows(selling, allowedSellingUnits)) {
      row['soldAs'] = selling;
    }
    row['_commercialUnit'] = allows(row['soldAs'], allowedSellingUnits)
        ? row['soldAs']
        : null;
    if (!conversionAllowed || row['_packaging'] != true) {
      row['_packaging'] = false;
      row['_baseUnit'] = null;
      row['_conversion'] = null;
    } else {
      if (!allows(row['_baseUnit'], allowedBaseUnits)) {
        row['_baseUnit'] = defaultBaseUnit;
      }
      final factor = row['_conversion'];
      if (factor is! num || !factor.isFinite || factor <= 0) {
        row['_conversion'] = null;
      }
    }
  }
}

/// Diagnostic item reported during template resolution.
class TemplateDiagnostic {
  const TemplateDiagnostic({
    required this.code,
    required this.message,
    this.attributeId,
    this.subcategoryId,
    this.categoryId,
    this.severity = 'WARNING', // 'ERROR', 'WARNING', 'INFO'
  });

  final String code;
  final String message;
  final String? attributeId;
  final String? subcategoryId;
  final String? categoryId;
  final String severity;

  @override
  String toString() =>
      '[$severity] $code ($subcategoryId/$attributeId): $message';
}

/// Authoritative resolved template attribute metadata.
class ResolvedTemplateAttribute {
  const ResolvedTemplateAttribute({
    required this.attributeId,
    required this.displayName,
    required this.level,
    required this.dataType,
    required this.required,
    this.defaultValue,
    required this.options,
    this.allowMultiple = false,
    this.allowAddNewOption = false,
    this.hint,
    this.exampleValue,
    this.technical = false,
    this.sortOrder = 0,
    this.conditions = const [],
    this.allowedUnits = const [],
    this.section = 'ESSENTIAL',
    this.semanticRole,
    this.measurementDimension,
    this.measurementUnitAttributeId,
    this.minimumExclusive,
    this.defaultRules = const [],
    this.visibleWhen,
    this.requiredWhen,
  });

  final String attributeId;
  final String displayName;
  final AttributeLevel level;
  final String
  dataType; // 'TEXT', 'NUMBER', 'SELECT', 'MULTI_SELECT', 'BOOLEAN'
  final bool required;
  final dynamic defaultValue;
  final List<ResolvedAttributeOption> options;
  final bool allowMultiple;
  final bool allowAddNewOption;
  final String? hint;
  final dynamic exampleValue;
  final bool technical;
  final int sortOrder;
  final List<ResolvedCondition> conditions;
  final List<String> allowedUnits;
  final String section;
  final String? semanticRole;
  final String? measurementDimension;
  final String? measurementUnitAttributeId;
  final num? minimumExclusive;
  final List<Map<String, dynamic>> defaultRules;
  final Map<String, dynamic>? visibleWhen;
  final Map<String, dynamic>? requiredWhen;

  List<String> get optionNames => options.map((o) => o.name).toList();

  bool isVisible(
    Map<String, dynamic> productValues, [
    Map<String, dynamic>? variantValues,
    List<Map<String, dynamic>>? allVariantValues,
  ]) {
    if (conditions.isEmpty) return true;
    return conditions.every(
      (c) => c.evaluate(productValues, variantValues, allVariantValues),
    );
  }

  /// Converts resolved attribute to legacy [ProductAttribute] for full backward compatibility.
  ProductAttribute toProductAttribute() => ProductAttribute(
    id: attributeId,
    name: displayName,
    dataType: dataType,
    level: level == AttributeLevel.variant ? 'VARIANT' : 'PRODUCT',
    required: required,
    defaultValue: defaultValue,
    options: optionNames,
    sortOrder: sortOrder,
    allowAddNewOption: allowAddNewOption,
    hintText: hint,
    exampleValue: exampleValue,
    section: section,
    semanticRole: semanticRole,
    measurementDimension: measurementDimension,
    measurementUnitAttributeId: measurementUnitAttributeId,
    minimumExclusive: minimumExclusive,
    defaultRules: defaultRules,
    visibleWhen:
        visibleWhen ??
        (conditions.isNotEmpty
            ? {
                'attributeId': conditions.first.targetAttributeId,
                'in': conditions.first.expectedValues,
              }
            : null),
    requiredWhen: requiredWhen,
  );
}

/// Authoritative resolved product template metadata contract.
class ResolvedProductTemplate {
  const ResolvedProductTemplate({
    required this.categoryId,
    required this.subcategoryId,
    required this.categoryName,
    required this.subcategoryName,
    this.scope = 'SYSTEM',
    this.status = 'ACTIVE',
    required this.readiness,
    required this.productAttributes,
    required this.variantAttributes,
    required this.technicalAttributes,
    this.validationMetadata = const {},
    required this.unitRules,
    this.diagnostics = const [],
  });

  final String categoryId;
  final String subcategoryId;
  final String categoryName;
  final String subcategoryName;
  final String scope;
  final String status;
  final TemplateReadinessState readiness;
  final List<ResolvedTemplateAttribute> productAttributes;
  final List<ResolvedTemplateAttribute> variantAttributes;
  final List<ResolvedTemplateAttribute> technicalAttributes;
  final Map<String, dynamic> validationMetadata;
  final ResolvedUnitRule unitRules;
  final List<TemplateDiagnostic> diagnostics;

  List<ResolvedTemplateAttribute> get allAttributes => [
    ...productAttributes,
    ...variantAttributes,
  ];

  /// Legacy attribute list for backward compatibility.
  List<ProductAttribute> get attributes =>
      allAttributes.map((a) => a.toProductAttribute()).toList();
}
