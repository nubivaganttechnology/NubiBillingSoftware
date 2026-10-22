import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/catalogue/central_product_master_contract.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/repositories/storage_repository.dart';
import 'package:testflutter/data/models/storage_location_model.dart';
import 'package:testflutter/data/repositories/purchase_repository.dart';
import 'package:testflutter/data/repositories/supplier_repository.dart';
import 'package:testflutter/data/repositories/staff_salary_repository.dart';
import 'package:testflutter/data/models/purchase_bill_model.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';

import 'support/product_test_catalogue.dart';

class FakeRemote extends FirestoreRestService {
  FakeRemote() : super(ApiClient());
  final docs = <String, Map<String, dynamic>>{};
  bool offline = false,
      loseAcknowledgement = false,
      quota = false,
      denied = false;
  int returnedDocuments = 0;
  String? failAfter;
  final pullReasons = <String>[];
  int commits = 0, reads = 0, queries = 0, clock = 0;
  void check() {
    if (denied) {
      throw const AppException('Permission denied.', code: 'permission-denied');
    }
    if (quota) throw const AppException('Quota exceeded.', code: '429');
    if (offline) throw const AppException('Offline', code: 'network');
  }

  void seed(String collection, String id, Map<String, dynamic> fields) {
    docs['$collection/$id'] = {
      'name': '$collection/$id',
      'fields': FirestoreRestService.encodeFields({
        'updatedAt': DateTime.now().toUtc(),
        ...fields,
      }),
      'updateTime': 'VERSION-${++clock}',
    };
  }

  @override
  Future<Map<String, dynamic>> getDocument(
    String c,
    String id, {
    String? idToken,
  }) async {
    reads++;
    check();
    final doc = docs['$c/$id'];
    if (doc == null) throw const AppException('Missing', code: 'not-found');
    return Map.of(doc);
  }

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    queries++;
    check();
    return docs.entries
        .where(
          (e) =>
              e.key.startsWith('$collection/') &&
              filters.every(
                (f) => LocalDataSource.matches(
                  FirestoreRestService.decodeFields(e.value['fields'])[f.field],
                  f,
                ),
              ),
        )
        .map((e) => Map<String, dynamic>.of(e.value))
        .toList();
  }

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
  }) async {
    pullReasons.add(reason);
    if (after != null && failAfter == collection) {
      throw const AppException('Page failed', code: 'network');
    }
    if (collection == CentralProductMasterContract.collection &&
        !docs.keys.any((key) => key.startsWith('$collection/'))) {
      final previousId = (after?['name'] as String?)?.split('/').last;
      final start = previousId == null
          ? 0
          : int.parse(previousId.substring('TEST-CENTRAL-'.length)) + 1;
      final products = [
        for (
          var index = start;
          index < CentralProductMasterContract.expectedDocumentCount &&
              index < start + pageSize;
          index++
        )
          () {
            final id = 'TEST-CENTRAL-${index.toString().padLeft(4, '0')}';
            return {
              'name': '$collection/$id',
              'fields': FirestoreRestService.encodeFields({
                'masterProductId': id,
                'productName': 'Fixture Product $index',
                'normalizedProductName': 'fixture product $index',
                'businessTypeId': 'BT-HARDWARE',
                'businessTypeName': 'Hardware',
                'businessSubTypeId': 'BST-PAINTS',
                'businessSubTypeName': 'Paints',
                'brandId': 'BRAND-$index',
                'brandName': 'Fixture Brand $index',
                'categoryId': 'CATEGORY',
                'categoryName': 'Category',
                'subcategoryId': 'SUBCATEGORY',
                'subcategoryName': 'Subcategory',
                'scopeType': 'SYSTEM',
                'status': 'ACTIVE',
                'isActive': true,
              }),
              'updateTime': 'VERSION-${index + 1}',
            };
          }(),
      ];
      queries++;
      return FirestoreSyncPage(
        products,
        readTime ?? DateTime.now().toUtc().toIso8601String(),
      );
    }
    final all = await queryDocuments(
      collection: collection,
      filters: [
        ...filters,
        if (cursor != null)
          FirestoreFilter(
            'updatedAt',
            'GREATER_THAN_OR_EQUAL',
            DateTime.parse(cursor).subtract(const Duration(seconds: 2)),
          ),
      ],
      idToken: idToken,
    );
    int compare(Map<String, dynamic> a, Map<String, dynamic> b) {
      if (cursor != null) {
        final t =
            (FirestoreRestService.decodeFields(a['fields'])['updatedAt']
                    as DateTime)
                .compareTo(
                  FirestoreRestService.decodeFields(b['fields'])['updatedAt']
                      as DateTime,
                );
        if (t != 0) return t;
      }
      return (a['name'] as String).compareTo(b['name'] as String);
    }

    all.sort(compare);
    final page = all
        .where((d) => after == null || compare(d, after) > 0)
        .take(pageSize)
        .toList();
    returnedDocuments += page.length;
    return FirestoreSyncPage(
      page,
      readTime ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> commitAtomicWrites(
    List<FirestoreWrite> writes, {
    String? idToken,
  }) async {
    check();
    for (final w in writes) {
      final doc = docs['${w.collection}/${w.id}'];
      if (w.kind == FirestoreWriteKind.create
          ? doc != null
          : doc?['updateTime'] != w.updateTime) {
        throw const AppException('Precondition', code: '409');
      }
    }
    commits++;
    for (final w in writes) {
      final key = '${w.collection}/${w.id}';
      if (w.kind == FirestoreWriteKind.delete) {
        docs.remove(key);
      } else {
        final existing = docs[key];
        final fields = existing == null
            ? <String, dynamic>{}
            : FirestoreRestService.decodeFields(existing['fields']);
        seed(w.collection, w.id, {
          ...fields,
          ...w.fields!,
          'updatedAt': DateTime.now().toUtc(),
        });
      }
    }
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw const AppException('Response lost', code: 'network');
    }
  }
}

class TestConnectivity extends ConnectivityService {
  void Function(bool)? callback;
  @override
  Future<void> start(void Function(bool) onChange) async {
    callback = onChange;
  }

  void reconnect() {
    available = true;
    callback?.call(true);
  }
}

