import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../services/firestore_value_codec.dart';

/// Versioned wire/compiler contract. Data release numbers are independent of
/// schema/compiler compatibility. No record identity is derived from a label.
class CatalogueContract {
  static const schemaRevision = 1;
  static const compilerRevision = 6;
  static const legacyReleaseVersion = 3;
  static const requiredCollections = {
    'product_categories',
    'product_subcategories',
    'product_attributes',
    'product_attribute_options',
    'subcategory_attribute_templates',
    'units',
    'product_catalogue_releases',
  };
  static const idFields = {
    'product_categories': 'categoryId',
    'product_subcategories': 'subcategoryId',
    'product_attributes': 'attributeId',
    'product_attribute_options': 'optionId',
    'subcategory_attribute_templates': 'templateId',
    'units': 'unitId',
    'brands': 'brandId',
    'product_catalogue_releases': 'releaseId',
  };
  static const optionIds = {
    "soldAs": {
      "Can": "SYS_OPTION_V3_soldAs_Can",
      "Bucket": "SYS_OPTION_V3_soldAs_Bucket",
      "Bag": "SYS_OPTION_V3_soldAs_Bag",
      "Pouch": "SYS_OPTION_V3_soldAs_Pouch",
      "Piece": "SYS_OPTION_V3_soldAs_Piece",
      "Roll": "SYS_OPTION_V3_soldAs_Roll",
      "Cartridge": "SYS_OPTION_V3_soldAs_Cartridge",
      "Tube": "SYS_OPTION_V3_soldAs_Tube",
      "Bottle": "SYS_OPTION_V3_soldAs_Bottle",
      "Jar": "SYS_OPTION_V3_soldAs_Jar",
      "Drum": "SYS_OPTION_V3_soldAs_Drum",
      "Pack": "SYS_OPTION_V3_soldAs_Pack",
      "Box": "SYS_OPTION_V3_soldAs_Box",
      "Set": "SYS_OPTION_V3_soldAs_Set",
      "Sheet": "SYS_OPTION_V3_soldAs_Sheet",
      "Kilogram": "SYS_OPTION_V3_soldAs_Kilogram",
      "Litre": "SYS_OPTION_V3_soldAs_Litre",
    },
    "baseType": {
      "White Base": "SYS_OPTION_V3_baseType_White%20Base",
      "Pastel Base": "SYS_OPTION_V3_baseType_Pastel%20Base",
      "Deep Base": "SYS_OPTION_V3_baseType_Deep%20Base",
      "Accent Base": "SYS_OPTION_V3_baseType_Accent%20Base",
      "Neutral Base": "SYS_OPTION_V3_baseType_Neutral%20Base",
      "Clear Base": "SYS_OPTION_V3_baseType_Clear%20Base",
    },
    "bristleMaterial": {
      "Synthetic": "SYS_OPTION_V3_bristleMaterial_Synthetic",
      "Nylon": "SYS_OPTION_V3_bristleMaterial_Nylon",
      "Polyester": "SYS_OPTION_V3_bristleMaterial_Polyester",
      "Natural Bristle": "SYS_OPTION_V3_bristleMaterial_Natural%20Bristle",
      "Mixed Bristle": "SYS_OPTION_V3_bristleMaterial_Mixed%20Bristle",
    },
    "brushType": {
      "Flat": "SYS_OPTION_V3_brushType_Flat",
      "Angle": "SYS_OPTION_V3_brushType_Angle",
      "Round": "SYS_OPTION_V3_brushType_Round",
      "Wall Brush": "SYS_OPTION_V3_brushType_Wall%20Brush",
      "Varnish Brush": "SYS_OPTION_V3_brushType_Varnish%20Brush",
      "Utility Brush": "SYS_OPTION_V3_brushType_Utility%20Brush",
    },
    "colourFamily": {
      "White": "SYS_OPTION_V3_colourFamily_White",
      "Off White": "SYS_OPTION_V3_colourFamily_Off%20White",
      "Cream": "SYS_OPTION_V3_colourFamily_Cream",
      "Beige": "SYS_OPTION_V3_colourFamily_Beige",
      "Yellow": "SYS_OPTION_V3_colourFamily_Yellow",
      "Orange": "SYS_OPTION_V3_colourFamily_Orange",
      "Red": "SYS_OPTION_V3_colourFamily_Red",
      "Pink": "SYS_OPTION_V3_colourFamily_Pink",
      "Purple": "SYS_OPTION_V3_colourFamily_Purple",
      "Blue": "SYS_OPTION_V3_colourFamily_Blue",
      "Green": "SYS_OPTION_V3_colourFamily_Green",
      "Brown": "SYS_OPTION_V3_colourFamily_Brown",
      "Grey": "SYS_OPTION_V3_colourFamily_Grey",
      "Black": "SYS_OPTION_V3_colourFamily_Black",
      "Metallic": "SYS_OPTION_V3_colourFamily_Metallic",
      "Clear": "SYS_OPTION_V3_colourFamily_Clear",
      "Other": "SYS_OPTION_V3_colourFamily_Other",
    },
    "colourMode": {
      "Fixed Colour": "SYS_OPTION_V3_colourMode_Fixed%20Colour",
      "Multiple Ready Colours":
          "SYS_OPTION_V3_colourMode_Multiple%20Ready%20Colours",
      "Tintable Base": "SYS_OPTION_V3_colourMode_Tintable%20Base",
      "Clear / Transparent":
          "SYS_OPTION_V3_colourMode_Clear%20%2F%20Transparent",
      "Not Applicable": "SYS_OPTION_V3_colourMode_Not%20Applicable",
    },
    "colourType": {
      "Ready Colour": "SYS_OPTION_V3_colourType_Ready%20Colour",
      "Tintable Base": "SYS_OPTION_V3_colourType_Tintable%20Base",
      "Clear / Transparent":
          "SYS_OPTION_V3_colourType_Clear%20%2F%20Transparent",
      "Not Applicable": "SYS_OPTION_V3_colourType_Not%20Applicable",
    },
    "dilutionType": {
      "Water": "SYS_OPTION_V3_dilutionType_Water",
      "Mineral Turpentine / MTO":
          "SYS_OPTION_V3_dilutionType_Mineral%20Turpentine%20%2F%20MTO",
      "Paint Thinner": "SYS_OPTION_V3_dilutionType_Paint%20Thinner",
      "PU Thinner": "SYS_OPTION_V3_dilutionType_PU%20Thinner",
      "Epoxy Thinner": "SYS_OPTION_V3_dilutionType_Epoxy%20Thinner",
      "Manufacturer Recommended Thinner":
          "SYS_OPTION_V3_dilutionType_Manufacturer%20Recommended%20Thinner",
      "Ready to Use": "SYS_OPTION_V3_dilutionType_Ready%20to%20Use",
      "Two Component": "SYS_OPTION_V3_dilutionType_Two%20Component",
      "Not Applicable": "SYS_OPTION_V3_dilutionType_Not%20Applicable",
    },
    "finish": {
      "Flat": "SYS_OPTION_V3_finish_Flat",
      "Matt": "SYS_OPTION_V3_finish_Matt",
      "Rich Matt": "SYS_OPTION_V3_finish_Rich%20Matt",
      "Smooth Matt": "SYS_OPTION_V3_finish_Smooth%20Matt",
      "Satin": "SYS_OPTION_V3_finish_Satin",
      "Silk": "SYS_OPTION_V3_finish_Silk",
      "Sheen": "SYS_OPTION_V3_finish_Sheen",
      "High Sheen": "SYS_OPTION_V3_finish_High%20Sheen",
      "Semi Gloss": "SYS_OPTION_V3_finish_Semi%20Gloss",
      "Gloss": "SYS_OPTION_V3_finish_Gloss",
      "High Gloss": "SYS_OPTION_V3_finish_High%20Gloss",
      "Metallic": "SYS_OPTION_V3_finish_Metallic",
      "Textured": "SYS_OPTION_V3_finish_Textured",
      "Clear": "SYS_OPTION_V3_finish_Clear",
    },
    "grit": {
      "P60": "SYS_OPTION_V3_grit_P60",
      "P80": "SYS_OPTION_V3_grit_P80",
      "P100": "SYS_OPTION_V3_grit_P100",
      "P120": "SYS_OPTION_V3_grit_P120",
      "P150": "SYS_OPTION_V3_grit_P150",
      "P180": "SYS_OPTION_V3_grit_P180",
      "P220": "SYS_OPTION_V3_grit_P220",
      "P320": "SYS_OPTION_V3_grit_P320",
      "P400": "SYS_OPTION_V3_grit_P400",
    },
    "handleMaterial": {
      "Plastic": "SYS_OPTION_V3_handleMaterial_Plastic",
      "Wood": "SYS_OPTION_V3_handleMaterial_Wood",
      "Rubber Grip": "SYS_OPTION_V3_handleMaterial_Rubber%20Grip",
    },
    "numberOfCoats": {
      "1 Coat": "SYS_OPTION_V3_numberOfCoats_1%20Coat",
      "2 Coats": "SYS_OPTION_V3_numberOfCoats_2%20Coats",
      "3 Coats": "SYS_OPTION_V3_numberOfCoats_3%20Coats",
      "4 Coats": "SYS_OPTION_V3_numberOfCoats_4%20Coats",
      "As Required": "SYS_OPTION_V3_numberOfCoats_As%20Required",
      "Not Applicable": "SYS_OPTION_V3_numberOfCoats_Not%20Applicable",
    },
    "rollerMaterial": {
      "Polyester": "SYS_OPTION_V3_rollerMaterial_Polyester",
      "Microfibre": "SYS_OPTION_V3_rollerMaterial_Microfibre",
      "Foam": "SYS_OPTION_V3_rollerMaterial_Foam",
      "Mohair": "SYS_OPTION_V3_rollerMaterial_Mohair",
      "Wool Blend": "SYS_OPTION_V3_rollerMaterial_Wool%20Blend",
    },
    "rollerType": {
      "Foam": "SYS_OPTION_V3_rollerType_Foam",
      "Short Pile": "SYS_OPTION_V3_rollerType_Short%20Pile",
      "Medium Pile": "SYS_OPTION_V3_rollerType_Medium%20Pile",
      "Long Pile": "SYS_OPTION_V3_rollerType_Long%20Pile",
      "Radiator": "SYS_OPTION_V3_rollerType_Radiator",
      "Texture": "SYS_OPTION_V3_rollerType_Texture",
    },
    "segment": {
      "Economy": "SYS_OPTION_V3_segment_Economy",
      "Standard": "SYS_OPTION_V3_segment_Standard",
      "Premium": "SYS_OPTION_V3_segment_Premium",
      "Luxury": "SYS_OPTION_V3_segment_Luxury",
      "Super Luxury": "SYS_OPTION_V3_segment_Super%20Luxury",
    },
    "sizeUnit": {
      "inch": "SYS_OPTION_V3_sizeUnit_inch",
      "mm": "SYS_OPTION_V3_sizeUnit_mm",
      "cm": "SYS_OPTION_V3_sizeUnit_cm",
    },
    "surface": {
      "Wall": "SYS_OPTION_V3_surface_Wall",
      "Ceiling": "SYS_OPTION_V3_surface_Ceiling",
      "Wood": "SYS_OPTION_V3_surface_Wood",
      "Metal": "SYS_OPTION_V3_surface_Metal",
      "Concrete": "SYS_OPTION_V3_surface_Concrete",
      "Floor": "SYS_OPTION_V3_surface_Floor",
      "Roof": "SYS_OPTION_V3_surface_Roof",
      "Tile": "SYS_OPTION_V3_surface_Tile",
      "Stone": "SYS_OPTION_V3_surface_Stone",
      "GI": "SYS_OPTION_V3_surface_GI",
      "Pipe": "SYS_OPTION_V3_surface_Pipe",
      "Glass": "SYS_OPTION_V3_surface_Glass",
      "Plastic": "SYS_OPTION_V3_surface_Plastic",
    },
    "usage": {
      "Interior": "SYS_OPTION_V3_usage_Interior",
      "Exterior": "SYS_OPTION_V3_usage_Exterior",
      "Interior & Exterior": "SYS_OPTION_V3_usage_Interior%20%26%20Exterior",
      "Roof": "SYS_OPTION_V3_usage_Roof",
      "Floor": "SYS_OPTION_V3_usage_Floor",
      "Multi-Surface": "SYS_OPTION_V3_usage_Multi-Surface",
    },
  };
  static const unitIds = {
    "Litre": "SYS_UNIT_LITRE",
    "Millilitre": "SYS_UNIT_MILLILITRE",
    "Kilogram": "SYS_UNIT_KILOGRAM",
    "Gram": "SYS_UNIT_GRAM",
    "Piece": "SYS_UNIT_PIECE",
    "Pack": "SYS_UNIT_PACK",
    "Box": "SYS_UNIT_BOX",
    "Roll": "SYS_UNIT_ROLL",
    "Sheet": "SYS_UNIT_SHEET",
    "Set": "SYS_UNIT_SET",
    "Can": "SYS_UNIT_CAN",
    "Bucket": "SYS_UNIT_BUCKET",
    "Bag": "SYS_UNIT_BAG",
    "Cartridge": "SYS_UNIT_CARTRIDGE",
    "Tube": "SYS_UNIT_TUBE",
    "Pouch": "SYS_UNIT_POUCH",
    "Bottle": "SYS_UNIT_BOTTLE",
    "Jar": "SYS_UNIT_JAR",
    "Drum": "SYS_UNIT_DRUM",
    "inch": "SYS_UNIT_INCH",
    "mm": "SYS_UNIT_MM",
    "cm": "SYS_UNIT_CM",
    "Metre": "SYS_UNIT_METRE",
  };

