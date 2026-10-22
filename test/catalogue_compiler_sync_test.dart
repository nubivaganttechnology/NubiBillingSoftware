import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/data/sync/sync_query_registry.dart';

import 'support/catalogue_import_fixture.dart';
import 'offline_sync_test.dart'
    show FakeRemote, TestConnectivity, session, token;

typedef Catalogue = Map<String, List<Map<String, dynamic>>>;

Map<String, dynamic> fields(Map<String, dynamic> doc) =>
    FirestoreRestService.decodeFields(doc['fields']);
Map<String, dynamic> doc(
  String collection,
  String id,
  Map<String, dynamic> f,
) => {
  'name': '$collection/$id',
  'fields': FirestoreRestService.encodeFields(f),
};
Catalogue fixture({bool archived = false}) {
  final raw = catalogueImportFixture(archived: archived);
  return {
    for (final e in raw.entries)
      e.key: [
        for (final r in e.value as List)
          doc(
            e.key,
            r['id'] as String,
            Map<String, dynamic>.from(r)..remove('id'),
          ),
      ],
  };
}

Catalogue clone(Catalogue c) => {
  for (final e in c.entries)
    e.key: [
      for (final d in e.value)
        Map<String, dynamic>.from(jsonDecode(jsonEncode(d)) as Map),
    ],
};
void edit(Map<String, dynamic> d, Map<String, dynamic> change) {
  d['fields'] = FirestoreRestService.encodeFields({...fields(d), ...change});
}

