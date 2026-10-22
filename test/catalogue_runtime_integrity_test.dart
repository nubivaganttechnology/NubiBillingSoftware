import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

import 'support/phase10e_release.dart';

void main() {
  late Directory directory;
  late LocalDatabase database;
  late LocalDataSource source;
  late Map<String, List<Map<String, dynamic>>> approvedRelease;

  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp(
      'nubibill-catalogue-integrity-',
    );
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    source = LocalDataSource(await database.open('isolated', 'catalogue-test'));
    approvedRelease = _approvedForTest(release4Documents());
  });

  tearDown(() async {
    await source.db.close();
    await directory.delete(recursive: true);
  });

  test(
    'fresh SQLite install stores and verifies exact manifest fingerprint',
    () async {
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: _clone(approvedRelease),
        readTimes: const {},
      );

      final cached = await _cachedSnapshot(source);
      final report = CatalogueReadiness.validateInstalled(cached);
      expect(report.isReady, isTrue, reason: '${report.errors}');
      final marker = FirestoreValueCodec.decodeFields(
        cached['product_catalogue_releases']!.single['fields'],
      );
      expect(marker['installedDocumentManifest'], isA<Map>());
      expect(marker['catalogueFingerprint'], isA<String>());
    },
  );

  test(
    'mixed record versions remain valid when they belong to release manifest',
    () async {
      final mixed = _clone(approvedRelease);
      final category = mixed['product_categories']!.first;
      final fields = FirestoreValueCodec.decodeFields(category['fields']);
      fields['version'] = 2;
      category['fields'] = FirestoreValueCodec.encodeFields(fields);
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: mixed,
        readTimes: const {},
      );
      final report = CatalogueReadiness.validateInstalled(
        await _cachedSnapshot(source),
      );
      expect(report.isReady, isTrue, reason: '${report.errors}');
    },
  );

  test('fingerprint mismatch and missing release marker fail closed', () async {
    await SystemCatalogueSnapshot.import(
      source: source,
      documents: _clone(approvedRelease),
      readTimes: const {},
    );
    final changed = await _cachedSnapshot(source);
    final marker = changed['product_catalogue_releases']!.single;
    final fields = FirestoreValueCodec.decodeFields(marker['fields']);
    fields['catalogueFingerprint'] = 'sha256:${List.filled(64, '0').join()}';
    marker['fields'] = FirestoreValueCodec.encodeFields(fields);
    expect(
      CatalogueReadiness.validateInstalled(changed).errors.join(' '),
      contains('fingerprint mismatch'),
    );

    final missing = await _cachedSnapshot(source);
    missing['product_catalogue_releases']!.clear();
    expect(CatalogueReadiness.validateInstalled(missing).isReady, isFalse);
  });

  test('incomplete catalogue snapshots are rejected before install', () async {
    final incomplete = _clone(approvedRelease)..remove('units');
    expect(
      () => SystemCatalogueSnapshot.import(
        source: source,
        documents: incomplete,
        readTimes: const {},
      ),
      throwsA(isA<Exception>()),
    );
    expect(await source.db.query('local_product_catalogue_releases'), isEmpty);
  });

  test('active duplicate Tile Adhesives identity is reported without deletion', () {
    final duplicate = _clone(approvedRelease);
    final original = duplicate['product_subcategories']!.singleWhere(
      (doc) => doc['name'].toString().endsWith(
        'SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES',
      ),
    );
    final fields = FirestoreValueCodec.decodeFields(original['fields']);
    fields['subcategoryId'] = 'SYS_SUBCATEGORY_DUPLICATE_TILE_ADHESIVES_TEST';
    duplicate['product_subcategories']!.add({
      'name':
          'product_subcategories/SYS_SUBCATEGORY_DUPLICATE_TILE_ADHESIVES_TEST',
      'fields': FirestoreValueCodec.encodeFields(fields),
    });
    final report = CatalogueReadiness.validate(duplicate);
    expect(report.isReady, isFalse);
    expect(
      report.errors.join(' '),
      contains('Ambiguous duplicate catalogue identity'),
    );
    expect(
      duplicate['product_subcategories']!.length,
      approvedRelease['product_subcategories']!.length + 1,
    );
  });

  test('active Hand Sanitizers without a supported profile is reported', () {
    final invalid = _clone(approvedRelease);
    invalid['product_categories']!.add(
      _document('product_categories', {
        'categoryId': 'SYS_CATEGORY_HEALTH_HYGIENE_TEST',
        'catalogueId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'businessTypeId': 'HARDWARE',
        'businessSubTypeId': 'PAINTS',
        'name': 'Health & Hygiene',
      }),
    );
    invalid['product_subcategories']!.add(
      _document('product_subcategories', {
        'subcategoryId': 'SYS_SUBCATEGORY_HAND_SANITIZERS_TEST',
        'catalogueId': 'PAINT_V1',
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'businessTypeId': 'HARDWARE',
        'businessSubTypeId': 'PAINTS',
        'categoryId': 'SYS_CATEGORY_HEALTH_HYGIENE_TEST',
        'name': 'Hand Sanitizers',
        'family': 'OTHER_DOMAIN_REVIEW',
        'templateSelectable': false,
        'templateStatus': 'READY',
      }),
    );
    final report = CatalogueReadiness.validate(invalid);
    expect(report.isReady, isFalse);
    expect(report.errors.join(' '), contains('Explicit profile required'));
  });

  test('isolated unapproved release is rejected and valid approved DIY Kits passes', () {
    final candidate = _clone(approvedRelease);
    final release = candidate['product_catalogue_releases']!.single;
    final fields = FirestoreValueCodec.decodeFields(release['fields']);
    fields
      ..['isolatedOnly'] = true
      ..['approvedForLiveExecution'] = false
      ..['productionMigrationApproved'] = false
      ..['firestorePublicationApproved'] = false;
    release['fields'] = FirestoreValueCodec.encodeFields(fields);
    expect(CatalogueReadiness.validate(candidate).isReady, isFalse);
    expect(
      CatalogueReadiness.validate(_clone(approvedRelease)).isReady,
      isTrue,
    );
  });

  test('unsupported DIY Kits profile is rejected', () {
    final invalid = _clone(approvedRelease);
    final diy = invalid['product_subcategories']!.singleWhere(
      (doc) => doc['name'].toString().endsWith('_DIY_KITS'),
    );
    final fields = FirestoreValueCodec.decodeFields(diy['fields']);
    fields['profileId'] = 'UNSUPPORTED_PROFILE';
    diy['fields'] = FirestoreValueCodec.encodeFields(fields);
    final report = CatalogueReadiness.validate(invalid);
    expect(report.isReady, isFalse);
    expect(
      report.errors.join(' '),
      contains('Unknown or conflicting catalogue profile'),
    );
  });

  test(
    'inactive historical rows outside the release manifest are retained',
    () async {
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: _clone(approvedRelease),
        readTimes: const {},
      );
      final historical = await _cachedSnapshot(source);
      final sourceCategory = FirestoreValueCodec.decodeFields(
        historical['product_categories']!.first['fields'],
      );
      historical['product_categories']!.add(
        _document('product_categories', {
          ...sourceCategory,
          'categoryId': 'SYS_CATEGORY_INACTIVE_HISTORY_TEST',
          'name': 'Historical inactive category',
          'status': 'INACTIVE',
        }),
      );
      final report = CatalogueReadiness.validateInstalled(historical);
      expect(report.isReady, isTrue, reason: '${report.errors}');
    },
  );

  test(
    'unexpected active records outside release manifest fail validation',
    () async {
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: _clone(approvedRelease),
        readTimes: const {},
      );
      final mixed = await _cachedSnapshot(source);
      mixed['product_categories']!.add(
        _document('product_categories', {
          'categoryId': 'SYS_CATEGORY_UNEXPECTED_ACTIVE_TEST',
          'catalogueId': 'PAINT_V1',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'businessTypeId': 'HARDWARE',
          'businessSubTypeId': 'PAINTS',
          'name': 'Unexpected active category',
        }),
      );
      final report = CatalogueReadiness.validateInstalled(mixed);
      expect(report.isReady, isFalse);
      expect(report.errors.join(' '), contains('outside installed release'));
    },
  );

  test('invalid cache cannot pass readiness and offline valid cache remains usable', () async {
    await SystemCatalogueSnapshot.import(
      source: source,
      documents: _clone(approvedRelease),
      readTimes: const {},
    );
    final offlineCache = await _cachedSnapshot(source);
    expect(CatalogueReadiness.validateInstalled(offlineCache).isReady, isTrue);
    final marker = offlineCache['product_catalogue_releases']!.single;
    final fields = FirestoreValueCodec.decodeFields(marker['fields']);
    fields['compilerRevision'] = 999;
    marker['fields'] = FirestoreValueCodec.encodeFields(fields);
    expect(CatalogueReadiness.validateInstalled(offlineCache).isReady, isFalse);
  });

  test('failed install preserves prior catalogue and pending outbox', () async {
    await SystemCatalogueSnapshot.import(
      source: source,
      documents: _clone(approvedRelease),
      readTimes: const {},
    );
    await source.db.insert('sync_outbox', {
      'batchId': 'isolated-batch',
      'entityType': 'products',
      'documentId': 'isolated-product',
      'operation': 'CREATE',
      'payloadJson': '{}',
      'readSetJson': '{}',
      'localRevision': 1,
      'createdAt': DateTime.utc(2026).toIso8601String(),
      'status': 'PENDING',
    });
    await source.db.insert('sync_queries', {
      'queryKey': 'catalogue-test-sentinel',
      'collectionName': 'units',
      'queryJson': '{"filters":[]}',
      'lastSyncedAt': '2026-01-01T00:00:00Z',
      'lastAttemptAt': '2026-01-02T00:00:00Z',
      'lastError': 'sentinel',
      'active': 1,
      'cursor': 'sentinel-cursor',
      'catalogueVersion': 'sentinel-release-token',
    });
    final queryBefore = await source.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: ['catalogue-test-sentinel'],
    );
    final changed = _clone(approvedRelease);
    final release = changed['product_catalogue_releases']!.single;
    final fields = FirestoreValueCodec.decodeFields(release['fields']);
    fields
      ..['version'] = 5
      ..['catalogueVersion'] = 5;
    release['fields'] = FirestoreValueCodec.encodeFields(fields);

    await expectLater(
      SystemCatalogueSnapshot.import(
        source: source,
        documents: changed,
        readTimes: const {},
        failureProbe: (stage, _) async {
          if (stage == 'product_categories')
            throw StateError('simulated interruption');
        },
      ),
      throwsA(isA<StateError>()),
    );
    final marker = await source.row('product_catalogue_releases', 'PAINT_V1');
    expect(
      FirestoreValueCodec.decodeFields(
        jsonDecode(marker!['payloadJson'] as String),
      )['version'],
      4,
    );
    expect(await source.db.query('sync_outbox'), hasLength(1));
    expect(
      await source.db.query(
        'sync_queries',
        where: 'queryKey=?',
        whereArgs: ['catalogue-test-sentinel'],
      ),
      queryBefore,
    );
  });

  test(
    'repeat import is idempotent and diagnostics redact secrets and PII',
    () async {
      final docs = _clone(approvedRelease);
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: docs,
        readTimes: const {},
      );
      final markerBefore = await source.row(
        'product_catalogue_releases',
        'PAINT_V1',
      );
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: _clone(approvedRelease),
        readTimes: const {},
      );
      final markerAfter = await source.row(
        'product_catalogue_releases',
        'PAINT_V1',
      );
      expect(markerAfter, markerBefore);

      final safe = EnvironmentConfig.redactDiagnosticText(
        'apiKey=secret-value key=AIza-secret user=person@example.com token=abcdefghijklmnopqrstuvwxyz0123456789 Bearer oauth-secret',
      );
      expect(safe, isNot(contains('secret-value')));
      expect(safe, isNot(contains('AIza-secret')));
      expect(safe, isNot(contains('oauth-secret')));
      expect(safe, isNot(contains('person@example.com')));
      expect(safe, isNot(contains('abcdefghijklmnopqrstuvwxyz0123456789')));
      expect(
        EnvironmentConfig.diagnostics().keys,
        isNot(contains('FIREBASE_API_KEY')),
      );
    },
  );
}

