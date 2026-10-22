import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';

/// Explicit maintenance entry point, outside the normal test suite.
/// flutter test tool/refresh_system_catalogue_test.dart
///   --dart-define=CATALOGUE_DB=/absolute/existing.db
///   --dart-define=CATALOGUE_SNAPSHOT=/absolute/download-directory
void main() {
  test('import downloaded catalogue into an existing SQLite account', () async {
    const path = String.fromEnvironment('CATALOGUE_DB');
    const folder = String.fromEnvironment('CATALOGUE_SNAPSHOT');
    if (path.isEmpty || folder.isEmpty || !await File(path).exists()) {
      throw StateError(
        'An existing account database and snapshot directory are required.',
      );
    }
    final documents = <String, List<Map<String, dynamic>>>{};
    final times = <String, String>{};
    for (final collection in SystemCatalogueSnapshot.requiredCollections) {
      final result = jsonDecode(
        await File('$folder/$collection.json').readAsString(),
      );
      if (result is! List || result.any((r) => r['error'] != null)) {
        throw StateError('Invalid REST snapshot for $collection.');
      }
      documents[collection] = [
        for (final row in result)
          if (row['document'] != null)
            Map<String, dynamic>.from(row['document'] as Map),
      ];
      if (documents[collection]!.isEmpty) {
        throw StateError('Empty catalogue collection: $collection');
      }
      times[collection] = result.last['readTime'] as String;
    }
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(path);
    final source = LocalDataSource(db);
    final lease = SyncOutboxRepository(source);
    const owner = 'SYSTEM_CATALOGUE_MAINTENANCE';
    if (!await lease.acquire(owner)) {
      await db.close();
      throw StateError(
        'Background synchronization is active. Retry once it finishes.',
      );
    }
    try {
      final backup =
          '$folder/account-before-catalogue-${DateTime.now().millisecondsSinceEpoch}.db';
      await db.execute('VACUUM INTO ?', [backup]);
      final outbox = await db.query('sync_outbox', orderBy: 'id');
      final business = <String, List<Map<String, Object?>>>{};
      for (final collection in SystemCatalogueSnapshot.requiredCollections) {
        business[collection] = await db.query(
          LocalDataSource.table(collection),
          where: "scopeType IS NULL OR scopeType!='SYSTEM'",
          orderBy: 'remoteId',
        );
      }
      await SystemCatalogueSnapshot.import(
        source: source,
        documents: documents,
        readTimes: times,
      );
      expect(await db.query('sync_outbox', orderBy: 'id'), outbox);
      for (final entry in business.entries) {
        expect(
          await db.query(
            LocalDataSource.table(entry.key),
            where: "scopeType IS NULL OR scopeType!='SYSTEM'",
            orderBy: 'remoteId',
          ),
          entry.value,
        );
      }
      final releases = await source.query('product_catalogue_releases', [
        FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
      ]);
      expect(
        FirestoreRestService.decodeFields(
          releases.single['fields'],
        )['catalogueVersion'],
        3,
      );
      // The backup contains account data and deliberately stays outside the repo.
      // ignore: avoid_print
      print(
        'SQLite catalogueVersion=3; BUSINESS rows and outbox unchanged; backup=$backup',
      );
    } finally {
      await lease.release(owner);
      await db.close();
    }
  });
}
