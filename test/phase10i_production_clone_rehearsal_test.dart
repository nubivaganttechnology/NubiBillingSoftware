import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_fingerprint.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/catalogue_archive_store.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_transaction_service.dart';
import 'package:testflutter/data/services/historical_catalogue_resolver.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
import 'package:testflutter/data/services/product_validator.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/core/config/environment_config.dart';

import 'support/decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;
import 'support/phase10e_release.dart';
import 'offline_sync_test.dart' show FakeRemote, TestConnectivity, session;

const _accountHash =
    '7751a6cc30a1f3765067bcec646beb16b0dc9dd094e1ccacd0d4d23e7e1515ef';
const _publicConfigHash =
    'a81b30213ada2f9fbb962eb4c55b5824545048cf0be534dcc12d591dc9c93693';
const _ceilingDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _ceilingPayloadId =
    'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS';
const _basementDocumentId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING';
const _basementPayloadId = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT';
const _writeClosureSubcategory =
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_PREMIUM_INTERIOR_EMULSIONS';

String _tokenFor(String uid) {
  final claims = {
    'sub': uid,
    'aud': EnvironmentConfig.projectId,
    'exp':
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
        1000,
  };
  // ignore: avoid_print
  final encoded = base64Url.encode(utf8.encode(jsonEncode(claims)));
  return 'header.$encoded.signature';
}

class _InjectedVariantWriteFailure implements Exception {
  const _InjectedVariantWriteFailure();
}

class _FailAtVariantCreate implements FirestoreTransactionService {
  _FailAtVariantCreate(this.delegate);

  final FirestoreTransactionService delegate;
  bool productCreateReached = false;

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) => delegate.runAtomicOperation(
    (tx) => action(_FailingTransactionContext(this, tx)),
    idToken: idToken,
    maxAttempts: maxAttempts,
  );
}

class _FailingTransactionContext implements FirestoreTransactionContext {
  _FailingTransactionContext(this.owner, this.delegate);

  final _FailAtVariantCreate owner;
  final FirestoreTransactionContext delegate;

  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) =>
      delegate.get(collection, id);

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) => delegate.query(collection, filters);

  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    if (collection == 'products') owner.productCreateReached = true;
    if (collection == 'product_variants' && owner.productCreateReached) {
      throw const _InjectedVariantWriteFailure();
    }
    delegate.create(collection, id, fields);
  }

  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) => delegate.update(collection, id, fields, updateTime: updateTime);

  @override
  void delete(String collection, String id, {required String? updateTime}) =>
      delegate.delete(collection, id, updateTime: updateTime);
}

String _stableRows(List<Map<String, Object?>> rows) {
  final encoded = rows.map((row) {
    final keys = row.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: row[key]});
  }).toList()..sort();
  return jsonEncode(encoded);
}

Future<String> _completeState(DatabaseExecutor db) async {
  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  );
  final state = <String, String>{};
  for (final entry in tableRows) {
    final table = entry['name'] as String;
    final quoted = table.replaceAll('"', '""');
    final rows = await db.rawQuery('SELECT * FROM "$quoted"');
    state[table] = _stableRows(rows);
  }
  return jsonEncode(state);
}

Future<File> _copyDatabase(
  File source,
  Directory directory,
  String project,
  String uid,
) async {
  await directory.create(recursive: true);
  final target = File(
    path.join(
      directory.path,
      'nubibill-${Uri.encodeComponent('$project-$uid')}.db',
    ),
  );
  await source.copy(target.path);
  return target;
}

Future<String> _sha256(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

Future<Map<String, List<Map<String, Object?>>>> _installedCatalogueRows(
  DatabaseExecutor db,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final collection in CatalogueArchiveStore.collections) {
    result[collection] = await db.query(
      LocalDataSource.table(collection),
      where: "scopeType='SYSTEM' AND isDeleted=0",
      orderBy: 'remoteId',
    );
  }
  result['brands'] = await db.query(
    LocalDataSource.table('brands'),
    where: "scopeType='SYSTEM' AND isDeleted=0",
    orderBy: 'remoteId',
  );
  return result;
}

String _catalogueFingerprint(Map<String, List<Map<String, Object?>>> rows) =>
    CatalogueFingerprint.calculate({
      for (final entry in rows.entries)
        entry.key: [
          for (final row in entry.value)
            {
              'name': '${entry.key}/${row['remoteId']}',
              'fields': jsonDecode(row['payloadJson'] as String),
            },
        ],
    });

