import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/outlet_product_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/data/sync/sync_query_registry.dart';

import 'offline_sync_test.dart' show FakeRemote, TestConnectivity, session, token;

void main() {
  sqfliteFfiInit();

  final winPath = r'C:\Users\SKSUM\Downloads\FirestoreBackup\firestore_complete_merged.json';
  const macPath = '/Users/sksuman/Desktop/Firebase Billing/Firestore Data Fetch/firestore_full_backup/firestore_complete_merged.json';
  final backupFilePath = Platform.environment['FIRESTORE_BACKUP_PATH'] ?? (File(winPath).existsSync() ? winPath : macPath);

  Map<String, List<Map<String, dynamic>>> loadProductionCatalogue() {
    final backupFile = File(backupFilePath);
    final bytes = backupFile.readAsBytesSync();
    final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final collections = jsonMap['collections'] as Map<String, dynamic>;

    final inputDocs = <String, List<Map<String, dynamic>>>{};
    for (final colName in CatalogueContract.requiredCollections) {
      final colData = collections[colName] as Map<String, dynamic>? ?? {};
      final list = <Map<String, dynamic>>[];
      for (final entry in colData.entries) {
        final doc = entry.value as Map<String, dynamic>;
        final fields = FirestoreValueCodec.decodeFields(doc['fields']);
        if (fields['scopeType'] == 'SYSTEM') {
          if (colName == 'product_attribute_options' &&
              SystemCatalogueMetadata.redundantOptionIds.contains(entry.key)) {
            continue;
          }
          list.add({
            'name': '$colName/${entry.key}',
            'fields': FirestoreValueCodec.encodeFields(fields),
          });
        }
      }
      inputDocs[colName] = list;
    }
    return inputDocs;
  }

  late Directory dir;
  late LocalDatabase database;
  late FakeRemote remote;
  late ConnectivityService connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  late ProductRepository repo;

  const primerSubId =
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS';
  const primerCatId = 'SYS_CATEGORY_PRIMERS_UNDERCOATS';

  Future<LocalDataSource> local() async =>
      LocalDataSource(await database.open('', 'U'));

  Future<void> seedSyncQueries({
    String tenant = 'T',
    String business = 'BUS-001',
  }) async {
    final localDb = await local();
    for (final collection in [
      'products',
      'product_variants',
      'outlet_products',
      'document_sequences',
      'product_unique_keys',
    ]) {
      final spec = <String, dynamic>{
        'filters': OfflineFirestoreService.encodeFilters([
          FirestoreFilter('tenantId', 'EQUAL', tenant),
          FirestoreFilter('businessId', 'EQUAL', business),
        ]),
      };
      final key = SyncQueryRegistry.key(collection, spec);
      await localDb.db.insert(
        'sync_queries',
        {
          'queryKey': key,
          'collectionName': collection,
          'queryJson': jsonEncode(spec),
          'lastSyncedAt': '2026-10-17T00:00:00Z',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nubibill-dup-scope-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    remote = FakeRemote();
    connectivity = TestConnectivity()..available = false;
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    await service.setScope(tenant: 'T', business: 'BUS-001');
    repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );

    final localSource = LocalDataSource(await database.open('', 'U'));
    final inputDocs = loadProductionCatalogue();
    await SystemCatalogueSnapshot.import(
      source: localSource,
      documents: inputDocs,
      readTimes: {},
    );

    // Seed brand BR1
    await localSource.upsertRemote('brands', [
      {
        'name': 'brands/BR1',
        'fields': FirestoreValueCodec.encodeFields({
          'brandId': 'BR1',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'name': 'Berger',
        }),
      },
    ]);

    await seedSyncQueries(tenant: 'T', business: 'BUS-001');
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<void> seedLocal(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) async {
    remote.seed(collection, id, fields);
    await (await local()).upsertRemote(collection, [
      remote.docs['$collection/$id']!,
    ]);
  }

  String placementDocId({
    required String outlet,
    required String product,
    String tenant = 'T',
    String business = 'BUS-001',
  }) =>
      OutletProductModel.documentId(
        tenantId: tenant,
        businessId: business,
        outletId: outlet,
        productId: product,
      );

  Future<void> seedPlacement({
    required String outlet,
    required String product,
    String status = 'ACTIVE',
    bool? isActive,
    String tenant = 'T',
    String business = 'BUS-001',
  }) =>
      seedLocal(
        'outlet_products',
        placementDocId(
          outlet: outlet,
          product: product,
          tenant: tenant,
          business: business,
        ),
        {
          'outletProductId': placementDocId(
            outlet: outlet,
            product: product,
            tenant: tenant,
            business: business,
          ),
          'tenantId': tenant,
          'businessId': business,
          'outletId': outlet,
          'productId': product,
          'status': status,
          'isActive': isActive ?? status == 'ACTIVE',
        },
      );

  Future<void> seedProductMaster({
    required String productId,
    required String name,
    required String brandId,
    String brand = 'Berger',
    String status = 'ACTIVE',
    bool isDeleted = false,
    String tenant = 'T',
    String business = 'BUS-001',
  }) async {
    await seedLocal('products', productId, {
      'productId': productId,
      'productCode': 'PRD-0001',
      'tenantId': tenant,
      'businessId': business,
      'productName': name,
      'name': name,
      'brandId': brandId,
      'brand': brand,
      'categoryId': primerCatId,
      'categoryName': 'Primers & Undercoats',
      'subcategoryId': primerSubId,
      'subcategory': 'Interior Wall Primers',
      'status': status,
      'isDeleted': isDeleted,
      'baseUnitId': 'SYS_UNIT_LITRE',
      'defaultGstRateBps': 1800,
      'attributeValues': {
        'colourMode': 'Fixed Colour',
        'productColour': 'White',
      },
    });

    final variantId = 'VAR-$productId-1';
    await seedLocal('product_variants', variantId, {
      'variantId': variantId,
      'tenantId': tenant,
      'businessId': business,
      'productId': productId,
      'variantName': '1L Can',
      'sku': 'SKU-$productId-1',
      'barcode': 'INT-$productId-1',
      'baseUnitId': 'SYS_UNIT_LITRE',
      'commercialUnitId': 'SYS_UNIT_LITRE',
      'baseQuantityPerCommercialUnit': 1,
      'defaultGstRateBps': 1800,
      'status': status,
      'isDeleted': isDeleted,
      'attributeValues': {
        'unit': 'Litre',
        'packSize': 1,
        'soldAs': 'Can',
      },
    });

    // Write unique key reservation
    final normName = name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    final uniqueId = 'PM_${tenant}_${business}_PRODUCT_${normName}_$brandId';
    await seedLocal('product_unique_keys', uniqueId, {
      'tenantId': tenant,
      'businessId': business,
      'productId': productId,
    });
  }

  Map<String, dynamic> validProductFields({
    String brandId = 'BR1',
    String brand = 'Berger',
  }) => {
    'brandId': brandId,
    'brand': brand,
    'categoryId': primerCatId,
    'categoryName': 'Primers & Undercoats',
    'subcategoryId': primerSubId,
    'subcategory': 'Interior Wall Primers',
    'defaultGstRateBps': 1800,
    'attributeValues': {
      'colourMode': 'Fixed Colour',
      'productColour': 'White',
    },
  };

  List<Map<String, dynamic>> validVariants() => [
    {
      'variantName': '1L Can',
      'displayName': '1L Can',
      'baseUnitId': 'SYS_UNIT_LITRE',
      'commercialUnitId': 'SYS_UNIT_LITRE',
      'baseQuantityPerCommercialUnit': 1,
      'defaultGstRateBps': 1800,
      'attributeValues': {
        'unit': 'Litre',
        'packSize': 1,
        'soldAs': 'Can',
      },
    },
  ];

  group('Product Duplicate Scope & Outlet Visibility', () {
    test(
      'Same outlet duplicate is rejected with product-exists-in-outlet',
      () async {
        await seedLocal('businesses', 'BUS-001', {
          'businessId': 'BUS-001',
          'tenantId': 'T',
          'name': 'Suman Enterprises',
        });
        await seedLocal('outlets', 'OUT-001', {
          'outletId': 'OUT-001',
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'BUS-001',
          'outletName': 'Kolkata Hardware Shop',
          'status': 'ACTIVE',
        });

        // Seed existing product placed actively at OUT-001
        await seedProductMaster(
          productId: 'PROD-SIGMARK',
          name: 'Sigmark HMRM',
          brandId: 'BR1',
          brand: 'Berger',
        );
        await seedPlacement(outlet: 'OUT-001', product: 'PROD-SIGMARK');

        // Attempting to create duplicate at the same outlet throws product-exists-in-outlet
        expect(
          () => repo.createStructuredProduct(
            tenantId: 'T',
            businessId: 'BUS-001',
            outletId: 'OUT-001',
            productName: 'Sigmark HMRM',
            actorUid: 'USER-1',
            token: token('U'),
            productFields: validProductFields(brandId: 'BR1', brand: 'Berger'),
            variants: validVariants(),
          ),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'product-exists-in-outlet')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Add another Variant to the existing Product'),
                ),
          ),
        );
      },
    );

    test(
      'Different outlet duplicate throws product-exists-in-business with actionable details and safe assignment',
      () async {
        await seedLocal('businesses', 'BUS-001', {
          'businessId': 'BUS-001',
          'tenantId': 'T',
          'name': 'Suman Enterprises',
        });
        for (final outId in ['OUT-001', 'OUT-002']) {
          await seedLocal('outlets', outId, {
            'outletId': outId,
            'tenantId': 'T',
            'ownerUid': 'T',
            'businessId': 'BUS-001',
            'outletName': 'Shop $outId',
            'status': 'ACTIVE',
          });
        }

        // Product placed ONLY at OUT-002
        await seedProductMaster(
          productId: 'PROD-SIGMARK',
          name: 'Sigmark HMRM',
          brandId: 'BR1',
          brand: 'Berger',
        );
        await seedPlacement(outlet: 'OUT-002', product: 'PROD-SIGMARK');

        // Trying to create at OUT-001 throws product-exists-in-business
        late AppException caught;
        try {
          await repo.createStructuredProduct(
            tenantId: 'T',
            businessId: 'BUS-001',
            outletId: 'OUT-001',
            productName: 'Sigmark HMRM',
            actorUid: 'USER-1',
            token: token('U'),
            productFields: validProductFields(brandId: 'BR1', brand: 'Berger'),
            variants: validVariants(),
          );
          fail('Should have thrown AppException');
        } on AppException catch (e) {
          caught = e;
        }

        expect(caught.code, equals('product-exists-in-business'));
        expect(caught.details?['productId'], equals('PROD-SIGMARK'));
        expect(caught.details?['productName'], equals('Sigmark HMRM'));
        expect(caught.details?['brand'], equals('Berger'));

        // getProductsNotInOutlet identifies it as available to add to OUT-001
        final available = await repo.getProductsNotInOutlet(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          token: token('U'),
        );
        expect(available.map((p) => p.productId), contains('PROD-SIGMARK'));

        // Calling assignProductsToOutlet places it at OUT-001 safely without touching master records
        final changed = await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          productIds: ['PROD-SIGMARK'],
          token: token('U'),
        );
        expect(changed, equals(1));

        final out1Products = await repo.getOutletProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          token: token('U'),
        );
        expect(out1Products.map((p) => p.productId), contains('PROD-SIGMARK'));
      },
    );

    test(
      'Different business allows identical product name and brand without collision',
      () async {
        // Business 1 already has Sigmark HMRM
        await seedProductMaster(
          productId: 'PROD-BUS1-SIGMARK',
          name: 'Sigmark HMRM',
          brandId: 'BR1',
          brand: 'Berger',
          business: 'BUS-001',
        );

        // Business 2 creates the exact same product name and brand
        await seedLocal('businesses', 'BUS-002', {
          'businessId': 'BUS-002',
          'tenantId': 'T',
          'name': 'Other Business',
        });
        await seedLocal('outlets', 'OUT-002', {
          'outletId': 'OUT-002',
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'BUS-002',
          'outletName': 'Other Outlet',
          'status': 'ACTIVE',
        });
        await seedSyncQueries(tenant: 'T', business: 'BUS-002');

        await repo.createStructuredProduct(
          tenantId: 'T',
          businessId: 'BUS-002',
          outletId: 'OUT-002',
          productName: 'Sigmark HMRM',
          actorUid: 'USER-1',
          token: token('U'),
          productFields: validProductFields(brandId: 'BR1', brand: 'Berger'),
          variants: validVariants(),
        );

        final bus2Products = await repo.getProducts(
          tenantId: 'T',
          businessId: 'BUS-002',
          token: token('U'),
        );
        expect(bus2Products.map((p) => p.name), contains('Sigmark HMRM'));
      },
    );

    test(
      'Inactive outlet placement is returned when activeOnly is false and can be reactivated cleanly',
      () async {
        await seedLocal('businesses', 'BUS-001', {
          'businessId': 'BUS-001',
          'tenantId': 'T',
          'name': 'Suman Enterprises',
        });
        await seedLocal('outlets', 'OUT-001', {
          'outletId': 'OUT-001',
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'BUS-001',
          'outletName': 'Kolkata Hardware Shop',
          'status': 'ACTIVE',
        });

        // Seed product with INACTIVE placement at OUT-001 (reproducing user DB state)
        await seedProductMaster(
          productId: 'PROD-SIGMARK',
          name: 'Sigmark HMRM',
          brandId: 'BR1',
          brand: 'Berger',
        );
        await seedPlacement(
          outlet: 'OUT-001',
          product: 'PROD-SIGMARK',
          status: 'INACTIVE',
          isActive: false,
        );

        // Active only query excludes it
        final activeOnlyList = await repo.getOutletProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          token: token('U'),
          activeOnly: true,
        );
        expect(activeOnlyList.map((p) => p.productId), isNot(contains('PROD-SIGMARK')));

        // All placements query (activeOnly: false) includes it with status INACTIVE
        final allList = await repo.getOutletProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          token: token('U'),
          activeOnly: false,
        );
        final found = allList.firstWhere((p) => p.productId == 'PROD-SIGMARK');
        expect(found.status, equals('INACTIVE'));
        expect(found.isActive, isFalse);

        // Reactivating via assignProductsToOutlet restores active placement
        final changed = await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          productIds: ['PROD-SIGMARK'],
          token: token('U'),
        );
        expect(changed, equals(1));

        final postActivate = await repo.getOutletProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          token: token('U'),
          activeOnly: true,
        );
        expect(postActivate.map((p) => p.productId), contains('PROD-SIGMARK'));
      },
    );

    test(
      'Soft-deleted products do not block creation of a product with identical name and brand',
      () async {
        await seedLocal('businesses', 'BUS-001', {
          'businessId': 'BUS-001',
          'tenantId': 'T',
          'name': 'Suman Enterprises',
        });
        await seedLocal('outlets', 'OUT-001', {
          'outletId': 'OUT-001',
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'BUS-001',
          'outletName': 'Kolkata Hardware Shop',
          'status': 'ACTIVE',
        });

        // Seed a soft-deleted product
        await seedProductMaster(
          productId: 'PROD-OLD-DELETED',
          name: 'Old Weathercoat',
          brandId: 'BR1',
          brand: 'Berger',
          status: 'DELETED',
          isDeleted: true,
        );

        // Creating a new product with the same name and brand succeeds without collision
        await repo.createStructuredProduct(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          productName: 'Old Weathercoat',
          actorUid: 'USER-1',
          token: token('U'),
          productFields: validProductFields(brandId: 'BR1', brand: 'Berger'),
          variants: validVariants(),
        );

        final activeProducts = await repo.getProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          token: token('U'),
        );
        final created =
            activeProducts.firstWhere((p) => p.name == 'Old Weathercoat');
        expect(created.productId, isNot(equals('PROD-OLD-DELETED')));
      },
    );

    test(
      'Stale/orphaned product_unique_keys record is safely recovered and reassigned',
      () async {
        await seedLocal('businesses', 'BUS-001', {
          'businessId': 'BUS-001',
          'tenantId': 'T',
          'name': 'Suman Enterprises',
        });
        await seedLocal('outlets', 'OUT-001', {
          'outletId': 'OUT-001',
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'BUS-001',
          'outletName': 'Kolkata Hardware Shop',
          'status': 'ACTIVE',
        });

        // Seed an orphaned unique key pointing to a non-existent product
        final normName = 'stale test paint';
        final uniqueId = ProductRepository.productUniquenessId(
          tenantId: 'T',
          businessId: 'BUS-001',
          normalizedName: normName,
          brandId: 'BR1',
        );
        await seedLocal('product_unique_keys', uniqueId, {
          'tenantId': 'T',
          'businessId': 'BUS-001',
          'productId': 'PROD-NON-EXISTENT',
        });

        // Product creation must NOT fail with duplicate unique key; it should recover the orphaned key
        await repo.createStructuredProduct(
          tenantId: 'T',
          businessId: 'BUS-001',
          outletId: 'OUT-001',
          productName: 'Stale Test Paint',
          actorUid: 'USER-1',
          token: token('U'),
          productFields: validProductFields(brandId: 'BR1', brand: 'Berger'),
          variants: validVariants(),
        );

        final activeProducts = await repo.getProducts(
          tenantId: 'T',
          businessId: 'BUS-001',
          token: token('U'),
        );
        final created =
            activeProducts.firstWhere((p) => p.name == 'Stale Test Paint');
        expect(created.productId, isNotEmpty);

        // Verify the unique key now references the new product
        final keys = await service.queryDocuments(
          collection: 'product_unique_keys',
          filters: const [],
          idToken: token('U'),
        );
        final matchingKey = keys.firstWhere(
          (k) => (k['name'] as String).endsWith(uniqueId),
        );
        final fields = FirestoreRestService.decodeFields(matchingKey['fields']);
        expect(fields['productId'], equals(created.productId));
      },
    );
  });
}
