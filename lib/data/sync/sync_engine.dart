import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../catalogue/system_catalogue_metadata.dart';
import '../catalogue/catalogue_contract.dart';
import '../catalogue/catalogue_readiness.dart';
import '../catalogue/central_product_master_contract.dart';
import '../catalogue/system_catalogue_snapshot.dart';
import 'sync_query_registry.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../local/local_data_source.dart';
import '../models/auth_session_model.dart';
import '../services/firestore_rest_service.dart';
import '../services/error_analytics_service.dart';
import 'connectivity_service.dart';
import 'sync_outbox_repository.dart';

enum SyncState { synced, syncing, offline, pending, error }

class SyncEngine extends ChangeNotifier {
  SyncEngine(
    this.remote,
    this.connectivity, {
    required this.sessionProvider,
    @visibleForTesting this.allowUnapprovedIsolatedCatalogueForTests = false,
    this.errorAnalytics,
  }) : assert(!allowUnapprovedIsolatedCatalogueForTests || kDebugMode);
  final FirestoreRestService remote;
  final ConnectivityService connectivity;
  final Future<AuthSession?> Function() sessionProvider;
  final ErrorAnalyticsService? errorAnalytics;
  @visibleForTesting
  final bool allowUnapprovedIsolatedCatalogueForTests;
  final owner = IdGenerator.create('ENGINE');
  LocalDataSource? local;
  String? accountUid;
  SyncState state = SyncState.pending;
  int pendingCount = 0;
  String? error;
  String? rawDiagnosticError;
  static bool isQuotaFailure(Object? value) {
    if (value == null) return false;
    final raw = value is AppException
        ? '${value.code ?? ''} ${value.message}'
        : value.toString();
    final normalized = raw.toLowerCase().replaceAll('-', '_');
    return normalized.contains('429') ||
        normalized.contains('quota') ||
        normalized.contains('resource_exhausted');
  }

  static bool isTombstone(Map<String, dynamic>? doc) {
    final fields = FirestoreRestService.decodeFields(doc?['fields']);
    return fields['isDeleted'] == true || fields['status'] == 'DELETED';
  }

  String get customerFriendlyError =>
      ErrorAnalyticsService.sanitizeForCustomer(rawDiagnosticError ?? error);
  final changes = StreamController<void>.broadcast();
  Future<void>? _running;
  Timer? _scheduled, _retry;
  int _generation = 0;
  bool _pullRequested = false;
  bool _refreshCatalogueRequested = false;
  bool _workRequested = false;
  String _reason = 'LOGIN';
  bool _started = false;
  bool _disposed = false;
  CatalogueReadinessReport? _cachedCatalogueReadiness;

