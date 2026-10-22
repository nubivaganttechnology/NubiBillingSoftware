import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/models/reclassification_plan.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'product_entry_form_test.dart' show EntryController, field;
import 'support/phase10e_release.dart' show release4Documents;

// No HTTP client exists in this fixture. Any attempted remote call fails loudly.
class _ForbiddenRemote implements FirestoreRestService {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Phase 7C forbids remote calls: ${invocation.memberName}');
  }
}

// Only background scheduling is disabled; persistence uses the real offline
// service, LocalTransactionContext, SyncOutboxRepository and SQLite transaction.
class _UnscheduledSync extends SyncEngine {
  _UnscheduledSync(FirestoreRestService remote)
    : super(
        remote,
        ConnectivityService()..available = false,
        sessionProvider: () async => null,
      );
  @override
  void schedule({bool pull = false, String reason = 'OUTBOX'}) {}
}

class _Fixture {
  late Directory directory;
  late LocalDatabase database;
  late LocalDataSource local;
  late _ForbiddenRemote remote;
  late _UnscheduledSync sync;
  late OfflineFirestoreService service;
  late ProductRepository repository;
  String get token =>
      'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'phase7c', 'aud': EnvironmentConfig.projectId})))}.signature';

  Future<void> open() async {
    directory = await Directory.systemTemp.createTemp('nubibill-phase7c-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    remote = _ForbiddenRemote();
    sync = _UnscheduledSync(remote);
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('phase7c');
    local = LocalDataSource(
      await database.open(EnvironmentConfig.projectId, 'phase7c'),
    );
    await SystemCatalogueSnapshot.import(
      source: local,
      documents: release4Documents(),
      readTimes: const {},
      allowUnapprovedIsolatedForTests: true,
    );
    repository = ProductRepository(
      service,
      service,
      allowUnapprovedIsolatedCatalogueForTests: true,
    );
    await seed('brands', 'BR', {'brandId': 'BR', 'name': 'Berger'}, system: false);
    for (final id in ['CA', 'CB']) {
      await seed('product_categories', id, {'categoryId': id, 'name': id}, system: false);
    }
    for (final entry in {
      'SU': 'CA',
      'SAME': 'CA',
      'SAFE': 'CB',
      'DROP': 'CB',
    }.entries) {
      await seed('product_subcategories', entry.key, {
        'subcategoryId': entry.key,
        'categoryId': entry.value,
        'name': entry.key,
        'templateStatus': 'READY',
        'unitRules': {
          'allowedPackUnits': ['SYS_UNIT_PIECE'],
          'defaultPackUnit': 'SYS_UNIT_PIECE',
          'allowedSellingUnits': ['SYS_UNIT_PIECE'],
          'defaultSellingUnit': 'SYS_UNIT_PIECE',
          'allowedBaseUnits': ['SYS_UNIT_PIECE'],
          'defaultBaseUnit': 'SYS_UNIT_PIECE',
          'conversionAllowed': false,
        },
      }, system: false);
      for (final attr in [
        'usage',
        'brushSize',
        if (entry.key != 'DROP') 'old',
      ]) {
        await seed('subcategory_attribute_templates', '${entry.key}-$attr', {
          'subcategoryId': entry.key,
          'attributeId': attr,
          'attributeLevel': attr == 'brushSize' ? 'VARIANT' : 'PRODUCT',
        }, system: false);
      }
    }
    // `usage` and `brushSize` are canonical attributes from the installed
    // catalogue fixture; only the synthetic `old` attribute is business-owned.
    for (final id in ['old']) {
      await seed('product_attributes', id, {
        'attributeId': id,
        'name': id,
        'dataType': id == 'brushSize' ? 'NUMBER' : 'TEXT',
        'attributeLevel': id == 'brushSize' ? 'VARIANT' : 'PRODUCT',
      }, system: false);
    }
    await seed('products', 'P', {
      'productId': 'P',
      'productName': 'Durable Brush',
      'name': 'Durable Brush',
      ...fields(subcategory: 'SU', category: 'CA'),
      'version': 1,
    }, system: false);
    for (var i = 1; i <= 3; i++) {
      await seed('product_variants', 'V$i', {
        ...variant('V$i'),
        'productId': 'P',
        'sku': 'SKU-000$i',
        'variantCode': 'SKU-000$i',
        'variantName': 'Size $i',
        'productName': 'Durable Brush',
        'version': 1,
      }, system: false);
    }
    await seed('document_sequences', 'T_B_PRODUCT_VARIANT', {
      'nextNumber': 4,
      'sequenceType': 'PRODUCT_VARIANT',
    }, system: false);
    // Satisfy existing offline creation prerequisites without remote bootstrap.
    for (final collection in [
      'products',
      'product_variants',
      'document_sequences',
      'product_unique_keys',
    ]) {
      final spec = jsonEncode({
        'filters': OfflineFirestoreService.encodeFilters([
          const FirestoreFilter('tenantId', 'EQUAL', 'T'),
          const FirestoreFilter('businessId', 'EQUAL', 'B'),
        ]),
      });
      await local.db.insert('sync_queries', {
        'queryKey': '$collection:$spec',
        'collectionName': collection,
        'queryJson': spec,
        'lastSyncedAt': '2026-10-04T00:00:00Z',
      });
    }
  }

  Future<void> seed(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    bool system = true,
  }) => local.upsertRemote(collection, [
    {
      'name': '$collection/$id',
      'updateTime': 'baseline-$id',
      'fields': FirestoreRestService.encodeFields({
        'status': 'ACTIVE',
        'isDeleted': false,
        if (system)
          'scopeType': 'SYSTEM'
        else ...{
          'tenantId': 'T',
          'businessId': 'B',
        },
        'createdAt': DateTime.utc(2026),
        'updatedAt': DateTime.utc(2026),
        ...fields,
      }),
    },
  ]);

