import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'offline_sync_test.dart' show FakeRemote, TestConnectivity, session;
import 'support/catalogue_import_fixture.dart';

Map<String, List<Map<String, dynamic>>> loadRelease3Fixture() {
  final raw = catalogueImportFixture();
  final fixture = {
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

  // Ensure live Automotive Coatings subcategory exists (without profileId)
  fixture['product_subcategories']!.removeWhere(
    (doc) => doc['name'].toString().endsWith(
          'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        ),
  );
  fixture['product_subcategories']!.add({
    'name':
        'product_subcategories/SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
    'fields': FirestoreValueCodec.encodeFields({
      'subcategoryId':
          'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
      'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
      'catalogueId': 'PAINT_V1',
      'version': 29,
      'businessTypeId': 'HARDWARE',
      'businessSubTypeId': 'PAINTS',
      'name': 'Automotive Coatings',
      'subcategoryName': 'Automotive Coatings',
      'status': 'ACTIVE',
      'scopeType': 'SYSTEM',
      'templateStatus': 'READY',
      'templateSelectable': false,
    }),
  });

  // Ensure Automotive Coatings attribute templates exist from fixture
  final v4Data = jsonDecode(
    File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final autoTemplates = (v4Data['subcategory_attribute_templates'] as List)
      .where(
        (t) =>
            t['subcategoryId'] ==
            'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
      )
      .toList();
  for (final t in autoTemplates) {
    if (!fixture['subcategory_attribute_templates']!.any(
      (doc) => doc['name'] == 'subcategory_attribute_templates/${t['id']}',
    )) {
      fixture['subcategory_attribute_templates']!.add({
        'name': 'subcategory_attribute_templates/${t['id']}',
        'fields': FirestoreValueCodec.encodeFields(
          Map<String, dynamic>.from(t)..remove('id'),
        ),
      });
    }
  }
  return fixture;
}

void main() {
  sqfliteFfiInit();

  group('Cross-Platform Sync Readiness Deep Validation Matrix', () {
    late Directory tempDir;
    late LocalDatabase database;
    late FakeRemote remote;
    late TestConnectivity connectivity;
    late SyncEngine sync;
    late LocalDataSource source;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sync-readiness-test-');
      database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: tempDir.path,
      );
      remote = FakeRemote();
      connectivity = TestConnectivity()..available = true;
      sync = SyncEngine(
        remote,
        connectivity,
        sessionProvider: () async => session('U'),
      );
      source = LocalDataSource(await database.open('', 'U'));
      sync.local = source;
      sync.accountUid = 'U';
    });

    tearDown(() async {
      sync.dispose();
      await database.close();
      await tempDir.delete(recursive: true);
    });

    Future<void> registerCatalogueQueries() async {
      for (final collection in SystemCatalogueMetadata.collections) {
        await source.db.insert('sync_queries', {
          'queryKey': 'QRY-CAT-$collection',
          'collectionName': collection,
          'queryJson': jsonEncode({
            'filters': [
              {
                'field': 'scopeType',
                'operation': 'EQUAL',
                'value': {'stringValue': 'SYSTEM'}
              }
            ]
          }),
          'active': 1,
          'lastSyncedAt': null,
          'lastAttemptAt': null,
        });
      }
    }

    test('Scenario 1: Missing installed release -> Not Synced', () async {
      await registerCatalogueQueries();
      // local_product_catalogue_releases has 0 rows
      final releases = await source.db.query('local_product_catalogue_releases');
      expect(releases, isEmpty);

      await sync.sync(pull: false);

      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
      expect(sync.error, contains('catalogue-readiness'));
      expect(sync.error, contains('No installed SYSTEM catalogue release found'));
    });

    test('Scenario 2: Installed release but empty categories -> Not Synced', () async {
      await registerCatalogueQueries();
      // Insert release row with installed=true
      await source.db.insert('local_product_catalogue_releases', {
        'remoteId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'catalogueId': 'PAINT_V1',
          'catalogueVersion': 3,
          'installed': true,
          'schemaRevision': 1,
          'compilerRevision': 0,
        }),
      });

      // Categories and subcategories tables are empty
      expect(await source.db.query('local_product_categories'), isEmpty);

      await sync.sync(pull: false);

      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
      expect(sync.error, contains('catalogue-readiness'));
    });

    test('Scenario 3: Installed release but empty subcategories -> Not Synced', () async {
      await registerCatalogueQueries();
      await source.db.insert('local_product_catalogue_releases', {
        'remoteId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'catalogueId': 'PAINT_V1',
          'catalogueVersion': 3,
          'installed': true,
        }),
      });
      await source.db.insert('local_product_categories', {
        'remoteId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
          'name': 'Automotive Coatings',
        }),
      });

      // Subcategories empty
      expect(await source.db.query('local_product_subcategories'), isEmpty);

      await sync.sync(pull: false);

      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
      expect(sync.error, contains('catalogue-readiness'));
    });

    test('Scenario 4: Installed release but missing required templates -> Not Synced', () async {
      await registerCatalogueQueries();
      await source.db.insert('local_product_catalogue_releases', {
        'remoteId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'catalogueId': 'PAINT_V1',
          'catalogueVersion': 3,
          'installed': true,
        }),
      });
      await source.db.insert('local_product_categories', {
        'remoteId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
          'name': 'Automotive Coatings',
        }),
      });
      await source.db.insert('local_product_subcategories', {
        'remoteId': 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        'subcategoryId': 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'subcategoryId': 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
          'categoryId': 'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
          'name': 'Automotive Coatings',
          'profileId': 'EXPLICIT_METADATA',
        }),
      });

      // Templates empty
      expect(await source.db.query('local_subcategory_attribute_templates'), isEmpty);

      await sync.sync(pull: false);

      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
      expect(sync.error, contains('catalogue-readiness'));
    });

    test('Scenario 5: Installed release but broken attribute references -> Not Synced', () async {
      await registerCatalogueQueries();
      final fixture = loadRelease3Fixture();
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: fixture,
        readTimes: {},
        preserveSyncQueries: false,
      );

      // Verify catalogue is initially ready
      await sync.sync(pull: false);
      expect(sync.state, SyncState.synced);

      // Now inject a broken template referencing a non-existent attribute ID
      await source.db.insert('local_subcategory_attribute_templates', {
        'remoteId': 'BROKEN_TEMPLATE',
        'subcategoryId': 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        'attributeId': 'NON_EXISTENT_ATTRIBUTE_XYZ',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'templateId': 'BROKEN_TEMPLATE',
          'subcategoryId': 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
          'attributeId': 'NON_EXISTENT_ATTRIBUTE_XYZ',
          'attributeLevel': 'PRODUCT',
          'dataType': 'TEXT',
          'status': 'ACTIVE',
          'scopeType': 'SYSTEM',
        }),
      });

      // Invalidate cache and sync pull: false
      sync.invalidateCatalogueReadiness();
      await sync.sync(pull: false);

      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
      expect(sync.error, contains('catalogue-readiness'));
    });

    test('Scenario 6: Successful outbox-only push with incomplete catalogue -> Not Synced', () async {
      await registerCatalogueQueries();
      // Categories missing (incomplete catalogue)
      await source.db.insert('local_product_catalogue_releases', {
        'remoteId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'SYNCED',
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({
          'catalogueId': 'PAINT_V1',
          'catalogueVersion': 3,
          'installed': true,
        }),
      });

      // Insert local invoice row
      await source.db.insert('local_invoices', {
        'remoteId': 'INV-001',
        'scopeType': 'TENANT',
        'status': 'ACTIVE',
        'isDeleted': 0,
        'syncStatus': 'PENDING',
        'localRevision': 1,
        'acknowledgedRevision': 0,
        'localUpdatedAt': LocalDataSource.now(),
        'payloadJson': jsonEncode({'invoiceNumber': 'INV-1001', 'total': 500}),
      });

      // Queue an outbox record with full push payload format
      await source.db.insert('sync_outbox', {
        'batchId': 'BATCH-001',
        'entityType': 'invoices',
        'documentId': 'INV-001',
        'operation': 'CREATE',
        'payloadJson': jsonEncode({
          'collection': 'invoices',
          'id': 'INV-001',
          'operation': 'CREATE',
          'fields': FirestoreValueCodec.encodeFields({
            'invoiceNumber': 'INV-1001',
            'total': 500,
          }),
        }),
        'readSetJson': jsonEncode({}),
        'localRevision': 1,
        'status': 'PENDING',
        'attemptCount': 0,
        'createdAt': LocalDataSource.now(),
        'tenantId': 'U',
        'businessId': 'BUS-001',
      });

      // Ensure remote doc does not exist prior to CREATE push so commit succeeds
      remote.docs.remove('invoices/INV-001');

      // Execute sync with push=true, pull=false
      await sync.sync(pull: false, push: true);

      // Verify push succeeded (outbox is empty)
      final outboxRows = await source.db.query('sync_outbox');
      expect(outboxRows, isEmpty);

      // But catalogue is incomplete, so sync.state MUST NOT be synced!
      expect(sync.state, SyncState.error);
      expect(sync.state, isNot(SyncState.synced));
    });

    test('Scenario 7: Previous failed pull followed by push-only sync -> Error retained', () async {
      await registerCatalogueQueries();
      // Record a previous pull error in sync_control
      await source.db.update('sync_control', {
        'failureCount': 2,
        'lastError': '[catalogue-profile] Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS.',
      }, where: 'id=1');

      await sync.sync(pull: false, push: true);

      expect(sync.state, SyncState.error);
      expect(sync.error, contains('Explicit profile required'));
    });

    test('Scenario 8: Complete Release 3 catalogue and successful sync -> Synced', () async {
      await registerCatalogueQueries();
      final fixture = loadRelease3Fixture();
      for (final entry in fixture.entries) {
        for (final doc in entry.value) {
          final id = (doc['name'] as String).split('/').last;
          final fields = FirestoreValueCodec.decodeFields(doc['fields']);
          remote.seed(entry.key, id, fields);
        }
      }

      await sync.sync(pull: true);

      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);

      // Subsequent pull:false remains Synced
      await sync.sync(pull: false);
      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);
    });

    test('Scenario 9: Genuine recovery from incomplete catalogue -> Synced', () async {
      await registerCatalogueQueries();
      // Initial incomplete state with error
      await source.db.update('sync_control', {
        'failureCount': 3,
        'lastError': '[catalogue-readiness] Required catalogue collection product_categories is missing or empty.',
      }, where: 'id=1');

      await sync.sync(pull: false);
      expect(sync.state, SyncState.error);

      // Now seed remote with complete Release 3 catalogue and trigger recovery pull
      final fixture = loadRelease3Fixture();
      for (final entry in fixture.entries) {
        for (final doc in entry.value) {
          final id = (doc['name'] as String).split('/').last;
          final fields = FirestoreValueCodec.decodeFields(doc['fields']);
          remote.seed(entry.key, id, fields);
        }
      }

      await sync.sync(pull: true);

      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);

      final controlRow = (await source.db.query('sync_control', where: 'id=1')).first;
      expect(controlRow['lastError'], isNull);
    });

    test('Scenario 10: Valid installed catalogue during offline operation -> Offline data preserved', () async {
      await registerCatalogueQueries();
      final fixture = loadRelease3Fixture();
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: fixture,
        readTimes: {},
        preserveSyncQueries: false,
      );

      // Initial sync is synced
      await sync.sync(pull: false);
      expect(sync.state, SyncState.synced);

      // Go offline
      connectivity.available = false;

      // Queue an offline local write
      await source.db.insert('sync_outbox', {
        'batchId': 'BATCH-OFFLINE-001',
        'entityType': 'invoices',
        'documentId': 'INV-OFFLINE-001',
        'operation': 'CREATE',
        'payloadJson': jsonEncode({'invoiceNumber': 'INV-OFF-101'}),
        'readSetJson': jsonEncode({}),
        'localRevision': 1,
        'status': 'PENDING',
        'attemptCount': 0,
        'createdAt': LocalDataSource.now(),
        'tenantId': 'U',
        'businessId': 'BUS-001',
      });

      // Simulate local write notification
      sync.notifyLocalWrite();

      // Ensure outbox row is preserved
      final pendingRows = await source.db.query('sync_outbox');
      expect(pendingRows.length, 1);
      expect(pendingRows.first['documentId'], 'INV-OFFLINE-001');

      // Database tables remain completely intact
      final categories = await source.db.query('local_product_categories');
      expect(categories.length, greaterThanOrEqualTo(32));
    });

    test('Scenario 11: Catalogue functionality legitimately disabled -> No false catalogue error', () async {
      // sync_queries has NO catalogue queries registered (only business queries)
      await source.db.insert('sync_queries', {
        'queryKey': 'QRY-BUS-invoices',
        'collectionName': 'invoices',
        'queryJson': jsonEncode({'filters': []}),
        'active': 1,
      });

      // Catalogue release table is completely empty
      expect(await source.db.query('local_product_catalogue_releases'), isEmpty);

      // Execute sync(pull: false)
      await sync.sync(pull: false);

      // No catalogue error is thrown; sync successfully transitions to Synced
      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);
    });

    test('Scenario 12: Unapproved Release 4 -> Rejected', () {
      final v4Raw = jsonDecode(
        File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final fixtureV4 = {
        for (final entry in v4Raw.entries)
          entry.key: [
            for (final raw in (entry.value as List).cast<Map>())
              {
                'name': '${entry.key}/${raw['id']}',
                'fields': FirestoreValueCodec.encodeFields(
                  Map<String, dynamic>.from(raw)..remove('id'),
                ),
              },
          ],
      };

      // Ensure release document lacks required approvals
      final releaseDoc = fixtureV4['product_catalogue_releases']!.single;
      final releaseFields = FirestoreValueCodec.decodeFields(releaseDoc['fields']);
      releaseFields['approvedForLiveExecution'] = false;
      releaseDoc['fields'] = FirestoreValueCodec.encodeFields(releaseFields);

      final report = CatalogueReadiness.validate(fixtureV4);
      expect(report.state, CatalogueReadinessState.failed);
      expect(report.errors.join(' '), contains('Catalogue release is isolated or lacks required production approvals.'));
    });
  });
}
