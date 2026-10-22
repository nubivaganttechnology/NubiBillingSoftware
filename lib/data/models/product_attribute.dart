class ProductAttribute {
  const ProductAttribute({
    required this.id,
    required this.name,
    this.dataType = 'TEXT',
    this.level = 'PRODUCT',
    this.required = false,
    this.defaultValue,
    this.options = const [],
    this.sortOrder = 0,
    this.allowAddNewOption = false,
    this.measurementUnitAttributeId,
    this.measurementDimension,
    this.hintText,
    this.exampleValue,
    this.section = 'ESSENTIAL',
    this.semanticRole,
    this.visibleWhen,
    this.requiredWhen,
    this.minimumExclusive,
    this.defaultRules = const [],
  });
  final String id, name, dataType, level;
  final bool required, allowAddNewOption;
  final dynamic defaultValue;
  final List<String> options;
  final int sortOrder;
  final String? measurementUnitAttributeId, measurementDimension, hintText;
  final dynamic exampleValue;
  final String section;
  final String? semanticRole;
  final Map<String, dynamic>? visibleWhen, requiredWhen;
  final num? minimumExclusive;
  final List<Map<String, dynamic>> defaultRules;

  dynamic initialValue(Map values, [Map? fallback]) {
    if (defaultValue != null) return defaultValue;
    for (final rule in defaultRules) {
      final attrId = rule['attributeId'];
      final value =
          values.containsKey(attrId) ? values[attrId] : fallback?[attrId];
      if (value != null && value.toString().trim().isNotEmpty) {
        return rule['value'];
      }
    }
    return null;
  }

  static bool _matches(
    Map<String, dynamic>? condition,
    Map values, [
    Map? fallback,
    List? allVariants,
  ]) {
    if (condition == null) return true;
    final attrId = condition['attributeId'];
    final allowed = condition['in'] as List? ?? [];
    final scopeStr = (condition['scope'] ?? condition['conditionScope'])?.toString().toUpperCase();

    bool matchSingle(dynamic val) {
      if (val == null && (attrId == 'colourMode' || attrId == 'colourType' || attrId == 'colorType')) {
        final ct = values['colourType'] ?? fallback?['colourType'] ?? values['colourMode'] ?? fallback?['colourMode'];
        if (ct == 'Ready Colour') {
          val = 'Multiple Ready Colours';
        } else if (ct == 'Tintable Base') {
          val = 'Tintable Base';
        } else if (ct == 'Not Applicable' || ct == 'Clear / Transparent') {
          val = 'Not Applicable';
        }
      }
      if (allowed.contains(val)) return true;
      if (val != null) {
        final valStr = val.toString().trim().toLowerCase();
        final allowedStrs = allowed.map((e) => e.toString().trim().toLowerCase()).toSet();
        if (valStr.contains('fixed') && allowedStrs.any((e) => e.contains('fixed'))) return true;
        if ((valStr.contains('ready') || valStr.contains('multiple')) &&
            allowedStrs.any((e) => e.contains('ready') || e.contains('multiple'))) return true;
        if ((valStr.contains('tintable') || valStr.contains('base')) &&
            allowedStrs.any((e) => e.contains('tintable') || e.contains('base'))) return true;
      }
      return false;
    }

    if (scopeStr == 'ANY_VARIANT' || scopeStr == 'ANYVARIANT' || (attrId == 'colourType' && allVariants != null)) {
      if (allVariants != null && allVariants.isNotEmpty) {
        return allVariants.any((v) {
          final attrMap = v is Map ? (v['attributeValues'] is Map ? v['attributeValues'] : v) : {};
          final val = attrMap.containsKey(attrId) ? attrMap[attrId] : (values.containsKey(attrId) ? values[attrId] : fallback?[attrId]);
          return matchSingle(val);
        });
      }
    }

    dynamic val = values.containsKey(attrId) ? values[attrId] : fallback?[attrId];
    return matchSingle(val);
  }

  bool isVisible(Map values, [Map? fallback, List? allVariants]) =>
      _matches(visibleWhen, values, fallback, allVariants);
  bool isRequired(Map values, [Map? fallback, List? allVariants]) =>
      isVisible(values, fallback, allVariants) &&
      (required ||
          (requiredWhen != null && _matches(requiredWhen, values, fallback, allVariants)));

  Map<String, dynamic> get metadata => {
    'attributeId': id,
    'name': name,
    'dataType': dataType,
    'attributeLevel': level,
    'required': required,
    'defaultValue': defaultValue,
    'options': options,
    'sortOrder': sortOrder,
    'allowAddNewOption': allowAddNewOption,
    'measurementUnitAttributeId': measurementUnitAttributeId,
    'measurementDimension': measurementDimension,
    'hintText': hintText,
    'exampleValue': exampleValue,
    'section': section,
    'semanticRole': semanticRole,
    'visibleWhen': visibleWhen,
    'requiredWhen': requiredWhen,
    'minimumExclusive': minimumExclusive,
    'defaultRules': defaultRules,
  };
  factory ProductAttribute.fromData(Map<String, dynamic> d) => ProductAttribute(
    id: d['attributeId'] as String,
    measurementUnitAttributeId: d['measurementUnitAttributeId'] as String?,
    measurementDimension: d['measurementDimension'] as String?,
    hintText: (d['hintText'] ?? d['hint']) as String?,
    exampleValue: d['exampleValue'],
    section: d['section'] as String? ?? 'ESSENTIAL',
    semanticRole: d['semanticRole'] as String?,
    visibleWhen: d['visibleWhen'] == null
        ? null
        : Map<String, dynamic>.from(d['visibleWhen'] as Map),
    requiredWhen: d['requiredWhen'] == null
        ? null
        : Map<String, dynamic>.from(d['requiredWhen'] as Map),
    minimumExclusive: d['minimumExclusive'] as num?,
    defaultRules: (d['defaultRules'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList(),
    name: d['name'] as String? ?? 'Product detail',
    dataType: d['dataType'] as String? ?? 'TEXT',
    level: d['attributeLevel'] as String? ?? 'PRODUCT',
    required: d['required'] == true,
    defaultValue: d['defaultValue'],
    options: (d['options'] as List? ?? []).whereType<String>().toSet().toList(),
    sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    allowAddNewOption: d['allowAddNewOption'] == true,
  );
}
