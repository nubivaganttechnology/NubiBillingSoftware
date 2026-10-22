import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'support/phase10e_release.dart' show release4Documents;

String token(String uid) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': EnvironmentConfig.projectId, 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.signature';

class TestConnectivity implements ConnectivityService {
  bool available = false;
  @override
  Stream<bool> get onConnectivityChanged => Stream.value(available);
  @override
  Future<bool> checkInternet() async => available;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

class MockFirestoreRemote extends FirestoreRestService {
  MockFirestoreRemote() : super(ApiClient());
  final docs = <String, Map<String, dynamic>>{};
  int clock = 0;
  final List<List<FirestoreWrite>> committedBatches = [];

  void seed(String collection, String id, Map<String, dynamic> fields, {String? updateTime}) {
    docs['$collection/$id'] = {
      'name': '$collection/$id',
      'fields': FirestoreRestService.encodeFields({
        ...fields,
      }),
      'updateTime': updateTime ?? 'VERSION-${++clock}',
    };
  }

  @override
  Future<Map<String, dynamic>> getDocument(
    String c,
    String id, {
    String? idToken,
  }) async {
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
    final all = await queryDocuments(
      collection: collection,
      filters: filters,
      idToken: idToken,
    );
    return FirestoreSyncPage(
      all,
      readTime ?? DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<void> commitAtomicWrites(
    List<FirestoreWrite> writes, {
    String? idToken,
  }) async {
    committedBatches.add(writes);
    for (final w in writes) {
      final key = '${w.collection}/${w.id}';
      final existing = docs[key];
      final fields = existing == null
          ? <String, dynamic>{}
          : FirestoreRestService.decodeFields(existing['fields']);
      docs[key] = {
        'name': key,
        'fields': FirestoreRestService.encodeFields({
          ...fields,
          ...?w.fields,
          'updatedAt': DateTime.now().toUtc(),
        }),
        'updateTime': 'VERSION-${++clock}',
      };
    }
  }
}

class TestFixture {
  final Directory tempDir;
  final LocalDatabase localDatabase;
  final MockFirestoreRemote remote;
  final TestConnectivity connectivity;
  final SyncEngine sync;
  final OfflineFirestoreService offlineFirestore;
  final ProductRepository productRepo;
  final String testUid = 'C6btLkx5SyZvUQOzOeUUd7XxsFh2';
  final String businessId = 'BUS-001';
  late final String testToken;
  late final LocalDataSource localSource;

  TestFixture._({
    required this.tempDir,
    required this.localDatabase,
    required this.remote,
    required this.connectivity,
    required this.sync,
    required this.offlineFirestore,
    required this.productRepo,
  });

  static Future<TestFixture> create() async {
    const accountDbPath = '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db';
    const testUid = 'C6btLkx5SyZvUQOzOeUUd7XxsFh2';
    final tempDir = Directory.systemTemp.createTempSync('audit_suite_');
    final projectKey = Uri.encodeComponent('${EnvironmentConfig.projectId}-$testUid');
    File(accountDbPath).copySync('${tempDir.path}/nubibill-$projectKey.db');
    File(accountDbPath).copySync('${tempDir.path}/nubibill-test1-bcebe-$testUid.db');

    final localDatabase = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: tempDir.path,
    );

    final remote = MockFirestoreRemote();
    final connectivity = TestConnectivity()..available = false;
    final testToken = token(testUid);
    final session = AuthSession(
      uid: testUid,
      email: 'test@nubibill.com',
      idToken: testToken,
      refreshToken: 'mock-refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    final sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session,
    );

    final offlineFirestore = OfflineFirestoreService(localDatabase, remote, sync);
    await offlineFirestore.activate(testUid);
    final localSource = await offlineFirestore.localDataSourceForToken(testToken);
    await SystemCatalogueSnapshot.import(
      source: localSource,
      documents: release4Documents(),
      readTimes: const {},
      allowUnapprovedIsolatedForTests: true,
    );
    final productRepo = ProductRepository(
      offlineFirestore,
      offlineFirestore,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );

    // Clean prior outbox/conflicts
    await localSource.db.delete('sync_outbox');
    await localSource.db.delete('sync_conflicts');

    // Seed existing documents
    final existingProdRow = await localSource.row('products', 'PROD-11696CF40807442CA761EE4264B8E24A');
    final existingProdFields = FirestoreRestService.decodeFields(jsonDecode(existingProdRow!['payloadJson'] as String));
    // The source machine's historical id is not a member of the test release.
    // Use the release's canonical Interior Dampness identity in this temporary
    // clone so these persistence tests exercise edits against a supported
    // template without assigning metadata to the historical record.
    existingProdFields['subcategoryId'] =
        'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS';
    remote.seed(
      'products',
      'PROD-11696CF40807442CA761EE4264B8E24A',
      existingProdFields,
      updateTime: existingProdRow['remoteUpdateTime'] as String?,
    );
    await localSource.upsertRemote('products', [
      remote.docs['products/PROD-11696CF40807442CA761EE4264B8E24A']!,
    ]);
    remote.seed('brands', 'SYS_BRAND_ASIAN_PAINTS', {
      'brandId': 'SYS_BRAND_ASIAN_PAINTS',
      'name': 'Asian Paints',
      'scopeType': 'BUSINESS',
      'tenantId': testUid,
      'businessId': 'BUS-001',
      'status': 'ACTIVE',
    });
    await localSource.upsertRemote('brands', [
      remote.docs['brands/SYS_BRAND_ASIAN_PAINTS']!,
    ]);

    final varRows = await localSource.db.query(
      'local_product_variants',
      where: 'payloadJson LIKE ?',
      whereArgs: ['%PROD-11696CF40807442CA761EE4264B8E24A%'],
    );
    for (final vr in varRows) {
      final vFields = FirestoreRestService.decodeFields(jsonDecode(vr['payloadJson'] as String));
      remote.seed(
        'product_variants',
        vr['remoteId'] as String,
        vFields,
        updateTime: vr['remoteUpdateTime'] as String?,
      );
    }

    final pukRows = await localSource.db.query('local_product_unique_keys');
    for (final puk in pukRows) {
      final pFields = FirestoreRestService.decodeFields(jsonDecode(puk['payloadJson'] as String));
      remote.seed(
        'product_unique_keys',
        puk['remoteId'] as String,
        pFields,
        updateTime: puk['remoteUpdateTime'] as String?,
      );
    }

    await localSource.db.update(
      'sync_queries',
      {'active': 0},
      where: "collectionName NOT IN ('products', 'product_variants', 'product_unique_keys')",
    );

    final fixture = TestFixture._(
      tempDir: tempDir,
      localDatabase: localDatabase,
      remote: remote,
      connectivity: connectivity,
      sync: sync,
      offlineFirestore: offlineFirestore,
      productRepo: productRepo,
    );
    fixture.testToken = testToken;
    fixture.localSource = localSource;
    return fixture;
  }

  Future<void> dispose() async {
    sync.dispose();
    await localDatabase.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }

  Map<String, dynamic> buildProductFields(ProductModel p, {Map<String, dynamic>? extraAttributes, String? description, String? imageUrl}) {
    return <String, dynamic>{
      'brandId': p.brandId,
      'brand': p.brand,
      'categoryId': p.categoryId,
      'categoryName': p.category,
      'subcategoryId': p.subcategoryId,
      'subcategory': p.subcategory,
      'masterProductId': p.masterProductId,
      'attributeValues': {
        ...p.attributeValues,
        ...?extraAttributes,
      },
      'hsnCode': p.hsnCode ?? '',
      'defaultGstRateBps': p.defaultGstRateBps,
      'status': p.status,
      'description': description ?? p.description ?? '',
      'productImage': imageUrl ?? p.productImage ?? '',
      'imageUrl': imageUrl ?? p.productImage ?? '',
    };
  }

  Map<String, dynamic> buildVariantMap(ProductModel p, {dynamic packSize, Map<String, dynamic>? extraAttributes}) {
    final v = p.variants.first;
    return <String, dynamic>{
      'variantId': v.variantId,
      'barcode': v.barcode,
      'status': v.status,
      'attributeValues': {
        ...v.attributeValues,
        if (packSize != null) 'packSize': packSize,
        ...?extraAttributes,
      },
      'displayName': '${packSize ?? v.packSize} - Litre',
      'packSize': packSize ?? v.packSize,
      'packUnitId': v.packUnitId,
      'unitId': v.baseUnitId,
      'baseUnitId': v.baseUnitId,
      'commercialUnitId': v.commercialUnitId,
      'commercialUnitName': v.commercialUnitName,
      'baseQuantityPerCommercialUnit': v.baseQuantityPerCommercialUnit,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Product Edit Persistence Audit (16 Required Test Cases)', () {
    test('1. existing variant packSize update survives save', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      final vRow = await fixture.localSource.row('product_variants', product.variants.first.variantId);
      final vPayload = FirestoreRestService.decodeFields(jsonDecode(vRow!['payloadJson'] as String));
      expect(vPayload['packSize'], equals(12));
      await fixture.dispose();
    });

    test('2. technical attribute update survives save', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {'warranty': '2 Years'}),
        variants: [fixture.buildVariantMap(product)],
      );

      final pRow = await fixture.localSource.row('products', product.productId);
      final pPayload = FirestoreRestService.decodeFields(jsonDecode(pRow!['payloadJson'] as String));
      expect(pPayload['attributeValues']['warranty'], equals('2 Years'));
      await fixture.dispose();
    });