  Map<String, dynamic> fields({
    String subcategory = 'SAFE',
    String category = 'CB',
  }) => {
    'brandId': 'BR',
    'brand': 'Berger',
    'categoryId': category,
    'categoryName': category,
    'subcategoryId': subcategory,
    'subcategory': subcategory,
    'attributeValues': {
      'usage': 'Interior',
      if (subcategory != 'DROP') 'old': 'keep',
    },
    'defaultGstRateBps': 0,
    'status': 'ACTIVE',
  };
  Map<String, dynamic> variant(String? id, {String? barcode}) => {
    'variantId': ?id,
    'barcode': barcode ?? (id == null ? 'BC-NEW' : 'BC-$id'),
    'attributeValues': {
      'brushSize': id == null ? 4 : int.parse(id.substring(1)),
    },
    'baseUnitId': 'SYS_UNIT_PIECE',
    'commercialUnitId': 'SYS_UNIT_PIECE',
    'packUnitId': 'SYS_UNIT_PIECE',
    'commercialUnitName': 'Piece',
    'baseQuantityPerCommercialUnit': 1,
    'status': 'ACTIVE',
  };
  List<Map<String, dynamic>> get unchanged => [
    for (final id in ['V1', 'V2', 'V3']) variant(id),
  ];
  List<Map<String, dynamic>> get mixed => [
    variant('V1')..['sellingPrice'] = 1200,
    variant('V2')..['sellingPrice'] = 2400,
    variant(null), // V3 is retired after preserved updates and the insertion.
  ];
  Future<void> edit(
    List<Map<String, dynamic>> variants, {
    Map<String, dynamic>? productFields,
  }) => repository.updateStructuredProduct(
    tenantId: 'T',
    businessId: 'B',
    productId: 'P',
    productName: 'Durable Brush',
    actorUid: 'phase7c',
    token: token,
    productFields: productFields ?? fields(),
    variants: variants,
  );
  Future<Map<String, dynamic>> doc(String collection, String id) async =>
      FirestoreRestService.decodeFields(
        jsonDecode((await local.row(collection, id))!['payloadJson'] as String),
      );
  Future<Map<String, Object>> snapshot() async => {
    for (final table in [
      ...LocalDatabase.tables.values,
      'sync_outbox',
      'sync_queries',
      'sqlite_sequence',
    ])
      table: await local.db.rawQuery('SELECT * FROM $table ORDER BY 1'),
  };
  Future<void> integrity() async {
    expect(
      await local.db.rawQuery('''
      SELECT v.remoteId FROM local_product_variants v
      LEFT JOIN local_products p
        ON p.remoteId=json_extract(v.payloadJson, '\$.productId.stringValue')
      WHERE v.status='ACTIVE' AND v.isDeleted=0 AND p.remoteId IS NULL
    '''),
      isEmpty,
      reason: 'No ACTIVE orphan variants',
    );
    for (final key in ['sku', 'barcode']) {
      expect(
        await local.db.rawQuery('''
        SELECT lower(trim(json_extract(payloadJson, '\$.$key.stringValue'))) value,
          COUNT(*) count FROM local_product_variants
        WHERE status='ACTIVE' AND isDeleted=0
          AND trim(COALESCE(json_extract(payloadJson, '\$.$key.stringValue'), ''))!=''
        GROUP BY tenantId,businessId,value HAVING COUNT(*)>1
      '''),
        isEmpty,
        reason: 'No duplicate ACTIVE $key',
      );
    }
    final retired = (await local.db.rawQuery(
      "SELECT remoteId FROM local_product_variants WHERE status='DELETED' OR isDeleted=1",
    )).map((r) => r['remoteId']).toSet();
    final activeQuery = await service.queryDocuments(
      collection: 'product_variants',
      filters: [const FirestoreFilter('productId', 'EQUAL', 'P')],
      idToken: token,
    );
    expect(
      activeQuery
          .map((d) => (d['name'] as String).split('/').last)
          .toSet()
          .intersection(retired),
      isEmpty,
      reason: 'Soft-retired rows excluded by local queries',
    );
    final products = await repository.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token,
    );
    expect(
      products
          .expand((p) => p.variants)
          .map((v) => v.variantId)
          .toSet()
          .intersection(retired),
      isEmpty,
      reason: 'Soft-retired rows excluded by product queries',
    );
  }

  Future<void> close() async {
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
    expect(remote.calls, 0, reason: 'Zero Firestore reads or writes');
  }
}

