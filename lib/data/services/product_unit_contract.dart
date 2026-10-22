import '../models/resolved_product_template.dart';

/// Decodes template/profile constraints. Global unit records are an identity and
/// dimension lookup only; they never supply an allowed-unit fallback.
class ProductUnitContract {
  static ResolvedUnitRule resolve({
    required Map<String, dynamic> metadata,
    required List<ResolvedTemplateAttribute> attributes,
    required List<Map<String, dynamic>> unitMasters,
    required List<TemplateDiagnostic> diagnostics,
    required Map<String, Map<String, dynamic>> declaredRows,
  }) {
    final aliases = <String, String>{};
    final dimensions = <String, String>{};
    for (final unit in unitMasters) {
      final name = (unit['name'] ?? unit['unitId'])?.toString();
      if (name == null) continue;
      for (final value in [name, unit['unitId']]) {
        if (value != null) {
          aliases[value.toString().trim().toLowerCase()] = name;
        }
      }
      final dimension = unit['measurementDimension']?.toString().toUpperCase();
      if (dimension != null) dimensions[name.toLowerCase()] = dimension;
    }
    final profile = metadata['templateProfile'];
    final raw =
        metadata['unitRules'] ?? (profile is Map ? profile['unitRules'] : null);
    final pack = attributes
        .where(
          (a) =>
              a.attributeId == 'unit' ||
              a.attributeId == 'packUnit' ||
              a.semanticRole == 'PACK_UNIT',
        )
        .firstOrNull;
    final selling = attributes
        .where(
          (a) =>
              a.attributeId == 'soldAs' ||
              a.attributeId == 'sellingUnit' ||
              a.attributeId == 'commercialUnit' ||
              a.semanticRole == 'SELLING_UNIT',
        )
        .firstOrNull;
    if (raw == null) {
      diagnostics.add(
        const TemplateDiagnostic(
          code: 'UNIT_CONTRACT_MISSING',
          message: 'Explicit base-unit/conversion contract is missing; declared pack/selling options only, conversion disabled.',
        ),
      );
      List<String> declared(
        ResolvedTemplateAttribute? attr,
        dynamic profileValues,
      ) {
        final fromProfile =
            profileValues is List && profileValues.every((v) => v is String)
            ? profileValues.cast<String>()
            : <String>[];
        final rowOptions = attr == null
            ? null
            : declaredRows[attr.attributeId]?['options'];
        // Read the authored row, not resolved attribute options: an empty
        // row can inherit global definition options in the legacy resolver.
        final fromRow = rowOptions is List
            ? rowOptions.whereType<String>().toList()
            : <String>[];
        if (fromProfile.isNotEmpty && fromRow.isNotEmpty) {
          final common = fromProfile
              .where(
                (u) => fromRow.any((v) => v.toLowerCase() == u.toLowerCase()),
              )
              .toList();
          if (common.length != fromProfile.length ||
              common.length != fromRow.length) {
            diagnostics.add(
              const TemplateDiagnostic(
                code: 'DOMAIN_REVIEW_REQUIRED',
                message: 'Declared profile/template unit sets disagree; only their explicit intersection is exposed.',
              ),
            );
          }
          return common;
        }
        return fromProfile.isNotEmpty ? fromProfile : fromRow;
      }

      final activeProfile = profile is Map && profile['status'] == 'ACTIVE'
          ? profile
          : const <String, dynamic>{};
      final packs = declared(pack, activeProfile['allowedUnits']);
      final sells = declared(
        selling,
        activeProfile['allowedSellingUnits'] ?? activeProfile['allowedSoldAs'],
      );
      final sellChoices = sells.isNotEmpty
          ? sells
          : (selling == null ? packs : <String>[]);
      String? validDefault(
        ResolvedTemplateAttribute? attr,
        List<String> choices,
        dynamic profileDefault,
      ) {
        final value = attr?.defaultValue ?? profileDefault;
        return value is String && choices.contains(value) ? value : null;
      }

      final defaults = activeProfile['defaults'] is Map
          ? activeProfile['defaults'] as Map
          : const <String, dynamic>{};
      final defaultPack = validDefault(pack, packs, defaults['unit']);
      return ResolvedUnitRule(
        allowedPackUnits: packs,
        defaultPackUnit: defaultPack,
        allowedSellingUnits: sellChoices,
        defaultSellingUnit: validDefault(
          selling,
          sellChoices,
          defaults['soldAs'] ??
              defaults['sellingUnit'] ??
              (selling == null ? defaultPack : null),
        ),
        unitAliases: aliases,
        unitDimensions: dimensions,
      );
    }
    final errors = <String>[];
    if (raw is! Map) {
      errors.add('unitRules must be an object');
    }
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    List<String> list(String key) {
      final value = data[key];
      if (value is! List ||
          value.any((v) => v is! String || v.trim().isEmpty)) {
        errors.add('$key must be an explicit list of unit identities');
        return [];
      }
      return value
          .cast<String>()
          .map((u) => aliases[u.trim().toLowerCase()] ?? u.trim())
          .toSet()
          .toList();
    }

    final packs = list('allowedPackUnits');
    final sells = list('allowedSellingUnits');
    final bases = list('allowedBaseUnits');
    final conversion = data['conversionAllowed'] == true;
    final dimension = data['conversionDimension']?.toString().toUpperCase();
    String? defaultValue(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is String) {
        return aliases[value.trim().toLowerCase()] ?? value.trim();
      }
      errors.add('$key must be a unit identity');
      return null;
    }

