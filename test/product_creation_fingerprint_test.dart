import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'offline_sync_test.dart' show FakeRemote, TestConnectivity, token, session;

void main() {
  sqfliteFfiInit();

  final winPath = r'C:\Users\SKSUM\Downloads\FirestoreBackup\firestore_complete_merged.json';
  const macPath = '/Users/sksuman/Desktop/Firebase Billing/Firestore Data Fetch/firestore_full_backup/firestore_complete_merged.json';
  final backupFilePath = Platform.environment['FIRESTORE_BACKUP_PATH'] ?? (File(winPath).existsSync() ? winPath : macPath);

  Map<String, List<Map<String, dynamic>>> loadProductionCatalogue() {
    final backupFile = File(backupFilePath);
    final bytes = backupFile.readAsBytesSync();
    final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final collections = jsonMap['collections'] as Map<String, dynamic>;

    final inputDocs = <String, List<Map<String, dynamic>>>{};
    for (final colName in CatalogueContract.requiredCollections) {
      final colData = collections[colName] as Map<String, dynamic>? ?? {};
      final list = <Map<String, dynamic>>[];
      for (final entry in colData.entries) {
        final doc = entry.value as Map<String, dynamic>;
        final fields = FirestoreValueCodec.decodeFields(doc['fields']);
        if (fields['scopeType'] == 'SYSTEM') {
          if (colName == 'product_attribute_options' &&
              SystemCatalogueMetadata.redundantOptionIds.contains(entry.key)) {
            continue;
          }
          list.add({
            'name': '$colName/${entry.key}',
            'fields': FirestoreValueCodec.encodeFields(fields),
          });
        }
      }
      inputDocs[colName] = list;
    }
    return inputDocs;
  }

  group('Product Add Catalogue Fingerprint & Dynamic Form Acceptance', () {
    test(
      'genuine installed Release 3 catalogue passes Product Creation readiness and saves product with exact provenance',
      () async {
        final inputDocs = loadProductionCatalogue();
        final tempDir = await Directory.systemTemp.createTemp('prod-fp-test-');
        LocalDatabase? localDb;
        SyncEngine? sync;
        OfflineFirestoreService? service;

        try {
          localDb = LocalDatabase(
            factory: databaseFactoryFfi,
            directory: tempDir.path,
          );
          final remote = FakeRemote();
          sync = SyncEngine(
            remote,
            TestConnectivity()..available = false,
            sessionProvider: () async => session('U'),
          );
          service = OfflineFirestoreService(localDb, remote, sync);
          await service.activate('U');
          await service.setScope(tenant: 'T', business: 'B');
          final source = LocalDataSource(await localDb.open('', 'U'));
          final productRepo = ProductRepository(service, service);

          await SystemCatalogueSnapshot.import(
            source: source,
            documents: inputDocs,
            readTimes: {},
          );

          // Verify release metadata in snapshot
          final snapshot = <String, List<Map<String, dynamic>>>{};
          for (final collection in SystemCatalogueMetadata.collections) {
            snapshot[collection] = await service.queryDocuments(
              collection: collection,
              filters: const [FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM')],
              idToken: token('U'),
            );
          }

          final readiness = CatalogueReadiness.validateInstalled(snapshot);
          expect(readiness.isReady, isTrue, reason: 'Readiness errors: ${readiness.errors}');
          expect(readiness.releaseVersion, equals(3));

          final decodedReleases = CatalogueContract.decode(snapshot)['product_catalogue_releases']!
              .where(CatalogueContract.active)
              .toList();
          expect(decodedReleases, hasLength(1));
          expect(
            decodedReleases.single['catalogueFingerprint'],
            equals('sha256:c97908f05f0488b84d0260034d4fd82c3332fe7ac2cccc76f4ee22994a495e0a'),
          );

          // Setup test business and brand
          await service.createDocument('businesses', 'B', {
            'tenantId': 'T',
            'businessId': 'B',
          }, idToken: token('U'));

          await source.upsertRemote('brands', [
            {
              'name': 'brands/BR1',
              'fields': FirestoreValueCodec.encodeFields({
                'brandId': 'BR1',
                'scopeType': 'SYSTEM',
                'status': 'ACTIVE',
                'name': 'Asian Paints',
              }),
            },
          ]);

          const primerSubId =
              'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS';

          // Attempt product creation - this exercises _requireInstalledCatalogueFingerprint
          await productRepo.createStructuredProduct(
            tenantId: 'T',
            businessId: 'B',
            productName: 'Decoprime Wall Primer',
            actorUid: 'U',
            token: token('U'),
            productFields: {
              'brandId': 'BR1',
              'brand': 'Asian Paints',
              'categoryId': 'SYS_CATEGORY_PRIMERS_UNDERCOATS',
              'categoryName': 'Primers & Undercoats',
              'subcategoryId': primerSubId,
              'subcategory': 'Interior Wall Primers',
              'defaultGstRateBps': 1800,
              'attributeValues': {
                'colourMode': 'Fixed Colour',
                'productColour': 'White',
              },
            },
            variants: [
              {
                'variantName': '1L Can',
                'baseUnitId': 'SYS_UNIT_LITRE',
                'commercialUnitId': 'SYS_UNIT_LITRE',
                'baseQuantityPerCommercialUnit': 1,
                'defaultGstRateBps': 1800,
                'attributeValues': {
                  'unit': 'Litre',
                  'packSize': 1,
                  'soldAs': 'Can',
                },
              }
            ],
          );

          // Verify saved product contains the catalogueFingerprint
          final products = await productRepo.getProducts(
            tenantId: 'T',
            businessId: 'B',
            token: token('U'),
          );
          expect(products, hasLength(1));
          final savedProduct = products.single;
          expect(savedProduct.name, equals('Decoprime Wall Primer'));
          expect(
            savedProduct.catalogueFingerprint,
            equals('sha256:c97908f05f0488b84d0260034d4fd82c3332fe7ac2cccc76f4ee22994a495e0a'),
          );
        } finally {
          service?.logout();
          sync?.dispose();
          await localDb?.close();
          await tempDir.delete(recursive: true);
        }
      },
    );

    test('negative cases: missing, corrupted, mismatched or uninstalled fingerprint blocks product creation', () async {
      final baseDocs = loadProductionCatalogue();

      Future<void> testNegativeMutation(
        String description,
        void Function(Map<String, dynamic> releaseFields) mutateRelease, {
        required String expectedErrorCode,
      }) async {
        final tempDir = await Directory.systemTemp.createTemp('prod-fp-neg-');
        LocalDatabase? localDb;
        SyncEngine? sync;
        OfflineFirestoreService? service;

        try {
          localDb = LocalDatabase(
            factory: databaseFactoryFfi,
            directory: tempDir.path,
          );
          final remote = FakeRemote();
          sync = SyncEngine(
            remote,
            TestConnectivity()..available = false,
            sessionProvider: () async => session('U'),
          );
          service = OfflineFirestoreService(localDb, remote, sync);
          await service.activate('U');
          await service.setScope(tenant: 'T', business: 'B');
          final source = LocalDataSource(await localDb.open('', 'U'));
          final productRepo = ProductRepository(service, service);

          // Import valid initial catalogue
          await SystemCatalogueSnapshot.import(
            source: source,
            documents: baseDocs,
            readTimes: {},
          );

          await service.createDocument('businesses', 'B', {
            'tenantId': 'T',
            'businessId': 'B',
          }, idToken: token('U'));

          await source.upsertRemote('brands', [
            {
              'name': 'brands/BR1',
              'fields': FirestoreValueCodec.encodeFields({
                'brandId': 'BR1',
                'scopeType': 'SYSTEM',
                'status': 'ACTIVE',
                'name': 'Asian Paints',
              }),
            },
          ]);

          // Fetch current release record from local store and mutate it
          final currentReleaseRow = (await service.queryDocuments(
            collection: 'product_catalogue_releases',
            filters: const [FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM')],
            idToken: token('U'),
          )).single;
          final releaseFields = FirestoreValueCodec.decodeFields(currentReleaseRow['fields']);
          mutateRelease(releaseFields);

          await source.upsertRemote('product_catalogue_releases', [
            {
              'name': currentReleaseRow['name'],
              'fields': FirestoreValueCodec.encodeFields(releaseFields),
            },
          ]);

          await expectLater(
            () => productRepo.createStructuredProduct(
              tenantId: 'T',
              businessId: 'B',
              productName: 'Decoprime Wall Primer',
              actorUid: 'U',
              token: token('U'),
              productFields: {
                'brandId': 'BR1',
                'brand': 'Asian Paints',
                'categoryId': 'SYS_CATEGORY_PRIMERS_UNDERCOATS',
                'categoryName': 'Primers & Undercoats',
                'subcategoryId':
                    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS',
                'subcategory': 'Interior Wall Primers',
                'defaultGstRateBps': 1800,
                'attributeValues': {
                  'colourMode': 'Fixed Colour',
                  'productColour': 'White',
                },
              },
              variants: [
                {
                  'variantName': '1L Can',
                  'baseUnitId': 'SYS_UNIT_LITRE',
                  'commercialUnitId': 'SYS_UNIT_LITRE',
                  'baseQuantityPerCommercialUnit': 1,
                  'defaultGstRateBps': 1800,
                  'attributeValues': {
                    'unit': 'Litre',
                    'packSize': 1,
                    'soldAs': 'Can',
                  },
                }
              ],
            ),
            throwsA(
              isA<AppException>().having((e) => e.code, 'code', equals(expectedErrorCode)),
            ),
            reason: description,
          );
        } finally {
          service?.logout();
          sync?.dispose();
          await localDb?.close();
          await tempDir.delete(recursive: true);
        }
      }

      // Negative Case 1: Corrupted/invalid fingerprint format -> triggers readiness failure
      await testNegativeMutation(
        'Invalid fingerprint format',
        (f) => f['catalogueFingerprint'] = 'not-a-valid-sha256',
        expectedErrorCode: 'catalogue-readiness',
      );

      // Negative Case 2: Mismatched/Tampered fingerprint value -> triggers hash mismatch in readiness
      await testNegativeMutation(
        'Tampered fingerprint value',
        (f) => f['catalogueFingerprint'] =
            'sha256:0000000000000000000000000000000000000000000000000000000000000000',
        expectedErrorCode: 'catalogue-readiness',
      );

      // Negative Case 3: Unsupported catalogue version (version 2) -> rejected by compiler/readiness
      await testNegativeMutation(
        'Unsupported catalogue version 2',
        (f) => f['catalogueVersion'] = 2,
        expectedErrorCode: 'catalogue-readiness',
      );

      // Negative Case 4: Unsupported schema revision -> triggers readiness failure
      await testNegativeMutation(
        'Unsupported schema revision 99',
        (f) => f['schemaRevision'] = 99,
        expectedErrorCode: 'catalogue-readiness',
      );

      // Negative Case 5: Unsupported compiler revision -> triggers readiness failure
      await testNegativeMutation(
        'Unsupported compiler revision 99',
        (f) => f['compilerRevision'] = 99,
        expectedErrorCode: 'catalogue-readiness',
      );

      // Negative Case 6: Uninstalled release marker -> triggers readiness failure
      await testNegativeMutation(
        'Uninstalled marker',
        (f) => f['installed'] = false,
        expectedErrorCode: 'catalogue-readiness',
      );
    });

    test('dynamic product forms load correctly for Waterproofing, Primers, and Painting Tools', () async {
      final inputDocs = loadProductionCatalogue();
      final tempDir = await Directory.systemTemp.createTemp('prod-fp-form-');
      LocalDatabase? localDb;
      SyncEngine? sync;
      OfflineFirestoreService? service;

      try {
        localDb = LocalDatabase(
          factory: databaseFactoryFfi,
          directory: tempDir.path,
        );
        final remote = FakeRemote();
        sync = SyncEngine(
          remote,
          TestConnectivity()..available = false,
          sessionProvider: () async => session('U'),
        );
        service = OfflineFirestoreService(localDb, remote, sync);
        await service.activate('U');
        await service.setScope(tenant: 'T', business: 'B');
        final source = LocalDataSource(await localDb.open('', 'U'));
        final productRepo = ProductRepository(service, service);

        await SystemCatalogueSnapshot.import(
          source: source,
          documents: inputDocs,
          readTimes: {},
        );

        // 1. Waterproofing -> Interior Dampness Treatment
        const waterproofingSubId =
            'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT';
        final waterproofing = await productRepo.resolveTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: waterproofingSubId,
          token: token('U'),
        );
        expect(waterproofing.readiness, equals(TemplateReadinessState.ready));
        expect(waterproofing.attributes, isNotEmpty);
        expect(waterproofing.attributes.length, equals(14));
        final waterproofingAttrIds = waterproofing.attributes.map((a) => a.id).toSet();
        expect(waterproofingAttrIds, containsAll(['packSize', 'unit', 'soldAs', 'usage', 'surface']));

        // 2. Primers -> Interior Wall Primers
        const primerSubId =
            'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS';
        final primer = await productRepo.resolveTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: primerSubId,
          token: token('U'),
        );
        expect(primer.readiness, equals(TemplateReadinessState.ready));
        expect(primer.attributes, isNotEmpty);
        expect(primer.attributes.length, equals(18));
        final primerAttrIds = primer.attributes.map((a) => a.id).toSet();
        expect(primerAttrIds, containsAll(['packSize', 'unit', 'soldAs', 'colourMode', 'usage', 'surface']));

        // 3. Painting Tools -> Brush
        const brushSubId =
            'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH';
        final brush = await productRepo.resolveTemplate(
          tenantId: 'T',
          businessId: 'B',
          subcategoryId: brushSubId,
          token: token('U'),
        );
        expect(brush.readiness, equals(TemplateReadinessState.ready));
        expect(brush.attributes, isNotEmpty);
        expect(brush.attributes.length, equals(8));
        final brushAttrIds = brush.attributes.map((a) => a.id).toSet();
        expect(brushAttrIds, containsAll(['brushType', 'bristleMaterial', 'handleMaterial', 'brushSize', 'sizeUnit', 'unit', 'soldAs']));
      } finally {
        service?.logout();
        sync?.dispose();
        await localDb?.close();
        await tempDir.delete(recursive: true);
      }
    });
  });
}
