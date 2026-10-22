import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_fingerprint.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/catalogue_archive_store.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/historical_catalogue_resolver.dart';

import 'support/catalogue_import_fixture.dart';
import 'support/phase10e_release.dart';

const _ceilingDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _ceilingHistoricalPayloadId =
    'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _basementDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING';
const _basementHistoricalPayloadId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT';
const _liquidId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID';
const _cementitiousId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS';

Future<String> _fingerprint(LocalDataSource local) async {
  final documents = <String, List<Map<String, dynamic>>>{};
  for (final collection in CatalogueArchiveStore.collections) {
    final rows = await local.db.query(
      LocalDataSource.table(collection),
      where: "scopeType='SYSTEM' AND isDeleted=0",
      orderBy: 'remoteId',
    );
    documents[collection] = [
      for (final row in rows)
        {
          'name': '$collection/${row['remoteId']}',
          'fields': jsonDecode(row['payloadJson'] as String),
        },
    ];
  }
  final brandRows = await local.db.query(
    'local_brands',
    where: "scopeType='SYSTEM' AND isDeleted=0",
    orderBy: 'remoteId',
  );
  documents['brands'] = [
    for (final row in brandRows)
      {
        'name': 'brands/${row['remoteId']}',
        'fields': jsonDecode(row['payloadJson'] as String),
      },
  ];
  return CatalogueFingerprint.calculate(documents);
}

Future<void> _seedProduct(
  LocalDataSource local,
  String id, {
  String? fingerprint,
}) async {
  final fields = <String, dynamic>{
    'productId': id,
    'tenantId': 'FIXTURE-TENANT',
    'businessId': 'FIXTURE-BUSINESS',
    'productName': 'Raw saved $id',
    'categoryId': 'FIXTURE-CATEGORY',
    'subcategoryId': 'FIXTURE-SUBCATEGORY',
    'attributeValues': {'finish': 'Saved exactly'},
    'status': 'ACTIVE',
    ...?fingerprint == null ? null : {'catalogueFingerprint': fingerprint},
  };
  await local.upsertRemote('products', [
    {
      'name': 'products/$id',
      'fields': FirestoreRestService.encodeFields(fields),
      'updateTime': 'PRODUCT-$id',
    },
  ]);
}