    final rule = ResolvedUnitRule(
      allowedPackUnits: packs,
      defaultPackUnit: defaultValue('defaultPackUnit'),
      allowedSellingUnits: sells,
      defaultSellingUnit: defaultValue('defaultSellingUnit'),
      allowedBaseUnits: bases,
      defaultBaseUnit: defaultValue('defaultBaseUnit'),
      conversionAllowed: conversion,
      conversionDimension: dimension,
      conversionRequiresExplicitFactor:
          data['conversionRequiresExplicitFactor'] != false,
      unitAliases: aliases,
      unitDimensions: dimensions,
      explicitContract: true,
    );
    if (packs.isEmpty || sells.isEmpty) {
      errors.add('Pack and selling unit sets must not be empty');
    }
    for (final unit in [...packs, ...sells, ...bases]) {
      if (!aliases.containsKey(unit.trim().toLowerCase())) {
        errors.add('Unit $unit is not present in local master metadata');
      }
    }
    if (dimension != null && !{'MASS', 'VOLUME'}.contains(dimension)) {
      errors.add('Unsupported conversion dimension');
    }
    if (data['conversionRequiresExplicitFactor'] != null &&
        data['conversionRequiresExplicitFactor'] is! bool) {
      errors.add('conversionRequiresExplicitFactor must be boolean');
    }
    if (data['conversionAllowed'] is! bool) {
      errors.add('conversionAllowed must be explicit');
    }
    for (final entry in [
      (rule.defaultPackUnit, packs),
      (rule.defaultSellingUnit, sells),
      (rule.defaultBaseUnit, bases),
    ]) {
      if (entry.$1 != null && !rule.allows(entry.$1, entry.$2)) {
        errors.add('Default ${entry.$1} is outside its allowed unit set');
      }
    }
    final baseDimensions = bases
        .map(rule.dimensionOf)
        .whereType<String>()
        .toSet();
    if (baseDimensions.length > 1 ||
        (dimension != null &&
            bases.any((u) => rule.dimensionOf(u) != dimension))) {
      errors.add('Base-unit dimensions are contradictory');
    }
    if (conversion) {
      if (!{'VOLUME', 'MASS'}.contains(dimension) || bases.isEmpty) {
        errors.add(
          'Conversion requires an explicit supported measurement dimension and base set',
        );
      }
      if (!rule.conversionRequiresExplicitFactor) {
        errors.add('Measurement conversion requires an explicit factor');
      }
      if (bases.any(
        (u) => !rule.isMeasurement(u) || rule.dimensionOf(u) != dimension,
      )) {
        errors.add('Base units must be measurements in the declared dimension');
      }
      if (packs.any(
        (u) => rule.isMeasurement(u) && rule.dimensionOf(u) != dimension,
      )) {
        errors.add('Pack measurement dimension conflicts with conversion');
      }
      if (sells.any(
        (u) => rule.isMeasurement(u) && rule.dimensionOf(u) != dimension,
      )) {
        errors.add('Selling measurement dimension conflicts with conversion');
      }
      if (packs.any((u) => !rule.isMeasurement(u))) {
        final content = data['measurementContent'];
        if (content is! Map ||
            content['amount'] is! num ||
            (content['amount'] as num) <= 0 ||
            !(content['amount'] as num).isFinite ||
            rule.dimensionOf(content['unit']) != dimension) {
          errors.add(
            'Packaged conversion requires exact measurementContent amount/unit metadata',
          );
        }
      }
    } else if (bases.any(rule.isContainer)) {
      errors.add('Packaging units cannot be declared measurement bases');
    }
    if (errors.isNotEmpty) {
      diagnostics.add(
        TemplateDiagnostic(
          code: 'DOMAIN_REVIEW_REQUIRED',
          severity: 'ERROR',
          message: 'Invalid unit contract: ${errors.join('; ')}',
        ),
      );
      return const ResolvedUnitRule();
    }
    return rule;
  }
}
