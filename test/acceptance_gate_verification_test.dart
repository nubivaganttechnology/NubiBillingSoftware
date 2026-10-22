import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_fingerprint.dart';
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
    if (!fixture['subcategory_attribute_templates']!.any((doc) => doc['name'] == 'subcategory_attribute_templates/${t['id']}')) {
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

  group('Gate 1: Backup Hashes and Serialization Analysis', () {
    test('calculate precise file hashes and line ending variations', () {
      final v3File = File('test/fixtures/system_catalogue_v3.json');
      final v4File = File('test/fixtures/system_catalogue_v4.json');

      final v3Bytes = v3File.readAsBytesSync();
      final v4Bytes = v4File.readAsBytesSync();

      final v3RawSha = sha256.convert(v3Bytes).toString();
      final v3LfSha = sha256.convert(utf8.encode(v3File.readAsStringSync().replaceAll('\r\n', '\n'))).toString();

      final v4RawSha = sha256.convert(v4Bytes).toString();
      final v4LfSha = sha256.convert(utf8.encode(v4File.readAsStringSync().replaceAll('\r\n', '\n'))).toString();

      print('GATE_LOG: v3 byte size = ${v3Bytes.length}');
      print('GATE_LOG: v3 raw sha256 = $v3RawSha');
      print('GATE_LOG: v3 LF sha256  = $v3LfSha');
      print('GATE_LOG: v4 byte size = ${v4Bytes.length}');
      print('GATE_LOG: v4 raw sha256 = $v4RawSha');
      print('GATE_LOG: v4 LF sha256  = $v4LfSha');

      expect(v3Bytes.length, anyOf(251445, 244532));
      expect(v4Bytes.length, anyOf(2912689, 2824602));
    });
  });

  group('Gate 2: Attribute Options Reconcile Audit', () {
    test('audit raw, active, inactive, duplicate and canonical options', () {
      final v3Raw = jsonDecode(File('test/fixtures/system_catalogue_v3.json').readAsStringSync()) as Map<String, dynamic>;
      final options = (v3Raw['product_attribute_options'] as List).cast<Map<String, dynamic>>();

      final rawCount = options.length;
      final activeCount = options.where((o) => o['status'] == 'ACTIVE').length;
      final inactiveCount = options.where((o) => o['status'] != 'ACTIVE').length;

      final uniquePairs = <String>{};
      final duplicates = <String>[];
      for (final o in options) {
        final pair = '${o['attributeId']}:${(o['name'] as String).trim().toLowerCase()}';
        if (!uniquePairs.add(pair)) {
          duplicates.add(pair);
        }
      }

      int totalCanonicalOptionIds = 0;
      for (final entry in CatalogueContract.optionIds.entries) {
        totalCanonicalOptionIds += entry.value.length;
      }

      print('GATE_LOG: options raw count = $rawCount');
      print('GATE_LOG: options active count = $activeCount');
      print('GATE_LOG: options inactive count = $inactiveCount');
      print('GATE_LOG: options unique pairs = ${uniquePairs.length}');
      print('GATE_LOG: options duplicate count = ${duplicates.length}');
      print('GATE_LOG: options canonical mappings in CatalogueContract = $totalCanonicalOptionIds');

      expect(rawCount, 129);
      expect(activeCount, 127);
      expect(inactiveCount, 2);
      expect(duplicates.length, 11);
      expect(uniquePairs.length, 118);
    });
  });

  group('Gate 3 & 4: Disposable SQLite SyncEngine pull:false push:true Scenarios', () {
    late Directory tempDir;
    late LocalDatabase database;
    late FakeRemote remote;
    late TestConnectivity connectivity;
    late SyncEngine sync;
    late LocalDataSource source;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('nubibill-gate-');
      database = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
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

      // Register catalogue queries
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
    });

    tearDown(() async {
      sync.dispose();
      await database.close();
      await tempDir.delete(recursive: true);
    });

    test('Scenario 1: Installed release exists but category/subcategory tables are empty', () async {
      // 1. Insert installed release row
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
          'compilerRevision': 0,
          'installed': true,
        }),
      });

      // Categories and subcategories tables remain completely empty (0 rows)
      final categories = await source.db.query('local_product_categories');
      final subcategories = await source.db.query('local_product_subcategories');
      expect(categories, isEmpty);
      expect(subcategories, isEmpty);

      // Execute SyncEngine.sync(pull: false) with push
      await sync.sync(pull: false);

      print('GATE_LOG: Scenario 1 sync.state = ${sync.state}, sync.error = ${sync.error}');
    });

    test('Scenario 2: Installed release exists but required attribute templates are missing', () async {
      // 1. Insert release and basic category/subcategory
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

      // Templates table is empty
      final templates = await source.db.query('local_subcategory_attribute_templates');
      expect(templates, isEmpty);

      // Execute sync(pull: false)
      await sync.sync(pull: false);

      print('GATE_LOG: Scenario 2 sync.state = ${sync.state}, sync.error = ${sync.error}');
    });

    test('Scenario 3: A previous catalogue pull failed', () async {
      // Simulate persistent error in sync_control
      await source.db.update('sync_control', {
        'failureCount': 1,
        'lastError': '[catalogue-profile] Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS.',
      }, where: 'id=1');

      // Execute sync(pull: false)
      await sync.sync(pull: false);

      print('GATE_LOG: Scenario 3 sync.state = ${sync.state}, sync.error = ${sync.error}');
      expect(sync.state, SyncState.error);
      expect(sync.error, contains('Explicit profile required'));
    });

    test('Scenario 4: Genuine full catalogue recovery has succeeded', () async {
      // Seed FakeRemote with full release 3 catalogue
      final fixture = loadRelease3Fixture();
      for (final entry in fixture.entries) {
        for (final doc in entry.value) {
          final id = (doc['name'] as String).split('/').last;
          final fields = FirestoreValueCodec.decodeFields(doc['fields']);
          remote.seed(entry.key, id, fields);
        }
      }

      // Initial state has previous error
      await source.db.update('sync_control', {
        'failureCount': 1,
        'lastError': '[catalogue-profile] Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS.',
      }, where: 'id=1');

      // Trigger recovery pull
      await sync.sync(pull: true);

      print('GATE_LOG: Scenario 4 after pull recovery: sync.state = ${sync.state}, sync.error = ${sync.error}');
      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);

      // Verify sync_control.lastError was cleared
      final controlRow = (await source.db.query('sync_control', where: 'id=1')).first;
      expect(controlRow['lastError'], isNull);

      // Subsequent sync(pull: false, push: true) remains Synced
      await sync.sync(pull: false);
      print('GATE_LOG: Scenario 4 after subsequent pull:false: sync.state = ${sync.state}, sync.error = ${sync.error}');
      expect(sync.state, SyncState.synced);
      expect(sync.error, isNull);
    });
  });

  group('Gate 5 & 6: Full Release 3 Compiler Import and Template Fidelity', () {
    test('Release 3 compiler imports all tables and preserves Automotive Coatings templates', () async {
      final tempDir = await Directory.systemTemp.createTemp('nubibill-gate-import-');
      final db = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
      final source = LocalDataSource(await db.open('', 'U'));

      try {
        final fixture = loadRelease3Fixture();
        await SystemCatalogueSnapshot.import(
          source: source,
          documents: fixture,
          readTimes: {
            for (final k in fixture.keys) k: DateTime.now().toUtc().toIso8601String(),
          },
          preserveSyncQueries: false,
        );

        // Check release row
        final releases = await source.db.query(
          LocalDataSource.table('product_catalogue_releases'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        expect(releases, hasLength(1));

        // Check Automotive Coatings subcategory
        final autoSub = await source.db.query(
          LocalDataSource.table('product_subcategories'),
          where: "scopeType='SYSTEM' AND subcategoryId='SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS'",
        );
        expect(autoSub, hasLength(1));
        final subPayload = FirestoreRestService.decodeFields(
          jsonDecode(autoSub.single['payloadJson'] as String),
        );
        expect(subPayload['profileId'], 'EXPLICIT_METADATA');
        expect(subPayload['templateStatus'], 'READY');
        expect(subPayload['templateSelectable'], false);

        // Check authored templates for Automotive Coatings
        final templates = await source.db.query(
          LocalDataSource.table('subcategory_attribute_templates'),
          where: "subcategoryId='SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS' AND isDeleted=0",
        );
        print('GATE_LOG: preserved Automotive Coatings templates count = ${templates.length}');
        expect(templates.length, greaterThanOrEqualTo(17));

        // Verify categories exist
        final categories = await source.db.query(
          LocalDataSource.table('product_categories'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        print('GATE_LOG: installed SYSTEM categories count = ${categories.length}');
        expect(categories, isNotEmpty);

        // Verify units exist
        final units = await source.db.query(
          LocalDataSource.table('units'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        print('GATE_LOG: installed SYSTEM units count = ${units.length}');
        expect(units, isNotEmpty);
      } finally {
        await db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('strict Release 4 rejection when profileId is missing', () {
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

      final autoSub = fixtureV4['product_subcategories']!.singleWhere(
        (doc) => doc['name'].toString().endsWith(
          'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
        ),
      );
      final fields = FirestoreValueCodec.decodeFields(autoSub['fields']);
      fields.remove('profileId');
      autoSub['fields'] = FirestoreValueCodec.encodeFields(fields);

      final report = CatalogueReadiness.validate(fixtureV4);
      print('GATE_LOG: Release 4 missing profile validation state = ${report.state}');
      print('GATE_LOG: Release 4 missing profile errors = ${report.errors}');
      expect(report.state, CatalogueReadinessState.failed);
      expect(report.errors.join(' '), contains('Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS'));
    });
  });
}
