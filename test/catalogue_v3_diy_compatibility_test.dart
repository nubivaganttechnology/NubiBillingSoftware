import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

import 'support/catalogue_import_fixture.dart';
import 'support/phase10e_release.dart';

const _diyId = 'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS';

void main() {
  late Map<String, List<Map<String, dynamic>>> v3;

  setUp(() {
    final raw = catalogueImportFixture();
    v3 = {
      for (final entry in raw.entries)
        entry.key: [
          for (final record in (entry.value as List).cast<Map>())
            {
              'name': '${entry.key}/${record['id']}',
              'fields': FirestoreValueCodec.encodeFields(
                Map<String, dynamic>.from(record)..remove('id'),
              ),
            },
        ],
    };
    // The archived v3 snapshot is representative and omits this row. Add the
    // exact raw legacy subcategory shape supplied for the live v3 document.
    // The template row below is synthetic test scaffolding only.
    v3['product_subcategories']!.add({
      'name': 'product_subcategories/$_diyId',
      'fields': FirestoreValueCodec.encodeFields({
        'subcategoryId': _diyId,
        'categoryId': 'SYS_CATEGORY_DIY_AEROSOLS',
        'catalogueId': 'PAINT_V1',
        'version': 2,
        'businessTypeId': 'HARDWARE',
        'businessSubTypeId': 'PAINTS',
        'name': 'DIY Kits',
        'status': 'ACTIVE',
        'scopeType': 'SYSTEM',
      }),
    });
    v3['subcategory_attribute_templates']!.add({
      'name': 'subcategory_attribute_templates/TEST_V3_DIY_UNIT',
      'fields': FirestoreValueCodec.encodeFields({
        'templateId': 'TEST_V3_DIY_UNIT',
        'subcategoryId': _diyId,
        'attributeId': 'unit',
        'attributeLevel': 'VARIANT',
        'catalogueId': 'PAINT_V1',
        'version': 2,
        'businessTypeId': 'HARDWARE',
        'businessSubTypeId': 'PAINTS',
        'status': 'ACTIVE',
        'scopeType': 'SYSTEM',
      }),
    });
  });

  test(
    'legacy v3 DIY Kits with absent metadata installs and remains excluded',
    () async {
      final fixture = Phase10EFixture();
      await fixture.open(importRelease: false);
      addTearDown(fixture.close);

      await SystemCatalogueSnapshot.import(
        source: fixture.local,
        documents: v3,
        readTimes: const {},
      );
      final incoming = FirestoreValueCodec.decodeFields(
        v3['product_subcategories']!.singleWhere(
          (row) => row['name'].toString().endsWith(_diyId),
        )['fields'],
      );
      expect(incoming.containsKey('profileId'), isFalse);
      expect(incoming.containsKey('templateSelectable'), isFalse);
      expect(incoming.containsKey('templateStatus'), isFalse);

      final compiled = SystemCatalogueMetadata.compile(v3);
      final fields = FirestoreValueCodec.decodeFields(
        compiled['product_subcategories']!.singleWhere(
          (row) => row['name'].toString().endsWith(_diyId),
        )['fields'],
      );
      expect(fields.containsKey('profileId'), isFalse);
      expect(fields['templateSelectable'], isFalse);
      expect(fields.containsKey('templateStatus'), isFalse);
      final report = CatalogueReadiness.validate(compiled);
      expect(report.isReady, isTrue, reason: report.errors.join(' '));
      final installed = await fixture.local.query(
        'product_subcategories',
        [],
      );
      final installedDiy = FirestoreValueCodec.decodeFields(
        installed.singleWhere(
          (row) => row['name'].toString().endsWith(_diyId),
        )['fields'],
      );
      expect(installedDiy.containsKey('profileId'), isFalse);
      expect(installedDiy['templateSelectable'], isFalse);
      expect(installedDiy.containsKey('templateStatus'), isFalse);

      final selection = await CatalogueSelectionResolver(
        _NoRemoteFirestore(),
      ).evaluateSubcategoryEligibility(
        subcat: ProductMasterValue(
          id: _diyId,
          name: 'DIY Kits',
          status: 'ACTIVE',
          scopeType: 'SYSTEM',
          categoryId: 'SYS_CATEGORY_DIY_AEROSOLS',
          rawFields: installedDiy,
        ),
        tenantId: 'test-tenant',
        businessId: 'test-business',
        token: 'test-token',
        businessTypeId: 'HARDWARE',
        businessSubTypeId: 'PAINTS',
      );
      expect(selection.eligible, isFalse);
      expect(
        selection.exclusionReason,
        SelectionExclusionReason.notTemplateSelectable,
      );
    },
  );

  test('legacy v3 explicit historical exclusion metadata is preserved', () {
    final row = v3['product_subcategories']!.singleWhere(
      (doc) => doc['name'].toString().endsWith(_diyId),
    );
    final fields = FirestoreValueCodec.decodeFields(row['fields'])
      ..['templateSelectable'] = false
      ..['templateStatus'] = 'READY';
    row['fields'] = FirestoreValueCodec.encodeFields(fields);

    final compiled = SystemCatalogueMetadata.compile(v3);
    final output = FirestoreValueCodec.decodeFields(
      compiled['product_subcategories']!.singleWhere(
        (doc) => doc['name'].toString().endsWith(_diyId),
      )['fields'],
    );
    expect(output['templateSelectable'], isFalse);
    expect(output['templateStatus'], 'READY');
  });

  test(
    'legacy v3 selectable DIY Kits without an explicit profile is rejected',
    () {
      final row = v3['product_subcategories']!.singleWhere(
        (doc) => doc['name'].toString().endsWith(_diyId),
      );
      final fields = FirestoreValueCodec.decodeFields(row['fields'])
        ..['templateSelectable'] = true;
      row['fields'] = FirestoreValueCodec.encodeFields(fields);
      expect(
        () => SystemCatalogueMetadata.compile(v3),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'catalogue-profile',
          ),
        ),
      );
    },
  );

  test('legacy v3 DIY Kits with unsupported explicit profile is rejected', () {
    final row = v3['product_subcategories']!.singleWhere(
      (doc) => doc['name'].toString().endsWith(_diyId),
    );
    final fields = FirestoreValueCodec.decodeFields(row['fields'])
      ..['profileId'] = 'OTHER_DOMAIN_REVIEW';
    row['fields'] = FirestoreValueCodec.encodeFields(fields);
    expect(
      () => SystemCatalogueMetadata.compile(v3),
      throwsA(isA<AppException>().having(
        (error) => error.code,
        'code',
        'catalogue-profile',
      )),
    );
  });
}

class _NoRemoteFirestore implements FirestoreDataService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'The selector must exclude legacy DIY Kits before remote access.',
  );
}
