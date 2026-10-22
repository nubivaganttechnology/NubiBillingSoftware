import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/errors/app_exception.dart';
import '../local/local_data_source.dart';
import '../local/catalogue_archive_store.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_value_codec.dart';
import 'catalogue_contract.dart';
import 'catalogue_fingerprint.dart';
import 'catalogue_readiness.dart';
import 'system_catalogue_metadata.dart';

/// Validates/compiles before mutation; rows, query cursors and installed marker
/// share one transaction. No outbox or remote-write path.
class SystemCatalogueSnapshot {
  static const requiredCollections = CatalogueContract.requiredCollections;

  static Future<void> import({
    required LocalDataSource source,
    required Map<String, List<Map<String, dynamic>>> documents,
    required Map<String, String> readTimes,
    bool preserveSyncQueries = true,
    bool allowUnapprovedIsolatedForTests = false,
    DatabaseExecutor? executor,
    Future<void> Function(String stage, DatabaseExecutor tx)? failureProbe,
  }) async {
    if (!requiredCollections.every(documents.containsKey)) {
      throw const AppException('Incomplete SYSTEM catalogue snapshot.');
    }
    // Preserve precise wire/identity diagnostics before wrapping readiness
    // failures in the user-facing catalogue readiness error.
    final normalizedDocuments = <String, List<Map<String, dynamic>>>{
      for (final collection in SystemCatalogueMetadata.collections)
        collection: documents[collection] ?? const [],
    };
    final compiled = SystemCatalogueMetadata.compile(normalizedDocuments);
    final readiness = CatalogueReadiness.validate(
      compiled,
      allowUnapprovedIsolatedForTests: allowUnapprovedIsolatedForTests,
    );
    if (!readiness.isReady) {
      throw AppException(
        readiness.errors.join(' '),
        code: 'catalogue-readiness',
      );
    }
    final raw = CatalogueContract.decode(compiled);
    final releases = raw['product_catalogue_releases']!
        .where((r) => CatalogueContract.active(r) && r['published'] != false)
        .toList();
    if (releases.length != 1) {
      CatalogueContract.fail(
        'Exactly one published catalogue release is required.',
      );
    }
    final release = releases.single;
    final version = CatalogueContract.version(release);
    final contentFingerprint = CatalogueContract.fingerprint({
      for (final entry in compiled.entries)
        if (entry.key != 'brands') entry.key: entry.value,
    });
    if (release['contentFingerprint'] != null &&
        release['contentFingerprint'] != contentFingerprint) {
      CatalogueContract.fail(
        'Published catalogue content fingerprint does not match its payload.',
        'catalogue-release',
      );
    }
    final manifest = <String, List<String>>{
      for (final entry in compiled.entries)
        entry.key:
            (entry.value
                .map((document) => (document['name'] as String).split('/').last)
                .toSet()
                .toList()
              ..sort()),
    };
    final releaseFingerprint = SystemCatalogueMetadata.fingerprint(
      compiled['product_catalogue_releases']!,
    );
    final installedDocuments = <String, List<Map<String, dynamic>>>{
      for (final entry in compiled.entries)
        entry.key: [
          for (final document in entry.value)
            if (entry.key == 'product_catalogue_releases')
              {
                ...document,
                'fields': FirestoreValueCodec.encodeFields({
                  ...FirestoreValueCodec.decodeFields(document['fields']),
                  'contentFingerprint': contentFingerprint,
                  'installed': true,
                  'installedDocumentManifest': manifest,
                }),
              }
            else
              document,
        ],
    };
    final catalogueFingerprint = CatalogueFingerprint.calculate(
      installedDocuments,
    );
    Future<void> executeInTx(DatabaseExecutor tx) async {
      final installed = await tx.query(
        LocalDataSource.table('product_catalogue_releases'),
        where: "scopeType='SYSTEM' AND isDeleted=0",
      );
      var previousFingerprintFound = false;
      for (final row in installed) {
        final prior = FirestoreValueCodec.decodeFields(
          jsonDecode(row['payloadJson'] as String),
        );
        if (!CatalogueContract.active(prior)) continue;
        previousFingerprintFound = true;
        final priorVersion = CatalogueContract.version(prior);
        final priorCompiler = prior['compilerRevision'] ?? 0;
        if (priorVersion > version ||
            (priorCompiler as num) > CatalogueContract.compilerRevision) {
          CatalogueContract.fail(
            'Cannot overwrite a newer installed release/compiler revision.',
            'catalogue-revision',
          );
        }
        if (prior['compilerRevision'] == null &&
            prior['localMetadataRevision'] is num &&
            (prior['localMetadataRevision'] as num) > 0 &&
            priorVersion >= version &&
            prior['contentFingerprint'] == null) {
          CatalogueContract.fail(
            'Legacy installed metadata revision has unknown compiler provenance; a reviewed newer versioned release is required.',
            'catalogue-revision',
          );
        }
        if (priorVersion == version &&
            prior['contentFingerprint'] != null &&
            prior['contentFingerprint'] != contentFingerprint) {
          CatalogueContract.fail(
            'Published release content changed without a new data version.',
            'catalogue-release',
          );
        }
        if (priorVersion == version &&
            prior['contentFingerprint'] == contentFingerprint &&
            _hasInstalledManifest(prior) &&
            CatalogueFingerprint.isValid(prior['catalogueFingerprint'])) {
          final current = await _readInstalledSnapshot(tx);
          if (CatalogueReadiness.validateInstalled(
                current,
                allowUnapprovedIsolatedForTests:
                    allowUnapprovedIsolatedForTests,
              ).isReady &&
              prior['catalogueFingerprint'] == catalogueFingerprint) {
            // An identical, still-valid release is a true no-op.
            return;
          }
        }
      }
      if (previousFingerprintFound) {
        // Archive the actual local preimage, never trust a stale marker value
        // as the identity of rows that may already have drifted.
        final priorFingerprint = await _fingerprintInstalledSnapshot(tx);
        await failureProbe?.call('before_archive', tx);
        await CatalogueArchiveStore().archiveCurrentSnapshot(
          tx,
          fingerprint: priorFingerprint,
          failureProbe: (insertedRows, executor) async {
            await failureProbe?.call('archive_row_$insertedRows', executor);
          },
        );
        await failureProbe?.call('after_archive', tx);
      }
      // Never let an incoming SYSTEM document replace BUSINESS/pending metadata
      // at the same ID, even if query order or a remote name match suggests it.
      for (final entry in compiled.entries) {
        for (final doc in entry.value) {
          final id = (doc['name'] as String).split('/').last;
          final old = await source.row(entry.key, id, executor: tx);
          if (old != null &&
              (old['scopeType'] != 'SYSTEM' || old['syncStatus'] != 'SYNCED')) {
            CatalogueContract.fail(
              'Protected BUSINESS/pending ID collision: ${entry.key}/$id.',
              'catalogue-collision',
            );
          }
        }
      }
      final entries = compiled.entries.where(
        (e) => e.key != 'product_catalogue_releases',
      );
      for (final entry in entries) {
        await source.upsertRemote(
          entry.key,
          entry.value,
          completeQuery: [
            const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
          ],
          executor: tx,
        );
        if (failureProbe != null) await failureProbe(entry.key, tx);
      }
      if (!preserveSyncQueries) {
        for (final entry in compiled.entries) {
          final queries = await tx.query(
            'sync_queries',
            where: 'collectionName=?',
            whereArgs: [entry.key],
          );
          for (final query in queries) {
            final spec = jsonDecode(query['queryJson'] as String) as Map;
            final filters = (spec['filters'] as List? ?? []).cast<Map>();
            if (spec['id'] != null ||
                filters.length != 1 ||
                filters.single['field'] != 'scopeType' ||
                filters.single['operation'] != 'EQUAL' ||
                FirestoreValueCodec.decodeValue(filters.single['value']) !=
                    'SYSTEM') {
              continue;
            }
            await tx.update(
              'sync_queries',
              {
                'lastSyncedAt': LocalDataSource.now(),
                'lastError': null,
                'catalogueVersion': releaseFingerprint,
                if (readTimes[entry.key] != null)
                  'cursor': readTimes[entry.key],
              },
              where: 'queryKey=?',
              whereArgs: [query['queryKey']],
            );
          }
        }
      }
      if (failureProbe != null) await failureProbe('before_release_marker', tx);
      // The installed/published marker is the final catalogue row write.
      await source.upsertRemote('product_catalogue_releases', [
        for (final doc in compiled['product_catalogue_releases']!)
          {
            ...doc,
            'fields': FirestoreValueCodec.encodeFields({
              ...FirestoreValueCodec.decodeFields(doc['fields']),
              'contentFingerprint': contentFingerprint,
              'catalogueFingerprint': catalogueFingerprint,
              'installed': true,
              'installedDocumentManifest': manifest,
            }),
          },
      ], executor: tx);
      if (failureProbe != null) await failureProbe('after_release_marker', tx);
    }

    if (executor != null) {
      await executeInTx(executor);
    } else {
      await source.db.transaction(executeInTx);
    }
  }