Future<Map<String, List<Map<String, dynamic>>>> _cachedSnapshot(
  LocalDataSource source,
) async {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final collection in release4Documents().keys) {
    result[collection] = await source.query(collection, const [
      FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
    ]);
  }
  result.putIfAbsent('brands', () => []);
  return result;
}

Map<String, dynamic> _document(String collection, Map<String, dynamic> fields) {
  final id = fields[CatalogueContract.idFields[collection]] as String;
  return {
    'name': '$collection/$id',
    'fields': FirestoreValueCodec.encodeFields(fields),
  };
}

Map<String, List<Map<String, dynamic>>> _approvedForTest(
  Map<String, List<Map<String, dynamic>>> documents,
) {
  final release = documents['product_catalogue_releases']!.single;
  final fields = FirestoreValueCodec.decodeFields(release['fields']);
  fields
    ..['isolatedOnly'] = false
    ..['approvedForLiveExecution'] = true
    ..['productionMigrationApproved'] = true
    ..['firestorePublicationApproved'] = true
    ..remove('contentFingerprint');
  release['fields'] = FirestoreValueCodec.encodeFields(fields);
  return documents;
}

Map<String, List<Map<String, dynamic>>> _clone(
  Map<String, List<Map<String, dynamic>>> value,
) => {
  for (final entry in value.entries)
    entry.key: [
      for (final document in entry.value)
        {
          'name': document['name'],
          'fields': FirestoreValueCodec.encodeFields(
            FirestoreValueCodec.decodeFields(document['fields']),
          ),
        },
    ],
};