  void invalidateCatalogueReadiness() {
    _cachedCatalogueReadiness = null;
  }

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (kDebugMode) {
      debugPrint('[startup] SyncEngine.start: connectivity listener');
    }
    await connectivity.start((available) {
      if (_disposed) return;
      if (available) {
        schedule(pull: true, reason: 'RECONNECT');
      } else {
        state = SyncState.offline;
        notifyListeners();
      }
    });
    if (kDebugMode) {
      debugPrint('[startup] SyncEngine.start completed');
    }
  }

  void attach(LocalDataSource source, String uid) {
    if (accountUid != uid) _generation++;
    local = source;
    accountUid = uid;
    _cachedCatalogueReadiness = null;
    schedule(pull: true, reason: 'LOGIN');
  }

  void detach() {
    _generation++;
    _scheduled?.cancel();
    _retry?.cancel();
    _pullRequested = false;
    _refreshCatalogueRequested = false;
    _cachedCatalogueReadiness = null;
    local = null;
    accountUid = null;
    pendingCount = 0;
    state = SyncState.pending;
    notifyListeners();
  }

  void beginScopeChange() {
    _generation++;
    _scheduled?.cancel();
    _retry?.cancel();
    _workRequested = false;
    _refreshCatalogueRequested = false;
    _pullRequested = false;
    _cachedCatalogueReadiness = null;
  }

  void notifyLocalWrite() {
    notifyListeners();
    schedule();
  }

  void schedule({bool pull = false, String reason = 'OUTBOX'}) {
    if (_disposed || local == null) return;
    _workRequested = true;
    _pullRequested |= pull;
    if (pull || !_pullRequested) _reason = reason;
    _scheduled?.cancel();
    _scheduled = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(sync(pull: false)),
    );
  }

  Future<void> retry() async {
    final source = local;
    if (source == null) return;
    await SyncOutboxRepository(source).retry();
    final control = (await source.db.query(
      'sync_control',
      where: 'id=1',
      limit: 1,
    )).firstOrNull;
    final quotaFailure = isQuotaFailure(control?['lastError']);
    if (!quotaFailure) {
      await source.db.update('sync_control', {
        'cooldownUntil': null,
        'lastError': null,
        'failureCount': 0,
      }, where: 'id=1');
    }
    error = null;
    await sync();
  }

  /// Resolves conflicted or failed outbox writes by accepting the remote
  /// Firestore document, updating local storage to match, and removing the
  /// conflicting outbox entry so synchronization can resume cleanly.
  Future<void> resolveConflictedOutbox({String? batchId}) async {
    final source = local, uid = accountUid;
    if (source == null || uid == null) return;
    final session = await sessionProvider();
    if (session == null || session.uid != uid) {
      throw const AppException(
        'Connect and sign in to synchronize.',
        code: 'unauthenticated',
      );
    }

    final outbox = SyncOutboxRepository(source);
    if (!await outbox.acquire(owner)) return;

    try {
      final whereClause = batchId != null
          ? "status='FAILED' AND batchId=?"
          : "status='FAILED'";
      final whereArgs = batchId != null ? [batchId] : null;
      final failedRows = await source.db.query(
        'sync_outbox',
        where: whereClause,
        whereArgs: whereArgs,
      );
      if (failedRows.isEmpty) return;

      final batches = <String>{};
      for (final row in failedRows) {
        final bId = row['batchId'] as String;
        batches.add(bId);
        final collection = row['entityType'] as String;
        final id = row['documentId'] as String;

        Map<String, dynamic>? remoteDoc;
        try {
          remoteDoc = await remote.getDocument(
            collection,
            id,
            idToken: session.idToken,
          );
        } on AppException catch (e) {
          if (e.code != 'not-found') rethrow;
          remoteDoc = null;
        }

        await source.db.transaction((tx) async {
          if (remoteDoc != null) {
            final fields = FirestoreRestService.decodeFields(remoteDoc['fields']);
            await tx.update(
              LocalDataSource.table(collection),
              {
                'payloadJson': jsonEncode(remoteDoc['fields']),
                ...LocalDataSource.scopeColumns(fields),
                'syncStatus': 'SYNCED',
                'syncError': null,
                'remoteUpdateTime': remoteDoc['updateTime'],
                'remoteUpdatedAt': fields['updatedAt']?.toString(),
                'lastSyncedAt': LocalDataSource.now(),
                'isDeleted': isTombstone(remoteDoc) ? 1 : 0,
                'acknowledgedRevision': row['localRevision'],
              },
              where: 'remoteId=?',
              whereArgs: [id],
            );
          } else {
            await tx.update(
              LocalDataSource.table(collection),
              {
                'syncStatus': 'SYNCED',
                'syncError': null,
                'isDeleted': 1,
                'lastSyncedAt': LocalDataSource.now(),
                'acknowledgedRevision': row['localRevision'],
              },
              where: 'remoteId=?',
              whereArgs: [id],
            );
          }
        });
      }

      for (final b in batches) {
        await source.db.delete('sync_outbox', where: 'batchId=?', whereArgs: [b]);
        await source.db.update(
          'sync_conflicts',
          {'resolved': 1},
          where: 'batchId=?',
          whereArgs: [b],
        );
      }

      error = null;
      rawDiagnosticError = null;
      pendingCount = await outbox.pendingCount();
      state = pendingCount > 0 ? SyncState.pending : SyncState.synced;
      notifyListeners();
    } finally {
      await outbox.release(owner);
    }

    schedule(pull: true, reason: 'MANUAL_REFRESH');
  }

  /// Catalogue checks explicitly exclude Product/business PUSH work.
  Future<void> checkCatalogue({bool forceCheck = false}) => sync(
    pull: true,
    refreshCatalogue: forceCheck,
    push: false,
    catalogueOnly: true,
  );

  Future<void> sync({
    bool pull = true,
    bool refreshCatalogue = false,
    bool push = true,
    bool catalogueOnly = false,
  }) {
    if (_disposed) return Future<void>.value();
    _refreshCatalogueRequested |= refreshCatalogue;
    _pullRequested |= pull || refreshCatalogue;
    if (pull) _reason = 'MANUAL_REFRESH';
    if (_running != null) return _running!;
    _scheduled?.cancel();
    _retry?.cancel();
    _workRequested = false;
    final requested = _pullRequested;
    final reason = requested ? _reason : 'OUTBOX';
    final refresh = _refreshCatalogueRequested;
    _pullRequested = false;
    _refreshCatalogueRequested = false;
    final future = _sync(
      pull: requested,
      reason: reason,
      refreshCatalogue: refresh,
      push: push,
      catalogueOnly: catalogueOnly,
    );
    _running = future;
    return future.whenComplete(() {
      _running = null;
      if (local != null && (_pullRequested || _workRequested)) schedule();
    });
  }

  Future<void> _sync({
    required bool pull,
    required String reason,
    required bool refreshCatalogue,
    required bool push,
    required bool catalogueOnly,
  }) async {
    final source = local, uid = accountUid, generation = _generation;
    if (source == null || uid == null) return;
    pendingCount = await SyncOutboxRepository(source).pendingCount();
    if (!connectivity.available) {
      state = SyncState.offline;
      notifyListeners();
      return;
    }
    try {
      await checkRemoteAllowed(source);
    } on AppException catch (e) {
      error = e.message;
      state = SyncState.error;
      notifyListeners();
      return;
    }
    final outbox = SyncOutboxRepository(source);
    if (!await outbox.acquire(owner)) return;
    if (pull || reason == 'MANUAL_REFRESH' || reason == 'LOGIN') {
      await outbox.retry();
    }
    // Renew the cross-instance lease during long catalogue downloads.
    final heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(
        source.db.update(
          'sync_lease',
          {
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          },
          where: 'owner=?',
          whereArgs: [owner],
        ),
      );
    });
    state = SyncState.syncing;
    error = null;
    notifyListeners();
    bool changed = false;
    try {
      final session = await sessionProvider();
      if (session != null && session.uid == uid && session.isExpired) {
        throw const AppException(
          'Connect to refresh your session and synchronize.',
          code: 'network',
        );
      }
      if (session == null || session.uid != uid) {
        throw const AppException(
          'Connect and sign in to synchronize.',
          code: 'unauthenticated',
        );
      }
      if (push) {
        // Sequence and attendance conflicts are resolved by rebasing/reconciliation,
        // so those batches are safe to retry automatically.
        await source.db.update(
          'sync_outbox',
          {'status': 'PENDING', 'lastError': null},
          where:
              "status='FAILED' AND (lastError LIKE 'Remote version changed for document_sequences/%' OR lastError LIKE 'Remote version changed for staff_attendance/%')",
        );
      }
      var uploaded = 0;
      while (push && generation == _generation && uploaded++ < 10) {
        final batch = await outbox.nextBatch();
        if (batch.isEmpty) break;
        try {
          await runZoned(
            () => _push(source, batch, session.idToken),
            zoneValues: {
              #firestoreReadContext:
                  'OUTBOX_PUSH query=OUTBOX:${batch.first['batchId']} tenant=${batch.first['tenantId']} business=${batch.first['businessId']} outlet=${batch.first['outletId']} cursor=none',
            },
          );
          changed = true;
        } on AppException catch (exception) {
          if (!isConflict(exception)) rethrow;
          changed = true;
        }
      }
      final queries = pull
          ? await source.db.query(
              'sync_queries',
              where: 'active=1',
              orderBy: "CASE WHEN collectionName='product_catalogue_releases' THEN 0 ELSE 1 END, rowid",
            )
          : <Map<String, Object?>>[];
      String? pullError;
      var performedPull = false;
      String? catalogueVersion, catalogueReadTime;
      final catalogueWrites = <Future<void> Function(DatabaseExecutor)>[];
      final catalogueDocuments = <String, List<Map<String, dynamic>>>{};
      final catalogueReadTimes = <String, String>{};
      var checkedCatalogue = false;
      var normalizedRelease = false;
      Map<String, dynamic>? incomingRelease;
      final cachedReleases = await source.query('product_catalogue_releases', [
        const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
      ]);
      final installedRelease = cachedReleases
          .map((d) => FirestoreRestService.decodeFields(d['fields']))
          .where((r) => r['catalogueId'] == 'PAINT_V1')
          .firstOrNull;
      final retainedCatalogueCollections = <String>{};
      for (final query in queries) {
        if (generation != _generation) break;
        final spec =
            jsonDecode(query['queryJson'] as String) as Map<String, dynamic>;
        final collection = query['collectionName'] as String;
        final filters = decodeFilters((spec['filters'] as List?) ?? []);
        final catalogue =
            SystemCatalogueMetadata.collections.contains(collection) &&
            filters.length == 1 &&
            filters.single.field == 'scopeType' &&
            filters.single.operation == 'EQUAL' &&
            filters.single.value == 'SYSTEM' &&
            spec['id'] == null;
        if (catalogueOnly && !catalogue) continue;
        if (SystemCatalogueMetadata.collections.contains(collection) &&
            SyncQueryRegistry.legacyReferences(spec).isNotEmpty) {
          throw const AppException(
            'Protected legacy catalogue query requires Phase 8 review; no rewrite performed.',
            code: 'legacy-query-reference',
          );
        }
        final system =
            const [
              'business_types',
              'business_sub_types',
            ].contains(collection) ||
            filters.any((f) => f.field == 'scopeType' && f.value == 'SYSTEM');
        final centralMaster =
            collection == CentralProductMasterContract.collection;
        // Only the complete release pipeline can write SYSTEM catalogue rows.
        // Historical narrower queries remain registered for review, not applied.
        if (SystemCatalogueMetadata.collections.contains(collection) &&
            (spec['id'] != null || system && !catalogue)) {
          continue;
        }
        final previous = DateTime.tryParse(
          query['lastSyncedAt'] as String? ?? '',
        );
        final centralCacheCount = centralMaster
            ? Sqflite.firstIntValue(
                    await source.db.rawQuery(
                      'SELECT COUNT(*) FROM local_central_product_master '
                      'WHERE source_collection=?',
                      [CentralProductMasterContract.collection],
                    ),
                  ) ??
                  0
            : null;
        final initialized = centralMaster
            ? query['catalogueVersion'] ==
                      CentralProductMasterContract.verifiedBootstrapVersion &&
                  centralCacheCount ==
                      CentralProductMasterContract.expectedDocumentCount
            : query['cursor'] != null || spec['id'] != null && previous != null;
        if (centralMaster && kDebugMode) {
          debugPrint(
            '[startup] Verified bootstrap eligibility: initialized=$initialized '
            'localVerifiedRows=$centralCacheCount '
            'expected=${CentralProductMasterContract.expectedDocumentCount} '
            'version=${query['catalogueVersion']}',
          );
        }
        if (catalogue && collection == 'product_catalogue_releases') {
          if (!refreshCatalogue &&
              reason != 'MANUAL_REFRESH' &&
              previous != null &&
              DateTime.now().toUtc().difference(previous) <
                  const Duration(minutes: 15)) {
            catalogueVersion = query['catalogueVersion'] as String?;
            continue;
          }
          checkedCatalogue = true;
        }
        // A failed/unavailable release check never falls back to a broad pull.
        if (catalogue &&
            collection != 'product_catalogue_releases' &&
            catalogueVersion == null) {
          continue;
        }
        if (reason != 'MANUAL_REFRESH' &&
            !system &&
            initialized &&
            previous != null &&
            DateTime.now().toUtc().difference(previous) <
                const Duration(minutes: 15)) {
          continue;
        }
        if (catalogue &&
            collection != 'product_catalogue_releases' &&
            initialized &&
            incomingRelease != null &&
            installedRelease != null) {
          final remoteRevisions = incomingRelease['collectionRevisions'];
          final localRevisions = installedRelease['collectionRevisions'];
          if (remoteRevisions is Map &&
              localRevisions is Map &&
              remoteRevisions[collection] != null &&
              remoteRevisions[collection] == localRevisions[collection]) {
            retainedCatalogueCollections.add(collection);
            continue;
          }
        }
        if (system &&
            !centralMaster &&
            collection != 'product_catalogue_releases' &&
            initialized &&
            !(refreshCatalogue && !normalizedRelease) &&
            catalogueVersion != null &&
            catalogueVersion == query['catalogueVersion']) {
          continue;
        }
        if (system &&
            !centralMaster &&
            initialized &&
            !refreshCatalogue &&
            catalogueVersion == null &&
            reason != 'MANUAL_REFRESH') {
          continue;
        }
        try {
          await source.db.update(
            'sync_queries',
            {'lastAttemptAt': LocalDataSource.now(), 'lastError': null},
            where: 'queryKey=?',
            whereArgs: [query['queryKey']],
          );
          final documents = <Map<String, dynamic>>[];
          final full =
              !initialized ||
              system && collection == 'product_catalogue_releases' ||
              refreshCatalogue && system && !normalizedRelease ||
              system &&
                  !centralMaster &&
                  catalogueVersion != null &&
                  catalogueVersion != query['catalogueVersion'];
          // Pin all collections in a release to the release check's server
          // snapshot, so a concurrent publication cannot mix catalogue versions.
          String? serverTime =
              system &&
                  full &&
                  SystemCatalogueMetadata.collections.contains(collection) &&
                  collection != 'product_catalogue_releases'
              ? catalogueReadTime
              : null;
          if (spec['id'] != null) {
            try {
              documents.add(
                await runZoned(
                  () => remote.getDocument(
                    collection,
                    spec['id'] as String,
                    idToken: session.idToken,
                  ),
                  zoneValues: {
                    #firestoreReadContext:
                        '$reason query=${query['queryKey']} cursor=${query['cursor']}',
                  },
                ),
              );
            } on AppException catch (e) {
              if (e.code != 'not-found') rethrow;
              await source.markRemoteMissing(collection, spec['id'] as String);
            }
          } else {
            Map<String, dynamic>? after;
            for (var page = 0; page < 500; page++) {
              if (centralMaster && page == 0 && kDebugMode) {
                debugPrint(
                  '[startup] First remote request: ${CentralProductMasterContract.collection}',
                );
              }
              final result = await remote.readSyncPage(
                collection: collection,
                filters: filters,
                queryId: query['queryKey'] as String,
                reason: system && collection == 'product_catalogue_releases'
                    ? 'CATALOGUE_VERSION_CHECK'
                    : full
                    ? 'INITIAL_PULL'
                    : reason == 'MANUAL_REFRESH'
                    ? reason
                    : 'INCREMENTAL_PULL',
                cursor: full ? null : query['cursor'] as String?,
                readTime: serverTime,
                after: after,
                idToken: session.idToken,
              );
              serverTime ??= result.readTime;
              documents.addAll(result.documents);
              if (result.documents.length < 200) break;
              if (page == 499) {
                throw const AppException(
                  'Synchronization page limit exceeded; cursor unchanged.',
                  code: 'page-limit',
                );
              }
              after = result.documents.last;
            }
          }
          if (centralMaster && kDebugMode) {
            debugPrint(
              '[startup] Verified source fetch complete: ${documents.length} document(s)',
            );
          }
          if (generation != _generation) break;
          performedPull = true;
          if (collection == 'product_catalogue_releases' && system) {
            incomingRelease = documents
                .map((d) => FirestoreRestService.decodeFields(d['fields']))
                .where(
                  (r) =>
                      r['catalogueId'] == 'PAINT_V1' &&
                      r['status'] == 'ACTIVE' &&
                      r['published'] != false,
                )
                .firstOrNull;
            normalizedRelease = incomingRelease != null;
            if (incomingRelease != null) {
              CatalogueContract.validateRevision(incomingRelease);
            }
            catalogueVersion = SystemCatalogueMetadata.fingerprint(documents);
            catalogueReadTime = serverTime;
          }
          final version = catalogueVersion;
          Future<void> applyQuery(DatabaseExecutor tx) async {
            final active = await tx.query(
              'sync_queries',
              where: 'queryKey=? AND active=1',
              whereArgs: [query['queryKey']],
            );
            if (active.isEmpty) return;
            if (SystemCatalogueMetadata.collections.contains(collection)) {
              for (final doc in documents) {
                final id = (doc['name'] as String).split('/').last;
                final old = await source.row(collection, id, executor: tx);
                final scope = FirestoreRestService.decodeFields(
                  doc['fields'],
                )['scopeType'];
                if (scope == 'SYSTEM' && !catalogue) {
                  throw const AppException(
                    'SYSTEM catalogue rows require the complete release pipeline.',
                    code: 'catalogue-release',
                  );
                }
                if (old != null && old['scopeType'] != scope) {
                  throw const AppException(
                    'SYSTEM/BUSINESS catalogue document ID collision.',
                    code: 'catalogue-collision',
                  );
                }
              }
            }
            if (centralMaster) {
              if (full && kDebugMode) {
                debugPrint(
                  '[startup] Starting verified SQLite replacement transaction',
                );
              }
              if (full) {
                await source.replaceCentralProductMasters(
                  documents,
                  executor: tx,
                );
              } else {
                await source.upsertCentralProductMasters(
                  documents,
                  executor: tx,
                );
              }
            } else {
              await source.upsertRemote(
                collection,
                documents,
                completeQuery: full && spec['id'] == null ? filters : null,
                executor: tx,
              );
            }
            await tx.update(
              'sync_queries',
              {
                'lastSyncedAt': LocalDataSource.now(),
                'cursor': ?serverTime,
                if (centralMaster)
                  'catalogueVersion':
                      CentralProductMasterContract.verifiedBootstrapVersion,
                if (system && !centralMaster) 'catalogueVersion': version,
              },
              where: 'queryKey=?',
              whereArgs: [query['queryKey']],
            );
          }

          if (catalogue &&
              !normalizedRelease &&
              collection != 'product_catalogue_releases' &&
              documents.any(
                (d) =>
                    FirestoreRestService.decodeFields(
                      d['fields'],
                    )['catalogueId'] ==
                    'PAINT_V1',
              )) {
            throw const AppException(
              'PAINT_V1 rows require a published versioned release; prior local catalogue retained.',
              code: 'catalogue-release',
            );
          }
          if (catalogue) {
            catalogueDocuments[collection] = documents;
            if (serverTime != null) catalogueReadTimes[collection] = serverTime;
            catalogueWrites.add(applyQuery);
          } else {
            await source.db.transaction(applyQuery);
            if (centralMaster && full && kDebugMode) {
              final localCount =
                  Sqflite.firstIntValue(
                    await source.db.rawQuery(
                      'SELECT COUNT(*) FROM local_central_product_master '
                      'WHERE source_collection=?',
                      [CentralProductMasterContract.collection],
                    ),
                  ) ??
                  0;
              debugPrint(
                '[startup] Verified SQLite replacement committed: localCount=$localCount',
              );
            }
          }
          if (documents.isNotEmpty || full) changed = true;
        } catch (e) {
          final queryKey = query['queryKey'] as String?;
          final collName = query['collectionName'] as String?;
          rawDiagnosticError = e.toString();
          pullError = e.toString();
          if (kDebugMode) {
            debugPrint(
              '[sync] pull failed collection=$collName '
              'queryKey=$queryKey query=${query['queryJson']} '
              'cursor=${query['cursor']} error=$e',
            );
          }
          await source.db.update(
            'sync_queries',
            {'lastError': rawDiagnosticError},
            where: 'queryKey=?',
            whereArgs: [queryKey],
          );
          await recordRemoteFailure(
            source,
            e,
            collection: collName,
            location: 'Pull query: $queryKey ($collName)',
          );
          break;
        }
      }
      if (pullError == null &&
          generation == _generation &&
          catalogueWrites.isNotEmpty) {
        final releases = catalogueDocuments['product_catalogue_releases'] ?? [];
        final normalized = releases.any(
          (d) =>
              FirestoreRestService.decodeFields(d['fields'])['catalogueId'] ==
              'PAINT_V1',
        );
        if (normalized &&
            (catalogueDocuments.length > 1 ||
                retainedCatalogueCollections.isNotEmpty)) {
          for (final collection in retainedCatalogueCollections) {
            catalogueDocuments[collection] = await source.query(collection, [
              const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
            ]);
          }
          if (!SystemCatalogueSnapshot.requiredCollections.every(
            catalogueDocuments.containsKey,
          )) {
            throw const AppException(
              'Release pull is incomplete; installed catalogue and cursors unchanged.',
              code: 'catalogue-release',
            );
          }
          await SystemCatalogueSnapshot.import(
            source: source,
            documents: catalogueDocuments,
            readTimes: catalogueReadTimes,
            preserveSyncQueries: false,
            allowUnapprovedIsolatedForTests:
                allowUnapprovedIsolatedCatalogueForTests,
          );
        } else if (normalized) {
          // Unchanged release: keep compiled local marker/content fingerprint.
          // Only the lightweight check's durable cursor/time can advance.
          await source.db.transaction((tx) async {
            final localRelease = await tx.query(
              LocalDataSource.table('product_catalogue_releases'),
              where: "scopeType='SYSTEM' AND isDeleted=0",
            );
            if (incomingRelease != null &&
                installedRelease != null &&
                ((incomingRelease['catalogueVersion'] ??
                            incomingRelease['version']) !=
                        (installedRelease['catalogueVersion'] ??
                            installedRelease['version']) ||
                    (incomingRelease['compilerRevision'] ??
                            SystemCatalogueMetadata.revision) !=
                        (installedRelease['compilerRevision'] ??
                            SystemCatalogueMetadata.revision))) {
              throw const AppException(
                'New release requires a complete payload; marker unchanged.',
                code: 'catalogue-release',
              );
            }
            if (localRelease.isEmpty) {
              throw const AppException(
                'Initial catalogue release requires complete payload.',
                code: 'catalogue-release',
              );
            }
            for (final query in queries.where(
              (q) => q['collectionName'] == 'product_catalogue_releases',
            )) {
              if (checkedCatalogue) {
                await tx.update(
                  'sync_queries',
                  {
                    'lastSyncedAt': LocalDataSource.now(),
                    'lastError': null,
                    'cursor': catalogueReadTime,
                    'catalogueVersion': catalogueVersion,
                  },
                  where: 'queryKey=? AND active=1',
                  whereArgs: [query['queryKey']],
                );
              }
            }
          });
        } else {
          // Other SYSTEM bootstrap catalogues retain ordinary cursor semantics;
          // the PAINT compiler never assigns them guessed paint profiles.
          await source.db.transaction((tx) async {
            for (final apply in catalogueWrites) {
              await apply(tx);
            }
          });
        }
      }
      if (performedPull && (catalogueWrites.isNotEmpty || checkedCatalogue)) {
        _cachedCatalogueReadiness = null;
      }
      if (performedPull && pullError == null && generation == _generation) {
        await source.db.update('sync_control', {
          'lastPullAt': LocalDataSource.now(),
          'failureCount': 0,
          'cooldownUntil': null,
          'lastError': null,
        }, where: 'id=1');
      }
      if (uploaded > 10) schedule();
      pendingCount = await outbox.pendingCount();
      final failed = await source.db.query(
        'sync_outbox',
        where: "status='FAILED'",
        limit: 1,
      );
      final rawOutboxError = failed.isEmpty
          ? null
          : failed.single['lastError'] as String?;
      if (rawOutboxError != null) {
        rawDiagnosticError ??= rawOutboxError;
      }
      final controlRow = (await source.db.query(
        'sync_control',
        where: 'id=1',
        limit: 1,
      )).firstOrNull;
      final controlLastError = controlRow?['lastError'] as String?;

      // Deep catalogue readiness verification
      String? catalogueReadinessError;
      if (pullError == null && controlLastError == null) {
        if (_cachedCatalogueReadiness == null ||
            !_cachedCatalogueReadiness!.isReady) {
          final readinessReport =
              await CatalogueReadiness.checkInstalledReadiness(
                source,
                allowUnapprovedIsolatedForTests:
                    allowUnapprovedIsolatedCatalogueForTests,
              );
          if (readinessReport != null) {
            if (readinessReport.isReady) {
              _cachedCatalogueReadiness = readinessReport;
            } else {
              _cachedCatalogueReadiness = null;
              catalogueReadinessError = readinessReport.errors.isNotEmpty
                  ? '[catalogue-readiness] ${readinessReport.errors.join(' ')}'
                  : '[catalogue-readiness] Incomplete SYSTEM catalogue.';
            }
          }
        }
      }

      error =
          pullError ??
          (failed.isEmpty ? null : failed.single['lastError'] as String?) ??
          controlLastError ??
          catalogueReadinessError;
      state = error != null
          ? SyncState.error
          : pendingCount > 0
          ? SyncState.pending
          : SyncState.synced;
    } catch (e) {
      rawDiagnosticError = e.toString();
      await recordRemoteFailure(
        source,
        e,
        location: '_sync main loop exception',
      );
      error = e.toString();
      pendingCount = await outbox.pendingCount();
      state = e is AppException && e.code == 'network'
          ? SyncState.offline
          : SyncState.error;
    } finally {
      heartbeat.cancel();
      await outbox.release(owner);
      if (generation == _generation) {
        if (changed) changes.add(null);
        notifyListeners();
      } else {
        schedule();
      }
    }
  }

  Future<void> onResume() async {
    final source = local;
    if (source == null) return;
    final rows = await source.db.query('sync_control', where: 'id=1');
    final previous = DateTime.tryParse(
      rows.single['lastPullAt'] as String? ?? '',
    );
    schedule(
      pull:
          previous == null ||
          DateTime.now().toUtc().difference(previous) >=
              const Duration(minutes: 15),
      reason: 'RESUME',
    );
  }

  Future<void> checkRemoteAllowed(LocalDataSource source) async {
    final row = (await source.db.query('sync_control', where: 'id=1')).single;
    final until = DateTime.tryParse(row['cooldownUntil'] as String? ?? '');
    if (until != null && DateTime.now().toUtc().isBefore(until)) {
      throw AppException(
        'Remote synchronization paused until ${until.toIso8601String()}. SQLite data and Pending writes remain available. ${row['lastError'] ?? ''}',
        code: 'quota-cooldown',
      );
    }
  }

  Future<void> recordRemoteFailure(
    LocalDataSource source,
    Object exception, {
    String? collection,
    String? location,
    Map<String, dynamic>? metadata,
  }) async {
    if (exception is AppException &&
        (exception.code == 'quota-cooldown' ||
            exception.code == 'not-found' ||
            isConflict(exception))) {
      return;
    }

    final rawErrStr = exception is AppException && exception.code != null
        ? '[${exception.code}] ${exception.message}'
        : exception.toString();
    rawDiagnosticError = rawErrStr;

    // Report to Error Analytics (which extracts index URL, determines which/where/what, and persists to Firestore)
    try {
      unawaited(
        errorAnalytics?.recordError(
          component: 'SyncEngine',
          location: location ?? 'Remote synchronization routine',
          error: exception,
          collection: collection,
          businessId: metadata?['businessId'] as String?,
          tenantId: metadata?['tenantId'] as String?,
          outletId: metadata?['outletId'] as String?,
          metadata: metadata,
        ),
      );
    } catch (_) {}

    final row = (await source.db.query('sync_control', where: 'id=1')).single;
    final attempts = ((row['failureCount'] as int) + 1).clamp(1, 12);
    final quota = isQuotaFailure(exception);
    final auth =
        exception is AppException &&
        const ['unauthenticated', 'permission-denied'].contains(exception.code);
    final seconds = auth
        ? 3600
        : quota
        ? (3600 * (1 << (attempts - 1))).clamp(3600, 86400)
        : (5 * (1 << (attempts - 1))).clamp(5, 900);
    await source.db.update('sync_control', {
      'failureCount': attempts,
      'cooldownUntil': DateTime.now()
          .toUtc()
          .add(Duration(seconds: seconds))
          .toIso8601String(),
      'lastError': rawErrStr,
    }, where: 'id=1');
    _retry?.cancel();
    if (!_disposed && identical(local, source) && pendingCount > 0) {
      final generation = _generation;
      _retry = Timer(Duration(seconds: seconds), () {
        if (!_disposed &&
            generation == _generation &&
            identical(local, source)) {
          schedule();
        }
      });
    }
  }

  static List<FirestoreFilter> decodeFilters(List raw) => [
    for (final f in raw)
      FirestoreFilter(
        f['field'] as String,
        f['operation'] as String,
        FirestoreRestService.decodeValue(f['value']) as Object,
      ),
  ];
  Future<void> _push(
    LocalDataSource source,
    List<Map<String, Object?>> rows,
    String token,
  ) async {
    final batch = rows.first['batchId'] as String;
    await source.db.rawUpdate(
      "UPDATE sync_outbox SET status='PROCESSING',attemptCount=attemptCount+1,lastAttemptAt=? WHERE batchId=?",
      [LocalDataSource.now(), batch],
    );
    final writes = [
      for (final row in rows)
        jsonDecode(row['payloadJson'] as String) as Map<String, dynamic>,
    ];
    final remoteDocs = <String, Map<String, dynamic>?>{};
    bool tombstone(Map<String, dynamic>? doc) => isTombstone(doc);

    Future<Map<String, dynamic>?> get(String collection, String id) async {
      final key = '$collection/$id';
      if (remoteDocs.containsKey(key)) return remoteDocs[key];
      try {
        final doc = await remote.getDocument(collection, id, idToken: token);
        final cached = await source.row(collection, id);
        if (cached == null || cached['syncStatus'] == 'SYNCED') {
          await source.upsertRemote(collection, [doc]);
        }
        return remoteDocs[key] = doc;
      } on AppException catch (e) {
        if (e.code == 'not-found') return remoteDocs[key] = null;
        rethrow;
      }
    }

    bool isRestoreMutation(
      Map<String, dynamic> write,
      Map<String, dynamic>? doc,
    ) {
      if (write['operation'] != 'UPDATE') return false;
      if (doc == null) return false;
      final decoded = FirestoreRestService.decodeFields(write['fields']);
      final isActivating =
          decoded['isDeleted'] == false || decoded['status'] == 'ACTIVE';
      if (!isActivating) return false;
      return tombstone(doc) ||
          doc['fields']?['status']?['stringValue'] == 'ACTIVE';
    }

    try {
      // An acknowledged response may have been lost, or the app may have died
      // after commit. Verify the WHOLE atomic batch before treating it as done.
      bool alreadyApplied = true;
      for (final w in writes) {
        final doc = await get(w['collection'] as String, w['id'] as String);
        final fields = doc?['fields'] as Map?;
        final isAttendanceApproval = w['collection'] == 'staff_attendance' &&
            fields != null &&
            FirestoreRestService.decodeValue(
                  (w['fields'] as Map)['approvalStatus'],
                ) ==
                'APPROVED' &&
            FirestoreRestService.decodeValue(fields['approvalStatus']) ==
                'APPROVED';
        if (w['operation'] == 'DELETE') {
          if (doc != null &&
              !(fields?['_syncMutationId'] is Map &&
                  FirestoreRestService.decodeValue(
                        fields?['_syncMutationId'],
                      ) ==
                      batch &&
                  FirestoreRestService.decodeValue(fields?['isDeleted']) ==
                      true)) {
            alreadyApplied = false;
          }
        } else if (isAttendanceApproval) {
          // Attendance is already approved remotely; local approval intent is satisfied.
        } else if (fields == null ||
            w['operation'] == 'CREATE' && tombstone(doc) ||
            !(w['fields'] as Map).entries.every((e) {
              if (e.key == 'updatedAt' ||
                  e.key == 'updatedBy' ||
                  e.key == 'approvedAt' ||
                  e.key == '_syncMutationId') {
                return true;
              }
              final remoteVal = fields[e.key];
              if (remoteVal == null &&
                  (e.value == null ||
                      (e.value is Map &&
                          (e.value as Map).containsKey('nullValue')))) {
                return true;
              }
              if (e.key == 'isDeleted' &&
                  remoteVal == null &&
                  e.value is Map &&
                  (e.value as Map)['booleanValue'] == false) {
                return true;
              }
              return _equal(remoteVal, e.value);
            })) {
          alreadyApplied = false;
        }
      }
      if (!alreadyApplied) {
        final reads = jsonDecode(rows.first['readSetJson'] as String) as Map;
        await _rebaseSequenceWrites(source, rows, writes, reads, get);
        for (final raw in reads.values) {
          final read = raw as Map;
          final doc = await get(
            read['collection'] as String,
            read['id'] as String,
          );
          String? expected = read['updateTime'] as String?;
          if (read['pending'] == true) {
            final row = await source.row(
              read['collection'] as String,
              read['id'] as String,
            );
            if (row == null ||
                (row['acknowledgedRevision'] as int) <
                    (read['revision'] as int)) {
              throw const AppException(
                'A preceding local operation must synchronize first.',
                code: 'sync-conflict',
              );
            }
            expected = row['remoteUpdateTime'] as String?;
          }
          final restoring = writes.any(
            (w) =>
                w['collection'] == read['collection'] &&
                w['id'] == read['id'] &&
                isRestoreMutation(w, doc),
          );
          if (restoring && doc != null) {
            expected = doc['updateTime'] as String?;
          }
          final exists =
              doc != null &&
              (!tombstone(doc) || (restoring && expected == doc['updateTime']));
          if ((read['exists'] == true) != exists ||
              (doc != null && expected != doc['updateTime'])) {
            throw AppException(
              'Remote version changed for ${read['collection']}/${read['id']}. Local data retained.',
              code: 'sync-conflict',
            );
          }
        }
        final commit = <FirestoreWrite>[];
        for (final w in writes) {
          final collection = w['collection'] as String, id = w['id'] as String;
          final doc = await get(collection, id);
          final fields = {
            ...FirestoreRestService.decodeFields(w['fields']),
            '_syncMutationId': batch,
          };
          if (w['operation'] == 'CREATE') {
            if (doc != null && !tombstone(doc)) {
              throw const AppException(
                'Remote ID already exists.',
                code: 'sync-conflict',
              );
            }
            commit.add(
              doc == null
                  ? FirestoreWrite.create(collection, id, fields)
                  : FirestoreWrite.update(collection, id, {
                      ...fields,
                      'isDeleted': false,
                      'status': fields['status'] ?? 'ACTIVE',
                    }, updateTime: doc['updateTime'] as String),
            );
          } else {
            final time = doc?['updateTime'] as String?;
            if (time == null) {
              throw const AppException(
                'Remote record is unavailable.',
                code: 'sync-conflict',
              );
            }
            commit.add(
              w['operation'] == 'DELETE'
                  ? FirestoreWrite.update(collection, id, {
                      ...fields,
                      'isDeleted': true,
                      'status': 'DELETED',
                    }, updateTime: time)
                  : FirestoreWrite.update(
                      collection,
                      id,
                      fields,
                      updateTime: time,
                    ),
            );
          }
        }
        await remote.commitAtomicWrites(commit, idToken: token);
        remoteDocs.clear();
        // Capture confirmed update times for dependent queued operations.
        for (final w in writes) {
          await get(w['collection'] as String, w['id'] as String);
        }
      }
      await source.db.transaction((tx) async {
        for (var i = 0; i < rows.length; i++) {
          final w = writes[i], queue = rows[i];
          final collection = w['collection'] as String, id = w['id'] as String;
          final row = await source.row(collection, id, executor: tx);
          final doc = remoteDocs['$collection/$id'];
          final remaining = await tx.query(
            'sync_outbox',
            where: 'entityType=? AND documentId=? AND batchId!=?',
            whereArgs: [collection, id, batch],
          );
          final data = <String, Object?>{
            'remoteUpdateTime': doc?['updateTime'],
            'remoteUpdatedAt': doc == null
                ? null
                : FirestoreRestService.decodeFields(
                    doc['fields'],
                  )['updatedAt']?.toString(),
            'lastSyncedAt': LocalDataSource.now(),
            'acknowledgedRevision': queue['localRevision'],
            'syncError': null,
          };
          if (remaining.isEmpty &&
              row?['localRevision'] == queue['localRevision']) {
            data['syncStatus'] = 'SYNCED';
            if (doc != null) {
              final confirmed = FirestoreRestService.decodeFields(
                doc['fields'],
              );
              data['payloadJson'] = jsonEncode(doc['fields']);
              data.addAll(LocalDataSource.scopeColumns(confirmed));
              data['isDeleted'] = tombstone(doc) ? 1 : 0;
            }
          }
          await tx.update(
            LocalDataSource.table(collection),
            data,
            where: 'remoteId=?',
            whereArgs: [id],
          );
        }
        await tx.delete('sync_outbox', where: 'batchId=?', whereArgs: [batch]);
        await tx.update(
          'sync_conflicts',
          {'resolved': 1},
          where: 'batchId=?',
          whereArgs: [batch],
        );
      });
    } catch (e) {
      final conflict = e is AppException && isConflict(e);
      await source.db.transaction((tx) async {
        await tx.update(
          'sync_outbox',
          {
            'status': conflict ? 'FAILED' : 'PENDING',
            'lastError': e.toString(),
          },
          where: 'batchId=?',
          whereArgs: [batch],
        );
        for (final w in writes) {
          await tx.update(
            LocalDataSource.table(w['collection'] as String),
            {'syncError': e.toString()},
            where: 'remoteId=?',
            whereArgs: [w['id']],
          );
          if (conflict) {
            await tx.insert('sync_conflicts', {
              'entityType': w['collection'],
              'documentId': w['id'],
              'batchId': batch,
              'localJson': jsonEncode(w),
              'remoteJson': jsonEncode(
                remoteDocs['${w['collection']}/${w['id']}'],
              ),
              'reason': e.toString(),
              'createdAt': LocalDataSource.now(),
            });
          }
        }
      });
      unawaited(
        errorAnalytics?.recordError(
          component: 'SyncEngine',
          location: 'Outbox push batch $batch',
          error: e,
          collection: writes.isNotEmpty
              ? writes.first['collection'] as String?
              : null,
          businessId: rows.isNotEmpty
              ? rows.first['businessId'] as String?
              : null,
          tenantId: rows.isNotEmpty ? rows.first['tenantId'] as String? : null,
          outletId: rows.isNotEmpty ? rows.first['outletId'] as String? : null,
        ),
      );
      rethrow;
    }
  }

  /// Counters only ever move forward. When another client advanced a code
  /// sequence after this batch reserved its codes, the batch's still-unissued
  /// codes are shifted past the remote counter so no code is issued twice, and
  /// the batch is re-based on the remote document version.
  Future<void> _rebaseSequenceWrites(
    LocalDataSource source,
    List<Map<String, Object?>> rows,
    List<Map<String, dynamic>> writes,
    Map reads,
    Future<Map<String, dynamic>?> Function(String, String) get,
  ) async {
    final renames = <String, String>{};
    final sequenceIds = <String>[];
    for (var i = 0; i < writes.length; i++) {
      final w = writes[i];
      if (w['collection'] != 'document_sequences' ||
          (w['operation'] != 'UPDATE' && w['operation'] != 'CREATE')) {
        continue;
      }
      final read = reads['document_sequences/${w['id']}'] as Map?;
      final remote = await get('document_sequences', w['id'] as String);
      if (read == null || remote == null) {
        continue;
      }
      if (read['pending'] == true) {
        final f = Map<String, dynamic>.from(w['fields'] as Map);
        final rf = FirestoreRestService.decodeFields(remote['fields']);
        final localN =
            (FirestoreRestService.decodeValue(
              f['nextNumber'] ?? f['sequence'],
            ) as num?)?.toInt() ??
            0;
        final remoteN =
            ((rf['nextNumber'] ?? rf['sequence']) as num?)?.toInt() ?? 0;
        if (remoteN < localN) {
          continue;
        }
      } else if (read['exists'] == true &&
          remote['updateTime'] == read['updateTime']) {
        continue;
      }
      if (w['operation'] == 'CREATE') {
        w['operation'] = 'UPDATE';
      }
      final fields = Map<String, dynamic>.from(w['fields'] as Map);
      final remoteFields = FirestoreRestService.decodeFields(remote['fields']);

      final isSequenceStyle =
          fields.containsKey('sequence') ||
          remoteFields.containsKey('sequence');
      final localNext =
          (FirestoreRestService.decodeValue(
            fields['nextNumber'] ?? fields['sequence'],
          ) as num?)?.toInt() ??
          0;
      final remoteNext =
          ((remoteFields['nextNumber'] ?? remoteFields['sequence']) as num?)
              ?.toInt() ??
          0;

      String? prefix = fields.containsKey('prefix')
          ? FirestoreRestService.decodeValue(fields['prefix'])?.toString()
          : null;
      int padding =
          (FirestoreRestService.decodeValue(fields['padding']) as num?)
              ?.toInt() ??
          (isSequenceStyle ? 5 : 4);
      String codePrefix;
      RegExp codePattern;

      if (prefix != null && prefix.isNotEmpty) {
        codePrefix = '$prefix-';
        codePattern = RegExp('^${RegExp.escape(prefix)}-(\\d+)\$');
      } else {
        final codeRegex = RegExp(r'^((?:[A-Za-z0-9]+-)+)(\d+)$');
        String? detectedPrefix;
        int? detectedPadding;

        void findCode(Object? node) {
          if (detectedPrefix != null) return;
          if (node is Map) {
            final text = node['stringValue'];
            if (text is String) {
              final m = codeRegex.firstMatch(text);
              if (m != null) {
                final digits = m.group(2)!;
                final numVal = int.tryParse(digits);
                if (numVal != null &&
                    (numVal == localNext ||
                        (numVal >= 1 && numVal <= localNext))) {
                  detectedPrefix = m.group(1);
                  detectedPadding = digits.length;
                  return;
                }
              }
            }
            node.values.forEach(findCode);
          } else if (node is List) {
            node.forEach(findCode);
          }
        }

        for (final other in writes) {
          if (other['collection'] != 'document_sequences') {
            findCode(other['fields']);
          }
        }

        if (detectedPrefix != null) {
          codePrefix = detectedPrefix!;
          padding = detectedPadding ?? padding;
          codePattern = RegExp('^${RegExp.escape(codePrefix)}(\\d+)\$');
        } else {
          codePrefix = '';
          codePattern = RegExp(r'^(\d+)$');
        }
      }

      final used = <int>{};
      void scan(Object? node) {
        if (node is Map) {
          final text = node['stringValue'];
          if (text is String) {
            final n = codePattern.firstMatch(text)?.group(1);
            if (n != null) {
              final val = int.tryParse(n);
              if (val != null) used.add(val);
            }
          } else {
            node.values.forEach(scan);
          }
        } else if (node is List) {
          node.forEach(scan);
        }
      }

      for (final other in writes) {
        if (other['collection'] != 'document_sequences') scan(other['fields']);
      }

      final int shift;
      final int next;
      final minUsed = used.isEmpty
          ? localNext
          : used.reduce((a, b) => a < b ? a : b);
      final maxUsed = used.isEmpty
          ? localNext
          : used.reduce((a, b) => a > b ? a : b);
      if (isSequenceStyle) {
        shift = (remoteNext - minUsed + 1).clamp(0, 1 << 30);
        next = maxUsed + shift > remoteNext ? maxUsed + shift : remoteNext;
      } else {
        shift = (remoteNext - minUsed).clamp(0, 1 << 30);
        next = localNext + shift > remoteNext ? localNext + shift : remoteNext;
      }

      if (shift > 0) {
        for (final n in used) {
          renames['$codePrefix${n.toString().padLeft(padding, '0')}'] =
              '$codePrefix${(n + shift).toString().padLeft(padding, '0')}';
        }
      }
      if (fields.containsKey('nextNumber')) {
        fields['nextNumber'] = {'integerValue': '$next'};
      }
      if (fields.containsKey('sequence')) {
        fields['sequence'] = {'integerValue': '$next'};
      }
      if (!fields.containsKey('nextNumber') &&
          !fields.containsKey('sequence')) {
        fields['nextNumber'] = {'integerValue': '$next'};
      }
      w['fields'] = fields;
      read['updateTime'] = remote['updateTime'];
      read['exists'] = true;
      read['pending'] = false;
      sequenceIds.add(w['id'] as String);
      if (kDebugMode) {
        debugPrint(
          '[sync] sequence rebase ${w['id']} local=$localNext remote=$remoteNext -> $next shift=$shift',
        );
      }
    }
    if (sequenceIds.isEmpty) return;
    String rewrite(String json) {
      if (renames.isEmpty) return json;
      var result = json;
      for (final entry in renames.entries) {
        result = result.replaceAll(entry.key, entry.value);
      }
      return result;
    }

    await source.db.transaction((tx) async {
      for (var i = 0; i < rows.length; i++) {
        final w = writes[i];
        final json = rewrite(jsonEncode(w));
        writes[i] = jsonDecode(json) as Map<String, dynamic>;
        final isSequence = sequenceIds.contains(w['id']);
        await tx.update(
          'sync_outbox',
          {'payloadJson': json, if (isSequence) 'operation': w['operation']},
          where: 'id=?',
          whereArgs: [rows[i]['id']],
        );
        final table = LocalDataSource.table(w['collection'] as String);
        final local = await tx.query(
          table,
          where: 'remoteId=?',
          whereArgs: [w['id']],
        );
        if (local.isEmpty) continue;
        final payload = isSequence
            ? jsonEncode({
                ...(jsonDecode(local.first['payloadJson'] as String) as Map),
                if ((writes[i]['fields'] as Map).containsKey('nextNumber'))
                  'nextNumber': (writes[i]['fields'] as Map)['nextNumber'],
                if ((writes[i]['fields'] as Map).containsKey('sequence'))
                  'sequence': (writes[i]['fields'] as Map)['sequence'],
              })
            : rewrite(local.first['payloadJson'] as String);
        await tx.update(
          table,
          {'payloadJson': payload},
          where: 'remoteId=?',
          whereArgs: [w['id']],
        );
      }
      await tx.update(
        'sync_outbox',
        {'readSetJson': jsonEncode(reads)},
        where: 'batchId=?',
        whereArgs: [rows.first['batchId']],
      );
    });
  }

  static bool isConflict(AppException error) =>
      [
        'sync-conflict',
        '409',
        '412',
        'FAILED_PRECONDITION',
        'ABORTED',
      ].contains(error.code) ||
      error.code == '400' &&
          error.message.toLowerCase().contains('precondition');
  static bool _equal(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    local = null;
    _pullRequested = false;
    _refreshCatalogueRequested = false;
    _scheduled?.cancel();
    _retry?.cancel();
    unawaited(connectivity.dispose());
    unawaited(changes.close());
    super.dispose();
  }
}
