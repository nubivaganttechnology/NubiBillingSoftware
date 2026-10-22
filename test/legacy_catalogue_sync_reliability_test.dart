import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'offline_sync_test.dart' show FakeRemote, TestConnectivity, session;
import 'support/catalogue_import_fixture.dart';

Map<String, List<Map<String, dynamic>>> _loadFixtureAsRelease3() {
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

  // Add the exact live Legacy Release 3 Automotive Coatings subcategory (without profileId)
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

  // Extract the live attribute templates for Automotive Coatings from fixture
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
    fixture['subcategory_attribute_templates']!.add({
      'name': 'subcategory_attribute_templates/${t['id']}',
      'fields': FirestoreValueCodec.encodeFields(
        Map<String, dynamic>.from(t as Map)..remove('id'),
      ),
    });
  }

  return fixture;
}

void main() {
  sqfliteFfiInit();

  group('Legacy Release 3 Automotive Coatings Compatibility', () {
    test('fresh catalogue installation compiles and validates Legacy Release 3', () {
      final fixture = _loadFixtureAsRelease3();
      final report = CatalogueReadiness.validate(fixture);

      expect(report.state, CatalogueReadinessState.ready, reason: '${report.errors}');
      expect(report.releaseVersion, 3);
      expect(report.errors, isEmpty);

      // Verify compiled output properties
      final compiled = SystemCatalogueMetadata.compile(fixture);
      final raw = CatalogueContract.decode(compiled);
      final sub = raw['product_subcategories']!.singleWhere(
        (s) => s['subcategoryId'] == 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
      );
      expect(sub['profileId'], 'EXPLICIT_METADATA');
      expect(sub['templateStatus'], 'READY');

      // Verify templates were preserved, not discarded
      final autoTemplates = raw['subcategory_attribute_templates']!.where(
        (t) => t['subcategoryId'] == 'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS' &&
            CatalogueContract.active(t),
      ).toList();
      expect(autoTemplates, isNotEmpty);
      expect(autoTemplates.length, greaterThanOrEqualTo(17));
    });

    test('strict profile enforcement is retained for Release 4 and later', () {
      final rows = jsonDecode(
        File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final fixtureV4 = {
        for (final entry in rows.entries)
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

      final release = fixtureV4['product_catalogue_releases']!.single;
      final releaseFields = FirestoreValueCodec.decodeFields(release['fields']);
      releaseFields['isolatedOnly'] = false;
      releaseFields['approvedForLiveExecution'] = true;
      releaseFields['productionMigrationApproved'] = true;
      releaseFields['firestorePublicationApproved'] = true;
      release['fields'] = FirestoreValueCodec.encodeFields(releaseFields);

      // In Release 4, remove profileId from AUTOMOTIVE_COATINGS
      final autoSub = fixtureV4['product_subcategories']!.singleWhere(
        (doc) => doc['name'].toString().endsWith(
          'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        ),
      );
      final subFields = FirestoreValueCodec.decodeFields(autoSub['fields']);
      subFields.remove('profileId');
      autoSub['fields'] = FirestoreValueCodec.encodeFields(subFields);

      // Must reject Release 4 missing profile
      final report = CatalogueReadiness.validate(fixtureV4);
      expect(report.state, CatalogueReadinessState.failed);
      expect(
        report.errors.join(' '),
        contains('Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS'),
      );
    });

    test('SystemCatalogueSnapshot.import installs Legacy Release 3 into SQLite', () async {
      final dir = await Directory.systemTemp.createTemp('nubibill-cat-test-');
      final db = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
      final source = LocalDataSource(await db.open('', 'U'));

      try {
        final fixture = _loadFixtureAsRelease3();
        await SystemCatalogueSnapshot.import(
          source: source,
          documents: fixture,
          readTimes: {
            for (final k in fixture.keys) k: DateTime.now().toUtc().toIso8601String(),
          },
          preserveSyncQueries: false,
        );

        final releases = await source.db.query(
          LocalDataSource.table('product_catalogue_releases'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        expect(releases, hasLength(1));

        final subcategories = await source.db.query(
          LocalDataSource.table('product_subcategories'),
          where: "scopeType='SYSTEM' AND subcategoryId='SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS'",
        );
        expect(subcategories, hasLength(1));
        final subFields = FirestoreRestService.decodeFields(
          jsonDecode(subcategories.single['payloadJson'] as String),
        );
        expect(subFields['profileId'], 'EXPLICIT_METADATA');

        final templates = await source.db.query(
          LocalDataSource.table('subcategory_attribute_templates'),
          where: "subcategoryId='SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS' AND isDeleted=0",
        );
        expect(templates.length, greaterThanOrEqualTo(17));
      } finally {
        await db.close();
        await dir.delete(recursive: true);
      }
    });
  });

  group('SyncEngine State Liveness and Masking Prevention', () {
    test('outbox-only sync does NOT mask unresolved catalogue failure', () async {
      final dir = await Directory.systemTemp.createTemp('nubibill-sync-mask-');
      final database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
      final remote = FakeRemote();
      final connectivity = TestConnectivity()..available = true;
      final sync = SyncEngine(
        remote,
        connectivity,
        sessionProvider: () async => session('U'),
      );

      final source = LocalDataSource(await database.open('', 'U'));
      sync.local = source;
      sync.accountUid = 'U';

      try {
        // Register catalogue queries to simulate active catalogue sync requirement
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

        // Simulate a persistent failure recorded in sync_control (e.g. previous snapshot import crash)
        await source.db.update('sync_control', {
          'failureCount': 1,
          'lastError': '[catalogue-profile] Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS.',
        }, where: 'id=1');

        // Trigger outbox-only sync (pull: false)
        await sync.sync(pull: false);

        // State MUST remain error and MUST NOT report Synced!
        expect(sync.state, SyncState.error);
        expect(sync.error, contains('Explicit profile required'));

        // Seed successful catalogue recovery into FakeRemote
        final fixture = _loadFixtureAsRelease3();
        for (final entry in fixture.entries) {
          for (final doc in entry.value) {
            final id = (doc['name'] as String).split('/').last;
            final fields = FirestoreValueCodec.decodeFields(doc['fields']);
            remote.seed(entry.key, id, fields);
          }
        }

        // Trigger pull sync to recover
        await sync.sync(pull: true);

        // Verify successful recovery:
        expect(sync.state, SyncState.synced, reason: 'sync.error: ${sync.error}');
        expect(sync.error, isNull);

        // Subsequent outbox-only sync (pull: false) correctly stays Synced
        await sync.sync(pull: false);
        expect(sync.state, SyncState.synced);
        expect(sync.error, isNull);

        // Verify Product Master availability (categories and units are ready)
        final categories = await source.db.query(
          LocalDataSource.table('product_categories'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        expect(categories, isNotEmpty);
        expect(categories.any((c) => c['categoryId'] == 'SYS_CATEGORY_AUTOMOTIVE_COATINGS'), isTrue);

        final units = await source.db.query(
          LocalDataSource.table('units'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        expect(units, isNotEmpty);

        // Verify Existing macOS Cache Parity:
        // When local database has matching catalogueVersion installed, subsequent sync
        // bypasses re-compilation and stays Synced without re-import.
        final initialRemoteCommits = remote.commits;
        await sync.sync(pull: true);
        expect(sync.state, SyncState.synced);
        expect(sync.error, isNull);
        // No new writes committed to remote
        expect(remote.commits, initialRemoteCommits);
      } finally {
        sync.dispose();
        await database.close();
        await dir.delete(recursive: true);
      }
    });
  });
}