class _EditController extends EntryController {
  _EditController(this.fixture);
  final _Fixture fixture;
  ReclassificationPlan? lastPlan;
  int saves = 0;
  final resolved = <String, ResolvedProductTemplate>{};
  late ReclassificationPlan preparedPlan;
  Map<String, dynamic>? pendingFields;
  List<Map<String, dynamic>>? pendingVariants;
  Future<void> preload() async {
    for (final category in ['CA', 'CB']) {
      await loadProductMasters(categoryId: category);
    }
    preloaded = true;
    for (final id in ['SU', 'SAME', 'SAFE', 'DROP']) {
      resolved[id] = await fixture.repository.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: id,
        token: fixture.token,
      );
    }
  }

  bool preloaded = false;
  @override
  Future<void> loadProductMasters({String? categoryId}) async {
    if (preloaded) return;
    for (final type in ['BRAND', 'CATEGORY', 'SUBCATEGORY', 'UNIT']) {
      productMasterValues[type == 'SUBCATEGORY'
          ? 'SUBCATEGORY:$categoryId'
          : type] = await fixture.repository.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: type,
        token: fixture.token,
        categoryId: categoryId,
      );
    }
  }

  @override
  Future<ResolvedProductTemplate> resolveProductTemplate(String id) async =>
      resolved[id]!;
  @override
  Future<ReclassificationPlan?> computeReclassificationPlan({
    required String productId,
    required String newCategoryId,
    required String newSubcategoryId,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    expect(newCategoryId, preparedPlan.newCategoryId);
    expect(newSubcategoryId, preparedPlan.newSubcategoryId);
    expect(variants.map((v) => v['variantId']), ['V1', 'V2', 'V3']);
    return lastPlan = preparedPlan;
  }

  @override
  Future<bool> saveStructuredProductEdit({
    required String productId,
    required String name,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    saves++;
    pendingFields = productFields;
    pendingVariants = variants;
    return true;
  }
}

void main() {
  sqfliteFfiInit();
  late _Fixture f;
  setUp(() async {
    f = _Fixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });

  // WHEN predicates prove earlier SQL mutations/outbox writes have happened,
  // rather than accepting a validation error before the transaction started.
  final failures = <String, String>{
    'after Product update before Variant updates': '''
      AFTER UPDATE ON local_products WHEN NEW.remoteId='P'
        AND NEW.categoryId='CB' AND NEW.localRevision=1
    ''',
    'while updating a preserved Variant': '''
      AFTER UPDATE ON local_product_variants WHEN NEW.remoteId='V2'
        AND NEW.localRevision=1
        AND (SELECT localRevision FROM local_product_variants WHERE remoteId='V1')=1
        AND (SELECT COUNT(*) FROM sync_outbox WHERE entityType='products')=1
    ''',
    'while inserting a new Variant': '''
      AFTER INSERT ON local_product_variants WHEN NEW.remoteId NOT IN ('V1','V2','V3')
        AND (SELECT localRevision FROM local_product_variants WHERE remoteId='V2')=1
        AND (SELECT COUNT(*) FROM sync_outbox WHERE entityType='products')=1
    ''',
    'during retirement of a removed Variant': '''
      AFTER UPDATE ON local_product_variants WHEN NEW.remoteId='V3' AND NEW.status='DELETED'
        AND (SELECT COUNT(*) FROM local_product_variants)=4
        AND (SELECT localRevision FROM local_product_variants WHERE remoteId='V1')=1
    ''',
    'during sync_outbox enqueue after tombstone insertion': '''
      AFTER INSERT ON sync_outbox WHEN NEW.entityType='product_variants' AND NEW.documentId='V3'
        AND (SELECT status FROM local_product_variants WHERE remoteId='V3')='DELETED'
        AND (SELECT COUNT(*) FROM local_product_variants)=4
        AND (SELECT COUNT(*) FROM sync_outbox)>=6
    ''',
  };
  for (final failure in failures.entries) {
    test('atomic rollback ${failure.key}', () async {
      final before = await f.snapshot();
      await f.local.db.execute(
        '''CREATE TEMP TRIGGER phase7c_failure ${failure.value}
        BEGIN SELECT RAISE(ABORT, 'phase7c forced failure'); END''',
      );
      await expectLater(
        f.edit(f.mixed),
        throwsA(
          predicate(
            (e) =>
                e is DatabaseException &&
                e.toString().contains('phase7c forced failure'),
          ),
        ),
      );
      expect(
        await f.snapshot(),
        before,
        reason: 'Exact payload/metadata/sequence/outbox rollback',
      );
      expect(await f.local.db.query('sync_outbox'), isEmpty);
      expect((await f.doc('products', 'P'))['categoryId'], 'CA');
      expect((await f.doc('product_variants', 'V3'))['status'], 'ACTIVE');
      expect(await f.local.db.query('local_product_variants'), hasLength(3));
      await f.integrity();
    });
  }

  test('classification alone preserves productId, surviving variantId, SKU and barcode', () async {
    final before = {
      for (final id in ['V1', 'V2', 'V3'])
        id: await f.doc('product_variants', id),
    };
    await f.edit(f.unchanged);
    final product = await f.doc('products', 'P');
    expect(product['productId'], 'P');
    expect(product['categoryId'], 'CB');
    expect(product['subcategoryId'], 'SAFE');
    expect(await f.local.db.query('local_products'), hasLength(1));
    for (final id in before.keys) {
      final after = await f.doc('product_variants', id);
      for (final key in ['variantId', 'productId', 'sku', 'barcode']) {
        expect(after[key], before[id]![key], reason: '$id preserves $key');
      }
    }
    await f.integrity();
  });

  test('explicit SKU change updates the same variantId', () async {
    final incoming = f.unchanged;
    incoming.first['sku'] = 'CUSTOM-01';
    await f.edit(incoming);
    final updated = await f.doc('product_variants', 'V1');
    expect(updated['variantId'], 'V1');
    expect(updated['sku'], 'CUSTOM-01');
    expect(updated['barcode'], 'BC-V1');
    expect((await f.doc('product_variants', 'V2'))['sku'], 'SKU-0002');
    expect(await f.local.db.query('local_product_variants'), hasLength(3));
    await f.integrity();
  });

  test(
    'explicit SKU cannot collide with a preserved sibling whose SKU is omitted',
    () async {
      final before = await f.snapshot();
      final incoming = f.unchanged;
      incoming.first['sku'] = 'sku-0002';
      await expectLater(f.edit(incoming), throwsA(isA<AppException>()));
      expect(await f.snapshot(), before);
      await f.integrity();
    },
  );

  test('generated SKU collision aborts rather than introducing an ACTIVE duplicate', () async {
    await f.seed('product_variants', 'V2', {
      ...await f.doc('product_variants', 'V2'),
      'sku': 'SKU-0004',
    }, system: false);
    final before = await f.snapshot();
    await expectLater(
      f.edit([...f.unchanged, f.variant(null)]),
      throwsA(isA<AppException>()),
    );
    expect(await f.snapshot(), before);
    await f.integrity();
  });

  test(
    'duplicate ACTIVE barcode edit rejects without any local writes',
    () async {
      final before = await f.snapshot();
      final incoming = f.unchanged;
      incoming.first['barcode'] = 'BC-V2';
      await expectLater(f.edit(incoming), throwsA(isA<AppException>()));
      expect(await f.snapshot(), before);
      await f.integrity();
    },
  );

  test(
    'computed destructive plan is read-only and assigns no new IDs',
    () async {
      final before = await f.snapshot();
      final incoming = f.mixed;
      final plan = await f.repository.computeReclassificationPlan(
        tenantId: 'T',
        businessId: 'B',
        productId: 'P',
        newCategoryId: 'CB',
        newSubcategoryId: 'SAFE',
        productFields: f.fields(),
        variants: incoming,
        token: f.token,
      );
      expect(plan.classificationChanged, true);
      expect(plan.isDestructive, true);
      expect(plan.retiredVariantIds, ['V3']);
      expect(plan.preservedVariantIds, ['V1', 'V2']);
      expect(plan.newVariantCount, 1);
      expect(incoming.last.containsKey('variantId'), false);
      expect(await f.snapshot(), before);
      await f.integrity();
    },
  );

  for (final cleared in <String?>['', null]) {
    test(
      'explicit barcode removal ($cleared) updates the same variantId',
      () async {
        final incoming = f.unchanged;
        incoming.first['barcode'] = cleared;
        await f.edit(incoming);
        final updated = await f.doc('product_variants', 'V1');
        expect(updated['variantId'], 'V1');
        expect(updated['barcode'], cleared);
        expect(updated['sku'], 'SKU-0001');
        expect(await f.local.db.query('local_product_variants'), hasLength(3));
        await f.integrity();
      },
    );
  }

  test('new variant gets a new ID while all existing IDs survive', () async {
    await f.edit([...f.unchanged, f.variant(null)]);
    final rows = await f.local.db.query('local_product_variants');
    final ids = rows.map((r) => r['remoteId']).toSet();
    expect(ids, containsAll(['V1', 'V2', 'V3']));
    expect(ids.difference({'V1', 'V2', 'V3'}), hasLength(1));
    final id = ids.difference({'V1', 'V2', 'V3'}).single as String;
    expect((await f.doc('product_variants', id))['variantId'], id);
    expect((await f.doc('product_variants', id))['sku'], 'SKU-0004');
    await f.integrity();
  });

  test('retired ID is never reassigned to unrelated new variants across later edits', () async {
    await f.edit(f.mixed);
    final retired = await f.local.row('product_variants', 'V3');
    expect(retired!['status'], 'DELETED');
    await f.integrity();
    expect(retired['isDeleted'], 1);
    final tombstones = await f.local.db.query(
      'sync_outbox',
      where: 'documentId=?',
      whereArgs: ['V3'],
    );
    final write = jsonDecode(tombstones.single['payloadJson'] as String) as Map;
    expect(write['operation'], 'UPDATE');
    final patch = FirestoreRestService.decodeFields(write['fields']);
    expect(patch['status'], 'DELETED');
    expect(patch['isDeleted'], true);
    await f.integrity();
    final active = await f.service.queryDocuments(
      collection: 'product_variants',
      filters: [const FirestoreFilter('productId', 'EQUAL', 'P')],
      idToken: f.token,
    );
    final preservedIds = active
        .map((d) => (d['name'] as String).split('/').last)
        .toSet();
    await f.edit([
      for (final d in active) FirestoreRestService.decodeFields(d['fields']),
      f.variant(null, barcode: 'BC-LATER'),
    ]);
    final ids = (await f.local.db.query('local_product_variants'))
        .map((r) => r['remoteId'])
        .toSet();
    expect(ids, containsAll(preservedIds));
    expect(ids.difference({...preservedIds, 'V3'}), hasLength(1));
    expect(await f.local.row('product_variants', 'V3'), retired);
    await f.integrity();
  });

  test(
    'explicit attempt to reuse a retired variant ID is rejected atomically',
    () async {
      await f.edit(f.mixed);
      await f.integrity();
      final before = await f.snapshot();
      await expectLater(
        f.edit([
          f.variant('V1'),
          f.variant('V2'),
          f.variant('V3', barcode: 'UNRELATED'),
        ]),
        throwsA(isA<AppException>()),
      );
      expect(await f.snapshot(), before);
      await f.integrity();
    },
  );

  for (final scenario in ['cancel', 'category', 'subcategory']) {
    final destructive = scenario == 'cancel';
    final category = scenario == 'subcategory' ? 'CA' : 'CB';
    final subcategory = destructive
        ? 'DROP'
        : scenario == 'subcategory'
        ? 'SAME'
        : 'SAFE';
    testWidgets(
      destructive
          ? 'destructive plan requires confirmation; Cancel causes zero Product, Variant and outbox writes'
          : 'non-destructive $scenario reclassification saves without unnecessary confirmation',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 2600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _EditController(f);
        addTearDown(controller.dispose);
        await tester.runAsync(() async {
          await controller.preload();
          controller.preparedPlan = await f.repository
              .computeReclassificationPlan(
                tenantId: 'T',
                businessId: 'B',
                productId: 'P',
                newCategoryId: category,
                newSubcategoryId: subcategory,
                productFields: f.fields(
                  subcategory: subcategory,
                  category: category,
                ),
                variants: f.unchanged,
                token: f.token,
              );
          controller.products.addAll(
            await f.repository.getProducts(
              tenantId: 'T',
              businessId: 'B',
              token: f.token,
            ),
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(0.9)),
              child: child!,
            ),
            home: Scaffold(body: ProductManagementPage(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PopupMenuButton<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit Product / Manage Variants'));
        await tester.pumpAndSettle();
        Future<void> pick(String label, String value) async {
          await tester.ensureVisible(field(label));
          await tester.enterText(field(label), value);
          await tester.pumpAndSettle();
          await tester.tap(find.text(value).last);
          await tester.pumpAndSettle();
        }

        if (category != 'CA') await pick('Category', category);
        await pick('Subcategory', subcategory);
        late Map<String, Object> before;
        late int changes;
        await tester.runAsync(() async {
          before = await f.snapshot();
          changes =
              (await f.local.db.rawQuery('SELECT total_changes() n'))
                      .single['n']
                  as int;
        });
        await tester.tap(find.text('Save Product'));
        // The saving spinner stays animated behind the confirmation dialog.
        await tester.pump(const Duration(milliseconds: 300));
        if (!destructive) await tester.pumpAndSettle();
        expect(controller.lastPlan, isNotNull);
        expect(controller.lastPlan!.classificationChanged, true);
        expect(controller.lastPlan!.isDestructive, destructive);
        if (destructive) {
          expect(find.text('Confirm Reclassification Impact'), findsOneWidget);
          expect(controller.saves, 0);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
          expect(find.text('Confirm Reclassification Impact'), findsNothing);
          expect(controller.saves, 0);
          await tester.runAsync(() async {
            expect(await f.snapshot(), before);
            expect(
              (await f.local.db.rawQuery('SELECT total_changes() n'))
                  .single['n'],
              changes,
            );
            expect(await f.local.db.query('sync_outbox'), isEmpty);
            await f.integrity();
          });
        } else {
          expect(find.text('Confirm Reclassification Impact'), findsNothing);
          expect(controller.saves, 1);
          await tester.runAsync(() async {
            await f.edit(
              controller.pendingVariants!,
              productFields: controller.pendingFields,
            );
            expect(
              (await f.doc('products', 'P'))['subcategoryId'],
              subcategory,
            );
            expect((await f.doc('products', 'P'))['productId'], 'P');
            for (final id in ['V1', 'V2', 'V3']) {
              final variant = await f.doc('product_variants', id);
              expect(variant['variantId'], id);
              expect(variant['barcode'], 'BC-$id');
              expect(variant['sku'], 'SKU-000${id.substring(1)}');
            }
            expect(await f.local.db.query('sync_outbox'), isNotEmpty);
            await f.integrity();
          });
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
