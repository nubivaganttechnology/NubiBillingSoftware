import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/errors/app_exception.dart';
import '../catalogue/catalogue_contract.dart';
import '../catalogue/catalogue_fingerprint.dart';
import '../catalogue/system_catalogue_metadata.dart';
import '../catalogue/system_catalogue_snapshot.dart';
import '../local/catalogue_archive_store.dart';
import '../local/local_data_source.dart';
import '../models/resolved_product_template.dart';
import '../services/catalogue_selection_resolver.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_value_codec.dart';
import '../services/historical_catalogue_resolver.dart';
import '../services/product_template_resolver.dart';

/// Read-only catalogue service adapter using local SQLite tables.
/// Does not construct any HTTP, remote, or Firestore client.
class MigrationReadOnlyCatalogueService implements FirestoreDataService {
  MigrationReadOnlyCatalogueService(this.source);
  final LocalDataSource source;

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => source.query(
    collection,
    filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Read-only catalogue service query only');
}

/// Options configuring the supported production migration runner.
class ProductionMigrationOptions {
  const ProductionMigrationOptions({
    required this.databasePath,
    required this.expectedAccountSha,
    this.execute = false,
    this.releaseFingerprint = 'sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88',
    this.snapshotPath,
    this.backupPath,
    this.expectedBackupSha,
    this.publicConfigPath,
    this.expectedPublicConfigSha,
    this.maintenanceAck = false,
    this.expectedProducts = 4,
    this.expectedVariants = 7,
    this.expectedQueries = 195,
    this.expectedProtectedQueries = 10,
    this.expectedOutbox = 0,
    this.expectedLegacyRows = 3903,
    this.expectedLegacyFingerprint = 'sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b',
    this.jsonOutput = false,
    this.reportFilePath,
  });

  final String databasePath;
  final String expectedAccountSha;
  final bool execute;
  final String releaseFingerprint;
  final String? snapshotPath;
  final String? backupPath;
  final String? expectedBackupSha;
  final String? publicConfigPath;
  final String? expectedPublicConfigSha;
  final bool maintenanceAck;
  final int expectedProducts;
  final int expectedVariants;
  final int expectedQueries;
  final int expectedProtectedQueries;
  final int expectedOutbox;
  final int expectedLegacyRows;
  final String expectedLegacyFingerprint;
  final bool jsonOutput;
  final String? reportFilePath;

  static ProductionMigrationOptions fromArgs(List<String> args) {
    String? databasePath;
    String? expectedAccountSha;
    bool execute = false;
    String releaseFingerprint =
        'sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88';
    String? snapshotPath;
    String? backupPath;
    String? expectedBackupSha;
    String? publicConfigPath;
    String? expectedPublicConfigSha;
    bool maintenanceAck = false;
    int expectedProducts = 4;
    int expectedVariants = 7;
    int expectedQueries = 195;
    int expectedProtectedQueries = 10;
    int expectedOutbox = 0;
    bool jsonOutput = false;
    String? reportFilePath;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--execute') {
        execute = true;
      } else if (arg == '--dry-run') {
        execute = false;
      } else if (arg == '--maintenance-ack' ||
          arg == '--maintenance-mode-acknowledged') {
        maintenanceAck = true;
      } else if (arg == '--json') {
        jsonOutput = true;
      } else if (arg == '--database' || arg == '-d') {
        if (i + 1 < args.length) databasePath = args[++i];
      } else if (arg.startsWith('--database=')) {
        databasePath = arg.substring('--database='.length);
      } else if (arg == '--expected-account-sha' ||
          arg == '--expected-preimage-sha') {
        if (i + 1 < args.length) expectedAccountSha = args[++i];
      } else if (arg.startsWith('--expected-account-sha=')) {
        expectedAccountSha = arg.substring('--expected-account-sha='.length);
      } else if (arg == '--release-fingerprint') {
        if (i + 1 < args.length) releaseFingerprint = args[++i];
      } else if (arg.startsWith('--release-fingerprint=')) {
        releaseFingerprint = arg.substring('--release-fingerprint='.length);
      } else if (arg == '--snapshot' || arg == '--snapshot-path') {
        if (i + 1 < args.length) snapshotPath = args[++i];
      } else if (arg.startsWith('--snapshot=')) {
        snapshotPath = arg.substring('--snapshot='.length);
      } else if (arg == '--backup' || arg == '--backup-path') {
        if (i + 1 < args.length) backupPath = args[++i];
      } else if (arg.startsWith('--backup=')) {
        backupPath = arg.substring('--backup='.length);
      } else if (arg == '--expected-backup-sha') {
        if (i + 1 < args.length) expectedBackupSha = args[++i];
      } else if (arg.startsWith('--expected-backup-sha=')) {
        expectedBackupSha = arg.substring('--expected-backup-sha='.length);
      } else if (arg == '--public-config') {
        if (i + 1 < args.length) publicConfigPath = args[++i];
      } else if (arg.startsWith('--public-config=')) {
        publicConfigPath = arg.substring('--public-config='.length);
      } else if (arg == '--expected-public-config-sha') {
        if (i + 1 < args.length) expectedPublicConfigSha = args[++i];
      } else if (arg.startsWith('--expected-public-config-sha=')) {
        expectedPublicConfigSha = arg.substring(
          '--expected-public-config-sha='.length,
        );
      } else if (arg == '--report-file') {
        if (i + 1 < args.length) reportFilePath = args[++i];
      } else if (arg.startsWith('--report-file=')) {
        reportFilePath = arg.substring('--report-file='.length);
      } else if (arg == '--expected-products') {
        if (i + 1 < args.length) expectedProducts = int.parse(args[++i]);
      } else if (arg == '--expected-variants') {
        if (i + 1 < args.length) expectedVariants = int.parse(args[++i]);
      } else if (arg == '--expected-queries') {
        if (i + 1 < args.length) expectedQueries = int.parse(args[++i]);
      } else if (arg == '--expected-outbox') {
        if (i + 1 < args.length) expectedOutbox = int.parse(args[++i]);
      }
    }

    if (databasePath == null || databasePath.isEmpty) {
      throw const AppException(
        'Database path argument (--database) is required.',
      );
    }
    if (expectedAccountSha == null || expectedAccountSha.isEmpty) {
      throw const AppException(
        'Expected account preimage SHA-256 argument (--expected-account-sha) is required.',
      );
    }

