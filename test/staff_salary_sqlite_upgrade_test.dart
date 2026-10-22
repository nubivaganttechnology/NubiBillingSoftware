import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_database.dart';

void main() {
  sqfliteFfiInit();

  test('v12 disposable database opens at v13 and preserves product and pending outbox data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nubibill-salary-v12-',
    );
    final path = '${directory.path}/nubibill-fixture-project-fixture-user.db';
    try {
      final fixture = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 12,
          onCreate: (db, version) => LocalDatabase.migrate(db, 0, version),
        ),
      );
      await fixture.insert('local_products', {
        'remoteId': 'PRODUCT-KEEP',
        'payloadJson': jsonEncode({'productId': 'PRODUCT-KEEP'}),
        'localUpdatedAt': DateTime.utc(2026).toIso8601String(),
        'syncStatus': 'SYNCED',
      });
      await fixture.insert('sync_outbox', {
        'batchId': 'BATCH-KEEP',
        'entityType': 'financial_transactions',
        'documentId': 'FIN-KEEP',
        'operation': 'CREATE',
        'payloadJson': '{}',
        'readSetJson': '[]',
        'localRevision': 3,
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'status': 'PENDING',
      });
      // Model the pre-salary v12 schema while staying entirely inside this
      // temporary fixture; v13 onOpen must add the salary document tables.
      for (final table in [
        'local_employee_salary_profiles',
        'local_employee_outlet_allocations',
        'local_staff_khata_transactions',
        'local_salary_periods',
      ]) {
        await fixture.execute('DROP TABLE IF EXISTS $table');
      }
      await fixture.close();

      final database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: directory.path,
      );
      final upgraded = await database.open('fixture-project', 'fixture-user');
      expect(await upgraded.getVersion(), LocalDatabase.schemaVersion);
      expect(
        (await upgraded.query(
          'local_products',
          where: 'remoteId=?',
          whereArgs: ['PRODUCT-KEEP'],
        )),
        hasLength(1),
      );
      final outbox = await upgraded.query(
        'sync_outbox',
        where: 'documentId=?',
        whereArgs: ['FIN-KEEP'],
      );
      expect(outbox, hasLength(1));
      expect(outbox.single['status'], 'PENDING');
      for (final table in [
        'local_employee_salary_profiles',
        'local_employee_outlet_allocations',
        'local_staff_khata_transactions',
        'local_salary_periods',
      ]) {
        expect(
          await upgraded.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          ),
          hasLength(1),
        );
      }
      await database.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('salary documents and pending outbox survive closing and reopening SQLite', () async {
    final directory = await Directory.systemTemp.createTemp('nubibill-salary-restart-');
    try {
      final first = LocalDatabase(factory: databaseFactoryFfi, directory: directory.path);
      final opened = await first.open('restart-project', 'restart-user');
      final now = DateTime.utc(2026, 10, 20).toIso8601String();
      await opened.insert('local_salary_periods', {
        'remoteId': 'PER-RESTART',
        'payloadJson': jsonEncode({'periodId': 'PER-RESTART', 'employeeId': 'EMP-1'}),
        'tenantId': 'OWNER-1', 'businessId': 'B-1', 'localUpdatedAt': now,
        'syncStatus': 'PENDING_CREATE', 'localRevision': 1,
      });
      await opened.insert('sync_outbox', {
        'batchId': 'SALARY-BATCH-RESTART', 'entityType': 'salary_periods',
        'documentId': 'PER-RESTART', 'operation': 'CREATE',
        'payloadJson': jsonEncode({'collection': 'salary_periods', 'id': 'PER-RESTART'}),
        'readSetJson': '{}', 'localRevision': 1, 'createdAt': now,
        'status': 'PENDING',
      });
      await first.close();

      final second = LocalDatabase(factory: databaseFactoryFfi, directory: directory.path);
      final reopened = await second.open('restart-project', 'restart-user');
      expect(await reopened.query('local_salary_periods', where: 'remoteId=?', whereArgs: ['PER-RESTART']), hasLength(1));
      final pending = await reopened.query('sync_outbox', where: 'batchId=?', whereArgs: ['SALARY-BATCH-RESTART']);
      expect(pending, hasLength(1));
      expect(pending.single['status'], 'PENDING');
      await second.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
