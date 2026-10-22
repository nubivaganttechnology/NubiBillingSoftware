import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/products/product_thumbnail.dart';

import 'support/phase10e_release.dart' show release4Documents;

class DebugRemoteService extends FirestoreRestService {
  DebugRemoteService() : super(ApiClient());
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

class TestConnectivityService extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String testToken(String uid) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': uid, 'aud': '', 'exp': DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000})))}.signature';

void main() {
  sqfliteFfiInit();
  const testImageUrl =
      'https://static.asianpaints.com/content/dam/asian_paints/products/packshots/DP-Advanced-Packshot.png';

  late Directory tempDir;
  late LocalDatabase database;
  late DebugRemoteService remote;
  late TestConnectivityService connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  late LocalDataSource local;
  late ProductRepository repo;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: tempDir.path,
    );
    remote = DebugRemoteService();
    connectivity = TestConnectivityService()..available = true;
    final session = AuthSession(
      uid: 'USER-TEST',
      email: 'test@example.com',
      idToken: testToken('USER-TEST'),
      refreshToken: 'REFRESH',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () => Future.value(session),
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('USER-TEST');
    local = await service.localDataSourceForToken(testToken('USER-TEST'));
    final catalogue = release4Documents();
    await SystemCatalogueSnapshot.import(
      source: local,
      documents: catalogue,
      readTimes: const {},
      allowUnapprovedIsolatedForTests: true,
    );
    for (final collection in catalogue.keys) {
      for (final doc in await local.query(collection, const [])) {
        final id = (doc['name'] as String).split('/').last;
        remote.seed(
          collection,
          id,
          FirestoreValueCodec.decodeFields(doc['fields']),
        );
      }
    }
    repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );

    Future<void> seedLocal(
      String c,
      String id,
      Map<String, dynamic> fields,
    ) async {
      remote.seed(c, id, fields);
      await local.upsertRemote(c, [remote.docs['$c/$id']!]);
    }

    // Seed master taxonomy
    for (final entry in {
      'brands': 'BR-1',
      'product_categories': 'CA-1',
      'product_subcategories': 'SC-1',
      'units': 'UN-1',
    }.entries) {
      await seedLocal(entry.key, entry.value, {
        'scopeType': 'BUSINESS',
        'tenantId': 'USER-TEST',
        'businessId': 'BUS-1',
        'status': 'ACTIVE',
        'name': entry.value,
        if (entry.key == 'product_categories') 'categoryId': entry.value,
        if (entry.key == 'product_subcategories') 'categoryId': 'CA-1',
        if (entry.key == 'product_subcategories') 'subcategoryId': entry.value,
        if (entry.key == 'product_subcategories') 'templateSelectable': true,
        if (entry.key == 'product_subcategories') 'templateStatus': 'READY',
        if (entry.key == 'units') 'measurementDimension': 'MASS',
        if (entry.key == 'product_subcategories')
          'unitRules': {
            'allowedPackUnits': ['UN-1'],
            'defaultPackUnit': 'UN-1',
            'allowedSellingUnits': ['UN-1'],
            'defaultSellingUnit': 'UN-1',
            'allowedBaseUnits': ['UN-1'],
            'defaultBaseUnit': 'UN-1',
            'conversionAllowed': true,
            'conversionDimension': 'MASS',
          },
      });
    }

    await seedLocal('product_attributes', 'imageFinish', {
      'scopeType': 'BUSINESS',
      'tenantId': 'USER-TEST',
      'businessId': 'BUS-1',
      'status': 'ACTIVE',
      'attributeId': 'imageFinish',
      'name': 'Finish',
      'dataType': 'SELECT',
      'options': ['Silk'],
    });
    await seedLocal('subcategory_attribute_templates', 'SC-1_imageFinish', {
      'scopeType': 'BUSINESS',
      'tenantId': 'USER-TEST',
      'businessId': 'BUS-1',
      'status': 'ACTIVE',
      'subcategoryId': 'SC-1',
      'attributeId': 'imageFinish',
      'attributeLevel': 'VARIANT',
    });

    // Sequence documents are BUSINESS scoped, independent of the catalogue.
    await seedLocal('document_sequences', 'USER-TEST_BUS-1_PRODUCT', {
      'currentValue': 100,
    });
    await seedLocal('document_sequences', 'USER-TEST_BUS-1_PRODUCT_VARIANT', {
      'currentValue': 100,
    });