Future<void> _assertRollback(
  Directory root,
  File source,
  String project,
  String uid,
  String stage,
) async {
  final rollbackRoot = Directory(
    path.join(root.path, 'rollback-${stage.replaceAll('_', '-')}'),
  );
  final seed = await _copyDatabase(
    source,
    Directory(path.join(rollbackRoot.path, 'seed')),
    project,
    uid,
  );
  final directory = Directory(path.join(rollbackRoot.path, 'app'));
  final workingCopy = await _copyDatabase(seed, directory, project, uid);
  final localDatabase = LocalDatabase(
    factory: databaseFactoryFfi,
    directory: directory.path,
  );
  final local = LocalDataSource(await localDatabase.open(project, uid));
  expect(await local.db.getVersion(), LocalDatabase.schemaVersion);
  final before = await _completeState(local.db);
  final markerBefore = await local.db.query('local_product_catalogue_releases');
  expect(markerBefore, isNotEmpty);
  final sentinel = StateError('Phase 10I injected rollback checkpoint: $stage');
  var reached = false;
  await expectLater(
    SystemCatalogueSnapshot.import(
      source: local,
      documents: approvedRelease4DocumentsForTest(),
      readTimes: const {'units': 'PHASE10I_FAILED_CURSOR'},
      failureProbe: (actual, tx) async {
        if (actual == stage) {
          reached = true;
          throw sentinel;
        }
      },
    ),
    throwsA(same(sentinel)),
  );
  expect(reached, isTrue, reason: 'Checkpoint $stage was not reached.');
  expect(await _completeState(local.db), before);
  expect(
    await local.db.query('local_product_catalogue_releases'),
    markerBefore,
  );
  await localDatabase.close();
  expect(await _sha256(seed), _accountHash);
  expect(await _sha256(workingCopy), isNot(_accountHash));
}