    return ProductionMigrationOptions(
      databasePath: databasePath,
      expectedAccountSha: expectedAccountSha,
      execute: execute,
      releaseFingerprint: releaseFingerprint,
      snapshotPath: snapshotPath,
      backupPath: backupPath,
      expectedBackupSha: expectedBackupSha,
      publicConfigPath: publicConfigPath,
      expectedPublicConfigSha: expectedPublicConfigSha,
      maintenanceAck: maintenanceAck,
      expectedProducts: expectedProducts,
      expectedVariants: expectedVariants,
      expectedQueries: expectedQueries,
      expectedProtectedQueries: expectedProtectedQueries,
      expectedOutbox: expectedOutbox,
      jsonOutput: jsonOutput,
      reportFilePath: reportFilePath,
    );
  }
}

/// Structured machine-readable migration result.
class ProductionMigrationResult {
  const ProductionMigrationResult({
    required this.mode,
    required this.result,
    required this.success,
    required this.sourceHashes,
    required this.backupHashes,
    required this.releaseFingerprint,
    this.legacyFingerprint,
    this.preimageCounts = const {},
    this.postimageCounts = const {},
    this.queryDigestBefore,
    this.queryDigestAfter,
    this.archiveCount,
    this.archiveDigest,
    this.abortReason,
    this.log = const [],
  });

  final String mode; // DRY_RUN | EXECUTE
  final String result; // GO | NO_GO | SUCCESS | ABORTED | ALREADY_INSTALLED | ROLLBACK_REQUIRED
  final bool success;
  final Map<String, dynamic> sourceHashes;
  final Map<String, dynamic> backupHashes;
  final String releaseFingerprint;
  final String? legacyFingerprint;
  final Map<String, dynamic> preimageCounts;
  final Map<String, dynamic> postimageCounts;
  final String? queryDigestBefore;
  final String? queryDigestAfter;
  final int? archiveCount;
  final String? archiveDigest;
  final String? abortReason;
  final List<String> log;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'mode': mode,
      'result': result,
      'success': success,
      'sourceHashes': sourceHashes,
      'backupHashes': backupHashes,
      'releaseFingerprint': releaseFingerprint,
      'preimageCounts': preimageCounts,
      'postimageCounts': postimageCounts,
      'log': log,
    };
    if (legacyFingerprint != null) map['legacyFingerprint'] = legacyFingerprint;
    if (queryDigestBefore != null) map['queryDigestBefore'] = queryDigestBefore;
    if (queryDigestAfter != null) map['queryDigestAfter'] = queryDigestAfter;
    if (archiveCount != null) map['archiveCount'] = archiveCount;
    if (archiveDigest != null) map['archiveDigest'] = archiveDigest;
    if (abortReason != null) map['abortReason'] = abortReason;
    return map;
  }
}

/// First-class repository-supported production migration runner.
class ProductionMigrationRunner {
  ProductionMigrationRunner(this.options, {this.failureProbe});

  final ProductionMigrationOptions options;
  final Future<void> Function(String stage, DatabaseExecutor tx)? failureProbe;
  final List<String> _logLines = [];

  static const List<String> protectedQueryKeys = [
    'product_subcategories:{"filters":[{"field":"businessId","operation":"EQUAL","value":{"stringValue":"BUS-6CB1F7443C2142159B8EBE3F9303839B"}},{"field":"categoryId","operation":"EQUAL","value":{"stringValue":"SYS_CATEGORY_ACCESSORIES"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}},{"field":"tenantId","operation":"EQUAL","value":{"stringValue":"C6btLkx5SyZvUQOzOeUUd7XxsFh2"}}]}',
    'product_subcategories:{"filters":[{"field":"businessId","operation":"EQUAL","value":{"stringValue":"BUS-6CB1F7443C2142159B8EBE3F9303839B"}},{"field":"categoryId","operation":"EQUAL","value":{"stringValue":"SYS_CATEGORY_EXTERIOR_WALL_PAINTS"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}},{"field":"tenantId","operation":"EQUAL","value":{"stringValue":"C6btLkx5SyZvUQOzOeUUd7XxsFh2"}}]}',
    'product_subcategories:{"filters":[{"field":"categoryId","operation":"EQUAL","value":{"stringValue":"SYS_CATEGORY_ACCESSORIES"}},{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"SYSTEM"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}}]}',
    'product_subcategories:{"filters":[{"field":"categoryId","operation":"EQUAL","value":{"stringValue":"SYS_CATEGORY_EXTERIOR_WALL_PAINTS"}},{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"SYSTEM"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"businessId","operation":"EQUAL","value":{"stringValue":"BUS-6CB1F7443C2142159B8EBE3F9303839B"}},{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"BUSINESS"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"PM_SUBCATEGORY_ce0bf39843417fca"}},{"field":"tenantId","operation":"EQUAL","value":{"stringValue":"C6btLkx5SyZvUQOzOeUUd7XxsFh2"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"businessId","operation":"EQUAL","value":{"stringValue":"BUS-6CB1F7443C2142159B8EBE3F9303839B"}},{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"BUSINESS"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH"}},{"field":"tenantId","operation":"EQUAL","value":{"stringValue":"C6btLkx5SyZvUQOzOeUUd7XxsFh2"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"businessId","operation":"EQUAL","value":{"stringValue":"BUS-6CB1F7443C2142159B8EBE3F9303839B"}},{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"BUSINESS"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS"}},{"field":"tenantId","operation":"EQUAL","value":{"stringValue":"C6btLkx5SyZvUQOzOeUUd7XxsFh2"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"SYSTEM"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"PM_SUBCATEGORY_ce0bf39843417fca"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"SYSTEM"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH"}}]}',
    'subcategory_attribute_templates:{"filters":[{"field":"scopeType","operation":"EQUAL","value":{"stringValue":"SYSTEM"}},{"field":"status","operation":"EQUAL","value":{"stringValue":"ACTIVE"}},{"field":"subcategoryId","operation":"EQUAL","value":{"stringValue":"SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS"}}]}',
  ];

  static const verifiedV4AccountSha =
      '2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8';
  static const verifiedV4PublicConfigSha =
      '9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289';
  static const verifiedV4SchemaFingerprint =
      '3996e1e7582713956302aab1c5578e0f22bab52f5b5f0cb376ce34eb9bf18d18';
  static const verifiedV3SchemaFingerprint =
      'ccd6c9a5a94b52dc181b1553c988d71a9366020b058a183981ca43553c9d492a';
  static const _verifiedV4ArchiveSql =
      'CREATE TABLE local_catalogue_archive ( catalogueFingerprint TEXT NOT NULL, collection TEXT NOT NULL, documentId TEXT NOT NULL, payloadId TEXT, payloadJson TEXT NOT NULL, canonicalContent TEXT NOT NULL, archivedAt TEXT NOT NULL, PRIMARY KEY (catalogueFingerprint, collection, documentId) )';

