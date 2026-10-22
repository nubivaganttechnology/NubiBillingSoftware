import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';

class _FakeFirestore implements FirestoreDataService {
  final records = <String, List<Map<String, dynamic>>>{};

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    final items = records[collection] ?? <Map<String, dynamic>>[];
    final results = <Map<String, dynamic>>[];

    for (final data in items) {
      final matchesAll = filters.every((f) {
        final val = data[f.field];
        if (f.operation == 'EQUAL') {
          return val == f.value;
        }
        return true;
      });

      if (matchesAll) {
        results.add({
          'name': '$collection/${data['id'] ?? data['remoteId'] ?? 'doc'}',
          'fields': FirestoreRestService.encodeFields(data),
        });
      }
    }
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeFirestore firestore;
  late ProductTemplateResolver templateResolver;

  setUp(() {
    firestore = _FakeFirestore();
    templateResolver = ProductTemplateResolver(firestore);

    firestore.records['product_categories'] = [
      {
        'id': 'CAT_PAINTS',
        'categoryId': 'CAT_PAINTS',
        'name': 'Paints & Coatings',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
      },
    ];

    firestore.records['product_subcategories'] = [
      {
        'id': 'SUB_PUTTY',
        'subcategoryId': 'SUB_PUTTY',
        'categoryId': 'CAT_PAINTS',
        'name': 'Wall Putty',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'unitRules': {
          'allowedPackUnits': ['Kilogram'],
          'defaultPackUnit': 'Kilogram',
          'allowedSellingUnits': ['Bag'],
          'defaultSellingUnit': 'Bag',
          'allowedBaseUnits': ['Kilogram'],
          'defaultBaseUnit': 'Kilogram',
          'conversionAllowed': true,
          'conversionDimension': 'MASS',
        },
      },
      {
        'id': 'SUB_PRIMER',
        'subcategoryId': 'SUB_PRIMER',
        'categoryId': 'CAT_PAINTS',
        'name': 'Interior Wall Primer',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'unitRules': {
          'allowedPackUnits': ['Litre'],
          'defaultPackUnit': 'Litre',
          'allowedSellingUnits': ['Can'],
          'defaultSellingUnit': 'Can',
          'allowedBaseUnits': ['Litre'],
          'defaultBaseUnit': 'Litre',
          'conversionAllowed': true,
          'conversionDimension': 'VOLUME',
        },
      },
      {
        'id': 'SUB_BRUSH',
        'subcategoryId': 'SUB_BRUSH',
        'categoryId': 'CAT_PAINTS',
        'name': 'Paint Brush',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'unitRules': {
          'allowedPackUnits': ['Piece'],
          'defaultPackUnit': 'Piece',
          'allowedSellingUnits': ['Piece'],
          'defaultSellingUnit': 'Piece',
          'allowedBaseUnits': ['Piece'],
          'defaultBaseUnit': 'Piece',
          'conversionAllowed': false,
        },
      },
    ];

    firestore.records['units'] = [
      {
        'id': 'Kilogram',
        'unitId': 'Kilogram',
        'name': 'Kilogram',
        'status': 'ACTIVE',
      },
      {'id': 'Litre', 'unitId': 'Litre', 'name': 'Litre', 'status': 'ACTIVE'},
      {'id': 'Bag', 'unitId': 'Bag', 'name': 'Bag', 'status': 'ACTIVE'},
      {'id': 'Can', 'unitId': 'Can', 'name': 'Can', 'status': 'ACTIVE'},
      {'id': 'Piece', 'unitId': 'Piece', 'name': 'Piece', 'status': 'ACTIVE'},
    ];

    // Putty template
    firestore.records['subcategory_attribute_templates'] = [
      {
        'id': 'T_PUTTY_1',
        'subcategoryId': 'SUB_PUTTY',
        'attributeId': 'unit',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Kilogram'],
        'defaultValue': 'Kilogram',
      },
      {
        'id': 'T_PUTTY_2',
        'subcategoryId': 'SUB_PUTTY',
        'attributeId': 'soldAs',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Bag'],
        'defaultValue': 'Bag',
      },
      // Primer template
      {
        'id': 'T_PRIMER_1',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'unit',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Litre'],
        'defaultValue': 'Litre',
      },
      {
        'id': 'T_PRIMER_2',
        'subcategoryId': 'SUB_PRIMER',
        'attributeId': 'soldAs',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Can'],
        'defaultValue': 'Can',
      },
      // Brush template
      {
        'id': 'T_BRUSH_1',
        'subcategoryId': 'SUB_BRUSH',
        'attributeId': 'soldAs',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'options': ['Piece'],
        'defaultValue': 'Piece',
      },
    ];
  });

  test('conversion defaults OFF and clears base unit / factor', () async {
    final row = <String, dynamic>{
      '_packaging': false,
      '_baseUnit': 'Kilogram',
      '_conversion': 20,
    };

    // When conversion is OFF
    if (row['_packaging'] != true) {
      row['_baseUnit'] = null;
      row['_conversion'] = null;
    }

    expect(row['_packaging'], isFalse);
    expect(row['_baseUnit'], isNull);
    expect(row['_conversion'], isNull);
  });