  static bool _hasInstalledManifest(Map<String, dynamic> marker) {
    final value = marker['installedDocumentManifest'];
    return value is Map &&
        SystemCatalogueMetadata.collections.every(
          (collection) => value[collection] is List,
        );
  }

  static Future<Map<String, List<Map<String, dynamic>>>> _readInstalledSnapshot(
    DatabaseExecutor tx,
  ) async {
    final documents = <String, List<Map<String, dynamic>>>{};
    for (final collection in SystemCatalogueMetadata.collections) {
      final rows = await tx.query(
        LocalDataSource.table(collection),
        where: "scopeType='SYSTEM' AND isDeleted=0",
        orderBy: 'remoteId',
      );
      documents[collection] = [
        for (final row in rows) LocalDataSource.document(row, collection),
      ];
    }
    return documents;
  }

  static Future<String> _fingerprintInstalledSnapshot(
    DatabaseExecutor tx,
  ) async {
    final documents = <String, List<Map<String, dynamic>>>{};
    const fingerprintCollections = {
      ...CatalogueArchiveStore.collections,
      'brands',
    };
    for (final collection in fingerprintCollections) {
      final rows = await tx.query(
        LocalDataSource.table(collection),
        where: "scopeType='SYSTEM' AND isDeleted=0",
        orderBy: 'remoteId',
      );
      documents[collection] = [
        for (final row in rows)
          {
            'name': '$collection/${row['remoteId']}',
            'fields': jsonDecode(row['payloadJson'] as String),
          },
      ];
    }
    if (documents['product_catalogue_releases']!.isEmpty) {
      CatalogueContract.fail(
        'Installed SYSTEM metadata has no release marker to fingerprint.',
        'catalogue-provenance-missing',
      );
    }
    return CatalogueFingerprint.calculate(documents);
  }
}
