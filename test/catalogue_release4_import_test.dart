import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

import 'support/catalogue_import_fixture.dart';
import 'support/phase10e_release.dart';

void main() {
  test('TEXT defaults are independent of options while SELECT defaults remain constrained', () {
    final rows = release4Rows();
    final template = rows['subcategory_attribute_templates']!.firstWhere(
      (r) => r['dataType'] == 'TEXT' && r['defaultValue'] != null,
    );
    expect(template['options'], isEmpty);
    CatalogueContract.validate(rows);
    template['dataType'] = 'SELECT';
    expect(
      () => CatalogueContract.validate(rows),
      throwsA(isA<AppException>()),
    );
    template['dataType'] = 'MULTI_SELECT';
    template['defaultValue'] = ['OUTSIDE-OPTIONS'];
    expect(
      () => CatalogueContract.validate(rows),
      throwsA(isA<AppException>()),
    );
  });
  test(
    'Release 4 validates without heuristic regeneration and imports atomically',
    () async {
      final documents = release4Documents();
      CatalogueContract.validate(CatalogueContract.decode(documents));
      final compiled = SystemCatalogueMetadata.compile(documents);
      expect(compiled, documents);
      expect(
        CatalogueContract.fingerprint(compiled),
        phase10eReview['contentFingerprint'],
      );
      final fixture = Phase10EFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final markerDocument = (await fixture.local.query(
        'product_catalogue_releases',
        [],
      )).single;
      final marker = FirestoreRestService.decodeFields(
        markerDocument['fields'],
      );
      expect(marker['catalogueVersion'], 4);
      expect(marker['compilerRevision'], 6);
      expect(marker['schemaRevision'], 1);
      expect(marker['installed'], true);
      expect(
        marker['contentFingerprint'],
        phase10eReview['contentFingerprint'],
      );
      expect(await fixture.local.db.query('sync_queries'), hasLength(2));
      final before = await completeState(fixture.local.db);
      await SystemCatalogueSnapshot.import(
        source: fixture.local,
        documents: documents,
        readTimes: const {'units': 'MUST_NOT_ADVANCE_ON_NOOP'},
        allowUnapprovedIsolatedForTests: true,
      );
      expect(await completeState(fixture.local.db), before);
      expect(await fixture.local.db.query('sync_outbox'), isEmpty);
    },
  );

  for (final stage in [
    'product_categories',
    'product_subcategories',
    'product_attributes',
    'product_attribute_options',
    'subcategory_attribute_templates',
    'before_release_marker',
    'after_release_marker',
  ]) {
    test(
      'Release 4 failure at $stage restores complete prior v3 state',
      () async {
        final fixture = Phase10EFixture();
        await fixture.open(importRelease: false);
        addTearDown(fixture.close);
        final prior = catalogueImportFixture();
        final priorDocuments = CatalogueContract.encode({
          for (final e in prior.entries)
            e.key: (e.value as List).cast<Map<String, dynamic>>(),
        });
        await SystemCatalogueSnapshot.import(
          source: fixture.local,
          documents: priorDocuments,
          readTimes: const {'units': 'PRIOR_V3_CURSOR'},
        );
        await fixture.local.upsertRemote('products', [
          {
            'name': 'products/EXISTING_PRODUCT_SENTINEL',
            'fields': FirestoreRestService.encodeFields({
              'productId': 'EXISTING_PRODUCT_SENTINEL',
              'status': 'ACTIVE',
              'scopeType': 'BUSINESS',
              'name': 'Preserve prior business state',
            }),
          },
        ]);
        await fixture.local.upsertRemote('product_variants', [
          {
            'name': 'product_variants/EXISTING_VARIANT_SENTINEL',
            'fields': FirestoreRestService.encodeFields({
              'variantId': 'EXISTING_VARIANT_SENTINEL',
              'productId': 'EXISTING_PRODUCT_SENTINEL',
              'sku': 'UNCHANGED-SKU',
              'barcode': 'UNCHANGED-BARCODE',
              'status': 'ACTIVE',
              'scopeType': 'BUSINESS',
            }),
          },
        ]);
        await fixture.local.db.insert('sync_outbox', {
          'batchId': 'existing-business-work',
          'entityType': 'products',
          'documentId': 'EXISTING_PRODUCT_SENTINEL',
          'operation': 'UPDATE',
          'payloadJson': '{}',
          'readSetJson': '{}',
          'localRevision': 1,
          'createdAt': '2026-01-01T00:00:00Z',
        });
        final before = await completeState(fixture.local.db);
        final sentinel = StateError('Controlled Release 4 failure: $stage');
        var reached = false;
        await expectLater(
          SystemCatalogueSnapshot.import(
            source: fixture.local,
            documents: release4Documents(),
            readTimes: const {'units': 'FAILED_RELEASE_4_CURSOR'},
            allowUnapprovedIsolatedForTests: true,
            failureProbe: (actual, tx) async {
              if (actual == stage) {
                reached = true;
                if (stage == 'after_release_marker') {
                  final marker = await tx.query(
                    'local_product_catalogue_releases',
                  );
                  expect(
                    CatalogueContract.version(
                      FirestoreRestService.decodeFields(
                        jsonDecode(marker.single['payloadJson'] as String),
                      ),
                    ),
                    4,
                  );
                }
                throw sentinel;
              }
            },
          ),
          throwsA(same(sentinel)),
        );
        expect(reached, true);
        expect(await completeState(fixture.local.db), before);
        final markerDocument = (await fixture.local.query(
          'product_catalogue_releases',
          [],
        )).single;
        final marker = FirestoreRestService.decodeFields(
          markerDocument['fields'],
        );
        expect(CatalogueContract.version(marker), 3);
      },
    );
  }
}