    await seedLocal('businesses', 'BUS-1', {
      'tenantId': 'USER-TEST',
      'name': 'Test Business',
    });
    await local.db.update('local_businesses', {'syncStatus': 'PENDING_CREATE'});
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  test('1. Pasted URL survives product CREATE, stored in local_products and outbox', () async {
    await repo.createStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productName: 'New Emulsion Paint',
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'productImage': testImageUrl,
        'imageUrl': testImageUrl,
        'attributeValues': {},
      },
      variants: [
        {
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
    );

    final products = await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    );
    final created = products.firstWhere((p) => p.name == 'New Emulsion Paint');
    expect(created.productImage, equals(testImageUrl));

    // Check local SQLite row
    final row = await local.row('products', created.productId);
    expect(row, isNotNull);
    final payload = FirestoreRestService.decodeFields(
      jsonDecode(row!['payloadJson'] as String),
    );
    expect(payload['productImage'], equals(testImageUrl));
    expect(payload['imageUrl'], equals(testImageUrl));

    // Check outbox mutation
    final outboxRows = await local.db.query(
      'sync_outbox',
      where: 'entityType=? AND documentId=?',
      whereArgs: ['products', created.productId],
    );
    expect(outboxRows, isNotEmpty);
    final write = jsonDecode(outboxRows.first['payloadJson'] as String) as Map;
    final writeFields = FirestoreRestService.decodeFields(write['fields']);
    expect(writeFields['productImage'], equals(testImageUrl));

    // Push to remote
    await sync.sync();

    // Verify remote Firestore document
    final remoteDoc = remote.docs['products/${created.productId}'];
    expect(remoteDoc, isNotNull);
    final remoteFields = FirestoreRestService.decodeFields(remoteDoc!['fields']);
    expect(remoteFields['productImage'], equals(testImageUrl));
    expect(remoteFields['imageUrl'], equals(testImageUrl));
  });

  test('2 & 3 & 4. Pasted URL survives product UPDATE, stored in SQLite & outbox', () async {
    // Seed existing product with empty image
    const prodId = 'PROD-UPDATE-TEST';
    remote.seed('products', prodId, {
      'tenantId': 'USER-TEST',
      'businessId': 'BUS-1',
      'productCode': 'PRD-0009',
      'productName': 'ASIAN PAINTS DAMP PROOF ULTRA COOL PU',
      'status': 'ACTIVE',
      'brandId': 'BR-1',
      'categoryId': 'CA-1',
      'subcategoryId': 'SC-1',
      'productImage': '',
      'imageUrl': '',
      'version': 1,
    });
    remote.seed('product_variants', 'VAR-0009', {
      'tenantId': 'USER-TEST',
      'businessId': 'BUS-1',
      'productId': prodId,
      'sku': 'SKU-0009',
      'status': 'ACTIVE',
      'baseUnitId': 'UN-1',
      'commercialUnitId': 'UN-1',
      'baseQuantityPerCommercialUnit': 1,
    });
    await local.upsertRemote('products', [remote.docs['products/$prodId']!]);
    await local.upsertRemote('product_variants', [remote.docs['product_variants/VAR-0009']!]);

    // Update with new image URL
    await repo.updateStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productId: prodId,
      productName: 'ASIAN PAINTS DAMP PROOF ULTRA COOL PU',
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'productImage': testImageUrl,
        'imageUrl': testImageUrl,
        'attributeValues': {},
        'status': 'ACTIVE',
      },
      variants: [
        {
          'variantId': 'VAR-0009',
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
    );

    // 3. Stored in local_products payloadJson before push
    final localRow = await local.row('products', prodId);
    expect(localRow, isNotNull);
    final localPayload = FirestoreRestService.decodeFields(
      jsonDecode(localRow!['payloadJson'] as String),
    );
    expect(localPayload['productImage'], equals(testImageUrl));
    expect(localPayload['imageUrl'], equals(testImageUrl));

    // 4. Present in sync_outbox mutation
    final outbox = await local.db.query(
      'sync_outbox',
      where: 'entityType=? AND documentId=?',
      whereArgs: ['products', prodId],
    );
    expect(outbox, isNotEmpty);
    final write = jsonDecode(outbox.first['payloadJson'] as String) as Map;
    final writeFields = FirestoreRestService.decodeFields(write['fields']);
    expect(writeFields['productImage'], equals(testImageUrl));
    expect(writeFields['imageUrl'], equals(testImageUrl));

    // Push to Firestore
    await sync.sync();

    // Verify remote Firestore document
    final remoteDoc = remote.docs['products/$prodId'];
    expect(remoteDoc, isNotNull);
    final remoteFields = FirestoreRestService.decodeFields(remoteDoc!['fields']);
    expect(remoteFields['productImage'], equals(testImageUrl));
    expect(remoteFields['imageUrl'], equals(testImageUrl));

    // Verify product list returns URL
    final products = await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    );
    expect(products.firstWhere((p) => p.productId == prodId).productImage, equals(testImageUrl));
  });

  test('5. Remote pull preserves URL (does not fabricate empty string when omitted)', () async {
    const prodId = 'PROD-PULL-TEST';
    // Local product with valid image
    remote.seed('products', prodId, {
      'tenantId': 'USER-TEST',
      'businessId': 'BUS-1',
      'productName': 'Test Existing Image',
      'status': 'ACTIVE',
      'brandId': 'BR-1',
      'categoryId': 'CA-1',
      'subcategoryId': 'SC-1',
      'productImage': testImageUrl,
      'imageUrl': testImageUrl,
      'version': 1,
    });
    await local.upsertRemote('products', [remote.docs['products/$prodId']!]);

    // Simulate remote document that omitted productImage during a partial update
    final remoteDocOmitted = {
      'name': 'products/$prodId',
      'fields': FirestoreRestService.encodeFields({
        'tenantId': 'USER-TEST',
        'businessId': 'BUS-1',
        'productName': 'Test Existing Image Renamed',
        'status': 'ACTIVE',
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'version': 2,
        'updatedAt': DateTime.now().toUtc(),
      }),
      'updateTime': 'VERSION-99',
    };

    await local.upsertRemote('products', [remoteDocOmitted]);

    final row = await local.row('products', prodId);
    final payload = FirestoreRestService.decodeFields(
      jsonDecode(row!['payloadJson'] as String),
    );
    expect(payload['productImage'], equals(testImageUrl));
  });

  test('6. Editing another field does not clear existing image', () async {
    await repo.createStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productName: 'Original Name',
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'productImage': testImageUrl,
        'imageUrl': testImageUrl,
        'attributeValues': {},
      },
      variants: [
        {
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
    );
    await sync.sync();

    // Now edit only description / name, preserving existing image
    final existingProduct = (await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    )).firstWhere((p) => p.name == 'Original Name');

    expect(existingProduct.productImage, equals(testImageUrl));

    // When form saves without modifying image:
    await repo.updateStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productId: existingProduct.productId,
      productName: 'Renamed Product',
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'description': 'Updated description',
        'productImage': existingProduct.productImage ?? '',
        'imageUrl': existingProduct.productImage ?? '',
        'attributeValues': {},
        'status': 'ACTIVE',
      },
      variants: [
        {
          'variantId': existingProduct.variants.first.variantId,
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
    );

    await sync.sync();

    final reloaded = (await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    )).firstWhere((p) => p.productId == existingProduct.productId);
    expect(reloaded.productImage, equals(testImageUrl));
  });

  test('7. Explicit Remove clears image', () async {
    await repo.createStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productName: 'Product With Image',
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'productImage': testImageUrl,
        'imageUrl': testImageUrl,
        'attributeValues': {},
      },
      variants: [
        {
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
    );
    await sync.sync();

    final existingProduct = (await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    )).firstWhere((p) => p.name == 'Product With Image');

    // User explicitly removes image
    await repo.updateStructuredProduct(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      productId: existingProduct.productId,
      productName: 'Product With Image',
      actorUid: 'USER-TEST',
      token: testToken('USER-TEST'),
      productFields: {
        'brandId': 'BR-1',
        'categoryId': 'CA-1',
        'subcategoryId': 'SC-1',
        'productImage': '',
        'imageUrl': '',
        'attributeValues': {},
        'status': 'ACTIVE',
      },
      variants: [
        {
          'variantId': existingProduct.variants.first.variantId,
          'baseUnitId': 'UN-1',
          'commercialUnitId': 'UN-1',
          'baseQuantityPerCommercialUnit': 1,
        },
      ],
    );
    await sync.sync();

    final reloaded = (await repo.getProducts(
      tenantId: 'USER-TEST',
      businessId: 'BUS-1',
      token: testToken('USER-TEST'),
    )).firstWhere((p) => p.productId == existingProduct.productId);
    expect(reloaded.productImage, isNull);
  });

  testWidgets('8. Missing/invalid URL still shows placeholder without crashing', (tester) async {
    for (final invalid in [null, '', '   ', 'not-a-url', 'ftp://sample.com/img.png']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductThumbnail(
              url: invalid,
              name: 'Sample Product',
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('product-image-placeholder')), findsOneWidget);
    }
  });
}
