import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/models/product_validation_result.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
import 'package:testflutter/data/services/product_validator.dart';

import 'decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;

final phase10cModel = jsonDecode(
  File('docs/phase10c-canonical-content.json').readAsStringSync(),
) as Map<String, dynamic>;
final phase10cCandidates = (phase10cModel['candidates'] as List)
    .cast<Map<String, dynamic>>();

/// Only temporary SQLite plus a query-only adapter. No remote client exists.
class Phase10CFixture {
  late Directory directory;
  late LocalDatabase database;
  late LocalDataSource local;
  late ProductTemplateResolver resolver;
  late ProductValidator validator;
  final templates = <String, ResolvedProductTemplate>{};

  Future<void> open() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('nubibill-phase10c-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    local = LocalDataSource(await database.open('phase10c', 'isolated'));
    final reader = ReadOnlyCatalogueService(local);
    resolver = ProductTemplateResolver(reader);
    validator = ProductValidator(reader);
    List<Map<String, dynamic>> docs(
      String collection,
      List<Map<String, dynamic>> rows,
      String key,
    ) => [
      for (final row in rows)
        {
          'name': '$collection/${row[key]}',
          'fields': FirestoreRestService.encodeFields({
            'status': 'ACTIVE',
            'scopeType': 'SYSTEM',
            ...row,
          }),
        },
    ];
    final unitNames = <String>{};
    for (final d in phase10cCandidates) {
      final rules = d['unitRules'] as Map;
      for (final key in [
        'allowedPackUnits',
        'allowedBaseUnits',
        'allowedSellingUnits',
      ]) {
        unitNames.addAll((rules[key] as List).cast<String>());
      }
    }
    await local.upsertRemote(
      'units',
      docs('units', [
        for (final name in unitNames.toList()..sort())
          {'unitId': unitId(name), 'name': name},
      ], 'unitId'),
    );
    await local.upsertRemote(
      'product_categories',
      docs('product_categories', [
        for (final id
            in phase10cCandidates.map((d) => d['categoryId'] as String).toSet())
          {
            'categoryId': id,
            'name': id,
            'businessTypeId': 'HARDWARE',
            'businessSubTypeId': 'PAINTS',
          },
      ], 'categoryId'),
    );
    await local.upsertRemote(
      'product_attributes',
      docs(
        'product_attributes',
        (phase10cModel['attributeDefinitions'] as List)
            .cast<Map<String, dynamic>>(),
        'attributeId',
      ),
    );
    await local.upsertRemote(
      'product_subcategories',
      docs('product_subcategories', [
        for (final d in phase10cCandidates)
          {
            'subcategoryId': d['canonicalId'],
            'categoryId': d['categoryId'],
            'name': d['name'],
            'templateSelectable':
                d['intendedSelectability'] == 'SELECTABLE_READY',
            'templateStatus': 'READY',
            'unitRules': d['unitRules'],
            'businessTypeId': 'HARDWARE',
            'businessSubTypeId': 'PAINTS',
          },
      ], 'subcategoryId'),
    );
    await local.upsertRemote(
      'subcategory_attribute_templates',
      docs('subcategory_attribute_templates', [
        for (final d in phase10cCandidates)
          for (final a in d['attributes'] as List)
            {
              ...Map<String, dynamic>.from(a as Map),
              'templateId': '${d['canonicalId']}-${a['attributeId']}',
              'subcategoryId': d['canonicalId'],
              'attributeLevel': (a['level'] as String).toUpperCase(),
              'businessTypeId': 'HARDWARE',
              'businessSubTypeId': 'PAINTS',
              'options': [for (final o in a['options'] as List) o['name']],
            },
      ], 'templateId'),
    );
  }

  static String unitId(String name) => 'UNIT_$name';

  Future<ResolvedProductTemplate> resolve(
    Map<String, dynamic> candidate,
  ) async {
    final id = candidate['canonicalId'] as String;
    return templates[id] ??= await resolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: id,
      categoryId: candidate['categoryId'] as String,
      token: 'ISOLATED_LOCAL_ONLY',
    );
  }

  Map<String, dynamic> state(
    ResolvedProductTemplate template, {
    ResolvedTemplateAttribute? selected,
    String? option,
    bool converting = false,
    bool omitColourMode = false,
  }) {
    final product = <String, dynamic>{};
    final variant = <String, dynamic>{};
    for (final a in template.allAttributes) {
      if (a.defaultValue != null) {
        (a.level == AttributeLevel.product ? product : variant)[a.attributeId] =
            a.defaultValue;
      }
    }
    if (omitColourMode) {
      product.remove('colourType');
    }
    if (selected != null) {
      final cond = selected.visibleWhen;
      if (cond != null) {
        product[cond['attributeId'] as String] = (cond['in'] as List).first;
      }
      (selected.level == AttributeLevel.product
              ? product
              : variant)[selected.attributeId] =
          option;
    }
    for (final a in template.allAttributes) {
      final target = a.level == AttributeLevel.product ? product : variant;
      if (!a.isVisible(product, variant, [variant])) {
        target.remove(a.attributeId);
      } else if (a.toProductAttribute().isRequired(
            target,
            a.level == AttributeLevel.variant ? product : null,
            [variant],
          ) &&
          (target[a.attributeId] == null || target[a.attributeId] == '')) {
        target[a.attributeId] = switch (a.dataType) {
          'NUMBER' => 2,
          'SELECT' => a.optionNames.first,
          'MULTI_SELECT' => [a.optionNames.first],
          'BOOLEAN' => true,
          _ => 'Example identity',
        };
      }
    }
    final rules = template.unitRules;
    final pack = variant['unit'] as String;
    final selling = variant['soldAs'] as String;
    final base = converting
        ? rules.defaultBaseUnit ?? rules.allowedBaseUnits.first
        : selling;
    return {
      'productFields': {
        'categoryId': template.categoryId,
        'subcategoryId': template.subcategoryId,
        'brandId': 'REPRESENTATIVE_BRAND',
        'hsnCode': '3208',
        'attributeValues': product,
      },
      'variants': <Map<String, dynamic>>[
        {
          'variantId': 'REPRESENTATIVE_VARIANT',
          'sku': 'REPRESENTATIVE_SKU',
          'barcode': 'REPRESENTATIVE_BARCODE',
          'packUnitId': unitId(pack),
          'commercialUnitId': unitId(selling),
          'baseUnitId': unitId(base),
          '_packaging': converting,
          'baseQuantityPerCommercialUnit': converting ? 2 : 1,
          'attributeValues': variant,
        },
      ],
    };
  }

  Future<ProductValidationResult> validate(Map<String, dynamic> state) =>
      validator.validateProduct(
        tenantId: 'T',
        businessId: 'B',
        productName: 'Representative Product',
        productFields: state['productFields'] as Map<String, dynamic>,
        variants: (state['variants'] as List).cast<Map<String, dynamic>>(),
        token: 'ISOLATED_LOCAL_ONLY',
      );

  Future<void> close() async {
    await database.close();
    await directory.delete(recursive: true);
  }
}
