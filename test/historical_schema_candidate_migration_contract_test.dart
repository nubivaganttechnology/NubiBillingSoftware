import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/migration/production_migration_runner.dart';

void main() {
  sqfliteFfiInit();

  test('schema-only v3 candidate migrates without losing sync work', () async {
    final fixture = jsonDecode(
      File('test/fixtures/schema_v3_candidate_schema_only.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(fixture['user_version'], 3);
    expect(
      fixture['schema_fingerprint'],
      ProductionMigrationRunner.verifiedV3SchemaFingerprint,
    );

    final directory = await Directory.systemTemp.createTemp('schema-v3-contract-');
    final path = '${directory.path}/v3.db';
    Database? db;
    try {
      db = await databaseFactoryFfi.openDatabase(path);
      final schemaRows = fixture['schema_rows'] as List<dynamic>;
      final ordered = [...schemaRows]
        ..removeWhere((row) => (row as Map)['name'] == 'sqlite_sequence')
        ..sort((a, b) {
          const rank = {'table': 0, 'index': 1, 'trigger': 2, 'view': 3};
          final left = rank[(a as Map)['type']] ?? 4;
          final right = rank[(b as Map)['type']] ?? 4;
          return left.compareTo(right);
        });
      for (final row in ordered) {
        await db.execute((row as Map)['sql'] as String);
      }
      await db.execute('PRAGMA user_version = 3');
      final beforeSchema = await db.rawQuery(
        'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
      );
      expect(
        ProductionMigrationRunner.computeSchemaFingerprint(beforeSchema),
        ProductionMigrationRunner.verifiedV3SchemaFingerprint,
      );

      await db.insert('sync_queries', {
        'queryKey': 'fixture:protected-query',
        'collectionName': 'product_subcategories',
        'queryJson': '{"filters":[]}',
        'lastSyncedAt': '2026-01-01T00:00:00.000Z',
        'active': 1,
        'cursor': 'fixture-cursor',
        'catalogueVersion': '3',
      });
      await db.insert('sync_outbox', {
        'batchId': 'fixture-batch',
        'entityType': 'products',
        'documentId': 'fixture-product',
        'operation': 'UPDATE',
        'payloadJson': '{}',
        'readSetJson': '{}',
        'localRevision': 1,
        'createdAt': '2026-01-01T00:00:00.000Z',
      });

      await LocalDatabase.migrate(db, 3, 4);
      await db.execute('PRAGMA user_version = 4');
      expect((await db.rawQuery('PRAGMA user_version')).single['user_version'], 4);
      expect(
        (await db.rawQuery(
          'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
        )).where((row) => row['name'] == 'local_catalogue_archive'),
        isNotEmpty,
      );
      expect(await db.query('sync_queries'), hasLength(1));
      expect((await db.query('sync_queries')).single['cursor'], 'fixture-cursor');
      expect(await db.query('sync_outbox'), hasLength(1));
    } finally {
      await db?.close();
      await directory.delete(recursive: true);
    }
  });

  test('fresh current database initializes and reopens at schema v12', () async {
    final directory = await Directory.systemTemp.createTemp('schema-v12-reopen-');
    try {
      final first = LocalDatabase(factory: databaseFactoryFfi, directory: directory.path);
      final db1 = await first.open('fixture-project', 'fixture-user');
      await db1.insert('sync_queries', {
        'queryKey': 'fixture-query',
        'collectionName': 'products',
        'queryJson': '{"filters":[]}',
      });
      await db1.close();

      final second = LocalDatabase(factory: databaseFactoryFfi, directory: directory.path);
      final db2 = await second.open('fixture-project', 'fixture-user');
      expect((await db2.rawQuery('PRAGMA user_version')).single['user_version'], 12);
      expect(await db2.query('sync_queries'), hasLength(1));
      await db2.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
