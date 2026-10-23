import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
import 'package:testflutter/data/services/product_validator.dart';

import 'support/decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;

Map<String, dynamic> contract(
  String unit, {
  String? dimension,
  bool conversion = false,
  String? selling,
}) => {
  'allowedPackUnits': [
    unit,
    if (unit == 'Litre') 'Millilitre',
    if (unit == 'Kilogram') 'Gram',
  ],
  'defaultPackUnit': unit,
  'allowedSellingUnits': [selling ?? unit],
  'defaultSellingUnit': selling ?? unit,
  'allowedBaseUnits': [
    unit,
    if (unit == 'Litre') 'Millilitre',
    if (unit == 'Kilogram') 'Gram',
  ],
  'defaultBaseUnit': unit,
  'conversionAllowed': conversion,
  'conversionDimension': dimension,
  'conversionRequiresExplicitFactor': true,
};

void main() {
  late Directory directory;
  late LocalDatabase database;
  late LocalDataSource local;
  late ProductTemplateResolver resolver;
  late ProductValidator validator;
  final units = [
    'Litre',
    'Millilitre',
    'Kilogram',
    'Gram',
    'Piece',
    'Sheet',
    'Roll',
    'Cartridge',
    'Tube',
    'Pouch',
    'Can',
    'Bag',
    'Gallon',
    'Bucket',
    'Drum',
    'Bottle',
    'Jar',
    'Pack',
    'Box',
    'Set',
  ];
  Future<void> seed(String collection, String id, Map<String, dynamic> data) =>
      local.upsertRemote(collection, [
        {
          'name': '$collection/$id',
          'fields': FirestoreRestService.encodeFields({
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            ...data,
          }),
        },
      ]);
  Future<void> template(String id, Map<String, dynamic>? rules) async {
    await seed('product_subcategories', id, {
      'subcategoryId': id,
      'categoryId': 'C',
      'name': id,
      'unitRules': ?rules,
    });
    for (final attribute in ['packSize', 'unit', 'soldAs']) {
      await seed('subcategory_attribute_templates', '$id-$attribute', {
        'subcategoryId': id,
        'attributeId': attribute,
        'attributeLevel': 'VARIANT',
        'required': true,
        'dataType': attribute == 'packSize' ? 'NUMBER' : 'SELECT',
        if (attribute != 'packSize') 'options': units,
        if (attribute == 'unit') 'defaultValue': rules?['defaultPackUnit'],
        if (attribute == 'soldAs') 'defaultValue': rules?['defaultSellingUnit'],
      });
    }
  }

  Future<ResolvedProductTemplate> resolve(String id) =>
      resolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: id,
        categoryId: 'C',
        token: 'ISOLATED',
      );
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('nubibill-phase10b-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    local = LocalDataSource(await database.open('phase10b', 'isolated'));
    final reader = ReadOnlyCatalogueService(local);
    resolver = ProductTemplateResolver(reader);
    validator = ProductValidator(reader);
    await seed('product_categories', 'C', {
      'categoryId': 'C',
      'name': 'Unrelated mutable display name',
    });
    for (final unit in units) {
      await seed('units', 'U_$unit', {
        'unitId': 'U_$unit',
        'name': unit,
        if (unit == 'Gallon') 'measurementDimension': 'VOLUME',
      });
    }
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  for (final entry in {
    'coating': contract(
      'Litre',
      dimension: 'VOLUME',
      conversion: true,
      selling: 'Can',
    ),
    'putty_powder': contract(
      'Kilogram',
      dimension: 'MASS',
      conversion: true,
      selling: 'Bag',
    ),
    'tool': contract('Piece'),
    'masking_tape': contract('Roll'),
    'sandpaper': contract('Sheet'),
    'wallpaper': contract('Roll'),
  }.entries) {
    test(
      '${entry.key} resolves only explicit units and conversion policy',
      () async {
        await template(entry.key, entry.value);
        final result = await resolve(entry.key);
        expect(result.readiness, TemplateReadinessState.ready);
        expect(
          result.unitRules.allowedBaseUnits,
          entry.value['allowedBaseUnits'],
        );
        expect(
          result.unitRules.allowedPackUnits,
          entry.value['allowedPackUnits'],
        );
        expect(
          result.unitRules.allowedSellingUnits,
          entry.value['allowedSellingUnits'],
        );
        expect(
          result.unitRules.conversionAllowed,
          entry.value['conversionAllowed'],
        );
        expect(
          result.unitRules.defaultBaseUnit,
          entry.value['defaultBaseUnit'],
        );
        expect(
          result.unitRules.conversionDimension,
          entry.value['conversionDimension'],
        );
        expect(result.unitRules.allowedBaseUnits, isNot(contains('Gallon')));
        final row = <String, dynamic>{};
        result.unitRules.reconcileVariantState(row);
        expect(row['_packaging'], false);
        expect(row['_conversion'], isNull);
      },
    );
  }
  test('missing explicit conversion contract diagnoses and never falls back to global base units', () async {
    await template('missing', null);
    final result = await resolve('missing');
    expect(result.unitRules.allowedBaseUnits, isEmpty);
    expect(result.unitRules.conversionAllowed, false);
    expect(
      result.diagnostics.any((d) => d.code == 'UNIT_CONTRACT_MISSING'),
      true,
    );
  });
  test('profile-nested contract resolves and IDs/defaults share one canonical unit identity', () async {
    final rules = contract(
      'Litre',
      dimension: 'VOLUME',
      conversion: true,
      selling: 'Can',
    );
    rules['allowedPackUnits'] = ['U_Litre'];
    rules['defaultPackUnit'] = 'Litre';
    await template('nested', null);
    await seed('product_subcategories', 'nested', {
      'subcategoryId': 'nested',
      'categoryId': 'C',
      'name': 'Nested',
      'templateProfile': {'status': 'ACTIVE', 'unitRules': rules},
    });
    final result = await resolve('nested');
    expect(result.unitRules.allowedPackUnits, ['Litre']);
    expect(result.unitRules.defaultPackUnit, 'Litre');
    expect(result.unitRules.conversionAllowed, true);
  });
  test('unknown unit target fails with diagnostic and no conversion', () async {
    final rules = contract('Unknown unit');
    await template('unknown', rules);
    final result = await resolve('unknown');
    expect(result.readiness, TemplateReadinessState.invalid);
    expect(result.unitRules.allowedPackUnits, isEmpty);
    expect(result.unitRules.conversionAllowed, false);
  });
  test(
    'missing all declared unit options exposes no global pack/selling choices',
    () async {
      await seed('product_subcategories', 'empty', {
        'subcategoryId': 'empty',
        'categoryId': 'C',
        'name': 'Empty',
      });
      await seed('subcategory_attribute_templates', 'empty-size', {
        'subcategoryId': 'empty',
        'attributeId': 'packSize',
        'dataType': 'NUMBER',
        'attributeLevel': 'VARIANT',
      });
      // Empty authored options must not inherit the global definition list.
      await seed('product_attributes', 'GLOBAL_UNIT', {
        'attributeId': 'unit',
        'name': 'Pack Unit',
        'dataType': 'SELECT',
        'attributeLevel': 'VARIANT',
        'options': units,
      });
      await seed('subcategory_attribute_templates', 'empty-unit', {
        'subcategoryId': 'empty',
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
        'options': <String>[],
      });
      final result = await resolve('empty');
      expect(result.unitRules.allowedPackUnits, isEmpty);
      expect(result.unitRules.allowedSellingUnits, isEmpty);
      expect(result.unitRules.allowedBaseUnits, isEmpty);
      expect(result.unitRules.conversionAllowed, false);
    },
  );
  test(
    'unrestricted template row inherits definition options for pack and selling units',
    () async {
      await seed('product_subcategories', 'unrestricted', {
        'subcategoryId': 'unrestricted',
        'categoryId': 'C',
        'name': 'Unrestricted Template',
      });
      await seed('product_attributes', 'GLOBAL_UNIT_UNRESTRICTED', {
        'attributeId': 'unit',
        'name': 'Pack Unit',
        'dataType': 'SELECT',
        'attributeLevel': 'VARIANT',
        'options': units,
      });
      // Template row without options key (null options)
      await seed('subcategory_attribute_templates', 'unrestricted-unit', {
        'subcategoryId': 'unrestricted',
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
      });
      final result = await resolve('unrestricted');
      expect(result.unitRules.allowedPackUnits, isNotEmpty);
      expect(result.unitRules.allowedPackUnits, containsAll(['Litre', 'Piece']));
      expect(result.unitRules.allowedSellingUnits, isNotEmpty);
      expect(result.unitRules.allowedSellingUnits, containsAll(['Litre', 'Piece']));

      // Test reconcileVariantState automatically defaulting soldAs to selected unit
      final row = <String, dynamic>{
        'unit': 'Piece',
      };
      result.unitRules.reconcileVariantState(row);
      expect(row['soldAs'], 'Piece');
      expect(row['_commercialUnit'], 'Piece');
    },
  );
  for (final bad in ['Can', 'Cartridge', 'Tube', 'Pouch', 'Piece']) {
    test('$bad never becomes a measurement base', () async {
      final rules = contract(
        'Litre',
        dimension: 'VOLUME',
        conversion: true,
        selling: 'Can',
      );
      rules['allowedBaseUnits'] = [bad];
      rules['defaultBaseUnit'] = bad;
      await template('container', rules);
      final result = await resolve('container');
      expect(result.readiness, TemplateReadinessState.invalid);
      expect(result.unitRules.allowedBaseUnits, isEmpty);
      expect(result.unitRules.conversionAllowed, false);
      expect(
        result.diagnostics.any((d) => d.code == 'DOMAIN_REVIEW_REQUIRED'),
        true,
      );
    });
  }
  test('packaged sealant cannot enable measurement conversion without exact content metadata', () async {
    final rules = contract('Cartridge', dimension: 'MASS', conversion: true);
    rules['allowedBaseUnits'] = ['Gram'];
    rules['defaultBaseUnit'] = 'Gram';
    await template('sealant', rules);
    final result = await resolve('sealant');
    expect(result.unitRules.conversionAllowed, false);
    expect(
      result.diagnostics.any((d) => d.message.contains('measurementContent')),
      true,
    );
  });
  test('legacy converted state is preserved in Edit and rejected without a contract', () async {
    await template('legacy', null);
    final rules = (await resolve('legacy')).unitRules;
    final row = <String, dynamic>{
      'unit': 'Litre',
      'soldAs': 'Can',
      '_packaging': true,
      '_baseUnit': 'Litre',
      '_conversion': 4,
      'variantId': 'KEEP',
    };
    final before = Map<String, dynamic>.from(row);
    rules.reconcileVariantState(row, preserveExisting: true);
    expect(row, before);
    final result = await validator.validateProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Legacy',
      token: 'ISOLATED',
      isNew: false,
      productFields: {'categoryId': 'C', 'subcategoryId': 'legacy'},
      variants: [
        {
          'packUnitId': 'U_Litre',
          'commercialUnitId': 'U_Can',
          'baseUnitId': 'U_Litre',
          'baseQuantityPerCommercialUnit': 4,
          'attributeValues': {'packSize': 4, 'unit': 'Litre', 'soldAs': 'Can'},
        },
      ],
    );
    expect(result.errors.any((e) => e.code == 'CONVERSION_NOT_ALLOWED'), true);
  });
  test('contradictory dimensions and invalid typed defaults diagnose rather than throw', () async {
    final rules = contract('Litre', dimension: 'VOLUME', conversion: true);
    rules['allowedBaseUnits'] = ['Litre', 'Kilogram'];
    rules['defaultPackUnit'] = 42;
    await template('contradiction', rules);
    final result = await resolve('contradiction');
    expect(result.readiness, TemplateReadinessState.invalid);
    expect(result.unitRules.conversionAllowed, false);
  });

  Future<dynamic> validate(
    String id, {
    String base = 'Litre',
    String selling = 'Can',
    bool converting = true,
    num? factor = 4,
    String pack = 'Litre',
  }) => validator.validateProduct(
    tenantId: 'T',
    businessId: 'B',
    productName: 'Valid example',
    token: 'ISOLATED',
    productFields: {
      'categoryId': 'C',
      'subcategoryId': id,
      'attributeValues': <String, dynamic>{},
    },
    variants: [
      {
        'variantId': 'V',
        'packUnitId': 'U_$pack',
        'commercialUnitId': 'U_$selling',
        'baseUnitId': 'U_$base',
        '_packaging': converting,
        'baseQuantityPerCommercialUnit': factor,
        'attributeValues': {'packSize': 4, 'unit': pack, 'soldAs': selling},
      },
    ],
  );
  test('validator accepts explicit compatible conversion with master ID/display-name agreement', () async {
    await template(
      'valid',
      contract('Litre', dimension: 'VOLUME', conversion: true, selling: 'Can'),
    );
    final result = await validate('valid');
    expect(result.isValid, true, reason: '${result.errors}');
  });
  test(
    'validator rejects out-of-contract base unit and incompatible dimension',
    () async {
      await template(
        'valid',
        contract(
          'Litre',
          dimension: 'VOLUME',
          conversion: true,
          selling: 'Can',
        ),
      );
      final result = await validate('valid', base: 'Kilogram');
      expect(result.isValid, false);
      expect(
        result.errors.any(
          (e) => e.code == 'UNIT_NOT_ALLOWED' && e.field == 'baseUnitId',
        ),
        true,
      );
      expect(
        result.errors.any((e) => e.code == 'INCOMPATIBLE_UNIT_DIMENSION'),
        true,
      );
    },
  );
  test('validator rejects conversion when contract says false', () async {
    await template(
      'off',
      contract('Litre', dimension: 'VOLUME', selling: 'Can'),
    );
    final result = await validate('off');
    expect(result.errors.any((e) => e.code == 'CONVERSION_NOT_ALLOWED'), true);
  });
  test('validator rejects out-of-contract selling/pack units and missing explicit factor', () async {
    await template(
      'valid',
      contract('Litre', dimension: 'VOLUME', conversion: true, selling: 'Can'),
    );
    final selling = await validate('valid', selling: 'Kilogram');
    expect(
      selling.errors.any(
        (e) => e.code == 'UNIT_NOT_ALLOWED' && e.field == 'commercialUnitId',
      ),
      true,
    );
    expect(
      selling.errors.any((e) => e.code == 'INCOMPATIBLE_UNIT_DIMENSION'),
      true,
    );
    final wrongPack = await validate('valid', pack: 'Kilogram');
    expect(
      wrongPack.errors.any(
        (e) => e.code == 'UNIT_NOT_ALLOWED' && e.field == 'packUnitId',
      ),
      true,
    );
    for (final invalidFactor in <num?>[
      null,
      0,
      -1,
      double.nan,
      double.infinity,
    ]) {
      final factor = await validate('valid', factor: invalidFactor);
      expect(
        factor.errors.any((e) => e.code == 'INVALID_CONVERSION_FACTOR'),
        true,
      );
    }
  });
  test('unconverted stock base equal to selling unit is preserved without measurement inference', () async {
    await template('stock', contract('Litre', selling: 'Can'));
    final result = await validate(
      'stock',
      base: 'Can',
      converting: false,
      factor: 1,
    );
    expect(result.isValid, true, reason: '${result.errors}');
  });

  final sealant = {
    ...contract('Cartridge'),
    'allowedBaseUnits': <String>[],
    'defaultBaseUnit': null,
  };
  final aerosol = {
    ...contract('Millilitre', selling: 'Can'),
    'allowedBaseUnits': <String>[],
    'defaultBaseUnit': null,
  };
  final transitions = <String, List<Map<String, dynamic>>>{
    'Wall Putty -> Interior Wall Primer': [
      contract('Kilogram', dimension: 'MASS', conversion: true),
      contract('Litre', dimension: 'VOLUME', conversion: true),
    ],
    'Interior Paint -> Brush': [
      contract('Litre', dimension: 'VOLUME', conversion: true),
      contract('Piece'),
    ],
    'Litre coating -> Sandpaper': [
      contract('Litre', dimension: 'VOLUME', conversion: true),
      contract('Sheet'),
    ],
    'Sealant cartridge -> liquid primer': [
      sealant,
      contract('Litre', dimension: 'VOLUME', conversion: true),
    ],
    'Powder coating -> aerosol product': [
      contract('Kilogram', dimension: 'MASS', conversion: true),
      aerosol,
    ],
  };
  for (final entry in transitions.entries) {
    test('shared form unit state transition ${entry.key}', () async {
      await template('before', entry.value[0]);
      await template('after', entry.value[1]);
      final previous = (await resolve('before')).unitRules;
      final next = (await resolve('after')).unitRules;
      final row = <String, dynamic>{
        'variantId': 'KEEP',
        'sku': 'SKU',
        'barcode': 'BAR',
        'unit': previous.defaultPackUnit,
        'soldAs': previous.defaultSellingUnit,
        '_packaging': true,
        '_baseUnit': previous.defaultBaseUnit,
        '_conversion': 20,
      };
      next.reconcileVariantState(row, reset: true);
      expect(row['unit'], next.defaultPackUnit);
      expect(row['soldAs'], next.defaultSellingUnit);
      expect(row['_packaging'], false);
      expect(row['_baseUnit'], isNull);
      expect(row['_conversion'], isNull);
      expect(row['variantId'], 'KEEP');
      expect(row['sku'], 'SKU');
      expect(row['barcode'], 'BAR');
    });
  }
  test('all intended candidate contracts resolve in isolated SQLite without installing a release', () async {
    final model = jsonDecode(
      File('docs/phase10b-intended-catalogue.json').readAsStringSync(),
    ) as Map;
    final definitions = (model['canonicalContentCandidates'] as List)
        .cast<Map>();
    final subDocs = <Map<String, dynamic>>[];
    final templateDocs = <Map<String, dynamic>>[];
    for (final d in definitions) {
      final id = d['canonicalCandidateId'] as String;
      subDocs.add({
        'name': 'product_subcategories/$id',
        'fields': FirestoreRestService.encodeFields({
          'subcategoryId': id,
          'categoryId': d['categoryId'],
          'name': d['name'],
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'unitRules': d['unitRules'],
        }),
      });
      for (final a in d['attributes'] as List) {
        templateDocs.add({
          'name': 'subcategory_attribute_templates/$id-${a['attributeId']}',
          'fields': FirestoreRestService.encodeFields({
            ...Map<String, dynamic>.from(a as Map),
            'subcategoryId': id,
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'attributeLevel': a['level'] == 'variant' ? 'VARIANT' : 'PRODUCT',
            'options': [for (final o in a['options'] as List) o['name']],
          }),
        });
      }
    }
    await local.upsertRemote('product_subcategories', subDocs);
    await local.upsertRemote('subcategory_attribute_templates', templateDocs);
    var enabled = 0;
    var disabled = 0;
    final invalid = <String>[];
    for (final d in definitions) {
      final result = await resolve(d['canonicalCandidateId'] as String);
      if (result.unitRules.conversionAllowed) {
        enabled++;
      } else {
        disabled++;
      }
      if (result.diagnostics.any(
        (v) => v.severity == 'ERROR' && v.code == 'DOMAIN_REVIEW_REQUIRED',
      )) {
        invalid.add(d['canonicalCandidateId'] as String);
      }
      expect(result.unitRules.allowedBaseUnits.length, lessThanOrEqualTo(2));
      if (result.unitRules.conversionAllowed) {
        expect(
          result.unitRules.allowedBaseUnits.every(
            result.unitRules.isMeasurement,
          ),
          true,
        );
        expect(
          result.unitRules.allowedBaseUnits.every(
            (u) =>
                result.unitRules.dimensionOf(u) ==
                result.unitRules.conversionDimension,
          ),
          true,
        );
      }
    }
    expect(
      enabled,
      model['counts']['conversionAllowedTrue'],
      reason: 'Invalid unit contracts: $invalid',
    );
    expect(disabled, model['counts']['conversionAllowedFalse']);
    expect(await local.db.query('local_product_catalogue_releases'), isEmpty);
    expect(model['importable'], false);
    // ignore: avoid_print
    print(
      'PHASE10B_ISOLATED_UNIT_PROOF: ${jsonEncode({'candidates': definitions.length, 'conversionTrue': enabled, 'conversionFalse': disabled, 'domainBlockedUnitIds': invalid})}',
    );
  });
}