  static String computeSchemaFingerprint(
    List<Map<String, Object?>> schemaRows,
  ) {
    final canonicalRows = schemaRows.map(
      (row) =>
          '${row['type']}|${row['name']}|${row['tbl_name']}|${row['sql'] ?? ''}',
    );
    return sha256
        .convert(utf8.encode('${canonicalRows.join('\n')}\n'))
        .toString();
  }

  static String _normalizeSchemaSql(String sql) =>
      sql.replaceAll(RegExp(r'\s+'), ' ').trim();

  void _log(String message) {
    _logLines.add(message);
    if (!options.jsonOutput) {
      // ignore: avoid_print
      print(message);
    }
  }

  static String stableRows(List<Map<String, Object?>> rows) {
    final encoded = rows.map((row) {
      final keys = row.keys.toList()..sort();
      return jsonEncode({for (final key in keys) key: row[key]});
    }).toList()..sort();
    return jsonEncode(encoded);
  }

  static String computeDigest(List<Map<String, Object?>> rows) {
    return sha256.convert(utf8.encode(stableRows(rows))).toString();
  }

  static Map<String, dynamic> _sourceHashes(
    String pre,
    String post,
    String? pub,
  ) {
    final map = <String, dynamic>{
      'accountPreimageSha': pre,
      'accountPostimageSha': post,
    };
    if (pub != null) map['publicConfigSha'] = pub;
    return map;
  }

  static Map<String, dynamic> _backupHashes(String? path, String? sha) {
    final map = <String, dynamic>{};
    if (path != null) map['backupPath'] = path;
    if (sha != null) map['backupSha'] = sha;
    return map;
  }

  static String computeFileSha256(File file) {
    return sha256.convert(file.readAsBytesSync()).toString();
  }

  static List<String> checkSidecars(String filePath) {
    final sidecars = <String>[];
    for (final ext in ['-wal', '-shm', '-journal']) {
      if (File('$filePath$ext').existsSync()) {
        sidecars.add('$filePath$ext');
      }
    }
    return sidecars;
  }

