@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/migration/production_migration_runner.dart';

const _fixtureDirectoryEnvironment = 'NUBIBILL_PHASE10N4_FIXTURE_DIR';

String _flutterDartExecutable() {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate =
        '${directory.path}${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName';
    if (File(candidate).existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }

  final configuredRoot = Platform.environment['FLUTTER_ROOT'];
  if (configuredRoot != null && configuredRoot.isNotEmpty) {
    final candidate =
        '$configuredRoot${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}$executableName';
    if (File(candidate).existsSync()) return candidate;
  }
  throw StateError(
    'Could not locate the Dart SDK bundled with the active Flutter test runner.',
  );
}

String get _approvedFixtureDirectory {
  final value = Platform.environment[_fixtureDirectoryEnvironment]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      'Set $_fixtureDirectoryEnvironment to a read-only directory containing '
      'the approved account-production.db and public-config-production.db '
      'source images. Tests copy them into disposable temporary databases.',
    );
  }
  return value;
}

Future<ProcessResult> _runMigrationRunner(List<String> arguments) =>
    Process.run(_flutterDartExecutable(), [
      'run',
      'bin/production_migration_runner.dart',
      ...arguments,
    ], workingDirectory: Directory.current.path);

void main() {
  sqfliteFfiInit();

  String computeSha256(File f) {
    return sha256.convert(f.readAsBytesSync()).toString();
  }

  Future<Map<String, String>> createDisposableClone() async {
    final dir = await Directory.systemTemp.createTemp('phase10n4_cli_test_');
    final account = '${dir.path}/account.db';
    final publicConfig = '${dir.path}/public-config.db';
    final backup = '${dir.path}/account.db.bak';
    final fixtureRoot = _approvedFixtureDirectory;
    final approvedAccountBackup =
        '$fixtureRoot${Platform.pathSeparator}account-production.db';
    final approvedPublicConfigBackup =
        '$fixtureRoot${Platform.pathSeparator}public-config-production.db';

    if (!File(approvedAccountBackup).existsSync() ||
        !File(approvedPublicConfigBackup).existsSync()) {
      throw StateError(
        'The approved Phase 10N4 account/public-config fixture pair is missing '
        'from $_fixtureDirectoryEnvironment=$fixtureRoot.',
      );
    }

    File(approvedAccountBackup).copySync(account);
    File(approvedPublicConfigBackup).copySync(publicConfig);
    File(account).copySync(backup);

    expect(
      computeSha256(File(account)),
      ProductionMigrationRunner.verifiedV4AccountSha,
    );
    expect(
      computeSha256(File(publicConfig)),
      ProductionMigrationRunner.verifiedV4PublicConfigSha,
    );

    return {
      'directory': dir.path,
      'account': account,
      'publicConfig': publicConfig,
      'backup': backup,
    };
  }

  group(
    'Phase 10N4: Production Migration Runner CLI Execution and Contract',
    () {
      test('disposable dry-run via CLI executes successfully with exit code 0 and valid JSON', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        final accountFile = File(fixture['account']!);
        final beforeSha = computeSha256(accountFile);

        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          beforeSha,
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          beforeSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          ProductionMigrationRunner.verifiedV4PublicConfigSha,
          '--json',
        ]);

        expect(
          result.exitCode,
          0,
          reason: 'CLI stdout: ${result.stdout}\nCLI stderr: ${result.stderr}',
        );

        // Verify stdout contains valid JSON output
        final stdout = (result.stdout as String).trim();
        final jsonStart = stdout.indexOf('{');
        expect(
          jsonStart,
          isNonNegative,
          reason: 'No JSON object found in stdout: $stdout',
        );
        final jsonString = stdout.substring(jsonStart);
        final dynamic decoded = jsonDecode(jsonString);

        expect(decoded, isA<Map<String, dynamic>>());
        final map = decoded as Map<String, dynamic>;
        expect(map['mode'], 'DRY_RUN');
        expect(map['result'], 'GO');
        expect(map['success'], isTrue);
        expect(
          map['releaseFingerprint'],
          'sha256:cfc96ca97f343ea5593813e28cc38a22c85fbd1d5c1e3d52d4fdfa52f5bb1f88',
        );
        expect(map['preimageCounts']['products'], 4);
        expect(map['preimageCounts']['variants'], 7);
        expect(map['preimageCounts']['syncQueries'], 195);
        expect(map['preimageCounts']['protectedQueries'], 10);
        expect(map['preimageCounts']['outbox'], 0);

        // Verify zero writes occurred
        final afterSha = computeSha256(accountFile);
        expect(
          afterSha,
          beforeSha,
          reason: 'Dry-run must not modify the database file',
        );

        // Verify no SQLite sidecars remain
        expect(
          ProductionMigrationRunner.checkSidecars(fixture['account']!),
          isEmpty,
        );
      });

      test('missing required arguments causes non-zero exit', () async {
        final result = await _runMigrationRunner(['--json']);

        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('--database'));
      });

      test('wrong account SHA causes non-zero exit', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          '0000000000000000000000000000000000000000000000000000000000000000',
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          ProductionMigrationRunner.verifiedV4PublicConfigSha,
          '--json',
        ]);

        expect(result.exitCode, isNot(0));
      });

      test('wrong public-config SHA causes non-zero exit', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          '0000000000000000000000000000000000000000000000000000000000000000',
          '--json',
        ]);

        expect(result.exitCode, isNot(0));
      });

      test('wrong release fingerprint causes non-zero exit', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--release-fingerprint',
          'sha256:0000000000000000000000000000000000000000000000000000000000000000',
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          ProductionMigrationRunner.verifiedV4PublicConfigSha,
          '--json',
        ]);

        expect(result.exitCode, isNot(0));
      });

      test('unknown/corrupted schema causes non-zero exit', () async {
        final dir = await Directory.systemTemp.createTemp('phase10n4_corrupt_');
        addTearDown(() async {
          if (dir.existsSync()) await dir.delete(recursive: true);
        });
        final corruptDb = '${dir.path}/corrupt.db';
        File(corruptDb).writeAsStringSync('NOT A VALID SQLITE DATABASE');
        final corruptSha = computeSha256(File(corruptDb));

        final result = await _runMigrationRunner([
          '--database',
          corruptDb,
          '--expected-account-sha',
          corruptSha,
          '--json',
        ]);

        expect(result.exitCode, isNot(0));
      });

      test('sidecar present causes non-zero exit', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        // Create an active sidecar file
        File('${fixture['account']}-wal').writeAsStringSync('active wal');

        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          ProductionMigrationRunner.verifiedV4AccountSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          ProductionMigrationRunner.verifiedV4PublicConfigSha,
          '--json',
        ]);

        expect(result.exitCode, isNot(0));
      });

      test('default invocation without --execute is strictly read-only and never writes', () async {
        final fixture = await createDisposableClone();
        addTearDown(() async {
          final dir = Directory(fixture['directory']!);
          if (dir.existsSync()) await dir.delete(recursive: true);
        });

        final accountFile = File(fixture['account']!);
        final beforeSha = computeSha256(accountFile);

        // Invoke without --execute
        final result = await _runMigrationRunner([
          '--database',
          fixture['account']!,
          '--expected-account-sha',
          beforeSha,
          '--backup',
          fixture['backup']!,
          '--expected-backup-sha',
          beforeSha,
          '--public-config',
          fixture['publicConfig']!,
          '--expected-public-config-sha',
          ProductionMigrationRunner.verifiedV4PublicConfigSha,
        ]);

        expect(result.exitCode, 0);
        expect(result.stdout.toString(), contains('Mode: DRY_RUN'));
        expect(result.stdout.toString(), contains('Zero writes performed.'));

        // Strict byte-for-byte SHA equality
        final afterSha = computeSha256(accountFile);
        expect(afterSha, beforeSha);
      });

      test(
        'invalid invocation must never silently fall back to execution',
        () async {
          final fixture = await createDisposableClone();
          addTearDown(() async {
            final dir = Directory(fixture['directory']!);
            if (dir.existsSync()) await dir.delete(recursive: true);
          });

          final accountFile = File(fixture['account']!);
          final beforeSha = computeSha256(accountFile);

          // Invalid option argument
          final result = await _runMigrationRunner([
            '--database',
            fixture['account']!,
            '--expected-account-sha',
            'invalid_sha',
            '--execute', // Even with --execute, validation failure must exit non-zero
            '--maintenance-ack',
          ]);

          expect(result.exitCode, isNot(0));
          // Must not have written anything
          final afterSha = computeSha256(accountFile);
          expect(afterSha, beforeSha);
        },
      );
    },
  );
}