class CountingRemote extends FakeRemote {
  final collections = <String>[];
  final cursors = <String?>[];
  String? failCollection;
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
    collections.add(collection);
    cursors.add(cursor);
    if (collection == failCollection) {
      throw const AppException('Forced pull failure', code: 'network');
    }
    return super.readSyncPage(
      collection: collection,
      filters: filters,
      queryId: queryId,
      reason: reason,
      cursor: cursor,
      readTime: readTime,
      after: after,
      pageSize: pageSize,
      idToken: idToken,
    );
  }

  void catalogue(Catalogue data) {
    for (final e in data.entries) {
      for (final d in e.value) {
        seed(e.key, (d['name'] as String).split('/').last, fields(d));
      }
    }
  }
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late LocalDataSource local;
  late CountingRemote remote;
  late TestConnectivity connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('phase9-catalogue-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    remote = CountingRemote();
    connectivity = TestConnectivity()..available = false;
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    await service.setScope(tenant: 'T', business: 'B');
    local = LocalDataSource(await database.open('', 'U'));
  });
  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });
  Future<void> import(
    Catalogue input, {
    Future<void> Function(String, DatabaseExecutor)? probe,
  }) {
    final documents = clone(input);
    final release = documents['product_catalogue_releases']!.single;
    final releaseFields = fields(release);
    if ((releaseFields['catalogueVersion'] ?? releaseFields['version']) == 4) {
      edit(release, {
        'version': 4,
        'catalogueVersion': 4,
        'isolatedOnly': false,
        'approvedForLiveExecution': true,
        'productionMigrationApproved': true,
        'firestorePublicationApproved': true,
      });
      final approvedFields = fields(release);
      approvedFields.remove('contentFingerprint');
      release['fields'] = FirestoreRestService.encodeFields(approvedFields);
    }
    return SystemCatalogueSnapshot.import(
      source: local,
      documents: documents,
      readTimes: {},
      failureProbe: probe,
    );
  }

  Future<Map<String, dynamic>> state() async => {
    for (final c in SystemCatalogueMetadata.collections)
      c: await local.db.query(LocalDataSource.table(c), orderBy: 'remoteId'),
    'outbox': await local.db.query('sync_outbox', orderBy: 'id'),
    'queries': await local.db.query('sync_queries', orderBy: 'queryKey'),
  };
  Catalogue next(Catalogue input) {
    final c = clone(SystemCatalogueMetadata.compile(input));
    edit(c['product_catalogue_releases']!.single, {
      'version': 4,
      'catalogueVersion': 4,
      'isolatedOnly': false,
      'approvedForLiveExecution': true,
      'productionMigrationApproved': true,
      'firestorePublicationApproved': true,
    });
    final release = c['product_catalogue_releases']!.single;
    final releaseFields = fields(release)..remove('contentFingerprint');
    release['fields'] = FirestoreRestService.encodeFields(releaseFields);
    return c;
  }

  test(
    'compiler identical input is pure and generates identical IDs/payloads',
    () {
      final input = fixture(), before = jsonEncode(fixture());
      final a = SystemCatalogueMetadata.compile(input),
          b = SystemCatalogueMetadata.compile(input);
      expect(a, b);
      expect(jsonEncode(input), before);
      expect(SystemCatalogueMetadata.compile(a), a);
      expect(
        CatalogueContract.fingerprint(a),
        CatalogueContract.fingerprint(b),
      );
    },
  );
  test('compiler input document order does not affect output', () {
    final input = fixture(),
        reversed = {
          for (final e in input.entries.toList().reversed)
            e.key: e.value.reversed.toList(),
        };
    expect(
      SystemCatalogueMetadata.compile(input),
      SystemCatalogueMetadata.compile(reversed),
    );
  });
  test('logical fingerprint ignores timestamps and document order but detects defaults', () {
    final a = SystemCatalogueMetadata.compile(fixture()), b = clone(a);
    for (final e in b.values) {
      e.shuffle();
      for (final d in e) {
        edit(d, {
          'updatedAt': DateTime.utc(2040),
          'createdAt': DateTime.utc(2030),
        });
      }
    }
    expect(CatalogueContract.fingerprint(a), CatalogueContract.fingerprint(b));
    final row = b['subcategory_attribute_templates']!.firstWhere(
      (d) =>
          fields(d)['attributeId'] == 'unit' && fields(d)['status'] == 'ACTIVE',
    );
    edit(row, {'defaultValue': 'TEST_CHANGED'});
    expect(
      CatalogueContract.fingerprint(a),
      isNot(CatalogueContract.fingerprint(b)),
    );
  });
  test('all current Metal & Wood Enamels IDs use explicit enamel profiles; Satin avoids Wood/Clear/PU defaults', () async {
    final input = fixture();
    const ids = [
      'EPOXY_ENAMELS',
      'METALLIC_FINISHES',
      'PU_ENAMELS',
      'SATIN_ENAMELS',
      'SYNTHETIC_ENAMELS',
    ];
    for (final suffix in ids) {
      final id = 'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_$suffix';
      input['product_subcategories']!.add(
        doc('product_subcategories', id, {
          'subcategoryId': id,
          'categoryId': 'SYS_CATEGORY_METAL_WOOD_ENAMELS',
          'scopeType': 'SYSTEM',
          'catalogueId': 'PAINT_V1',
          'status': 'ACTIVE',
          'name': suffix,
        }),
      );
    }
    await import(input);
    final subs = await local.query('product_subcategories', [
      const FirestoreFilter(
        'categoryId',
        'EQUAL',
        'SYS_CATEGORY_METAL_WOOD_ENAMELS',
      ),
      const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
    ]);
    expect(subs, hasLength(8));
    for (final s in subs) {
      final satin =
          fields(s)['subcategoryId'] ==
          'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS';
      expect(fields(s)['profileId'], satin ? 'SATIN_ENAMEL' : 'ENAMEL');
      final resolved = await ProductTemplateResolver(service).resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: fields(s)['subcategoryId'] as String,
        token: token('U'),
      );
      final all = resolved.allAttributes;
      expect(
        all.singleWhere((a) => a.attributeId == 'finish').defaultValue,
        satin ? 'Satin' : 'Gloss',
      );
      expect(all.singleWhere((a) => a.attributeId == 'surface').defaultValue, [
        'Metal',
        'Wood',
      ]);
      expect(
        all.singleWhere((a) => a.attributeId == 'colourMode').defaultValue,
        'Multiple Ready Colours',
      );
      expect(
        all.singleWhere((a) => a.attributeId == 'dilutionType').defaultValue,
        'Mineral Turpentine / MTO',
      );
    }
    expect(remote.queries + remote.reads, 0);
  });
  test('display formatting cannot change profile or generated IDs', () {
    final a = fixture(), b = fixture();
    for (final d in b['product_categories']!) {
      edit(d, {'name': 'WRONG Wood display ${fields(d)['name']}'});
    }
    for (final d in b['product_subcategories']!) {
      edit(d, {'name': 'Arbitrary display'});
    }
    for (final d in b['product_attribute_options']!) {
      final name = fields(d)['name'] as String;
      if (SystemCatalogueMetadata.controlledOptions.containsKey(
        fields(d)['attributeId'],
      )) {
        edit(d, {'name': '  ${name.toLowerCase().replaceAll(' ', '   ')}  '});
      }
    }
    for (final d in b['units']!) {
      edit(d, {'name': '  ${(fields(d)['name'] as String).toLowerCase()}  '});
    }
    final x = SystemCatalogueMetadata.compile(a),
        y = SystemCatalogueMetadata.compile(b);
    for (final c in x.keys) {
      expect(
        x[c]!.map((d) => d['name']).toList(),
        y[c]!.map((d) => d['name']).toList(),
      );
    }
  });
  test(
    'document ID equals canonical payload ID in every compiler collection',
    () {
      final compiled = SystemCatalogueMetadata.compile(fixture());
      for (final e in compiled.entries) {
        for (final d in e.value) {
          expect(
            (d['name'] as String).split('/').last,
            fields(d)[CatalogueContract.idFields[e.key]],
          );
        }
      }
    },
  );
  test('document/payload mismatch fails before mutation', () async {
    final input = fixture();
    edit(input['product_categories']!.first, {'categoryId': 'DIFFERENT'});
    final before = await state();
    await expectLater(
      import(input),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'catalogue-identity'),
      ),
    );
    expect(await state(), before);
  });
  test(
    'unknown and conflicting profiles fail with diagnostic rather than guess',
    () {
      expect(
        () => SystemCatalogueMetadata.profileFor('UNKNOWN', 'UNKNOWN'),
        throwsA(isA<AppException>()),
      );
      expect(
        () => SystemCatalogueMetadata.profileFor(
          'SYS_CATEGORY_METAL_WOOD_ENAMELS',
          'SATIN',
          explicit: 'WOOD_FINISH',
        ),
        throwsA(isA<AppException>()),
      );
      final input = fixture();
      edit(
        input['product_subcategories']!.firstWhere(
          (d) => fields(d)['status'] == 'ACTIVE',
        ),
        {'profileId': 'UNKNOWN'},
      );
      expect(
        () => SystemCatalogueMetadata.compile(input),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            'catalogue-profile',
          ),
        ),
      );
    },
  );
  test('Ceiling and Basement compile current IDs without attaching old orphan groups', () {
    final input = fixture();
    for (final pair in {
      'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS':
          'SYS_CATEGORY_INTERIOR_WALL_COATINGS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING':
          'SYS_CATEGORY_WATERPROOFING',
    }.entries) {
      input['product_subcategories']!.add(
        doc('product_subcategories', pair.key, {
          'subcategoryId': pair.key,
          'categoryId': pair.value,
          'scopeType': 'SYSTEM',
          'catalogueId': 'PAINT_V1',
          'status': 'ACTIVE',
          'name': pair.key,
        }),
      );
    }
    final c = SystemCatalogueMetadata.compile(input);
    for (final old in [
      'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS',
      'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT',
    ]) {
      expect(
        c['product_subcategories']!.any(
          (d) => fields(d)['subcategoryId'] == old,
        ),
        false,
      );
      expect(
        c['subcategory_attribute_templates']!.any(
          (d) => fields(d)['subcategoryId'] == old,
        ),
        false,
      );
    }
  });
  test('archived malformed v3 option duplicates fail safely without alias migration', () async {
    final before = await state();
    await expectLater(
      import(fixture(archived: true)),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          'catalogue-collision',
        ),
      ),
    );
    expect(await state(), before);
  });
  test('first import succeeds; identical second import has exact same database state', () async {
    await import(fixture());
    final a = await state();
    await import(fixture());
    expect(await state(), a);
    final marker = fields(
      (await local.query('product_catalogue_releases', [])).single,
    );
    expect(marker['installed'], true);
    expect(marker['schemaRevision'], 1);
    expect(marker['compilerRevision'], CatalogueContract.compilerRevision);
    expect(marker['catalogueVersion'], 3);
    expect(marker['contentFingerprint'], isNotEmpty);
  });
  for (final collection in [
    'product_categories',
    'product_subcategories',
    'subcategory_attribute_templates',
    'product_attribute_options',
  ]) {
    test(
      'duplicate $collection rejected without creating parallel records',
      () async {
        final input = fixture(), entry = input[collection]!.first;
        input[collection]!.add(Map<String, dynamic>.from(entry));
        final before = await state();
        await expectLater(import(input), throwsA(isA<AppException>()));
        expect(await state(), before);
      },
    );
  }
  test('same-name active record under same parent rejects name-based ID reassignment', () async {
    final input = fixture(),
        base = input['product_subcategories']!.firstWhere(
          (d) => fields(d)['status'] == 'ACTIVE',
        );
    final f = {...fields(base), 'subcategoryId': 'PARALLEL_ID'};
    input['product_subcategories']!.add(
      doc('product_subcategories', 'PARALLEL_ID', f),
    );
    await expectLater(
      import(input),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          'catalogue-collision',
        ),
      ),
    );
    expect(await local.row('product_subcategories', 'PARALLEL_ID'), isNull);
  });
  test('BUSINESS category, corrected option, override and outbox survive SYSTEM import', () async {
    for (final entry in {
      'product_categories': 'CUSTOM_CAT',
      'product_attribute_options': 'CUSTOM_OPTION',
      'subcategory_attribute_templates': 'CUSTOM_TEMPLATE',
    }.entries) {
      await service.createDocument(entry.key, entry.value, {
        'scopeType': 'BUSINESS',
        'tenantId': 'T',
        'businessId': 'B',
        'name': 'Interior Wall Coatings',
        'status': 'ACTIVE',
        if (entry.key == 'product_attribute_options') ...{
          'optionId': entry.value,
          'attributeId': 'colourFamily',
        },
        if (entry.key == 'subcategory_attribute_templates') ...{
          'templateId': entry.value,
          'attributeId': 'finish',
          'defaultValue': 'Satin',
        },
      }, idToken: token('U'));
    }
    final before = {
      for (final c in [
        'product_categories',
        'product_attribute_options',
        'subcategory_attribute_templates',
      ])
        c: await local.db.query(
          LocalDataSource.table(c),
          where: "scopeType='BUSINESS'",
        ),
    };
    final outbox = await local.db.query('sync_outbox');
    await import(fixture());
    await import(fixture());
    for (final c in before.keys) {
      expect(
        await local.db.query(
          LocalDataSource.table(c),
          where: "scopeType='BUSINESS'",
        ),
        before[c],
      );
    }
    expect(await local.db.query('sync_outbox'), outbox);
  });
  test('SYSTEM/BUSINESS same document ID collision fails atomically', () async {
    final input = fixture(),
        id = (input['product_categories']!.first['name'] as String)
            .split('/')
            .last;
    await service.createDocument('product_categories', id, {
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
    }, idToken: token('U'));
    final before = await state();
    await expectLater(import(input), throwsA(isA<AppException>()));
    expect(await state(), before);
  });
  for (final stage in [
    'product_attributes',
    'before_release_marker',
    'after_release_marker',
  ]) {
    test(
      'forced import failure at $stage preserves prior rows, release, cursors and outbox',
      () async {
        await import(fixture());
        final before = await state(), newer = next(fixture());
        var fired = false;
        await expectLater(
          import(
            newer,
            probe: (s, tx) async {
              if (s == stage) {
                fired = true;
                final marker = await tx.query(
                  LocalDataSource.table('product_catalogue_releases'),
                );
                expect(
                  fields(
                    LocalDataSource.document(
                      marker.single,
                      'product_catalogue_releases',
                    ),
                  )['catalogueVersion'],
                  stage == 'after_release_marker' ? 4 : 3,
                );
                throw const AppException('Forced mid-transaction failure');
              }
            },
          ),
          throwsA(isA<AppException>()),
        );
        expect(fired, true);
        expect(await state(), before);
      },
    );
  }
  test('older compiler and unsupported schema cannot overwrite installed newer state', () async {
    await import(fixture());
    final before = await state();
    for (final change in [
      {'compilerRevision': 1},
      {'compilerRevision': 999},
      {'schemaRevision': 999},
    ]) {
      final input = next(fixture());
      edit(input['product_catalogue_releases']!.single, change);
      await expectLater(import(input), throwsA(isA<AppException>()));
      expect(await state(), before);
    }
  });
  test('same release with changed defaults is rejected; corrected explicit newer release remains unchanged', () async {
    final compiled = SystemCatalogueMetadata.compile(fixture());
    await import(compiled);
    final changed = clone(compiled),
        row = changed['subcategory_attribute_templates']!.firstWhere(
          (d) =>
              fields(d)['attributeId'] == 'numberOfCoats' &&
              fields(d)['status'] == 'ACTIVE',
        );
    edit(row, {'defaultValue': '3 Coats'});
    final before = await state();
    await expectLater(import(changed), throwsA(isA<AppException>()));
    expect(await state(), before);
    edit(changed['product_catalogue_releases']!.single, {
      'catalogueVersion': 4,
    });
    await import(changed);
    expect(
      fields(
        (await local.query('subcategory_attribute_templates', [
          FirestoreFilter('templateId', 'EQUAL', fields(row)['templateId']),
        ])).single,
      )['defaultValue'],
      '3 Coats',
    );
  });
  test('full isolated catalogue resolves with zero PRODUCT/VARIANT placement intersections and no active orphan groups', () async {
    await import(fixture());
    final subs = await local.query('product_subcategories', [
      const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
    ]);
    final allIds = subs.map((d) => fields(d)['subcategoryId']).toSet();
    for (final s in subs) {
      final result = await ProductTemplateResolver(service).resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: fields(s)['subcategoryId'] as String,
        token: token('U'),
      );
      expect(
        result.productAttributes
            .map((a) => a.attributeId)
            .toSet()
            .intersection(
              result.variantAttributes.map((a) => a.attributeId).toSet(),
            ),
        isEmpty,
      );
      expect(result.allAttributes, isNotEmpty);
    }
    for (final t in await local.query('subcategory_attribute_templates', [
      const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
    ])) {
      expect(allIds.contains(fields(t)['subcategoryId']), true);
    }
    expect(remote.queries + remote.reads, 0);
  });

  test('unchanged release makes zero full catalogue pulls and survives engine restart', () async {
    remote.catalogue(fixture());
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNull);
    final before = remote.collections.length;
    await sync.checkCatalogue(forceCheck: true);
    expect(remote.collections.skip(before).toList(), [
      'product_catalogue_releases',
    ]);
    sync.dispose();
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    sync.attach(local, 'U');
    final again = remote.collections.length;
    await sync.checkCatalogue(forceCheck: true);
    expect(remote.collections.skip(again).toList(), [
      'product_catalogue_releases',
    ]);
    expect(remote.commits, 0);
  });
  test(
    'newer release triggers required pull and installs only after success',
    () async {
      remote.catalogue(fixture());
      connectivity.available = true;
      await sync.checkCatalogue(forceCheck: true);
      remote.catalogue(next(fixture()));
      final before = remote.collections.length;
      await sync.checkCatalogue(forceCheck: true);
      expect(sync.error, isNull);
      expect(
        remote.collections.skip(before),
        contains('subcategory_attribute_templates'),
      );
      expect(
        fields(
          (await local.query('product_catalogue_releases', [])).single,
        )['catalogueVersion'],
        4,
      );
      expect(remote.commits, 0);
    },
  );
  test('failed release pull leaves installed marker and all catalogue cursors unchanged', () async {
    remote.catalogue(fixture());
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    remote.catalogue(next(fixture()));
    final before = await state();
    remote.failCollection = 'subcategory_attribute_templates';
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNotNull);
    final after = await state();
    for (final c in SystemCatalogueMetadata.collections) {
      expect(after[c], before[c]);
    }
    final a = (after['queries'] as List).cast<Map>(),
        b = (before['queries'] as List).cast<Map>();
    for (var i = 0; i < a.length; i++) {
      expect(a[i]['cursor'], b[i]['cursor']);
      expect(a[i]['catalogueVersion'], b[i]['catalogueVersion']);
    }
  });
  test(
    'quota cooldown serves SQLite and blocks repeated remote checks',
    () async {
      await import(fixture());
      connectivity.available = true;
      remote.quota = true;
      await sync.checkCatalogue(forceCheck: true);
      final before = remote.queries + remote.reads;
      for (var i = 0; i < 5; i++) {
        await sync.checkCatalogue(forceCheck: true);
      }
      expect(remote.queries + remote.reads, before);
      expect(
        await local.query('product_categories', [
          const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
        ]),
        isNotEmpty,
      );
      final control = (await local.db.query('sync_control')).single;
      expect(
        DateTime.parse(control['cooldownUntil'] as String)
            .difference(DateTime.now().toUtc())
            .inMinutes,
        greaterThanOrEqualTo(59),
      );
      expect(remote.commits, 0);
    },
  );
  test('catalogue-only check never pushes Product outbox and outbox-only push never pulls catalogue', () async {
    await service.createDocument('products', 'LOCAL', {
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
    }, idToken: token('U'));
    remote.catalogue(fixture());
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    expect(remote.commits, 0);
    expect(await local.db.query('sync_outbox'), hasLength(1));
    final before = remote.collections.length;
    await sync.sync(pull: false);
    expect(remote.commits, 1);
    expect(remote.collections.length, before);
  });
  test('Product form metadata and repeated field-dependent reads make zero Firestore reads or query registrations', () async {
    await import(fixture());
    sync.beginScopeChange();
    connectivity.available = true;
    final before = await local.db.query('sync_queries');
    final resolver = ProductTemplateResolver(service);
    for (var i = 0; i < 5; i++) {
      final template = await resolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: 'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS',
        token: token('U'),
      );
      expect(template.allAttributes, isNotEmpty);
    }
    expect(remote.queries + remote.reads, 0);
    expect(await local.db.query('sync_queries'), before);
  });
  test('equivalent query specs dedupe despite field/filter/key ordering and duplicate filters', () async {
    final filters = OfflineFirestoreService.encodeFilters([
      const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
      const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
    ]);
    final a = {'filters': filters},
        b = {
          'filters': [...filters.reversed, filters.first],
        };
    expect(
      SyncQueryRegistry.key('brands', a),
      SyncQueryRegistry.key('brands', b),
    );
    await local.db.transaction((tx) async {
      for (var i = 0; i < 10; i++) {
        await SyncQueryRegistry.upsert(tx, 'brands', i.isEven ? a : b);
      }
    });
    final matches = await local.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: [SyncQueryRegistry.key('brands', a)],
    );
    expect(matches, hasLength(1));
  });
  test('isolated registry reconciliation preserves legacy specs and conservatively dedupes cursors', () async {
    final filter = OfflineFirestoreService.encodeFilters([
      const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
    ]);
    final broad = {'filters': filter};
    for (final pair in {
      'DUP_A': '2020-01-01T00:00:00Z',
      'DUP_B': '2021-01-01T00:00:00Z',
    }.entries) {
      await local.db.insert('sync_queries', {
        'queryKey': pair.key,
        'collectionName': 'brands',
        'queryJson': jsonEncode(broad),
        'active': 1,
        'cursor': pair.value,
        'lastSyncedAt': pair.value,
      });
    }
    const oldId = 'SYS_CATEGORY_EXTERIOR_WALL_PAINTS';
    final legacy = {
      'filters': OfflineFirestoreService.encodeFilters([
        const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        const FirestoreFilter('categoryId', 'EQUAL', oldId),
      ]),
    };
    await local.db.insert('sync_queries', {
      'queryKey': 'PROTECTED',
      'collectionName': 'product_subcategories',
      'queryJson': jsonEncode(legacy),
      'active': 1,
    });
    final protected = await local.db.query(
      'sync_queries',
      where: "queryKey='PROTECTED'",
    );
    await local.db.transaction(
      (tx) =>
          SyncQueryRegistry.reconcile(tx, SystemCatalogueMetadata.collections),
    );
    expect(
      await local.db.query('sync_queries', where: "queryKey='PROTECTED'"),
      protected,
    );
    final findings = await SyncQueryRegistry.auditLegacy(local.db);
    expect(findings.single['legacyIds'], [oldId]);
    final row = (await local.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: [SyncQueryRegistry.key('brands', broad)],
    )).single;
    // An uninitialized pre-existing broad query is the conservative baseline.
    expect(row['cursor'], isNull);
    expect(
      await local.db.query(
        'sync_queries',
        where: "queryKey IN ('DUP_A','DUP_B')",
      ),
      isEmpty,
    );
    await expectLater(
      local.db.transaction(
        (tx) => SyncQueryRegistry.upsert(tx, 'product_subcategories', legacy),
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('stable collection revisions fetch only changed collections; failed changes leave revisions/cursors intact', () async {
    final initial = SystemCatalogueMetadata.compile(fixture());
    final revisions = {
      for (final c in CatalogueContract.requiredCollections) c: 1,
      'brands': 1,
    };
    edit(initial['product_catalogue_releases']!.single, {
      'collectionRevisions': revisions,
    });
    remote.catalogue(initial);
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNull);
    final changed = clone(initial);
    edit(changed['product_catalogue_releases']!.single, {
      'version': 4,
      'catalogueVersion': 4,
      'isolatedOnly': false,
      'approvedForLiveExecution': true,
      'productionMigrationApproved': true,
      'firestorePublicationApproved': true,
      'collectionRevisions': {...revisions, 'product_attribute_options': 2},
    });
    final option = changed['product_attribute_options']!.firstWhere(
      (d) => fields(d)['status'] == 'ACTIVE',
    );
    edit(option, {'sortOrder': 123});
    remote.catalogue(changed);
    final before = remote.collections.length;
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNull);
    expect(remote.collections.skip(before).toList(), [
      'product_catalogue_releases',
      'product_attribute_options',
    ]);
    expect(
      fields(
        (await local.query('product_catalogue_releases', [])).single,
      )['catalogueVersion'],
      4,
    );
    final marker = fields(
      (await local.query('product_catalogue_releases', [])).single,
    );
    expect(
      (marker['collectionRevisions'] as Map)['product_attribute_options'],
      2,
    );
    final failed = clone(changed);
    edit(failed['product_catalogue_releases']!.single, {
      'version': 5,
      'catalogueVersion': 5,
      'collectionRevisions': {...revisions, 'product_attribute_options': 3},
    });
    remote.catalogue(failed);
    final snapshot = await state();
    remote.failCollection = 'product_attribute_options';
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNotNull);
    final after = await state();
    for (final c in SystemCatalogueMetadata.collections) {
      expect(after[c], snapshot[c]);
    }
    for (final q in (after['queries'] as List).cast<Map>()) {
      final old = (snapshot['queries'] as List).cast<Map>().singleWhere(
        (r) => r['queryKey'] == q['queryKey'],
      );
      expect(q['cursor'], old['cursor']);
      expect(q['catalogueVersion'], old['catalogueVersion']);
    }
  });
  test('automatic catalogue checks use durable freshness; manual check still does no unchanged full pull', () async {
    remote.catalogue(fixture());
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    final before = remote.collections.length;
    sync.schedule(pull: true, reason: 'SCOPE_CHANGE');
    await sync.sync(pull: false, push: false, catalogueOnly: true);
    expect(remote.collections.length, before);
    await sync.checkCatalogue(forceCheck: true);
    expect(remote.collections.skip(before).toList(), [
      'product_catalogue_releases',
    ]);
  });
  test('RESOURCE_EXHAUSTED with opaque message persists quota backoff that manual refresh cannot bypass', () async {
    await import(fixture());
    sync.beginScopeChange();
    connectivity.available = true;
    await sync.recordRemoteFailure(
      local,
      const AppException(
        'Request cannot be served.',
        code: 'resource-exhausted',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await sync.checkCatalogue(forceCheck: true);
    }
    expect(remote.queries + remote.reads, 0);
    final control = (await local.db.query('sync_control')).single;
    expect(control['failureCount'], 1);
    expect(
      DateTime.parse(control['cooldownUntil'] as String)
          .difference(DateTime.now().toUtc())
          .inMinutes,
      greaterThanOrEqualTo(59),
    );
    await sync.recordRemoteFailure(
      local,
      const AppException(
        'Request cannot be served.',
        code: 'RESOURCE_EXHAUSTED',
      ),
    );
    expect(
      DateTime.parse(
        (await local.db.query('sync_control')).single['cooldownUntil']
            as String,
      ).difference(DateTime.now().toUtc()).inMinutes,
      greaterThanOrEqualTo(119),
    );
  });
  test('legacy admin unversioned apply cannot make Firestore writes', () async {
    final result = await Process.run('python3', [
      '-B',
      'tool/repair_brush_catalogue.py',
      '--database',
      'NONEXISTENT',
      '--apply',
    ]);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('Legacy unversioned --apply is disabled'));
    expect(result.stdout, isEmpty);
  });
  test('explicit isolated registry cleanup deactivates safely covered queries without deleting specifications', () async {
    await local.db.update(
      'sync_queries',
      {'lastSyncedAt': '2020-01-01T00:00:00Z'},
      where: 'collectionName=?',
      whereArgs: ['brands'],
    );
    final spec = {
      'filters': OfflineFirestoreService.encodeFilters([
        const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
      ]),
    };
    await local.db.transaction(
      (tx) => SyncQueryRegistry.upsert(tx, 'brands', spec),
    );
    final identity = SyncQueryRegistry.key('brands', spec);
    await local.db.transaction(
      (tx) =>
          SyncQueryRegistry.reconcile(tx, SystemCatalogueMetadata.collections),
    );
    final row = (await local.db.query(
      'sync_queries',
      where: 'queryKey=?',
      whereArgs: [identity],
    )).single;
    expect(row['active'], 0);
    expect(row['queryJson'], jsonEncode(SyncQueryRegistry.normalize(spec)));
  });
  test(
    'selector reconciliation accounts for every active imported subcategory',
    () async {
      await import(fixture());
      final selector = CatalogueSelectionResolver(service);
      final categories = await selector.getEligibleCategories(
        tenantId: 'T',
        businessId: 'B',
        token: token('U'),
      );
      final eligible = <String>{};
      for (final c in categories) {
        eligible.addAll(
          (await selector.getEligibleSubcategories(
            tenantId: 'T',
            businessId: 'B',
            categoryId: c.id,
            token: token('U'),
          )).map((s) => s.id),
        );
      }
      final raw = await local.query('product_subcategories', [
        const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
      ]);
      expect(eligible, raw.map((d) => fields(d)['subcategoryId']).toSet());
      expect(remote.reads + remote.queries, 0);
    },
  );
  test('catalogue imports and alias metadata preserve Product, Variant, SKU, barcode and historical rows byte-for-byte', () async {
    for (final pair in {
      'products': 'PRODUCT',
      'product_variants': 'VARIANT',
      'inventory_transactions': 'HISTORY',
    }.entries) {
      await local.upsertRemote(pair.key, [
        doc(pair.key, pair.value, {
          'scopeType': 'BUSINESS',
          'tenantId': 'T',
          'businessId': 'B',
          'status': 'ACTIVE',
          'productId': 'PRODUCT',
          'variantId': 'VARIANT',
          'sku': 'KEEP-SKU',
          'barcode': 'KEEP-BARCODE',
          'categoryId': 'SYS_CATEGORY_EXTERIOR_WALL_PAINTS',
          'subcategoryId': 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT',
          'unitId': 'PM_UNIT_3871fc5bdee74d78',
          'createdAt': DateTime.utc(2020),
        }),
      ]);
    }
    final before = {
      for (final c in [
        'products',
        'product_variants',
        'inventory_transactions',
      ])
        c: await local.db.query(LocalDataSource.table(c)),
    };
    final input = fixture();
    edit(input['product_catalogue_releases']!.single, {
      'historicalAliases': {
        'SYS_CATEGORY_EXTERIOR_WALL_PAINTS':
            'SYS_CATEGORY_EXTERIOR_WALL_COATINGS',
      },
    });
    await import(input);
    await import(next(input));
    for (final c in before.keys) {
      expect(await local.db.query(LocalDataSource.table(c)), before[c]);
    }
    expect(await local.db.query('sync_outbox'), isEmpty);
    expect(remote.commits, 0);
  });
  test('invalid parents, active orphan templates and condition metadata fail before writes', () async {
    final valid = SystemCatalogueMetadata.compile(fixture());
    for (final mode in ['parent', 'orphan', 'condition']) {
      final c = clone(valid);
      if (mode == 'parent') {
        edit(
          c['product_subcategories']!.firstWhere(
            (d) => fields(d)['status'] == 'ACTIVE',
          ),
          {'categoryId': 'ABSENT'},
        );
      }
      if (mode == 'orphan') {
        edit(
          c['subcategory_attribute_templates']!.firstWhere(
            (d) => fields(d)['status'] == 'ACTIVE',
          ),
          {'subcategoryId': 'ABSENT'},
        );
      }
      if (mode == 'condition') {
        edit(
          c['subcategory_attribute_templates']!.firstWhere(
            (d) => fields(d)['status'] == 'ACTIVE',
          ),
          {
            'visibleWhen': {
              'attributeId': 'ABSENT',
              'in': ['A'],
            },
          },
        );
      }
      final before = await state();
      await expectLater(import(c), throwsA(isA<AppException>()));
      expect(await state(), before);
    }
  });
  test('legacy correction revision is not inferred as compiler provenance or overwritten by same-version defaults', () async {
    final raw = fixture();
    await local.upsertRemote('product_catalogue_releases', [
      doc('product_catalogue_releases', 'PAINT_V1', {
        ...fields(raw['product_catalogue_releases']!.single),
        'localMetadataRevision': 5,
      }),
    ]);
    final before = await state();
    await expectLater(
      import(raw),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'catalogue-revision'),
      ),
    );
    expect(await state(), before);
    final corrected = fixture();
    edit(corrected['subcategory_attribute_templates']!.first, {
      'localMetadataRevision': 5,
    });
    await expectLater(
      import(corrected),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'catalogue-revision'),
      ),
    );
    expect(await state(), before);
    await import(next(raw));
    expect(
      fields(
        (await local.query('product_catalogue_releases', [])).single,
      )['compilerRevision'],
      CatalogueContract.compilerRevision,
    );
  });
  test('installed future compiler revision blocks older import even at same data version', () async {
    await local.upsertRemote('product_catalogue_releases', [
      doc('product_catalogue_releases', 'PAINT_V1', {
        ...fields(fixture()['product_catalogue_releases']!.single),
        'schemaRevision': CatalogueContract.schemaRevision,
        'compilerRevision': CatalogueContract.compilerRevision + 1,
      }),
    ]);
    final before = await state();
    await expectLater(import(fixture()), throwsA(isA<AppException>()));
    expect(await state(), before);
  });
  test(
    'compiled manifest still rejects unknown profile and undeclared schema',
    () async {
      for (final mode in ['profile', 'schema']) {
        final c = SystemCatalogueMetadata.compile(fixture());
        if (mode == 'profile') {
          edit(
            c['product_subcategories']!.firstWhere(
              (d) => fields(d)['status'] == 'ACTIVE',
            ),
            {'profileId': 'UNKNOWN'},
          );
        } else {
          final f = fields(c['product_catalogue_releases']!.single)
            ..remove('schemaRevision');
          c['product_catalogue_releases']!.single['fields'] =
              FirestoreRestService.encodeFields(f);
        }
        final before = await state();
        await expectLater(import(c), throwsA(isA<AppException>()));
        expect(await state(), before);
      }
    },
  );
  test('PAINT SYSTEM rows without a published release cannot bootstrap unversioned metadata', () async {
    remote.seed('product_attributes', 'usage', {
      'scopeType': 'SYSTEM',
      'catalogueId': 'PAINT_V1',
      'attributeId': 'usage',
      'status': 'ACTIVE',
    });
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, contains('published versioned release'));
    expect(await local.query('product_attributes', []), isEmpty);
    expect(await local.query('product_catalogue_releases', []), isEmpty);
    for (final q in await local.db.query(
      'sync_queries',
      where: 'collectionName=?',
      whereArgs: ['product_attributes'],
    )) {
      expect(q['cursor'], isNull);
    }
  });
  test(
    'unfiltered catalogue query cannot bypass validated SYSTEM release import',
    () async {
      await local.db.update('sync_queries', {'active': 0});
      await local.db.transaction(
        (tx) =>
            SyncQueryRegistry.upsert(tx, 'product_attributes', {'filters': []}),
      );
      remote.seed('product_attributes', 'usage', {
        'scopeType': 'SYSTEM',
        'attributeId': 'usage',
        'status': 'ACTIVE',
      });
      connectivity.available = true;
      await sync.sync(push: false);
      expect(sync.error, contains('complete release pipeline'));
      expect(await local.query('product_attributes', []), isEmpty);
      final row = (await local.db.query(
        'sync_queries',
        where: 'queryKey=?',
        whereArgs: [
          SyncQueryRegistry.key('product_attributes', {'filters': []}),
        ],
      )).single;
      expect(row['cursor'], isNull);
    },
  );
  test('incomplete compiler input and incompatible remote marker fail with diagnostics before cursors advance', () async {
    expect(
      () => SystemCatalogueMetadata.compile({}),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'catalogue-release'),
      ),
    );
    remote.catalogue(fixture());
    connectivity.available = true;
    await sync.checkCatalogue(forceCheck: true);
    expect(sync.error, isNull);
    final before = await state(), reads = remote.collections.length;
    final incompatible = SystemCatalogueMetadata.compile(fixture());
    edit(incompatible['product_catalogue_releases']!.single, {
      'schemaRevision': 999,
    });
    remote.catalogue(incompatible);
    await sync.checkCatalogue(forceCheck: true);
    expect(
      sync.error,
      contains('Unsupported catalogue schema/compiler revision'),
    );
    expect(remote.collections.skip(reads).toList(), [
      'product_catalogue_releases',
    ]);
    final after = await state();
    for (final c in SystemCatalogueMetadata.collections) {
      expect(after[c], before[c]);
    }
    for (final q in (after['queries'] as List).cast<Map>()) {
      final prior = (before['queries'] as List).cast<Map>().singleWhere(
        (r) => r['queryKey'] == q['queryKey'],
      );
      expect(q['cursor'], prior['cursor']);
      expect(q['catalogueVersion'], prior['catalogueVersion']);
    }
  });
  test('logical fingerprint preserves priority order of default rules', () {
    final a = SystemCatalogueMetadata.compile(fixture()), b = clone(a);
    final row = b['subcategory_attribute_templates']!.firstWhere(
      (d) => (fields(d)['defaultRules'] as List? ?? []).length > 1,
    );
    final rules = (fields(row)['defaultRules'] as List).reversed.toList();
    edit(row, {'defaultRules': rules});
    expect(
      CatalogueContract.fingerprint(a),
      isNot(CatalogueContract.fingerprint(b)),
    );
  });
}
