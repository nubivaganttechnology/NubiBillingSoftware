import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'catalogue_archive_store.dart';
import 'local_database_tables.dart';

/// All documents retain their REST fields verbatim; arrays/maps/timestamps survive
/// without flattening or changing the remote schema. Accounts are separate files.
class LocalDatabase {
  LocalDatabase({DatabaseFactory? factory, this.directory})
    : factory = factory ?? databaseFactory;
  final DatabaseFactory factory;
  final String? directory;
  static const schemaVersion = 13;
  static const tables = LocalDatabaseTables.tables;
  final Map<String, Future<Database>> _opened = {};
  Future<Database> open(String project, String uid) =>
      _opened.putIfAbsent('$project/$uid', () async {
        final key = Uri.encodeComponent('$project-$uid');
        final String dbPath;
        if (kIsWeb) {
          dbPath = directory != null
              ? path.join(directory!, 'nubibill-$key.db')
              : 'nubibill-$key.db';
        } else {
          final root = directory ?? await factory.getDatabasesPath();
          final dir = Directory(root);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          dbPath = path.join(root, 'nubibill-$key.db');
        }
        try {
          return await factory.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              version: schemaVersion,
              onConfigure: (db) async {
                await db.execute('PRAGMA foreign_keys = ON');
              },
              onCreate: (db, version) => migrate(db, 0, version),
              onUpgrade: migrate,
              onDowngrade: (db, old, next) async {
                // Non-destructive downgrade allows graceful compatibility across
                // test builds with higher schema versions, preserving local tables.
              },
              onOpen: (db) async {
                for (final table in tables.values) {
                  await _createDocumentTable(db, table);
                }
              },
            ),
          );
        } catch (_) {
          _opened.remove('$project/$uid');
          rethrow;
        }
      });

  static Future<void> _createDocumentTable(Database db, String table) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $table (
          remoteId TEXT PRIMARY KEY, payloadJson TEXT NOT NULL,
          scopeType TEXT, status TEXT, catalogueId TEXT,
          businessTypeId TEXT, businessSubTypeId TEXT,
          tenantId TEXT, businessId TEXT, outletId TEXT,
          categoryId TEXT, subcategoryId TEXT, attributeId TEXT,
          syncStatus TEXT NOT NULL DEFAULT 'SYNCED',
          localUpdatedAt TEXT NOT NULL, remoteUpdatedAt TEXT,
          remoteUpdateTime TEXT, lastSyncedAt TEXT,
          isDeleted INTEGER NOT NULL DEFAULT 0, syncError TEXT,
          localRevision INTEGER NOT NULL DEFAULT 0,
          acknowledgedRevision INTEGER NOT NULL DEFAULT 0
        )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${table}_scope ON $table(tenantId,businessId,outletId,scopeType)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${table}_reconcile ON $table(syncStatus,isDeleted)',
    );
  }

  static Future<void> migrate(Database db, int old, int next) async {
    if (old < 1 && next >= 1) {
      for (final table in tables.values) {
        await _createDocumentTable(db, table);
      }
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT, batchId TEXT NOT NULL,
        entityType TEXT NOT NULL, documentId TEXT NOT NULL,
        operation TEXT NOT NULL CHECK(operation IN ('CREATE','UPDATE','DELETE')),
        tenantId TEXT, businessId TEXT, outletId TEXT,
        payloadJson TEXT NOT NULL, readSetJson TEXT NOT NULL,
        localRevision INTEGER NOT NULL, createdAt TEXT NOT NULL,
        attemptCount INTEGER NOT NULL DEFAULT 0, lastAttemptAt TEXT,
        lastError TEXT, status TEXT NOT NULL DEFAULT 'PENDING'
          CHECK(status IN ('PENDING','PROCESSING','FAILED'))
      )''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS outbox_batch ON sync_outbox(batchId,id)',
      );
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_queries (
        queryKey TEXT PRIMARY KEY, collectionName TEXT NOT NULL,
        queryJson TEXT NOT NULL, lastSyncedAt TEXT
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, entityType TEXT NOT NULL,
        documentId TEXT NOT NULL, batchId TEXT, localJson TEXT,
        remoteJson TEXT, reason TEXT NOT NULL, createdAt TEXT NOT NULL,
        resolved INTEGER NOT NULL DEFAULT 0
      )''');
      await db.execute('''CREATE TABLE IF NOT EXISTS sync_lease (
        id INTEGER PRIMARY KEY CHECK(id=1), owner TEXT, expiresAt TEXT
      )''');
      await db.insert('sync_lease', {'id': 1});
    }
    if (old < 2 && next >= 2) {
      await db.execute(
        'ALTER TABLE sync_queries ADD COLUMN lastAttemptAt TEXT',
      );
      await db.execute('ALTER TABLE sync_queries ADD COLUMN lastError TEXT');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS conflict_entity ON sync_conflicts(entityType,documentId,resolved)',
      );
    }
    if (old < 3 && next >= 3) {
      await _createDocumentTable(db, 'local_godown_code_reservations');
      await db.execute(
        'CREATE INDEX outbox_entity ON sync_outbox(entityType,documentId,id)',
      );
      await db.execute(
        'CREATE INDEX outbox_status ON sync_outbox(status,batchId,id)',
      );
      for (final table in tables.values) {
        // Tables introduced after v1 may not exist yet on this upgrade path.
        await _createDocumentTable(db, table);
        await db.execute(
          'CREATE INDEX IF NOT EXISTS ${table}_reconcile ON $table(syncStatus,isDeleted)',
        );
      }
      await db.execute(
        'ALTER TABLE sync_queries ADD COLUMN active INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute('ALTER TABLE sync_queries ADD COLUMN cursor TEXT');
      await db.execute(
        'ALTER TABLE sync_queries ADD COLUMN catalogueVersion TEXT',
      );
      await db.execute(
        'CREATE INDEX sync_queries_active ON sync_queries(active)',
      );
      await db.execute(
        'CREATE TABLE sync_control (id INTEGER PRIMARY KEY CHECK(id=1), cooldownUntil TEXT, failureCount INTEGER NOT NULL DEFAULT 0, lastPullAt TEXT, lastError TEXT)',
      );
      final quotaErrors = await db.query(
        'sync_outbox',
        where: "lastError LIKE '%429%' OR lastError LIKE '%RESOURCE_EXHAUSTED%' OR lastError LIKE '%quota%'",
        limit: 1,
      );
      final historicalPullErrors = quotaErrors.isEmpty
          ? await db.query(
              'sync_queries',
              where: "lastError LIKE '%429%' OR lastError LIKE '%RESOURCE_EXHAUSTED%' OR lastError LIKE '%quota%'",
              limit: 1,
            )
          : quotaErrors;
      await db.insert('sync_control', {
        'id': 1,
        if (historicalPullErrors.isNotEmpty) ...{
          'cooldownUntil': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'failureCount': 1,
          'lastError': historicalPullErrors.first['lastError'],
        },
      });
      // Normalize legacy identities without deleting documents or outbox work.
      for (final row in await db.query('sync_queries')) {
        final spec =
            jsonDecode(row['queryJson'] as String) as Map<String, dynamic>;
        if (spec['filters'] is List) {
          (spec['filters'] as List).sort(
            (a, b) => jsonEncode(a).compareTo(jsonEncode(b)),
          );
        }
        final encoded = jsonEncode(spec);
        final key = '${row['collectionName']}:$encoded';
        if (key == row['queryKey']) continue;
        final existing = await db.query(
          'sync_queries',
          where: 'queryKey=?',
          whereArgs: [key],
        );
        if (existing.isEmpty) {
          await db.update(
            'sync_queries',
            {'queryKey': key, 'queryJson': encoded},
            where: 'queryKey=?',
            whereArgs: [row['queryKey']],
          );
        } else {
          final previous = DateTime.tryParse(
            existing.single['lastSyncedAt'] as String? ?? '',
          );
          final completed = DateTime.tryParse(
            row['lastSyncedAt'] as String? ?? '',
          );
          if (completed != null &&
              (previous == null || completed.isAfter(previous))) {
            await db.update(
              'sync_queries',
              {'lastSyncedAt': row['lastSyncedAt']},
              where: 'queryKey=?',
              whereArgs: [key],
            );
          }
          await db.delete(
            'sync_queries',
            where: 'queryKey=?',
            whereArgs: [row['queryKey']],
          );
        }
      }
    }
    if (old < 4 && next >= 4) {
      await CatalogueArchiveStore.createSchema(db);
    }
    if (old < 5 && next >= 5) {
      await db.execute(
        '''CREATE TABLE IF NOT EXISTS local_central_product_master (
        master_product_id TEXT PRIMARY KEY,
        product_name TEXT NOT NULL,
        normalized_product_name TEXT NOT NULL,
        business_type_id TEXT NOT NULL,
        business_sub_type_id TEXT NOT NULL,
        brand_id TEXT NOT NULL,
        brand_name TEXT NOT NULL,
        range_name TEXT,
        category_id TEXT NOT NULL,
        category_name TEXT NOT NULL,
        subcategory_id TEXT NOT NULL,
        subcategory_name TEXT NOT NULL,
        scope_type TEXT NOT NULL,
        status TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        image_url TEXT,
        description TEXT,
        pack_sizes TEXT,
        finish TEXT,
        colour TEXT,
        remote_updated_at TEXT,
        synced_at TEXT,
        payload_json TEXT NOT NULL
      )''',
      );
      for (final column in [
        'normalized_product_name',
        'business_type_id',
        'business_sub_type_id',
        'status',
        'is_active',
      ]) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS local_central_product_master_$column '
          'ON local_central_product_master($column)',
        );
      }
    }
    if (old < 6 && next >= 6) {
      await db.execute(
        "ALTER TABLE local_central_product_master ADD COLUMN source_collection TEXT NOT NULL DEFAULT 'central_product_master'",
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS local_central_product_master_source '
        'ON local_central_product_master(source_collection)',
      );
    }
    if (old < 7 && next >= 7) {
      // Outlet placement only. Existing products are deliberately NOT placed
      // anywhere: placement is never guessed and must be assigned explicitly.
      final table = tables['outlet_products']!;
      await _createDocumentTable(db, table);
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${table}_reconcile ON $table(syncStatus,isDeleted)',
      );
    }
    if (old < 8 && next >= 8) {
      // Device-local, never synced: records one-time data migrations that ran.
      await db.execute('''CREATE TABLE IF NOT EXISTS local_migration_markers (
        markerKey TEXT PRIMARY KEY, completedAt TEXT NOT NULL
      )''');
    }
    if (old < 9 && next >= 9) {
      await _createDocumentTable(db, tables['inventory_batches']!);
      await _createDocumentTable(db, tables['purchase_bill_items']!);
      for (final column in [
        'variantId',
        'internalBatchNo',
        'supplierLotNo',
        'expiryDate',
        'purchaseId',
      ]) {
        await db.execute(
          'ALTER TABLE local_inventory_batches ADD COLUMN $column TEXT',
        );
      }
      await db.execute(
        'CREATE INDEX IF NOT EXISTS local_inventory_batches_scope ON local_inventory_batches(businessId,outletId)',
      );
      for (final column in [
        'variantId',
        'internalBatchNo',
        'supplierLotNo',
        'expiryDate',
        'purchaseId',
      ]) {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS local_inventory_batches_$column ON local_inventory_batches($column)',
        );
      }
    }
    if (old < 10 && next >= 10) {
      final table = tables['purchase_corrections']!;
      await _createDocumentTable(db, table);
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${table}_reconcile ON $table(syncStatus,isDeleted)',
      );
    }
    if (old < 11 && next >= 11) {
      final table = tables['inventory_batch_movements']!;
      await _createDocumentTable(db, table);
    }
    if (old < 12 && next >= 12) {
      for (final collection in ['supplier_refunds', 'financial_transactions']) {
        final table = tables[collection]!;
        await _createDocumentTable(db, table);
        await db.execute(
          'CREATE INDEX IF NOT EXISTS ${table}_reconcile ON $table(syncStatus,isDeleted)',
        );
      }
    }
  }

  Future<void> close() async {
    for (final future in _opened.values) {
      await (await future).close();
    }
    _opened.clear();
  }
}