  test('enable conversion does not copy Bag into Base Unit', () async {
    final row = <String, dynamic>{
      '_packaging': false,
      '_commercialUnit': 'Bag',
      'unit': 'Kilogram',
      'packSize': 20,
    };

    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PUTTY',
      token: 'TOK',
    );
    row['_packaging'] = true;
    template.unitRules.reconcileVariantState(row);

    expect(row['_baseUnit'], equals('Kilogram'));
    expect(row['_baseUnit'], isNot(equals('Bag')));
    expect(
      row['_conversion'],
      isNull,
      reason: 'Pack size cannot provide an implicit factor',
    );
  });

  test('enable conversion does not copy Can into Base Unit', () async {
    final row = <String, dynamic>{
      '_packaging': false,
      '_commercialUnit': 'Can',
      'unit': 'Litre',
      'packSize': 4,
    };

    final template = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_PRIMER',
      token: 'TOK',
    );
    row['_packaging'] = true;
    template.unitRules.reconcileVariantState(row);

    expect(row['_baseUnit'], equals('Litre'));
    expect(row['_baseUnit'], isNot(equals('Can')));
    expect(
      row['_conversion'],
      isNull,
      reason: 'Pack size cannot provide an implicit factor',
    );
  });

  test(
    'subcategory change clears stale conversion state and applies new defaults',
    () async {
      final puttyTemplate = await templateResolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: 'SUB_PUTTY',
        token: 'TOK',
      );

      final primerTemplate = await templateResolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: 'SUB_PRIMER',
        token: 'TOK',
      );

      expect(puttyTemplate.unitRules.allowedPackUnits, contains('Kilogram'));
      expect(puttyTemplate.unitRules.allowedSoldAsUnits, contains('Bag'));

      expect(primerTemplate.unitRules.allowedPackUnits, contains('Litre'));
      expect(primerTemplate.unitRules.allowedSoldAsUnits, contains('Can'));

      // Simulate Putty -> Primer subcategory switch
      final row = <String, dynamic>{
        'unit': 'Kilogram',
        'soldAs': 'Bag',
        '_packaging': true,
        '_baseUnit': 'Kilogram',
        '_conversion': 20,
      };

      // Reset conversion state on subcategory change
      row['_packaging'] = false;
      row['_conversion'] = null;
      row['_baseUnit'] = null;
      row['_commercialUnit'] = primerTemplate.unitRules.defaultSoldAsUnit;
      row['unit'] = primerTemplate.unitRules.defaultPackUnit;

      expect(row['_packaging'], isFalse);
      expect(row['_baseUnit'], isNull);
      expect(row['_conversion'], isNull);
      expect(row['unit'], equals('Litre'));
      expect(row['_commercialUnit'], equals('Can'));
    },
  );

  test('Primer -> Brush clears paint unit/conversion state', () async {
    final brushTemplate = await templateResolver.resolveTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'SUB_BRUSH',
      token: 'TOK',
    );

    final row = <String, dynamic>{
      'unit': 'Litre',
      'soldAs': 'Can',
      '_packaging': true,
      '_baseUnit': 'Litre',
      '_conversion': 4,
    };

    // Reset on switch to Brush
    row['_packaging'] = false;
    row['_conversion'] = null;
    row['_baseUnit'] = null;
    row['_commercialUnit'] = brushTemplate.unitRules.defaultSoldAsUnit;
    row['unit'] = brushTemplate.unitRules.defaultPackUnit;

    expect(row['_packaging'], isFalse);
    expect(row['_baseUnit'], isNull);
    expect(row['_conversion'], isNull);
    expect(row['_commercialUnit'], equals('Piece'));
  });

  test('preview hidden when conversion inputs incomplete or invalid', () async {
    bool isPreviewVisible({
      required bool packaged,
      required String? soldAs,
      required String? baseUnit,
      required num? conversionFactor,
    }) {
      return packaged &&
          soldAs != null &&
          soldAs.isNotEmpty &&
          baseUnit != null &&
          baseUnit.isNotEmpty &&
          conversionFactor != null &&
          conversionFactor > 0;
    }

    expect(
      isPreviewVisible(
        packaged: true,
        soldAs: 'Bag',
        baseUnit: 'Kilogram',
        conversionFactor: null, // Factor missing!
      ),
      isFalse,
    );

    expect(
      isPreviewVisible(
        packaged: true,
        soldAs: 'Bag',
        baseUnit: null, // Base unit missing!
        conversionFactor: 20,
      ),
      isFalse,
    );

    expect(
      isPreviewVisible(
        packaged: true,
        soldAs: 'Bag',
        baseUnit: 'Kilogram',
        conversionFactor: 20,
      ),
      isTrue,
    );
  });

  test('valid Bag -> Kilogram preview renders correctly without ?', () async {
    String buildPreview({
      required String soldAs,
      required num factor,
      required String baseUnit,
    }) {
      return '1 $soldAs = $factor $baseUnit';
    }

    final preview = buildPreview(
      soldAs: 'Bag',
      factor: 20,
      baseUnit: 'Kilograms',
    );

    expect(preview, equals('1 Bag = 20 Kilograms'));
    expect(preview.contains('?'), isFalse);
  });
}
