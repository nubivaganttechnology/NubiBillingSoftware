import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/outlet_product_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';

import 'offline_sync_test.dart'
    show FakeRemote, TestConnectivity, session, token;
import 'support/product_test_catalogue.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late FakeRemote remote;
  late ConnectivityService connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  late ProductRepository repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nubibill-placement-');
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
    repo = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
  });
  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<LocalDataSource> local() async =>
      LocalDataSource(await database.open('', 'U'));
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

  String placementId(String outlet, String product, {String tenant = 'T'}) =>
      OutletProductModel.documentId(
        tenantId: tenant,
        businessId: 'B',
        outletId: outlet,
        productId: product,
      );

  Future<void> seedPlacement(
    String outlet,
    String product, {
    String status = 'ACTIVE',
    bool? isActive,
    String tenant = 'T',
    String business = 'B',
    List<String>? variantIds,
  }) => seedLocal(
    'outlet_products',
    placementId(outlet, product, tenant: tenant),
    {
      'outletProductId': placementId(outlet, product, tenant: tenant),
      'tenantId': tenant,
      'businessId': business,
      'outletId': outlet,
      'productId': product,
      'status': status,
      'isActive': isActive ?? status == 'ACTIVE',
      if (variantIds != null) 'variantIds': variantIds,
    },
  );

  Future<void> seedMaster(String product, List<String> variants) async {
    await seedLocal('products', product, {
      'productId': product,
      'tenantId': 'T',
      'businessId': 'B',
      'productName': 'Name $product',
      'status': 'ACTIVE',
    });
    for (final variant in variants) {
      await seedLocal('product_variants', variant, {
        'variantId': variant,
        'tenantId': 'T',
        'businessId': 'B',
        'productId': product,
        'variantName': 'Var $variant',
        'baseUnitId': 'UN',
        'status': 'ACTIVE',
      });
    }
  }

  Future<void> seedStock(String outlet, String variant, int quantity) =>
      seedLocal('stock_balances', 'S_${outlet}_$variant', {
        'tenantId': 'T',
        'businessId': 'B',
        'outletId': outlet,
        'locationType': 'OUTLET',
        'locationId': outlet,
        'variantId': variant,
        'quantityOnHand': quantity,
      });

  /// Business B with outlets A and B; P1 placed only at A, P2 only at B.
  Future<void> seedTwoOutletBusiness() async {
    for (final outlet in ['A', 'B']) {
      await seedLocal('outlets', outlet, {
        'outletId': outlet,
        'tenantId': 'T',
        'ownerUid': 'T',
        'businessId': 'B',
        'outletName': 'Outlet $outlet',
        'status': 'ACTIVE',
      });
    }
    await seedMaster('P1', ['V1']);
    await seedMaster('P2', ['V2']);
    await seedPlacement('A', 'P1');
    await seedPlacement('B', 'P2');
    await seedStock('A', 'V1', 2000);
    await seedStock('B', 'V1', 500);
    await seedStock('B', 'V2', 700);
  }

  Future<List<String>> outletProductIds(String outlet) async => [
    for (final p in await repo.getOutletProducts(
      tenantId: 'T',
      businessId: 'B',
      outletId: outlet,
      token: token('U'),
    ))
      p.productId,
  ];

  Future<int> rowCount(String collection) async =>
      (await (await local()).db.query(
        LocalDataSource.table(collection),
        where: 'isDeleted=0',
      )).length;

  Future<void> seedCatalogue() async {
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
      'attributeLevel': 'VARIANT',
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
    await seedLocal('product_attributes', 'testAttr', {
      'attributeId': 'testAttr',
      'name': 'Test Attr',
      'dataType': 'TEXT',
      'attributeLevel': 'VARIANT',
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    });
  }

  Future<void> createFrom(
    ProductRepository target,
    String outlet,
    String name, {
    int variants = 1,
  }) => target.createStructuredProduct(
    tenantId: 'T',
    businessId: 'B',
    outletId: outlet,
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
      for (var i = 0; i < variants; i++)
        {
          'displayName': 'Standard $i',
          'baseUnitId': 'UN',
          'commercialUnitId': 'UN',
          'baseQuantityPerCommercialUnit': 1,
          'attributeValues': <String, dynamic>{'testAttr': 'size $i'},
        },
    ],
  );

  Map<String, dynamic> remoteFields(String key) =>
      FirestoreRestService.decodeFields(remote.docs[key]!['fields']);

  test('outlet view shows only products placed at that outlet', () async {
    await seedTwoOutletBusiness();
    await seedMaster('P3', ['V3']); // Business product with no placement.
    expect(await outletProductIds('A'), ['P1']);
    expect(await outletProductIds('B'), ['P2']);
    expect(await outletProductIds('C'), isEmpty);
  });

  test(
    'inactive, foreign-scope and restricted placements are honoured',
    () async {
      await seedTwoOutletBusiness();
      await seedMaster('P3', ['V3']);
      await seedMaster('P4', ['V4a', 'V4b']);
      await seedPlacement('A', 'P3', status: 'INACTIVE');
      await seedPlacement('A', 'P4', variantIds: ['V4b']);
      await seedPlacement('B', 'P1', tenant: 'OTHER');
      await seedPlacement('B', 'P3', business: 'OTHER_BUSINESS');
      await seedLocal('outlet_products', 'FLAG_OFF', {
        'tenantId': 'T',
        'businessId': 'B',
        'outletId': 'B',
        'productId': 'P4',
        'status': 'ACTIVE',
        'isActive': false,
      });
      final a = await repo.getOutletProducts(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'A',
        token: token('U'),
      );
      expect(a.map((p) => p.productId).toSet(), {'P1', 'P4'});
      expect(
        a
            .singleWhere((p) => p.productId == 'P4')
            .variants
            .map((v) => v.variantId),
        ['V4b'],
      );
      expect(await outletProductIds('B'), ['P2']);
    },
  );

  test(
    'business master holds P1 and P2 once while outlet views stay separate',
    () async {
      await seedTwoOutletBusiness();
      final all = await repo.getProducts(
        tenantId: 'T',
        businessId: 'B',
        token: token('U'),
      );
      expect(all.map((p) => p.productId).toSet(), {'P1', 'P2'});
      expect(await outletProductIds('A'), isNot(contains('P2')));
      expect(await outletProductIds('B'), isNot(contains('P1')));
    },
  );

  test(
    'outlet stock is outlet-specific and never aggregated across outlets',
    () async {
      await seedTwoOutletBusiness();
      Future<Map<String, int>> outletStock(String outlet) =>
          repo.getOutletProductStock(
            tenantId: 'T',
            businessId: 'B',
            outletId: outlet,
            token: token('U'),
          );
      expect(await outletStock('A'), {'V1': 2000});
      expect(await outletStock('B'), {'V1': 500, 'V2': 700});
      expect(await outletStock('C'), isEmpty);
      expect(
        () => repo.getOutletProductStock(
          tenantId: 'T',
          businessId: 'B',
          outletId: '',
          token: token('U'),
        ),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('outlet products require an outlet', () async {
    await expectLater(
      repo.getOutletProducts(
        tenantId: 'T',
        businessId: 'B',
        outletId: '',
        token: token('U'),
      ),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'creating from an outlet saves masters once and places only at that outlet',
    () async {
      await seedCatalogue();
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      await createFrom(repo, 'A', 'Alpha', variants: 2);
      await createFrom(repo, 'B', 'Beta');

      expect(await rowCount('products'), 2);
      expect(await rowCount('product_variants'), 3);
      expect(await rowCount('outlet_products'), 2);
      final alpha = (await outletProductIds('A')).single;
      final beta = (await outletProductIds('B')).single;
      expect(alpha, isNot(beta));
      final all = await repo.getProducts(
        tenantId: 'T',
        businessId: 'B',
        token: token('U'),
      );
      expect(all.map((p) => p.productId).toSet(), {alpha, beta});
      expect(all.singleWhere((p) => p.productId == alpha).variants.length, 2);

      // Product, variants and placement are one atomic outbox batch.
      final source = await local();
      final outbox = await source.db.query('sync_outbox', orderBy: 'id');
      final alphaBatch = outbox
          .where((r) => r['entityType'] == 'outlet_products')
          .firstWhere(
            (r) => r['documentId'] == placementId('A', alpha),
          )['batchId'];
      final inBatch = outbox.where((r) => r['batchId'] == alphaBatch);
      expect(inBatch.where((r) => r['entityType'] == 'products').length, 1);
      expect(
        inBatch.where((r) => r['entityType'] == 'product_variants').length,
        2,
      );
      expect(
        inBatch.where((r) => r['entityType'] == 'outlet_products').length,
        1,
      );
      expect(remote.commits, 0);

      connectivity.available = true;
      await sync.sync();
      expect(sync.error, isNull);
      expect(await SyncOutboxRepository(source).pendingCount(), 0);
      expect(
        remote.docs.keys.where((k) => k.startsWith('products/')).length,
        2,
      );
      expect(
        remote.docs.keys.where((k) => k.startsWith('product_variants/')).length,
        3,
      );
      final placements = remote.docs.keys
          .where((k) => k.startsWith('outlet_products/'))
          .toList();
      expect(placements.length, 2);
      final byProduct = {
        for (final key in placements)
          remoteFields(key)['productId'] as String: remoteFields(key),
      };
      expect(byProduct[alpha]!['outletId'], 'A');
      expect(byProduct[beta]!['outletId'], 'B');
      for (final fields in byProduct.values) {
        expect(fields['tenantId'], 'T');
        expect(fields['businessId'], 'B');
        expect(fields['status'], 'ACTIVE');
        expect(fields['isActive'], true);
      }
    },
  );

  test('same product cannot be created again from another outlet', () async {
    await seedCatalogue();
    await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
    await sync.sync();
    connectivity.available = false;
    await createFrom(repo, 'A', 'Alpha');
    await expectLater(
      createFrom(repo, 'B', 'Alpha'),
      throwsA(isA<AppException>()),
    );
    expect(await rowCount('products'), 1);
    expect(await rowCount('product_variants'), 1);
    expect(await rowCount('outlet_products'), 1);
  });

  test('adding an existing product creates only a placement', () async {
    await seedTwoOutletBusiness();
    final source = await local();
    final productsBefore = await source.db.query('local_products');
    final variantsBefore = await source.db.query('local_product_variants');
    connectivity.available = false;

    final added = await repo.assignProductsToOutlet(
      tenantId: 'T',
      businessId: 'B',
      outletId: 'B',
      productIds: ['P1', 'P1'],
      token: token('U'),
    );
    expect(added, 1);
    expect((await outletProductIds('B')).toSet(), {'P1', 'P2'});
    expect(await outletProductIds('A'), ['P1']);
    expect(await source.db.query('local_products'), productsBefore);
    expect(await source.db.query('local_product_variants'), variantsBefore);
    final outbox = await source.db.query('sync_outbox');
    expect(outbox.map((r) => r['entityType']).toSet(), {'outlet_products'});
    expect(outbox.single['documentId'], placementId('B', 'P1'));
    expect(outbox.single['operation'], 'CREATE');

    // Idempotent.
    expect(
      await repo.assignProductsToOutlet(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'B',
        productIds: ['P1'],
        token: token('U'),
      ),
      0,
    );
    expect(await rowCount('outlet_products'), 3);
  });

  test(
    'adding reactivates an inactive placement and rejects invalid targets',
    () async {
      await seedTwoOutletBusiness();
      await seedPlacement('B', 'P1', status: 'INACTIVE');
      expect(await outletProductIds('B'), ['P2']);
      expect(
        (await repo.getProductsNotInOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'B',
          token: token('U'),
        )).map((p) => p.productId),
        ['P1'],
      );
      await repo.assignProductsToOutlet(
        tenantId: 'T',
        businessId: 'B',
        outletId: 'B',
        productIds: ['P1'],
        token: token('U'),
      );
      expect((await outletProductIds('B')).toSet(), {'P1', 'P2'});
      expect(await rowCount('outlet_products'), 3);

      await expectLater(
        repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'MISSING',
          productIds: ['P1'],
          token: token('U'),
        ),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productIds: ['NOT_A_PRODUCT'],
          token: token('U'),
        ),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'placement survives an offline restart and is not guessed on upgrade',
    () async {
      await seedCatalogue();
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      await createFrom(repo, 'A', 'Alpha');
      final alpha = (await outletProductIds('A')).single;
      await database.close();

      final offlineRemote = FakeRemote()..offline = true;
      final restartedDatabase = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final restartedSync = SyncEngine(
        offlineRemote,
        TestConnectivity()..available = false,
        sessionProvider: () async => session('U'),
      );
      final restarted = OfflineFirestoreService(
        restartedDatabase,
        offlineRemote,
        restartedSync,
      );
      await restarted.activate('U');
      final restartedRepo = ProductRepository(
        restarted,
        restarted,
        allowUnapprovedIsolatedCatalogueForTests: true,
      );
      expect(
        [
          for (final p in await restartedRepo.getOutletProducts(
            tenantId: 'T',
            businessId: 'B',
            outletId: 'A',
            token: token('U'),
          ))
            p.productId,
        ],
        [alpha],
      );
      expect(
        await restartedRepo.getOutletProducts(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'B',
          token: token('U'),
        ),
        isEmpty,
      );
      expect(offlineRemote.queries + offlineRemote.reads, 0);
      restartedSync.dispose();
      await restartedDatabase.close();
    },
  );

  test(
    'schema upgrade adds an empty placement table and never guesses placement',
    () async {
      final dbPath = '${dir.path}/legacy.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await LocalDatabase.migrate(db, 0, version);
            await db.execute('DROP TABLE local_outlet_products');
          },
        ),
      );
      await legacy.insert('local_products', {
        'remoteId': 'OLD',
        'payloadJson': jsonEncode(
          FirestoreRestService.encodeFields({
            'tenantId': 'T',
            'businessId': 'B',
            'productName': 'Old',
          }),
        ),
        'tenantId': 'T',
        'businessId': 'B',
        'localUpdatedAt': LocalDataSource.now(),
      });
      await legacy.close();
      final upgraded = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: LocalDatabase.schemaVersion,
          onUpgrade: LocalDatabase.migrate,
        ),
      );
      expect(await upgraded.query('local_products'), hasLength(1));
      expect(await upgraded.query('local_outlet_products'), isEmpty);
      await upgraded.close();
    },
  );

  test('switching outlets performs zero Firestore reads', () async {
    await seedTwoOutletBusiness();
    await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
    await sync.sync();
    final baseline = remote.queries + remote.reads + remote.pullReasons.length;
    final seen = <String, List<String>>{};
    for (final outlet in ['A', 'B', 'A', 'B']) {
      await service.setScope(tenant: 'T', business: 'B', outlet: outlet);
      seen[outlet] = await outletProductIds(outlet);
      await repo.getOutletProductStock(
        tenantId: 'T',
        businessId: 'B',
        outletId: outlet,
        token: token('U'),
      );
    }
    expect(seen, {
      'A': ['P1'],
      'B': ['P2'],
    });
    expect(remote.queries + remote.reads + remote.pullReasons.length, baseline);
  });

  test(
    'outlet_products is registered once at business level for sync',
    () async {
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await service.setScope(tenant: 'T', business: 'B', outlet: 'B');
      final rows = await (await local()).db.query(
        'sync_queries',
        where: "collectionName='outlet_products'",
      );
      expect(rows, hasLength(1));
      expect(rows.single['queryJson'], isNot(contains('outletId')));
    },
  );

  group('migration of existing products', () {
    /// Three pre-existing products that predate outlet_products.
    Future<void> seedLegacyCatalogue() async {
      for (final outlet in ['A', 'B']) {
        await seedLocal('outlets', outlet, {
          'outletId': outlet,
          'tenantId': 'T',
          'ownerUid': 'T',
          'businessId': 'B',
          'outletName': 'Outlet $outlet',
          'status': 'ACTIVE',
        });
      }
      await seedMaster('P1', ['V1']);
      await seedMaster('P2', ['V2']);
      await seedMaster('P3', ['V3']);
      await seedStock('A', 'V1', 2000);
      await seedLocal('inventory_transactions', 'TX1', {
        'tenantId': 'T',
        'businessId': 'B',
        'outletId': 'A',
        'locationType': 'OUTLET',
        'variantId': 'V1',
      });
      await seedLocal('goods_receipt_items', 'GRI2', {
        'tenantId': 'T',
        'businessId': 'B',
        'outletId': 'B',
        'variantId': 'V2',
      });
      // Godown stock and other tenants/outlets are not outlet evidence.
      await seedLocal('stock_balances', 'GODOWN3', {
        'tenantId': 'T',
        'businessId': 'B',
        'outletId': 'A',
        'locationType': 'GODOWN',
        'variantId': 'V3',
        'quantityOnHand': 10,
      });
      await seedLocal('stock_balances', 'OTHER_TENANT', {
        'tenantId': 'OTHER',
        'businessId': 'B',
        'outletId': 'B',
        'locationType': 'OUTLET',
        'variantId': 'V3',
        'quantityOnHand': 10,
      });
    }

    // Pulls refresh lastSyncedAt; masters are compared on their data columns.
    Future<List<List<Object?>>> snapshot(String table) async => [
      for (final r in await (await local()).db.query(
        table,
        orderBy: 'remoteId',
      ))
        [
          r['remoteId'],
          r['payloadJson'],
          r['isDeleted'],
          r['syncStatus'],
          r['localRevision'],
        ],
    ];
    Future<List<List<Object?>>> masterRows() => snapshot('local_products');

    Future<dynamic> backfill() => repo.backfillKnownOutletPlacements(
      tenantId: 'T',
      businessId: 'B',
      actorUid: 'U',
      token: token('U'),
    );

    test('places each product only at the outlet its history proves', () async {
      await seedLegacyCatalogue();
      expect(await masterRows(), hasLength(3));
      expect(await rowCount('outlet_products'), 0);
      // Before the fix every outlet view was empty.
      expect(await outletProductIds('A'), isEmpty);

      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      final productsBefore = await masterRows();
      final variantsBefore = await snapshot('local_product_variants');
      expect(productsBefore.where((r) => r[2] == 0), hasLength(3));
      final report = await backfill();

      expect(report, isNotNull);
      expect(
        {
          for (final a in report.assignments)
            '${a.productId}@${a.outletId}': a.evidence,
        },
        {
          'P1@A': ['inventory_transactions', 'stock_balances'],
          'P2@B': ['goods_receipt_items'],
        },
      );
      expect(report.unassigned, {'P3': 'Name P3'});
      expect(await outletProductIds('A'), ['P1']);
      expect(await outletProductIds('B'), ['P2']);
      expect(
        (await repo.getProducts(
          tenantId: 'T',
          businessId: 'B',
          token: token('U'),
        )).map((p) => p.productId).toSet(),
        {'P1', 'P2', 'P3'},
      );

      // Masters are untouched: same rows, nothing deleted, nothing queued.
      expect(await masterRows(), productsBefore);
      expect(await snapshot('local_product_variants'), variantsBefore);
      final outbox = await (await local()).db.query('sync_outbox');
      expect(outbox.map((r) => r['entityType']).toSet(), {'outlet_products'});
      expect(outbox, hasLength(2));
    });

    test(
      'runs once, waits for the first sync and respects manual choices',
      () async {
        await seedLegacyCatalogue();
        // Local data cannot be trusted before the first complete sync.
        expect(await backfill(), isNull);
        expect(await rowCount('outlet_products'), 0);

        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        connectivity.available = false;
        // The user deliberately deactivated P1 at A before the migration ran.
        await seedPlacement('A', 'P1', status: 'INACTIVE');
        expect(await backfill(), isNotNull);
        expect(await outletProductIds('A'), isEmpty);
        expect(await rowCount('outlet_products'), 2);
        expect(await backfill(), isNull);
        expect(await rowCount('outlet_products'), 2);
      },
    );

    test(
      'unproven products can be assigned manually without duplication',
      () async {
        await seedLegacyCatalogue();
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        connectivity.available = false;
        await backfill();
        expect(
          (await repo.getProductsNotInOutlet(
            tenantId: 'T',
            businessId: 'B',
            outletId: 'A',
            token: token('U'),
          )).map((p) => p.productId).toSet(),
          {'P2', 'P3'},
        );
        await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productIds: ['P3'],
          token: token('U'),
        );
        expect((await outletProductIds('A')).toSet(), {'P1', 'P3'});
        expect(await outletProductIds('B'), ['P2']);
        expect(await rowCount('products'), 3);
        expect(await rowCount('product_variants'), 3);
      },
    );

    test('an explicit outletId on the master is proof of placement', () async {
      for (final outlet in ['A', 'B']) {
        await seedLocal('outlets', outlet, {
          'tenantId': 'T',
          'businessId': 'B',
          'status': 'ACTIVE',
        });
      }
      await seedLocal('products', 'P9', {
        'productId': 'P9',
        'tenantId': 'T',
        'businessId': 'B',
        'productName': 'Tagged',
        'status': 'ACTIVE',
        'outletId': 'B',
      });
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      await backfill();
      expect(await outletProductIds('B'), ['P9']);
      expect(await outletProductIds('A'), isEmpty);
    });
  });

  group('pending products, code sequences and sync status', () {
    Future<void> seedSequences(int next) async {
      for (final entry in {
        'PRODUCT': 'PRD',
        'PRODUCT_VARIANT': 'SKU',
      }.entries) {
        remote.seed('document_sequences', 'T_B_${entry.key}', {
          'tenantId': 'T',
          'businessId': 'B',
          'sequenceType': entry.key,
          'prefix': entry.value,
          'padding': 4,
          'nextNumber': next,
        });
      }
    }

    Future<Map<String, dynamic>> localFields(String c, String id) async =>
        FirestoreRestService.decodeFields(
          jsonDecode(
            (await (await local()).row(c, id))!['payloadJson'] as String,
          ),
        );

    test('pending product is visible in its outlet only, then syncs to the same rows', () async {
      await seedCatalogue();
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      await createFrom(repo, 'A', 'Pending P4');
      final id = (await outletProductIds('A')).single;
      expect(await outletProductIds('B'), isEmpty);
      final source = await local();
      expect(
        (await source.row('products', id))!['syncStatus'],
        'PENDING_CREATE',
      );
      connectivity.available = true;
      await sync.sync();
      expect((await source.row('products', id))!['syncStatus'], 'SYNCED');
      expect(await rowCount('products'), 1);
      expect(await rowCount('outlet_products'), 1);
      expect(await outletProductIds('A'), [id]);
      expect(await outletProductIds('B'), isEmpty);
    });

    test('sequence conflict (local 7, remote 9) rebases the unissued code and never goes backward', () async {
      await seedCatalogue();
      await seedSequences(7);
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      await sync.sync();
      connectivity.available = false;
      await createFrom(repo, 'A', 'Offline Dia');
      final id = (await outletProductIds('A')).single;
      expect((await localFields('products', id))['productCode'], 'PRD-0007');
      // Another client meanwhile issued PRD-0007 and PRD-0008.
      for (final n in [7, 8]) {
        remote.seed('products', 'OTHER$n', {
          'productId': 'OTHER$n',
          'tenantId': 'T',
          'businessId': 'B',
          'productCode': 'PRD-000$n',
          'productName': 'Other $n',
          'status': 'ACTIVE',
        });
      }
      await seedSequences(9);
      connectivity.available = true;
      await sync.sync();

      expect(sync.error, isNull);
      expect(await SyncOutboxRepository(await local()).pendingCount(), 0);
      expect(remoteFields('products/$id')['productCode'], 'PRD-0009');
      expect((await localFields('products', id))['productCode'], 'PRD-0009');
      final codes = [
        for (final e in remote.docs.entries)
          if (e.key.startsWith('products/'))
            FirestoreRestService.decodeFields(e.value['fields'])['productCode'],
      ];
      expect(codes.toSet().length, codes.length);
      expect(
        remoteFields('document_sequences/T_B_PRODUCT')['nextNumber'],
        greaterThanOrEqualTo(10),
      );
      expect(
        (await localFields('document_sequences', 'T_B_PRODUCT'))['nextNumber'],
        greaterThanOrEqualTo(10),
      );
    });

    test(
      'a lower remote counter never lowers the sequence or changes the code',
      () async {
        await seedCatalogue();
        await seedSequences(7);
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        connectivity.available = false;
        await createFrom(repo, 'A', 'Offline Dia');
        final id = (await outletProductIds('A')).single;
        await seedSequences(3);
        connectivity.available = true;
        await sync.sync();
        expect(sync.error, isNull);
        expect(remoteFields('products/$id')['productCode'], 'PRD-0007');
        expect(remoteFields('document_sequences/T_B_PRODUCT')['nextNumber'], 8);
      },
    );

    test(
      'a stale counter cannot reissue a code already used in the business',
      () async {
        await seedCatalogue();
        await seedSequences(3);
        remote.seed('products', 'OLD', {
          'productId': 'OLD',
          'tenantId': 'T',
          'businessId': 'B',
          'productCode': 'PRD-0010',
          'productName': 'Old',
          'status': 'ACTIVE',
        });
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        await createFrom(repo, 'A', 'Fresh');
        final id = (await outletProductIds('A')).single;
        expect((await localFields('products', id))['productCode'], 'PRD-0011');
      },
    );

    test(
      'historical errors on inactive queries do not make the status Sync error',
      () async {
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        await service.setScope(tenant: 'T', business: 'B2', outlet: 'A');
        final source = await local();
        await source.db.update('sync_queries', {
          'lastError': 'Quota exceeded. (HTTP 429)',
        }, where: 'active=0');
        expect(
          await source.db.query(
            'sync_queries',
            where: 'active=0 AND lastError IS NOT NULL',
          ),
          isNotEmpty,
        );
        await sync.sync();
        expect(sync.state, SyncState.synced);
        expect(sync.error, isNull);
      },
    );

    test('a current active sync failure does show Sync error', () async {
      await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
      remote.quota = true;
      await sync.sync();
      expect(sync.state, SyncState.error);
      remote.quota = false;
    });

    test(
      'safely removing product from outlet marks placement inactive without touching masters',
      () async {
        await seedCatalogue();
        for (final outlet in ['A', 'B']) {
          await seedLocal('outlets', outlet, {
            'outletId': outlet,
            'tenantId': 'T',
            'ownerUid': 'T',
            'businessId': 'B',
            'outletName': 'Outlet $outlet',
            'status': 'ACTIVE',
          });
        }
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();
        await createFrom(repo, 'A', 'Paint Test Master');
        final productId = (await outletProductIds('A')).single;

        // Also place at outlet B to prove other outlets are not affected
        await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'B',
          productIds: [productId],
          token: token('U'),
          actorUid: 'U',
        );
        expect(await outletProductIds('B'), [productId]);

        // Verify active placement at outlet A before deactivation
        final placementsBefore = await repo.getOutletPlacements(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          token: token('U'),
        );
        expect(placementsBefore.length, 1);
        expect(placementsBefore.first.isActive, isTrue);

        // Deactivate from outlet A
        final removed = await repo.removeProductFromOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productId: productId,
          token: token('U'),
          actorUid: 'U',
        );
        expect(removed, isTrue);

        // 1. Row preserved in outlet_products (no hard delete)
        final placementId = OutletProductModel.documentId(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productId: productId,
        );
        final placementFields =
            await localFields('outlet_products', placementId);
        expect(placementFields['status'], 'INACTIVE');
        expect(placementFields['isActive'], isFalse);
        expect(placementFields['updatedBy'], 'U');

        // 2. Product and variant masters remain intact
        final productDoc = await localFields('products', productId);
        expect(productDoc['status'], 'ACTIVE');
        final masters = await repo.getProducts(
          tenantId: 'T',
          businessId: 'B',
          token: token('U'),
        );
        final productMaster =
            masters.firstWhere((p) => p.productId == productId);
        expect(productMaster.variants, isNotEmpty);

        // 3. Product disappears from outlet A active listing
        expect(await outletProductIds('A'), isEmpty);

        // 4. Other outlet placement (B) remains active and untouched
        expect(await outletProductIds('B'), [productId]);

        // 5. Product is now available under "Add existing product" for outlet A
        final notInOutlet = await repo.getProductsNotInOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          token: token('U'),
        );
        expect(notInOutlet.map((p) => p.productId), contains(productId));

        // 6. Normal outbox write occurred for outlet_products UPDATE
        final source = await local();
        final outboxRows = await source.db.query(
          'sync_outbox',
          where: 'entityType = ? AND documentId = ?',
          whereArgs: ['outlet_products', placementId],
        );
        expect(outboxRows, isNotEmpty);

        // 7. Reactivating via assignProductsToOutlet restores active placement
        final reactivated = await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productIds: [productId],
          token: token('U'),
          actorUid: 'U',
        );
        expect(reactivated, 1);
        expect(await outletProductIds('A'), [productId]);
      },
    );

    test(
      'multi-select placement removal mutates only outlet_products and queues no products mutation',
      () async {
        await seedCatalogue();
        for (final outlet in ['A', 'B']) {
          await seedLocal('outlets', outlet, {
            'outletId': outlet,
            'tenantId': 'T',
            'ownerUid': 'T',
            'businessId': 'B',
            'outletName': 'Outlet $outlet',
            'status': 'ACTIVE',
          });
        }
        await service.setScope(tenant: 'T', business: 'B', outlet: 'A');
        await sync.sync();

        await createFrom(repo, 'A', 'Paint Alpha Master');
        await createFrom(repo, 'A', 'Paint Beta Master');
        final allA = await outletProductIds('A');
        final p1 = allA[0];
        final p2 = allA[1];

        // Assign both to Outlet B as well
        await repo.assignProductsToOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'B',
          productIds: [p1, p2],
          token: token('U'),
          actorUid: 'U',
        );

        expect(await outletProductIds('A'), [p1, p2]);
        expect(await outletProductIds('B'), [p1, p2]);

        // Sync first so outbox is empty before removal
        await sync.sync();
        final source = await local();
        expect(await source.db.query('sync_outbox'), isEmpty);

        // Remove both from Outlet A
        final removed1 = await repo.removeProductFromOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productId: p1,
          token: token('U'),
          actorUid: 'U',
        );
        final removed2 = await repo.removeProductFromOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          productId: p2,
          token: token('U'),
          actorUid: 'U',
        );

        expect(removed1, isTrue);
        expect(removed2, isTrue);

        // Masters and variants remain completely ACTIVE
        final doc1 = await localFields('products', p1);
        final doc2 = await localFields('products', p2);
        expect(doc1['status'], 'ACTIVE');
        expect(doc1['isDeleted'], isNot(true));
        expect(doc2['status'], 'ACTIVE');
        expect(doc2['isDeleted'], isNot(true));

        final masters = await repo.getProducts(
          tenantId: 'T',
          businessId: 'B',
          token: token('U'),
        );
        for (final id in [p1, p2]) {
          final m = masters.firstWhere((p) => p.productId == id);
          expect(m.isActive, isTrue);
          expect(m.variants.every((v) => v.status == 'ACTIVE'), isTrue);
        }

        // Outlet A has 0 products; Outlet B still has both
        expect(await outletProductIds('A'), isEmpty);
        expect(await outletProductIds('B'), [p1, p2]);

        // Both are available to add back to Outlet A
        final candidates = await repo.getProductsNotInOutlet(
          tenantId: 'T',
          businessId: 'B',
          outletId: 'A',
          token: token('U'),
        );
        expect(candidates.map((p) => p.productId), containsAll([p1, p2]));

        // Outbox contains mutations ONLY for outlet_products (no products or product_variants)
        final outboxRows = await source.db.query('sync_outbox');
        final entityTypes = outboxRows.map((r) => r['entityType']).toSet();
        expect(entityTypes.contains('products'), isFalse);
        expect(entityTypes.contains('product_variants'), isFalse);
        expect(entityTypes.contains('outlet_products'), isTrue);
      },
    );
  });
}
