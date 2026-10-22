import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'support/product_test_catalogue.dart';

class DebugRemote extends FirestoreRestService {
  DebugRemote() : super(ApiClient());
  final docs = <String, Map<String, dynamic>>{};
  int clock = 0;

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
    final doc = docs['$c/$id'];
    if (doc == null) throw AppException('Missing', code: 'not-found');
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
          ...w.fields!,
          'updatedAt': DateTime.now().toUtc(),
        }),
        'updateTime': 'VERSION-${++clock}',
      };
    }
  }
}

class TestConnectivity extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String token(String uid) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': '', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.signature';

void main() {
  sqfliteFfiInit();
  const testUrl =
      'https://static.asianpaints.com/content/dam/asian_paints/products/packshots/DP-Advanced-Packshot.png';

  test('trace product edit save and sync with image URL', () async {
    final dir = Directory.systemTemp.createTempSync();
    final database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: dir.path,
    );
    final remote = DebugRemote();
    final connectivity = TestConnectivity()..available = true;
    final session = AuthSession(
      uid: 'USER-1',
      email: 'u@example.com',
      idToken: token('USER-1'),
      refreshToken: 'REFRESH',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () => Future.value(session),
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    final service = OfflineFirestoreService(database, remote, sync);
    await service.activate('USER-1');
    final local = await service.localDataSourceForToken(token('USER-1'));

    Future<void> seedLocal(
      String c,
      String id,
      Map<String, dynamic> fields,
    ) async {
      remote.seed(c, id, fields);
      await local.upsertRemote(c, [remote.docs['$c/$id']!]);
    }

    await installProductTestCatalogue(
      source: local,
      seedRemote: remote.seed,
    );

    // These test-specific masters belong to this test business, not SYSTEM.
    for (final entry in {
      'brands': 'BR',
      'product_categories': 'CA',
      'product_subcategories': 'SC',
      'units': 'UN',
    }.entries) {
      await seedLocal(entry.key, entry.value, {
        'scopeType': 'BUSINESS',
        'tenantId': 'USER-1',
        'businessId': 'BUS-001',
        'status': 'ACTIVE',
        'name': entry.value,
        if (entry.key == 'product_subcategories') 'categoryId': 'CA',
        if (entry.key == 'product_subcategories') 'subcategoryId': entry.value,
        if (entry.key == 'units') 'measurementDimension': 'MASS',
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
    await seedLocal('product_attributes', 'businessFinish', {
      'scopeType': 'BUSINESS',
      'tenantId': 'USER-1',
      'businessId': 'BUS-001',
      'status': 'ACTIVE',
      'attributeId': 'businessFinish',
      'name': 'finish',
      'dataType': 'SELECT',
      'options': ['Silk'],
    });
    await seedLocal('subcategory_attribute_templates', 'SC_businessFinish', {
      'scopeType': 'BUSINESS',
      'tenantId': 'USER-1',
      'businessId': 'BUS-001',
      'status': 'ACTIVE',
      'subcategoryId': 'SC',
      'attributeId': 'businessFinish',
      'attributeLevel': 'VARIANT',
    });

    // Seed existing product PRD-0009 in remote & local with empty image
    const prodId = 'PROD-0009';
    await seedLocal('products', prodId, {
      'tenantId': 'USER-1',
      'businessId': 'BUS-001',
      'productCode': 'PRD-0009',
      'productName': 'ASIAN PAINTS DAMP PROOF ULTRA COOL PU',
      'status': 'ACTIVE',
      'brandId': 'BR',
      'categoryId': 'CA',
      'subcategoryId': 'SC',
      'productImage': '',
      'imageUrl': '',
      'version': 1,
    });
    await seedLocal('product_variants', 'VAR-0009', {
      'tenantId': 'USER-1',
      'businessId': 'BUS-001',
      'productId': prodId,
      'sku': 'SKU-0009',
      'status': 'ACTIVE',
      'baseUnitId': 'UN',
      'commercialUnitId': 'UN',
      'baseQuantityPerCommercialUnit': 1,
    });

    final repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );

    // 1. Initial getProducts check
    final initialProducts = await repo.getProducts(
      tenantId: 'USER-1',
      businessId: 'BUS-001',
      token: token('USER-1'),
    );
    print('Initial productImage: "${initialProducts.single.productImage}"');

    // 2. Perform Edit with new image URL
    final editFields = {
      'brandId': 'BR',
      'categoryId': 'CA',
      'subcategoryId': 'SC',
      'productImage': testUrl,
      'imageUrl': testUrl,
      'attributeValues': {},
      'status': 'ACTIVE',
    };

    await repo.updateStructuredProduct(
      tenantId: 'USER-1',
      businessId: 'BUS-001',
      productId: prodId,
      productName: 'ASIAN PAINTS DAMP PROOF ULTRA COOL PU',
      actorUid: 'USER-1',
      token: token('USER-1'),
      productFields: editFields,
      variants: [
        {
          'variantId': 'VAR-0009',
          'baseUnitId': 'UN',
          'commercialUnitId': 'UN',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
    );

    // 3. Check SQLite row before push
    final localRowBeforePush = await local.row('products', prodId);
    final payloadBeforePush = FirestoreRestService.decodeFields(
      jsonDecode(localRowBeforePush!['payloadJson'] as String),
    );
    print('Local SQLite payload before push:');
    print('  productImage: "${payloadBeforePush['productImage']}"');
    print('  imageUrl: "${payloadBeforePush['imageUrl']}"');
    print('  syncStatus: "${localRowBeforePush['syncStatus']}"');

    // 4. Check sync_outbox row
    final outboxRows = await local.db.query('sync_outbox');
    print('Outbox rows: ${outboxRows.length}');
    for (final row in outboxRows) {
      final write = jsonDecode(row['payloadJson'] as String) as Map;
      final writeFields = FirestoreRestService.decodeFields(write['fields']);
      print('  outbox ${row['entityType']} operation=${row['operation']}:');
      if (row['entityType'] == 'products') {
        print('    productImage: "${writeFields['productImage']}"');
        print('    imageUrl: "${writeFields['imageUrl']}"');
      }
    }

    // 5. Check products list while pending
    final pendingProducts = await repo.getProducts(
      tenantId: 'USER-1',
      businessId: 'BUS-001',
      token: token('USER-1'),
    );
    print('Pending products list productImage: "${pendingProducts.single.productImage}"');

    // 6. Push / sync
    await sync.sync();

    // 7. Check remote Firestore doc after sync
    final remoteDocAfterSync = remote.docs['products/$prodId'];
    final remoteFieldsAfterSync = FirestoreRestService.decodeFields(
      remoteDocAfterSync!['fields'],
    );
    print('Remote Firestore doc after sync:');
    print('  productImage: "${remoteFieldsAfterSync['productImage']}"');
    print('  imageUrl: "${remoteFieldsAfterSync['imageUrl']}"');

    // 8. Check SQLite row after sync
    final localRowAfterPush = await local.row('products', prodId);
    final payloadAfterPush = FirestoreRestService.decodeFields(
      jsonDecode(localRowAfterPush!['payloadJson'] as String),
    );
    print('Local SQLite payload after sync:');
    print('  productImage: "${payloadAfterPush['productImage']}"');
    print('  imageUrl: "${payloadAfterPush['imageUrl']}"');
    print('  syncStatus: "${localRowAfterPush['syncStatus']}"');

    // 9. Check products list after sync
    final syncedProducts = await repo.getProducts(
      tenantId: 'USER-1',
      businessId: 'BUS-001',
      token: token('USER-1'),
    );
    print('Synced products list productImage: "${syncedProducts.single.productImage}"');

    sync.dispose();
    await database.close();
    dir.deleteSync(recursive: true);
  });
}