Future<void> _seedVariant(
  LocalDataSource local,
  String id,
  String productId,
) async {
  await local.upsertRemote('product_variants', [
    {
      'name': 'product_variants/$id',
      'fields': FirestoreRestService.encodeFields({
        'variantId': id,
        'tenantId': 'FIXTURE-TENANT',
        'businessId': 'FIXTURE-BUSINESS',
        'productId': productId,
        'baseUnitId': 'FIXTURE-UNIT',
        'attributeValues': {'shade': 'Raw value'},
        'status': 'ACTIVE',
      }),
      'updateTime': 'VARIANT-$id',
    },
  ]);
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalDatabase database;
  late LocalDataSource local;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phase10g2-archive-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    local = LocalDataSource(await database.open('phase10g2', 'isolated'));
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  for (final stage in ['before_archive', 'archive_row_1', 'after_archive']) {
    test(
      'archive failure at $stage rolls back the entire Release 4 install',
      () async {
        final prior = {
          for (final entry in catalogueImportFixture().entries)
            entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
        };
        await SystemCatalogueSnapshot.import(
          source: local,
          documents: CatalogueContract.encode(prior),
          readTimes: const {'units': 'PREVIOUS-CURSOR'},
        );
        final beforeMarker = await local.db.query(
          LocalDataSource.table('product_catalogue_releases'),
        );
        final beforeUnits = await local.db.query(
          LocalDataSource.table('units'),
          orderBy: 'remoteId',
        );
        final sentinel = StateError('archive rollback checkpoint: $stage');
        var reached = false;
        await expectLater(
          SystemCatalogueSnapshot.import(
            source: local,
            documents: release4Documents(),
            readTimes: const {'units': 'FAILED-CURSOR'},
            allowUnapprovedIsolatedForTests: true,
            failureProbe: (actual, tx) async {
              if (actual == stage) {
                reached = true;
                throw sentinel;
              }
            },
          ),
          throwsA(same(sentinel)),
        );
        expect(reached, isTrue);
        expect(
          await local.db.query(
            LocalDataSource.table('product_catalogue_releases'),
          ),
          beforeMarker,
        );
        expect(
          await local.db.query(
            LocalDataSource.table('units'),
            orderBy: 'remoteId',
          ),
          beforeUnits,
        );
        expect(await local.db.query(CatalogueArchiveStore.table), isEmpty);
      },
    );
  }

  test(
    'archive key is immutable and identical upgrade replay is idempotent',
    () async {
      await CatalogueArchiveStore.createSchema(local.db);
      final fingerprint = 'sha256:${List.filled(64, 'e').join()}';
      final archive = CatalogueArchiveStore();
      await archive.archiveDocument(
        local.db,
        fingerprint: fingerprint,
        collection: 'units',
        documentId: 'UNIT-1',
        payloadId: 'UNIT-1',
        payloadJson: jsonEncode({'unitId': 'UNIT-1', 'name': 'Each'}),
      );
      await expectLater(
        archive.archiveDocument(
          local.db,
          fingerprint: fingerprint,
          collection: 'units',
          documentId: 'UNIT-1',
          payloadId: 'UNIT-1',
          payloadJson: jsonEncode({'unitId': 'UNIT-1', 'name': 'Piece'}),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Catalogue archive key collision'),
          ),
        ),
      );

      final prior = {
        for (final entry in catalogueImportFixture().entries)
          entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
      };
      await SystemCatalogueSnapshot.import(
        source: local,
        documents: CatalogueContract.encode(prior),
        readTimes: const {},
      );
      await SystemCatalogueSnapshot.import(
        source: local,
        documents: release4Documents(),
        readTimes: const {},
        allowUnapprovedIsolatedForTests: true,
      );
      final archivedCount = (await local.db.rawQuery(
        'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
      )).single['count'];
      await SystemCatalogueSnapshot.import(
        source: local,
        documents: release4Documents(),
        readTimes: const {},
        allowUnapprovedIsolatedForTests: true,
      );
      expect(
        (await local.db.rawQuery(
          'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
        )).single['count'],
        archivedCount,
      );
      final currentCeiling = await local.row(
        'product_subcategories',
        _ceilingDocumentId,
      );
      expect(currentCeiling, isNotNull);
      expect(
        await local.row('product_subcategories', _ceilingHistoricalPayloadId),
        isNull,
      );
    },
  );

  test('isolated v3-to-v4 install archives exact preimage and preserves all 11 owner payloads', () async {
    final v3Rows = {
      for (final entry in catalogueImportFixture().entries)
        entry.key: (entry.value as List).cast<Map<String, dynamic>>(),
    };
    final v3Documents = CatalogueContract.encode(v3Rows);
    await SystemCatalogueSnapshot.import(
      source: local,
      documents: v3Documents,
      readTimes: const {},
    );
    final oldFingerprint = await _fingerprint(local);
    expect(CatalogueFingerprint.isValid(oldFingerprint), isTrue);
    final markerBefore = FirestoreRestService.decodeFields(
      jsonDecode(
        (await local.row(
              'product_catalogue_releases',
              'PAINT_V1',
            ))!['payloadJson']
            as String,
      ),
    );
    expect(markerBefore['catalogueFingerprint'], oldFingerprint);

    final productIds = [
      'PROD-515E99F5F2C24423B75AEBFE81CB075A',
      'PROD-6198168F50EA48BB9209914A7A2003D2',
      'PROD-78125CD6E1864CA1AF4E3E71C915D025',
      'PROD-C446FD4E4DD349DAB46DDFEDA251915D',
    ];
    final variantIds = [
      'VAR-089A2A0AA0A14E45AEC89328F3A193E6',
      'VAR-233931D4CB8A432E8F2DC88912B59C48',
      'VAR-3F8DCEC102144603B4BFF7DF558ECFDF',
      'VAR-42F8F567B7F54AC9A653C5826B53344B',
      'VAR-808222B8F37A40138FE9416965A61F49',
      'VAR-CF94091746164266B8DA7863706991A0',
      'VAR-FE7BA134B0B94E058B21689F4DBB757B',
    ];
    for (var index = 0; index < productIds.length; index++) {
      await _seedProduct(
        local,
        productIds[index],
        fingerprint: index == 0 ? oldFingerprint : null,
      );
    }
    for (var index = 0; index < variantIds.length; index++) {
      await _seedVariant(
        local,
        variantIds[index],
        productIds[index % productIds.length],
      );
    }
    final productsBefore = await local.db.query(
      'local_products',
      orderBy: 'remoteId',
    );
    final variantsBefore = await local.db.query(
      'local_product_variants',
      orderBy: 'remoteId',
    );
    final syncQueriesBefore = await local.db.query(
      'sync_queries',
      orderBy: 'queryKey',
    );
    final outboxBefore = await local.db.query('sync_outbox', orderBy: 'id');

    await SystemCatalogueSnapshot.import(
      source: local,
      documents: release4Documents(),
      readTimes: const {},
      allowUnapprovedIsolatedForTests: true,
    );

    expect(
      await local.db.query('local_products', orderBy: 'remoteId'),
      productsBefore,
    );
    expect(
      await local.db.query('local_product_variants', orderBy: 'remoteId'),
      variantsBefore,
    );
    expect(
      await local.db.query('sync_queries', orderBy: 'queryKey'),
      syncQueriesBefore,
    );
    expect(await local.db.query('sync_outbox', orderBy: 'id'), outboxBefore);
    final archived = await local.db.query(
      CatalogueArchiveStore.table,
      where: 'catalogueFingerprint=?',
      whereArgs: [oldFingerprint],
    );
    expect(archived, isNotEmpty);
    expect(
      archived.every(
        (row) => CatalogueArchiveStore.collections.contains(row['collection']),
      ),
      isTrue,
    );
    expect(
      archived.where(
        (row) =>
            row['collection'] == 'products' ||
            row['collection'] == 'product_variants',
      ),
      isEmpty,
    );

    final currentMarker = FirestoreRestService.decodeFields(
      jsonDecode(
        (await local.row(
              'product_catalogue_releases',
              'PAINT_V1',
            ))!['payloadJson']
            as String,
      ),
    );
    final release4Fingerprint = currentMarker['catalogueFingerprint'] as String;
    expect(CatalogueFingerprint.isValid(release4Fingerprint), isTrue);
    expect(release4Fingerprint, isNot(oldFingerprint));
    final historicalProduct = ProductModel.fromData({
      ...FirestoreRestService.decodeFields(
        jsonDecode(
          productsBefore.firstWhere(
                (r) => r['remoteId'] == productIds.first,
              )['payloadJson']
              as String,
        ),
      ),
      'createdAt': DateTime.utc(2026),
      'updatedAt': DateTime.utc(2026),
    });
    expect(historicalProduct.catalogueFingerprint, oldFingerprint);
    expect(historicalProduct.toData()['catalogueFingerprint'], oldFingerprint);
    final resolver = HistoricalCatalogueResolver(local.db);
    final exact = await resolver.resolveProduct(
      historicalProduct.toData(),
      context: CatalogueResolutionContext.historical,
    );
    expect(exact.status, CatalogueResolutionStatus.exact);
    expect(
      exact.collections.keys,
      containsAll(CatalogueArchiveStore.collections),
    );
    final missing = await resolver.resolveProduct(
      ProductModel.fromData({'productId': 'NULL-PROVENANCE'}).toData(),
      context: CatalogueResolutionContext.readExisting,
    );
    expect(missing.status, CatalogueResolutionStatus.provenanceMissing);

    final legacyOwnerPayloads = [
      ...await local.db.query('local_products', orderBy: 'remoteId'),
      ...await local.db.query('local_product_variants', orderBy: 'remoteId'),
    ];
    expect(legacyOwnerPayloads, hasLength(11));
    expect(legacyOwnerPayloads, [...productsBefore, ...variantsBefore]);
  });

  test('legacy resolver returns exact Ceiling metadata by fingerprint and never ID-only fallback', () async {
    final archive = CatalogueArchiveStore();
    await CatalogueArchiveStore.createSchema(local.db);
    final oldFingerprint = 'sha256:${List.filled(64, 'a').join()}';
    final newFingerprint = 'sha256:${List.filled(64, 'b').join()}';
    final oldPayload = jsonEncode({
      'subcategoryId': _ceilingHistoricalPayloadId,
      'name': 'Historical Ceiling Paints',
    });
    final newPayload = jsonEncode({
      'subcategoryId': _ceilingDocumentId,
      'name': 'Release 4 Ceiling Paints',
    });
    await archive.archiveDocument(
      local.db,
      fingerprint: oldFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingHistoricalPayloadId,
      payloadJson: oldPayload,
    );
    await archive.archiveDocument(
      local.db,
      fingerprint: newFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingDocumentId,
      payloadJson: newPayload,
    );
    final resolver = HistoricalCatalogueResolver(local.db);
    final old = await resolver.resolveDocument(
      fingerprint: oldFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      context: CatalogueResolutionContext.historical,
    );
    final current = await resolver.resolveDocument(
      fingerprint: newFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      context: CatalogueResolutionContext.historical,
    );
    final missing = await resolver.resolveDocument(
      fingerprint: null,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      context: CatalogueResolutionContext.readExisting,
    );
    expect(old.status, CatalogueResolutionStatus.exact);
    expect(
      old.collections['product_subcategories']!.single['payloadId'],
      _ceilingHistoricalPayloadId,
    );
    expect(
      current.collections['product_subcategories']!.single['payloadId'],
      _ceilingDocumentId,
    );
    expect(missing.status, CatalogueResolutionStatus.provenanceMissing);
  });

  test('Basement remains historical and cannot resolve to either Release 4 split identity', () async {
    final archive = CatalogueArchiveStore();
    await CatalogueArchiveStore.createSchema(local.db);
    final oldFingerprint = 'sha256:${List.filled(64, 'c').join()}';
    final newFingerprint = 'sha256:${List.filled(64, 'd').join()}';
    await archive.archiveDocument(
      local.db,
      fingerprint: oldFingerprint,
      collection: 'product_subcategories',
      documentId: _basementDocumentId,
      payloadId: _basementHistoricalPayloadId,
      payloadJson: jsonEncode({
        'subcategoryId': _basementHistoricalPayloadId,
        'name': 'Basement Waterproofing',
      }),
    );
    for (final id in [_liquidId, _cementitiousId]) {
      await archive.archiveDocument(
        local.db,
        fingerprint: newFingerprint,
        collection: 'product_subcategories',
        documentId: id,
        payloadId: id,
        payloadJson: jsonEncode({'subcategoryId': id, 'name': id}),
      );
    }
    final resolver = HistoricalCatalogueResolver(local.db);
    final legacy = await resolver.resolveDocument(
      fingerprint: oldFingerprint,
      collection: 'product_subcategories',
      documentId: _basementDocumentId,
      context: CatalogueResolutionContext.historical,
    );
    final wronglyRetagged = await resolver.resolveDocument(
      fingerprint: newFingerprint,
      collection: 'product_subcategories',
      documentId: _basementDocumentId,
      context: CatalogueResolutionContext.historical,
    );
    expect(
      legacy.collections['product_subcategories']!.single['payloadId'],
      _basementHistoricalPayloadId,
    );
    expect(wronglyRetagged.status, CatalogueResolutionStatus.archiveNotFound);
  });
}
