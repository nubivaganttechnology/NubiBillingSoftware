import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'support/phase10hb_provenance_proof.dart';

const _ceilingDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _ceilingHistoricalPayloadId =
    'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _basementDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING';
const _basementHistoricalPayloadId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT';
const _basementLiquidId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID';
const _basementCementitiousId =
    'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS';

class _NoNetworkRemote extends FirestoreRestService {
  _NoNetworkRemote() : super(ApiClient());
  int calls = 0;
  Never _forbidden() {
    calls++;
    throw StateError('Firestore/network access is forbidden in this proof.');
  }

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async => _forbidden();

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async => _forbidden();

  @override
  Future<FirestoreSyncPage> readSyncPage({
    required String collection,
    required List<FirestoreFilter> filters,
    required String queryId,
    required String reason,
    String? cursor,
    String? readTime,
    Map<String, dynamic>? after,
    int pageSize = 200,
    String? idToken,
  }) async => _forbidden();

  @override
  Future<void> commitAtomicWrites(
    List<FirestoreWrite> writes, {
    String? idToken,
  }) async => _forbidden();
}

class _OfflineConnectivity extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String _token(String uid) {
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'sub': uid,
        'aud': EnvironmentConfig.projectId,
        'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
      }),
    ),
  );
  return 'header.$payload.signature';
}

AuthSession _session(String uid) => AuthSession(
  idToken: _token(uid),
  refreshToken: 'unused-test-value',
  uid: uid,
  email: 'proof@example.invalid',
  expiresAt: DateTime.now().add(const Duration(days: 1)),
);

Map<String, dynamic> _snapshot({
  String categoryName = 'Interior Wall Coatings',
  String defaultValue = 'Ceiling',
  String option = 'Ceiling',
  String unit = 'Litre',
  String status = 'ACTIVE',
  String payloadId = _ceilingHistoricalPayloadId,
  String documentId = _ceilingDocumentId,
}) => {
  'documentId': documentId,
  'fields': {
    'subcategoryId': payloadId,
    'name': categoryName,
    'status': status,
    'defaultValue': defaultValue,
    'options': [option],
    'allowedUnits': [unit],
  },
};

Future<void> _seedDocument(
  LocalDataSource local,
  String collection,
  String id,
  Map<String, dynamic> fields,
) async {
  await local.upsertRemote(collection, [
    {
      'name': '$collection/$id',
      'fields': FirestoreRestService.encodeFields(fields),
      'updateTime': 'TEST-INITIAL',
    },
  ]);
}

Future<Map<String, Object?>> _disposableState(Database db) async {
  final schema = await db.rawQuery(
    "SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name",
  );
  final state = <String, Object?>{'sqlite_master': schema};
  for (final table in [
    'local_product_catalogue_releases',
    'local_products',
    'local_product_variants',
    'sync_outbox',
    'sync_queries',
  ]) {
    state[table] = await db.query(table, orderBy: table == 'sync_outbox' ? 'id' : null);
  }
  return state;
}