Future<Map<String, dynamic>> _runWritePathClosure({
  required Directory root,
  required File upgradedAccount,
  required String project,
  required String uid,
}) async {
  final tenant = 'C6btLkx5SyZvUQOzOeUUd7XxsFh2';
  final business = 'BUS-6CB1F7443C2142159B8EBE3F9303839B';
  final sourceCopy = await _copyDatabase(
    upgradedAccount,
    Directory(path.join(root.path, 'write-success-seed')),
    project,
    uid,
  );
  final successDirectory = Directory(path.join(root.path, 'write-success'));
  await successDirectory.create(recursive: true);
  final successPath = File(
    path.join(
      successDirectory.path,
      'nubibill-${Uri.encodeComponent('${EnvironmentConfig.projectId}-$uid')}.db',
    ),
  );
  await sourceCopy.copy(successPath.path);

  final failedSeed = await _copyDatabase(
    upgradedAccount,
    Directory(path.join(root.path, 'write-failure-seed')),
    project,
    uid,
  );
  final failureDirectory = Directory(path.join(root.path, 'write-failure'));
  await failureDirectory.create(recursive: true);
  final failurePath = File(
    path.join(
      failureDirectory.path,
      'nubibill-${Uri.encodeComponent('${EnvironmentConfig.projectId}-$uid')}.db',
    ),
  );
  await failedSeed.copy(failurePath.path);

  final cloneRecord = <String, dynamic>{
    'successChildPath': successPath.path,
    'failureChildPath': failurePath.path,
    'successChildMatchedUpgradedClone':
        await _sha256(successPath) == await _sha256(upgradedAccount),
    'failureChildMatchedUpgradedClone':
        await _sha256(failurePath) == await _sha256(upgradedAccount),
  };
  expect(cloneRecord['successChildMatchedUpgradedClone'], isTrue);
  expect(cloneRecord['failureChildMatchedUpgradedClone'], isTrue);

  final remote = FakeRemote()..offline = true;
  final connectivity = TestConnectivity()..available = false;
  final sync = SyncEngine(
    remote,
    connectivity,
    sessionProvider: () async => session(uid),
  );
  final database = LocalDatabase(
    factory: databaseFactoryFfi,
    directory: successDirectory.path,
  );
  final offline = OfflineFirestoreService(database, remote, sync);
  final token = _tokenFor(uid);
  final local = LocalDataSource(
    await database.open(EnvironmentConfig.projectId, uid),
  );
  await offline.activate(uid);
  final repository = ProductRepository(offline, offline);

  final productBefore = await local.db.query(
    'local_products',
    orderBy: 'remoteId',
  );
  final variantsBefore = await local.db.query(
    'local_product_variants',
    orderBy: 'remoteId',
  );
  final queriesBefore = await local.db.query(
    'sync_queries',
    orderBy: 'queryKey',
  );
  final archiveBefore = await local.db.query(
    CatalogueArchiveStore.table,
    orderBy: 'catalogueFingerprint, collection, documentId',
  );
  expect(productBefore, hasLength(4));
  expect(variantsBefore, hasLength(7));
  expect(queriesBefore, hasLength(195));
  expect(archiveBefore, hasLength(3903));
  final productStateBefore = _stableRows(productBefore);
  final variantStateBefore = _stableRows(variantsBefore);
  final queryStateBefore = _stableRows(queriesBefore);
  final archiveDigestBefore = sha256
      .convert(utf8.encode(_stableRows(archiveBefore)))
      .toString();
  final oldProductIds = productBefore.map((r) => r['remoteId']).toSet();
  final oldVariantIds = variantsBefore.map((r) => r['remoteId']).toSet();

  final marker = FirestoreRestService.decodeFields(
    jsonDecode(
      (await local.row(
            'product_catalogue_releases',
            'PAINT_V1',
          ))!['payloadJson']
          as String,
    ),
  );
  final releaseFingerprint = marker['catalogueFingerprint'] as String;
  expect(CatalogueFingerprint.isValid(releaseFingerprint), isTrue);
  final systemCategories = phase10eCandidates
      .map((candidate) => candidate['categoryId'] as String)
      .toSet();
  final selector = CatalogueSelectionResolver(offline);
  final resolvedSelectors = <String>{};
  for (final categoryId in systemCategories) {
    resolvedSelectors.addAll(
      (await selector.getEligibleSubcategories(
        tenantId: tenant,
        businessId: business,
        categoryId: categoryId,
        token: token,
        businessTypeId: 'HARDWARE',
        businessSubTypeId: 'PAINTS',
      )).map((value) => value.id),
    );
  }
  expect(resolvedSelectors, hasLength(137));

  final candidate = phase10eCandidates.singleWhere(
    (row) => row['canonicalId'] == _writeClosureSubcategory,
  );
  expect(candidate['intendedSelectability'], 'SELECTABLE_READY');
  expect(resolvedSelectors, contains(_writeClosureSubcategory));
  final canonicalForm = await ProductTemplateResolver(offline).resolveTemplate(
    tenantId: tenant,
    businessId: business,
    subcategoryId: _writeClosureSubcategory,
    categoryId: candidate['categoryId'] as String,
    token: token,
  );
  expect(canonicalForm.readiness, TemplateReadinessState.ready);
  expect(canonicalForm.allAttributes, isNotEmpty);
  final currentOptionNamesByAttribute = <String, Set<String>>{};
  for (final option in await local.query('product_attribute_options', [
    const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
    const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
  ])) {
    final fields = FirestoreRestService.decodeFields(option['fields']);
    currentOptionNamesByAttribute
        .putIfAbsent(fields['attributeId'] as String, () => <String>{})
        .add(fields['name'] as String);
  }
  for (final attribute in canonicalForm.allAttributes) {
    for (final option in attribute.options) {
      if (option.scopeType == 'SYSTEM' &&
          currentOptionNamesByAttribute.containsKey(attribute.attributeId)) {
        expect(
          currentOptionNamesByAttribute[attribute.attributeId],
          contains(option.name),
          reason:
              'Create form included a legacy/inactive option for ${attribute.attributeId}.',
        );
      }
    }
  }

  final brands = await repository.getMasterValues(
    tenantId: tenant,
    businessId: business,
    masterType: 'BRAND',
    token: token,
  );
  final systemBrand = brands.firstWhere((value) => value.scopeType == 'SYSTEM');
  final fixture = Phase10EFixture()
    ..local = local
    ..resolver = ProductTemplateResolver(ReadOnlyCatalogueService(local))
    ..validator = ProductValidator(ReadOnlyCatalogueService(local));
  final template = await fixture.resolve(candidate);
  final state = fixture.state(template);
  final productFields = Map<String, dynamic>.from(state['productFields'] as Map)
    ..['brandId'] = systemBrand.id;
  final variants = (state['variants'] as List)
      .map((raw) => Map<String, dynamic>.from(raw as Map))
      .toList();
  final variantForm = variants.single;
  final variantValues = Map<String, dynamic>.from(
    variantForm['attributeValues'] as Map? ?? const {},
  );
  String release4UnitId(String name) => CatalogueContract.unitIds[name]!;
  final packUnitName = variantValues['unit'] as String;
  final sellingUnitName = variantValues['soldAs'] as String;
  variantForm['packUnitId'] = release4UnitId(packUnitName);
  variantForm['commercialUnitId'] = release4UnitId(sellingUnitName);
  variantForm['baseUnitId'] = release4UnitId(sellingUnitName);
  variantForm['baseQuantityPerCommercialUnit'] = 1;
  final barcode = 'P10IB-${DateTime.now().microsecondsSinceEpoch}';
  variantForm['barcode'] = barcode;
  final productName =
      'Phase 10IB Release Four ${DateTime.now().microsecondsSinceEpoch}';
  final validatorResult = await ProductValidator(offline).validateProduct(
    tenantId: tenant,
    businessId: business,
    productName: productName,
    productFields: productFields,
    variants: variants,
    token: token,
    isNew: true,
  );
  expect(validatorResult.isValid, isTrue, reason: '${validatorResult.errors}');

  await repository.createStructuredProduct(
    tenantId: tenant,
    businessId: business,
    productName: productName,
    actorUid: uid,
    token: token,
    productFields: productFields,
    variants: variants,
  );

  final savedProducts = await local.db.query('local_products');
  final savedProductRow = savedProducts.singleWhere((row) {
    final fields = FirestoreRestService.decodeFields(
      jsonDecode(row['payloadJson'] as String),
    );
    return fields['productName'] == productName;
  });
  final savedProductFields = FirestoreRestService.decodeFields(
    jsonDecode(savedProductRow['payloadJson'] as String),
  );
  final productId = savedProductRow['remoteId'] as String;
  final savedVariantRows = (await local.db.query('local_product_variants'))
      .where((row) {
        final fields = FirestoreRestService.decodeFields(
          jsonDecode(row['payloadJson'] as String),
        );
        return fields['productId'] == productId;
      })
      .toList();
  expect(savedVariantRows, hasLength(1));
  final variantRow = savedVariantRows.single;
  final variantFields = FirestoreRestService.decodeFields(
    jsonDecode(variantRow['payloadJson'] as String),
  );
  final variantId = variantRow['remoteId'] as String;
  expect(savedProductFields['catalogueFingerprint'], releaseFingerprint);
  expect(variantFields['productId'], productId);
  expect(variantFields.containsKey('catalogueFingerprint'), isFalse);

  final productOutbox = (await local.db.query(
    'sync_outbox',
    where: 'entityType=? AND documentId=?',
    whereArgs: ['products', productId],
  )).single;
  final productWrite =
      jsonDecode(productOutbox['payloadJson'] as String) as Map;
  final outboxProductFields = FirestoreRestService.decodeFields(
    productWrite['fields'],
  );
  expect(outboxProductFields['catalogueFingerprint'], releaseFingerprint);
  final variantOutbox = (await local.db.query(
    'sync_outbox',
    where: 'entityType=? AND documentId=?',
    whereArgs: ['product_variants', variantId],
  )).single;
  final variantWrite =
      jsonDecode(variantOutbox['payloadJson'] as String) as Map;
  final outboxVariantFields = FirestoreRestService.decodeFields(
    variantWrite['fields'],
  );
  expect(outboxVariantFields['productId'], productId);
  expect(outboxVariantFields.containsKey('catalogueFingerprint'), isFalse);

  final loaded = await repository.getProducts(
    tenantId: tenant,
    businessId: business,
    token: token,
  );
  final loadedProduct = loaded.singleWhere(
    (value) => value.productId == productId,
  );
  expect(loadedProduct.catalogueFingerprint, releaseFingerprint);
  expect(loadedProduct.variants, hasLength(1));
  expect(loadedProduct.variants.single.variantId, variantId);
  expect(loadedProduct.variants.single.productId, productId);
  expect(loadedProduct.variants.single.barcode, barcode);
  final allVariantModels = loaded.expand((value) => value.variants).toList();
  expect(
    allVariantModels.map((value) => value.sku).toSet().length,
    allVariantModels.length,
  );
  expect(
    allVariantModels
        .map((value) => value.barcode)
        .whereType<String>()
        .toSet()
        .length,
    allVariantModels.where((value) => value.barcode?.isNotEmpty == true).length,
  );

  final resolvedCanonical = await ProductTemplateResolver(offline)
      .resolveTemplate(
        tenantId: tenant,
        businessId: business,
        subcategoryId: savedProductFields['subcategoryId'] as String,
        categoryId: savedProductFields['categoryId'] as String,
        token: token,
      );
  expect(resolvedCanonical.readiness, TemplateReadinessState.ready);
  expect(savedProductFields['catalogueFingerprint'], releaseFingerprint);

  for (final historical in loaded.where(
    (value) => oldProductIds.contains(value.productId),
  )) {
    expect(historical.catalogueFingerprint, isNull);
    expect(
      historical.historicalCatalogueResolution?.status,
      CatalogueResolutionStatus.provenanceMissing,
    );
  }
  final productAfter = await local.db.query(
    'local_products',
    orderBy: 'remoteId',
  );
  final variantsAfter = await local.db.query(
    'local_product_variants',
    orderBy: 'remoteId',
  );
  expect(
    _stableRows(
      productAfter
          .where((row) => oldProductIds.contains(row['remoteId']))
          .toList(),
    ),
    productStateBefore,
  );
  expect(
    _stableRows(
      variantsAfter
          .where((row) => oldVariantIds.contains(row['remoteId']))
          .toList(),
    ),
    variantStateBefore,
  );
  expect(
    _stableRows(await local.db.query('sync_queries', orderBy: 'queryKey')),
    queryStateBefore,
  );
  final archiveAfter = await local.db.query(
    CatalogueArchiveStore.table,
    orderBy: 'catalogueFingerprint, collection, documentId',
  );
  final archiveDigestAfter = sha256
      .convert(utf8.encode(_stableRows(archiveAfter)))
      .toString();
  expect(archiveDigestAfter, archiveDigestBefore);
  final oldProductPayloads = productAfter
      .where((row) => oldProductIds.contains(row['remoteId']))
      .map(
        (row) => FirestoreRestService.decodeFields(
          jsonDecode(row['payloadJson'] as String),
        ),
      )
      .toList();
  expect(
    oldProductPayloads.every(
      (fields) => fields['catalogueFingerprint'] == null,
    ),
    isTrue,
  );

  final duplicateState = await _completeState(local.db);
  final duplicateVariant = Map<String, dynamic>.from(variants.single)
    ..['barcode'] = barcode;
  await expectLater(
    repository.createStructuredProduct(
      tenantId: tenant,
      businessId: business,
      productName: '$productName Duplicate',
      actorUid: uid,
      token: token,
      productFields: productFields,
      variants: [duplicateVariant],
    ),
    throwsA(isA<AppException>()),
  );
  expect(await _completeState(local.db), duplicateState);

  await Future<void>.delayed(const Duration(milliseconds: 500));
  expect(remote.reads + remote.queries + remote.commits, 0);
  sync.dispose();
  await database.close();

  final failureRemote = FakeRemote()..offline = true;
  final failureConnectivity = TestConnectivity()..available = false;
  final failureSync = SyncEngine(
    failureRemote,
    failureConnectivity,
    sessionProvider: () async => session(uid),
  );
  final failureDatabase = LocalDatabase(
    factory: databaseFactoryFfi,
    directory: failureDirectory.path,
  );
  final failureOffline = OfflineFirestoreService(
    failureDatabase,
    failureRemote,
    failureSync,
  );
  final failureLocal = LocalDataSource(
    await failureDatabase.open(EnvironmentConfig.projectId, uid),
  );
  await failureOffline.activate(uid);
  final failureRepository = ProductRepository(
    failureOffline,
    _FailAtVariantCreate(failureOffline),
  );
  final failureBefore = await _completeState(failureLocal.db);
  final failureBrand = (await failureRepository.getMasterValues(
    tenantId: tenant,
    businessId: business,
    masterType: 'BRAND',
    token: token,
  )).firstWhere((value) => value.scopeType == 'SYSTEM');
  final failureFields = Map<String, dynamic>.from(productFields)
    ..['brandId'] = failureBrand.id;
  final failureVariants = variants
      .map(
        (value) =>
            Map<String, dynamic>.from(value)..['barcode'] = '$barcode-FAIL',
      )
      .toList();
  final failingTransactions =
      (failureRepository.transactions as _FailAtVariantCreate);
  await expectLater(
    failureRepository.createStructuredProduct(
      tenantId: tenant,
      businessId: business,
      productName: '$productName Rollback',
      actorUid: uid,
      token: token,
      productFields: failureFields,
      variants: failureVariants,
    ),
    throwsA(isA<_InjectedVariantWriteFailure>()),
  );
  expect(failingTransactions.productCreateReached, isTrue);
  expect(await _completeState(failureLocal.db), failureBefore);
  expect(
    failureRemote.reads + failureRemote.queries + failureRemote.commits,
    0,
  );
  failureSync.dispose();
  await failureDatabase.close();

  return {
    ...cloneRecord,
    'selectedCanonicalSubcategory': _writeClosureSubcategory,
    'productId': productId,
    'variantId': variantId,
    'barcode': barcode,
    'sku': variantFields['sku'],
    'catalogueFingerprint': releaseFingerprint,
    'productAndOutboxFingerprintEqual':
        savedProductFields['catalogueFingerprint'] ==
        outboxProductFields['catalogueFingerprint'],
    'variantUsesParentProductIdForProvenance':
        variantFields['productId'] == productId &&
        !variantFields.containsKey('catalogueFingerprint'),
    'productValidatorValid': validatorResult.isValid,
    'readBackValid':
        loadedProduct.variants.single.variantId == variantId &&
        loadedProduct.catalogueFingerprint == releaseFingerprint,
    'productsPreserved': oldProductIds.length,
    'variantsPreserved': oldVariantIds.length,
    'syncQueriesPreserved': queriesBefore.length,
    'archiveRows': archiveBefore.length,
    'archiveDigestBefore': archiveDigestBefore,
    'archiveDigestAfter': archiveDigestAfter,
    'archiveDigestPreserved': archiveDigestBefore == archiveDigestAfter,
    'historicalNullProvenanceFailClosed': true,
    'failedCreateRolledBackCompletely': true,
    'failedCreateProductStagedBeforeFailure':
        failingTransactions.productCreateReached,
    'skuUnique':
        allVariantModels.map((value) => value.sku).toSet().length ==
        allVariantModels.length,
    'barcodeUnique':
        allVariantModels
            .map((value) => value.barcode)
            .whereType<String>()
            .toSet()
            .length ==
        allVariantModels
            .where((value) => value.barcode?.isNotEmpty == true)
            .length,
    'remoteCalls':
        remote.reads +
        remote.queries +
        remote.commits +
        failureRemote.reads +
        failureRemote.queries +
        failureRemote.commits,
  };
}

