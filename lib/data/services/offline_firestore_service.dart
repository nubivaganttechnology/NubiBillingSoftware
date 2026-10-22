import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/config/environment_config.dart';
import '../../core/errors/app_exception.dart';
import '../catalogue/central_product_master_contract.dart';
import '../catalogue/system_catalogue_metadata.dart';
import '../local/local_database.dart';
import '../local/local_data_source.dart';
import '../models/auth_session_model.dart';
import '../models/central_product_master.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_outbox_repository.dart';
import '../sync/sync_query_registry.dart';
import 'firestore_data_service.dart';
import 'firestore_rest_service.dart';
import 'firestore_transaction_service.dart';

/// Repository-compatible local runtime source. REST is used only by sync and
/// first-time authorization/bootstrap when no cached authorization exists.
class OfflineFirestoreService
    implements
        FirestoreDataService,
        FirestoreTransactionService,
        FinancialReportSnapshotReader,
        OfflineWritePrerequisites {
  OfflineFirestoreService(this.database, this.remote, this.sync);
  final LocalDatabase database;
  final FirestoreRestService remote;
  final SyncEngine sync;
  LocalDataSource? _local;
  String? _uid;
  Future<void>? _activation;
  int _accountEpoch = 0;
  String? tenantId, businessId, outletId;
  static const catalogueCollections = [
    'product_catalogue_releases',
    'brands',
    'product_categories',
    'product_subcategories',
    'units',
    'product_attributes',
    'product_attribute_options',
    'subcategory_attribute_templates',
  ];
  static const bootstrap = {
    'app_config',
    'user',
    'employees',
    'roles',
    'permissions',
    'businesses',
    'outlets',
    'business_types',
    'business_sub_types',
  };
  Future<void> activate(String uid) {
    if (_uid == uid) {
      if (_activation != null) return _activation!;
      if (_local != null) return Future.value();
    }
    _registeredScope = null;
    sync.detach();
    tenantId = null;
    businessId = null;
    outletId = null;
    _uid = uid;
    _local = null;
    final epoch = ++_accountEpoch;
    final opening = _openAccount(uid, epoch);
    _activation = opening;
    return opening.whenComplete(() {
      if (epoch == _accountEpoch) _activation = null;
    });
  }

  Future<void> _openAccount(String uid, int epoch) async {
    if (kDebugMode) {
      debugPrint('[startup] Opening account database');
    }
    final db = await database.open(EnvironmentConfig.projectId, uid);
    if (epoch != _accountEpoch || uid != _uid) {
      throw const AppException(
        'Workspace account changed. Retry.',
        code: 'unauthenticated',
      );
    }
    _local = LocalDataSource(db);
    sync.attach(_local!, uid);
    if (kDebugMode) {
      debugPrint('[startup] Account database open; sync attached');
    }
  }

  void logout() {
    _accountEpoch++;
    _activation = null;
    _registeredScope = null;
    sync.detach();
    _uid = null;
    _local = null;
    tenantId = null;
    businessId = null;
    outletId = null;
  }

  Future<LocalDataSource> _source(String? token) async {
    if (token == null) {
      if (_local != null) return _local!;
      return LocalDataSource(
        await database.open(EnvironmentConfig.projectId, 'public-config'),
      );
    }
    final claims = AuthSession(
      idToken: token,
      refreshToken: '',
      uid: '',
      email: '',
      expiresAt: DateTime.now(),
    ).tokenClaims;
    final uid = claims?['sub'] as String?;
    if (uid == null || claims?['aud'] != EnvironmentConfig.projectId) {
      throw const AppException('Invalid session.', code: 'unauthenticated');
    }
    if (_uid == null) await activate(uid);
    if (uid == _uid && _activation != null) await _activation;
    if (uid != _uid) {
      throw const AppException(
        'Workspace account changed. Retry.',
        code: 'unauthenticated',
      );
    }
    return _local!;
  }

  /// Local account source for explicit read-only archive resolution. This does
  /// not issue network requests or alter sync registration/query state.
  Future<LocalDataSource> localDataSourceForToken(String token) =>
      _source(token);

  @override
  Future<ReportReadSnapshot> readReportSnapshot(
    List<ReportReadQuery> queries, {
    required String token,
  }) async {
    final local = await _source(token);
    return local.db.transaction((tx) async {
      final documents = <String, List<Map<String, dynamic>>>{};
      final coverage = <String, Map<String, Object?>>{};
      final syncQueries = await tx.query('sync_queries');
      for (final query in queries) {
        documents[query.key] = await local.query(
          query.collection,
          query.filters,
          executor: tx,
        );
        final requested = encodeFilters(query.filters).map(jsonEncode).toSet();
        final covering = syncQueries.where((row) {
          if (row['collectionName'] != query.collection ||
              row['lastSyncedAt'] == null ||
              row['lastError'] != null) {
            return false;
          }
          final spec = jsonDecode(row['queryJson'] as String) as Map;
          if (spec['limit'] != null) return false;
          final filters = spec['filters'];
          return filters is List &&
              filters.every((f) => requested.contains(jsonEncode(f)));
        }).toList();
        covering.sort(
          (a, b) => '${b['lastSyncedAt']}'.compareTo('${a['lastSyncedAt']}'),
        );
        final scopedFilters = query.filters
            .where(
              (f) =>
                  f.operation == 'EQUAL' &&
                  ['tenantId', 'businessId', 'outletId'].contains(f.field),
            )
            .toList();
        final outbox = await tx.query(
          'sync_outbox',
          columns: ['documentId'],
          where: [
            'entityType=?',
            ...scopedFilters.map((f) => '${f.field}=?'),
          ].join(' AND '),
          whereArgs: [query.collection, ...scopedFilters.map((f) => f.value)],
        );
        final pendingIds = {
          ...documents[query.key]!
              .where((d) => d['localSyncStatus'] != 'SYNCED')
              .map((d) => '${d['name']}'.split('/').last),
          ...outbox.map((r) => r['documentId']),
        };
        final conflicts = await tx.query(
          'sync_conflicts',
          columns: ['documentId'],
          where: 'entityType=? AND resolved=0',
          whereArgs: [query.collection],
        );
        final ids = documents[query.key]!
            .map((d) => '${d['name']}'.split('/').last)
            .toSet();
        coverage[query.key] = {
          'status': covering.isEmpty ? 'NOT_VERIFIED' : 'LOCAL_SNAPSHOT',
          'lastSyncedAt': covering.isEmpty
              ? null
              : covering.first['lastSyncedAt'],
          'pending': pendingIds.length,
          'conflicts': conflicts
              .where((r) => ids.contains(r['documentId']))
              .length,
        };
      }
      return ReportReadSnapshot(documents, coverage);
    });
  }

  static List<Map<String, dynamic>> encodeFilters(
    List<FirestoreFilter> filters,
  ) {
    final encoded = [
      for (final f in filters)
        {
          'field': f.field,
          'operation': f.operation,
          'value': FirestoreRestService.encodeValue(f.value),
        },
    ];
    encoded.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    return encoded;
  }

  final _bootstrapReads = <String, Future<dynamic>>{};
  Future<T> _readOnce<T>(String key, Future<T> Function() read) async {
    final identity = '$_accountEpoch:$key';
    final existing = _bootstrapReads[identity];
    if (existing != null) return await existing as T;
    final future = read();
    _bootstrapReads[identity] = future;
    try {
      return await future;
    } finally {
      if (identical(_bootstrapReads[identity], future)) {
        _bootstrapReads.remove(identity);
      }
    }
  }

  Future<bool> _coveredByInitializedQuery(
    LocalDataSource local,
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final requested = encodeFilters(filters).map(jsonEncode).toSet();
    final queries = await local.db.query(
      'sync_queries',
      where: 'collectionName=? AND lastSyncedAt IS NOT NULL',
      whereArgs: [collection],
    );
    for (final row in queries) {
      final spec = jsonDecode(row['queryJson'] as String) as Map;
      final registered = spec['filters'];
      if (registered is List &&
          registered.every((f) => requested.contains(jsonEncode(f)))) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _register(
    LocalDataSource local,
    String collection,
    Map<String, dynamic> spec, {
    bool active = true,
  }) async {
    return local.db.transaction(
      (tx) => SyncQueryRegistry.upsert(tx, collection, spec, active: active),
    );
  }

  String? _registeredScope;
  Future<void> setScope({
    required String tenant,
    required String business,
    String? outlet,
    bool products = true,
    bool productCreation = true,
    bool suppliers = true,
    bool purchases = true,
    bool storage = true,
    bool sales = true,
    bool customers = true,
    bool salaryAccess = false,
    bool attendanceAccess = false,
    bool staffKhataAccess = false,
    String? salaryEmployeeId,
  }) async {
    final signature = jsonEncode([
      tenant,
      business,
      outlet,
      products,
      productCreation,
      suppliers,
      purchases,
      storage,
      sales,
      customers,
      salaryAccess,
      attendanceAccess,
      staffKhataAccess,
      salaryEmployeeId,
    ]);
    if (_registeredScope == signature) return;
    sync.beginScopeChange();
    tenantId = tenant;
    businessId = business;
    outletId = outlet;
    final local = _local;
    if (local == null) return;
    await local.db.update(
      'sync_queries',
      {'active': 0},
      where:
          "collectionName NOT IN ('user','roles','permissions','app_config')",
    );
    await _register(local, 'user', {'id': sync.accountUid ?? tenant});
    if (tenant == sync.accountUid) {
      for (final c in ['roles', 'permissions']) {
        await _register(local, c, {'filters': encodeFilters([])});
      }
      await _register(local, 'businesses', {
        'filters': encodeFilters([
          FirestoreFilter('ownerUid', 'EQUAL', tenant),
        ]),
      });
      await _register(local, 'employees', {
        'filters': encodeFilters([
          FirestoreFilter('ownerUid', 'EQUAL', tenant),
        ]),
      });
    } else {
      await _register(local, 'businesses', {'id': business});
      await _register(local, 'employees', {
        'filters': encodeFilters([
          FirestoreFilter('uid', 'EQUAL', sync.accountUid ?? tenant),
        ]),
      });
    }
    if ((staffKhataAccess || attendanceAccess) && tenant != sync.accountUid) {
      await _register(local, 'employees', {
        'filters': encodeFilters([
          FirestoreFilter('ownerUid', 'EQUAL', tenant),
        ]),
      });
    }
    await _register(local, 'outlets', {
      'filters': encodeFilters([
        FirestoreFilter('businessId', 'EQUAL', business),
      ]),
    });
    for (final c in ['business_types', 'business_sub_types']) {
      await _register(local, c, {'filters': encodeFilters([])});
    }
    if (products || productCreation || purchases || sales) {
      for (final collection in catalogueCollections) {
        await _register(local, collection, {
          'filters': encodeFilters([
            const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
            // Include INACTIVE records to replace previously cached ACTIVE records.
          ]),
        });
        if (collection == 'product_catalogue_releases') continue;
        await _register(local, collection, {
          'filters': encodeFilters([
            FirestoreFilter('tenantId', 'EQUAL', tenant),
            FirestoreFilter('businessId', 'EQUAL', business),
          ]),
        });
      }
    }
    if (productCreation) {
      await local.db.transaction((tx) async {
        await tx.delete(
          'sync_queries',
          where: 'collectionName=?',
          whereArgs: [CentralProductMasterContract.previousCollection],
        );
      });
      if (kDebugMode) {
        debugPrint(
          '[startup] Registering ${CentralProductMasterContract.collection}',
        );
      }
      await _register(local, CentralProductMasterContract.collection, {
        'filters': const [],
      });
      if (kDebugMode) {
        debugPrint(
          '[startup] Registered ${CentralProductMasterContract.collection}',
        );
      }
    }
    final collections = <String>{
      if (products || productCreation || purchases || sales) ...[
        'products',
        'product_variants',
        // Business-wide (not outlet-filtered) so switching outlets is a pure
        // SQLite filter with no new remote query.
        'outlet_products',
      ],
      if (productCreation || purchases || sales) 'document_sequences',
      if (productCreation) 'product_unique_keys',
      if (suppliers || purchases) ...[
        'supplier_businesses',
        'supplier_products',
        'supplier_balances',
        'supplier_ledger_entries',
      ],
      if (storage || purchases || sales) ...[
        'godowns',
        'godown_code_reservations',
        'racks',
        'shelves',
        'stock_balances',
        'inventory_transactions',
        'stock_movements',
      ],
      if (productCreation) ...['product_costs', 'product_audit'],
      if (productCreation || storage) 'inventory_settings',
      if (outlet != null && (purchases || sales)) ...[
        'purchase_bills',
        'purchase_orders',
        'purchase_order_items',
        'goods_receipts',
        'goods_receipt_items',
        'purchase_bill_items',
        'purchase_corrections',
        'inventory_batch_movements',
        'inventory_batches',
        'supplier_payments',
        'supplier_credits',
        'payment_allocations',
        'purchase_returns',
        'purchases',
      ],
      if (outlet != null && (suppliers || purchases || sales)) ...[
        'supplier_refunds',
        'financial_transactions',
      ],
      if (outlet != null && sales) ...['invoices'],
      if (outlet != null && (customers || sales)) ...[
        'customers',
        'customer_balances',
      ],
      'expenses',
      if (salaryAccess) ...[
        'employee_salary_profiles',
        'employee_outlet_allocations',
        'staff_khata_transactions',
        'salary_periods',
      ],
      if (attendanceAccess) ...['staff_attendance', 'staff_attendance_events'],
      'business_settings',
    };
    for (final collection in collections) {
      await _register(local, collection, {
        'filters': encodeFilters([
          FirestoreFilter('tenantId', 'EQUAL', tenant),
          FirestoreFilter('businessId', 'EQUAL', business),
          if (outlet != null &&
              [
                'purchase_bills',
                'purchase_bill_items',
                'purchase_corrections',
                'supplier_refunds',
                'financial_transactions',
                if (salaryAccess) 'staff_khata_transactions',
                'inventory_batch_movements',
                'goods_receipts',
                'inventory_batches',
                'stock_balances',
                'inventory_transactions',
                'invoices',
                'customer_balances',
                'purchases',
                'stock_movements',
                'staff_attendance',
                'staff_attendance_events',
              ].contains(collection))
            FirestoreFilter('outletId', 'EQUAL', outlet),
          if (salaryAccess &&
              salaryEmployeeId != null &&
              [
                'employee_salary_profiles',
                'employee_outlet_allocations',
                'staff_khata_transactions',
                'salary_periods',
                'staff_attendance',
                'staff_attendance_events',
              ].contains(collection))
            FirestoreFilter('employeeId', 'EQUAL', salaryEmployeeId),
          if (collection == 'financial_transactions' && !salaryAccess) ...[
            const FirestoreFilter('transactionType', 'NOT_IN', [
              'SALARY_PAYMENT',
              'STAFF_ADVANCE',
            ]),
          ],
        ]),
      });
    }
    if (outlet != null && (products || productCreation)) {
      // Outlet backfill must establish that its evidence scan covers every
      // outlet in the business. Keep these business-wide cursors alongside
      // the normal outlet-filtered operational queries; both are scoped to the
      // same tenant and business.
      for (final collection in const [
        'products',
        'product_variants',
        'outlet_products',
        'stock_balances',
        'inventory_transactions',
        'goods_receipt_items',
        'purchase_order_items',
      ]) {
        await _register(local, collection, {
          'filters': encodeFilters([
            FirestoreFilter('tenantId', 'EQUAL', tenant),
            FirestoreFilter('businessId', 'EQUAL', business),
          ]),
        });
      }
    }
    if (suppliers || purchases) {
      await _register(local, 'suppliers', {
        'filters': encodeFilters([
          FirestoreFilter('tenantId', 'EQUAL', tenant),
        ]),
      });
    }
    _registeredScope = signature;
    sync.schedule(pull: true, reason: 'SCOPE_CHANGE');
  }

  /// True when every collection's tenant+business sync query has completed at
  /// least once, i.e. local data is a faithful copy of the remote scope.
  Future<bool> hasCompletedInitialSync(
    String tenant,
    String business,
    List<String> collections,
  ) async {
    final local = _local;
    if (local == null) return false;
    final spec = {
      'filters': encodeFilters([
        FirestoreFilter('tenantId', 'EQUAL', tenant),
        FirestoreFilter('businessId', 'EQUAL', business),
      ]),
    };
    for (final collection in collections) {
      final rows = await local.db.query(
        'sync_queries',
        where: 'queryKey=? AND lastSyncedAt IS NOT NULL',
        whereArgs: [SyncQueryRegistry.key(collection, spec)],
      );
      if (rows.isEmpty) return false;
    }
    return true;
  }

  Future<bool> isMigrationDone(String key) async {
    final local = _local;
    if (local == null) return false;
    return (await local.db.query(
      'local_migration_markers',
      where: 'markerKey=?',
      whereArgs: [key],
    )).isNotEmpty;
  }

  Future<void> markMigrationDone(String key) async {
    final local = _local;
    if (local == null) return;
    await local.db.insert('local_migration_markers', {
      'markerKey': key,
      'completedAt': LocalDataSource.now(),
    });
  }

  @override
  Future<void> ensureProductScopeReady(String tenant, String business) async {
    final local = _local;
    if (local == null) throw const AppException('Select a workspace first.');
    final businessRow = await local.row('businesses', business);
    if (businessRow?['syncStatus'] == 'PENDING_CREATE') return;
    for (final collection in [
      'products',
      'product_variants',
      'document_sequences',
      'product_unique_keys',
    ]) {
      final spec = {
        'filters': encodeFilters([
          FirestoreFilter('tenantId', 'EQUAL', tenant),
          FirestoreFilter('businessId', 'EQUAL', business),
        ]),
      };
      final rows = await local.db.query(
        'sync_queries',
        where: 'queryKey=? AND lastSyncedAt IS NOT NULL',
        whereArgs: [SyncQueryRegistry.key(collection, spec)],
      );
      if (rows.isEmpty) {
        throw const AppException(
          'Complete the initial product synchronization before creating offline products.',
          code: 'initial-sync-required',
        );
      }
    }
  }

  Future<List<CentralProductMaster>> searchCentralProductMaster({
    required String query,
    required String businessTypeId,
    required String businessSubTypeId,
    int limit = 20,
  }) async {
    final normalized = query.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final catalogueNormalized = normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length < 2 ||
        catalogueNormalized.length < 2 ||
        businessTypeId.isEmpty ||
        businessSubTypeId.isEmpty) {
      return const [];
    }
    final local = _local;
    if (local == null) {
      throw const AppException(
        'Local product catalogue is not available. Open the workspace and sync.',
        code: 'local-catalogue-unavailable',
      );
    }
    final escaped = normalized
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final catalogueEscaped = catalogueNormalized
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await local.db.rawQuery(
      "SELECT master_product_id, payload_json "
      'FROM local_central_product_master '
      "WHERE (normalized_product_name LIKE ? ESCAPE '\\' "
      "OR normalized_product_name LIKE ? ESCAPE '\\') "
      "AND business_type_id=? AND business_sub_type_id=? "
      "AND source_collection=? "
      "AND scope_type='SYSTEM' AND status='ACTIVE' AND is_active=1 "
      'ORDER BY normalized_product_name LIMIT ?',
      [
        '$escaped%',
        '$catalogueEscaped%',
        businessTypeId,
        businessSubTypeId,
        CentralProductMasterContract.collection,
        limit,
      ],
    );
    return [
      for (final row in rows)
        CentralProductMaster.fromData(
          row['master_product_id'] as String,
          FirestoreRestService.decodeFields(
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
          ),
        ),
    ];
  }

  @override
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    final local = await _source(idToken);
    final cached = await local.row(collection, id);
    final registered = bootstrap.contains(collection)
        ? await _register(
            local,
            collection,
            {'id': id},
            active: const [
              'user',
              'roles',
              'permissions',
              'app_config',
              'employees',
            ].contains(collection),
          )
        : false;
    if (cached != null && cached['isDeleted'] == 0) {
      return LocalDataSource.document(cached, collection);
    }
    if (cached?['isDeleted'] == 1 || registered && cached == null) {
      throw const AppException('Document not found.', code: 'not-found');
    }
    if (bootstrap.contains(collection)) {
      if (!sync.connectivity.available) {
        throw const AppException(
          'This account must be opened online once before offline use.',
          code: 'network',
        );
      }
      try {
        await _readOnce<Map<String, dynamic>>('$collection/$id', () async {
          final fresh = await local.row(collection, id);
          if (fresh != null && fresh['isDeleted'] == 0) {
            return LocalDataSource.document(fresh, collection);
          }
          final key = SyncQueryRegistry.key(collection, {'id': id});
          final completed = await local.db.query(
            'sync_queries',
            where: 'queryKey=? AND lastSyncedAt IS NOT NULL',
            whereArgs: [key],
          );
          if (completed.isNotEmpty) {
            throw const AppException('Document not found.', code: 'not-found');
          }
          await sync.checkRemoteAllowed(local);
          Map<String, dynamic> doc;
          try {
            doc = await runZoned(
              () => remote.getDocument(collection, id, idToken: idToken),
              zoneValues: {
                #firestoreReadContext: 'BOOTSTRAP query=$key cursor=none',
              },
            );
          } on AppException catch (e) {
            if (e.code == 'not-found') {
              await local.db.update(
                'sync_queries',
                {'lastSyncedAt': LocalDataSource.now()},
                where: 'queryKey=?',
                whereArgs: [key],
              );
            }
            rethrow;
          }
          await local.db.transaction((tx) async {
            await local.upsertRemote(collection, [doc], executor: tx);
            await tx.update(
              'sync_queries',
              {'lastSyncedAt': LocalDataSource.now()},
              where: 'queryKey=?',
              whereArgs: [key],
            );
          });
          return doc;
        });
      } catch (e) {
        await sync.recordRemoteFailure(local, e);
        rethrow;
      }
      return LocalDataSource.document(
        (await local.row(collection, id))!,
        collection,
      );
    }
    throw const AppException(
      'Record not available locally. Sync and retry.',
      code: 'not-found',
    );
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
    final local = await _source(idToken);
    final boot = bootstrap.contains(collection);
    final covered =
        boot && await _coveredByInitializedQuery(local, collection, filters);
    if (covered) {
      return local.query(
        collection,
        filters,
        orderBy: orderBy,
        limit: limit,
        descending: descending,
      );
    }
    final registered = boot
        ? await _register(
            local,
            collection,
            {'filters': encodeFilters(filters)},
            active: const [
              'user',
              'roles',
              'permissions',
              'app_config',
              'employees',
            ].contains(collection),
          )
        : true;
    // Cached bootstrap data returns immediately on restart. First login must
    // establish server-authorized context instead of treating a miss as absence.
    if (!registered && bootstrap.contains(collection)) {
      try {
        final key = SyncQueryRegistry.key(collection, {
          'filters': encodeFilters(filters),
        });
        await _readOnce<void>(key, () async {
          final completed = await local.db.query(
            'sync_queries',
            where: 'queryKey=? AND lastSyncedAt IS NOT NULL',
            whereArgs: [key],
          );
          if (completed.isNotEmpty) return;
          await sync.checkRemoteAllowed(local);
          final docs = <Map<String, dynamic>>[];
          String? serverTime;
          Map<String, dynamic>? after;
          for (var page = 0; page < 500; page++) {
            final result = await remote.readSyncPage(
              collection: collection,
              filters: filters,
              queryId: key,
              reason: 'BOOTSTRAP_INITIAL',
              readTime: serverTime,
              after: after,
              idToken: idToken,
            );
            serverTime ??= result.readTime;
            docs.addAll(result.documents);
            if (result.documents.length < 200) break;
            if (page == 499) {
              throw const AppException(
                'Bootstrap page limit exceeded.',
                code: 'page-limit',
              );
            }
            after = result.documents.last;
          }
          await local.db.transaction((tx) async {
            await local.upsertRemote(
              collection,
              docs,
              completeQuery: filters,
              executor: tx,
            );
            await tx.update(
              'sync_queries',
              {'lastSyncedAt': LocalDataSource.now(), 'cursor': serverTime},
              where: 'queryKey=?',
              whereArgs: [key],
            );
          });
        });
      } on AppException catch (e) {
        await sync.recordRemoteFailure(local, e);
        if (e.code != 'network' &&
            e.code != '429' &&
            e.code != 'quota-cooldown') {
          rethrow;
        }
        if ((await local.query(collection, filters)).isEmpty) rethrow;
      }
    }
    return local.query(
      collection,
      filters,
      orderBy: orderBy,
      limit: limit,
      descending: descending,
    );
  }

  /// Reads only the already-open local SYSTEM catalogue and its query markers.
  /// This diagnostic path never registers queries or contacts Firestore.
  Future<
    ({
      Map<String, List<Map<String, dynamic>>> documents,
      List<Map<String, Object?>> queries,
    })?
  >
  readCatalogueDiagnostics() async {
    final local = _local;
    if (local == null) return null;
    final documents = <String, List<Map<String, dynamic>>>{};
    for (final collection in SystemCatalogueMetadata.collections) {
      documents[collection] = await local.query(collection, const [
        FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
      ]);
    }
    final queries = <Map<String, Object?>>[];
    for (final row in await local.db.query(
      'sync_queries',
      where:
          'collectionName IN (${List.filled(SystemCatalogueMetadata.collections.length, '?').join(',')})',
      whereArgs: SystemCatalogueMetadata.collections.toList(),
    )) {
      final decoded = <String, Object?>{};
      for (final key in [
        'collectionName',
        'lastSyncedAt',
        'lastAttemptAt',
        'catalogueVersion',
        'active',
        'lastError',
      ]) {
        decoded[key] = row[key];
      }
      queries.add(decoded);
    }
    return (documents: documents, queries: queries);
  }

  @override
  Future<List<Map<String, dynamic>>> queryEqual(
    String collection,
    String field,
    Object value, {
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: [FirestoreFilter(field, 'EQUAL', value)],
    idToken: idToken,
  );
  @override
  Future<List<Map<String, dynamic>>> runQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
    idToken: idToken,
  );
  @override
  Future<List<Map<String, dynamic>>> listDocuments(
    String collection, {
    String? idToken,
  }) => queryDocuments(collection: collection, filters: [], idToken: idToken);
  @override
  Future<Map<String, dynamic>> aggregateDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) async {
    final docs = await queryDocuments(
      collection: collection,
      filters: filters,
      idToken: idToken,
    );
    num total = 0;
    if (sumField != null) {
      for (final d in docs) {
        final value = FirestoreRestService.decodeFields(d['fields'])[sumField];
        if (value is num) total += value;
      }
    }
    return {'count': docs.length, if (sumField != null) 'total': total};
  }

  @override
  Future<Map<String, dynamic>> runAggregationQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) => aggregateDocuments(
    collection: collection,
    filters: filters,
    sumField: sumField,
    idToken: idToken,
  );
  /// Direct reference to the server transaction service for online-only financial operations.
  FirestoreTransactionService get serverTransactions => remote;

  /// Exposes the local cached data source for read-only query display.
  LocalDataSource? get localDataSource => _local;

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    final local = await _source(idToken);
    final result = await local.db.transaction((tx) async {
      final context = LocalTransactionContext(local, tx);
      final value = await action(context);
      if (context.writes.length > 500) {
        throw const AppException('Atomic operation exceeds 500 writes.');
      }

      // Hard check: Financial operations require confirmed server transaction
      for (final write in context.writes.values) {
        final col = write['collection'] as String?;
        if (SyncOutboxRepository.financialCollections.contains(col)) {
          throw const AppException(
            'Financial transactions must be confirmed directly by the server and cannot run in offline mode.',
            code: 'offline-financial-prohibited',
          );
        }
      }

      final outbox = SyncOutboxRepository(local);
      for (final write in context.writes.values) {
        // Capture baselines even for simple service writes that did not call get.
        final key = '${write['collection']}/${write['id']}';
        if (!context.reads.containsKey(key)) {
          await context.get(
            write['collection'] as String,
            write['id'] as String,
          );
        }
      }
      for (final write in context.writes.values) {
        final fields = FirestoreRestService.decodeFields(write['fields']);
        for (final reference in {
          'businessId': 'businesses',
          'outletId': 'outlets',
        }.entries) {
          final referenceId = fields[reference.key] as String?;
          if (referenceId == null ||
              context.writes.containsKey('${reference.value}/$referenceId')) {
            continue;
          }
          final referenced = await local.row(
            reference.value,
            referenceId,
            executor: tx,
          );
          if (referenced != null && referenced['syncStatus'] != 'SYNCED') {
            await context.get(reference.value, referenceId);
          }
        }
      }
      for (final write in context.writes.values) {
        await outbox.enqueue(tx, context.batchId, write, context.reads);
      }
      return value;
    });
    sync.pendingCount = await SyncOutboxRepository(local).pendingCount();
    sync.state = sync.connectivity.available
        ? SyncState.pending
        : SyncState.offline;
    sync.notifyLocalWrite();
    return result;
  }

  @override
  Future<void> createDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    if (idToken == null) throw const AppException('Sign in before saving.');
    await runAtomicOperation((tx) async {
      tx.create(collection, id, fields);
    }, idToken: idToken);
  }

  @override
  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    if (idToken == null) throw const AppException('Sign in before saving.');
    await runAtomicOperation((tx) async {
      final row = await tx.get(collection, id);
      tx.update(collection, id, fields, updateTime: row.updateTime);
    }, idToken: idToken);
  }

  @override
  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) => updateDocument(collection, id, fields, idToken: idToken);
  @override
  Future<void> deleteDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    if (idToken == null) throw const AppException('Sign in before saving.');
    await runAtomicOperation((tx) async {
      final row = await tx.get(collection, id);
      tx.delete(collection, id, updateTime: row.updateTime);
    }, idToken: idToken);
  }
}