String token(String uid) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': '', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.signature';
AuthSession session(String uid) => AuthSession(
  idToken: token(uid),
  refreshToken: 'SECRET',
  uid: uid,
  email: 'test@example.com',
  expiresAt: DateTime.now().add(const Duration(days: 1)),
);

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late FakeRemote remote;
  late ConnectivityService connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nubibill-sync-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    remote = FakeRemote();
    connectivity = TestConnectivity();
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
  });
  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });
  Future<LocalDataSource> local() async =>
      LocalDataSource(await database.open('', 'U'));
  Future<void> seedLocal(
    String c,
    String id,
    Map<String, dynamic> fields,
  ) async {
    remote.seed(c, id, fields);
    await (await local()).upsertRemote(c, [remote.docs['$c/$id']!]);
  }

  test('staff advance stays in the SQLite outbox offline and synchronizes once after reconnect', () async {
    await service.setScope(
      tenant: 'U',
      business: 'B',
      outlet: 'O',
      salaryAccess: true,
    );
    final salaryPeriods = await (await local()).db.query(
      'sync_queries',
      where: 'collectionName=? AND active=1',
      whereArgs: ['salary_periods'],
    );
    expect(salaryPeriods, hasLength(1));
    await sync.sync();
    await seedLocal('employees', 'EMP-1', {
      'employeeId': 'EMP-1',
      'ownerUid': 'U',
      'businessIds': ['B'],
      'outletIds': ['O'],
      'updatedAt': DateTime.now().toUtc(),
    });
    remote.offline = true;
    final repository = StaffSalaryRepository(service, service);
    Future<void> addAdvance() => repository.recordAdvance(
      tenantId: 'U',
      businessId: 'B',
      outletId: 'O',
      employeeId: 'EMP-1',
      amountPaise: 42000,
      date: DateTime.utc(2026, 10, 1),
      paymentMode: 'CASH',
      requestId: 'OFFLINE-ADV-1',
      createdBy: 'U',
      token: token('U'),
    );
    await addAdvance();
    await addAdvance();
    final localSource = await local();
    expect(
      await localSource.db.query(
        'sync_outbox',
        where: 'status=?',
        whereArgs: ['PENDING'],
      ),
      hasLength(2),
    );
    remote.offline = false;
    await sync.sync(pull: false);
    expect(
      remote.docs.keys.where(
        (key) => key == 'staff_khata_transactions/SKH-ADV-OFFLINE-ADV-1',
      ),
      hasLength(1),
    );
    expect(
      remote.docs.keys.where(
        (key) => key == 'financial_transactions/FIN-SKH-ADV-OFFLINE-ADV-1',
      ),
      hasLength(1),
    );
    expect(
      await localSource.db.query(
        'sync_outbox',
        where: 'status=?',
        whereArgs: ['PENDING'],
      ),
      isEmpty,
    );
  });

  test('salary outbox survives REST authorization failure and retries without duplicate posting', () async {
    await service.setScope(
      tenant: 'U',
      business: 'B',
      outlet: 'O',
      salaryAccess: true,
    );
    await sync.sync();
    await seedLocal('employees', 'EMP-2', {
      'employeeId': 'EMP-2',
      'ownerUid': 'U',
      'businessIds': ['B'],
      'outletIds': ['O'],
    });
    final repository = StaffSalaryRepository(service, service);
    await repository.recordAdvance(
      tenantId: 'U',
      businessId: 'B',
      outletId: 'O',
      employeeId: 'EMP-2',
      amountPaise: 18000,
      date: DateTime.utc(2026, 10, 2),
      paymentMode: 'UPI',
      requestId: 'AUTH-RETRY-ADV',
      createdBy: 'U',
      token: token('U'),
    );
    remote.denied = true;
    await sync.sync(pull: false);
    final source = await local();
    final pending = await source.db.query(
      'sync_outbox',
      where: 'status=?',
      whereArgs: ['PENDING'],
    );
    expect(pending, hasLength(2));
    expect(
      remote.docs.containsKey(
        'staff_khata_transactions/SKH-ADV-AUTH-RETRY-ADV',
      ),
      isFalse,
    );

    remote.denied = false;
    remote.loseAcknowledgement = true;
    await sync.retry();
    expect(await SyncOutboxRepository(source).pendingCount(), 2);
    await sync.retry();
    expect(
      remote.docs.keys.where(
        (key) => key == 'staff_khata_transactions/SKH-ADV-AUTH-RETRY-ADV',
      ),
      hasLength(1),
    );
    expect(
      remote.docs.keys.where(
        (key) => key == 'financial_transactions/FIN-SKH-ADV-AUTH-RETRY-ADV',
      ),
      hasLength(1),
    );
    expect(remote.commits, 1);
    expect(
      await source.db.query(
        'sync_outbox',
        where: 'status=?',
        whereArgs: ['PENDING'],
      ),
      isEmpty,
    );
  });

  test('salary periods are not registered in local sync scope without salary permission', () async {
    await service.setScope(
      tenant: 'U',
      business: 'B',
      outlet: 'O',
      salaryAccess: false,
    );
    final salaryPeriods = await (await local()).db.query(
      'sync_queries',
      where: 'collectionName=? AND active=1',
      whereArgs: ['salary_periods'],
    );
    expect(salaryPeriods, isEmpty);
  });

  test(
    'attendance sync uses the dedicated access scope and outlet isolation',
    () async {
      await service.setScope(
        tenant: 'U',
        business: 'B',
        outlet: 'O',
        salaryAccess: false,
        attendanceAccess: true,
      );
      final source = await local();
      final attendance = await source.db.query(
        'sync_queries',
        where: 'collectionName=? AND active=1',
        whereArgs: ['staff_attendance'],
      );
      expect(attendance, hasLength(1));
      final attendanceEvents = await source.db.query(
        'sync_queries',
        where: 'collectionName=? AND active=1',
        whereArgs: ['staff_attendance_events'],
      );
      expect(attendanceEvents, hasLength(1));
      expect(
        await source.db.query(
          'sync_queries',
          where: 'collectionName=? AND active=1',
          whereArgs: ['salary_periods'],
        ),
        isEmpty,
      );
      final spec = jsonDecode(attendance.single['queryJson'] as String) as Map;
      final filters = (spec['filters'] as List).cast<Map>();
      expect(
        filters.map((f) => f['field']),
        containsAll(['tenantId', 'businessId', 'outletId']),
      );
      final eventSpec =
          jsonDecode(attendanceEvents.single['queryJson'] as String) as Map;
      final eventFilters = (eventSpec['filters'] as List).cast<Map>();
      expect(
        eventFilters.map((f) => f['field']),
        containsAll(['tenantId', 'businessId', 'outletId']),
      );
      await service.setScope(tenant: 'U', business: 'B', outlet: 'O');
      expect(
        await source.db.query(
          'sync_queries',
          where: 'collectionName=? AND active=1',
          whereArgs: ['staff_attendance'],
        ),
        isEmpty,
      );
      expect(
        await source.db.query(
          'sync_queries',
          where: 'collectionName=? AND active=1',
          whereArgs: ['staff_attendance_events'],
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'ten minutes idle and repeated local navigation generate zero reads',
    (tester) async {
      await tester.runAsync(() async {
        remote.seed('products', 'P', {
          'tenantId': 'T',
          'businessId': 'B',
          'status': 'ACTIVE',
        });
        await service.setScope(tenant: 'T', business: 'B');
        await sync.start();
        await sync.sync();
        final requests = remote.queries + remote.reads;
        for (var i = 0; i < 10; i++) {
          await service.queryDocuments(
            collection: 'products',
            filters: [const FirestoreFilter('status', 'EQUAL', 'ACTIVE')],
            idToken: token('U'),
          );
          await service.queryDocuments(
            collection: 'invoices',
            filters: [
              FirestoreFilter('createdAt', 'GREATER_THAN', DateTime.now()),
            ],
            idToken: token('U'),
          );
        }
        expect(remote.queries + remote.reads, requests);
      });
      final requests = remote.queries + remote.reads;
      await tester.pump(const Duration(minutes: 10));
      expect(remote.queries + remote.reads, requests);
    },
  );

  test('outbox-only upload does not pull and query identity is stable across scope switches', () async {
    await service.setScope(tenant: 'T', business: 'B');
    await sync.sync();
    final source = await local();
    final count = (await source.db.query('sync_queries')).length;
    await service.setScope(tenant: 'T', business: 'C');
    await sync.sync();
    await service.setScope(tenant: 'T', business: 'B');
    await sync.sync(pull: false);
    expect(
      (await source.db.query('sync_queries', where: 'active=1')).length,
      count,
    );
    final rows = await source.db.query('sync_queries', where: 'active=1');
    expect(
      rows.where(
        (r) => (r['queryJson'] as String).contains('"stringValue":"C"'),
      ),
      isEmpty,
    );
    final queries = remote.queries;
    await service.createDocument('products', 'LOCAL', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Offline',
    }, idToken: token('U'));
    await sync.sync(pull: false);
    expect(remote.queries, queries);
    expect((await source.row('products', 'LOCAL'))!['syncStatus'], 'SYNCED');
  });

  test('verified central product master bootstraps atomically and searches locally', () async {
    void seedCentral(
      String id,
      String name, {
      String brandName = 'Asian Paints',
      String categoryId = 'CATEGORY',
      String categoryName = 'Adhesives & Tiling',
      String subcategoryId = 'SUBCATEGORY',
      String subcategoryName = 'Woodworking & Multi-Surface Adhesives',
    }) {
      remote.seed(CentralProductMasterContract.collection, id, {
        'masterProductId': id,
        'productName': name,
        'normalizedProductName': name.toLowerCase(),
        'businessTypeId': 'BT-HARDWARE',
        'businessTypeName': 'Hardware',
        'businessSubTypeId': 'BST-PAINTS',
        'businessSubTypeName': 'Paints',
        'brandId': 'BRAND-${brandName.replaceAll(' ', '-')}',
        'brandName': brandName,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'subcategoryId': subcategoryId,
        'subcategoryName': subcategoryName,
        'searchTokens': name.toLowerCase().split(' '),
        'isActive': true,
        'status': 'ACTIVE',
        'scopeType': 'SYSTEM',
        'rangeName': null,
        'description': 'Reference description',
        'imageUrl': 'https://example.test/$id.png',
        'packSizes': ['1 L', '4 L'],
        'finish': 'Matt',
        'colour': 'White',
      });
      final document =
          remote.docs['${CentralProductMasterContract.collection}/$id']!;
      final fields = FirestoreRestService.decodeFields(document['fields'])
        ..['updatedAt'] = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
      document['fields'] = FirestoreRestService.encodeFields(fields);
    }

    seedCentral(
      'AP-TRUCARE',
      'AP Trucare Brush 160',
      categoryId: 'SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES',
      categoryName: 'Painting Tools & Accessories',
      subcategoryId:
          'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH',
      subcategoryName: 'Brush',
    );
    seedCentral(
      'APEX-CREATEX',
      'Apex Createx',
      categoryId: 'SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS',
      categoryName: 'Textures & Special Effects',
      subcategoryId: 'SYS_SUBCATEGORY_SYS_CATEGORY_TEXTURES_SPECIAL_EFFECTS_EXTERIOR_TEXTURES',
      subcategoryName: 'Exterior Textures',
    );
    seedCentral('LOCTITE-RAPID', 'Loctite Rapid');
    seedCentral(
      'SMARTCARE-MORTAR',
      'SmartCare Block Joining Mortar',
      subcategoryId: 'SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_BLOCK_JOINING_MORTARS_ADHESIVES',
      subcategoryName: 'Block Joining Mortars & Adhesives',
    );
    seedCentral(
      'BERGER-ADHESIVE-Z',
      'Berger HomeShield Adhesive Z',
      brandName: 'Berger',
      subcategoryId: 'SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_CONSTRUCTION_ETICS_ADHESIVES',
      subcategoryName: 'Construction & ETICS Adhesives',
    );
    seedCentral(
      'HOMESHIELD-BASE',
      'HomeShield Base Coat-US',
      subcategoryId: 'SYS_SUBCATEGORY_SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS_ETICS_BASE_COATS',
      categoryId: 'SYS_CATEGORY_PROTECTIVE_INDUSTRIAL_COATINGS',
      categoryName: 'Protective & Industrial Coatings',
      subcategoryName: 'ETICS Base Coats',
    );
    for (
      var index = 0;
      index < CentralProductMasterContract.expectedDocumentCount - 6;
      index++
    ) {
      seedCentral('OTHER-$index', 'Other Product $index');
    }

    final sourceBeforeSync = await local();
    await sourceBeforeSync.db.insert('sync_queries', {
      'queryKey': '${CentralProductMasterContract.previousCollection}:legacy',
      'collectionName': CentralProductMasterContract.previousCollection,
      'queryJson': jsonEncode({
        'filters': [
          {
            'field': 'scopeType',
            'operation': 'EQUAL',
            'value': {'stringValue': 'SYSTEM'},
          },
        ],
      }),
      'lastSyncedAt': LocalDataSource.now(),
      'lastAttemptAt': LocalDataSource.now(),
      'lastError': 'old composite index failure',
      'active': 1,
      'cursor': DateTime.now().toUtc().toIso8601String(),
      'catalogueVersion': 'old-source-version',
    });
    await service.setScope(tenant: 'T', business: 'B');
    final newQuery = (await sourceBeforeSync.db.query(
      'sync_queries',
      where: 'collectionName=?',
      whereArgs: [CentralProductMasterContract.collection],
    )).single;
    expect(newQuery['cursor'], isNull);
    expect(newQuery['lastSyncedAt'], isNull);
    expect(newQuery['catalogueVersion'], isNull);
    expect(
      await sourceBeforeSync.db.query(
        'sync_queries',
        where: 'collectionName=?',
        whereArgs: [CentralProductMasterContract.previousCollection],
      ),
      isEmpty,
    );
    await sync.sync();

    final source = await local();
    final cached = await source.db.query(
      'local_central_product_master',
      where: 'source_collection=?',
      whereArgs: [CentralProductMasterContract.collection],
    );
    expect(
      cached,
      hasLength(CentralProductMasterContract.expectedDocumentCount),
    );
    final duplicateIds = await source.db.rawQuery(
      '''
      SELECT master_product_id FROM local_central_product_master
      WHERE source_collection=?
      GROUP BY master_product_id HAVING COUNT(*) > 1
    ''',
      [CentralProductMasterContract.collection],
    );
    final duplicateNames = await source.db.rawQuery(
      '''
      SELECT brand_name, normalized_product_name
      FROM local_central_product_master WHERE source_collection=?
      GROUP BY lower(trim(brand_name)), lower(trim(normalized_product_name))
      HAVING COUNT(*) > 1
    ''',
      [CentralProductMasterContract.collection],
    );
    expect(duplicateIds, isEmpty);
    expect(duplicateNames, isEmpty);
    final queryRows = await source.db.query(
      'sync_queries',
      where: 'collectionName=?',
      whereArgs: [CentralProductMasterContract.collection],
    );
    expect(queryRows, hasLength(1));
    expect(queryRows.single['active'], 1);
    expect(queryRows.single['lastError'], isNull, reason: sync.error);
    expect(queryRows.single['lastSyncedAt'], isNotNull);
    expect(queryRows.single['cursor'], isNotNull);
    expect(
      queryRows.single['catalogueVersion'],
      CentralProductMasterContract.verifiedBootstrapVersion,
    );
    final expectedClassifications = {
      'ap trucare brush 160': ('Painting Tools & Accessories', 'Brush'),
      'apex createx': ('Textures & Special Effects', 'Exterior Textures'),
      'loctite rapid': (
        'Adhesives & Tiling',
        'Woodworking & Multi-Surface Adhesives',
      ),
      'smartcare block joining mortar': (
        'Adhesives & Tiling',
        'Block Joining Mortars & Adhesives',
      ),
      'berger homeshield adhesive z': (
        'Adhesives & Tiling',
        'Construction & ETICS Adhesives',
      ),
      'homeshield base coat-us': (
        'Protective & Industrial Coatings',
        'ETICS Base Coats',
      ),
    };
    for (final entry in expectedClassifications.entries) {
      final rows = await source.db.query(
        'local_central_product_master',
        columns: ['category_name', 'subcategory_name'],
        where: 'source_collection=? AND normalized_product_name=?',
        whereArgs: [CentralProductMasterContract.collection, entry.key],
      );
      expect(rows, hasLength(1), reason: entry.key);
      expect(rows.single['category_name'], entry.value.$1);
      expect(rows.single['subcategory_name'], entry.value.$2);
    }

    final previousReadCount = remote.returnedDocuments;
    expect(
      previousReadCount,
      CentralProductMasterContract.expectedDocumentCount,
    );
    await sync.sync();
    expect(remote.returnedDocuments, previousReadCount);
    expect(
      await source.db.query(
        'local_central_product_master',
        where: 'source_collection=?',
        whereArgs: [CentralProductMasterContract.collection],
      ),
      hasLength(CentralProductMasterContract.expectedDocumentCount),
    );

    final previousSuccessfulSync = (await source.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: [queryRows.single['queryKey']],
    )).single['lastSyncedAt'];
    await source.db.update(
      'sync_queries',
      {'catalogueVersion': null},
      where: 'queryKey=?',
      whereArgs: [queryRows.single['queryKey']],
    );
    remote.docs.remove('${CentralProductMasterContract.collection}/OTHER-0');
    await sync.sync();
    expect(
      await source.db.query(
        'local_central_product_master',
        where: 'source_collection=?',
        whereArgs: [CentralProductMasterContract.collection],
      ),
      hasLength(CentralProductMasterContract.expectedDocumentCount),
    );
    final failedBootstrap = (await source.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: [queryRows.single['queryKey']],
    )).single;
    expect(failedBootstrap['catalogueVersion'], isNull);
    expect(failedBootstrap['lastSyncedAt'], previousSuccessfulSync);
    expect(failedBootstrap['lastError'], contains('expected 1305'));

    sync.dispose();
    await database.close();
    remote.offline = true;
    connectivity.available = false;
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    final previousRequests = remote.queries + remote.reads;
    final results = await ProductRepository(service, service)
        .searchCentralProductMaster(
          query: 'Loctite Rapid',
          businessTypeId: 'BT-HARDWARE',
          businessSubTypeId: 'BST-PAINTS',
        );
    expect(results, hasLength(1));
    expect(results.single.productName, 'Loctite Rapid');
    expect(results.single.categoryName, 'Adhesives & Tiling');
    expect(
      results.single.subcategoryName,
      'Woodworking & Multi-Surface Adhesives',
    );
    expect(remote.queries + remote.reads, previousRequests);
  });

  test('quota cooldown persists and blocks manual, automatic and bootstrap attempts', () async {
    await service.setScope(tenant: 'T', business: 'B');
    // Drain the initial scope-change pull before simulating a quota response;
    // otherwise its debounce timer can race this explicit sync and issue a
    // second request before the first failure persists the cooldown.
    await sync.sync();
    remote.quota = true;
    await sync.sync();
    final attempts = remote.queries + remote.reads;
    await sync.sync();
    await sync.sync(pull: false);
    expect(remote.queries + remote.reads, attempts);
    await sync.retry();
    expect(remote.queries + remote.reads, attempts);
    final control = (await (await local()).db.query('sync_control')).single;
    expect(
      DateTime.parse(control['cooldownUntil'] as String)
          .difference(DateTime.now().toUtc()),
      greaterThan(const Duration(minutes: 59)),
    );
    await expectLater(
      service.queryDocuments(
        collection: 'employees',
        filters: [],
        idToken: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    expect(remote.queries + remote.reads, attempts);
    await service.createDocument('products', 'PENDING', {
      'tenantId': 'T',
      'businessId': 'B',
    }, idToken: token('U'));
    await sync.sync();
    expect(
      (await (await local()).row('products', 'PENDING'))!['syncStatus'],
      'PENDING_CREATE',
    );
    await database.close();
    expect(
      (await (await local()).db.query('sync_control')).single['cooldownUntil'],
      control['cooldownUntil'],
    );
  });

  test('failed later page commits neither documents nor cursor; equal timestamps paginate safely', () async {
    await service.setScope(tenant: 'T', business: 'B');
    for (var i = 0; i < 401; i++) {
      remote.seed('products', 'P${i.toString().padLeft(4, '0')}', {
        'tenantId': 'T',
        'businessId': 'B',
        'updatedAt': DateTime.utc(2020),
      });
    }
    remote.failAfter = 'products';
    await sync.sync();
    final source = await local();
    final failed = (await source.db.query(
      'sync_queries',
      where: "collectionName='products' AND active=1",
    )).single;
    expect(failed['cursor'], isNull);
    expect(await source.query('products', []), isEmpty);
    remote.failAfter = null;
    // Failed remote pages set transient backoff; exercise the supported
    // explicit retry path before asserting the next complete page commit.
    await sync.retry();
    expect((await source.query('products', [])).length, 401);
    final first = (await source.db.query(
      'sync_queries',
      where: "collectionName='products' AND active=1",
    )).single['cursor'];
    expect(first, isNotNull);
    final time = DateTime.parse(first as String);
    for (var i = 0; i < 401; i++) {
      remote.seed('products', 'P${i.toString().padLeft(4, '0')}', {
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Changed',
        'updatedAt': time,
      });
    }
    await sync.sync();
    expect(
      (await source.query('products', []))
          .where(
            (d) =>
                FirestoreRestService.decodeFields(d['fields'])['name'] ==
                'Changed',
          )
          .length,
      401,
    );
    expect(remote.pullReasons, contains('MANUAL_REFRESH'));
  });

  test(
    'unchanged catalogue is cached and incremental pulls exclude old documents',
    () async {
      await service.setScope(tenant: 'T', business: 'B');
      remote.seed('brands', 'SYSTEM', {
        'scopeType': 'SYSTEM',
        'name': 'Cached',
        'updatedAt': DateTime.utc(2020),
      });
      remote.seed('products', 'P', {
        'tenantId': 'T',
        'businessId': 'B',
        'updatedAt': DateTime.utc(2020),
      });
      await sync.sync();
      final before = remote.returnedDocuments;
      await sync.sync();
      expect(remote.returnedDocuments, before);
      remote.seed('products', 'P', {
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Updated',
      });
      await sync.sync();
      expect(remote.returnedDocuments, before + 1);
      remote.seed('product_catalogue_releases', 'R', {
        'scopeType': 'SYSTEM',
        'version': 2,
        'status': 'ACTIVE',
      });
      remote.seed('brands', 'NEW', {'scopeType': 'SYSTEM', 'name': 'New'});
      await sync.sync();
      expect(await (await local()).row('brands', 'NEW'), isNotNull);
    },
  );

  test('resume freshness and reconnect use incremental pulls rather than initial downloads', () async {
    await service.setScope(tenant: 'T', business: 'B');
    remote.seed('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'updatedAt': DateTime.utc(2020),
    });
    await sync.start();
    await sync.sync();
    final requests = remote.queries + remote.reads;
    await sync.onResume();
    await sync.sync(pull: false);
    expect(remote.queries + remote.reads, requests);
    await (await local()).db.update('sync_control', {
      'lastPullAt': DateTime.utc(2020).toIso8601String(),
    }, where: 'id=1');
    // onResume throttles per collection too, so backdate those markers along
    // with the global marker to model a genuinely stale resumed session.
    await (await local()).db.update('sync_queries', {
      'lastSyncedAt': DateTime.utc(2020).toIso8601String(),
    }, where: 'active=1');
    await sync.onResume();
    final reasons = remote.pullReasons.length;
    await sync.sync(pull: false);
    expect(remote.pullReasons.skip(reasons), contains('INCREMENTAL_PULL'));
    connectivity.available = false;
    await service.createDocument('products', 'LOCAL', {
      'tenantId': 'T',
      'businessId': 'B',
    }, idToken: token('U'));
    final reconnectReasons = remote.pullReasons.length;
    (connectivity as TestConnectivity).reconnect();
    await sync.sync(pull: false);
    expect(
      remote.pullReasons.skip(reconnectReasons),
      isNot(contains('INITIAL_PULL')),
    );
    expect(
      (await (await local()).row('products', 'LOCAL'))!['syncStatus'],
      'SYNCED',
    );
  });

  test(
    'automatic upload attempts respect persisted transient backoff',
    () async {
      await service.createDocument('products', 'P', {
        'name': 'Pending',
      }, idToken: token('U'));
      remote.offline = true;
      await sync.sync();
      final attempts = remote.reads;
      for (var i = 0; i < 5; i++) {
        sync.notifyLocalWrite();
        await sync.sync(pull: false);
      }
      expect(remote.reads, attempts);
      expect(
        (await (await local()).row('products', 'P'))!['syncStatus'],
        'PENDING_CREATE',
      );
    },
  );

  test('incremental remote tombstones hide synced records locally', () async {
    await service.setScope(tenant: 'T', business: 'B');
    remote.seed('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
      'updatedAt': DateTime.utc(2020),
    });
    await sync.sync();
    remote.seed('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'DELETED',
      'isDeleted': true,
    });
    await sync.sync();
    expect(await (await local()).query('products', []), isEmpty);
    expect((await (await local()).row('products', 'P'))!['isDeleted'], 1);
  });

  test('legacy registry migration deduplicates identities and deactivates historical scopes without deleting pending data', () async {
    final inventory = jsonDecode(
      await File('docs/sync-query-inventory-before.json').readAsString(),
    ) as Map;
    final queries = inventory['queries'] as List;
    final selected = queries.firstWhere(
      (q) =>
          q['collectionName'] == 'products' &&
          (jsonDecode(q['queryJson'])['filters'] as List).length == 2,
    );
    final filters = SyncEngine.decodeFilters(
      jsonDecode(selected['queryJson'])['filters'] as List,
    );
    final tenant =
        filters.firstWhere((f) => f.field == 'tenantId').value as String;
    final business =
        filters.firstWhere((f) => f.field == 'businessId').value as String;
    final path = '${dir.path}/nubibill-${Uri.encodeComponent('-$tenant')}.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) => LocalDatabase.migrate(db, 0, 2),
      ),
    );
    for (final q in queries) {
      await legacy.insert('sync_queries', Map<String, Object?>.from(q as Map));
    }
    final spec = jsonDecode(selected['queryJson']) as Map<String, dynamic>;
    spec['filters'] = (spec['filters'] as List).reversed.toList();
    final identity = '${selected['collectionName']}:${jsonEncode(spec)}';
    if (identity != selected['queryKey']) {
      await legacy.insert('sync_queries', {
        'queryKey': identity,
        'collectionName': selected['collectionName'],
        'queryJson': jsonEncode(spec),
      });
    }
    await legacy.insert('local_products', {
      'remoteId': 'PENDING',
      'payloadJson': '{}',
      'syncStatus': 'PENDING_CREATE',
      'localUpdatedAt': LocalDataSource.now(),
    });
    await legacy.close();
    sync.dispose();
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session(tenant),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate(tenant);
    final upgraded = await database.open('', tenant);
    expect((await upgraded.query('sync_queries')).length, 98);
    expect(await upgraded.query('sync_queries', where: 'active=1'), isEmpty);
    expect(
      (await upgraded.query('local_products')).single['syncStatus'],
      'PENDING_CREATE',
    );
    final oldKeys = (await upgraded.query('sync_queries'))
        .map((q) => q['queryKey'])
        .toSet();
    final outletQuery = queries.firstWhere(
      (q) =>
          q['collectionName'] == 'invoices' &&
          (jsonDecode(q['queryJson'])['filters'] as List).any(
            (f) => f['field'] == 'outletId',
          ),
    );
    final outlet =
        SyncEngine.decodeFilters(
              jsonDecode(outletQuery['queryJson'])['filters'] as List,
            ).firstWhere((f) => f.field == 'outletId').value
            as String;
    await service.setScope(tenant: tenant, business: business, outlet: outlet);
    final active = await upgraded.query('sync_queries', where: 'active=1');
    final reused = active.where((q) => oldKeys.contains(q['queryKey'])).length;
    expect(
      active.where((q) => (q['queryJson'] as String).contains('createdAt')),
      isEmpty,
    );
    debugPrint(
      'LEGACY_REGISTRY_MEASUREMENT ${jsonEncode({'oldQueries': 98, 'oldQueriesDeactivated': 98 - reused, 'oldQueriesReused': reused, 'activeCanonicalQueries': active.length, 'finalRegistryRows': (await upgraded.query('sync_queries')).length})}',
    );
  });

  test('controlled before-after measurement replays the audited registry without live Firestore', () async {
    final inventory = jsonDecode(
      await File('docs/sync-query-inventory-before.json').readAsString(),
    ) as Map;
    final queries = inventory['queries'] as List;
    final selected = queries.firstWhere(
      (q) =>
          q['collectionName'] == 'products' &&
          (jsonDecode(q['queryJson'])['filters'] as List).length == 2,
    );
    final filters = SyncEngine.decodeFilters(
      jsonDecode(selected['queryJson'])['filters'] as List,
    );
    final tenant =
        filters.firstWhere((f) => f.field == 'tenantId').value as String;
    final business =
        filters.firstWhere((f) => f.field == 'businessId').value as String;
    for (var i = 0; i < 511; i++) {
      remote.seed('subcategory_attribute_templates', 'T$i', {
        'scopeType': 'SYSTEM',
        'status': 'ACTIVE',
        'updatedAt': DateTime.utc(2020),
      });
    }
    for (var i = 0; i < 2; i++) {
      remote.seed('products', 'P$i', {
        'tenantId': tenant,
        'businessId': business,
        'status': 'ACTIVE',
        'updatedAt': DateTime.utc(2020),
      });
    }
    var oldDocuments = 0;
    for (final q in queries) {
      final spec = jsonDecode(q['queryJson']) as Map;
      if (spec['id'] != null) {
        try {
          await remote.getDocument(q['collectionName'], spec['id']);
          oldDocuments++;
        } on AppException catch (e) {
          if (e.code != 'not-found') rethrow;
        }
      } else {
        oldDocuments += (await remote.queryDocuments(
          collection: q['collectionName'],
          filters: SyncEngine.decodeFilters(spec['filters'] as List),
        )).length;
      }
    }
    final beforeRequests = remote.queries + remote.reads;
    expect(beforeRequests, 98);
    await service.setScope(tenant: tenant, business: business);
    await sync.sync();
    final afterInitial = remote.queries + remote.reads;
    for (var i = 0; i < 13; i++) {
      await service.queryDocuments(
        collection: 'products',
        filters: filters,
        idToken: token('U'),
      );
      await sync.sync(pull: false);
    }
    final idleRequests = remote.queries + remote.reads - afterInitial;
    expect(idleRequests, 0);
    debugPrint(
      'CONTROLLED_READ_MEASUREMENT ${jsonEncode({'oldRequestsPerCycle': beforeRequests, 'oldReturnedDocumentsPerCycle': oldDocuments, 'oldRequestsFor13IdleTicks': beforeRequests * 13, 'oldDocumentsFor13IdleTicks': oldDocuments * 13, 'newIdleRequests': idleRequests, 'newInitialRequests': afterInitial - beforeRequests, 'newInitialDocuments': remote.returnedDocuments})}',
    );
  });

  test('remote tombstone can be recreated with version protection', () async {
    await seedLocal('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Original',
    });
    await service.deleteDocument('products', 'P', idToken: token('U'));
    await sync.sync(pull: false);
    await service.createDocument('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Recreated',
    }, idToken: token('U'));
    await sync.sync(pull: false);
    expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
    final fields = FirestoreRestService.decodeFields(
      remote.docs['products/P']!['fields'],
    );
    expect(fields['isDeleted'], false);
    expect(fields['name'], 'Recreated');
  });

  test(
    'Godown reservation stops at 100 collisions without partial local writes',
    () async {
      connectivity.available = false;
      await seedLocal('document_sequences', 'T_B_GODOWN', {
        'tenantId': 'T',
        'businessId': 'B',
        'sequenceType': 'GODOWN',
        'nextNumber': 1,
      });
      for (var i = 1; i <= 100; i++) {
        final code = 'GD-${i.toString().padLeft(4, '0')}';
        final id = base64Url
            .encode(utf8.encode('T|B|$code'))
            .replaceAll('=', '');
        await seedLocal('godown_code_reservations', id, {
          'tenantId': 'T',
          'businessId': 'B',
          'code': code,
        });
      }
      final reads = remote.reads;
      await expectLater(
        StorageRepository(service, service).createStorageLocation(
          tenantId: 'T',
          businessId: 'B',
          parentLocationId: null,
          name: 'Storage',
          code: null,
          type: StorageLocationType.godown,
          description: null,
          godownScope: GodownScope.central,
          actorUid: 'U',
          token: token('U'),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            'reservation-limit',
          ),
        ),
      );
      expect(await (await local()).db.query('sync_outbox'), isEmpty);
      expect(await (await local()).query('godowns', []), isEmpty);
      expect(remote.reads, reads);
    },
  );

  test('concurrent bootstrap reads coalesce and cached navigation does not repeat REST', () async {
    remote.seed('businesses', 'B', {'ownerUid': 'T', 'name': 'Business'});
    await Future.wait(
      List.generate(
        5,
        (_) => service.queryDocuments(
          collection: 'businesses',
          filters: [const FirestoreFilter('ownerUid', 'EQUAL', 'T')],
          idToken: token('U'),
        ),
      ),
    );
    expect(remote.queries, 1);
    await service.queryDocuments(
      collection: 'businesses',
      filters: [const FirestoreFilter('ownerUid', 'EQUAL', 'T')],
      idToken: token('U'),
    );
    expect(remote.queries, 1);
    await service.queryDocuments(
      collection: 'businesses',
      filters: [
        const FirestoreFilter('ownerUid', 'EQUAL', 'T'),
        const FirestoreFilter('name', 'EQUAL', 'Missing'),
      ],
      idToken: token('U'),
    );
    expect(remote.queries, 1);
    remote.seed('user', 'U', {'name': 'Account'});
    await Future.wait(
      List.generate(
        5,
        (_) => service.getDocument('user', 'U', idToken: token('U')),
      ),
    );
    expect(remote.reads, 1);
    await Future.wait(
      List.generate(5, (_) async {
        await expectLater(
          service.getDocument('user', 'MISSING', idToken: token('U')),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', 'not-found'),
          ),
        );
      }),
    );
    expect(remote.reads, 2);
  });

  test('business attribute option deduplicates system names, survives offline restart and uploads via outbox', () async {
    await seedLocal('product_attribute_options', 'FLAT', {
      'attributeId': 'A',
      'name': 'Flat',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });
    connectivity.available = false;
    remote.offline = true;
    var repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    Future<String> add(String name) => repo.createAttributeOption(
      tenantId: 'T',
      businessId: 'B',
      attributeId: 'A',
      name: name,
      actorUid: 'U',
      token: token('U'),
    );
    expect(await add(' flat '), 'Flat');
    expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
    expect(await add('  Oval   Brush  '), 'Oval Brush');
    expect(await add('oval brush'), 'Oval Brush');
    expect(await SyncOutboxRepository(await local()).pendingCount(), 1);
    sync.dispose();
    await database.close();
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    repo = ProductRepository(service, service);
    expect(await add('OVAL BRUSH'), 'Oval Brush');
    final rows = await (await local()).db.query(
      'local_product_attribute_options',
      where: "scopeType='BUSINESS'",
    );
    expect(rows.length, 1);
    expect(rows.single['syncStatus'], 'PENDING_CREATE');
    remote.offline = false;
    connectivity.available = true;
    await sync.sync();
    expect(sync.error, isNull);
    expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
    final remoteOption = FirestoreRestService.decodeFields(
      remote
          .docs['product_attribute_options/${rows.single['remoteId']}']!['fields'],
    );
    expect(remoteOption['scopeType'], 'BUSINESS');
    expect(remoteOption['name'], 'Oval Brush');
  });

  test('product KPI base dataset excludes deleted parents, orphan variants and other businesses while retaining pending records', () async {
    connectivity.available = false;
    remote.offline = true;
    Map<String, dynamic> product(
      String id, {
      String status = 'ACTIVE',
      bool deleted = false,
      String tenant = 'T',
      String business = 'B',
    }) => {
      'productId': id,
      'productName': id,
      'tenantId': tenant,
      'businessId': business,
      'status': status,
      'isDeleted': deleted,
    };
    Map<String, dynamic> variant(
      String id,
      String parent, {
      String status = 'ACTIVE',
      bool deleted = false,
      String tenant = 'T',
      String business = 'B',
    }) => {
      'variantId': id,
      'productId': parent,
      'variantName': id,
      'sku': id,
      'baseUnitId': 'PIECE',
      'tenantId': tenant,
      'businessId': business,
      'status': status,
      'isDeleted': deleted,
    };
    await seedLocal('products', 'P1', product('P1'));
    await seedLocal('product_variants', 'V1', variant('V1', 'P1'));
    await service.runAtomicOperation((tx) async {
      tx.create('products', 'P2', product('P2'));
      for (final id in ['V2', 'V3', 'V4']) {
        tx.create('product_variants', id, variant(id, 'P2'));
      }
    }, idToken: token('U'));
    for (final id in [
      'DELETED',
      'SOFT',
      'TOMBSTONE',
      'OTHER_BUSINESS',
      'OTHER_TENANT',
    ]) {
      await seedLocal(
        'products',
        id,
        product(
          id,
          status: id == 'DELETED' ? 'deleted' : 'ACTIVE',
          deleted: id == 'SOFT',
          business: id == 'OTHER_BUSINESS' ? 'OTHER' : 'B',
          tenant: id == 'OTHER_TENANT' ? 'OTHER' : 'T',
        ),
      );
      await seedLocal('product_variants', 'V_$id', variant('V_$id', id));
    }
    await (await local()).db.update(
      'local_products',
      {'isDeleted': 1},
      where: 'remoteId=?',
      whereArgs: ['TOMBSTONE'],
    );
    await seedLocal('product_variants', 'ORPHAN', variant('ORPHAN', 'MISSING'));
    await seedLocal(
      'product_variants',
      'DELETED_VARIANT',
      variant('DELETED_VARIANT', 'P1', status: 'DELETED'),
    );
    await seedLocal(
      'product_variants',
      'SOFT_VARIANT',
      variant('SOFT_VARIANT', 'P1', deleted: true),
    );
    await seedLocal(
      'product_variants',
      'TOMBSTONE_VARIANT',
      variant('TOMBSTONE_VARIANT', 'P1'),
    );
    await (await local()).db.update(
      'local_product_variants',
      {'isDeleted': 1},
      where: 'remoteId=?',
      whereArgs: ['TOMBSTONE_VARIANT'],
    );
    await seedLocal(
      'product_variants',
      'OTHER_BUSINESS_VARIANT',
      variant('OTHER_BUSINESS_VARIANT', 'P1', business: 'OTHER'),
    );
    await seedLocal(
      'product_variants',
      'OTHER_TENANT_VARIANT',
      variant('OTHER_TENANT_VARIANT', 'P1', tenant: 'OTHER'),
    );
    final readsBefore = remote.reads, queriesBefore = remote.queries;
    final products = await ProductRepository(
      service,
      service,
    ).getProducts(tenantId: 'T', businessId: 'B', token: token('U'));
    expect(products.map((p) => p.productId).toSet(), {'P1', 'P2'});
    expect(products.length, 2);
    expect(products.fold<int>(0, (sum, p) => sum + p.variants.length), 4);
    expect(products.where((p) => p.isActive).length, 2);
    expect(
      products.singleWhere((p) => p.productId == 'P2').syncStatus,
      'PENDING_CREATE',
    );
    expect(products.expand((p) => p.variants).map((v) => v.variantId).toSet(), {
      'V1',
      'V2',
      'V3',
      'V4',
    });
    expect(remote.reads, readsBefore);
    expect(remote.queries, queriesBefore);
    // Inspection did not delete the source records or clear pending operations.
    expect(await (await local()).row('products', 'DELETED'), isNotNull);
    expect(await (await local()).row('product_variants', 'ORPHAN'), isNotNull);
    expect(await SyncOutboxRepository(await local()).pendingCount(), 4);
  });

  test('full product edit persists image and dynamic values offline and uploads one atomic batch', () async {
    await installProductTestCatalogue(
      source: await local(),
      seedRemote: remote.seed,
    );
    for (final entry in {
      'brands': 'BR',
      'product_categories': 'CA',
      'product_subcategories': 'SC',
      'units': 'UN',
    }.entries) {
      await seedLocal(entry.key, entry.value, {
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
        'name': entry.value,
        if (entry.key == 'product_subcategories') 'categoryId': 'CA',
        if (entry.key == 'units') 'measurementDimension': 'MASS',
        if (entry.key == 'product_subcategories') 'subcategoryId': entry.value,
        if (entry.key == 'product_subcategories')
          'unitRules': {
            'allowedPackUnits': ['UN'],
            'defaultPackUnit': 'UN',
            'allowedSellingUnits': ['UN'],
            'defaultSellingUnit': 'UN',
            'allowedBaseUnits': ['UN'],
            'defaultBaseUnit': 'UN',
            'conversionAllowed': true,
            'conversionDimension': 'MASS',
          },
      });
    }
    for (final entry in {
      'custom': 'PRODUCT',
      'businessFinish': 'VARIANT',
    }.entries) {
      await seedLocal('product_attributes', entry.key, {
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
        'attributeId': entry.key,
        'name': entry.key,
        'dataType': entry.key == 'custom' ? 'MULTI_SELECT' : 'SELECT',
        'options': entry.key == 'custom' ? ['a', 'b'] : ['Silk'],
      });
      await seedLocal('subcategory_attribute_templates', 'SC_${entry.key}', {
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
        'subcategoryId': 'SC',
        'attributeId': entry.key,
        'attributeLevel': entry.value,
      });
    }
    await seedLocal('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'productName': 'Original',
      'status': 'ACTIVE',
      'imageUrl': 'https://example.com/old.png',
      'brandId': 'BR',
      'categoryId': 'CA',
      'subcategoryId': 'SC',
    });
    await seedLocal('product_variants', 'V', {
      'tenantId': 'T',
      'businessId': 'B',
      'productId': 'P',
      'variantName': 'One',
      'baseUnitId': 'UN',
      'sku': 'SKU-0001',
      'sellingPrice': 12345,
      'purchaseRate': 9000,
      'mrp': 15000,
    });
    remote.offline = true;
    final repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    await repo.updateStructuredProduct(
      tenantId: 'T',
      businessId: 'B',
      productId: 'P',
      productName: 'Edited',
      actorUid: 'U',
      token: token('U'),
      productFields: {
        'brandId': 'BR',
        'categoryId': 'CA',
        'subcategoryId': 'SC',
        'imageUrl': 'https://example.com/new.png',
        'productImage': 'https://example.com/new.png',
        'attributeValues': {
          'custom': ['a', 'b'],
        },
      },
      variants: [
        {
          'variantId': 'V',
          'attributeValues': {'businessFinish': 'Silk'},
          'baseUnitId': 'UN',
          'commercialUnitId': 'UN',
          'baseQuantityPerCommercialUnit': 2,
          'barcode': 'CODE',
        },
      ],
    );
    var products = await repo.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    );
    expect(products.single.productImage, 'https://example.com/new.png');
    expect(products.single.attributeValues['custom'], ['a', 'b']);
    expect(products.single.variants.single.sellingPrice, 12345);
    expect(products.single.variants.single.purchaseRate, 9000);
    expect(products.single.variants.single.mrp, 15000);
    expect(products.single.variants.single.sku, 'SKU-0001');
    expect(
      products.single.variants.single.attributeValues['businessFinish'],
      'Silk',
    );
    expect(products.single.syncStatus, 'PENDING_UPDATE');
    sync.dispose();
    await database.close();
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () => Future.value(session('U')),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    final reopened = ProductRepository(service, service);
    products = await reopened.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    );
    expect(products.single.productImage, 'https://example.com/new.png');
    remote.offline = false;
    await sync.sync();
    expect(
      FirestoreRestService.decodeFields(
        remote.docs['products/P']!['fields'],
      )['imageUrl'],
      'https://example.com/new.png',
    );
    expect((await local()).db.isOpen, true);
    expect(
      (await (await local()).row('products', 'P'))!['syncStatus'],
      'SYNCED',
    );
  });

  test('offline bulk soft deletion retains variants and historical lines through synchronization', () async {
    for (final id in ['USED', 'UNUSED']) {
      await seedLocal('products', id, {
        'tenantId': 'T',
        'businessId': 'B',
        'productName': id,
        'status': 'ACTIVE',
        'imageUrl': 'https://example.com/image.png',
      });
    }
    await seedLocal('product_variants', 'V', {
      'tenantId': 'T',
      'businessId': 'B',
      'productId': 'USED',
      'sku': 'SKU-1',
    });
    await seedLocal('invoices', 'H', {
      'tenantId': 'T',
      'businessId': 'B',
      'productId': 'USED',
      'variantId': 'V',
      'items': [
        {'productId': 'USED', 'variantId': 'V', 'quantity': 1},
      ],
    });
    remote.offline = true;
    await ProductRepository(service, service).setProductStatus(
      tenantId: 'T',
      businessId: 'B',
      productIds: ['USED', 'UNUSED'],
      status: 'DELETED',
      actorUid: 'U',
      token: token('U'),
    );
    expect(
      FirestoreRestService.decodeFields(
        (await (await local()).row('products', 'USED'))!['payloadJson']
                is String
            ? jsonDecode(
                (await (await local()).row('products', 'USED'))!['payloadJson']
                    as String,
              )
            : {},
      )['status'],
      'DELETED',
    );
    expect(await (await local()).row('product_variants', 'V'), isNotNull);
    expect(await (await local()).row('invoices', 'H'), isNotNull);
    remote.offline = false;
    await sync.sync();
    expect(remote.docs['invoices/H'], isNotNull);
    expect(remote.docs['product_variants/V'], isNotNull);
    expect(
      FirestoreRestService.decodeFields(
        remote.docs['products/USED']!['fields'],
      )['status'],
      'DELETED',
    );
  });

  test(
    'product stock reads enforce tenant, business and selected outlet',
    () async {
      for (final entry in [
        {
          'id': 'A',
          'tenantId': 'T',
          'businessId': 'B',
          'outletId': 'O',
          'quantityOnHand': 2000,
        },
        {
          'id': 'B',
          'tenantId': 'OTHER',
          'businessId': 'B',
          'outletId': 'O',
          'quantityOnHand': 9000,
        },
        {
          'id': 'C',
          'tenantId': 'T',
          'businessId': 'B',
          'outletId': 'OTHER',
          'quantityOnHand': 8000,
        },
      ]) {
        await seedLocal('stock_balances', entry['id'] as String, {
          ...entry,
          'variantId': 'V',
        });
      }
      remote.offline = true;
      expect(
        await ProductRepository(service, service).getOutletProductStock(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'O',
          token: token('U'),
        ),
        {'V': 2000},
      );
    },
  );

  test('brush measurements remain separate from selling units through offline restart, edit and new SKU', () async {
    await installProductTestCatalogue(
      source: await local(),
      seedRemote: remote.seed,
    );
    await seedLocal('brands', 'BR', {
      'brandId': 'BR',
      'name': 'Test Brand',
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await service.setScope(tenant: 'T', business: 'B');
    await sync.sync();
    remote.offline = true;
    connectivity.available = false;
    var repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    final template = await repo.loadTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId:
          'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH',
      token: token('U'),
    );
    expect(
      template
          .firstWhere((a) => a.id == 'brushSize')
          .measurementUnitAttributeId,
      'sizeUnit',
    );
    final fields = <String, dynamic>{
      'brandId': 'BR',
      'categoryId': 'SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES',
      'subcategoryId':
          'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH',
      'hsnCode': '960340',
      'attributeValues': {'brushType': 'Flat'},
      'imageUrl': 'https://example.com/brush.png',
    };
    Map<String, dynamic> variant(num size) => {
      'attributeValues': {
        'brushSize': size,
        'sizeUnit': 'inch',
        'packSize': size,
        'unit': 'Piece',
        'soldAs': 'Piece',
      },
      'baseUnitId': 'SYS_UNIT_PIECE',
      'commercialUnitId': 'SYS_UNIT_PIECE',
      'baseQuantityPerCommercialUnit': 1,
      'sellingPrice': 12500,
      'purchaseRate': 9000,
      'mrp': 15000,
      'status': 'ACTIVE',
    };
    await repo.createStructuredProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: 'Professional Brush',
      actorUid: 'U',
      token: token('U'),
      productFields: fields,
      variants: [variant(1), variant(2), variant(4)],
    );
    var product = (await repo.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    )).single;
    expect(
      product.variants.every(
        (v) =>
            v.sellingPrice == 12500 && v.purchaseRate == 9000 && v.mrp == 15000,
      ),
      isTrue,
    );
    expect(product.hsnCode, '960340');
    expect(product.attributeValues.containsKey('hsnCode'), false);
    expect(product.variants.map((v) => v.sku).toSet().length, 3);
    expect(product.variants.map((v) => v.barcode).toSet(), {
      '700000000001',
      '700000000002',
      '700000000003',
    });
    expect(
      product.variants.every(
        (v) =>
            v.baseUnitId == 'SYS_UNIT_PIECE' &&
            v.commercialUnitId == 'SYS_UNIT_PIECE' &&
            v.baseQuantityPerCommercialUnit == 1,
      ),
      true,
    );
    final originalIds = product.variants.map((v) => v.variantId).toSet();
    sync.dispose();
    await database.close();
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () => Future.value(session('U')),
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    product = (await repo.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    )).single;
    expect(product.variants.map((v) => v.barcode).toSet(), {
      '700000000001',
      '700000000002',
      '700000000003',
    });
    expect(product.variants.length, 3);
    expect(product.productImage, 'https://example.com/brush.png');
    await repo.updateStructuredProduct(
      tenantId: 'T',
      businessId: 'B',
      productId: product.productId,
      productName: product.name,
      actorUid: 'U',
      token: token('U'),
      productFields: fields,
      variants: [
        for (final v in product.variants)
          {
            ...variant(v.attributeValues['brushSize'] as num),
            'variantId': v.variantId,
          },
        variant(1.5),
      ],
    );
    product = (await repo.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    )).single;
    expect(product.variants.length, 4);
    expect(product.variants.map((v) => v.sku).toSet().length, 4);
    expect(product.variants.map((v) => v.barcode).toSet(), {
      '700000000001',
      '700000000002',
      '700000000003',
      '700000000004',
    });
    expect(
      product.variants.map((v) => v.variantId).toSet().containsAll(originalIds),
      true,
    );
    remote.offline = false;
    connectivity.available = true;
    await sync.sync();
    expect(sync.error, isNull);
    expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
  });

  test('initial pull caches catalogue; offline restart reads arrays and business options locally', () async {
    remote.seed('brands', 'S', {
      'name': 'Central Brand',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });
    remote.seed('brands', 'B', {
      'name': 'Custom Brand',
      'scopeType': 'BUSINESS',
      'status': 'ACTIVE',
      'tenantId': 'T',
      'businessId': 'B',
    });
    remote.seed('product_attributes', 'A', {
      'attributeId': 'A',
      'name': 'Surface',
      'dataType': 'MULTI_SELECT',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });
    remote.seed('subcategory_attribute_templates', 'S_A', {
      'attributeId': 'A',
      'subcategoryId': 'S',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
      'defaultValue': ['Wall'],
      'attributeLevel': 'VARIANT',
      'required': true,
    });
    remote.seed('product_attribute_options', 'O', {
      'attributeId': 'A',
      'name': 'Wall',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });
    await service.setScope(tenant: 'T', business: 'B');
    await sync.sync();
    final repo = ProductRepository(service, service);
    expect(
      (await repo.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'BRAND',
        token: token('U'),
      )).length,
      2,
    );
    final before = remote.queries;
    await repo.getMasterValues(
      tenantId: 'T',
      businessId: 'B',
      masterType: 'BRAND',
      token: token('U'),
    );
    expect(remote.queries, before);
    sync.dispose();
    await database.close();
    remote.offline = true;
    connectivity.available = false;
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    final reopened = ProductRepository(service, service);
    final attrs = await reopened.loadTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: 'S',
      token: token('U'),
    );
    expect(attrs.single.defaultValue, ['Wall']);
    expect(attrs.single.options, ['Wall']);
    expect(
      (await reopened.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'BRAND',
        token: token('U'),
      )).length,
      2,
    );
  });
  test(
    'offline create persists across restart; retries upload exactly once',
    () async {
      connectivity.available = false;
      await service.createDocument('products', 'P', {
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Offline product',
      }, idToken: token('U'));
      expect(remote.docs, isEmpty);
      expect(
        (await (await local()).row('products', 'P'))!['syncStatus'],
        'PENDING_CREATE',
      );
      sync.dispose();
      await database.close();
      database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      connectivity.available = true;
      sync = SyncEngine(
        remote,
        connectivity,
        sessionProvider: () async => session('U'),
      );
      service = OfflineFirestoreService(database, remote, sync);
      await service.activate('U');
      expect(
        FirestoreRestService.decodeFields(
          (await service.getDocument(
            'products',
            'P',
            idToken: token('U'),
          ))['fields'],
        )['name'],
        'Offline product',
      );
      remote.loseAcknowledgement = true;
      await sync.sync();
      expect(await SyncOutboxRepository(await local()).pendingCount(), 1);
      await sync.retry();
      expect(remote.commits, 1);
      expect(
        (await (await local()).row('products', 'P'))!['syncStatus'],
        'SYNCED',
      );
      expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
    },
  );
  test('dependent create and edit replay in order without losing latest local value', () async {
    connectivity.available = false;
    await service.createDocument('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'First',
    }, idToken: token('U'));
    await service.updateDocument('products', 'P', {
      'name': 'Second',
    }, idToken: token('U'));
    connectivity.available = true;
    await Future.wait([sync.sync(), sync.sync()]);
    expect(remote.commits, 2);
    expect(
      FirestoreRestService.decodeFields(
        remote.docs['products/P']!['fields'],
      )['name'],
      'Second',
    );
    expect(
      (await (await local()).row('products', 'P'))!['syncStatus'],
      'SYNCED',
    );
  });
  test(
    'pull protects pending edits and upload records version conflicts',
    () async {
      await seedLocal('products', 'P', {
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Original',
      });
      connectivity.available = false;
      await service.updateDocument('products', 'P', {
        'name': 'Local edit',
      }, idToken: token('U'));
      remote.seed('products', 'P', {
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Remote edit',
      });
      await (await local()).upsertRemote('products', [
        remote.docs['products/P']!,
      ]);
      final fields = FirestoreRestService.decodeFields(
        (await service.getDocument(
          'products',
          'P',
          idToken: token('U'),
        ))['fields'],
      );
      expect(fields['name'], 'Local edit');
      connectivity.available = true;
      await sync.sync();
      expect(remote.commits, 0);
      expect(sync.state, SyncState.error);
      expect(
        (await (await local()).db.query('sync_outbox')).single['status'],
        'FAILED',
      );
      expect(await (await local()).db.query('sync_conflicts'), isNotEmpty);
    },
  );
  test('soft deletion survives failed network and disappears after confirmed upload', () async {
    await seedLocal('products', 'P', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Product',
    });
    remote.offline = true;
    await service.deleteDocument('products', 'P', idToken: token('U'));
    await sync.sync();
    expect((await (await local()).row('products', 'P'))!['isDeleted'], 1);
    expect(await SyncOutboxRepository(await local()).pendingCount(), 1);
    remote.offline = false;
    await sync.retry();
    expect(
      FirestoreRestService.decodeFields(
        remote.docs['products/P']!['fields'],
      )['isDeleted'],
      isTrue,
    );
    expect(
      (await (await local()).row('products', 'P'))!['syncStatus'],
      'SYNCED',
    );
  });
  test('local queries isolate tenants and accounts; rollback leaves no partial records', () async {
    connectivity.available = false;
    await service.createDocument('products', 'A', {
      'tenantId': 'T',
      'businessId': 'A',
      'name': 'A',
    }, idToken: token('U'));
    await service.createDocument('products', 'B', {
      'tenantId': 'OTHER',
      'businessId': 'B',
      'name': 'B',
    }, idToken: token('U'));
    final docs = await service.queryDocuments(
      collection: 'products',
      filters: [
        const FirestoreFilter('tenantId', 'EQUAL', 'T'),
        const FirestoreFilter('businessId', 'EQUAL', 'A'),
      ],
      idToken: token('U'),
    );
    expect(docs.single['name'], 'products/A');
    await expectLater(
      service.runAtomicOperation((tx) async {
        tx.create('products', 'ROLLBACK', {'name': 'No'});
        tx.create('products', 'A', {'name': 'Duplicate'});
      }, idToken: token('U')),
      throwsA(isA<AppException>()),
    );
    expect(await (await local()).row('products', 'ROLLBACK'), isNull);
    service.logout();
    await service.activate('OTHER');
    expect(
      await service.queryDocuments(
        collection: 'products',
        filters: [],
        idToken: token('OTHER'),
      ),
      isEmpty,
    );
  });
  test('real product creation queues product, variants, unique key and sequences atomically', () async {
    await installProductTestCatalogue(
      source: await local(),
      seedRemote: remote.seed,
    );
    for (final entry in {
      'brands': 'BR',
      'product_categories': 'CA',
      'product_subcategories': 'SU',
      'units': 'UN',
    }.entries) {
      await seedLocal(entry.key, entry.value, {
        'name': entry.value,
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'status': 'ACTIVE',
        if (entry.key == 'product_subcategories') 'categoryId': 'CA',
        if (entry.key == 'units') 'measurementDimension': 'MASS',
        if (entry.key == 'product_subcategories') 'subcategoryId': entry.value,
        if (entry.key == 'product_subcategories')
          'unitRules': {
            'allowedPackUnits': ['UN'],
            'defaultPackUnit': 'UN',
            'allowedSellingUnits': ['UN'],
            'defaultSellingUnit': 'UN',
            'allowedBaseUnits': ['UN'],
            'defaultBaseUnit': 'UN',
            'conversionAllowed': true,
            'conversionDimension': 'MASS',
          },
      });
    }
    await seedLocal('subcategory_attribute_templates', 'SU_ATTR', {
      'subcategoryId': 'SU',
      'attributeId': 'testAttr',
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await seedLocal('product_attributes', 'testAttr', {
      'attributeId': 'testAttr',
      'name': 'Test Attr',
      'dataType': 'TEXT',
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await service.setScope(tenant: 'T', business: 'B');
    await sync.sync();
    connectivity.available = false;
    final repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    Future<void> create(String name) => repo.createStructuredProduct(
      tenantId: 'T',
      businessId: 'B',
      productName: name,
      actorUid: 'U',
      token: token('U'),
      productFields: {
        'brandId': 'BR',
        'brand': 'BR',
        'categoryId': 'CA',
        'subcategoryId': 'SU',
        'attributeValues': <String, dynamic>{},
      },
      variants: [
        {
          'displayName': 'Standard',
          'baseUnitId': 'UN',
          'commercialUnitId': 'UN',
          'baseQuantityPerCommercialUnit': 1,
          'attributeValues': <String, dynamic>{},
        },
      ],
    );
    await create('Offline One');
    await create('Offline Two');
    final products = await repo.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    );
    expect(products.length, 2);
    final source = await local();
    final queued = await source.db.query('sync_outbox');
    expect(queued.length, 12);
    expect(
      products
          .expand((product) => product.variants)
          .map((v) => v.barcode)
          .toSet(),
      {'700000000001', '700000000002'},
    );
    expect(queued.map((r) => r['batchId']).toSet().length, 2);
    expect(remote.commits, 0);
    connectivity.available = true;
    await sync.sync();
    expect(sync.error, isNull);
    expect(remote.commits, 2);
    expect(await SyncOutboxRepository(source).pendingCount(), 0);
    final remoteProducts = remote.docs.entries
        .where((e) => e.key.startsWith('products/'))
        .toList();
    expect(remoteProducts.length, 2);
    expect(
      remoteProducts
          .map(
            (e) => FirestoreRestService.decodeFields(
              e.value['fields'],
            )['productCode'],
          )
          .toSet(),
      {'PRD-0001', 'PRD-0002'},
    );
    expect(
      remote.docs.keys.where((k) => k.startsWith('product_variants/')).length,
      2,
    );
    expect(
      remote.docs.entries
          .where((entry) => entry.key.startsWith('product_variants/'))
          .map(
            (entry) => FirestoreRestService.decodeFields(
              entry.value['fields'],
            )['barcode'],
          )
          .toSet(),
      {'700000000001', '700000000002'},
    );
    await expectLater(create('Offline One'), throwsA(isA<AppException>()));
  });
  test('catalogue deactivation and remote removal hide synced values but protect pending ones', () async {
    await service.setScope(tenant: 'T', business: 'B');
    remote.seed('brands', 'ACTIVE', {
      'name': 'Central',
      'scopeType': 'SYSTEM',
      'status': 'ACTIVE',
    });
    await sync.sync();
    remote.seed('brands', 'ACTIVE', {
      'name': 'Central',
      'scopeType': 'SYSTEM',
      'status': 'INACTIVE',
    });
    await sync.sync(refreshCatalogue: true);
    final repo = ProductRepository(service, service);
    expect(
      await repo.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'BRAND',
        token: token('U'),
      ),
      isEmpty,
    );
    connectivity.available = false;
    await service.createDocument('brands', 'LOCAL', {
      'name': 'Pending',
      'scopeType': 'BUSINESS',
      'status': 'ACTIVE',
      'tenantId': 'T',
      'businessId': 'B',
    }, idToken: token('U'));
    await (await local()).upsertRemote(
      'brands',
      [],
      completeQuery: [const FirestoreFilter('tenantId', 'EQUAL', 'T')],
    );
    expect((await (await local()).row('brands', 'LOCAL'))!['isDeleted'], 0);
    remote.docs.remove('brands/ACTIVE');
    await (await local()).upsertRemote(
      'brands',
      [],
      completeQuery: [const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM')],
    );
    expect((await (await local()).row('brands', 'ACTIVE'))!['isDeleted'], 1);
  });
  test('failed batch blocks its dependants while independent operations still upload', () async {
    await seedLocal('products', 'P', {'name': 'Base'});
    connectivity.available = false;
    await service.updateDocument('products', 'P', {
      'name': 'Local',
    }, idToken: token('U'));
    await service.updateDocument('products', 'P', {
      'name': 'Dependent',
    }, idToken: token('U'));
    await service.createDocument('brands', 'INDEPENDENT', {
      'name': 'Independent',
      'scopeType': 'BUSINESS',
    }, idToken: token('U'));
    remote.seed('products', 'P', {'name': 'Other device'});
    connectivity.available = true;
    await sync.sync();
    expect(remote.docs.containsKey('brands/INDEPENDENT'), isTrue);
    expect(
      FirestoreRestService.decodeFields(
        remote.docs['products/P']!['fields'],
      )['name'],
      'Other device',
    );
    expect(await SyncOutboxRepository(await local()).pendingCount(), 2);
    expect(sync.state, SyncState.error);
  });
  test('persistent lease prevents concurrent engines and recovers interrupted PROCESSING batch', () async {
    connectivity.available = false;
    await service.createDocument('products', 'P', {
      'name': 'Keep',
    }, idToken: token('U'));
    final outbox = SyncOutboxRepository(await local());
    expect(await outbox.acquire('ONE'), isTrue);
    expect(await outbox.acquire('TWO'), isFalse);
    await (await local()).db.update('sync_outbox', {'status': 'PROCESSING'});
    await (await local()).db.update('sync_lease', {
      'expiresAt': DateTime.utc(2000).toIso8601String(),
    });
    expect(await outbox.acquire('TWO'), isTrue);
    expect((await outbox.nextBatch()).single['status'], 'PENDING');
    await outbox.release('TWO');
    connectivity.available = true;
    await sync.sync();
    expect(remote.commits, 1);
  });
  test('supplier refund records money-in once and preserves payable/payment history', () async {
    await seedLocal('supplier_businesses', 'SUP_B', {
      'supplierBusinessId': 'SUP_B',
      'supplierId': 'SUP',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await seedLocal('supplier_balances', 'SUP_B', {
      'tenantId': 'T',
      'businessId': 'B',
      'supplierBusinessId': 'SUP_B',
      'totalPayable': 7500,
      'unallocatedAdvance': 48160,
    });
    await seedLocal('supplier_payments', 'SPAY-ORIGINAL', {
      'paymentId': 'SPAY-ORIGINAL',
      'tenantId': 'T',
      'businessId': 'B',
      'supplierBusinessId': 'SUP_B',
      'amount': 368160,
      'allocatedAmount': 320000,
      'unallocatedAmount': 48160,
      'paymentType': 'AGAINST_BILL',
    });
    connectivity.available = false;
    await service.setScope(tenant: 'T', business: 'B', outlet: 'O');
    final registeredRefundQueries = await (await local()).db.query(
      'sync_queries',
      where: "collectionName IN ('supplier_refunds','financial_transactions') AND active=1",
    );
    expect(registeredRefundQueries, hasLength(2));
    final repository = SupplierRepository(service, service);

    final first = await repository.recordSupplierRefund(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierBusinessId: 'SUP_B',
      amount: 30000,
      refundDate: DateTime.utc(2026, 10, 15),
      paymentMode: 'UPI',
      referenceNo: 'UTR-REFUND-1',
      reason: 'Supplier returned excess advance',
      notes: 'Partial refund',
      createdByUid: 'U',
      requestId: 'SREQ-TEST-1',
      token: token('U'),
    );
    final retry = await repository.recordSupplierRefund(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierBusinessId: 'SUP_B',
      amount: 30000,
      refundDate: DateTime.utc(2026, 10, 15),
      paymentMode: 'UPI',
      referenceNo: 'UTR-REFUND-1',
      reason: 'Supplier returned excess advance',
      notes: 'Partial refund',
      createdByUid: 'U',
      requestId: 'SREQ-TEST-1',
      token: token('U'),
    );
    expect(retry.refundId, first.refundId);

    final source = await local();
    final balanceRow = await source.row('supplier_balances', 'SUP_B');
    final balance = FirestoreRestService.decodeFields(
      jsonDecode(balanceRow!['payloadJson'] as String),
    );
    expect(balance['unallocatedAdvance'], 18160);
    expect(balance['totalPayable'], 7500);
    final paymentRow = await source.row('supplier_payments', 'SPAY-ORIGINAL');
    final payment = FirestoreRestService.decodeFields(
      jsonDecode(paymentRow!['payloadJson'] as String),
    );
    expect(payment['amount'], 368160);
    expect(payment['allocatedAmount'], 320000);
    expect(payment['unallocatedAmount'], 48160);
    final refundRow = await source.row('supplier_refunds', first.refundId);
    final refund = FirestoreRestService.decodeFields(
      jsonDecode(refundRow!['payloadJson'] as String),
    );
    expect(refund['status'], 'POSTED');
    expect(refund['amount'], 30000);
    final financialRow = await source.row(
      'financial_transactions',
      'FIN-${first.refundId}',
    );
    final financial = FirestoreRestService.decodeFields(
      jsonDecode(financialRow!['payloadJson'] as String),
    );
    expect(financial['direction'], 'IN');
    expect(financial['transactionType'], 'SUPPLIER_REFUND');
    final ledgerRows = await source.query('supplier_ledger_entries', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
    ]);
    final refundLedger = ledgerRows
        .map((row) => FirestoreRestService.decodeFields(row['fields']))
        .where((row) => row['entryType'] == 'SUPPLIER_REFUND')
        .toList();
    expect(refundLedger, hasLength(1));
    expect(refundLedger.single['debit'], 0);
    expect(refundLedger.single['credit'], 0);
    final outbox = await source.db.query(
      'sync_outbox',
      where: 'entityType IN (?, ?, ?, ?)',
      whereArgs: [
        'supplier_refunds',
        'financial_transactions',
        'supplier_balances',
        'supplier_ledger_entries',
      ],
    );
    expect(outbox, hasLength(4));
    expect(outbox.map((row) => row['batchId']).toSet(), hasLength(1));

    final fullRefund = await repository.recordSupplierRefund(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierBusinessId: 'SUP_B',
      amount: 18160,
      refundDate: DateTime.utc(2026, 10, 15),
      paymentMode: 'CASH',
      referenceNo: '',
      reason: 'Return remaining advance',
      notes: '',
      createdByUid: 'U',
      requestId: 'SREQ-TEST-2',
      token: token('U'),
    );
    expect(fullRefund.status, 'POSTED');
    final afterFullRow = await source.row('supplier_balances', 'SUP_B');
    final afterFull = FirestoreRestService.decodeFields(
      jsonDecode(afterFullRow!['payloadJson'] as String),
    );
    expect(afterFull['unallocatedAdvance'], 0);
    expect(afterFull['totalPayable'], 7500);

    await expectLater(
      repository.recordSupplierRefund(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'O',
        supplierId: 'SUP',
        supplierBusinessId: 'SUP_B',
        amount: 1,
        refundDate: DateTime.utc(2026, 10, 15),
        paymentMode: 'CASH',
        referenceNo: '',
        reason: 'Over available advance',
        notes: '',
        createdByUid: 'U',
        requestId: 'SREQ-TEST-3',
        token: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    connectivity.available = true;
    await sync.sync();
    expect(
      remote.docs.containsKey('supplier_refunds/${first.refundId}'),
      isTrue,
    );
    expect(
      remote.docs.containsKey('financial_transactions/FIN-${first.refundId}'),
      isTrue,
    );
    final remoteBalance = FirestoreRestService.decodeFields(
      remote.docs['supplier_balances/SUP_B']!['fields'],
    );
    expect(remoteBalance['unallocatedAdvance'], 0);
    expect(await SyncOutboxRepository(source).pendingCount(), 0);
    expect(await source.query('supplier_refunds', []), hasLength(2));
    expect(await source.query('financial_transactions', []), hasLength(2));
    expect(
      await source.db.query(
        'sync_conflicts',
        where: "entityType IN ('supplier_refunds','financial_transactions') AND resolved=0",
      ),
      isEmpty,
    );
  });

  test('offline purchase approval and payment preserve atomic inventory and ledger posting', () async {
    await seedLocal('suppliers', 'SUP', {
      'supplierId': 'SUP',
      'name': 'Supplier',
      'tenantId': 'T',
      'status': 'ACTIVE',
    });
    await seedLocal('supplier_businesses', 'SUP_B', {
      'supplierBusinessId': 'SUP_B',
      'supplierId': 'SUP',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await seedLocal('supplier_balances', 'SUP_B', {
      'tenantId': 'T',
      'businessId': 'B',
      'supplierBusinessId': 'SUP_B',
      'totalPayable': 0,
    });
    await seedLocal('product_variants', 'V', {
      'variantId': 'V',
      'name': 'Item',
      'tenantId': 'T',
      'businessId': 'B',
      'productId': 'P',
      'baseUnitId': 'UN',
      'status': 'ACTIVE',
    });
    await seedLocal('outlet_products', 'OP', {
      'outletProductId': 'OP',
      'tenantId': 'T',
      'businessId': 'B',
      'outletId': 'O',
      'productId': 'P',
      'status': 'ACTIVE',
      'isActive': true,
    });
    connectivity.available = false;
    await service.setScope(tenant: 'T', business: 'B', outlet: 'O');
    final suppliers = SupplierRepository(service, service);
    final purchases = PurchaseRepository(service, suppliers, service);
    final draft = await purchases.createDraft(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierInvoiceNumber: 'INV-1',
      invoiceDate: DateTime.utc(2026, 10, 2),
      purchaseType: 'DIRECT',
      placeOfSupplyStateCode: '27',
      businessStateCode: '27',
      discountAmount: 0,
      chargesAmount: 0,
      roundOff: 0,
      createdBy: 'U',
      token: token('U'),
      items: [
        PurchaseBillItemModel(
          goodsReceiptItemId: 'LINE',
          variantId: 'V',
          productName: 'Item',
          unitId: 'UN',
          conversionFactor: 1000,
          quantity: 2000,
          rate: 5000,
          gstRateBps: 0,
          taxableAmount: 10000,
          taxAmount: 0,
          productId: 'P',
          supplierLotNo: 'SUP-LOT-7',
          manufacturingDate: DateTime.utc(2026, 9, 1),
          expiryDate: DateTime.utc(2028, 3, 31),
          storageType: 'GODOWN',
          storageLocationId: 'GOD-001',
          rackId: 'RACK-G05',
        ),
      ],
    );
    final editedDraft = await purchases.updateDraft(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      billId: draft.purchaseBillId,
      supplierId: 'SUP',
      supplierInvoiceNumber: 'INV-1-EDITED',
      invoiceDate: DateTime.utc(2026, 10, 2),
      purchaseDate: DateTime.utc(2026, 10, 3),
      placeOfSupplyStateCode: '27',
      businessStateCode: '27',
      discountAmount: 0,
      chargesAmount: 0,
      roundOff: 0,
      updatedBy: 'U',
      token: token('U'),
      items: [
        PurchaseBillItemModel(
          goodsReceiptItemId: 'LINE',
          variantId: 'V',
          productName: 'Item',
          unitId: 'UN',
          conversionFactor: 1000,
          quantity: 2000,
          rate: 6000,
          gstRateBps: 0,
          taxableAmount: 12000,
          taxAmount: 0,
          productId: 'P',
          supplierLotNo: 'SUP-LOT-7',
          manufacturingDate: DateTime.utc(2026, 9, 1),
          expiryDate: DateTime.utc(2028, 3, 31),
          storageType: 'GODOWN',
          storageLocationId: 'GOD-001',
          rackId: 'RACK-G05',
        ),
      ],
    );
    expect(editedDraft.supplierInvoiceNumber, 'INV-1-EDITED');
    expect(editedDraft.items.single.internalBatchNo, 'BAT-000001');
    expect(editedDraft.items.single.rate, 6000);
    expect(draft.items.single.barcodeSnapshot, isNull);
    expect(draft.items.single.internalBatchNo, 'BAT-000001');
    final localSource = await local();
    final variantRow = await localSource.row('product_variants', 'V');
    expect(
      FirestoreRestService.decodeFields(
        jsonDecode(variantRow!['payloadJson'] as String),
      )['barcode'],
      isNull,
    );
    final batchId = 'BATCH_${draft.purchaseBillId}_LINE';
    final batchRow = await localSource.row('inventory_batches', batchId);
    final batch = FirestoreRestService.decodeFields(
      jsonDecode(batchRow!['payloadJson'] as String),
    );
    expect(batch['businessId'], 'B');
    expect(batch['outletId'], 'O');
    expect(batch['internalBatchNo'], 'BAT-000001');
    expect(batch['barcode'], isNull);
    expect(batch['supplierLotNo'], 'SUP-LOT-7');
    expect(batch['manufacturingDate'], DateTime.utc(2026, 9, 1));
    expect(batch['expiryDate'], DateTime.utc(2028, 3, 31));
    expect(batch['storageType'], 'GODOWN');
    expect(batch['storageLocationId'], 'GOD-001');
    expect(batch['rackId'], 'RACK-G05');
    final history = await purchases.getBills(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      token: token('U'),
    );
    expect(history.single.items.single.barcodeSnapshot, isNull);
    expect(history.single.items.single.internalBatchNo, 'BAT-000001');
    expect(
      (await localSource.db.query('sync_outbox'))
          .map((row) => row['entityType'])
          .toSet(),
      containsAll([
        'purchase_bills',
        'purchase_bill_items',
        'inventory_batches',
      ]),
    );
    await localSource.db.update(
      'local_inventory_batches',
      {
        'payloadJson': jsonEncode(
          FirestoreRestService.encodeFields({...batch, 'productId': 'WRONG'}),
        ),
      },
      where: 'remoteId=?',
      whereArgs: [batchId],
    );
    await expectLater(
      purchases.approveDirectBill(
        tenantId: 'T',
        billId: draft.purchaseBillId,
        userId: 'U',
        token: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    expect(
      FirestoreRestService.decodeFields(
        jsonDecode(
          (await localSource.row(
                'purchase_bills',
                draft.purchaseBillId,
              ))!['payloadJson']
              as String,
        ),
      )['status'],
      'DRAFT',
    );
    expect(
      await localSource.row(
        'goods_receipts',
        'AUTO_GRN_${draft.purchaseBillId}',
      ),
      isNull,
    );
    expect(
      await localSource.row(
        'inventory_batch_movements',
        'BATCH_MOVEMENT_PURCHASE_RECEIPT_${draft.purchaseBillId}_LINE',
      ),
      isNull,
    );
    expect(
      await localSource.row(
        'inventory_transactions',
        'PURCHASE_RECEIPT_${draft.purchaseBillId}_LINE',
      ),
      isNull,
    );
    await localSource.db.update(
      'local_inventory_batches',
      {'payloadJson': batchRow['payloadJson']},
      where: 'remoteId=?',
      whereArgs: [batchId],
    );
    final approvedBill = await purchases.approveDirectBill(
      tenantId: 'T',
      billId: draft.purchaseBillId,
      userId: 'U',
      token: token('U'),
    );
    final correction = await purchases.correctApprovedMetadata(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      billId: draft.purchaseBillId,
      reason: 'Correct supplier lot and expiry details',
      correctedByUid: 'U',
      supplierInvoiceNumber: 'INV-1-EDITED',
      invoiceDate: DateTime.utc(2026, 10, 2),
      purchaseDate: DateTime.utc(2026, 10, 3),
      lineMetadata: {
        'LINE': {
          'supplierLotNo': 'SUP-LOT-8',
          'manufacturingDate': DateTime.utc(2026, 9, 1),
          'expiryDate': DateTime.utc(2028, 4, 30),
        },
      },
      token: token('U'),
    );
    expect(correction.changedFields, contains('items.LINE.supplierLotNo'));
    expect(approvedBill.status, 'APPROVED');
    final correctedBatchRow = await localSource.row(
      'inventory_batches',
      'BATCH_${draft.purchaseBillId}_LINE',
    );
    final correctedBatch = FirestoreRestService.decodeFields(
      jsonDecode(correctedBatchRow!['payloadJson'] as String),
    );
    expect(correctedBatch['availableQty'], 2000);
    expect(correctedBatch['internalBatchNo'], 'BAT-000001');
    expect(correctedBatch['supplierLotNo'], 'SUP-LOT-8');
    expect(correctedBatch['expiryDate'], DateTime.utc(2028, 4, 30));
    final audits = await purchases.getCorrections(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      purchaseId: draft.purchaseBillId,
      token: token('U'),
    );
    expect(audits, hasLength(1));
    expect(audits.single.beforeSnapshot['items'], hasLength(1));
    await expectLater(
      service.updateDocument('purchase_corrections', correction.correctionId, {
        'reason': 'tampered',
      }, idToken: token('U')),
      throwsA(isA<AppException>()),
    );
    expect(
      (await purchases.getCorrections(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'O',
        purchaseId: draft.purchaseBillId,
        token: token('U'),
      )).single.reason,
      'Correct supplier lot and expiry details',
    );
    final receiptLine = await localSource.row(
      'goods_receipt_items',
      'AUTO_GRN_${draft.purchaseBillId}_LINE',
    );
    final receipt = FirestoreRestService.decodeFields(
      jsonDecode(receiptLine!['payloadJson'] as String),
    );
    expect(receipt['storageType'], 'GODOWN');
    expect(receipt['storageLocationId'], 'GOD-001');
    expect(receipt['rackId'], 'RACK-G05');
    await purchases.approveDirectBill(
      tenantId: 'T',
      billId: draft.purchaseBillId,
      userId: 'U',
      token: token('U'),
    );
    await purchases.recordPayment(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierBusinessId: 'SUP_B',
      purchaseBillId: draft.purchaseBillId,
      amount: 5000,
      paymentMode: 'CASH',
      transactionReference: '',
      userId: 'U',
      token: token('U'),
    );
    final source = await local();
    final movementRows = await source.query('inventory_batch_movements', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
      const FirestoreFilter('outletId', 'EQUAL', 'O'),
      FirestoreFilter('batchId', 'EQUAL', batchId),
    ]);
    expect(movementRows, hasLength(1));
    final movement = FirestoreRestService.decodeFields(
      movementRows.single['fields'],
    );
    expect(
      (await source.db.query('sync_outbox'))
          .map((row) => row['entityType'])
          .toSet(),
      contains('inventory_batch_movements'),
    );
    expect(movement['movementType'], 'PURCHASE_RECEIPT');
    expect(movement['direction'], 'IN');
    expect(movement['quantity'], 2000);
    expect(movement['referenceType'], 'GOODS_RECEIPT');
    expect(movement['referenceId'], 'AUTO_GRN_${draft.purchaseBillId}');
    expect(
      movement['referenceLineId'],
      'AUTO_GRN_${draft.purchaseBillId}_LINE',
    );
    expect(
      await purchases.batchMovementRepository.derivedAvailableForBatch(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'O',
        batchId: batchId,
        token: token('U'),
      ),
      2000,
    );
    await expectLater(
      purchases.batchMovementRepository.validateOutboundQuantity(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'O',
        batchId: batchId,
        quantity: 2001,
        token: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      service.updateDocument(
        'inventory_batch_movements',
        movement['movementId'] as String,
        {'reason': 'rewritten'},
        idToken: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    final movementMutation = (await source.db.query(
      'sync_outbox',
      where: 'entityType=? AND documentId=?',
      whereArgs: ['inventory_batch_movements', movement['movementId']],
    )).single;
    final receiptMutation = (await source.db.query(
      'sync_outbox',
      where: 'entityType=? AND documentId=?',
      whereArgs: [
        'inventory_transactions',
        'PURCHASE_RECEIPT_${draft.purchaseBillId}_LINE',
      ],
    )).single;
    expect(movementMutation['batchId'], receiptMutation['batchId']);
    expect(
      (await source.db.query('sync_outbox'))
          .map((r) => r['batchId'])
          .toSet()
          .length,
      5,
    );
    expect(await source.query('inventory_transactions', []), hasLength(1));
    expect(await source.query('supplier_ledger_entries', []), hasLength(2));
    expect(remote.commits, 0);
    connectivity.available = true;
    await sync.sync();
    expect(sync.error, isNull);
    expect(remote.commits, 5);
    expect(await SyncOutboxRepository(source).pendingCount(), 0);
    final remoteBatch = FirestoreRestService.decodeFields(
      remote.docs['inventory_batches/$batchId']!['fields'],
    );
    expect(remoteBatch['tenantId'], 'T');
    expect(remoteBatch['businessId'], 'B');
    expect(remoteBatch['outletId'], 'O');
    expect(remoteBatch['internalBatchNo'], 'BAT-000001');
    expect(remoteBatch['storageType'], 'GODOWN');
    expect(remoteBatch['storageLocationId'], 'GOD-001');
    expect(remoteBatch['rackId'], 'RACK-G05');
    expect(remoteBatch['availableQty'], 2000);
    expect(remoteBatch['supplierLotNo'], 'SUP-LOT-8');
    expect(
      remote.docs.containsKey(
        'purchase_corrections/${correction.correctionId}',
      ),
      isTrue,
    );
    final remoteMovement = FirestoreRestService.decodeFields(
      remote
          .docs['inventory_batch_movements/${movement['movementId']}']!['fields'],
    );
    expect(remoteMovement['batchId'], batchId);
    expect(remoteMovement['businessId'], 'B');
    expect(remoteMovement['outletId'], 'O');
    expect(remoteMovement['quantity'], 2000);
    final movementPull = (await source.db.query(
      'sync_queries',
      where: "collectionName='inventory_batch_movements' AND active=1",
    )).single;
    expect(movementPull['lastSyncedAt'], isNotNull);
    expect(movementPull['lastError'], isNull);
    expect(
      (await source.row(
        'inventory_batch_movements',
        movement['movementId'] as String,
      ))!['syncStatus'],
      'SYNCED',
    );
    final remoteItem = FirestoreRestService.decodeFields(
      remote.docs['purchase_bill_items/LINE']!['fields'],
    );
    expect(remoteItem['purchaseId'], draft.purchaseBillId);
    expect(remoteItem['variantId'], 'V');
    expect(remoteItem['storageType'], 'GODOWN');
    expect(remoteItem['storageLocationId'], 'GOD-001');
    expect(remoteItem['rackId'], 'RACK-G05');
    final bill = FirestoreRestService.decodeFields(
      remote.docs['purchase_bills/${draft.purchaseBillId}']!['fields'],
    );
    expect(bill['status'], 'APPROVED');
    expect(bill['paidAmount'], 5000);
    expect(bill['outstandingAmount'], 7000);
    expect(
      remote.docs.keys.where((k) => k.startsWith('inventory_transactions/')),
      hasLength(1),
    );
    final remoteTransaction = FirestoreRestService.decodeFields(
      remote
          .docs['inventory_transactions/PURCHASE_RECEIPT_${draft.purchaseBillId}_LINE']!['fields'],
    );
    expect(remoteTransaction['locationType'], 'GODOWN');
    expect(remoteTransaction['locationId'], 'GOD-001');
    expect(remoteTransaction['rackId'], 'RACK-G05');
    expect(remoteTransaction['productId'], 'P');
    final stock = FirestoreRestService.decodeFields(
      remote.docs['stock_balances/T_O_V']!['fields'],
    );
    expect(stock['quantityOnHand'], 2000);
    final advanced = await purchases.correctApprovedMetadata(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      billId: draft.purchaseBillId,
      reason: 'Correct received quantity and prices',
      correctedByUid: 'U',
      supplierInvoiceNumber: 'INV-1-EDITED',
      invoiceDate: DateTime.utc(2026, 10, 2),
      purchaseDate: DateTime.utc(2026, 10, 3),
      lineMetadata: {
        'LINE': {
          'quantity': 2500,
          'rate': 6500,
          'gstRateBps': 500,
          'mrp': 80000,
          'sellingPrice': 70000,
          'supplierLotNo': 'SUP-LOT-8',
          'manufacturingDate': DateTime.utc(2026, 9, 1),
          'expiryDate': DateTime.utc(2028, 4, 30),
        },
      },
      token: token('U'),
    );
    expect(advanced.changedFields, contains('items.LINE.quantity'));
    expect(advanced.changedFields, contains('items.LINE.rate'));
    expect(advanced.changedFields, contains('items.LINE.gstRateBps'));
    expect(advanced.afterSnapshot['paidAmount'], 5000);
    expect(advanced.afterSnapshot['outstandingAmount'], 12063);
    final advancedBatch = FirestoreRestService.decodeFields(
      jsonDecode(
        (await localSource.row('inventory_batches', batchId))!['payloadJson']
            as String,
      ),
    );
    expect(advancedBatch['receivedQty'], 2500);
    expect(advancedBatch['availableQty'], 2500);
    expect(advancedBatch['purchaseRate'], 6500);
    expect(advancedBatch['mrp'], 80000);
    expect(advancedBatch['sellingPrice'], 70000);
    final advancedMovements = await source.query('inventory_batch_movements', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
      const FirestoreFilter('outletId', 'EQUAL', 'O'),
      FirestoreFilter('batchId', 'EQUAL', batchId),
    ]);
    expect(advancedMovements, hasLength(2));
    final correctionMovement = advancedMovements
        .map((row) => FirestoreRestService.decodeFields(row['fields']))
        .singleWhere((row) => row['movementType'] == 'PURCHASE_CORRECTION_IN');
    expect(correctionMovement['quantity'], 500);
    expect(correctionMovement['direction'], 'IN');
    final advancedStock = FirestoreRestService.decodeFields(
      jsonDecode(
        (await localSource.row('stock_balances', 'T_O_V'))!['payloadJson']
            as String,
      ),
    );
    expect(advancedStock['quantityOnHand'], 2500);
    expect(advanced.afterSnapshot['grandTotal'], 17063);
    await purchases.recordPayment(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      supplierId: 'SUP',
      supplierBusinessId: 'SUP_B',
      purchaseBillId: draft.purchaseBillId,
      amount: 12063,
      paymentMode: 'UPI',
      transactionReference: 'second-part',
      userId: 'U',
      token: token('U'),
    );
    final paidDown = await purchases.correctApprovedMetadata(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'O',
      billId: draft.purchaseBillId,
      reason: 'Correct purchase total after supplier overpayment',
      correctedByUid: 'U',
      supplierInvoiceNumber: 'INV-1-EDITED',
      invoiceDate: DateTime.utc(2026, 10, 2),
      purchaseDate: DateTime.utc(2026, 10, 3),
      lineMetadata: {
        'LINE': {
          'quantity': 2500,
          'rate': 1000,
          'gstRateBps': 0,
          'mrp': 80000,
          'sellingPrice': 70000,
        },
      },
      token: token('U'),
    );
    expect(paidDown.afterSnapshot['grandTotal'], 2500);
    expect(paidDown.afterSnapshot['paidAmount'], 2500);
    expect(paidDown.afterSnapshot['outstandingAmount'], 0);
    final paidDownBill = FirestoreRestService.decodeFields(
      jsonDecode(
        (await localSource.row(
              'purchase_bills',
              draft.purchaseBillId,
            ))!['payloadJson']
            as String,
      ),
    );
    expect(paidDownBill['paymentStatus'], 'PAID');
    expect(paidDownBill['paidAmount'], 2500);
    expect(paidDownBill['outstandingAmount'], 0);
    final allocations = await localSource.query('payment_allocations', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
      FirestoreFilter('purchaseBillId', 'EQUAL', draft.purchaseBillId),
    ]);
    expect(allocations, hasLength(2));
    expect(
      allocations.fold<int>(
        0,
        (sum, row) =>
            sum +
            ((FirestoreRestService.decodeFields(
                          row['fields'],
                        )['allocatedAmount']
                        as num?)
                    ?.toInt() ??
                0),
      ),
      2500,
    );
    final paymentHistory = await localSource.query('supplier_payments', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
      FirestoreFilter('purchaseBillId', 'EQUAL', draft.purchaseBillId),
    ]);
    expect(paymentHistory, hasLength(2));
    expect(
      paymentHistory.fold<int>(
        0,
        (sum, row) =>
            sum +
            ((FirestoreRestService.decodeFields(row['fields'])['amount']
                        as num?)
                    ?.toInt() ??
                0),
      ),
      17063,
    );
    final releasedPayments = paymentHistory
        .map((row) => FirestoreRestService.decodeFields(row['fields']))
        .toList();
    expect(
      releasedPayments.fold<int>(
        0,
        (sum, payment) =>
            sum + ((payment['allocatedAmount'] as num?)?.toInt() ?? 0),
      ),
      2500,
    );
    expect(
      releasedPayments.fold<int>(
        0,
        (sum, payment) =>
            sum + ((payment['unallocatedAmount'] as num?)?.toInt() ?? 0),
      ),
      14563,
    );
    final supplierBalance = FirestoreRestService.decodeFields(
      jsonDecode(
        (await localSource.row('supplier_balances', 'SUP_B'))!['payloadJson']
            as String,
      ),
    );
    expect(supplierBalance['totalPayable'], 0);
    expect(supplierBalance['unallocatedAdvance'], 14563);
    final releaseLedger = await localSource.query('supplier_ledger_entries', [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
    ]);
    final releaseEvents = releaseLedger
        .map((row) => FirestoreRestService.decodeFields(row['fields']))
        .where((row) => row['entryType'] == 'PAYMENT_ALLOCATION_RELEASE')
        .toList();
    expect(releaseEvents, hasLength(2));
    expect(
      releaseEvents.fold<int>(
        0,
        (sum, event) => sum + ((event['releasedAmount'] as num?)?.toInt() ?? 0),
      ),
      14563,
    );
    final auditRow = await localSource.row(
      'purchase_corrections',
      paidDown.correctionId,
    );
    final auditFields = FirestoreRestService.decodeFields(
      jsonDecode(auditRow!['payloadJson'] as String),
    );
    expect(
      (auditFields['paymentRelease'] as Map)['releasedAllocationAmount'],
      14563,
    );
    expect(
      ((auditFields['paymentRelease'] as Map)['allocations'] as List),
      hasLength(2),
    );
    await expectLater(
      purchases.correctApprovedMetadata(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'O',
        billId: draft.purchaseBillId,
        reason: 'Retry same correction',
        correctedByUid: 'U',
        supplierInvoiceNumber: 'INV-1-EDITED',
        invoiceDate: DateTime.utc(2026, 10, 2),
        purchaseDate: DateTime.utc(2026, 10, 3),
        lineMetadata: {
          'LINE': {
            'quantity': 2500,
            'rate': 1000,
            'gstRateBps': 0,
            'mrp': 80000,
            'sellingPrice': 70000,
          },
        },
        token: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
    expect(
      (await localSource.query('supplier_ledger_entries', [
            const FirestoreFilter('tenantId', 'EQUAL', 'T'),
            const FirestoreFilter('businessId', 'EQUAL', 'B'),
          ]))
          .map((row) => FirestoreRestService.decodeFields(row['fields']))
          .where((row) => row['entryType'] == 'PAYMENT_ALLOCATION_RELEASE')
          .length,
      2,
    );
    await sync.sync();
    expect(sync.error, isNull);
    expect(await SyncOutboxRepository(source).pendingCount(), 0);
    final remoteBill = FirestoreRestService.decodeFields(
      remote.docs['purchase_bills/${draft.purchaseBillId}']!['fields'],
    );
    expect(remoteBill['paidAmount'], 2500);
    expect(remoteBill['outstandingAmount'], 0);
    expect(remoteBill['paymentStatus'], 'PAID');
    final remoteBalance = FirestoreRestService.decodeFields(
      remote.docs['supplier_balances/SUP_B']!['fields'],
    );
    expect(remoteBalance['totalPayable'], 0);
    expect(remoteBalance['unallocatedAdvance'], 14563);
    for (final row in paymentHistory) {
      final fields = FirestoreRestService.decodeFields(row['fields']);
      final paymentId = fields['paymentId'] as String;
      final remotePayment = FirestoreRestService.decodeFields(
        remote.docs['supplier_payments/$paymentId']!['fields'],
      );
      expect(remotePayment['amount'], fields['amount']);
    }
    for (final row in allocations) {
      final fields = FirestoreRestService.decodeFields(row['fields']);
      final allocationId = fields['allocationId'] as String;
      final remoteAllocation = FirestoreRestService.decodeFields(
        remote.docs['payment_allocations/$allocationId']!['fields'],
      );
      expect(remoteAllocation['allocatedAmount'], fields['allocatedAmount']);
    }
    final remoteReleaseEvents = remote.docs.entries
        .where((entry) => entry.key.startsWith('supplier_ledger_entries/'))
        .map(
          (entry) => FirestoreRestService.decodeFields(entry.value['fields']),
        )
        .where((fields) => fields['entryType'] == 'PAYMENT_ALLOCATION_RELEASE')
        .toList();
    expect(remoteReleaseEvents, hasLength(2));
  });
  test(
    'schema v11 to v12 upgrade preserves data and adds refund tables',
    () async {
      final dbPath = '${dir.path}/upgrade.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 11,
          onCreate: (db, version) => LocalDatabase.migrate(db, 0, version),
        ),
      );
      await legacy.insert('local_brands', {
        'remoteId': 'B',
        'payloadJson': jsonEncode(
          FirestoreRestService.encodeFields({'name': 'Keep'}),
        ),
        'syncStatus': 'PENDING_CREATE',
        'localUpdatedAt': LocalDataSource.now(),
      });
      await legacy.insert('sync_outbox', {
        'batchId': 'LEGACY',
        'entityType': 'brands',
        'documentId': 'B',
        'operation': 'CREATE',
        'payloadJson': '{}',
        'readSetJson': '{}',
        'localRevision': 1,
        'createdAt': LocalDataSource.now(),
      });
      await legacy.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: LocalDatabase.schemaVersion,
          onUpgrade: LocalDatabase.migrate,
        ),
      );
      expect((await upgraded.query('local_brands')).single['remoteId'], 'B');
      expect((await upgraded.query('sync_outbox')).single['batchId'], 'LEGACY');
      expect(await upgraded.getVersion(), LocalDatabase.schemaVersion);
      expect(await upgraded.query('local_inventory_batch_movements'), isEmpty);
      expect(await upgraded.query('local_supplier_refunds'), isEmpty);
      expect(await upgraded.query('local_financial_transactions'), isEmpty);
      expect(await upgraded.query('local_central_product_master'), isEmpty);
      final columns = await upgraded.rawQuery(
        'PRAGMA table_info(sync_queries)',
      );
      expect(
        columns.map((c) => c['name']),
        containsAll(['lastAttemptAt', 'lastError']),
      );
      await upgraded.close();
    },
  );
}