void main() {
  final clonePath = Platform.environment['PHASE10I_CLONE_DIR'];
  final accountProject = Platform.environment['PHASE10I_ACCOUNT_PROJECT'];
  final accountUid = Platform.environment['PHASE10I_ACCOUNT_UID'];
  final configProject = Platform.environment['PHASE10I_CONFIG_PROJECT'];
  final configUid = Platform.environment['PHASE10I_CONFIG_UID'];

  test(
    'verified production clones migrate, archive and install Release 4 locally',
    () async {
      expect(clonePath, isNotNull);
      expect(accountProject, isNotNull);
      expect(accountUid, isNotNull);
      expect(configProject, isNotNull);
      expect(configUid, isNotNull);
      final root = Directory(clonePath!);
      final accountSource = File(path.join(root.path, 'account.db'));
      final configSource = File(path.join(root.path, 'public-config.db'));
      expect(await _sha256(accountSource), _accountHash);
      expect(await _sha256(configSource), _publicConfigHash);

      sqfliteFfiInit();
      final accountRaw = await databaseFactoryFfi.openDatabase(
        accountSource.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final configRaw = await databaseFactoryFfi.openDatabase(
        configSource.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      expect(await accountRaw.getVersion(), 3);
      expect(await configRaw.getVersion(), 3);
      final productsBefore = await accountRaw.query(
        'local_products',
        orderBy: 'remoteId',
      );
      final variantsBefore = await accountRaw.query(
        'local_product_variants',
        orderBy: 'remoteId',
      );
      final queriesBefore = await accountRaw.query(
        'sync_queries',
        orderBy: 'queryKey',
      );
      final outboxBefore = await accountRaw.query('sync_outbox', orderBy: 'id');
      final queryDefinitionsBefore = _stableRows([
        for (final row in queriesBefore)
          {
            'queryKey': row['queryKey'],
            'collectionName': row['collectionName'],
            'queryJson': row['queryJson'],
            'active': row['active'],
          },
      ]);
      expect(productsBefore, hasLength(4));
      expect(variantsBefore, hasLength(7));
      expect(queriesBefore, hasLength(195));
      expect(outboxBefore, isEmpty);
      final protectedSpecs =
          (jsonDecode(
                File('docs/phase10e-installed-v3-v4-diff.json')
                    .readAsStringSync(),
              ) as Map<String, dynamic>)['protectedLegacyQueries']
              as List;
      final protectedKeys = protectedSpecs
          .map((row) => (row as Map)['queryKey'] as String)
          .toSet();
      final protectedBefore = queriesBefore
          .where((row) => protectedKeys.contains(row['queryKey']))
          .toList();
      expect(protectedBefore, hasLength(10));
      final catalogueBefore = await _installedCatalogueRows(accountRaw);
      final oldFingerprint = _catalogueFingerprint(catalogueBefore);
      expect(CatalogueFingerprint.isValid(oldFingerprint), isTrue);
      await accountRaw.close();
      await configRaw.close();

      final accountDirectory = Directory(path.join(root.path, 'account-app'));
      final configDirectory = Directory(
        path.join(root.path, 'public-config-app'),
      );
      final accountWorkingCopy = await _copyDatabase(
        accountSource,
        accountDirectory,
        accountProject!,
        accountUid!,
      );
      final configWorkingCopy = await _copyDatabase(
        configSource,
        configDirectory,
        configProject!,
        configUid!,
      );
      expect(await _sha256(accountWorkingCopy), _accountHash);
      expect(await _sha256(configWorkingCopy), _publicConfigHash);

      final accountDatabase = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: accountDirectory.path,
      );
      final accountLocal = LocalDataSource(
        await accountDatabase.open(accountProject, accountUid),
      );
      final configDatabase = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: configDirectory.path,
      );
      final configLocal = LocalDataSource(
        await configDatabase.open(configProject, configUid),
      );
      expect(await accountLocal.db.getVersion(), LocalDatabase.schemaVersion);
      expect(await configLocal.db.getVersion(), LocalDatabase.schemaVersion);
      expect(await configLocal.db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'},
      ]);
      expect(
        await accountLocal.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='local_catalogue_archive'",
        ),
        hasLength(1),
      );
      expect(
        await configLocal.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='local_catalogue_archive'",
        ),
        hasLength(1),
      );

      // Snapshot import accepts only a LocalDataSource; no HTTP client, sync
      // engine, or Firestore adapter is constructed in this rehearsal.
      await SystemCatalogueSnapshot.import(
        source: accountLocal,
        documents: approvedRelease4DocumentsForTest(),
        readTimes: const {'units': 'PHASE10I_RELEASE4_CURSOR'},
      );
      expect(await accountLocal.db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'},
      ]);

      expect(
        _stableRows(
          await accountLocal.db.query('local_products', orderBy: 'remoteId'),
        ),
        _stableRows(productsBefore),
      );
      expect(
        _stableRows(
          await accountLocal.db.query(
            'local_product_variants',
            orderBy: 'remoteId',
          ),
        ),
        _stableRows(variantsBefore),
      );
      expect(
        _stableRows(await accountLocal.db.query('sync_outbox', orderBy: 'id')),
        _stableRows(outboxBefore),
      );
      final queriesAfter = await accountLocal.db.query(
        'sync_queries',
        orderBy: 'queryKey',
      );
      expect(queriesAfter, hasLength(195));
      expect(
        _stableRows([
          for (final row in queriesAfter)
            {
              'queryKey': row['queryKey'],
              'collectionName': row['collectionName'],
              'queryJson': row['queryJson'],
              'active': row['active'],
            },
        ]),
        queryDefinitionsBefore,
      );
      final protectedAfter = queriesAfter
          .where((row) => protectedKeys.contains(row['queryKey']))
          .toList();
      expect(_stableRows(protectedAfter), _stableRows(protectedBefore));

      final newMarker = FirestoreRestService.decodeFields(
        jsonDecode(
          (await accountLocal.row(
                'product_catalogue_releases',
                'PAINT_V1',
              ))!['payloadJson']
              as String,
        ),
      );
      expect(CatalogueContract.version(newMarker), 4);
      expect(newMarker['schemaRevision'], 1);
      expect(newMarker['compilerRevision'], 6);
      expect(newMarker['installed'], isTrue);
      expect(
        newMarker['contentFingerprint'],
        phase10eReview['contentFingerprint'],
      );
      final releaseFingerprint = newMarker['catalogueFingerprint'] as String;
      expect(CatalogueFingerprint.isValid(releaseFingerprint), isTrue);
      final expectedArchive = <String, String>{};
      for (final entry in catalogueBefore.entries) {
        if (!CatalogueArchiveStore.collections.contains(entry.key)) continue;
        for (final row in entry.value) {
          expectedArchive['${entry.key}/${row['remoteId']}'] =
              row['payloadJson'] as String;
        }
      }
      final archived = await accountLocal.db.query(
        CatalogueArchiveStore.table,
        where: 'catalogueFingerprint=?',
        whereArgs: [oldFingerprint],
        orderBy: 'collection,documentId',
      );
      expect(archived, hasLength(expectedArchive.length));
      expect({
        for (final row in archived)
          '${row['collection']}/${row['documentId']}': row['payloadJson'],
      }, expectedArchive);
      final archivedCeiling = archived.singleWhere(
        (row) =>
            row['collection'] == 'product_subcategories' &&
            row['documentId'] == _ceilingDocumentId,
      );
      final archivedBasement = archived.singleWhere(
        (row) =>
            row['collection'] == 'product_subcategories' &&
            row['documentId'] == _basementDocumentId,
      );
      expect(archivedCeiling['payloadId'], _ceilingPayloadId);
      expect(archivedBasement['payloadId'], _basementPayloadId);
      expect(
        archived.any(
          (row) =>
              row['collection'] == 'product_subcategories' &&
              row['documentId'] ==
                  'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_LIQUID',
        ),
        isFalse,
      );

      final historicalResolver = HistoricalCatalogueResolver(accountLocal.db);
      for (final row in productsBefore) {
        final fields = FirestoreRestService.decodeFields(
          jsonDecode(row['payloadJson'] as String),
        );
        expect(fields['catalogueFingerprint'], isNull);
        final resolution = await historicalResolver.resolveProduct(
          fields,
          context: CatalogueResolutionContext.readExisting,
        );
        expect(resolution.status, CatalogueResolutionStatus.provenanceMissing);
      }

      final selection = CatalogueSelectionResolver(
        ReadOnlyCatalogueService(accountLocal),
      );
      final actualSelectors = <String>{};
      for (final category
          in phase10eCandidates
              .map((candidate) => candidate['categoryId'] as String)
              .toSet()) {
        actualSelectors.addAll(
          (await selection.getEligibleSubcategories(
            tenantId: 'T',
            businessId: 'B',
            categoryId: category,
            token: 'PHASE10I_LOCAL_ONLY',
          )).map((row) => row.id),
        );
      }
      final expectedSelectors = phase10eCandidates
          .where((row) => row['intendedSelectability'] == 'SELECTABLE_READY')
          .map((row) => row['canonicalId'] as String)
          .toSet();
      expect(phase10eCandidates, hasLength(137));
      expect(expectedSelectors, hasLength(137));
      expect(actualSelectors, expectedSelectors);

      final formFixture = Phase10EFixture();
      formFixture.local = accountLocal;
      final localReader = ReadOnlyCatalogueService(accountLocal);
      formFixture.resolver = ProductTemplateResolver(localReader);
      formFixture.validator = ProductValidator(localReader);
      var readyForms = 0;
      for (final candidate in phase10eCandidates) {
        final template = await formFixture.resolve(candidate);
        expect(template.readiness, TemplateReadinessState.ready);
        expect(
          template.allAttributes.any(
            (attribute) => attribute.attributeId == 'unit',
          ),
          isTrue,
          reason: '${candidate['canonicalId']} has no resolved unit attribute.',
        );
        final validation = await formFixture.validate(
          formFixture.state(template),
        );
        expect(
          validation.isValid,
          isTrue,
          reason: '${candidate['canonicalId']}: ${validation.errors}',
        );
        readyForms++;
      }
      expect(readyForms, 137);

      final beforeNoOp = await _completeState(accountLocal.db);
      await SystemCatalogueSnapshot.import(
        source: accountLocal,
        documents: approvedRelease4DocumentsForTest(),
        readTimes: const {'units': 'PHASE10I_NOOP_CURSOR'},
      );
      expect(await _completeState(accountLocal.db), beforeNoOp);

      final writeClosure = await _runWritePathClosure(
        root: root,
        upgradedAccount: accountWorkingCopy,
        project: accountProject,
        uid: accountUid,
      );
      expect(writeClosure['remoteCalls'], 0);
      expect(writeClosure['productAndOutboxFingerprintEqual'], isTrue);
      expect(writeClosure['failedCreateRolledBackCompletely'], isTrue);

      for (final stage in [
        'before_archive',
        'archive_row_1',
        'after_archive',
        'product_subcategories',
        'before_release_marker',
        'after_release_marker',
      ]) {
        await _assertRollback(
          root,
          accountSource,
          accountProject,
          accountUid,
          stage,
        );
      }

      final restoreDirectory = Directory(path.join(root.path, 'restore-drill'));
      final restoredAccount = await _copyDatabase(
        accountSource,
        restoreDirectory,
        accountProject,
        accountUid,
      );
      final restoredConfig = await _copyDatabase(
        configSource,
        restoreDirectory,
        configProject,
        configUid,
      );
      expect(await _sha256(restoredAccount), _accountHash);
      expect(await _sha256(restoredConfig), _publicConfigHash);
      final restoredRaw = await databaseFactoryFfi.openDatabase(
        restoredAccount.path,
        options: OpenDatabaseOptions(readOnly: true),
      );
      expect(await restoredRaw.getVersion(), 3);
      expect(await restoredRaw.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'},
      ]);
      await restoredRaw.close();

      await accountDatabase.close();
      await configDatabase.close();
      expect(await _sha256(accountSource), _accountHash);
      expect(await _sha256(configSource), _publicConfigHash);
      // ignore: avoid_print
      print('PHASE10IB_WRITE_CLOSURE: ${jsonEncode(writeClosure)}');
      // ignore: avoid_print
      print(
        'PHASE10I_CLONE_REHEARSAL: ${jsonEncode({'accountSchemaVersion': LocalDatabase.schemaVersion, 'publicConfigSchemaVersion': LocalDatabase.schemaVersion, 'productsPreserved': productsBefore.length, 'variantsPreserved': variantsBefore.length, 'syncQueriesPreserved': queriesBefore.length, 'protectedQueriesPreserved': protectedBefore.length, 'outboxRowsPreserved': outboxBefore.length, 'archivedLegacyRows': archived.length, 'releaseFingerprint': releaseFingerprint, 'selectors': actualSelectors.length, 'formsReady': readyForms, 'rollbackCheckpoints': 6, 'postUpgradeIntegrityChecks': 'ok', 'remoteCalls': 0, 'restorePairVerified': true, 'sourceHashesUnchanged': true})}',
      );
    },
    skip: clonePath == null
        ? 'Set PHASE10I_CLONE_DIR to a verified clone set.'
        : false,
  );
}
