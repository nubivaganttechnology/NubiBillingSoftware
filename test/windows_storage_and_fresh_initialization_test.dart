import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('Windows Storage and Fresh SQLite Initialization', () {
    test('fresh public-config database initializes to schema version 12 in disposable directory', () async {
      final tempDir = await Directory.systemTemp.createTemp('pub-config-test-');
      addTearDown(() => tempDir.delete(recursive: true));

      final localDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
      final db = await localDb.open('test1-bcebe', 'public-config');
      addTearDown(db.close);

      final versionResult = await db.rawQuery('PRAGMA user_version');
      expect(versionResult.single['user_version'], 12);

      // Verify that public-config table local_app_config and sync tables exist
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      final tableNames = tables.map((r) => r['name'] as String).toSet();
      expect(tableNames, contains('local_app_config'));
      expect(tableNames, contains('sync_queries'));
      expect(tableNames, contains('sync_control'));
      expect(tableNames, contains('sync_lease'));

      // Verify initial sync_control and sync_lease rows
      final leaseRows = await db.query('sync_lease');
      expect(leaseRows, hasLength(1));
      expect(leaseRows.first['id'], 1);

      final controlRows = await db.query('sync_control');
      expect(controlRows, hasLength(1));
      expect(controlRows.first['id'], 1);
    });

    test('fresh account database initializes independently at schema v12 and cannot share database with another UID', () async {
      final tempDir = await Directory.systemTemp.createTemp('account-isolation-test-');
      addTearDown(() => tempDir.delete(recursive: true));

      final localDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
      final dbUserA = await localDb.open('test1-bcebe', 'user-alpha');
      final dbUserB = await localDb.open('test1-bcebe', 'user-beta');
      addTearDown(dbUserA.close);
      addTearDown(dbUserB.close);

      expect((await dbUserA.rawQuery('PRAGMA user_version')).single['user_version'], 12);
      expect((await dbUserB.rawQuery('PRAGMA user_version')).single['user_version'], 12);

      // Insert record into user-alpha
      await dbUserA.insert('sync_queries', {
        'queryKey': 'alpha:query-1',
        'collectionName': 'products',
        'queryJson': '{"id":"p1"}',
        'lastSyncedAt': '2026-10-16T10:00:00.000Z',
      });

      // Verify user-beta does not see user-alpha's data
      final rowsA = await dbUserA.query('sync_queries');
      final rowsB = await dbUserB.query('sync_queries');
      expect(rowsA, hasLength(1));
      expect(rowsB, isEmpty);

      // Verify physical file paths are distinct and isolated
      final files = tempDir.listSync().whereType<File>().map((f) => p.basename(f.path)).toList();
      expect(files, contains('nubibill-test1-bcebe-user-alpha.db'));
      expect(files, contains('nubibill-test1-bcebe-user-beta.db'));
      expect(files.length, 2);
    });

    test('reopening databases does not recreate, overwrite, or destroy stored records', () async {
      final tempDir = await Directory.systemTemp.createTemp('reopen-test-');
      addTearDown(() => tempDir.delete(recursive: true));

      // First run: open, write data, close
      final localDb1 = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
      final db1 = await localDb1.open('test1-bcebe', 'user-gamma');
      await db1.insert('local_products', {
        'remoteId': 'PROD-001',
        'payloadJson': '{"name":"Sample Paint"}',
        'syncStatus': 'SYNCED',
        'localUpdatedAt': '2026-10-16T10:00:00.000Z',
        'localRevision': 1,
        'isDeleted': 0,
      });
      await db1.close();

      // Second run: fresh LocalDatabase instance reopening the same directory
      final localDb2 = LocalDatabase(factory: databaseFactoryFfi, directory: tempDir.path);
      final db2 = await localDb2.open('test1-bcebe', 'user-gamma');
      addTearDown(db2.close);

      expect((await db2.rawQuery('PRAGMA user_version')).single['user_version'], 12);
      final products = await db2.query('local_products');
      expect(products, hasLength(1));
      expect(products.first['remoteId'], 'PROD-001');
      expect(products.first['payloadJson'], '{"name":"Sample Paint"}');
    });

    test('storage paths are stable and independent of current working directory', () async {
      final tempStorage = await Directory.systemTemp.createTemp('stable-storage-');
      addTearDown(() => tempStorage.delete(recursive: true));

      final localDb = LocalDatabase(factory: databaseFactoryFfi, directory: tempStorage.path);
      final db = await localDb.open('project-x', 'uid-y');
      addTearDown(db.close);

      final dbPath = p.join(tempStorage.path, 'nubibill-project-x-uid-y.db');
      expect(File(dbPath).existsSync(), isTrue);
      // Ensure the path is an absolute path within tempStorage, not relative to .dart_tool or cwd
      expect(p.isAbsolute(dbPath), isTrue);
      expect(p.isWithin(Directory.current.path, dbPath), isFalse);
    });

    test('historical Windows database detection alerts without modifying or deleting files', () async {
      final sandbox = await Directory.systemTemp.createTemp('historical-detection-test-');
      addTearDown(() => sandbox.delete(recursive: true));

      final historicalDir = Directory(p.join(sandbox.path, '.dart_tool', 'sqflite_common_ffi', 'databases'));
      await historicalDir.create(recursive: true);

      final oldDb = File(p.join(historicalDir.path, 'nubibill-legacy-user.db'));
      await oldDb.writeAsString('placeholder database content');

      final targetDir = p.join(sandbox.path, 'app_support', 'databases');
      final notice = detectHistoricalWindowsDatabaseLocation(
        workingDirectory: sandbox.path,
        targetDirectory: targetDir,
      );

      expect(notice, isNotNull);
      expect(notice, contains('Detected 1 database(s) in historical location'));
      expect(notice, contains('Existing databases are preserved and NOT automatically moved or deleted'));
      expect(notice, contains('To migrate historical data to permanent storage'));

      // Verify that the historical database was NOT modified or deleted
      expect(oldDb.existsSync(), isTrue);
      expect(oldDb.readAsStringSync(), 'placeholder database content');
    });
  });
}