  static Never fail(String message, [String code = 'catalogue-invalid']) =>
      throw AppException(message, code: code);

  static bool active(Map<String, dynamic> row) =>
      row['status'] == 'ACTIVE' && row['isDeleted'] != true;

  static int version(Map<String, dynamic> release) {
    final value =
        release['catalogueVersion'] ??
        release['releaseVersion'] ??
        release['version'];
    if (value is! num || value < 1 || value != value.toInt()) {
      fail('Invalid catalogue data release version.', 'catalogue-release');
    }
    return value.toInt();
  }

  static void validateRevision(Map<String, dynamic> release) {
    final declaredVersion = release['catalogueVersion'];
    final aliasVersion = release['version'];
    if (declaredVersion != null &&
        aliasVersion != null &&
        declaredVersion != aliasVersion) {
      fail(
        'Catalogue release version aliases do not agree.',
        'catalogue-revision',
      );
    }
    final schema = release['schemaRevision'] ?? schemaRevision;
    final compiler = release['compilerRevision'] ?? 0;
    if (compiler != 0 && !release.containsKey('schemaRevision')) {
      fail(
        'Compiled release must declare its schema revision.',
        'catalogue-revision',
      );
    }
    final revisions = release['collectionRevisions'];
    if (revisions != null &&
        (revisions is! Map ||
            revisions.values.any((v) => v is! int || v < 1))) {
      fail(
        'Collection revisions must be positive stable integers.',
        'catalogue-revision',
      );
    }
    if (revisions is Map &&
        version(release) >= 4 &&
        !requiredCollections.every(revisions.containsKey)) {
      fail(
        'Release manifest is missing a required collection revision.',
        'catalogue-revision',
      );
    }
    if (schema is! int ||
        compiler is! int ||
        schema != schemaRevision ||
        (compiler != 0 && compiler != compilerRevision)) {
      fail(
        'Unsupported catalogue schema/compiler revision: $schema/$compiler; supported $schemaRevision/$compilerRevision.',
        'catalogue-revision',
      );
    }
    if (compiler == 0 && version(release) != legacyReleaseVersion) {
      fail(
        'Only the declared legacy v3 manifest can be compiled without revision metadata.',
        'catalogue-revision',
      );
    }
  }