    test('3. multiple technical attributes survive together', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
          'coverage': '100 sq ft',
        }),
        variants: [fixture.buildVariantMap(product)],
      );

      final pRow = await fixture.localSource.row('products', product.productId);
      final pPayload = FirestoreRestService.decodeFields(jsonDecode(pRow!['payloadJson'] as String));
      expect(pPayload['attributeValues']['warranty'], equals('2 Years'));
      expect(pPayload['attributeValues']['mixingRatio'], equals('2:1'));
      expect(pPayload['attributeValues']['coverage'], equals('100 sq ft'));
      await fixture.dispose();
    });

    test('4. product + variant edits survive one atomic save', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      final reloaded = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);
      expect(reloaded.attributeValues['warranty'], equals('2 Years'));
      expect(reloaded.attributeValues['mixingRatio'], equals('2:1'));
      expect(reloaded.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });

    test('5. SQLite contains edited values before sync', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      // Verify syncStatus is PENDING_UPDATE and values are present
      final pRow = await fixture.localSource.row('products', product.productId);
      expect(pRow!['syncStatus'], equals('PENDING_UPDATE'));
      final pPayload = FirestoreRestService.decodeFields(jsonDecode(pRow['payloadJson'] as String));
      expect(pPayload['attributeValues']['warranty'], equals('2 Years'));
      expect(pPayload['attributeValues']['mixingRatio'], equals('2:1'));

      final vRow = await fixture.localSource.row('product_variants', product.variants.first.variantId);
      expect(vRow!['syncStatus'], equals('PENDING_UPDATE'));
      final vPayload = FirestoreRestService.decodeFields(jsonDecode(vRow['payloadJson'] as String));
      expect(vPayload['packSize'], equals(12));
      await fixture.dispose();
    });

    test('6. outbox contains edited values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      final outbox = await fixture.localSource.db.query('sync_outbox');
      expect(outbox.length, equals(2));

      final pOutbox = outbox.firstWhere((r) => r['entityType'] == 'products');
      final pFields = FirestoreRestService.decodeFields((jsonDecode(pOutbox['payloadJson'] as String) as Map)['fields']);
      expect(pFields['attributeValues']['warranty'], equals('2 Years'));
      expect(pFields['attributeValues']['mixingRatio'], equals('2:1'));

      final vOutbox = outbox.firstWhere((r) => r['entityType'] == 'product_variants');
      final vFields = FirestoreRestService.decodeFields((jsonDecode(vOutbox['payloadJson'] as String) as Map)['fields']);
      expect(vFields['packSize'], equals(12));
      await fixture.dispose();
    });

    test('7. Firestore receives edited values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      final remoteProd = fixture.remote.docs['products/${product.productId}'];
      final remoteProdFields = FirestoreRestService.decodeFields(remoteProd!['fields']);
      expect(remoteProdFields['attributeValues']['warranty'], equals('2 Years'));
      expect(remoteProdFields['attributeValues']['mixingRatio'], equals('2:1'));

      final remoteVar = fixture.remote.docs['product_variants/${product.variants.first.variantId}'];
      final remoteVarFields = FirestoreRestService.decodeFields(remoteVar!['fields']);
      expect(remoteVarFields['packSize'], equals(12));
      await fixture.dispose();
    });

    test('8. successful remote pull preserves edited values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      // Trigger another pull explicitly
      await fixture.sync.sync();

      final pRow = await fixture.localSource.row('products', product.productId);
      expect(pRow!['syncStatus'], equals('SYNCED'));
      final pPayload = FirestoreRestService.decodeFields(jsonDecode(pRow['payloadJson'] as String));
      expect(pPayload['attributeValues']['warranty'], equals('2 Years'));
      expect(pPayload['attributeValues']['mixingRatio'], equals('2:1'));

      final vRow = await fixture.localSource.row('product_variants', product.variants.first.variantId);
      expect(vRow!['syncStatus'], equals('SYNCED'));
      final vPayload = FirestoreRestService.decodeFields(jsonDecode(vRow['payloadJson'] as String));
      expect(vPayload['packSize'], equals(12));
      await fixture.dispose();
    });

    test('9. pending local edit cannot be overwritten by stale remote pull', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      // Simulate a pull happening with stale remote document while local is PENDING_UPDATE
      final staleDoc = {
        'name': 'products/${product.productId}',
        'fields': FirestoreRestService.encodeFields({
          ...product.toData(),
          'attributeValues': {'usage': 'Interior & Exterior'},
        }),
        'updateTime': 'STALE_VERSION',
      };
      await fixture.localSource.upsertRemote('products', [staleDoc]);

      // Local product must NOT be overwritten!
      final pRow = await fixture.localSource.row('products', product.productId);
      expect(pRow!['syncStatus'], equals('PENDING_UPDATE'));
      final pPayload = FirestoreRestService.decodeFields(jsonDecode(pRow['payloadJson'] as String));
      expect(pPayload['attributeValues']['warranty'], equals('2 Years'));
      expect(pPayload['attributeValues']['mixingRatio'], equals('2:1'));
      await fixture.dispose();
    });

    test('10. edit form reopens with persisted values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      // "Reopen": re-read from repo as UI initState does
      final reopened = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(reopened.attributeValues['warranty'], equals('2 Years'));
      expect(reopened.attributeValues['mixingRatio'], equals('2:1'));
      expect(reopened.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });

    test('11. app restart preserves values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      final tempDirPath = fixture.tempDir.path;
      final savedUid = fixture.testUid;
      final savedToken = fixture.testToken;
      final savedBusinessId = fixture.businessId;
      await fixture.localDatabase.close();

      // "Restart": re-initialize completely fresh database instance against disk
      final restartedDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempDirPath);
      final restartedSync = SyncEngine(fixture.remote, fixture.connectivity, sessionProvider: () async => null);
      final restartedOffline = OfflineFirestoreService(restartedDb, fixture.remote, restartedSync);
      await restartedOffline.activate(savedUid);
      final restartedRepo = ProductRepository(restartedOffline, restartedOffline);

      final restartedProducts = await restartedRepo.getProducts(tenantId: savedUid, businessId: savedBusinessId, token: savedToken);
      final restartedProd = restartedProducts.firstWhere((p) => p.productCode == 'PRD-0009');

      expect(restartedProd.attributeValues['warranty'], equals('2 Years'));
      expect(restartedProd.attributeValues['mixingRatio'], equals('2:1'));
      expect(restartedProd.variants.first.packSize, equals('12'));

      restartedSync.dispose();
      await restartedDb.close();
      try {
        Directory(tempDirPath).deleteSync(recursive: true);
      } catch (_) {}
    });

    test('12. editing image + technical + variant simultaneously works', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');
      const testImage = 'https://static.asianpaints.com/test-image.png';

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, imageUrl: testImage, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
          'coverage': '100 sq ft',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      final reloaded = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(reloaded.productImage, equals(testImage));
      expect(reloaded.attributeValues['warranty'], equals('2 Years'));
      expect(reloaded.attributeValues['mixingRatio'], equals('2:1'));
      expect(reloaded.attributeValues['coverage'], equals('100 sq ft'));
      expect(reloaded.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });

    test('13. unrelated edit does not reset technical values', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      // Edit 1: set technical attributes
      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
          'mixingRatio': '2:1',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      // Edit 2: unrelated edit - only update description
      final pAfter1 = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: pAfter1.productId,
        productName: pAfter1.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(pAfter1, description: 'Updated description only'),
        variants: [fixture.buildVariantMap(pAfter1)],
      );

      await fixture.sync.sync();

      final pAfter2 = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(pAfter2.description, equals('Updated description only'));
      expect(pAfter2.attributeValues['warranty'], equals('2 Years'));
      expect(pAfter2.attributeValues['mixingRatio'], equals('2:1'));
      expect(pAfter2.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });

    test('14. unrelated edit does not reset variant fields', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      // Edit 1: set packSize = 12
      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      // Edit 2: only edit product name
      final pAfter1 = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: pAfter1.productId,
        productName: 'ASIAN PAINTS DAMP PROOF ULTRA COOL PU RENAMED',
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(pAfter1),
        variants: [fixture.buildVariantMap(pAfter1)],
      );

      await fixture.sync.sync();

      final pAfter2 = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(pAfter2.name, equals('ASIAN PAINTS DAMP PROOF ULTRA COOL PU RENAMED'));
      expect(pAfter2.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });

    test('15. empty untouched field is preserved correctly', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      // voc was empty originally, warranty is edited
      expect(product.attributeValues['voc'], isNull);

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      final reloaded = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(reloaded.attributeValues['warranty'], equals('2 Years'));
      expect(reloaded.attributeValues['voc'], isNull);
      await fixture.dispose();
    });

    test('16. explicit field clear works only when user explicitly clears it', () async {
      final fixture = await TestFixture.create();
      final products = await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken);
      final product = products.firstWhere((p) => p.productCode == 'PRD-0009');

      // Set warranty to 2 Years
      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: product.productId,
        productName: product.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: fixture.buildProductFields(product, extraAttributes: {
          'warranty': '2 Years',
        }),
        variants: [fixture.buildVariantMap(product, packSize: 12)],
      );

      fixture.connectivity.available = true;
      await fixture.sync.sync();

      final pAfterSet = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);
      expect(pAfterSet.attributeValues['warranty'], equals('2 Years'));

      // Explicitly clear warranty (pass empty string or remove from attributeValues)
      final clearedFields = fixture.buildProductFields(pAfterSet);
      (clearedFields['attributeValues'] as Map).remove('warranty');

      await fixture.productRepo.updateStructuredProduct(
        tenantId: fixture.testUid,
        businessId: fixture.businessId,
        productId: pAfterSet.productId,
        productName: pAfterSet.name,
        actorUid: fixture.testUid,
        token: fixture.testToken,
        productFields: clearedFields,
        variants: [fixture.buildVariantMap(pAfterSet)],
      );

      await fixture.sync.sync();

      final pAfterClear = (await fixture.productRepo.getProducts(tenantId: fixture.testUid, businessId: fixture.businessId, token: fixture.testToken))
          .firstWhere((p) => p.productId == product.productId);

      expect(pAfterClear.attributeValues['warranty'], isNull);
      expect(pAfterClear.variants.first.packSize, equals('12'));
      await fixture.dispose();
    });
  });
}
