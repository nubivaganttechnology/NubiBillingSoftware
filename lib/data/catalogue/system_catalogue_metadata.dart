import 'dart:convert';

import '../../core/errors/app_exception.dart';
import 'catalogue_contract.dart';
import '../services/firestore_value_codec.dart';

/// Pure, versioned SYSTEM catalogue compiler. Defaults are generated only for
/// the declared legacy v3 manifest with explicit ID/profile context. Already
/// compiled releases keep their authoritative metadata and are validated only.
class SystemCatalogueMetadata {
  static const revision = CatalogueContract.compilerRevision;
  static const collections = {
    'product_catalogue_releases',
    'brands',
    'product_categories',
    'product_subcategories',
    'product_attributes',
    'product_attribute_options',
    'subcategory_attribute_templates',
    'units',
  };

  static String fingerprint(List<Map<String, dynamic>> documents) => jsonEncode(
    documents
        .map((doc) {
          final fields = FirestoreValueCodec.decodeFields(doc['fields']);
          return {
            'name': (doc['name'] as String).split('/').last,
            for (final key in [
              'catalogueId',
              'version',
              'catalogueVersion',
              'releaseVersion',
              'collectionRevisions',
              'status',
              'isActive',
              'published',
            ])
              key: CatalogueContract.canonical(fields[key]),
            'schemaRevision':
                fields['schemaRevision'] ?? CatalogueContract.schemaRevision,
            'compilerRevision': (fields['compilerRevision'] ?? 0) == 0
                ? revision
                : fields['compilerRevision'],
          };
        })
        .where(
          (r) =>
              r['status'] != 'INACTIVE' &&
              r['isActive'] != false &&
              r['published'] != false,
        )
        .toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b))),
  );

  static const colourTypes = [
    'Ready Colour',
    'Tintable Base',
    'Clear / Transparent',
    'Not Applicable',
  ];
  static const colourModes = [
    'Fixed Colour',
    'Multiple Ready Colours',
    'Tintable Base',
    'Clear / Transparent',
    'Not Applicable',
  ];
  static const soldAsOptions = [
    'Can',
    'Bucket',
    'Bag',
    'Pouch',
    'Piece',
    'Roll',
    'Cartridge',
    'Tube',
    'Bottle',
    'Jar',
    'Drum',
    'Pack',
    'Box',
    'Set',
    'Sheet',
    'Kilogram',
    'Litre',
  ];
  static const controlledOptions = <String, List<String>>{
    'colourType': colourTypes,
    'colourMode': colourModes,
    'soldAs': soldAsOptions,
    'baseType': [
      'White Base',
      'Pastel Base',
      'Deep Base',
      'Accent Base',
      'Neutral Base',
      'Clear Base',
    ],
    'finish': [
      'Flat',
      'Matt',
      'Rich Matt',
      'Smooth Matt',
      'Satin',
      'Silk',
      'Sheen',
      'High Sheen',
      'Semi Gloss',
      'Gloss',
      'High Gloss',
      'Metallic',
      'Textured',
      'Clear',
    ],
    'colourFamily': [
      'White',
      'Off White',
      'Cream',
      'Beige',
      'Yellow',
      'Orange',
      'Red',
      'Pink',
      'Purple',
      'Blue',
      'Green',
      'Brown',
      'Grey',
      'Black',
      'Metallic',
      'Clear',
      'Other',
    ],
    'numberOfCoats': [
      '1 Coat',
      '2 Coats',
      '3 Coats',
      '4 Coats',
      'As Required',
      'Not Applicable',
    ],
    'dilutionType': [
      'Water',
      'Mineral Turpentine / MTO',
      'Paint Thinner',
      'PU Thinner',
      'Epoxy Thinner',
      'Manufacturer Recommended Thinner',
      'Ready to Use',
      'Two Component',
      'Not Applicable',
    ],
    'segment': ['Economy', 'Standard', 'Premium', 'Luxury', 'Super Luxury'],
    'surface': [
      'Wall',
      'Ceiling',
      'Wood',
      'Metal',
      'Concrete',
      'Floor',
      'Roof',
      'Tile',
      'Stone',
      'GI',
      'Pipe',
      'Glass',
      'Plastic',
    ],
    'usage': [
      'Interior',
      'Exterior',
      'Interior & Exterior',
      'Roof',
      'Floor',
      'Multi-Surface',
    ],
    'brushType': [
      'Flat',
      'Angle',
      'Round',
      'Wall Brush',
      'Varnish Brush',
      'Utility Brush',
    ],
    'bristleMaterial': [
      'Synthetic',
      'Nylon',
      'Polyester',
      'Natural Bristle',
      'Mixed Bristle',
    ],
    'handleMaterial': ['Plastic', 'Wood', 'Rubber Grip'],
    'rollerType': [
      'Foam',
      'Short Pile',
      'Medium Pile',
      'Long Pile',
      'Radiator',
      'Texture',
    ],
    'rollerMaterial': [
      'Polyester',
      'Microfibre',
      'Foam',
      'Mohair',
      'Wool Blend',
    ],
    'grit': [
      'P60',
      'P80',
      'P100',
      'P120',
      'P150',
      'P180',
      'P220',
      'P320',
      'P400',
    ],
    'sizeUnit': ['inch', 'mm', 'cm'],
  };
  static const hints = {
    'colourType': 'Select colour type',
    'colourMode': 'Select colour availability',
    'productColour': 'e.g. White',
    'soldAs': 'Select how the item is packaged or sold',
    'baseType': 'Select the tinting base supplied by the manufacturer',
    'baseCode': 'e.g. W1',
    'finish': 'Select finish / sheen',
    'colourFamily': 'Select colour family',
    'numberOfCoats': 'Select recommended number of coats',
    'dilutionType': 'Select dilution / thinner type',
    'coverage': 'e.g. 120-140 sq.ft/L/coat',
    'dilutionRatio': 'e.g. 30-40% by volume',
    'dryingRecoatTime': 'e.g. 4-6 hours',
    'warranty': 'e.g. 5 years',
    'shelfLife': 'e.g. 36 months',
    'shade': 'e.g. Snow White',
    'shadeCode': 'e.g. 001',
    'packSize': 'e.g. 1, 4, 10 or 20',
    'brushType': 'Select brush type',
    'bristleMaterial': 'Select bristle material',
    'handleMaterial': 'Select handle material',
    'brushSize': 'e.g. 2',
    'style': 'e.g. Geometric, Floral, Textured',
    'rollLength': 'e.g. 10',
    'rollWidth': 'e.g. 0.53',
    'rollerType': 'Select roller type',
    'rollerMaterial': 'Select roller material',
    'rollerWidth': 'e.g. 9',
    'grit': 'e.g. 80, 120, 220',
    'width': 'e.g. 24',
    'length': 'e.g. 50',
    'segment': 'Select grade / tier',
    'mixingRatio': 'e.g. 1:1 or 4:1 by volume',
    'voc': 'e.g. < 50 g/L',
    'filmThickness': 'e.g. 100-150 microns',
    'dosage': 'e.g. 200 ml per bag of cement',
  };
  static const technical = {
    'coverage',
    'numberOfCoats',
    'dilutionType',
    'dilutionRatio',
    'dryingRecoatTime',
    'warranty',
    'shelfLife',
    'mixingRatio',
    'voc',
    'filmThickness',
    'dosage',
  };

  static const canonicalSubcategoryAliases = <String, String>{
    'SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES':
        'SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES',
    'SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS':
        'SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS',
    'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING':
        'SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING',
    'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY':
        'SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY',
    'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY':
        'SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY',
    'SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS':
        'SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS',
    'SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN':
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING',
    'SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL':
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING',
    'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS':
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT',
    'SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE':
        'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING',
  };

  static final reverseSubcategoryAliases = <String, String>{
    for (final e in canonicalSubcategoryAliases.entries) e.value: e.key,
  };

  static const legacyExplicitSubcategories = <String>{
    'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_STICKERS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_ACRYLIC_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_MULTI_SURFACE_EMULSIONS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_EXTERIOR_COATINGS_UNIVERSAL_EMULSIONS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_PAINTING_TOOLS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_GI_COATINGS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PIPE_GI_COATINGS_PIPE_COATINGS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_CEMENT_PRIMERS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EPOXY_PRIMERS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_GENERAL_PURPOSE_PRIMERS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_SEALERS_UNDERCOATS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_DESIGNER_DECORATIVE_FINISHES',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_GLITTER_METALLIC_ACCENTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_DESIGNER_TEXTURES',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_INTERIOR_TEXTURES',
    'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_STENCILS_WALL_ART',
  };

  static const redundantOptionIds = <String>{
    'SYS_OPT_brushType_1',
    'SYS_OPT_brushType_2',
    'SYS_OPT_brushType_3',
    'SYS_OPT_brushType_4',
    'SYS_OPT_brushType_5',
    'SYS_OPT_brushType_6',
    'SYS_OPT_bristleMaterial_1',
    'SYS_OPT_bristleMaterial_2',
    'SYS_OPT_bristleMaterial_3',
    'SYS_OPT_bristleMaterial_4',
    'SYS_OPT_bristleMaterial_5',
  };

  /// Pure compatibility compiler for the declared v3 manifest. Runtime imports
  /// call this before opening a SQLite transaction. Already compiled releases
  /// are validated and preserved, rather than regenerated from defaults.
  static Map<String, List<Map<String, dynamic>>> compile(
    Map<String, List<Map<String, dynamic>>> documents,
  ) {
    if (!CatalogueContract.requiredCollections.every(documents.containsKey)) {
      throw const AppException(
        'Incomplete compiler catalogue input.',
        code: 'catalogue-release',
      );
    }
    final raw = CatalogueContract.decode(documents);
    final releases = raw['product_catalogue_releases']!.where(
      (r) =>
          r['catalogueId'] == 'PAINT_V1' &&
          r['status'] == 'ACTIVE' &&
          r['published'] != false &&
          ((r['catalogueVersion'] ?? r['version'] ?? 0) as num) >=
              CatalogueContract.legacyReleaseVersion,
    );
    if (releases.isEmpty) {
      throw const AppException(
        'No supported PAINT_V1 release to compile.',
        code: 'catalogue-release',
      );
    }
    final release = releases.single;
    CatalogueContract.validateRevision(release);
    if ((release['compilerRevision'] ?? 0) == revision) {
      for (final sub in raw['product_subcategories']!.where(
        CatalogueContract.active,
      )) {
        if (_isLegacyDiyKitWithoutProfile(release, sub)) {
          _preserveLegacyDiyKitExclusion(sub);
          continue;
        }
        if (_isLegacyExplicitSubcategoryWithoutProfile(release, sub)) {
          _preserveLegacyExplicitSubcategory(sub);
          continue;
        }
        profileFor(
          sub['categoryId'].toString(),
          sub['subcategoryId'].toString(),
          explicit: sub['profileId']?.toString(),
        );
      }
      CatalogueContract.validate(raw);
      return CatalogueContract.encode(raw);
    }
    if ((release['compilerRevision'] ?? 0) != 0 ||
        (release['catalogueVersion'] ?? release['version']) !=
            CatalogueContract.legacyReleaseVersion) {
      throw const AppException(
        'Unsupported compatibility compiler revision.',
        code: 'catalogue-revision',
      );
    }
    if (raw.values
        .expand((rows) => rows)
        .any(
          (row) =>
              row['localMetadataRevision'] is num &&
              (row['localMetadataRevision'] as num) > 0,
        )) {
      throw const AppException(
        'Unversioned metadata already contains correction revisions; explicit reviewed compiler provenance is required.',
        code: 'catalogue-revision',
      );
    }
    final common = <String, dynamic>{
      'catalogueId': 'PAINT_V1',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
      'businessTypeId': 'HARDWARE',
      'businessSubTypeId': 'PAINTS',
      'version': CatalogueContract.legacyReleaseVersion,
      'localMetadataRevision': revision,
    };
    bool active(Map<String, dynamic> r) =>
        r['status'] == 'ACTIVE' && r['catalogueId'] == 'PAINT_V1';

    final categoriesList = raw['product_categories']!;
    final subcategoriesList = raw['product_subcategories']!;

    final obsoleteCategoryIds = {
      'SYS_CATEGORY_ACCESSORIES',
      'SYS_CATEGORY_EXTERIOR_WALL_PAINTS',
      'SYS_CATEGORY_FLOOR_COATINGS',
      'SYS_CATEGORY_INDUSTRIAL_COATINGS',
      'SYS_CATEGORY_INTERIOR_WALL_PAINTS',
      'SYS_CATEGORY_METAL_PAINTS',
      'SYS_CATEGORY_PRIMERS_PUTTY',
      'SYS_CATEGORY_WALLPAPERS',
      'SYS_CATEGORY_WOOD_COATINGS',
      'SYS_CATEGORY_WALL_TEXTURES',
    };
    for (final c in categoriesList) {
      if (obsoleteCategoryIds.contains(c['categoryId']) ||
          obsoleteCategoryIds.contains(c['id'])) {
        c['status'] = 'INACTIVE';
      }
    }
    for (final s in subcategoriesList) {
      if (obsoleteCategoryIds.contains(s['categoryId'])) {
        s['status'] = 'INACTIVE';
      }
    }

    final canonicalCategories = <String, Map<String, dynamic>>{
      'SYS_CATEGORY_INTERIOR_WALL_COATINGS': {
        'name': 'Interior Wall Coatings',
        'aliases': ['Interior Wall Paints'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS',
            'name': 'Premium Interior Emulsions',
            'aliases': ['Premium Interior Emulsion', 'Interior Emulsion'],
          },
          {
            'id': 'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS',
            'name': 'Economy Interior Paints',
            'aliases': ['Economy Interior Paint', 'Distemper'],
          },
          {
            'id':
                'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_LUXURY_INTERIOR_PAINTS',
            'name': 'Luxury Interior Paints',
            'aliases': ['Luxury Paints', 'Luxury Emulsion'],
          },
        ],
      },
      'SYS_CATEGORY_EXTERIOR_WALL_COATINGS': {
        'name': 'Exterior Wall Coatings',
        'aliases': ['Exterior Wall Paints'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_EXTERIOR_EMULSION',
            'name': 'Exterior Emulsion',
            'aliases': ['Exterior Wall Emulsion'],
          },
          {
            'id': 'SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_PREMIUM_EXTERIOR_PAINTS',
            'name': 'Premium Exterior Paints',
            'aliases': ['Premium Exterior Paint'],
          },
          {
            'id': 'SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_ECONOMY_EXTERIOR_PAINTS',
            'name': 'Economy Exterior Paints',
            'aliases': ['Economy Exterior Paint'],
          },
          {
            'id': 'SYS_SUBCATEGORY_EXTERIOR_WALL_COATINGS_WEATHER_RESISTANT_PAINTS',
            'name': 'Weather Resistant Paints',
            'aliases': ['Weather Proof Paints'],
          },
        ],
      },
      'SYS_CATEGORY_PRIMERS_UNDERCOATS': {
        'name': 'Primers & Undercoats',
        'aliases': ['Primers', 'Primers & Putty'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS',
            'name': 'Interior Wall Primers',
            'aliases': ['Interior Wall Primer', 'Interior Primers'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS',
            'name': 'Exterior Wall Primers',
            'aliases': ['Exterior Wall Primer', 'Exterior Primers'],
          },
          {
            'id':
                'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS',
            'name': 'Metal Primers',
            'aliases': ['Metal Primer', 'Metal Primers & Undercoats'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS',
            'name': 'Anti-Corrosive Metal Primers',
            'aliases': ['Anti-Corrosion Metal Primer', 'Anti Corrosive Primer'],
          },
          {
            'id':
                'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS',
            'name': 'Wood Primers',
            'aliases': ['Wood Primer'],
          },
        ],
      },
      'SYS_CATEGORY_PUTTY_SURFACE_PREPARATION': {
        'name': 'Putty & Surface Preparation',
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WALL_PUTTY',
            'name': 'Wall Putty',
            'aliases': ['White Cement Wall Putty', 'Cement Putty'],
          },
          {
            'id': 'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY',
            'name': 'Waterproof Wall Putty',
            'aliases': ['Waterproof Putty'],
          },
          {
            'id': 'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY',
            'name': 'Acrylic Putty',
            'aliases': ['Acrylic Wall Putty'],
          },
        ],
      },
      'SYS_CATEGORY_WATERPROOFING': {
        'name': 'Waterproofing',
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE',
            'name': 'Roof & Terrace Waterproofing',
            'aliases': ['Terrace Waterproofing', 'Roof Waterproofing'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL',
            'name': 'Exterior Wall Waterproofing',
            'aliases': ['Wall Waterproofing'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS',
            'name': 'Interior Dampness Treatment',
            'aliases': ['Damp Proofing', 'Dampness Treatment'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN',
            'name': 'Bathroom & Kitchen Waterproofing',
            'aliases': ['Bathroom Waterproofing'],
          },
        ],
      },
      'SYS_CATEGORY_WOOD_FINISHES': {
        'name': 'Wood Finishes',
        'aliases': ['Wood Coatings'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_POLISH',
            'name': 'Wood Polish',
            'aliases': ['Polish', 'French Polish'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WOOD_FINISHES_PU_WOOD_FINISH',
            'name': 'PU Wood Finish',
            'aliases': ['PU Coating', 'Polyurethane Wood Finish'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WOOD_FINISHES_MELAMINE',
            'name': 'Melamine Wood Finish',
            'aliases': ['Melamine', 'Melamine Coating'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WOOD_FINISHES_WOOD_SEALER',
            'name': 'Wood Sealer',
            'aliases': ['Sealer'],
          },
        ],
      },
      'SYS_CATEGORY_METAL_WOOD_ENAMELS': {
        'name': 'Metal & Wood Enamels',
        'aliases': ['Metal Paints', 'Enamels'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ENAMEL_PAINT',
            'name': 'Enamel Paint',
            'aliases': ['Gloss Enamel', 'Synthetic Enamel'],
          },
          {
            'id': 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_DECORATIVE_METAL_PAINT',
            'name': 'Decorative Metal Paint',
            'aliases': ['Metal Paint'],
          },
          {
            'id': 'SYS_SUBCATEGORY_METAL_WOOD_ENAMELS_ANTI_CORROSION_PAINT',
            'name': 'Anti-Corrosion Paint',
            'aliases': ['Anti-Rust Paint'],
          },
        ],
      },
      'SYS_CATEGORY_FLOOR_TILE_COATINGS': {
        'name': 'Floor & Tile Coatings',
        'aliases': ['Floor Coatings'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING',
            'name': 'Epoxy Flooring',
            'aliases': ['Epoxy Floor Coating'],
          },
          {
            'id': 'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_FLOOR_PAINT',
            'name': 'Floor Paint',
            'aliases': ['Floor Coating'],
          },
          {
            'id': 'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_CONCRETE_COATING',
            'name': 'Concrete Coating',
            'aliases': ['Concrete Floor Coating'],
          },
        ],
      },
      'SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS': {
        'name': 'Protective & Industrial Coatings',
        'aliases': ['Industrial Coatings'],
        'subcategories': [
          {
            'id':
                'SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ANTI_CORROSION',
            'name': 'Anti-Corrosion Coating',
            'aliases': ['Anti Corrosion'],
          },
          {
            'id': 'SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_EPOXY',
            'name': 'Epoxy Coating',
            'aliases': ['Industrial Epoxy'],
          },
          {
            'id':
                'SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_HEAT_RESISTANT',
            'name': 'Heat Resistant Coating',
            'aliases': ['Heat Resistant Paint'],
          },
          {
            'id': 'SYS_SUBCATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_PROTECTIVE',
            'name': 'Protective Coating',
            'aliases': ['Protective Industrial Coating'],
          },
        ],
      },
      'SYS_CATEGORY_ADHESIVES_TILING': {
        'name': 'Adhesives & Tiling',
        'aliases': ['Adhesives', 'Tiling Solution'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES',
            'name': 'Tile Adhesives',
            'aliases': ['Tile Adhesive', 'Tile Glue'],
          },
          {
            'id': 'SYS_SUBCATEGORY_ADHESIVES_TILING_GROUT',
            'name': 'Grout & Joint Fillers',
            'aliases': ['Tile Grout', 'Joint Filler'],
          },
        ],
      },
      'SYS_CATEGORY_SEALANTS_REPAIR': {
        'name': 'Sealants & Repair',
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_SILICONE_SEALANTS',
            'name': 'Silicone Sealants',
            'aliases': ['Silicone Sealant', 'Silicone'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS',
            'name': 'Acrylic Sealants',
            'aliases': ['Acrylic Sealant', 'Gap Filler'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SEALANTS_REPAIR_PU_SEALANTS',
            'name': 'Polyurethane Sealants',
            'aliases': ['PU Sealant'],
          },
        ],
      },
      'SYS_CATEGORY_ADMIXTURES': {
        'name': 'Admixtures',
        'aliases': ['Admixture'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_ADMIXTURES_WATERPROOFING',
            'name': 'Waterproofing Admixtures',
            'aliases': ['Integral Waterproofing Compound'],
          },
          {
            'id': 'SYS_SUBCATEGORY_ADMIXTURES_PLASTICIZERS',
            'name': 'Plasticizers & Retarders',
            'aliases': ['Concrete Plasticizer'],
          },
        ],
      },
      'SYS_CATEGORY_WALL_COVERINGS': {
        'name': 'Wall Coverings',
        'aliases': ['Wallpapers'],
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_COVERINGS_WALLPAPERS',
            'name': 'Wallpapers',
            'aliases': ['Wallpaper'],
          },
          {
            'id': 'SYS_SUBCATEGORY_WALL_COVERINGS_DESIGNER_WALLPAPER',
            'name': 'Designer Wallpaper',
            'aliases': ['Vinyl Wallpaper', 'Paper Wallpaper'],
          },
        ],
      },
      'SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES': {
        'name': 'Painting Tools & Accessories',
        'aliases': ['Accessories'],
        'subcategories': [
          {
            'id':
                'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH',
            'name': 'Brush',
            'aliases': ['Paint Brush'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER',
            'name': 'Roller',
            'aliases': ['Paint Roller'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES',
            'name': 'Sandpaper & Abrasives',
            'aliases': ['Sandpaper', 'Abrasives'],
          },
          {
            'id': 'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE',
            'name': 'Masking Tape',
            'aliases': ['Painter Tape'],
          },
        ],
      },
      'SYS_CATEGORY_ALLIED_PRODUCTS': {
        'name': 'Allied Products',
        'subcategories': [
          {
            'id': 'SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS',
            'name': 'Thinners',
            'aliases': ['Paint Thinner', 'Solvents'],
          },
        ],
      },
    };

    for (final entry in canonicalCategories.entries) {
      final catId = entry.key;
      final catData = entry.value;
      final catName = catData['name'] as String;
      final catAliases = (catData['aliases'] as List<String>? ?? []);
      var existingCat = categoriesList
          .where((c) => c['categoryId'] == catId || c['id'] == catId)
          .firstOrNull;
      if (existingCat != null) {
        existingCat['status'] = 'ACTIVE';
        existingCat['categoryId'] = catId;
        existingCat['name'] = catName;
        existingCat['categoryName'] = catName;
      } else {
        categoriesList.add({
          ...common,
          'id': catId,
          'categoryId': catId,
          'name': catName,
          'categoryName': catName,
          'aliases': catAliases,
        });
      }

      for (final subData
          in (catData['subcategories'] as List<Map<String, dynamic>>)) {
        final subId = subData['id'] as String;
        final subName = subData['name'] as String;
        final subAliases = (subData['aliases'] as List<String>? ?? []);
        final aliasId = canonicalSubcategoryAliases[subId] ??
            reverseSubcategoryAliases[subId];
        var existingSub = subcategoriesList
            .where((s) =>
                s['subcategoryId'] == subId ||
                s['id'] == subId ||
                (aliasId != null &&
                    (s['subcategoryId'] == aliasId || s['id'] == aliasId)))
            .firstOrNull;
        if (existingSub != null) {
          if (existingSub['categoryId'] != catId) {
            throw AppException(
              'Canonical subcategory $subId has conflicting parent metadata.',
              code: 'catalogue-profile',
            );
          }
          existingSub['status'] = 'ACTIVE';
          // Preserve persisted Firestore ID (do not mutate with subId)
          existingSub['categoryId'] = catId;
          existingSub['name'] = subName;
          existingSub['subcategoryName'] = subName;
        } else {
          subcategoriesList.add({
            ...common,
            'id': subId,
            'subcategoryId': subId,
            'categoryId': catId,
            'name': subName,
            'subcategoryName': subName,
            'aliases': subAliases,
          });
        }
      }
    }

    final attributes = raw['product_attributes']!;
    for (final pair in {
      'colourType': 'Colour Type',
      'baseCode': 'Base Code',
      'colourMode': 'Colour Availability',
      'productColour': 'Product Colour',
      'soldAs': 'Sold As',
      'segment': 'Grade / Tier',
      'style': 'Style / Pattern',
      'rollerType': 'Roller Type',
      'rollerMaterial': 'Roller Material',
      'rollerWidth': 'Roller Width',
      'grit': 'Grit',
      'width': 'Width',
      'length': 'Length',
      'rollLength': 'Roll Length',
      'rollWidth': 'Roll Width',
      'brushSize': 'Brush Size',
      'dimensionUnit': 'Dimension Unit',
      'sizeUnit': 'Size Unit',
    }.entries) {
      for (final a in attributes.where((a) => a['attributeId'] == pair.key)) {
        a['status'] = 'ACTIVE';
        a['version'] = CatalogueContract.legacyReleaseVersion;
        a['localMetadataRevision'] = revision;
      }
      if (!attributes.any((a) => a['attributeId'] == pair.key)) {
        final isProduct = {
          'colourMode',
          'productColour',
          'segment',
          'style',
          'rollerType',
          'rollerMaterial',
        }.contains(pair.key);
        final isSelect = {
          'colourType',
          'colourMode',
          'soldAs',
          'segment',
          'rollerType',
          'rollerMaterial',
          'grit',
          'sizeUnit',
          'dimensionUnit',
        }.contains(pair.key);
        final isNumber = {
          'brushSize',
          'rollerWidth',
          'width',
          'length',
          'rollLength',
          'rollWidth',
        }.contains(pair.key);
        attributes.add({
          ...common,
          'id': pair.key,
          'attributeId': pair.key,
          'name': pair.value,
          'dataType': isSelect ? 'SELECT' : (isNumber ? 'NUMBER' : 'TEXT'),
          'attributeLevel': isProduct ? 'PRODUCT' : 'VARIANT',
          if (pair.key == 'soldAs') 'semanticRole': 'SELLING_UNIT',
        });
      }
    }

    for (final a in attributes.where(active)) {
      final id = a['attributeId'];
      a['section'] = technical.contains(id) ? 'TECHNICAL' : 'ESSENTIAL';
      if (hints.containsKey(id)) a['hintText'] = hints[id];
      if (controlledOptions.containsKey(id)) {
        a['dataType'] = id == 'surface' ? 'MULTI_SELECT' : 'SELECT';
        a['options'] = controlledOptions[id];
      }
      if (id == 'colourType' ||
          id == 'colourMode' ||
          id == 'numberOfCoats' ||
          id == 'soldAs' ||
          id == 'segment') {
        a['allowAddNewOption'] = false;
      }
      if (id == 'segment') a['name'] = 'Grade / Tier';
      if (id == 'style') a['name'] = 'Style / Pattern';
      if (id == 'shade') a['name'] = 'Shade / Colour';
      if (id == 'numberOfCoats') a['name'] = 'Recommended Coats';
      if (id == 'dilutionType') a['name'] = 'Dilution / Thinner Type';
      if (id == 'colourMode') a['name'] = 'Colour Availability';
      if (id == 'productColour') a['name'] = 'Product Colour';
      if (id == 'soldAs') {
        a['name'] = 'Sold As';
        a['semanticRole'] = 'SELLING_UNIT';
      }
      if (id == 'packSize') {
        a['semanticRole'] = 'PACK_SIZE';
        a['minimumExclusive'] = 0;
      }
    }

    final options = raw['product_attribute_options']!;
    for (final o in options.where(active)) {
      final allowed = controlledOptions[o['attributeId']];
      if (allowed != null) {
        final label = allowed
            .where(
              (name) =>
                  CatalogueContract.normalize(name) ==
                  CatalogueContract.normalize(o['name']),
            )
            .firstOrNull;
        if (label == null) {
          o['status'] = 'INACTIVE';
        } else {
          // Formatting is metadata, not a new option identity.
          o['name'] = label;
          o['normalizedName'] = label.toLowerCase();
        }
      }
    }
    for (final entry in controlledOptions.entries) {
      for (final name in entry.value) {
        if (options.any(
          (o) =>
              active(o) && o['attributeId'] == entry.key && o['name'] == name,
        )) {
          continue;
        }
        final id = CatalogueContract.optionIds[entry.key]![name]!;
        options.add({
          ...common,
          'id': id,
          'optionId': id,
          'attributeId': entry.key,
          'name': name,
          'normalizedName': name.toLowerCase(),
        });
      }
    }

    final units = raw['units']!;
    for (final name in [
      'Litre',
      'Millilitre',
      'Kilogram',
      'Gram',
      'Piece',
      'Pack',
      'Box',
      'Roll',
      'Sheet',
      'Set',
      'Can',
      'Bucket',
      'Bag',
      'Cartridge',
      'Tube',
      'Pouch',
      'Bottle',
      'Jar',
      'Drum',
      'inch',
      'mm',
      'cm',
      'Metre',
    ]) {
      if (units.any(
        (u) =>
            active(u) &&
            (u['id'] == CatalogueContract.unitIds[name] ||
                CatalogueContract.normalize(u['name']) ==
                    CatalogueContract.normalize(name)),
      )) {
        continue;
      }
      final id = CatalogueContract.unitIds[name]!;
      units.add({
        ...common,
        'id': id,
        'unitId': id,
        'name': name,
        'unitName': name,
        'normalizedName': name.toLowerCase(),
      });
    }
    for (final u in units.where(active)) {
      final declared = CatalogueContract.unitIds.entries
          .where((e) => e.value == u['id'])
          .firstOrNull;
      if (declared != null) {
        u['name'] = declared.key;
        u['unitName'] = declared.key;
        u['normalizedName'] = declared.key.toLowerCase();
      }
      if (['inch', 'mm', 'cm', 'Metre'].contains(u['name'])) {
        u['measurementDimension'] = 'LENGTH';
      }
    }

    final subcategories = {
      for (final s in raw['product_subcategories']!.where(active))
        s['subcategoryId']: s,
    };
    final templates = raw['subcategory_attribute_templates']!;

    for (final sub in subcategories.values) {
      // The legacy PAINT_V1 v3 DIY Kits document has no compiler profile.
      // Historical installed-state evidence shows it was excluded from
      // product selection. Keep it excluded without inventing a profile or
      // templateStatus; the v3 default applies only to this exact row.
      if (_isLegacyDiyKitWithoutProfile(release, sub)) {
        _preserveLegacyDiyKitExclusion(sub);
        continue;
      }
      if (_isLegacyExplicitSubcategoryWithoutProfile(release, sub)) {
        _preserveLegacyExplicitSubcategory(sub);
        continue;
      }
      final rows = templates
          .where((t) => active(t) && t['subcategoryId'] == sub['subcategoryId'])
          .toList();

      final profile = _resolveProfile(
        categoryId: sub['categoryId']?.toString() ?? '',

        subcategoryId: sub['subcategoryId']?.toString() ?? '',
        profileId: sub['profileId']?.toString(),
      );

      sub['profileId'] = profileFor(
        sub['categoryId'].toString(),
        sub['subcategoryId'].toString(),
        explicit: sub['profileId']?.toString(),
      );
      sub['templateStatus'] = 'READY';
      final applicableIds = {
        ...profile.productFields,
        ...profile.variantFields,
        ...profile.technicalFields,
      };

      for (final t in templates.where(
        (t) =>
            t['subcategoryId'] == sub['subcategoryId'] &&
            !applicableIds.contains(t['attributeId']),
      )) {
        t['status'] = 'INACTIVE';
      }
      rows.removeWhere((t) => !applicableIds.contains(t['attributeId']));

      for (final id in applicableIds) {
        if (!rows.any((r) => r['attributeId'] == id)) {
          final isVariant = profile.variantFields.contains(id);
          final isTechnical = profile.technicalFields.contains(id);
          final tid = 'SYS_TEMPLATE_V3_${sub['subcategoryId']}_$id';
          final row = {
            ...common,
            'id': tid,
            'templateId': tid,
            'subcategoryId': sub['subcategoryId'],
            'attributeId': id,
            'attributeLevel': isVariant ? 'VARIANT' : 'PRODUCT',
            'section':
                profile.sectionOverrides[id] ??
                (isTechnical ? 'TECHNICAL' : 'ESSENTIAL'),
            'sortOrder': _sortOrder(id, isVariant, isTechnical),
            'required': _isRequiredByDefault(id),
          };
          rows.add(row);
          templates.add(row);
        }
      }

      for (final t in rows) {
        final id = t['attributeId'] as String;
        final isVariant = profile.variantFields.contains(id);
        final isTechnical = profile.technicalFields.contains(id);

        t['attributeLevel'] = id == 'productColour'
            ? 'PRODUCT'
            : (isVariant ? 'VARIANT' : 'PRODUCT');
        t['section'] =
            profile.sectionOverrides[id] ??
            (isTechnical ? 'TECHNICAL' : 'ESSENTIAL');
        t['sortOrder'] = _sortOrder(id, isVariant, isTechnical);

        if (profile.defaults.containsKey(id)) {
          t['defaultValue'] = profile.defaults[id];
        }

        if (profile.optionsOverrides.containsKey(id)) {
          t['options'] = profile.optionsOverrides[id];
        }

        if (id == 'unit') {
          t['options'] = profile.allowedUnits;
          t['defaultValue'] =
              profile.defaults['unit'] ?? profile.allowedUnits.first;
          t['semanticRole'] = applicableIds.contains('packSize')
              ? 'PACK_UNIT'
              : 'SELLING_UNIT';
          t['name'] = applicableIds.contains('soldAs')
              ? 'Pack Unit'
              : (applicableIds.contains('packSize') ? 'Pack Unit' : 'Sold As');
          t['allowAddNewOption'] = false;
          t['required'] = true;
        }

        if (id == 'soldAs') {
          t['options'] = profile.allowedSoldAs;
          t['defaultValue'] =
              profile.defaults['soldAs'] ?? profile.allowedSoldAs.first;
          t['semanticRole'] = 'SELLING_UNIT';
          t['name'] = 'Sold As';
          t['allowAddNewOption'] = false;
          t['required'] = true;
        }

        if (id == 'packSize') {
          t['semanticRole'] = 'PACK_SIZE';
          t['minimumExclusive'] = 0;
          t['required'] = true;
        }

        if (id == 'colourMode') {
          t['options'] = colourModes;
          t['defaultValue'] =
              profile.defaults['colourMode'] ?? 'Multiple Ready Colours';
          t['required'] = true;
        }

        if (id == 'colourType') {
          t['options'] = colourTypes;
          t['defaultValue'] = profile.defaults['colourType'] ?? 'Ready Colour';
          t['required'] = true;
          t['defaultRules'] = [
            {'attributeId': 'shade', 'value': 'Ready Colour'},
            {'attributeId': 'baseType', 'value': 'Tintable Base'},
          ];
        }

        if (id == 'productColour') {
          t['defaultValue'] = profile.defaults['productColour'] ?? 'White';
          t['visibleWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Fixed Colour'],
          };
          t['requiredWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Fixed Colour'],
          };
          t['required'] = false;
        }

        if (['shade', 'colourFamily'].contains(id)) {
          t['visibleWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Multiple Ready Colours', 'Ready Colour'],
          };
          t['requiredWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Multiple Ready Colours', 'Ready Colour'],
          };
          t['required'] = false;
        }

        if (id == 'shadeCode') {
          t['visibleWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Multiple Ready Colours', 'Ready Colour'],
          };
          t['required'] = false;
        }

        if (id == 'baseType') {
          t['visibleWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Tintable', 'Tintable Base'],
          };
          t['requiredWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Tintable', 'Tintable Base'],
          };
          t['required'] = false;
        }

        if (id == 'baseCode') {
          t['visibleWhen'] = {
            'attributeId': 'colourMode',
            'in': ['Tintable', 'Tintable Base'],
          };
          t['required'] = false;
        }

        if (['brushSize', 'rollerWidth'].contains(id)) {
          t['measurementUnitAttributeId'] = 'sizeUnit';
          t['measurementDimension'] = 'LENGTH';
          t['minimumExclusive'] = 0;
          t['required'] = true;
        }

        if (['rollLength', 'rollWidth', 'width', 'length'].contains(id)) {
          t['measurementUnitAttributeId'] =
              applicableIds.contains('dimensionUnit')
              ? 'dimensionUnit'
              : 'sizeUnit';
          t['measurementDimension'] = 'LENGTH';
          t['minimumExclusive'] = 0;
          t['required'] = true;
        }

        if (id == 'sizeUnit') {
          t['options'] = ['inch', 'mm', 'cm'];
          t['defaultValue'] = profile.defaults['sizeUnit'] ?? 'inch';
          t['measurementDimension'] = 'LENGTH';
          t['required'] = true;
        }

        if (id == 'dimensionUnit') {
          t['options'] = ['Metre', 'cm', 'mm'];
          t['defaultValue'] = 'Metre';
          t['measurementDimension'] = 'LENGTH';
          t['required'] = true;
        }

        if (id == 'numberOfCoats') {
          t['options'] = controlledOptions['numberOfCoats'];
        }

        if (id == 'dilutionType') {
          t['options'] = controlledOptions['dilutionType'];
        }
      }
    }

    release['schemaRevision'] = CatalogueContract.schemaRevision;
    release['compilerRevision'] = revision;
    release['sourceCompilerRevision'] = 0;
    for (final rows in raw.values) {
      for (final row in rows) {
        row['localMetadataRevision'] = revision;
      }
    }
    CatalogueContract.validate(raw);
    return CatalogueContract.encode(raw);
  }

  static bool _isLegacyDiyKitWithoutProfile(
    Map<String, dynamic> release,
    Map<String, dynamic> subcategory,
  ) =>
      CatalogueContract.version(release) ==
          CatalogueContract.legacyReleaseVersion &&
      subcategory['catalogueId'] == 'PAINT_V1' &&
      subcategory['scopeType'] == 'SYSTEM' &&
      subcategory['status'] == 'ACTIVE' &&
      subcategory['version'] == 2 &&
      subcategory['subcategoryId'] ==
          'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS' &&
      subcategory['categoryId'] == 'SYS_CATEGORY_DIY_AEROSOLS' &&
      !subcategory.containsKey('profileId') &&
      ((subcategory['templateSelectable'] == false &&
              (!subcategory.containsKey('templateStatus') ||
                  subcategory['templateStatus'] == 'READY')) ||
          (!subcategory.containsKey('templateSelectable') &&
              !subcategory.containsKey('templateStatus')));

  static void _preserveLegacyDiyKitExclusion(
    Map<String, dynamic> subcategory,
  ) {
    // This is derived compatibility metadata, not a remote document edit.
    // Do not overwrite any explicit source value or invent a status value.
    subcategory.putIfAbsent('templateSelectable', () => false);
  }

  static bool _isLegacyExplicitSubcategoryWithoutProfile(
    Map<String, dynamic> release,
    Map<String, dynamic> subcategory,
  ) =>
      CatalogueContract.version(release) ==
          CatalogueContract.legacyReleaseVersion &&
      subcategory['catalogueId'] == 'PAINT_V1' &&
      subcategory['scopeType'] == 'SYSTEM' &&
      subcategory['status'] == 'ACTIVE' &&
      legacyExplicitSubcategories.contains(subcategory['subcategoryId']) &&
      (!subcategory.containsKey('profileId') ||
          subcategory['profileId'] == null ||
          subcategory['profileId'] == 'EXPLICIT_METADATA');

  static void _preserveLegacyExplicitSubcategory(
    Map<String, dynamic> subcategory,
  ) {
    subcategory['profileId'] = 'EXPLICIT_METADATA';
    subcategory.putIfAbsent('templateStatus', () => 'READY');
    subcategory.putIfAbsent('templateSelectable', () => false);
  }

  static bool _isRequiredByDefault(String id) => [
    'packSize',
    'unit',
    'soldAs',
    'brushSize',
    'sizeUnit',
    'rollerWidth',
    'grit',
    'width',
    'length',
    'rollLength',
    'rollWidth',
    'dimensionUnit',
    'colourMode',
    'colourType',
  ].contains(id);

  static int _sortOrder(String id, bool isVariant, bool isTechnical) {
    if (isTechnical) {
      const order = [
        'coverage',
        'mixingRatio',
        'dilutionRatio',
        'dryingRecoatTime',
        'filmThickness',
        'dosage',
        'warranty',
        'shelfLife',
        'voc',
      ];
      final idx = order.indexOf(id);
      return idx >= 0 ? 100 + idx : 150;
    }
    if (isVariant) {
      const order = [
        'finish',
        'colourType',
        'colourMode',
        'shade',
        'shadeCode',
        'colourFamily',
        'baseType',
        'baseCode',
        'brushSize',
        'rollerWidth',
        'sizeUnit',
        'grit',
        'width',
        'length',
        'rollLength',
        'rollWidth',
        'dimensionUnit',
        'packSize',
        'unit',
        'soldAs',
      ];
      final idx = order.indexOf(id);
      return idx >= 0 ? 50 + idx : 90;
    }
    const order = [
      'usage',
      'surface',
      'segment',
      'style',
      'brushType',
      'bristleMaterial',
      'handleMaterial',
      'rollerType',
      'rollerMaterial',
      'colourMode',
      'productColour',
      'numberOfCoats',
      'dilutionType',
    ];
    final idx = order.indexOf(id);
    return idx >= 0 ? 1 + idx : 30;
  }

  /// Stable semantic profile identifiers. Display names never select chemistry.
  static String profileFor(
    String categoryId,
    String subcategoryId, {
    String? explicit,
  }) {
    const families = {
      'SYS_CATEGORY_INTERIOR_WALL_COATINGS': 'INTERIOR_COATING',
      'SYS_CATEGORY_EXTERIOR_WALL_COATINGS': 'EXTERIOR_COATING',
      'SYS_CATEGORY_WOOD_FINISHES': 'WOOD_FINISH',
      'SYS_CATEGORY_METAL_WOOD_ENAMELS': 'ENAMEL',
      'SYS_CATEGORY_FLOOR_TILE_COATINGS': 'FLOOR_COATING',
      'SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS': 'PROTECTIVE_COATING',
      'SYS_CATEGORY_ADHESIVES_TILING': 'ADHESIVE',
      'SYS_CATEGORY_SEALANTS_REPAIR': 'SEALANT',
      'SYS_CATEGORY_ADMIXTURES': 'ADMIXTURE',
      'SYS_CATEGORY_WALL_COVERINGS': 'WALL_COVERING',
      'SYS_CATEGORY_ALLIED_PRODUCTS': 'THINNER',
      'SYS_CATEGORY_PUTTY_SURFACE_PREPARATION': 'PUTTY',
      'SYS_CATEGORY_WATERPROOFING': 'WATERPROOFING',
    };
    const specific = {
      // DIY Kits is deliberately not inferred here. The available installed
      // audit and isolated v4 review disagree on its selectability; a published
      // snapshot must carry an explicit profile until that data is approved.
      'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS':
          'SATIN_ENAMEL',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH': 'BRUSH',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_ROLLER':
          'ROLLER',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES':
          'ABRASIVE',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_MASKING_TAPE':
          'MASKING_TAPE',
      'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY':
          'WATERPROOF_PUTTY',
      'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY':
          'ACRYLIC_PUTTY',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS':
          'WALL_PRIMER',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_EXTERIOR_WALL_PRIMERS':
          'EXTERIOR_PRIMER',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_METAL_PRIMERS':
          'METAL_PRIMER',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_ANTI_CORROSIVE_METAL_PRIMERS':
          'METAL_PRIMER',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_WOOD_PRIMERS':
          'WOOD_PRIMER',
      'SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE': 'ROOF_WATERPROOFING',
      'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS':
          'INTERIOR_WATERPROOFING',
      'SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN':
          'WET_AREA_WATERPROOFING',
    };
    final known = {
      'EXPLICIT_METADATA',
      'SATIN_ENAMEL',
      'BRUSH',
      'ROLLER',
      'ABRASIVE',
      'MASKING_TAPE',
      'WATERPROOF_PUTTY',
      'ACRYLIC_PUTTY',
      'PUTTY',
      'WALL_PRIMER',
      'EXTERIOR_PRIMER',
      'METAL_PRIMER',
      'WOOD_PRIMER',
      'WATERPROOFING',
      'WET_AREA_WATERPROOFING',
      'ROOF_WATERPROOFING',
      'INTERIOR_WATERPROOFING',
      ...families.values,
    };
    final resolvedSubcategoryId = canonicalSubcategoryAliases[subcategoryId] ??
        reverseSubcategoryAliases[subcategoryId] ??
        subcategoryId;
    final intended = specific[subcategoryId] ??
        specific[resolvedSubcategoryId] ??
        families[categoryId];
    if (explicit != null &&
        (!known.contains(explicit) ||
            (explicit != 'EXPLICIT_METADATA' &&
                intended != null &&
                intended != explicit))) {
      throw AppException(
        'Unknown or conflicting catalogue profile $explicit for $subcategoryId.',
        code: 'catalogue-profile',
      );
    }
    final result = explicit ?? intended;
    if (result == null) {
      throw AppException(
        'Explicit profile required for $subcategoryId under $categoryId.',
        code: 'catalogue-profile',
      );
    }
    return result;
  }

  static _ProfileConfig _resolveProfile({
    required String categoryId,
    required String subcategoryId,
    String? profileId,
  }) {
    final profile = profileFor(categoryId, subcategoryId, explicit: profileId);

    // 14. Painting Tools & Accessories
    if (const {
      'BRUSH',
      'ROLLER',
      'ABRASIVE',
      'MASKING_TAPE',
    }.contains(profile)) {
      if (profile == 'BRUSH') {
        return const _ProfileConfig(
          productFields: [
            'brushType',
            'bristleMaterial',
            'handleMaterial',
            'surface',
          ],
          variantFields: ['brushSize', 'sizeUnit', 'unit', 'soldAs'],
          technicalFields: [],
          defaults: {'sizeUnit': 'inch', 'unit': 'Piece', 'soldAs': 'Piece'},
          allowedUnits: ['Piece', 'Pack', 'Box', 'Set'],
          allowedSoldAs: ['Piece', 'Pack', 'Box', 'Set'],
          optionsOverrides: {
            'surface': [
              'Wall',
              'Wood',
              'Metal',
              'Ceiling',
              'Floor',
              'Concrete',
            ],
          },
        );
      } else if (profile == 'ROLLER') {
        return const _ProfileConfig(
          productFields: ['rollerType', 'rollerMaterial'],
          variantFields: ['rollerWidth', 'sizeUnit', 'unit', 'soldAs'],
          technicalFields: [],
          defaults: {'sizeUnit': 'inch', 'unit': 'Piece', 'soldAs': 'Piece'},
          allowedUnits: ['Piece', 'Pack', 'Box', 'Set'],
          allowedSoldAs: ['Piece', 'Pack', 'Box', 'Set'],
        );
      } else if (profile == 'ABRASIVE') {
        return const _ProfileConfig(
          productFields: [],
          variantFields: ['grit', 'unit', 'soldAs'],
          technicalFields: [],
          defaults: {'unit': 'Sheet', 'soldAs': 'Sheet'},
          allowedUnits: ['Sheet', 'Pack', 'Roll', 'Box'],
          allowedSoldAs: ['Sheet', 'Pack', 'Roll', 'Box'],
        );
      } else if (profile == 'MASKING_TAPE') {
        return const _ProfileConfig(
          productFields: [],
          variantFields: ['width', 'length', 'sizeUnit', 'unit', 'soldAs'],
          technicalFields: [],
          defaults: {'sizeUnit': 'mm', 'unit': 'Roll', 'soldAs': 'Roll'},
          allowedUnits: ['Roll', 'Pack', 'Box'],
          allowedSoldAs: ['Roll', 'Pack', 'Box'],
        );
      }
    }

    // 15. Allied Products (Thinners)
    if (profile == 'THINNER') {
      return const _ProfileConfig(
        productFields: [],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: ['shelfLife', 'voc'],
        defaults: {'unit': 'Litre', 'soldAs': 'Can'},
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Bottle', 'Drum'],
        allowedSoldAs: ['Can', 'Bottle', 'Drum', 'Litre'],
      );
    }

    // 13. Wall Coverings
    if (profile == 'WALL_COVERING') {
      return const _ProfileConfig(
        productFields: ['style'],
        variantFields: [
          'rollLength',
          'rollWidth',
          'dimensionUnit',
          'unit',
          'soldAs',
        ],
        technicalFields: [],
        defaults: {'dimensionUnit': 'Metre', 'unit': 'Roll', 'soldAs': 'Roll'},
        allowedUnits: ['Roll', 'Sheet'],
        allowedSoldAs: ['Roll', 'Sheet'],
      );
    }

    // 4. Putty & Surface Preparation
    if (const {
      'PUTTY',
      'WATERPROOF_PUTTY',
      'ACRYLIC_PUTTY',
    }.contains(profile)) {
      final isWaterproof = profile == 'WATERPROOF_PUTTY';
      final isAcrylic = profile == 'ACRYLIC_PUTTY';
      return _ProfileConfig(
        productFields: ['usage', 'surface', 'colourMode', 'productColour'],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: ['coverage', 'dryingRecoatTime', 'shelfLife'],
        defaults: {
          'usage': isWaterproof ? 'Interior & Exterior' : 'Interior',
          'surface': ['Wall'],
          'colourMode': 'Fixed Colour',
          'productColour': 'White',
          'unit': 'Kilogram',
          'soldAs': isAcrylic ? 'Bucket' : 'Bag',
        },
        allowedUnits: ['Kilogram', 'Gram', 'Bag'],
        allowedSoldAs: ['Bag', 'Pouch', 'Bucket', 'Kilogram'],
        optionsOverrides: {
          'surface': isWaterproof
              ? ['Wall', 'Concrete']
              : ['Wall', 'Ceiling', 'Concrete'],
        },
        hasColourMode: true,
      );
    }

    // 3. Primers & Undercoats
    if (const {
      'WALL_PRIMER',
      'EXTERIOR_PRIMER',
      'METAL_PRIMER',
      'WOOD_PRIMER',
    }.contains(profile)) {
      final isMetal = profile == 'METAL_PRIMER';
      final isWood = profile == 'WOOD_PRIMER';
      final isExterior = profile == 'EXTERIOR_PRIMER';
      return _ProfileConfig(
        productFields: [
          'usage',
          'surface',
          'colourMode',
          'productColour',
          'numberOfCoats',
          'dilutionType',
        ],
        variantFields: [
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
        ],
        technicalFields: [
          'coverage',
          'dilutionRatio',
          'dryingRecoatTime',
          'shelfLife',
        ],
        sectionOverrides: {
          'numberOfCoats': 'ESSENTIAL',
          'dilutionType': 'ESSENTIAL',
        },
        defaults: {
          'usage': (isMetal || isWood)
              ? 'Interior & Exterior'
              : (isExterior ? 'Exterior' : 'Interior'),
          'surface': isMetal ? ['Metal'] : (isWood ? ['Wood'] : ['Wall']),
          'colourMode': 'Fixed Colour',
          'productColour': isMetal ? 'Red Oxide' : 'White',
          'numberOfCoats': (isMetal || isWood) ? '1 Coat' : '2 Coats',
          'dilutionType': (isMetal || isWood)
              ? 'Mineral Turpentine / MTO'
              : 'Water',
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: [
          'Litre',
          'Millilitre',
          'Can',
          'Bucket',
          'Drum',
          'Kilogram',
        ],
        allowedSoldAs: ['Can', 'Bucket', 'Drum', 'Bottle', 'Jar', 'Litre'],
        optionsOverrides: {
          'surface': isMetal
              ? ['Metal', 'GI', 'Pipe']
              : (isWood
                    ? ['Wood']
                    : (isExterior
                          ? ['Wall', 'Concrete']
                          : ['Wall', 'Ceiling'])),
        },
        hasColourMode: true,
      );
    }

    // 5. Waterproofing
    if (const {
      'WATERPROOFING',
      'WET_AREA_WATERPROOFING',
      'ROOF_WATERPROOFING',
      'INTERIOR_WATERPROOFING',
    }.contains(profile)) {
      final isBathroom = profile == 'WET_AREA_WATERPROOFING';
      final isRoof = profile == 'ROOF_WATERPROOFING';
      final isInterior = profile == 'INTERIOR_WATERPROOFING' || isBathroom;
      return _ProfileConfig(
        productFields: ['usage', 'surface', 'numberOfCoats', 'dilutionType'],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: [
          'coverage',
          'mixingRatio',
          'dilutionRatio',
          'dryingRecoatTime',
          'warranty',
          'shelfLife',
          'voc',
        ],
        defaults: {
          'usage': isInterior ? 'Interior' : 'Exterior',
          'surface': isBathroom
              ? ['Wall', 'Floor']
              : (isRoof ? ['Roof'] : ['Wall']),
          'numberOfCoats': '2 Coats',
          'dilutionType': 'Water',
          'unit': isBathroom ? 'Kilogram' : 'Litre',
          'soldAs': isBathroom ? 'Bag' : 'Bucket',
        },
        allowedUnits: [
          'Litre',
          'Millilitre',
          'Kilogram',
          'Bucket',
          'Can',
          'Bag',
          'Drum',
        ],
        allowedSoldAs: ['Bucket', 'Can', 'Bag', 'Drum', 'Litre', 'Kilogram'],
        optionsOverrides: {
          'surface': isBathroom
              ? ['Wall', 'Floor', 'Concrete']
              : (isRoof ? ['Roof', 'Concrete'] : ['Wall', 'Concrete']),
        },
      );
    }

    // 6. Wood Finishes
    if (profile == 'WOOD_FINISH') {
      return const _ProfileConfig(
        productFields: ['usage', 'surface', 'numberOfCoats', 'dilutionType'],
        variantFields: [
          'finish',
          'colourMode',
          'colourType',
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
          'productColour',
        ],
        technicalFields: [
          'coverage',
          'mixingRatio',
          'dilutionRatio',
          'dryingRecoatTime',
          'shelfLife',
        ],
        defaults: {
          'usage': 'Interior & Exterior',
          'surface': ['Wood'],
          'numberOfCoats': '2 Coats',
          'dilutionType': 'PU Thinner',
          'finish': 'Gloss',
          'colourMode': 'Clear / Transparent',
          'colourType': 'Clear / Transparent',
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Bottle', 'Jar', 'Drum'],
        allowedSoldAs: ['Can', 'Bottle', 'Litre'],
        optionsOverrides: {
          'surface': ['Wood'],
        },
        hasColourMode: true,
        hasColourType: true,
      );
    }

    // 7. Metal & Wood Enamels
    if (profile == 'ENAMEL' || profile == 'SATIN_ENAMEL') {
      return _ProfileConfig(
        productFields: ['usage', 'surface', 'numberOfCoats', 'dilutionType'],
        variantFields: [
          'finish',
          'colourMode',
          'colourType',
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
          'productColour',
        ],
        technicalFields: [
          'coverage',
          'dilutionRatio',
          'dryingRecoatTime',
          'shelfLife',
        ],
        defaults: {
          'usage': 'Interior & Exterior',
          'surface': ['Metal', 'Wood'],
          'numberOfCoats': '2 Coats',
          'dilutionType': 'Mineral Turpentine / MTO',
          'finish': profile == 'SATIN_ENAMEL' ? 'Satin' : 'Gloss',
          'colourMode': 'Multiple Ready Colours',
          'colourType': 'Ready Colour',
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Drum', 'Bucket'],
        allowedSoldAs: ['Can', 'Drum', 'Litre'],
        optionsOverrides: {
          'surface': ['Metal', 'Wood', 'GI', 'Pipe'],
        },
        hasColourMode: true,
        hasColourType: true,
      );
    }

    // 8. Floor & Tile Coatings
    if (profile == 'FLOOR_COATING') {
      return const _ProfileConfig(
        productFields: ['usage', 'surface', 'numberOfCoats', 'dilutionType'],
        variantFields: [
          'finish',
          'colourMode',
          'colourType',
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
          'productColour',
        ],
        technicalFields: [
          'coverage',
          'mixingRatio',
          'dryingRecoatTime',
          'filmThickness',
        ],
        defaults: {
          'usage': 'Floor',
          'surface': ['Floor'],
          'numberOfCoats': '2 Coats',
          'dilutionType': 'Epoxy Thinner',
          'finish': 'Gloss',
          'colourMode': 'Multiple Ready Colours',
          'colourType': 'Ready Colour',
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Bucket', 'Drum', 'Set'],
        allowedSoldAs: ['Can', 'Bucket', 'Set', 'Litre'],
        optionsOverrides: {
          'surface': ['Floor', 'Tile', 'Concrete'],
        },
        hasColourMode: true,
        hasColourType: true,
      );
    }

    // 9. Protective & Industrial Coatings
    if (profile == 'PROTECTIVE_COATING') {
      return const _ProfileConfig(
        productFields: ['surface', 'numberOfCoats', 'dilutionType'],
        variantFields: [
          'finish',
          'colourMode',
          'colourType',
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
          'productColour',
        ],
        technicalFields: [
          'coverage',
          'mixingRatio',
          'voc',
          'filmThickness',
          'dryingRecoatTime',
        ],
        defaults: {
          'surface': ['Metal', 'Concrete'],
          'numberOfCoats': '2 Coats',
          'dilutionType': 'Epoxy Thinner',
          'finish': 'Semi Gloss',
          'colourMode': 'Multiple Ready Colours',
          'colourType': 'Ready Colour',
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Drum', 'Set'],
        allowedSoldAs: ['Can', 'Drum', 'Set', 'Litre'],
        optionsOverrides: {
          'surface': ['Metal', 'Concrete', 'GI', 'Pipe'],
        },
        hasColourMode: true,
        hasColourType: true,
      );
    }

    // 10. Adhesives & Tiling
    if (profile == 'ADHESIVE') {
      return const _ProfileConfig(
        productFields: ['surface'],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: ['coverage', 'mixingRatio', 'dryingRecoatTime'],
        defaults: {
          'surface': ['Tile', 'Stone', 'Concrete'],
          'unit': 'Kilogram',
          'soldAs': 'Bag',
        },
        allowedUnits: ['Kilogram', 'Gram', 'Bag', 'Pouch', 'Bucket'],
        allowedSoldAs: ['Bag', 'Pouch', 'Can', 'Bucket', 'Kilogram'],
        optionsOverrides: {
          'surface': ['Tile', 'Stone', 'Concrete'],
        },
      );
    }

    // 11. Sealants & Repair
    if (profile == 'SEALANT') {
      return const _ProfileConfig(
        productFields: ['surface'],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: ['mixingRatio', 'dryingRecoatTime', 'voc'],
        defaults: {
          'surface': ['Concrete', 'Metal', 'Glass', 'Tile'],
          'unit': 'Cartridge',
          'soldAs': 'Cartridge',
        },
        allowedUnits: ['Cartridge', 'Tube', 'Pouch', 'Kilogram', 'Litre'],
        allowedSoldAs: [
          'Cartridge',
          'Tube',
          'Pouch',
          'Bottle',
          'Jar',
          'Kilogram',
          'Litre',
        ],
        optionsOverrides: {
          'surface': ['Concrete', 'Metal', 'Glass', 'Tile', 'Plastic'],
        },
      );
    }

    // 12. Admixtures
    if (profile == 'ADMIXTURE') {
      return const _ProfileConfig(
        productFields: ['surface'],
        variantFields: ['packSize', 'unit', 'soldAs'],
        technicalFields: ['dosage', 'mixingRatio', 'shelfLife'],
        defaults: {
          'surface': ['Concrete'],
          'unit': 'Litre',
          'soldAs': 'Can',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Drum', 'Bottle'],
        allowedSoldAs: ['Can', 'Drum', 'Bottle', 'Litre'],
        optionsOverrides: {
          'surface': ['Concrete'],
        },
      );
    }

    // 2. Exterior Wall Coatings
    if (profile == 'EXTERIOR_COATING') {
      return const _ProfileConfig(
        productFields: [
          'usage',
          'surface',
          'segment',
          'numberOfCoats',
          'dilutionType',
        ],
        variantFields: [
          'finish',
          'colourMode',
          'colourType',
          'packSize',
          'unit',
          'soldAs',
          'shade',
          'shadeCode',
          'colourFamily',
          'baseType',
          'baseCode',
          'productColour',
        ],
        technicalFields: [
          'coverage',
          'dilutionRatio',
          'dryingRecoatTime',
          'warranty',
          'shelfLife',
        ],
        defaults: {
          'usage': 'Exterior',
          'surface': ['Wall'],
          'numberOfCoats': '2 Coats',
          'dilutionType': 'Water',
          'unit': 'Litre',
          'soldAs': 'Can',
          'colourMode': 'Multiple Ready Colours',
          'colourType': 'Ready Colour',
        },
        allowedUnits: ['Litre', 'Millilitre', 'Can', 'Bucket', 'Drum'],
        allowedSoldAs: ['Can', 'Bucket', 'Drum', 'Litre'],
        optionsOverrides: {
          'surface': ['Wall', 'Roof', 'Concrete'],
        },
        hasColourMode: true,
        hasColourType: true,
      );
    }

    if (profile != 'INTERIOR_COATING') {
      throw AppException(
        'Unsupported catalogue profile $profile for $subcategoryId.',
        code: 'catalogue-profile',
      );
    }
    // 1. Explicit Interior Wall Coatings
    return const _ProfileConfig(
      productFields: [
        'usage',
        'surface',
        'segment',
        'numberOfCoats',
        'dilutionType',
      ],
      variantFields: [
        'finish',
        'colourMode',
        'colourType',
        'packSize',
        'unit',
        'soldAs',
        'shade',
        'shadeCode',
        'colourFamily',
        'baseType',
        'baseCode',
        'productColour',
      ],
      technicalFields: [
        'coverage',
        'dilutionRatio',
        'dryingRecoatTime',
        'warranty',
        'shelfLife',
      ],
      defaults: {
        'usage': 'Interior',
        'surface': ['Wall'],
        'numberOfCoats': '2 Coats',
        'dilutionType': 'Water',
        'unit': 'Litre',
        'soldAs': 'Can',
        'colourMode': 'Multiple Ready Colours',
        'colourType': 'Ready Colour',
      },
      allowedUnits: ['Litre', 'Millilitre', 'Can', 'Bucket', 'Drum'],
      allowedSoldAs: ['Can', 'Bucket', 'Drum', 'Litre'],
      optionsOverrides: {
        'surface': ['Wall', 'Ceiling'],
      },
      hasColourMode: true,
      hasColourType: true,
    );
  }
}

class _ProfileConfig {
  final List<String> productFields;
  final List<String> variantFields;
  final List<String> technicalFields;
  final Map<String, dynamic> defaults;
  final List<String> allowedUnits;
  final List<String> allowedSoldAs;
  final Map<String, String> sectionOverrides;
  final Map<String, List<String>> optionsOverrides;
  final bool hasColourMode;
  final bool hasColourType;

  const _ProfileConfig({
    required this.productFields,
    required this.variantFields,
    required this.technicalFields,
    required this.defaults,
    required this.allowedUnits,
    required this.allowedSoldAs,
    this.sectionOverrides = const {},
    this.optionsOverrides = const {},
    this.hasColourMode = false,
    this.hasColourType = false,
  });
}