  Future<ProductionMigrationResult> run() async {
    final mode = options.execute ? 'EXECUTE' : 'DRY_RUN';
    _log('=== NubiBill Catalogue Production Migration Runner ===');
    _log('Mode: $mode');
    _log('Database: ${options.databasePath}');
    _log('Expected Account SHA-256: ${options.expectedAccountSha}');
    _log('Target Release Fingerprint: ${options.releaseFingerprint}');

    final sourceFile = File(options.databasePath);
    if (!sourceFile.existsSync()) {
      return _abort(
        mode: mode,
        reason: 'Database file does not exist: ${options.databasePath}',
      );
    }

    final sidecars = checkSidecars(options.databasePath);
    if (sidecars.isNotEmpty) {
      return _abort(
        mode: mode,
        reason: 'Active SQLite sidecars detected for database: $sidecars',
      );
    }

    final currentSha = computeFileSha256(sourceFile);
    if (currentSha != options.expectedAccountSha) {
      return _abort(
        mode: mode,
        reason:
            'Preimage SHA-256 mismatch: expected ${options.expectedAccountSha} but found $currentSha',
      );
    }
    _log('Preimage SHA-256 verified: $currentSha');

    String? publicConfigSha;
    if (options.publicConfigPath != null) {
      final pubFile = File(options.publicConfigPath!);
      if (!pubFile.existsSync()) {
        return _abort(
          mode: mode,
          reason: 'Public config file not found: ${options.publicConfigPath}',
        );
      }
      final pubSidecars = checkSidecars(options.publicConfigPath!);
      if (pubSidecars.isNotEmpty) {
        return _abort(
          mode: mode,
          reason:
              'Active SQLite sidecars detected for public-config: $pubSidecars',
        );
      }
      publicConfigSha = computeFileSha256(pubFile);
      if (options.expectedPublicConfigSha != null &&
          publicConfigSha != options.expectedPublicConfigSha) {
        return _abort(
          mode: mode,
          reason:
              'Public-config preimage SHA-256 mismatch: expected ${options.expectedPublicConfigSha} but found $publicConfigSha',
        );
      }
      _log('Public config preimage SHA-256 verified: $publicConfigSha');
    }

    // Execute-mode gate validations before any write connection
    String? backupSha;
    if (options.execute) {
      if (!options.maintenanceAck) {
        return _abort(
          mode: mode,
          reason: 'Maintenance mode acknowledgement (--maintenance-ack) is required for execution mode.',
        );
      }
      if (options.backupPath == null || options.backupPath!.isEmpty) {
        return _abort(
          mode: mode,
          reason: 'Verified fresh backup path (--backup) is required for execution mode.',
        );
      }
      final backupFile = File(options.backupPath!);
      if (!backupFile.existsSync() || backupFile.lengthSync() == 0) {
        return _abort(
          mode: mode,
          reason:
              'Backup file does not exist or is empty: ${options.backupPath}',
        );
      }
      if (backupFile.path == sourceFile.path) {
        return _abort(
          mode: mode,
          reason: 'Backup path cannot be identical to source database path.',
        );
      }
      final backupSidecars = checkSidecars(options.backupPath!);
      if (backupSidecars.isNotEmpty) {
        return _abort(
          mode: mode,
          reason: 'Active SQLite sidecars detected for backup: $backupSidecars',
        );
      }
      backupSha = computeFileSha256(backupFile);
      if (options.expectedBackupSha != null &&
          backupSha != options.expectedBackupSha) {
        return _abort(
          mode: mode,
          reason:
              'Backup SHA-256 mismatch: expected ${options.expectedBackupSha} but found $backupSha',
        );
      }

      sqfliteFfiInit();
      final backupDb = await databaseFactoryFfi.openDatabase(
        options.backupPath!,
        options: OpenDatabaseOptions(readOnly: true),
      );
      final backupIntegrity = await backupDb.rawQuery(
        'PRAGMA integrity_check;',
      );
      await backupDb.close();
      if (backupIntegrity.isEmpty ||
          backupIntegrity.first['integrity_check'] != 'ok') {
        return _abort(
          mode: mode,
          reason: 'Backup failed PRAGMA integrity_check: $backupIntegrity',
        );
      }
      _log('Backup verified: ${options.backupPath} ($backupSha, integrity ok)');
    }

    // Load and validate Release 4 artifact
    final snapshotFile = File(
      options.snapshotPath ?? 'test/fixtures/system_catalogue_v4.json',
    );
    if (!snapshotFile.existsSync()) {
      return _abort(
        mode: mode,
        reason: 'Release 4 snapshot file not found: ${snapshotFile.path}',
      );
    }
    final dynamic snapshotRaw;
    try {
      snapshotRaw = jsonDecode(snapshotFile.readAsStringSync());
    } catch (e) {
      return _abort(mode: mode, reason: 'Failed to parse snapshot JSON: $e');
    }
    if (snapshotRaw is! Map) {
      return _abort(mode: mode, reason: 'Snapshot root must be a JSON object.');
    }
    final release4Rows = {
      for (final e in snapshotRaw.entries)
        e.key as String: (e.value as List).cast<Map<String, dynamic>>(),
    };
    final release4Docs = CatalogueContract.encode(release4Rows);
    if (!SystemCatalogueSnapshot.requiredCollections.every(
      release4Docs.containsKey,
    )) {
      return _abort(
        mode: mode,
        reason: 'Release 4 snapshot is missing required collections.',
      );
    }
    final compiledSnapshot = SystemCatalogueMetadata.compile(release4Docs);
    final rawSnapshot = CatalogueContract.decode(compiledSnapshot);
    final snapshotReleases = rawSnapshot['product_catalogue_releases']!
        .where((r) => CatalogueContract.active(r) && r['published'] != false)
        .toList();
    if (snapshotReleases.length != 1) {
      return _abort(
        mode: mode,
        reason: 'Release 4 snapshot must have exactly one active published release.',
      );
    }
    final candidateRelease = snapshotReleases.single;
    if (CatalogueContract.version(candidateRelease) != 4 ||
        candidateRelease['schemaRevision'] != 1 ||
        candidateRelease['compilerRevision'] != 6 ||
        candidateRelease['catalogueId'] != 'PAINT_V1') {
      return _abort(
        mode: mode,
        reason:
            'Unsupported catalogue/version combination: ${candidateRelease['catalogueId']} v${candidateRelease['version']} rev${candidateRelease['compilerRevision']}',
      );
    }
    final contentFingerprint = CatalogueContract.fingerprint(compiledSnapshot);
    final calculatedInstalledDocs = <String, List<Map<String, dynamic>>>{
      for (final entry in compiledSnapshot.entries)
        entry.key: [
          for (final document in entry.value)
            if (entry.key == 'product_catalogue_releases')
              {
                ...document,
                'fields': FirestoreValueCodec.encodeFields({
                  ...FirestoreValueCodec.decodeFields(document['fields']),
                  'contentFingerprint': contentFingerprint,
                  'installed': true,
                }),
              }
            else
              document,
        ],
    };
    final calculatedReleaseFingerprint = CatalogueFingerprint.calculate(
      calculatedInstalledDocs,
    );
    if (calculatedReleaseFingerprint != options.releaseFingerprint) {
      return _abort(
        mode: mode,
        reason:
            'Release artifact fingerprint mismatch: expected ${options.releaseFingerprint} but computed $calculatedReleaseFingerprint',
      );
    }
    _log(
      'Release 4 artifact fingerprint verified: $calculatedReleaseFingerprint',
    );

    // Read-only pre-flight inspection of target database
    sqfliteFfiInit();
    final Database roDb;
    try {
      roDb = await databaseFactoryFfi.openDatabase(
        options.databasePath,
        options: OpenDatabaseOptions(readOnly: true),
      );
    } catch (e) {
      return _abort(
        mode: mode,
        reason: 'Could not open source database read-only: $e',
      );
    }
    final List<Map<String, Object?>> queryOnlyResult;
    final List<Map<String, Object?>> roIntegrity;
    try {
      await roDb.execute('PRAGMA query_only=ON;');
      queryOnlyResult = await roDb.rawQuery('PRAGMA query_only;');
      roIntegrity = await roDb.rawQuery('PRAGMA integrity_check;');
    } catch (e) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason: 'Read-only query_only/integrity inspection failed: $e',
      );
    }
    if (queryOnlyResult.isEmpty || queryOnlyResult.first['query_only'] != 1) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason: 'Could not enable query_only for the source database.',
      );
    }
    if (roIntegrity.isEmpty || roIntegrity.first['integrity_check'] != 'ok') {
      await roDb.close();
      return _abort(
        mode: mode,
        reason: 'Source database failed integrity_check: $roIntegrity',
      );
    }
    final userVersionResult = await roDb.rawQuery('PRAGMA user_version;');
    final schemaVersion = userVersionResult.first['user_version'] as int? ?? 0;
    if (schemaVersion != 3 && schemaVersion != 4) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Unsupported schema version: expected user_version=3 or the verified v4/R3 preimage, found $schemaVersion',
      );
    }

    final schemaRows = await roDb.rawQuery(
      'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
    );
    final schemaFingerprint = computeSchemaFingerprint(schemaRows);
    final activeReleaseRows = await roDb.query(
      LocalDataSource.table('product_catalogue_releases'),
      where: "scopeType='SYSTEM' AND isDeleted=0",
    );
    final activeReleases = activeReleaseRows
        .map(
          (row) => FirestoreValueCodec.decodeFields(
            jsonDecode(row['payloadJson'] as String),
          ),
        )
        .where(CatalogueContract.active)
        .toList();
    if (activeReleases.length != 1) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Expected exactly one active SYSTEM catalogue release, found ${activeReleases.length}.',
      );
    }
    final activeReleasePayload = activeReleases.single;
    final activeVersion = CatalogueContract.version(activeReleasePayload);
    final activeReleaseFingerprint =
        activeReleasePayload['catalogueFingerprint'] as String?;

    if (activeVersion == 4 &&
        activeReleaseFingerprint == options.releaseFingerprint) {
      if (activeReleasePayload['catalogueId'] != 'PAINT_V1' ||
          activeReleasePayload['schemaRevision'] != 1 ||
          activeReleasePayload['compilerRevision'] != 6 ||
          activeReleasePayload['installed'] != true) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Release 4 marker does not match the installed PAINT_V1 schema/compiler contract.',
        );
      }
      final archiveTableRows = await roDb.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [CatalogueArchiveStore.table],
      );
      final archiveCountRows = archiveTableRows.isEmpty
          ? const <Map<String, Object?>>[]
          : await roDb.rawQuery(
              'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
            );
      final archiveCount = archiveCountRows.isEmpty
          ? -1
          : archiveCountRows.single['count'] as int;
      final pCount = (await roDb.query(LocalDataSource.table('products')))
          .length;
      final vCount = (await roDb.query(
        LocalDataSource.table('product_variants'),
      )).length;
      final qRows = await roDb.query('sync_queries', orderBy: 'queryKey');
      final qCount = qRows.length;
      final protCount = qRows
          .where((row) => protectedQueryKeys.contains(row['queryKey']))
          .length;
      final outboxCount =
          (await roDb.rawQuery('SELECT COUNT(*) AS count FROM sync_outbox'))
                  .single['count']
              as int;
      if (schemaFingerprint != verifiedV4SchemaFingerprint ||
          archiveTableRows.isEmpty ||
          _normalizeSchemaSql(archiveTableRows.single['sql'] as String) !=
              _verifiedV4ArchiveSql ||
          archiveCount != options.expectedLegacyRows ||
          pCount != options.expectedProducts ||
          vCount != options.expectedVariants ||
          qCount != options.expectedQueries ||
          protCount != options.expectedProtectedQueries ||
          outboxCount != options.expectedOutbox) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Release 4 is present, but the installed schema/archive/business-state contract is not recognized; refusing no-op classification.',
        );
      }
      await roDb.close();
      _log('Release 4 is ALREADY INSTALLED with matching fingerprint.');
      return ProductionMigrationResult(
        mode: mode,
        result: 'ALREADY_INSTALLED',
        success: true,
        sourceHashes: _sourceHashes(currentSha, currentSha, publicConfigSha),
        backupHashes: _backupHashes(options.backupPath, backupSha),
        releaseFingerprint: options.releaseFingerprint,
        preimageCounts: {
          'products': pCount,
          'variants': vCount,
          'syncQueries': qCount,
          'protectedQueries': protCount,
          'outbox': outboxCount,
          'archiveRows': archiveCount,
        },
        postimageCounts: {
          'products': pCount,
          'variants': vCount,
          'syncQueries': qCount,
          'protectedQueries': protCount,
          'outbox': outboxCount,
          'archiveRows': archiveCount,
        },
        log: _logLines,
      );
    }

    if (activeVersion != 3) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Unexpected installed catalogue version: expected version=3, found $activeVersion',
      );
    }

    if (schemaVersion == 3 &&
        schemaFingerprint != verifiedV3SchemaFingerprint) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason: 'Schema v3 object fingerprint differs from the explicitly supported v3/R3 preimage.',
      );
    }

    if (schemaVersion == 4) {
      if (options.expectedAccountSha != verifiedV4AccountSha ||
          currentSha != verifiedV4AccountSha ||
          options.publicConfigPath == null ||
          options.expectedPublicConfigSha != verifiedV4PublicConfigSha ||
          publicConfigSha != verifiedV4PublicConfigSha) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Schema v4 is accepted only for the pinned current account/public-config preimage hashes.',
        );
      }
      if (schemaFingerprint != verifiedV4SchemaFingerprint) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Schema v4 object fingerprint differs from the verified v4/R3 schema.',
        );
      }
      final archiveTableRows = await roDb.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [CatalogueArchiveStore.table],
      );
      if (archiveTableRows.length != 1 ||
          _normalizeSchemaSql(archiveTableRows.single['sql'] as String) !=
              _verifiedV4ArchiveSql) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Schema v4 archive table is missing or differs from the exact LocalDatabase v3-to-v4 migration definition.',
        );
      }
      final archiveCount =
          (await roDb.rawQuery(
                'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
              )).single['count']
              as int;
      if (archiveCount != 0) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason:
              'Schema v4/R3 preimage requires an empty catalogue archive; found $archiveCount rows.',
        );
      }
      final hasInstalledRelease4 = activeReleaseRows.any((row) {
        final fields = FirestoreValueCodec.decodeFields(
          jsonDecode(row['payloadJson'] as String),
        );
        final version =
            fields['catalogueVersion'] ??
            fields['releaseVersion'] ??
            fields['version'];
        return version == 4 && fields['installed'] == true;
      });
      if (activeReleasePayload['catalogueId'] != 'PAINT_V1' ||
          activeVersion != 3 ||
          hasInstalledRelease4) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Schema v4 migration source must have exactly the active PAINT_V1 Release 3 marker and no installed Release 4 marker.',
        );
      }

      final publicDb = await databaseFactoryFfi.openDatabase(
        options.publicConfigPath!,
        options: OpenDatabaseOptions(readOnly: true),
      );
      await publicDb.execute('PRAGMA query_only=ON;');
      final publicQueryOnly = await publicDb.rawQuery('PRAGMA query_only;');
      final publicIntegrity = await publicDb.rawQuery(
        'PRAGMA integrity_check;',
      );
      final publicVersion = await publicDb.rawQuery('PRAGMA user_version;');
      final publicSchema = await publicDb.rawQuery(
        'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
      );
      final publicArchiveTable = await publicDb.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        [CatalogueArchiveStore.table],
      );
      final publicArchiveCount = publicArchiveTable.isEmpty
          ? -1
          : (await publicDb.rawQuery(
                  'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
                )).single['count']
                as int;
      final publicReleaseCount =
          (await publicDb.rawQuery(
                'SELECT COUNT(*) AS count FROM ${LocalDataSource.table('product_catalogue_releases')}',
              )).single['count']
              as int;
      final publicContractOk =
          publicQueryOnly.isNotEmpty &&
          publicQueryOnly.single['query_only'] == 1 &&
          publicIntegrity.isNotEmpty &&
          publicIntegrity.first['integrity_check'] == 'ok' &&
          publicVersion.isNotEmpty &&
          publicVersion.single['user_version'] == 4 &&
          computeSchemaFingerprint(publicSchema) ==
              verifiedV4SchemaFingerprint &&
          publicArchiveTable.length == 1 &&
          _normalizeSchemaSql(publicArchiveTable.single['sql'] as String) ==
              _verifiedV4ArchiveSql &&
          publicArchiveCount == 0 &&
          publicReleaseCount == 0;
      await publicDb.close();
      if (!publicContractOk ||
          computeFileSha256(File(options.publicConfigPath!)) !=
              verifiedV4PublicConfigSha ||
          checkSidecars(options.publicConfigPath!).isNotEmpty) {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Public-config database does not match the verified schema-v4/integrity/empty-archive contract.',
        );
      }
      if (options.expectedProducts != 4 ||
          options.expectedVariants != 7 ||
          options.expectedQueries != 195 ||
          options.expectedProtectedQueries != 10 ||
          options.expectedOutbox != 0 ||
          options.expectedLegacyRows != 3903 ||
          options.expectedLegacyFingerprint !=
              'sha256:1557b7d098f0ae5f829853fb798c86152282af67776cbb525063e2055387e74b') {
        await roDb.close();
        return _abort(
          mode: mode,
          reason: 'Schema v4 contract constants differ from the approved production preimage expectations.',
        );
      }
      _log(
        'Verified exact schema-v4/catalogue-v3 preimage contract (pinned hashes, schema fingerprint, empty archive, and public-config integrity).',
      );
    }

    final productsBefore = await roDb.query(
      LocalDataSource.table('products'),
      orderBy: 'remoteId',
    );
    final variantsBefore = await roDb.query(
      LocalDataSource.table('product_variants'),
      orderBy: 'remoteId',
    );
    final queriesBefore = await roDb.query('sync_queries', orderBy: 'queryKey');
    final outboxBefore = await roDb.query('sync_outbox', orderBy: 'id');

    if (productsBefore.length != options.expectedProducts) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Product count mismatch: expected ${options.expectedProducts}, found ${productsBefore.length}',
      );
    }
    if (variantsBefore.length != options.expectedVariants) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Variant count mismatch: expected ${options.expectedVariants}, found ${variantsBefore.length}',
      );
    }
    if (queriesBefore.length != options.expectedQueries) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Sync query count mismatch: expected ${options.expectedQueries}, found ${queriesBefore.length}',
      );
    }
    if (outboxBefore.length != options.expectedOutbox) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Sync outbox count mismatch: expected ${options.expectedOutbox}, found ${outboxBefore.length}',
      );
    }

    final protectedBefore = queriesBefore
        .where((row) => protectedQueryKeys.contains(row['queryKey']))
        .toList();
    if (protectedBefore.length != options.expectedProtectedQueries) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Protected query count mismatch: expected ${options.expectedProtectedQueries}, found ${protectedBefore.length}',
      );
    }

    // Derive legacy catalogue fingerprint from installed SYSTEM rows
    final legacyDocs = <String, List<Map<String, dynamic>>>{};
    const fingerprintCollections = {
      ...CatalogueArchiveStore.collections,
      'brands',
    };
    var totalEligibleLegacyRows = 0;
    for (final collection in fingerprintCollections) {
      final rows = await roDb.query(
        LocalDataSource.table(collection),
        where: "scopeType='SYSTEM' AND isDeleted=0",
        orderBy: 'remoteId',
      );
      if (CatalogueArchiveStore.collections.contains(collection)) {
        totalEligibleLegacyRows += rows.length;
      }
      legacyDocs[collection] = [
        for (final row in rows)
          {
            'name': '$collection/${row['remoteId']}',
            'fields': jsonDecode(row['payloadJson'] as String),
          },
      ];
    }
    final legacyFingerprint = CatalogueFingerprint.calculate(legacyDocs);
    if (legacyFingerprint != options.expectedLegacyFingerprint) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Legacy catalogue fingerprint mismatch: expected ${options.expectedLegacyFingerprint}, found $legacyFingerprint',
      );
    }
    if (totalEligibleLegacyRows != options.expectedLegacyRows) {
      await roDb.close();
      return _abort(
        mode: mode,
        reason:
            'Legacy SYSTEM rows eligible for archive mismatch: expected ${options.expectedLegacyRows}, found $totalEligibleLegacyRows',
      );
    }

    final queryDigestBefore = computeDigest(queriesBefore);
    _log('Preimage inspection successful:');
    _log('  Products: ${productsBefore.length}');
    _log('  Variants: ${variantsBefore.length}');
    _log(
      '  Sync queries: ${queriesBefore.length} (digest: $queryDigestBefore)',
    );
    _log('  Protected queries: ${protectedBefore.length}');
    _log(
      '  Legacy fingerprint: $legacyFingerprint ($totalEligibleLegacyRows rows)',
    );
    await roDb.close();

    final sidecarsAfterInspection = checkSidecars(options.databasePath);
    if (sidecarsAfterInspection.isNotEmpty) {
      return _abort(
        mode: mode,
        reason:
            'SQLite sidecars appeared during read-only inspection: $sidecarsAfterInspection',
      );
    }
    final postShaBeforeAction = computeFileSha256(sourceFile);
    if (postShaBeforeAction != options.expectedAccountSha) {
      return _abort(
        mode: mode,
        reason: 'Database file was modified during read-only inspection.',
      );
    }

    // Dry-run mode: report planned actions and GO decision
    if (!options.execute) {
      _log('=== DRY-RUN EVALUATION: GO ===');
      _log('Planned write actions:');
      _log(
        '  1. Archive $totalEligibleLegacyRows legacy SYSTEM rows under $legacyFingerprint.',
      );
      _log(
        '  2. Import Release 4 snapshot under $calculatedReleaseFingerprint.',
      );
      _log(
        '  3. Preserve all 195 sync queries unchanged (digest: $queryDigestBefore).',
      );
      _log('  4. Preserve all 4 Products and 7 Variants unchanged.');
      _log('  5. Activate 137 canonical selectors and 137 READY forms.');
      _log('  6. Zero Firestore or network calls.');
      _log('Zero writes performed. Preimage SHA-256 untouched.');

      final result = ProductionMigrationResult(
        mode: 'DRY_RUN',
        result: 'GO',
        success: true,
        sourceHashes: _sourceHashes(
          currentSha,
          postShaBeforeAction,
          publicConfigSha,
        ),
        backupHashes: _backupHashes(options.backupPath, backupSha),
        releaseFingerprint: options.releaseFingerprint,
        legacyFingerprint: legacyFingerprint,
        preimageCounts: {
          'products': productsBefore.length,
          'variants': variantsBefore.length,
          'syncQueries': queriesBefore.length,
          'protectedQueries': protectedBefore.length,
          'outbox': outboxBefore.length,
          'systemRowsEligibleForArchive': totalEligibleLegacyRows,
        },
        postimageCounts: {
          'expectedProducts': productsBefore.length,
          'expectedVariants': variantsBefore.length,
          'expectedSyncQueries': queriesBefore.length,
          'expectedProtectedQueries': protectedBefore.length,
          'expectedSelectors': 137,
          'expectedReadyForms': 137,
          'expectedArchiveRows': totalEligibleLegacyRows,
        },
        queryDigestBefore: queryDigestBefore,
        queryDigestAfter: queryDigestBefore,
        archiveCount: totalEligibleLegacyRows,
        log: _logLines,
      );
      _writeReport(result);
      return result;
    }

    // EXECUTE MODE: Apply schema and snapshot in a controlled transaction
    _log('=== EXECUTE MODE: INITIATING CONTROLLED WRITABLE TRANSACTION ===');
    _log('Maintenance mode acknowledged: ${options.maintenanceAck}');
    _log('Verified backup present: ${options.backupPath}');

    final writeDb = await databaseFactoryFfi.openDatabase(options.databasePath);
    final source = LocalDataSource(writeDb);

    try {
      await writeDb.transaction((tx) async {
        _log('[TX 1/6] In-transaction preimage verification...');
        final inTxProducts = await tx.query(
          LocalDataSource.table('products'),
          orderBy: 'remoteId',
        );
        final inTxVariants = await tx.query(
          LocalDataSource.table('product_variants'),
          orderBy: 'remoteId',
        );
        final inTxQueries = await tx.query('sync_queries', orderBy: 'queryKey');
        final inTxOutbox = await tx.query('sync_outbox', orderBy: 'id');
        final inTxReleaseRows = await tx.query(
          LocalDataSource.table('product_catalogue_releases'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        if (stableRows(inTxProducts) != stableRows(productsBefore) ||
            stableRows(inTxVariants) != stableRows(variantsBefore) ||
            stableRows(inTxQueries) != stableRows(queriesBefore) ||
            stableRows(inTxOutbox) != stableRows(outboxBefore) ||
            stableRows(inTxReleaseRows) != stableRows(activeReleaseRows)) {
          throw const AppException(
            'In-transaction Product, Variant, query, outbox, or release-marker preimage differs from read-only inspection; aborting.',
          );
        }

        _log(
          '[TX 2/6] Applying schema migration and preparing archive store...',
        );
        if (schemaVersion == 3) {
          await CatalogueArchiveStore.createSchema(tx);
        } else {
          final archiveRowsInTx = await tx.rawQuery(
            'SELECT COUNT(*) AS count FROM ${CatalogueArchiveStore.table}',
          );
          if ((archiveRowsInTx.single['count'] as int) != 0) {
            throw const AppException(
              'Verified schema-v4/R3 preimage archive became non-empty before the migration transaction.',
            );
          }
          _log(
            'Verified schema-v4 archive table already exists; skipping CREATE TABLE.',
          );
        }
        final transactionSchema = await tx.rawQuery(
          'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
        );
        if (computeSchemaFingerprint(transactionSchema) !=
            verifiedV4SchemaFingerprint) {
          throw const AppException(
            'Migration schema objects do not match the exact expected v4 definition.',
          );
        }

        _log(
          '[TX 3/6] Applying Release 4 snapshot with query preservation and archiving ($legacyFingerprint)...',
        );
        await SystemCatalogueSnapshot.import(
          source: source,
          documents: release4Docs,
          readTimes: const {},
          preserveSyncQueries: true,
          executor: tx,
          failureProbe: failureProbe,
        );

        _log('[TX 4/6] Verifying in-transaction invariants...');
        final postTxArchive = await tx.query(
          CatalogueArchiveStore.table,
          where: 'catalogueFingerprint=?',
          whereArgs: [legacyFingerprint],
        );
        if (postTxArchive.length != totalEligibleLegacyRows) {
          throw AppException(
            'In-transaction archive count mismatch: expected $totalEligibleLegacyRows, found ${postTxArchive.length}',
          );
        }

        final postTxProducts = await tx.query(
          LocalDataSource.table('products'),
          orderBy: 'remoteId',
        );
        final postTxVariants = await tx.query(
          LocalDataSource.table('product_variants'),
          orderBy: 'remoteId',
        );
        final postTxQueries = await tx.query(
          'sync_queries',
          orderBy: 'queryKey',
        );
        final postTxOutbox = await tx.query('sync_outbox', orderBy: 'id');

        if (stableRows(postTxProducts) != stableRows(productsBefore)) {
          throw const AppException(
            'In-transaction Product rows were mutated; rolling back.',
          );
        }
        if (stableRows(postTxVariants) != stableRows(variantsBefore)) {
          throw const AppException(
            'In-transaction Variant rows were mutated; rolling back.',
          );
        }
        if (stableRows(postTxQueries) != stableRows(queriesBefore)) {
          throw const AppException(
            'In-transaction Sync Query rows were mutated; rolling back.',
          );
        }
        if (postTxOutbox.isNotEmpty) {
          throw const AppException(
            'In-transaction Outbox rows were created; rolling back.',
          );
        }

        _log('[TX 5/6] In-transaction Release 4 marker check...');
        final releaseCheck = await tx.query(
          LocalDataSource.table('product_catalogue_releases'),
          where: "scopeType='SYSTEM' AND isDeleted=0",
        );
        final activeCheck = releaseCheck
            .map(
              (r) => FirestoreValueCodec.decodeFields(
                jsonDecode(r['payloadJson'] as String),
              ),
            )
            .where(CatalogueContract.active)
            .single;
        if (CatalogueContract.version(activeCheck) != 4 ||
            activeCheck['catalogueFingerprint'] != options.releaseFingerprint) {
          throw const AppException(
            'In-transaction Release 4 marker mismatch; rolling back.',
          );
        }

        await failureProbe?.call('before_commit', tx);

        _log('[TX 6/6] Invariants satisfied. Committing transaction.');
      });
    } catch (e) {
      await writeDb.close();
      _log('TRANSACTION ROLLED BACK: $e');
      return _abort(
        mode: mode,
        reason: 'Transaction rolled back due to error: $e',
      );
    }

    _log(
      'Transaction committed successfully. Running post-commit verification...',
    );

    // Post-commit independent verification
    final postIntegrity = await writeDb.rawQuery('PRAGMA integrity_check;');
    if (postIntegrity.isEmpty ||
        postIntegrity.first['integrity_check'] != 'ok') {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit PRAGMA integrity_check failed: $postIntegrity',
        isRollbackRequired: true,
      );
    }

    final postProducts = await writeDb.query(
      LocalDataSource.table('products'),
      orderBy: 'remoteId',
    );
    final postVariants = await writeDb.query(
      LocalDataSource.table('product_variants'),
      orderBy: 'remoteId',
    );
    final postQueries = await writeDb.query(
      'sync_queries',
      orderBy: 'queryKey',
    );
    final postOutbox = await writeDb.query('sync_outbox', orderBy: 'id');

    if (stableRows(postProducts) != stableRows(productsBefore)) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit verification: Product rows do not match preimage.',
        isRollbackRequired: true,
      );
    }
    if (stableRows(postVariants) != stableRows(variantsBefore)) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit verification: Variant rows do not match preimage.',
        isRollbackRequired: true,
      );
    }
    if (stableRows(postQueries) != stableRows(queriesBefore)) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit verification: Sync queries do not match preimage.',
        isRollbackRequired: true,
      );
    }
    if (postOutbox.isNotEmpty) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit verification: Outbox contains non-zero rows.',
        isRollbackRequired: true,
      );
    }

    final postProtected = postQueries
        .where((row) => protectedQueryKeys.contains(row['queryKey']))
        .toList();
    if (stableRows(postProtected) != stableRows(protectedBefore)) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason: 'Post-commit verification: 10 protected queries were mutated.',
        isRollbackRequired: true,
      );
    }

    // Verify 137 canonical selectors and 137 READY forms
    final localReader = MigrationReadOnlyCatalogueService(source);
    final selectionResolver = CatalogueSelectionResolver(localReader);
    final templateResolver = ProductTemplateResolver(localReader);

    final categories = (await writeDb.query(
      LocalDataSource.table('product_categories'),
      where: "scopeType='SYSTEM' AND isDeleted=0",
    )).map((r) => r['remoteId'] as String).toList();

    final actualSelectors = <String>{};
    for (final cat in categories) {
      final eligible = await selectionResolver.getEligibleSubcategories(
        tenantId: 'T',
        businessId: 'B',
        categoryId: cat,
        token: 'LOCAL_ONLY',
      );
      actualSelectors.addAll(eligible.map((r) => r.id));
    }

    if (actualSelectors.length != 137) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason:
            'Post-commit verification: expected 137 selectors, found ${actualSelectors.length}',
        isRollbackRequired: true,
      );
    }

    var readyForms = 0;
    for (final subId in actualSelectors) {
      final template = await templateResolver.resolveTemplate(
        tenantId: 'T',
        businessId: 'B',
        subcategoryId: subId,
        token: 'LOCAL_ONLY',
      );
      if (template.readiness != TemplateReadinessState.ready) {
        await writeDb.close();
        return _abort(
          mode: mode,
          reason:
              'Post-commit verification: template $subId readiness is ${template.readiness}',
          isRollbackRequired: true,
        );
      }
      if (!template.allAttributes.any((a) => a.attributeId == 'unit')) {
        await writeDb.close();
        return _abort(
          mode: mode,
          reason:
              'Post-commit verification: template $subId missing unit attribute',
          isRollbackRequired: true,
        );
      }
      readyForms++;
    }
    if (readyForms != 137) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason:
            'Post-commit verification: expected 137 READY forms, found $readyForms',
        isRollbackRequired: true,
      );
    }

    // Verify archive count and digest
    final archivedRows = await writeDb.query(
      CatalogueArchiveStore.table,
      where: 'catalogueFingerprint=?',
      whereArgs: [legacyFingerprint],
      orderBy: 'collection, documentId',
    );
    if (archivedRows.length != totalEligibleLegacyRows) {
      await writeDb.close();
      return _abort(
        mode: mode,
        reason:
            'Post-commit verification: archived rows count mismatch: expected $totalEligibleLegacyRows, found ${archivedRows.length}',
        isRollbackRequired: true,
      );
    }
    final archiveDigest = computeDigest(archivedRows);

    // Verify historical null provenance still fail-closed
    final historicalResolver = HistoricalCatalogueResolver(writeDb);
    for (final prod in postProducts) {
      final fields = FirestoreValueCodec.decodeFields(
        jsonDecode(prod['payloadJson'] as String),
      );
      if (fields['catalogueFingerprint'] == null) {
        final resolution = await historicalResolver.resolveProduct(
          fields,
          context: CatalogueResolutionContext.historical,
        );
        if (resolution.status != CatalogueResolutionStatus.provenanceMissing) {
          await writeDb.close();
          return _abort(
            mode: mode,
            reason:
                'Historical product ${prod['remoteId']} without fingerprint did not fail-closed: ${resolution.status}',
            isRollbackRequired: true,
          );
        }
      }
    }

    await writeDb.close();
    final postimageSha = computeFileSha256(sourceFile);
    final postimageSidecars = checkSidecars(options.databasePath);
    if (postimageSidecars.isNotEmpty) {
      return _abort(
        mode: mode,
        reason: 'Post-migration sidecars detected: $postimageSidecars',
        isRollbackRequired: true,
      );
    }

    _log('=== EXECUTION SUCCESSFUL ===');
    _log('Postimage SHA-256: $postimageSha');
    _log('Archive count: ${archivedRows.length} (digest: $archiveDigest)');
    _log('Query digest before: $queryDigestBefore');
    _log('Query digest after:  $queryDigestBefore');
    _log('Selectors verified: 137/137');
    _log('READY forms verified: 137/137');
    _log('Products preserved: 4/4');
    _log('Variants preserved: 7/7');
    _log('Sync queries preserved: 195/195 (protected: 10/10)');

    final result = ProductionMigrationResult(
      mode: 'EXECUTE',
      result: 'SUCCESS',
      success: true,
      sourceHashes: _sourceHashes(currentSha, postimageSha, publicConfigSha),
      backupHashes: _backupHashes(options.backupPath, backupSha),
      releaseFingerprint: options.releaseFingerprint,
      legacyFingerprint: legacyFingerprint,
      preimageCounts: {
        'products': productsBefore.length,
        'variants': variantsBefore.length,
        'syncQueries': queriesBefore.length,
        'protectedQueries': protectedBefore.length,
        'outbox': outboxBefore.length,
        'systemRowsEligibleForArchive': totalEligibleLegacyRows,
      },
      postimageCounts: {
        'products': postProducts.length,
        'variants': postVariants.length,
        'syncQueries': postQueries.length,
        'protectedQueries': postProtected.length,
        'selectors': actualSelectors.length,
        'readyForms': readyForms,
        'archivedRows': archivedRows.length,
      },
      queryDigestBefore: queryDigestBefore,
      queryDigestAfter: queryDigestBefore,
      archiveCount: archivedRows.length,
      archiveDigest: archiveDigest,
      log: _logLines,
    );

    _writeReport(result);
    return result;
  }

  ProductionMigrationResult _abort({
    required String mode,
    required String reason,
    bool isRollbackRequired = false,
  }) {
    final status = isRollbackRequired ? 'ROLLBACK_REQUIRED' : 'ABORTED';
    _log('ABORT [$status]: $reason');
    final result = ProductionMigrationResult(
      mode: mode,
      result: status,
      success: false,
      sourceHashes: {'accountPreimageSha': options.expectedAccountSha},
      backupHashes: _backupHashes(options.backupPath, null),
      releaseFingerprint: options.releaseFingerprint,
      abortReason: reason,
      log: _logLines,
    );
    _writeReport(result);
    return result;
  }

  void _writeReport(ProductionMigrationResult result) {
    if (options.reportFilePath != null) {
      final file = File(options.reportFilePath!);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    }
    if (options.jsonOutput) {
      // ignore: avoid_print
      print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
    }
  }
}

Future<void> runProductionMigration(List<String> args) async {
  try {
    final options = ProductionMigrationOptions.fromArgs(args);
    final runner = ProductionMigrationRunner(options);
    final result = await runner.run();
    exit(result.success ? 0 : 1);
  } on AppException catch (e) {
    stderr.writeln('Migration runner configuration error: ${e.message}');
    exit(1);
  } catch (e, stack) {
    stderr.writeln('Unexpected migration runner exception: $e\n$stack');
    exit(1);
  }
}