Future<void> _seedRollbackPreimage(LocalDatabase database) async {
  final db = await database.open(EnvironmentConfig.projectId, 'rollback-proof');
  final local = LocalDataSource(db);
  await _seedDocument(local, 'product_catalogue_releases', 'TEST-RELEASE', {
    'releaseId': 'TEST-RELEASE',
    'catalogueVersion': 1,
    'status': 'ACTIVE',
  });
  await _seedDocument(local, 'products', 'PRODUCT-PREIMAGE', {
    'productId': 'PRODUCT-PREIMAGE',
    'tenantId': 'TENANT',
    'businessId': 'BUSINESS',
    'name': 'Preimage Product',
    'catalogueFingerprint': 'sha256:${List.filled(64, 'a').join()}',
  });
  await _seedDocument(local, 'product_variants', 'VARIANT-PREIMAGE', {
    'variantId': 'VARIANT-PREIMAGE',
    'productId': 'PRODUCT-PREIMAGE',
    'tenantId': 'TENANT',
    'businessId': 'BUSINESS',
  });
  await db.insert('sync_outbox', {
    'batchId': 'PREIMAGE-BATCH',
    'entityType': 'products',
    'documentId': 'PRODUCT-PREIMAGE',
    'operation': 'CREATE',
    'payloadJson': '{"preimage":true}',
    'readSetJson': '{}',
    'localRevision': 1,
    'createdAt': '2026-10-05T00:00:00Z',
  });
  await db.insert('sync_queries', {
    'queryKey': 'protected-products-query',
    'collectionName': 'products',
    'queryJson': '{}',
    'active': 1,
  });
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalDatabase database;
  late Database db;
  late _NoNetworkRemote remote;
  late _OfflineConnectivity connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  const uid = 'phase10hb-test-user';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('phase10hb-proof-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: directory.path);
    db = await database.open(EnvironmentConfig.projectId, uid);
    remote = _NoNetworkRemote();
    connectivity = _OfflineConnectivity()..available = false;
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => _session(uid),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate(uid);
  });

  tearDown(() async {
    service.logout();
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  test('snapshot fingerprint is deterministic across collection, document and map order', () {
    final left = {
      'units': [
        {'documentId': 'U2', 'fields': {'unitId': 'U2', 'name': 'Litre'}},
        {'documentId': 'U1', 'fields': {'name': 'Piece', 'unitId': 'U1'}},
      ],
      'product_subcategories': [_snapshot()],
    };
    final right = {
      'product_subcategories': [
        {'documentId': _ceilingDocumentId, 'fields': {
          'allowedUnits': ['Litre'],
          'options': ['Ceiling'],
          'defaultValue': 'Ceiling',
          'status': 'ACTIVE',
          'name': 'Interior Wall Coatings',
          'subcategoryId': _ceilingHistoricalPayloadId,
        }},
      ],
      'units': [
        {'documentId': 'U1', 'fields': {'unitId': 'U1', 'name': 'Piece'}},
        {'documentId': 'U2', 'fields': {'name': 'Litre', 'unitId': 'U2'}},
      ],
    };
    expect(catalogueSnapshotFingerprint(left), catalogueSnapshotFingerprint(right));
    expect(catalogueSnapshotFingerprint(left), matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
  });

  for (final change in [
    ('semantic name', _snapshot(categoryName: 'Ceiling Coatings')),
    ('template default', _snapshot(defaultValue: 'Wall')),
    ('option', _snapshot(option: 'Roof')),
    ('unit rule', _snapshot(unit: 'Kilogram')),
    ('status', _snapshot(status: 'INACTIVE')),
    ('payload identity', _snapshot(payloadId: 'OTHER-PAYLOAD-ID')),
    ('document identity', _snapshot(documentId: 'OTHER-DOCUMENT-ID')),
  ]) {
    test('snapshot fingerprint changes for ${change.$1}', () {
      final baseline = {'product_subcategories': [_snapshot()]};
      final changed = {
        'product_subcategories': [change.$2],
      };
      expect(
        catalogueSnapshotFingerprint(changed),
        isNot(catalogueSnapshotFingerprint(baseline)),
      );
    });
  }

  test('snapshot fingerprint excludes local bookkeeping and its own field', () {
    final a = {
      'product_subcategories': [
        {
          ..._snapshot(),
          'fields': {
            ...(_snapshot()['fields'] as Map<String, dynamic>),
            'catalogueFingerprint': 'ignored-self-reference',
            '_syncMutationId': 'MUTATION-A',
            'localRevision': 1,
          },
        },
      ],
    };
    final b = {
      'product_subcategories': [
        {
          ..._snapshot(),
          'fields': {
            ...(_snapshot()['fields'] as Map<String, dynamic>),
            'catalogueFingerprint': 'ignored-other-self-reference',
            '_syncMutationId': 'MUTATION-B',
            'localRevision': 99,
          },
        },
      ],
    };
    expect(catalogueSnapshotFingerprint(a), catalogueSnapshotFingerprint(b));
  });

  test('Product payload supports nullable provenance and old payloads decode null', () {
    final fingerprint = catalogueSnapshotFingerprint({
      'product_categories': [
        {'documentId': 'C', 'fields': {'categoryId': 'C', 'name': 'Paint'}},
      ],
    });
    final currentPayload = {
      'productId': 'P1',
      'catalogueFingerprint': fingerprint,
      'name': 'New Product',
    };
    final roundTrip = Map<String, dynamic>.from(jsonDecode(jsonEncode(currentPayload)) as Map);
    expect(roundTrip['catalogueFingerprint'], fingerprint);

    final legacyPayload = Map<String, dynamic>.from(
      jsonDecode(jsonEncode({'productId': 'P0', 'name': 'Legacy'})) as Map,
    );
    expect(legacyPayload['catalogueFingerprint'] as String?, isNull);
    expect(resolveProductProvenance(legacyPayload).status, 'PROVENANCE_MISSING');
  });

  test('Variant inherits exact Product provenance and orphan fails closed', () {
    final fingerprint = 'sha256:${List.filled(64, 'b').join()}';
    final products = {
      'P1': {'productId': 'P1', 'catalogueFingerprint': fingerprint},
    };
    final resolved = resolveVariantParent({'variantId': 'V1', 'productId': 'P1'}, products);
    expect(resolved.status, 'EXACT');
    expect(resolved.payloadId, fingerprint);
    expect(
      resolveVariantParent({'variantId': 'V2', 'productId': 'MISSING'}, products).status,
      'PROVENANCE_MISSING',
    );
    expect(
      resolveVariantParent({'variantId': 'V3', 'productId': 'P1'}, {}).status,
      'PROVENANCE_MISSING',
    );
  });

  test('archive same-key same-content is idempotent and different content collides', () async {
    await createDisposableArchiveSchema(db);
    final fingerprint = catalogueSnapshotFingerprint({'units': [_snapshot(documentId: 'U')]});
    final payload = {'unitId': 'U', 'name': 'Litre', 'status': 'ACTIVE'};
    expect(await archiveSnapshotDocument(
      db,
      fingerprint: fingerprint,
      collection: 'units',
      documentId: 'U',
      payloadId: 'U',
      payload: payload,
    ), isTrue);
    expect(await archiveSnapshotDocument(
      db,
      fingerprint: fingerprint,
      collection: 'units',
      documentId: 'U',
      payloadId: 'U',
      payload: {'status': 'ACTIVE', 'name': 'Litre', 'unitId': 'U'},
    ), isFalse);
    expect(await db.query('phase10hb_catalogue_archive'), hasLength(1));
    await expectLater(
      archiveSnapshotDocument(
        db,
        fingerprint: fingerprint,
        collection: 'units',
        documentId: 'U',
        payloadId: 'U',
        payload: {'unitId': 'U', 'name': 'Millilitre', 'status': 'ACTIVE'},
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('phase10hb_catalogue_archive'), hasLength(1));
  });

  test('archive preserves document ID and payload identity independently', () async {
    await createDisposableArchiveSchema(db);
    final fingerprint = 'sha256:${List.filled(64, 'c').join()}';
    final payload = {
      'subcategoryId': _ceilingHistoricalPayloadId,
      'name': 'Ceiling Paints',
    };
    await archiveSnapshotDocument(
      db,
      fingerprint: fingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingHistoricalPayloadId,
      payload: payload,
    );
    final row = (await db.query('phase10hb_catalogue_archive')).single;
    expect(row['documentId'], _ceilingDocumentId);
    expect(row['payloadId'], _ceilingHistoricalPayloadId);
    expect(jsonDecode(row['payloadJson'] as String), payload);
  });

  test('atomic Product, Variants and outbox carry one fingerprint; failure rolls back all', () async {
    final fingerprint = 'sha256:${List.filled(64, 'd').join()}';
    final local = LocalDataSource(db);
    await _seedDocument(local, 'product_catalogue_releases', 'INSTALLED-PROOF-RELEASE', {
      'releaseId': 'INSTALLED-PROOF-RELEASE',
      'catalogueVersion': 77,
      'installed': true,
      'catalogueFingerprint': fingerprint,
      'status': 'ACTIVE',
    });
    final installedMarker = FirestoreRestService.decodeFields(
      jsonDecode((await local.row('product_catalogue_releases', 'INSTALLED-PROOF-RELEASE'))!['payloadJson'] as String),
    );
    final installedFingerprint = installedMarker['catalogueFingerprint'] as String;
    expect(installedFingerprint, fingerprint);
    final product = {
      'productId': 'ATOMIC-PRODUCT',
      'tenantId': 'TENANT',
      'businessId': 'BUSINESS',
      'name': 'Proof Product',
      'categoryId': 'CAT',
      'subcategoryId': 'SUB',
      'catalogueFingerprint': installedFingerprint,
    };
    final variant = {
      'variantId': 'ATOMIC-VARIANT',
      'productId': 'ATOMIC-PRODUCT',
      'tenantId': 'TENANT',
      'businessId': 'BUSINESS',
      'baseUnitId': 'UNIT',
    };
    await service.runAtomicOperation((tx) async {
      tx.create('products', 'ATOMIC-PRODUCT', product);
      tx.create('product_variants', 'ATOMIC-VARIANT', variant);
    }, idToken: _token(uid));

    final productRow = (await db.query('local_products', where: 'remoteId=?', whereArgs: ['ATOMIC-PRODUCT'])).single;
    final storedProduct = FirestoreRestService.decodeFields(jsonDecode(productRow['payloadJson'] as String));
    expect(storedProduct['catalogueFingerprint'], fingerprint);
    final variantRow = (await db.query('local_product_variants', where: 'remoteId=?', whereArgs: ['ATOMIC-VARIANT'])).single;
    final storedVariant = FirestoreRestService.decodeFields(jsonDecode(variantRow['payloadJson'] as String));
    expect(storedVariant.containsKey('catalogueFingerprint'), isFalse);
    expect(storedVariant['productId'], 'ATOMIC-PRODUCT');
    final outbox = await db.query('sync_outbox', orderBy: 'id');
    expect(outbox, hasLength(2));
    final productWrite = outbox.singleWhere((row) => row['documentId'] == 'ATOMIC-PRODUCT');
    final productOutboxPayload = jsonDecode(productWrite['payloadJson'] as String) as Map;
    final productOutboxFields = FirestoreRestService.decodeFields(productOutboxPayload['fields']);
    expect(productOutboxFields['catalogueFingerprint'], fingerprint);
    expect(remote.calls, 0);

    await db.execute('''
      CREATE TEMP TRIGGER phase10hb_fail_variant_outbox
      BEFORE INSERT ON sync_outbox
      WHEN NEW.documentId = 'ROLLBACK-VARIANT'
      BEGIN SELECT RAISE(ABORT, 'injected variant outbox failure'); END
    ''');
    final productsBeforeFailure = await db.query('local_products', orderBy: 'remoteId');
    final variantsBeforeFailure = await db.query('local_product_variants', orderBy: 'remoteId');
    final outboxBeforeFailure = await db.query('sync_outbox', orderBy: 'id');
    await expectLater(
      service.runAtomicOperation((tx) async {
        tx.create('products', 'ROLLBACK-PRODUCT', {
          ...product,
          'productId': 'ROLLBACK-PRODUCT',
          'catalogueFingerprint': 'sha256:${List.filled(64, 'e').join()}',
        });
        tx.create('product_variants', 'ROLLBACK-VARIANT', {
          ...variant,
          'variantId': 'ROLLBACK-VARIANT',
          'productId': 'ROLLBACK-PRODUCT',
        });
      }, idToken: _token(uid)),
      throwsA(anything),
    );
    expect(await db.query('local_products', orderBy: 'remoteId'), productsBeforeFailure);
    expect(await db.query('local_product_variants', orderBy: 'remoteId'), variantsBeforeFailure);
    expect(await db.query('sync_outbox', orderBy: 'id'), outboxBeforeFailure);
    await db.execute('DROP TRIGGER phase10hb_fail_variant_outbox');
    expect(remote.calls, 0);
  });

  test('normal Product edit and classification patch preserve provenance', () async {
    final fingerprint = 'sha256:${List.filled(64, 'f').join()}';
    await service.runAtomicOperation((tx) async {
      tx.create('products', 'EDIT-PRODUCT', {
      'productId': 'P1',
      'tenantId': 'TENANT',
      'businessId': 'BUSINESS',
      'name': 'Old name',
      'categoryId': 'OLD-CATEGORY',
      'subcategoryId': 'OLD-SUBCATEGORY',
      'catalogueFingerprint': fingerprint,
      });
    }, idToken: _token(uid));
    await service.updateDocument('products', 'EDIT-PRODUCT', {
      'name': 'Renamed',
    }, idToken: _token(uid));
    await service.updateDocument('products', 'EDIT-PRODUCT', {
      'categoryId': 'NEW-CATEGORY',
      'subcategoryId': 'NEW-SUBCATEGORY',
    }, idToken: _token(uid));
    final updated = FirestoreRestService.decodeFields(
      jsonDecode((await db.query('local_products', where: 'remoteId=?', whereArgs: ['EDIT-PRODUCT'])).single['payloadJson'] as String),
    );
    expect(updated['name'], 'Renamed');
    expect(updated['categoryId'], 'NEW-CATEGORY');
    expect(updated['subcategoryId'], 'NEW-SUBCATEGORY');
    expect(updated['catalogueFingerprint'], fingerprint);
  });

  test('missing provenance fails closed without current-ID, name or timestamp fallback', () async {
    await createDisposableArchiveSchema(db);
    final currentFingerprint = 'sha256:${List.filled(64, '1').join()}';
    await archiveSnapshotDocument(
      db,
      fingerprint: currentFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingDocumentId,
      payload: {'subcategoryId': _ceilingDocumentId, 'name': 'Current Ceiling'},
    );
    final legacy = {
      'subcategoryId': _ceilingDocumentId,
      'name': 'Current Ceiling',
      'createdAt': '2026-10-03T00:00:00Z',
    };
    expect(resolveProductProvenance(legacy).status, 'PROVENANCE_MISSING');
    expect(await resolveArchivedDocument(
      db,
      fingerprint: null,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
    ).then((result) => result.status), 'PROVENANCE_MISSING');
  });

  test('Ceiling ID-only lookup is ambiguous; exact fingerprint selects each snapshot', () async {
    await createDisposableArchiveSchema(db);
    final historicalSnapshot = {'product_subcategories': [_snapshot()]};
    final release4Snapshot = {
      'product_subcategories': [
        _snapshot(
          categoryName: 'Ceiling Paints',
          payloadId: _ceilingDocumentId,
        ),
      ],
    };
    final historicalFingerprint = catalogueSnapshotFingerprint(historicalSnapshot);
    final release4Fingerprint = catalogueSnapshotFingerprint(release4Snapshot);
    expect(historicalFingerprint, isNot(release4Fingerprint));
    await archiveSnapshotDocument(
      db,
      fingerprint: historicalFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingHistoricalPayloadId,
      payload: (_snapshot()['fields'] as Map).cast<String, dynamic>(),
    );
    await archiveSnapshotDocument(
      db,
      fingerprint: release4Fingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
      payloadId: _ceilingDocumentId,
      payload: (_snapshot(categoryName: 'Ceiling Paints', payloadId: _ceilingDocumentId)['fields'] as Map).cast<String, dynamic>(),
    );
    expect(await db.query(
      'phase10hb_catalogue_archive',
      where: 'collection=? AND documentId=?',
      whereArgs: ['product_subcategories', _ceilingDocumentId],
    ), hasLength(2));
    final oldResolution = await resolveArchivedDocument(
      db,
      fingerprint: historicalFingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
    );
    final newResolution = await resolveArchivedDocument(
      db,
      fingerprint: release4Fingerprint,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
    );
    expect(oldResolution.status, 'EXACT');
    expect(oldResolution.payloadId, _ceilingHistoricalPayloadId);
    expect(oldResolution.payload!['subcategoryId'], _ceilingHistoricalPayloadId);
    expect(newResolution.status, 'EXACT');
    expect(newResolution.payloadId, _ceilingDocumentId);
    expect(newResolution.payload!['name'], 'Ceiling Paints');
    expect((await resolveArchivedDocument(
      db,
      fingerprint: null,
      collection: 'product_subcategories',
      documentId: _ceilingDocumentId,
    )).status, 'PROVENANCE_MISSING');
  });

  test('Basement legacy identity never maps to Release 4 Liquid or Cementitious', () async {
    await createDisposableArchiveSchema(db);
    final releaseFingerprint = catalogueSnapshotFingerprint({
      'product_subcategories': [
        {'documentId': _basementLiquidId, 'fields': {'subcategoryId': _basementLiquidId, 'name': 'Basement Liquid'}},
        {'documentId': _basementCementitiousId, 'fields': {'subcategoryId': _basementCementitiousId, 'name': 'Basement Cementitious'}},
      ],
    });
    await archiveSnapshotDocument(
      db,
      fingerprint: releaseFingerprint,
      collection: 'product_subcategories',
      documentId: _basementLiquidId,
      payloadId: _basementLiquidId,
      payload: {'subcategoryId': _basementLiquidId, 'name': 'Basement Liquid'},
    );
    await archiveSnapshotDocument(
      db,
      fingerprint: releaseFingerprint,
      collection: 'product_subcategories',
      documentId: _basementCementitiousId,
      payloadId: _basementCementitiousId,
      payload: {'subcategoryId': _basementCementitiousId, 'name': 'Basement Cementitious'},
    );
    final oldNull = await resolveArchivedDocument(
      db,
      fingerprint: null,
      collection: 'product_subcategories',
      documentId: _basementDocumentId,
    );
    final oldWithReleaseFingerprint = await resolveArchivedDocument(
      db,
      fingerprint: releaseFingerprint,
      collection: 'product_subcategories',
      documentId: _basementDocumentId,
    );
    expect(oldNull.status, 'PROVENANCE_MISSING');
    expect(oldWithReleaseFingerprint.status, 'ARCHIVE_ENTRY_MISSING');
    expect((await resolveArchivedDocument(
      db,
      fingerprint: releaseFingerprint,
      collection: 'product_subcategories',
      documentId: _basementLiquidId,
    )).payloadId, _basementLiquidId);
    expect((await resolveArchivedDocument(
      db,
      fingerprint: releaseFingerprint,
      collection: 'product_subcategories',
      documentId: _basementCementitiousId,
    )).payloadId, _basementCementitiousId);
    expect(_basementHistoricalPayloadId, isNot(_basementLiquidId));
    expect(_basementHistoricalPayloadId, isNot(_basementCementitiousId));
  });

  test('Phase 10H inventory remains 0 EXACT, 0 AMBIGUOUS, 11 UNRESOLVED and no proposals', () {
    final evidence = jsonDecode(File('docs/phase10h-backfill-feasibility.json').readAsStringSync()) as Map<String, dynamic>;
    final records = (evidence['records'] as List).cast<Map<String, dynamic>>();
    final states = records.map((record) {
      // The inventory carries no per-record exact fingerprint or archived
      // snapshot key; do not use IDs, names, candidate lists or timestamps.
      final savedFingerprint = record['catalogueFingerprint'];
      return isCatalogueFingerprint(savedFingerprint) ? 'EXACT' : 'UNRESOLVED';
    }).toList();
    expect(records, hasLength(11));
    expect(states.where((state) => state == 'EXACT'), isEmpty);
    expect(states.where((state) => state == 'AMBIGUOUS'), isEmpty);
    expect(states.where((state) => state == 'UNRESOLVED'), hasLength(11));
    expect(records.every((record) => record['backfillState'] == 'UNRESOLVED'), isTrue);
    expect((evidence['classificationCounts'] as Map)['automaticProposals'], 0);
  });

  for (final failureStage in ['after-schema', 'after-archive-insert', 'before-commit']) {
    test('disposable archive transaction rollback at $failureStage restores full preimage', () async {
      final rollbackDirectory = await Directory.systemTemp.createTemp('phase10hb-rollback-');
      final rollbackDatabase = LocalDatabase(factory: databaseFactoryFfi, directory: rollbackDirectory.path);
      addTearDown(() async {
        await rollbackDatabase.close();
        await rollbackDirectory.delete(recursive: true);
      });
      await _seedRollbackPreimage(rollbackDatabase);
      final rollbackDb = await rollbackDatabase.open(EnvironmentConfig.projectId, 'rollback-proof');
      final before = await _disposableState(rollbackDb);
      final fingerprint = 'sha256:${List.filled(64, '9').join()}';
      await expectLater(
        rollbackDb.transaction((tx) async {
          await createDisposableArchiveSchema(tx);
          if (failureStage == 'after-schema') throw StateError('injected after schema creation');
          await archiveSnapshotDocument(
            tx,
            fingerprint: fingerprint,
            collection: 'product_subcategories',
            documentId: _ceilingDocumentId,
            payloadId: _ceilingHistoricalPayloadId,
            payload: {'subcategoryId': _ceilingHistoricalPayloadId, 'status': 'ACTIVE'},
          );
          if (failureStage == 'after-archive-insert') throw StateError('injected after archive insert');
          await tx.update(
            'local_product_catalogue_releases',
            {'payloadJson': jsonEncode({'releaseId': 'TEST-RELEASE', 'catalogueVersion': 2})},
            where: 'remoteId=?',
            whereArgs: ['TEST-RELEASE'],
          );
          if (failureStage == 'before-commit') throw StateError('injected before commit');
        }),
        throwsA(isA<StateError>()),
      );
      expect(await _disposableState(rollbackDb), before);
      expect(remote.calls, 0);
    });
  }

  test('disposable schema creation and identical archive transaction replay are idempotent', () async {
    final fingerprint = 'sha256:${List.filled(64, '8').join()}';
    Future<void> apply() => db.transaction((tx) async {
      await createDisposableArchiveSchema(tx);
      await archiveSnapshotDocument(
        tx,
        fingerprint: fingerprint,
        collection: 'product_subcategories',
        documentId: _ceilingDocumentId,
        payloadId: _ceilingHistoricalPayloadId,
        payload: {'subcategoryId': _ceilingHistoricalPayloadId, 'status': 'ACTIVE'},
      );
    });
    await apply();
    final once = await _disposableState(db);
    final archivedOnce = await db.query('phase10hb_catalogue_archive');
    await apply();
    final twice = await _disposableState(db);
    final archivedRows = await db.query('phase10hb_catalogue_archive');
    expect(archivedRows, hasLength(1));
    expect((twice['sqlite_master'] as List).where((row) => (row as Map)['name'] == 'phase10hb_catalogue_archive'), hasLength(1));
    expect(archivedRows, equals(archivedOnce));
    expect(twice['local_products'], equals(once['local_products']));
    expect(remote.calls, 0);
  });
}
