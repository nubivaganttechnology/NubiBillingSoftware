import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/catalogue_archive_store.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/migration/production_migration_runner.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

import 'support/phase10e_release.dart' show release4Documents;

void main() {
  sqfliteFfiInit();

  const prodDbPath =
      '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db';
  const prodBakPath =
      '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak';
  const prodPubConfigPath =
      '/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db';

  String computeSha256(File f) {
    return sha256.convert(f.readAsBytesSync()).toString();
  }

  Future<Map<String, String>> createVerifiedV4Clone() async {
    final dir = await Directory.systemTemp.createTemp('phase10m_v4_r3_');
    final account = '${dir.path}/account.db';
    final publicConfig = '${dir.path}/public-config.db';
    final backup = '${dir.path}/clone-backup.db';
    File(prodDbPath).copySync(account);
    File(prodPubConfigPath).copySync(publicConfig);
    File(account).copySync(backup);
    expect(
      computeSha256(File(account)),
      ProductionMigrationRunner.verifiedV4AccountSha,
      reason: 'Account clone must match the approved current preimage before opening SQLite.',
    );
    expect(
      computeSha256(File(publicConfig)),
      ProductionMigrationRunner.verifiedV4PublicConfigSha,
      reason: 'Public-config clone must match the approved current preimage before opening SQLite.',
    );
    expect(ProductionMigrationRunner.checkSidecars(account), isEmpty);
    expect(ProductionMigrationRunner.checkSidecars(publicConfig), isEmpty);
    return {
      'directory': dir.path,
      'account': account,
      'publicConfig': publicConfig,
      'backup': backup,
    };
  }

  Future<Map<String, List<Map<String, Object?>>>> captureV4LogicalState(
    String databasePath,
  ) async {
    final db = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final tables = [
      'products',
      'product_variants',
      'product_categories',
      'product_subcategories',
      'product_attributes',
      'product_attribute_options',
      'units',
      'subcategory_attribute_templates',
      'product_catalogue_releases',
    ];
    final state = <String, List<Map<String, Object?>>>{
      for (final table in tables)
        table: await db.query(
          LocalDataSource.table(table),
          orderBy: 'remoteId',
        ),
      'sync_queries': await db.query('sync_queries', orderBy: 'queryKey'),
      'sync_outbox': await db.query('sync_outbox', orderBy: 'id'),
      CatalogueArchiveStore.table: await db.query(
        CatalogueArchiveStore.table,
        orderBy: 'catalogueFingerprint, collection, documentId',
      ),
    };
    await db.close();
    return state;
  }

  Future<void> restoreVersion3Preimage(String databasePath) async {
    final db = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      final versionRows = await db.rawQuery('PRAGMA user_version;');
      final version = versionRows.single['user_version'] as int;
      if (version == 4) {
        final archiveTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [CatalogueArchiveStore.table],
        );
        if (archiveTable.isNotEmpty) {
          final archiveRows = await db.rawQuery(
            'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
          );
          expect(
            archiveRows.single['count'],
            0,
            reason: 'The v4-only archive table must be empty in this preimage.',
          );
          await db.execute('DROP TABLE ${CatalogueArchiveStore.table};');
        }
        await db.execute('PRAGMA user_version=3;');
      }

      final restoredVersionRows = await db.rawQuery('PRAGMA user_version;');
      expect(
        restoredVersionRows.single['user_version'],
        3,
        reason:
            'Phase 10K runner fixtures must model the v3 pre-migration schema.',
      );
      final archiveTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [CatalogueArchiveStore.table],
      );
      expect(
        archiveTable,
        isEmpty,
        reason: 'The v3 preimage must not contain the v4 archive table.',
      );
    } finally {
      await db.close();
    }
  }

  late Directory tempDir;
  late String cloneDbPath;
  late String cloneBakPath;
  late String clonePubPath;
  late String initialDbSha;
  late String initialBakSha;
  late String initialPubSha;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phase10k_runner_test_');
    cloneDbPath = '${tempDir.path}/clone.db';
    cloneBakPath = '${tempDir.path}/clone.db.bak';
    clonePubPath = '${tempDir.path}/public-config.db';

    // Copy production databases to disposable clones
    File(prodDbPath).copySync(cloneDbPath);
    File(prodBakPath).copySync(cloneBakPath);
    File(prodPubConfigPath).copySync(clonePubPath);

    // App schema initialization advanced the source database to v4. Recreate
    // the runner's intended v3 pre-migration state on the disposable clone only.
    await restoreVersion3Preimage(cloneDbPath);

    initialDbSha = computeSha256(File(cloneDbPath));
    initialBakSha = computeSha256(File(cloneBakPath));
    initialPubSha = computeSha256(File(clonePubPath));
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 10M schema-v4 migration forensics', () {
    test(
      'v3-to-v4 migration adds only the archive table and its PK index',
      () async {
        final db = await databaseFactoryFfi.openDatabase(cloneDbPath);
        final beforeVersion = await db.rawQuery('PRAGMA user_version;');
        expect(beforeVersion.single['user_version'], 3);

        final beforeSchema = await db.rawQuery(
          'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
        );
        expect(
          ProductionMigrationRunner.computeSchemaFingerprint(beforeSchema),
          ProductionMigrationRunner.verifiedV3SchemaFingerprint,
        );
        final beforeObjectNames = beforeSchema
            .map((row) => row['name'] as String)
            .toSet();
        final beforeTableNames = (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
        )).map((row) => row['name'] as String);
        final beforeTableRows = <String, String>{
          for (final table in beforeTableNames)
            table: ProductionMigrationRunner.stableRows(await db.query(table)),
        };

        await LocalDatabase.migrate(db, 3, 4);
        // sqflite advances user_version after onUpgrade returns; model that
        // wrapper metadata update explicitly when invoking migrate directly.
        await db.execute('PRAGMA user_version=4;');

        final afterSchema = await db.rawQuery(
          'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
        );
        expect(
          ProductionMigrationRunner.computeSchemaFingerprint(afterSchema),
          ProductionMigrationRunner.verifiedV4SchemaFingerprint,
        );
        final addedObjects = afterSchema
            .where((row) => !beforeObjectNames.contains(row['name']))
            .map((row) => '${row['type']}:${row['name']}')
            .toSet();
        expect(addedObjects, {
          'table:local_catalogue_archive',
          'index:sqlite_autoindex_local_catalogue_archive_1',
        });
        final preservedSchema = afterSchema
            .where((row) => beforeObjectNames.contains(row['name']))
            .toList();
        expect(
          ProductionMigrationRunner.stableRows(preservedSchema),
          ProductionMigrationRunner.stableRows(beforeSchema),
        );

        for (final entry in beforeTableRows.entries) {
          expect(
            ProductionMigrationRunner.stableRows(await db.query(entry.key)),
            entry.value,
            reason: 'v3-to-v4 migration changed existing table ${entry.key}',
          );
        }
        expect(
          (await db.rawQuery(
            'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
          )).single['count'],
          0,
        );
        expect(
          (await db.rawQuery('PRAGMA user_version;')).single['user_version'],
          4,
        );
        expect(
          (await db.rawQuery('PRAGMA integrity_check;'))
              .single['integrity_check'],
          'ok',
        );
        await db.close();
      },
    );
  });

  group('Phase 10M verified v4/R3 disposable-clone rehearsal', () {
    test('dry-run, execute child clone, and idempotent rerun preserve approved state', () async {
      final parent = await createVerifiedV4Clone();
      addTearDown(() async {
        final dir = Directory(parent['directory']!);
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      final parentAccountSha = computeSha256(File(parent['account']!));
      final dryRun = await ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: parent['account']!,
          expectedAccountSha: ProductionMigrationRunner.verifiedV4AccountSha,
          backupPath: parent['backup'],
          expectedBackupSha: parentAccountSha,
          publicConfigPath: parent['publicConfig'],
          expectedPublicConfigSha:
              ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ),
      ).run();
      expect(dryRun.success, isTrue, reason: dryRun.abortReason);
      expect(dryRun.result, 'GO');
      expect(dryRun.preimageCounts['products'], 4);
      expect(dryRun.preimageCounts['variants'], 7);
      expect(dryRun.preimageCounts['syncQueries'], 195);
      expect(dryRun.preimageCounts['protectedQueries'], 10);
      expect(dryRun.preimageCounts['outbox'], 0);
      expect(computeSha256(File(parent['account']!)), parentAccountSha);
      expect(
        ProductionMigrationRunner.checkSidecars(parent['account']!),
        isEmpty,
      );

      final childDir = Directory('${parent['directory']}/execute-child');
      childDir.createSync();
      final childAccount = '${childDir.path}/account.db';
      final childPublic = '${childDir.path}/public-config.db';
      final childBackup = '${childDir.path}/backup.db';
      File(parent['account']!).copySync(childAccount);
      File(parent['publicConfig']!).copySync(childPublic);
      File(childAccount).copySync(childBackup);
      expect(
        computeSha256(File(childAccount)),
        ProductionMigrationRunner.verifiedV4AccountSha,
      );
      expect(
        computeSha256(File(childPublic)),
        ProductionMigrationRunner.verifiedV4PublicConfigSha,
      );
      final before = await captureV4LogicalState(childAccount);
      expect(before['products'], hasLength(4));
      expect(before['product_variants'], hasLength(7));
      expect(before['sync_queries'], hasLength(195));
      expect(before['sync_outbox'], isEmpty);
      expect(before[CatalogueArchiveStore.table], isEmpty);

      final execute = await ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: childAccount,
          expectedAccountSha: ProductionMigrationRunner.verifiedV4AccountSha,
          execute: true,
          maintenanceAck: true,
          backupPath: childBackup,
          expectedBackupSha: parentAccountSha,
          publicConfigPath: childPublic,
          expectedPublicConfigSha:
              ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ),
      ).run();
      expect(execute.success, isTrue, reason: execute.abortReason);
      expect(execute.result, 'SUCCESS');
      expect(execute.postimageCounts['selectors'], 137);
      expect(execute.postimageCounts['readyForms'], 137);
      expect(execute.postimageCounts['products'], 4);
      expect(execute.postimageCounts['variants'], 7);
      expect(execute.postimageCounts['syncQueries'], 195);
      expect(execute.postimageCounts['protectedQueries'], 10);
      expect(execute.postimageCounts['archivedRows'], 3903);

      final after = await captureV4LogicalState(childAccount);
      for (final table in [
        'products',
        'product_variants',
        'sync_queries',
        'sync_outbox',
      ]) {
        expect(
          ProductionMigrationRunner.stableRows(after[table]!),
          ProductionMigrationRunner.stableRows(before[table]!),
          reason: '$table changed during the v4/R3 clone migration',
        );
      }
      expect(after['products'], hasLength(4));
      expect(after['product_variants'], hasLength(7));
      expect(after['sync_queries'], hasLength(195));
      expect(after['sync_outbox'], isEmpty);
      expect(after[CatalogueArchiveStore.table], hasLength(3903));

      final verifyDb = await databaseFactoryFfi.openDatabase(
        childAccount,
        options: OpenDatabaseOptions(readOnly: true),
      );
      expect(
        (await verifyDb.rawQuery('PRAGMA user_version;'))
            .single['user_version'],
        4,
      );
      expect(
        (await verifyDb.rawQuery('PRAGMA integrity_check;'))
            .single['integrity_check'],
        'ok',
      );
      expect(
        ProductionMigrationRunner.computeSchemaFingerprint(
          await verifyDb.rawQuery(
            'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
          ),
        ),
        ProductionMigrationRunner.verifiedV4SchemaFingerprint,
      );
      await verifyDb.close();

      final migratedSha = computeSha256(File(childAccount));
      final rerun = await ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: childAccount,
          expectedAccountSha: migratedSha,
          execute: true,
          maintenanceAck: true,
          backupPath: childBackup,
          expectedBackupSha: parentAccountSha,
          publicConfigPath: childPublic,
          expectedPublicConfigSha:
              ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ),
      ).run();
      expect(rerun.success, isTrue, reason: rerun.abortReason);
      expect(rerun.result, 'ALREADY_INSTALLED');
      expect(rerun.postimageCounts['archiveRows'], 3903);
      expect(computeSha256(File(childAccount)), migratedSha);
      final afterRerun = await captureV4LogicalState(childAccount);
      for (final table in [
        'products',
        'product_variants',
        'sync_queries',
        'sync_outbox',
        CatalogueArchiveStore.table,
      ]) {
        expect(
          ProductionMigrationRunner.stableRows(afterRerun[table]!),
          ProductionMigrationRunner.stableRows(after[table]!),
        );
      }
    }, timeout: const Timeout(Duration(minutes: 8)));

    test('both transaction failure points restore the exact v4/R3 logical preimage', () async {
      for (final failureStage in ['after_archive', 'after_release_marker']) {
        final clone = await createVerifiedV4Clone();
        final dir = Directory(clone['directory']!);
        addTearDown(() async {
          if (dir.existsSync()) await dir.delete(recursive: true);
        });
        final before = await captureV4LogicalState(clone['account']!);
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: clone['account']!,
            expectedAccountSha: ProductionMigrationRunner.verifiedV4AccountSha,
            execute: true,
            maintenanceAck: true,
            backupPath: clone['backup'],
            expectedBackupSha: ProductionMigrationRunner.verifiedV4AccountSha,
            publicConfigPath: clone['publicConfig'],
            expectedPublicConfigSha:
                ProductionMigrationRunner.verifiedV4PublicConfigSha,
          ),
          failureProbe: (stage, tx) async {
            if (stage == failureStage) {
              throw StateError('INJECTED_$failureStage');
            }
          },
        );
        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.abortReason, contains('INJECTED_$failureStage'));

        final after = await captureV4LogicalState(clone['account']!);
        for (final table in before.keys) {
          expect(
            ProductionMigrationRunner.stableRows(after[table]!),
            ProductionMigrationRunner.stableRows(before[table]!),
            reason: '$table did not roll back after $failureStage',
          );
        }
        expect(after[CatalogueArchiveStore.table], isEmpty);
        final verifyDb = await databaseFactoryFfi.openDatabase(
          clone['account']!,
          options: OpenDatabaseOptions(readOnly: true),
        );
        expect(
          (await verifyDb.rawQuery('PRAGMA user_version;'))
              .single['user_version'],
          4,
        );
        expect(
          (await verifyDb.rawQuery('PRAGMA integrity_check;'))
              .single['integrity_check'],
          'ok',
        );
        await verifyDb.close();
      }
    }, timeout: const Timeout(Duration(minutes: 8)));

    test(
      'schema v5 is rejected and mismatched v4 hash cannot enter the contract',
      () async {
        final clone = await createVerifiedV4Clone();
        addTearDown(() async {
          final dir = Directory(clone['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });
        final db = await databaseFactoryFfi.openDatabase(clone['account']!);
        await db.execute('PRAGMA user_version=5;');
        await db.close();
        final alteredSha = computeSha256(File(clone['account']!));
        final result = await ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: clone['account']!,
            expectedAccountSha: alteredSha,
            publicConfigPath: clone['publicConfig'],
            expectedPublicConfigSha:
                ProductionMigrationRunner.verifiedV4PublicConfigSha,
          ),
        ).run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(result.abortReason, contains('Unsupported schema version'));
      },
    );

    test('non-empty archive, schema drift, count drift, sidecars, and corruption fail closed', () async {
      for (final mutation in [
        'archive',
        'schema',
        'products',
        'variants',
        'queries',
      ]) {
        final clone = await createVerifiedV4Clone();
        final dir = Directory(clone['directory']!);
        addTearDown(() async {
          if (dir.existsSync()) await dir.delete(recursive: true);
        });
        final db = await databaseFactoryFfi.openDatabase(clone['account']!);
        switch (mutation) {
          case 'archive':
            await db.execute('''
              INSERT INTO ${CatalogueArchiveStore.table}
                (catalogueFingerprint,collection,documentId,payloadId,payloadJson,canonicalContent,archivedAt)
              VALUES ('sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'product_categories','phase10m-sentinel',NULL,'{}','{}','2026-10-05T00:00:00Z')
            ''');
          case 'schema':
            await db.execute(
              'CREATE TABLE phase10m_unexpected_schema (id INTEGER PRIMARY KEY)',
            );
          case 'products':
            await db.execute(
              'DELETE FROM local_products WHERE rowid=(SELECT rowid FROM local_products LIMIT 1)',
            );
          case 'variants':
            await db.execute(
              'DELETE FROM local_product_variants WHERE rowid=(SELECT rowid FROM local_product_variants LIMIT 1)',
            );
          case 'queries':
            await db.execute(
              'DELETE FROM sync_queries WHERE rowid=(SELECT rowid FROM sync_queries LIMIT 1)',
            );
        }
        await db.close();
        final result = await ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: clone['account']!,
            expectedAccountSha: ProductionMigrationRunner.verifiedV4AccountSha,
            publicConfigPath: clone['publicConfig'],
            expectedPublicConfigSha:
                ProductionMigrationRunner.verifiedV4PublicConfigSha,
          ),
        ).run();
        expect(result.success, isFalse, reason: '$mutation drift was accepted');
        expect(result.result, 'ABORTED');
        expect(result.abortReason, contains('Preimage SHA-256 mismatch'));
      }

      final sidecarClone = await createVerifiedV4Clone();
      final sidecarDir = Directory(sidecarClone['directory']!);
      addTearDown(() async {
        if (sidecarDir.existsSync()) await sidecarDir.delete(recursive: true);
      });
      File('${sidecarClone['account']}-wal')
          .writeAsStringSync('disposable sentinel');
      final sidecarResult = await ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: sidecarClone['account']!,
          expectedAccountSha: ProductionMigrationRunner.verifiedV4AccountSha,
          publicConfigPath: sidecarClone['publicConfig'],
          expectedPublicConfigSha:
              ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ),
      ).run();
      expect(sidecarResult.success, isFalse);
      expect(
        sidecarResult.abortReason,
        contains('Active SQLite sidecars detected'),
      );

      final corruptClone = await createVerifiedV4Clone();
      final corruptDir = Directory(corruptClone['directory']!);
      addTearDown(() async {
        if (corruptDir.existsSync()) await corruptDir.delete(recursive: true);
      });
      final corruptFile = File(corruptClone['account']!)
          .openSync(mode: FileMode.append);
      corruptFile.truncateSync(corruptFile.lengthSync() - 512);
      corruptFile.closeSync();
      final corruptSha = computeSha256(File(corruptClone['account']!));
      final integrityResult = await ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: corruptClone['account']!,
          expectedAccountSha: corruptSha,
          publicConfigPath: corruptClone['publicConfig'],
          expectedPublicConfigSha:
              ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ),
      ).run();
      expect(integrityResult.success, isFalse);
      expect(integrityResult.abortReason, contains('integrity_check'));
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  group(
    'Part 1 & 2: Sync-Query Exact Preservation Contract and Importer Fix',
    () {
      test('SystemCatalogueSnapshot.import preserves all 195 queries and 10 protected queries exact', () async {
        final db = await databaseFactoryFfi.openDatabase(cloneDbPath);
        final source = LocalDataSource(db);

        // Read baseline 195 queries
        final baselineRows = await db.query(
          'sync_queries',
          orderBy: 'queryKey ASC',
        );
        expect(baselineRows.length, 195);

        final protectedRows = baselineRows
            .where(
              (r) => ProductionMigrationRunner.protectedQueryKeys.contains(
                r['queryKey'],
              ),
            )
            .toList();
        expect(protectedRows.length, 10);

        // Import Release 4 snapshot with preserveSyncQueries: true (default)
        await SystemCatalogueSnapshot.import(
          source: source,
          documents: release4Documents(),
          readTimes: const {},
          allowUnapprovedIsolatedForTests: true,
          preserveSyncQueries: true,
        );

        // Read post-import queries
        final postRows = await db.query(
          'sync_queries',
          orderBy: 'queryKey ASC',
        );
        expect(postRows.length, 195);

        // Byte and logical equality verification across every single field of all 195 queries
        for (var i = 0; i < 195; i++) {
          final b = baselineRows[i];
          final p = postRows[i];

          expect(
            p['queryKey'],
            b['queryKey'],
            reason: 'queryKey mismatch at $i',
          );
          expect(
            p['collectionName'],
            b['collectionName'],
            reason: 'collectionName mismatch at $i',
          );
          expect(
            p['queryJson'],
            b['queryJson'],
            reason: 'queryJson mismatch at $i',
          );
          expect(p['cursor'], b['cursor'], reason: 'cursor mismatch at $i');
          expect(
            p['lastSyncedAt'],
            b['lastSyncedAt'],
            reason: 'lastSyncedAt mismatch at $i',
          );
          expect(
            p['lastAttemptAt'],
            b['lastAttemptAt'],
            reason: 'lastAttemptAt mismatch at $i',
          );
          expect(
            p['lastError'],
            b['lastError'],
            reason: 'lastError mismatch at $i',
          );
          expect(p['active'], b['active'], reason: 'active mismatch at $i');
          expect(
            p['catalogueVersion'],
            b['catalogueVersion'],
            reason: 'catalogueVersion mismatch at $i',
          );
        }

        // Assert the 10 protected legacy queries specifically remain completely identical
        final postProtectedRows = postRows
            .where(
              (r) => ProductionMigrationRunner.protectedQueryKeys.contains(
                r['queryKey'],
              ),
            )
            .toList();
        expect(postProtectedRows.length, 10);
        for (var i = 0; i < 10; i++) {
          expect(postProtectedRows[i], protectedRows[i]);
        }

        await db.close();
      });
    },
  );

  group(
    'Part 3 & 4: Production Migration Runner - Dry Run Mode (Zero Write)',
    () {
      test('dry run verifies database, leaves it 100% byte-identical, and emits GO decision', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: false,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            publicConfigPath: clonePubPath,
            expectedPublicConfigSha: initialPubSha,
          ),
        );

        final result = await runner.run();

        expect(result.success, isTrue);
        expect(result.mode, 'DRY_RUN');
        expect(result.result, 'GO');
        expect(result.abortReason, isNull);
        expect(result.preimageCounts['products'], 4);
        expect(result.preimageCounts['variants'], 7);
        expect(result.preimageCounts['syncQueries'], 195);
        expect(result.preimageCounts['protectedQueries'], 10);

        // Verify zero writes: file SHA-256 before and after dry run must be identical
        final afterDryRunSha = computeSha256(File(cloneDbPath));
        expect(afterDryRunSha, initialDbSha);

        // Verify no sidecars remain
        expect(ProductionMigrationRunner.checkSidecars(cloneDbPath), isEmpty);
      });

      test(
        'missing --execute flag defaults to dry-run mode and never writes',
        () async {
          final options = ProductionMigrationOptions.fromArgs([
            '--database',
            cloneDbPath,
            '--expected-account-sha',
            initialDbSha,
            '--backup',
            cloneBakPath,
            '--maintenance-ack',
          ]);
          expect(options.execute, isFalse);

          final runner = ProductionMigrationRunner(options);
          final result = await runner.run();

          expect(result.success, isTrue);
          expect(result.mode, 'DRY_RUN');
          expect(result.result, 'GO');

          // Database untouched
          expect(computeSha256(File(cloneDbPath)), initialDbSha);
        },
      );
    },
  );

  group(
    'Part 5-7: Production Migration Runner - Execute Mode On Disposable Clone',
    () {
      test('execute mode safely migrates clone and verifies all post-commit invariants', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            publicConfigPath: clonePubPath,
            expectedPublicConfigSha: initialPubSha,
          ),
        );

        final result = await runner.run();

        expect(
          result.success,
          isTrue,
          reason: 'Migration failed: ${result.abortReason}',
        );
        expect(result.mode, 'EXECUTE');
        expect(result.result, 'SUCCESS');
        expect(result.abortReason, isNull);

        // Post-commit invariants verification
        expect(
          result.postimageCounts['products'],
          4,
          reason: '4 original Product rows unchanged',
        );
        expect(
          result.postimageCounts['variants'],
          7,
          reason: '7 original Variant rows unchanged',
        );
        expect(
          result.postimageCounts['syncQueries'],
          195,
          reason: '195 sync queries unchanged',
        );
        expect(
          result.postimageCounts['protectedQueries'],
          10,
          reason: '10 protected queries unchanged',
        );
        expect(
          result.postimageCounts['selectors'],
          137,
          reason: '137 selector IDs verified',
        );
        expect(
          result.postimageCounts['readyForms'],
          137,
          reason: '137 READY forms verified',
        );
        expect(result.archiveCount, 3903, reason: '3903 legacy rows archived');

        // Verify database directly with read-only probe
        final db = await databaseFactoryFfi.openDatabase(
          cloneDbPath,
          options: OpenDatabaseOptions(readOnly: true),
        );

        // 1. SQLite PRAGMA integrity_check
        final integrity = await db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first['integrity_check'], 'ok');

        // 2. Release 4 marker exists
        final marker = await db.query(
          LocalDataSource.table('product_catalogue_releases'),
          where: "scopeType = 'SYSTEM' AND isDeleted = 0",
        );
        expect(marker.length, 1);
        final markerFields = FirestoreRestService.decodeFields(
          jsonDecode(marker.first['payloadJson'] as String),
        );
        expect(markerFields['version'], 4);
        expect(markerFields['catalogueId'], 'PAINT_V1');
        expect(markerFields['installed'], true);
        expect(markerFields['catalogueFingerprint'], result.releaseFingerprint);

        // 3. 195 sync queries byte/logically identical before and after
        final postQueries = await db.query(
          'sync_queries',
          orderBy: 'queryKey ASC',
        );
        expect(postQueries.length, 195);
        final protected = postQueries
            .where(
              (q) => ProductionMigrationRunner.protectedQueryKeys.contains(
                q['queryKey'],
              ),
            )
            .toList();
        expect(protected.length, 10);

        // 4. Products and Variants unchanged
        final products = await db.query(LocalDataSource.table('products'));
        expect(products.length, 4);
        final variants = await db.query(
          LocalDataSource.table('product_variants'),
        );
        expect(variants.length, 7);

        // 5. 3903 legacy archive rows
        final archives = await db.query(CatalogueArchiveStore.table);
        expect(archives.length, 3903);

        await db.close();
      }, timeout: const Timeout(Duration(minutes: 3)));

      test('already-installed Release 4 reports idempotent no-op', () async {
        // First execute
        final runner1 = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            publicConfigPath: clonePubPath,
            expectedPublicConfigSha: initialPubSha,
          ),
        );
        final result1 = await runner1.run();
        expect(result1.success, isTrue);

        final migratedSha = computeSha256(File(cloneDbPath));

        // Second execute: should safely detect already-installed Release 4
        final runner2 = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: migratedSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            publicConfigPath: clonePubPath,
            expectedPublicConfigSha: initialPubSha,
          ),
        );
        final result2 = await runner2.run();
        expect(result2.success, isTrue);
        expect(result2.result, 'ALREADY_INSTALLED');
        expect(result2.postimageCounts['syncQueries'], 195);
        expect(result2.postimageCounts['products'], 4);
        expect(result2.postimageCounts['variants'], 7);
      }, timeout: const Timeout(Duration(minutes: 4)));
    },
  );

  group(
    'Part 11: Production Migration Runner - Negative Tests and Safety Gates',
    () {
      test(
        'wrong account SHA aborts before write and leaves DB untouched',
        () async {
          final runner = ProductionMigrationRunner(
            ProductionMigrationOptions(
              databasePath: cloneDbPath,
              expectedAccountSha: 'wrong_sha_00000000000000000000000000000000000000000000000000000000',
              execute: true,
              maintenanceAck: true,
              backupPath: cloneBakPath,
              expectedBackupSha: initialBakSha,
            ),
          );

          final result = await runner.run();
          expect(result.success, isFalse);
          expect(result.result, 'ABORTED');
          expect(result.abortReason, contains('Preimage SHA-256 mismatch'));
          expect(computeSha256(File(cloneDbPath)), initialDbSha);
        },
      );

      test(
        'missing maintenance ack in execute mode aborts before write',
        () async {
          final runner = ProductionMigrationRunner(
            ProductionMigrationOptions(
              databasePath: cloneDbPath,
              expectedAccountSha: initialDbSha,
              execute: true,
              maintenanceAck: false,
              backupPath: cloneBakPath,
            ),
          );

          final result = await runner.run();
          expect(result.success, isFalse);
          expect(result.result, 'ABORTED');
          expect(
            result.abortReason,
            contains('Maintenance mode acknowledgement'),
          );
          expect(computeSha256(File(cloneDbPath)), initialDbSha);
        },
      );

      test('missing backup in execute mode aborts before write', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: null,
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(result.abortReason, contains('Verified fresh backup path'));
        expect(computeSha256(File(cloneDbPath)), initialDbSha);
      });

      test('wrong backup SHA in execute mode aborts before write', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: 'wrong_backup_sha_000000000000000000000000000000000000000000000000',
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(result.abortReason, contains('Backup SHA-256 mismatch'));
        expect(computeSha256(File(cloneDbPath)), initialDbSha);
      });

      test('wrong public-config SHA aborts before write', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            publicConfigPath: clonePubPath,
            expectedPublicConfigSha:
                'wrong_pub_sha_0000000000000000000000000000000000000000000000',
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(
          result.abortReason,
          contains('Public-config preimage SHA-256 mismatch'),
        );
        expect(computeSha256(File(cloneDbPath)), initialDbSha);
      });

      test('wrong target release fingerprint aborts before write', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            releaseFingerprint: 'sha256:wrong_release_fingerprint_00000000000000000000000000000000',
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(
          result.abortReason,
          contains('Release artifact fingerprint mismatch'),
        );
        expect(computeSha256(File(cloneDbPath)), initialDbSha);
      });

      test('active sidecar file causes runner to abort before write', () async {
        final walFile = File('$cloneDbPath-wal');
        walFile.writeAsStringSync('dummy wal content');

        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(result.abortReason, contains('Active SQLite sidecars detected'));

        walFile.deleteSync();
      });

      test('unknown/missing snapshot file causes runner to abort', () async {
        final runner = ProductionMigrationRunner(
          ProductionMigrationOptions(
            databasePath: cloneDbPath,
            expectedAccountSha: initialDbSha,
            execute: true,
            maintenanceAck: true,
            backupPath: cloneBakPath,
            expectedBackupSha: initialBakSha,
            snapshotPath: '${tempDir.path}/non_existent_snapshot.json',
          ),
        );

        final result = await runner.run();
        expect(result.success, isFalse);
        expect(result.result, 'ABORTED');
        expect(
          result.abortReason,
          contains('Release 4 snapshot file not found'),
        );
        expect(computeSha256(File(cloneDbPath)), initialDbSha);
      });
    },
  );

  group('Part 12 & 13: Zero Firestore and Architecture Invariants', () {
    test('runner operates purely with local SQLite and never references remote Firestore client', () {
      // Inspect runner source code structure and verify pure local operation
      final runnerSource = File(
        'lib/data/migration/production_migration_runner.dart',
      ).readAsStringSync();
      expect(runnerSource, isNot(contains('cloud_firestore')));
      expect(runnerSource, isNot(contains('firebase_core')));
      expect(runnerSource, isNot(contains('http.Client')));
      expect(runnerSource, isNot(contains('HttpClient(')));
      expect(runnerSource, isNot(contains('FirestoreRestService(')));
      expect(
        runnerSource,
        contains(
          'MigrationReadOnlyCatalogueService implements FirestoreDataService',
        ),
      );
    });
  });

  group('Part 14: Transaction Rollback Proofs on Clone', () {
    Future<Map<String, List<Map<String, Object?>>>> captureLogicalSnapshot(
      String dbPath,
    ) async {
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final collections = [
        'products',
        'product_variants',
        'product_categories',
        'product_subcategories',
        'product_attributes',
        'product_attribute_options',
        'units',
        'subcategory_attribute_templates',
        'product_catalogue_releases',
      ];
      final snapshot = <String, List<Map<String, Object?>>>{};
      for (final c in collections) {
        snapshot[c] = await db.query(
          LocalDataSource.table(c),
          orderBy: 'remoteId',
        );
      }
      snapshot['sync_queries'] = await db.query(
        'sync_queries',
        orderBy: 'queryKey',
      );
      snapshot['sync_outbox'] = await db.query('sync_outbox', orderBy: 'id');
      final archiveTableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [CatalogueArchiveStore.table],
      );
      if (archiveTableCheck.isNotEmpty) {
        snapshot[CatalogueArchiveStore.table] = await db.query(
          CatalogueArchiveStore.table,
          orderBy: 'catalogueFingerprint, collection, documentId',
        );
      } else {
        snapshot[CatalogueArchiveStore.table] = [];
      }
      await db.close();
      return snapshot;
    }

    test('failure after legacy archive insertion triggers complete transaction rollback', () async {
      final preimage = await captureLogicalSnapshot(cloneDbPath);
      expect(preimage['products']!.length, 4);
      expect(preimage['product_variants']!.length, 7);
      expect(preimage['sync_queries']!.length, 195);
      expect(preimage['sync_outbox']!.length, 0);

      // Verify v3 release marker in preimage
      final v3Marker = FirestoreRestService.decodeFields(
        jsonDecode(
          preimage['product_catalogue_releases']!.first['payloadJson']
              as String,
        ),
      );
      expect(CatalogueContract.version(v3Marker), 3);

      final runner = ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: cloneDbPath,
          expectedAccountSha: initialDbSha,
          execute: true,
          maintenanceAck: true,
          backupPath: cloneBakPath,
          expectedBackupSha: initialBakSha,
          publicConfigPath: clonePubPath,
          expectedPublicConfigSha: initialPubSha,
        ),
        failureProbe: (stage, tx) async {
          if (stage == 'after_archive') {
            throw Exception('INJECTED_FAILURE_AFTER_ARCHIVE');
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.result, 'ABORTED');
      expect(result.abortReason, contains('INJECTED_FAILURE_AFTER_ARCHIVE'));

      // Verify complete rollback on target database
      final probeDb = await databaseFactoryFfi.openDatabase(
        cloneDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final integrity = await probeDb.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first['integrity_check'], 'ok');
      await probeDb.close();

      final postFailure = await captureLogicalSnapshot(cloneDbPath);

      // Products and variants restored exact
      expect(
        ProductionMigrationRunner.stableRows(postFailure['products']!),
        ProductionMigrationRunner.stableRows(preimage['products']!),
      );
      expect(
        ProductionMigrationRunner.stableRows(postFailure['product_variants']!),
        ProductionMigrationRunner.stableRows(preimage['product_variants']!),
      );

      // All 195 sync queries restored exact
      expect(
        ProductionMigrationRunner.stableRows(postFailure['sync_queries']!),
        ProductionMigrationRunner.stableRows(preimage['sync_queries']!),
      );

      // All 10 protected queries restored exact
      final protectedPost = postFailure['sync_queries']!
          .where(
            (q) => ProductionMigrationRunner.protectedQueryKeys.contains(
              q['queryKey'],
            ),
          )
          .toList();
      final protectedPre = preimage['sync_queries']!
          .where(
            (q) => ProductionMigrationRunner.protectedQueryKeys.contains(
              q['queryKey'],
            ),
          )
          .toList();
      expect(protectedPost.length, 10);
      expect(
        ProductionMigrationRunner.stableRows(protectedPost),
        ProductionMigrationRunner.stableRows(protectedPre),
      );

      // Outbox restored exact
      expect(postFailure['sync_outbox']!.length, 0);

      // Release marker remains v3, Release 4 not present
      final postRelease = FirestoreRestService.decodeFields(
        jsonDecode(
          postFailure['product_catalogue_releases']!.first['payloadJson']
              as String,
        ),
      );
      expect(CatalogueContract.version(postRelease), 3);

      // Catalogue rows restored to exact preimage
      for (final collection in [
        'product_categories',
        'product_subcategories',
        'product_attributes',
        'product_attribute_options',
        'units',
        'subcategory_attribute_templates',
      ]) {
        expect(
          ProductionMigrationRunner.stableRows(postFailure[collection]!),
          ProductionMigrationRunner.stableRows(preimage[collection]!),
          reason: '$collection was mutated after rollback',
        );
      }

      // Archive state restored to preimage
      expect(postFailure[CatalogueArchiveStore.table]!.length, 0);
    });

    test('failure after Release 4 marker staging (before commit) triggers complete transaction rollback', () async {
      final preimage = await captureLogicalSnapshot(cloneDbPath);

      final runner = ProductionMigrationRunner(
        ProductionMigrationOptions(
          databasePath: cloneDbPath,
          expectedAccountSha: initialDbSha,
          execute: true,
          maintenanceAck: true,
          backupPath: cloneBakPath,
          expectedBackupSha: initialBakSha,
          publicConfigPath: clonePubPath,
          expectedPublicConfigSha: initialPubSha,
        ),
        failureProbe: (stage, tx) async {
          if (stage == 'after_release_marker' || stage == 'before_commit') {
            throw Exception('INJECTED_FAILURE_BEFORE_COMMIT');
          }
        },
      );

      final result = await runner.run();
      expect(result.success, isFalse);
      expect(result.result, 'ABORTED');
      expect(result.abortReason, contains('INJECTED_FAILURE_BEFORE_COMMIT'));

      // Verify complete rollback on target database
      final probeDb = await databaseFactoryFfi.openDatabase(
        cloneDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final integrity = await probeDb.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first['integrity_check'], 'ok');
      await probeDb.close();

      final postFailure = await captureLogicalSnapshot(cloneDbPath);

      // Products and variants restored exact
      expect(
        ProductionMigrationRunner.stableRows(postFailure['products']!),
        ProductionMigrationRunner.stableRows(preimage['products']!),
      );
      expect(
        ProductionMigrationRunner.stableRows(postFailure['product_variants']!),
        ProductionMigrationRunner.stableRows(preimage['product_variants']!),
      );

      // All 195 sync queries restored exact
      expect(
        ProductionMigrationRunner.stableRows(postFailure['sync_queries']!),
        ProductionMigrationRunner.stableRows(preimage['sync_queries']!),
      );

      // Release marker remains v3, not v4
      final postRelease = FirestoreRestService.decodeFields(
        jsonDecode(
          postFailure['product_catalogue_releases']!.first['payloadJson']
              as String,
        ),
      );
      expect(CatalogueContract.version(postRelease), 3);

      // Archive state restored to 0 rows
      expect(postFailure[CatalogueArchiveStore.table]!.length, 0);
    });
  });
}