  static Map<String, List<Map<String, dynamic>>> decode(
    Map<String, List<Map<String, dynamic>>> documents,
  ) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final entry in documents.entries) {
      final field = idFields[entry.key];
      if (field == null) fail('Unsupported catalogue collection ${entry.key}.');
      final seen = <String>{};
      result[entry.key] = [];
      for (final doc in entry.value) {
        final name = doc['name'];
        if (name is! String ||
            name.split('/').length < 2 ||
            name.split('/').reversed.skip(1).first != entry.key) {
          fail('Invalid document name for ${entry.key}.');
        }
        final id = name.split('/').last;
        if (id.isEmpty || !seen.add(id)) {
          fail('Duplicate/empty document ID $name.');
        }
        final f = FirestoreValueCodec.decodeFields(doc['fields']);
        if (f['scopeType'] != 'SYSTEM') {
          fail('SYSTEM import contains BUSINESS or unscoped data.');
        }
        if ((f[field] != null && f[field] != id) ||
            (f['id'] != null && f['id'] != id)) {
          fail(
            'Document/payload identity mismatch: $name / ${f[field]}.',
            'catalogue-identity',
          );
        }
        result[entry.key]!.add({
          'id': id,
          ...f,
          field: id,
          if (doc['updateTime'] != null) '_remoteUpdateTime': doc['updateTime'],
        });
      }
      result[entry.key]!.sort(
        (a, b) => (a['id'] as String).compareTo(b['id'] as String),
      );
    }
    return result;
  }

  static dynamic orderedFields(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: orderedFields(value[k])};
    }
    if (value is List) return value.map(orderedFields).toList();
    return value;
  }

  static Map<String, List<Map<String, dynamic>>> encode(
    Map<String, List<Map<String, dynamic>>> rows,
  ) => {
    for (final entry
        in (rows.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
      entry.key: [
        for (final row
            in (entry.value.toList()..sort(
              (a, b) => (a['id'] as String).compareTo(b['id'] as String),
            )))
          {
            'name': '${entry.key}/${row['id']}',
            'fields': FirestoreValueCodec.encodeFields(
              Map<String, dynamic>.from(
                orderedFields(
                  Map<String, dynamic>.from(row)
                    ..remove('id')
                    ..remove('_remoteUpdateTime'),
                ) as Map,
              ),
            ),
            if (row['_remoteUpdateTime'] != null)
              'updateTime': row['_remoteUpdateTime'],
          },
      ],
  };

  static void validate(Map<String, List<Map<String, dynamic>>> rows) {
    Map<String, Map<String, dynamic>> index(String c) => {
      for (final r in rows[c] ?? <Map<String, dynamic>>[]) r['id'] as String: r,
    };
    final cats = index('product_categories'),
        subs = index('product_subcategories'),
        attrs = index('product_attributes');
    final duplicateKeys = <String>{};
    for (final entry in rows.entries) {
      final field = idFields[entry.key]!;
      final ids = <String>{};
      for (final r in entry.value) {
        if (r['id'] != r[field] || !ids.add(r['id'] as String)) {
          fail('Duplicate or mismatched ID in ${entry.key}.');
        }
        if (!active(r)) continue;
        String? key;
        if (entry.key == 'product_categories' ||
            entry.key == 'product_subcategories') {
          key =
              '${entry.key}:${r['catalogueId']}:${r['businessTypeId']}:${r['businessSubTypeId']}:${entry.key == 'product_subcategories' ? r['categoryId'] : ''}:${normalize(r['name'] ?? r['categoryName'] ?? r['subcategoryName'])}';
        } else if (entry.key == 'subcategory_attribute_templates') {
          key = 'template:${r['subcategoryId']}:${r['attributeId']}';
        } else if (entry.key == 'units') {
          key = 'unit:${normalize(r['name'])}';
        } else if (entry.key == 'product_attribute_options') {
          key = 'option:${r['attributeId']}:${normalize(r['name'])}';
        }
        if (key != null && !duplicateKeys.add(key)) {
          fail(
            'Ambiguous duplicate catalogue identity: $key.',
            'catalogue-collision',
          );
        }
        if (entry.key == 'product_subcategories' &&
            (!cats.containsKey(r['categoryId']) ||
                !active(cats[r['categoryId']]!))) {
          fail(
            'Active subcategory ${r['id']} has missing/inactive parent ${r['categoryId']}.',
          );
        }
        if (entry.key == 'product_attribute_options' &&
            (!attrs.containsKey(r['attributeId']) ||
                !active(attrs[r['attributeId']]!))) {
          fail('Option ${r['id']} references missing/inactive attribute.');
        }
      }
    }
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t
        in rows['subcategory_attribute_templates'] ??
            <Map<String, dynamic>>[]) {
      if (!active(t)) continue;
      final sub = subs[t['subcategoryId']], def = attrs[t['attributeId']];
      if (sub == null || !active(sub) || def == null || !active(def)) {
        fail('Active template ${t['id']} has invalid references.');
      }
      final level = t['attributeLevel'] ?? def['attributeLevel'];
      if (level != 'PRODUCT' && level != 'VARIANT') {
        fail('Template ${t['id']} has invalid attribute level.');
      }
      final type = t['dataType'] ?? def['dataType'] ?? 'TEXT';
      if (!const {
        'TEXT',
        'NUMBER',
        'SELECT',
        'MULTI_SELECT',
        'BOOLEAN',
        'DATE',
      }.contains(type)) {
        fail('Unknown attribute data type in ${t['id']}.');
      }
      final options = t['options'] ?? def['options'];
      final defaultValue = t['defaultValue'];
      if (defaultValue != null && type == 'NUMBER' && defaultValue is! num) {
        fail('Non-numeric default in ${t['id']}.');
      }
      if (defaultValue != null &&
          type == 'MULTI_SELECT' &&
          defaultValue is! List) {
        fail('Multi-select default must be a list in ${t['id']}.');
      }
      if (defaultValue is num &&
          t['minimumExclusive'] is num &&
          defaultValue <= t['minimumExclusive']) {
        fail('Default violates numeric minimum in ${t['id']}.');
      }
      if (options is List &&
          options.map(jsonEncode).toSet().length != options.length) {
        fail('Duplicate template options in ${t['id']}.');
      }
      if (options is List &&
          defaultValue != null &&
          (type == 'SELECT' || type == 'MULTI_SELECT')) {
        final values = defaultValue is List ? defaultValue : [defaultValue];
        if (values.any((v) => !options.contains(v))) {
          fail('Template ${t['id']} default is outside its options.');
        }
      }
      groups.putIfAbsent(t['subcategoryId'] as String, () => []).add(t);
    }
    for (final s in subs.values.where(active)) {
      final group = groups[s['id']] ?? [];
      if (group.isEmpty) {
        fail(
          'Active subcategory ${s['id']} has no template; explicit profile/rows required.',
          'catalogue-profile',
        );
      }
      final ids = group.map((r) => r['attributeId']).toSet();
      void conditions(dynamic value) {
        if (value is Map) {
          if (value['operator'] != null &&
              !const {'EQUALS', 'IN', 'NOT_IN'}.contains(value['operator'])) {
            fail('Unsupported condition operator in ${s['id']}.');
          }
          if (value.containsKey('attributeId') &&
              !ids.contains(value['attributeId'])) {
            fail(
              'Unknown condition attribute ${value['attributeId']} in ${s['id']}.',
            );
          }
          for (final v in value.values) {
            conditions(v);
          }
        } else if (value is List) {
          for (final v in value) {
            conditions(v);
          }
        }
      }

      for (final t in group) {
        for (final k in ['visibleWhen', 'requiredWhen', 'defaultRules']) {
          conditions(t[k]);
        }
      }
    }
  }

  static String normalize(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  static dynamic canonical(dynamic value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: canonical(value[k])};
    }
    if (value is List) {
      return value.map(canonical).toList()
        ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    }
    return value;
  }

  /// FNV-1a 64-bit logical content hash, for change detection, not authentication.
  static String fingerprint(Map<String, List<Map<String, dynamic>>> docs) {
    final rows = decode(docs);
    const ignore = {
      'createdAt',
      'updatedAt',
      'publishedAt',
      'createdBy',
      'updatedBy',
      '_remoteUpdateTime',
      'localMetadataRevision',
      'contentFingerprint',
      'catalogueFingerprint',
      'installedDocumentManifest',
      'installed',
    };
    final logical = {
      for (final e in rows.entries)
        e.key: [
          for (final r in e.value)
            {
              for (final f in r.entries)
                if (!ignore.contains(f.key)) f.key: f.value,
            },
        ],
    };
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one,
        prime = BigInt.parse('100000001b3', radix: 16);
    for (final byte in utf8.encode(jsonEncode(orderedFields(logical)))) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
